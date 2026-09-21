/*
 * glp_client.c —— 客户端运行时实现（glibc，在 chroot 里跑）
 *
 * 关键设计：**流水线**。
 * 实测同步往返 34.8µs/次，而 Chrome 每帧要发上千条 GL 调用 —— 每条都等回包不可能。
 * 所以：不需要返回值的调用（draw/bind/uniform/vertexAttribPointer …）只往写缓冲里
 * 追加（一次 memcpy），攒够 256KB 或遇到需要回包的调用才真正 write() 出去。
 */
#define _GNU_SOURCE
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "glp_client.h"

static int g_fd = -1;
static int g_warned = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned char g_wbuf[GLP_WBUF_SIZE];
static uint32_t g_wlen = 0;
static unsigned char g_rbuf[GLP_MAX_BLOB];
static char g_strbuf[8192];
static uint32_t g_strlen_last = 0;
static uint32_t g_rblob_len = 0;

static const char *sock_path(void) {
    const char *p = getenv("GLPROXY_SOCK");
    return (p && *p) ? p : GLP_DEFAULT_SOCK;
}

static int wfull(int fd, const void *b, size_t n) {
    const char *p = (const char *)b; size_t off = 0;
    while (off < n) { ssize_t w = write(fd, p + off, n - off); if (w <= 0) return -1; off += (size_t)w; }
    return 0;
}
static int rfull(int fd, void *b, size_t n) {
    char *p = (char *)b; size_t off = 0;
    while (off < n) { ssize_t r = read(fd, p + off, n - off); if (r <= 0) return -1; off += (size_t)r; }
    return 0;
}

int glp_conn(void) {
    if (g_fd >= 0) return g_fd;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof sa.sun_path, "%s", sock_path());
    if (connect(fd, (struct sockaddr *)&sa, sizeof sa) != 0) {
        if (!g_warned) { fprintf(stderr, "glproxy: 连不上 %s: %s（GPU 加速不可用，将退化为软件渲染）\n",
                                 sa.sun_path, strerror(errno)); g_warned = 1; }
        close(fd);
        return -1;
    }
    g_fd = fd;
    fprintf(stderr, "glproxy: 已连上 %s\n", sa.sun_path);
    return fd;
}

/* ------------------------------------------------------------------ 写缓冲（流水线） */

static int wbuf_flush_locked(void) {
    if (!g_wlen) return 0;
    if (glp_conn() < 0) { g_wlen = 0; return -1; }
    if (wfull(g_fd, g_wbuf, g_wlen) != 0) { g_fd = -1; g_wlen = 0; return -1; }
    g_wlen = 0;
    return 0;
}

void glp_void(uint16_t op, uint16_t argc, const uint64_t *args, const void *bin, uint32_t blen) {
    uint32_t need = (uint32_t)sizeof(struct glp_req) + blen;
    pthread_mutex_lock(&g_lock);
    if (need > GLP_WBUF_SIZE) {                         /* 单条就超过整个缓冲：直接发 */
        wbuf_flush_locked();
        struct glp_req q; memset(&q, 0, sizeof q);
        q.len = need; q.op = op; q.argc = argc;
        if (args) memcpy(q.args, args, argc * sizeof(uint64_t));
        if (glp_conn() >= 0) { wfull(g_fd, &q, sizeof q); if (blen) wfull(g_fd, bin, blen); }
        pthread_mutex_unlock(&g_lock);
        return;
    }
    if (g_wlen + need > GLP_WBUF_SIZE) wbuf_flush_locked();
    struct glp_req *q = (struct glp_req *)(g_wbuf + g_wlen);
    memset(q, 0, sizeof *q);
    q->len = need; q->op = op; q->argc = argc;
    if (args) memcpy(q->args, args, argc * sizeof(uint64_t));
    if (blen && bin) memcpy(g_wbuf + g_wlen + sizeof *q, bin, blen);
    g_wlen += need;
    pthread_mutex_unlock(&g_lock);
}

int glp_call_sync(uint16_t op, uint16_t argc, const uint64_t *args,
                  const void *bin, uint32_t blen,
                  uint64_t *rets, uint16_t *retc, void *bout, uint32_t *boutlen) {
    pthread_mutex_lock(&g_lock);
    /* 先把流水线里攒的刷出去，保证顺序 */
    if (wbuf_flush_locked() != 0) { pthread_mutex_unlock(&g_lock); return -1; }
    if (glp_conn() < 0) { pthread_mutex_unlock(&g_lock); return -1; }

    struct glp_req q; memset(&q, 0, sizeof q);
    q.len = (uint32_t)(sizeof q + blen); q.op = op; q.argc = argc;
    if (args) memcpy(q.args, args, argc * sizeof(uint64_t));
    if (wfull(g_fd, &q, sizeof q) != 0 || (blen && wfull(g_fd, bin, blen) != 0)) {
        g_fd = -1; pthread_mutex_unlock(&g_lock); return -1;
    }

    struct glp_rsp r;
    if (rfull(g_fd, &r, sizeof r) != 0) { g_fd = -1; pthread_mutex_unlock(&g_lock); return -1; }
    uint32_t rblob = (r.len > sizeof r) ? (r.len - (uint32_t)sizeof r) : 0;
    if (rblob > GLP_MAX_BLOB) { g_fd = -1; pthread_mutex_unlock(&g_lock); return -1; }

    unsigned char *dst = bout ? (unsigned char *)bout : g_rbuf;
    uint32_t cap = bout ? (boutlen ? *boutlen : rblob) : sizeof g_rbuf;
    if (cap > GLP_MAX_BLOB) cap = GLP_MAX_BLOB;
    uint32_t want = rblob < cap ? rblob : cap;
    if (want && rfull(g_fd, dst, want) != 0) { g_fd = -1; pthread_mutex_unlock(&g_lock); return -1; }
    if (want < rblob) {                                  /* 多余的丢掉 */
        unsigned char tmp[4096];
        uint32_t left = rblob - want;
        while (left) { uint32_t n = left > sizeof tmp ? (uint32_t)sizeof tmp : left;
                       if (rfull(g_fd, tmp, n) != 0) { g_fd = -1; pthread_mutex_unlock(&g_lock); return -1; } left -= n; }
    }
    if (!bout && rblob) {                                /* 字符串类：留在 g_rbuf，供 glp_last_string 取 */
        uint32_t n = rblob < sizeof g_strbuf ? rblob : (uint32_t)sizeof g_strbuf - 1;
        memcpy(g_strbuf, g_rbuf, n);
        g_strbuf[n] = 0;
        g_strlen_last = n;
    }
    g_rblob_len = want;
    if (boutlen) *boutlen = rblob;
    if (retc) *retc = r.retc;
    if (rets) memcpy(rets, r.rets, r.retc * sizeof(uint64_t));
    int st = (int)r.status;
    pthread_mutex_unlock(&g_lock);
    return st;
}

const char *glp_last_string(void) { return g_strbuf; }

/* 回复 blob 本体 + 实际长度：多出参的转发桩靠它逐段回拷到调用方的指针 */
const unsigned char *glp_last_blob(void) { return g_rbuf; }
uint32_t glp_last_blob_len(void) { return g_rblob_len; }

/* 还没实现的入口：只记一次日志（迭代时看 Chrome 到底要什么），返回安全值由桩负责 */
void glp_unsupported(const char *name) {
    static const char *seen[64];
    static int nseen = 0;
    for (int i = 0; i < nseen; i++) if (!strcmp(seen[i], name)) return;
    if (nseen < 64) seen[nseen++] = name;
    fprintf(stderr, "glproxy: 未实现入口被调用 → %s\n", name);
}

/* ------------------------------------------------------------------ blob 长度辅助 */

size_t glp_pixels_size(GLsizei w, GLsizei h, GLenum format, GLenum type) {
    int comps = 4;
    switch (format) {
        case GL_ALPHA: case GL_LUMINANCE: case GL_DEPTH_COMPONENT:
        case GL_RED: case GL_RED_INTEGER: case GL_GREEN: case GL_BLUE: comps = 1; break;
        case GL_LUMINANCE_ALPHA: case GL_RG: case GL_RG_INTEGER: comps = 2; break;
        case GL_RGB: case GL_RGB_INTEGER: case GL_SRGB: comps = 3; break;
        default: comps = 4; break;
    }
    int bpc = 1;
    switch (type) {
        case GL_UNSIGNED_BYTE: case GL_BYTE: bpc = 1; break;
        case GL_UNSIGNED_SHORT: case GL_SHORT: case GL_HALF_FLOAT: bpc = 2; break;
        case GL_UNSIGNED_INT: case GL_INT: case GL_FLOAT: case GL_FIXED: bpc = 4; break;
        case GL_UNSIGNED_SHORT_5_6_5: case GL_UNSIGNED_SHORT_4_4_4_4:
        case GL_UNSIGNED_SHORT_5_5_5_1: comps = 1; bpc = 2; break;
        case GL_UNSIGNED_INT_2_10_10_10_REV: case GL_UNSIGNED_INT_24_8: comps = 1; bpc = 4; break;
        default: bpc = 4; break;
    }
    if (w < 0) w = 0;
    if (h < 0) h = 0;
    return (size_t)w * (size_t)h * (size_t)comps * (size_t)bpc;
}

size_t glp_strlen(const char *s) { return s ? strlen(s) + 1 : 0; }

size_t glp_strv_size(GLsizei count, const char *const *v) {
    size_t n = 0;
    if (!v || count <= 0) return 0;
    for (GLsizei i = 0; i < count; i++) n += v[i] ? strlen(v[i]) + 1 : 1;
    return n;
}

/* 只回**确切**字节数：glGetIntegerv 的调用方按 pname 准备了刚好够的空间，
 * 多写会踩坏调用方的栈（曾经因为默认返回 16 个 int 把 GLint 写爆过）。 */
size_t glp_getint_size(GLenum pname) {
    switch (pname) {
        case GL_VIEWPORT: case GL_SCISSOR_BOX: case GL_COLOR_CLEAR_VALUE:
        case GL_COLOR_WRITEMASK: case GL_BLEND_COLOR:
            return 4 * sizeof(GLint);
        case GL_MAX_VIEWPORT_DIMS: case GL_DEPTH_RANGE:
        case GL_ALIASED_LINE_WIDTH_RANGE: case GL_ALIASED_POINT_SIZE_RANGE:
            return 2 * sizeof(GLint);
        case GL_COMPRESSED_TEXTURE_FORMATS: return 64 * sizeof(GLint);
        default: return sizeof(GLint);          /* 绝大多数 pname 是单值 */
    }
}

size_t glp_uniform_size(GLuint program, GLint location, int is_float) {
    GLint n = 16;                              /* 矩阵最多 16 个 */
    (void)program; (void)location;
    return (size_t)n * (is_float ? sizeof(GLfloat) : sizeof(GLint));
}

size_t glp_index_size(GLsizei count, GLenum type) {
    size_t es = (type == GL_UNSIGNED_BYTE) ? 1 : (type == GL_UNSIGNED_SHORT) ? 2 : 4;
    return (count > 0 ? (size_t)count : 0) * es;
}

/* EGL 的属性表都是 EGL_NONE 结尾 → 可以安全地扫长度（有上限保护）*/
size_t glp_attribs_size(const EGLint *list) {
    if (!list) return 0;
    size_t n = 0;
    while (n < 256 && list[n] != EGL_NONE) n++;
    return (n + 1) * sizeof(EGLint);          /* 含结尾的 EGL_NONE */
}
