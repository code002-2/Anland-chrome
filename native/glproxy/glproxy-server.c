/*
 * glproxy-server.c —— GL 转发的执行端（Android 侧，bionic，root 运行）
 *
 * 它把 chroot 里发过来的 GL/EGL 调用，真正执行在 **Android 自己的 EGL/GLES** 上
 * （也就是 SurfaceFlinger / 守护进程用的同一套 Adreno 驱动），因此不会像 Mesa 那样
 * 引入第二套用户态驱动 —— 这是本项目唯一被验证安全的 GPU 加速路线。
 *
 * 编译（PC 侧 NDK，直接链 NDK 的 EGL/GLESv2 存根，运行时解析到厂商实现）：
 *   aarch64-linux-android29-clang -O2 -Wall -pthread glproxy-server.c -o glproxy-server -lEGL -lGLESv2 -llog
 *
 * 每个连接一个线程、一套自己的 EGL display/config/context/surface：
 * eglMakeCurrent 是**按线程**生效的，所以线程模型天然隔离，互不干扰。
 */
#define LOG_TAG "glproxy"
#include <android/log.h>

#include <EGL/egl.h>
#include <GLES2/gl2.h>

#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include "glproxy.h"
#include "glp_gen.h"   /* 生成的 opcode 表 */

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define MAX_CFG   64
#define MAX_CTX   32
#define MAX_SURF  32

typedef struct {
    int fd;
    EGLDisplay dpy;
    EGLConfig  cfgs[MAX_CFG];
    int        ncfg;
    EGLContext ctxs[MAX_CTX];
    EGLSurface surfs[MAX_SURF];
    unsigned char *in, *out;          /* 复用的收发缓冲 */
    size_t in_cap, out_cap;
} client_t;
/* ------------------------------------------------------------------ IO 原语 */

static int read_full(int fd, void *buf, size_t n) {
    size_t off = 0;
    while (off < n) {
        ssize_t r = read(fd, (char *)buf + off, n - off);
        if (r <= 0) return r == 0 ? 0 : -1;
        off += (size_t)r;
    }
    return (int)n;
}

static int write_full(int fd, const void *buf, size_t n) {
    size_t off = 0;
    while (off < n) {
        ssize_t w = write(fd, (const char *)buf + off, n - off);
        if (w <= 0) return -1;
        off += (size_t)w;
    }
    return 0;
}

static int send_rsp(client_t *c, uint16_t status, uint16_t retc,
                    const uint64_t *rets, const void *blob, uint32_t bloblen) {
    uint32_t len = (uint32_t)(sizeof(struct glp_rsp) + bloblen);
    struct glp_rsp r;
    memset(&r, 0, sizeof r);
    r.len = len; r.status = status; r.retc = retc;
    if (rets) memcpy(r.rets, rets, retc * sizeof(uint64_t));
    if (write_full(c->fd, &r, sizeof r) != 0) return -1;
    if (bloblen && write_full(c->fd, blob, bloblen) != 0) return -1;
    return 0;
}

static int send_str(client_t *c, const char *s) {
    if (!s) s = "";
    return send_rsp(c, GLP_OK, 0, NULL, s, (uint32_t)strlen(s) + 1);
}

static int send_err(client_t *c, uint16_t status, const char *fmt, ...) {
    char buf[256];
    va_list ap; va_start(ap, fmt);
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    LOGE("%s", buf);
    return send_rsp(c, status, 0, NULL, buf, (uint32_t)strlen(buf) + 1);
}

/* ------------------------------------------------------------------ 请求处理 */

/* 生成的 GL/EGL 全量 dispatch（glp_gen_server.c）：
 * 返回 GLP_NO_REPLY 表示"这条是流水线调用，不回包"。 */
int glp_gen_exec(uint16_t op, const uint64_t *a, const unsigned char *blob, uint32_t bloblen,
                 uint64_t *rets, uint16_t *retc, unsigned char *out, uint32_t *outlen);

static int handle(client_t *c, struct glp_req *q, unsigned char *blob) {
    uint64_t rets[GLP_MAX_ARGS];
    memset(rets, 0, sizeof rets);

    /* eglChooseConfig DEBUG: 定位多出参编组问题（临时日志） */
    if (q->op == GLP_EGLCHOOSECONFIG) {
        uint32_t bl = q->len - (uint32_t)sizeof(struct glp_req);
        const EGLint *at = (const EGLint *)blob;
        LOGI("eglChooseConfig IN: dpy=%llu config_size=%d bloblen=%u attribs=[%d %d %d %d %d %d %d %d]",
             (unsigned long long)q->args[0], (int)q->args[1], bl,
             bl >= 4 ? at[0] : -1, bl >= 8 ? at[1] : -1, bl >= 12 ? at[2] : -1,
             bl >= 16 ? at[3] : -1, bl >= 20 ? at[4] : -1, bl >= 24 ? at[5] : -1,
             bl >= 28 ? at[6] : -1, bl >= 32 ? at[7] : -1);
    }    /* 字符串数组入参：客户端把内容编组过来了，这里重建本地指针数组 */
    if (q->op == GLP_OP_CUSTOM_STRARRAY) {
        uint32_t bl = q->len - (uint32_t)sizeof(struct glp_req);
        if (!blob || bl < 8) return send_err(c, GLP_E_ARGS, "strarray blob 太小");
        int32_t cnt = *(const int32_t *)blob;
        if (cnt < 0 || cnt > 64) return send_err(c, GLP_E_ARGS, "strarray count=%d", cnt);
        const char *p = (const char *)blob + 8;
        const char *end = (const char *)blob + bl;
        const GLchar *arr[64];
        int n = 0;
        for (int i = 0; i < cnt; i++) {
            if (p >= end) break;
            arr[n++] = (const GLchar *)p;
            p += strlen(p) + 1;
        }
        glShaderSource((GLuint)q->args[0], n, arr, NULL);
        return 0;                       /* 流水线调用：不回包 */
    }
    /* 生成的全量 GL/EGL 入口 */
    if (q->op >= GLP_OP_GL_BASE) {
        uint16_t retc = 0; uint32_t outlen = 0;
        uint32_t bloblen = q->len - (uint32_t)sizeof(struct glp_req);
        int st = glp_gen_exec(q->op, q->args, blob, bloblen, rets, &retc, c->out, &outlen);
        if (q->op == GLP_EGLCHOOSECONFIG) {
            LOGI("eglChooseConfig OUT: st=%d retc=%u ret0=%llu outlen=%u out[0..3]=%d %d %d %d eglErr=0x%x",
                 st, (unsigned)retc, (unsigned long long)rets[0], outlen,
                 outlen >= 4 ? ((EGLint *)c->out)[0] : -1,
                 outlen >= 8 ? ((EGLint *)c->out)[1] : -1,
                 outlen >= 12 ? ((EGLint *)c->out)[2] : -1,
                 outlen >= 16 ? ((EGLint *)c->out)[3] : -1, eglGetError());
        }
        if (st == GLP_NO_REPLY) return 0;                 /* 流水线调用：不回包 */
        if (st != GLP_OK) return send_err(c, GLP_E_GL, "op 0x%x 执行失败", q->op);
        if (outlen > c->out_cap) outlen = (uint32_t)c->out_cap;
        return send_rsp(c, GLP_OK, retc, rets, outlen ? c->out : NULL, outlen);
    }

    switch (q->op) {

    /* ---------------- EGL ---------------- */
    case GLP_OP_PING:
        return send_str(c, "glproxy-server/1 ok");

    case GLP_EGL_GET_DISPLAY: {
        if (!c->dpy) c->dpy = eglGetDisplay((EGLNativeDisplayType)(uintptr_t)q->args[0]);
        rets[0] = c->dpy ? 1 : 0;
        return send_rsp(c, c->dpy ? GLP_OK : GLP_E_GL, 1, rets, NULL, 0);
    }
    case GLP_EGL_INITIALIZE: {
        EGLint maj = 0, min = 0;
        EGLBoolean ok = eglInitialize(c->dpy, &maj, &min);
        rets[0] = ok; rets[1] = (uint64_t)maj; rets[2] = (uint64_t)min;
        return send_rsp(c, GLP_OK, 3, rets, NULL, 0);
    }
    case GLP_EGL_TERMINATE:
        eglTerminate(c->dpy);
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);

    case GLP_EGL_QUERY_STRING:
        return send_str(c, eglQueryString(c->dpy, (EGLint)q->args[1]));

    case GLP_EGL_GET_CONFIGS: {
        EGLint n = 0;
        /* 先要总数，再取全部（blob = 客户端不传内容，这里只当作容量提示） */
        eglGetConfigs(c->dpy, NULL, 0, &n);
        if (n <= 0) return send_err(c, GLP_E_GL, "eglGetConfigs 没有 config");
        if (n > MAX_CFG) n = MAX_CFG;
        EGLConfig cfgs[MAX_CFG];
        EGLint got = 0;
        eglGetConfigs(c->dpy, cfgs, n, &got);
        c->ncfg = got;
        for (int i = 0; i < got; i++) c->cfgs[i] = cfgs[i];
        /* 回传句柄表（客户端只当作不透明 int 用） */
        int32_t handles[MAX_CFG];
        for (int i = 0; i < got; i++) handles[i] = i + 1;
        return send_rsp(c, GLP_OK, 1, (uint64_t[]){ (uint64_t)got }, handles,
                        (uint32_t)(got * sizeof(int32_t)));
    }
    case GLP_EGL_CHOOSE_CONFIG: {
        EGLConfig cfg = NULL;
        EGLint got = 0;
        /* num_config 不能传 NULL（EGL 规范要求，传了就是 EGL_BAD_PARAMETER 0x300C） */
        EGLBoolean ok = eglChooseConfig(c->dpy, (const EGLint *)blob, &cfg, 1, &got);
        if (!ok || !cfg || got < 1) return send_err(c, GLP_E_GL, "eglChooseConfig 失败 (ok=%d got=%d err=0x%x)",
                                                   (int)ok, got, eglGetError());
        c->cfgs[0] = cfg; c->ncfg = 1;
        rets[0] = 1;                        /* 句柄 1 */
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    }
    case GLP_EGL_GET_CONFIG_ATTRIB: {
        EGLint v = 0;
        eglGetConfigAttrib(c->dpy, c->cfgs[q->args[1] - 1], (EGLint)q->args[2], &v);
        rets[0] = (uint64_t)v;
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    }
    case GLP_EGL_CREATE_CONTEXT: {
        EGLContext ctx = eglCreateContext(c->dpy, c->cfgs[q->args[1] - 1],
                                          EGL_NO_CONTEXT, (const EGLint *)blob);
        if (ctx == EGL_NO_CONTEXT) return send_err(c, GLP_E_GL, "eglCreateContext 失败");
        int slot = -1;
        for (int i = 0; i < MAX_CTX; i++) if (!c->ctxs[i]) { slot = i; break; }
        if (slot < 0) return send_err(c, GLP_E_GL, "context 表满");
        c->ctxs[slot] = ctx;
        rets[0] = (uint64_t)(slot + 1);
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    }
    case GLP_EGL_DESTROY_CONTEXT: {
        int i = (int)q->args[1] - 1;
        if (i >= 0 && i < MAX_CTX && c->ctxs[i]) { eglDestroyContext(c->dpy, c->ctxs[i]); c->ctxs[i] = NULL; }
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    }
    case GLP_EGL_CREATE_PBUFFER: {
        EGLint attribs[24]; int n = 0;
        if (blob) { /* 客户端传 attribs（含结尾 EGL_NONE），原样抄进来 */
            const EGLint *a = (const EGLint *)blob;
            while (n < 20 && a[n] != EGL_NONE) { attribs[n] = a[n]; n++; }
        }
        if (n == 0) {                            /* 客户端没给属性：自己补尺寸 */
            attribs[n++] = EGL_WIDTH;  attribs[n++] = (EGLint)q->args[2];
            attribs[n++] = EGL_HEIGHT; attribs[n++] = (EGLint)q->args[3];
        }
        attribs[n++] = EGL_NONE;

        EGLSurface s = eglCreatePbufferSurface(c->dpy, c->cfgs[q->args[1] - 1], attribs);
        if (s == EGL_NO_SURFACE) {
            char dump[256]; int off = 0;
            for (int i = 0; i < n && off < 200; i++)
                off += snprintf(dump + off, sizeof dump - off, "%d ", attribs[i]);
            return send_err(c, GLP_E_GL, "eglCreatePbufferSurface 失败 err=0x%x (cfg=%p attribs=[%s] w=%u h=%u)",
                            eglGetError(), (void *)c->cfgs[q->args[1] - 1], dump,
                            (unsigned)q->args[2], (unsigned)q->args[3]);
        }
        int slot = -1;
        for (int i = 0; i < MAX_SURF; i++) if (!c->surfs[i]) { slot = i; break; }
        if (slot < 0) return send_err(c, GLP_E_GL, "surface 表满");
        c->surfs[slot] = s;
        rets[0] = (uint64_t)(slot + 1);
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    }
    case GLP_EGL_DESTROY_SURFACE: {
        int i = (int)q->args[1] - 1;
        if (i >= 0 && i < MAX_SURF && c->surfs[i]) { eglDestroySurface(c->dpy, c->surfs[i]); c->surfs[i] = NULL; }
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    }
    case GLP_EGL_MAKE_CURRENT: {
        int ci = (int)q->args[3] - 1, di = (int)q->args[1] - 1, ri = (int)q->args[2] - 1;
        EGLContext ctx = (ci >= 0 && ci < MAX_CTX) ? c->ctxs[ci] : EGL_NO_CONTEXT;
        EGLSurface drw = (di >= 0 && di < MAX_SURF) ? c->surfs[di] : EGL_NO_SURFACE;
        EGLSurface rd  = (ri >= 0 && ri < MAX_SURF) ? c->surfs[ri] : drw;
        EGLBoolean ok = eglMakeCurrent(c->dpy, drw, rd, ctx);
        rets[0] = ok;
        return send_rsp(c, ok ? GLP_OK : GLP_E_GL, 1, rets, NULL, 0);
    }
    case GLP_EGL_SWAP_BUFFERS: {
        int si = (int)q->args[1] - 1;
        EGLBoolean ok = eglSwapBuffers(c->dpy, (si >= 0 && si < MAX_SURF) ? c->surfs[si] : EGL_NO_SURFACE);
        rets[0] = ok;
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    }
    case GLP_EGL_GET_ERROR:
        rets[0] = (uint64_t)eglGetError();
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    case GLP_EGL_QUERY_CONTEXT: {
        EGLint v = 0;
        int ci = (int)q->args[1] - 1;
        eglQueryContext(c->dpy, (ci >= 0 && ci < MAX_CTX) ? c->ctxs[ci] : EGL_NO_CONTEXT,
                        (EGLint)q->args[2], &v);
        rets[0] = (uint64_t)v;
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    }
    case GLP_EGL_BIND_API:
        rets[0] = eglBindAPI((EGLenum)q->args[0]);
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);
    case GLP_EGL_QUERY_API:
        rets[0] = eglQueryAPI();
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);

    /* ---------------- GLES ---------------- */
    case GLP_GL_GET_STRING:
        return send_str(c, (const char *)glGetString((GLenum)q->args[0]));

    case GLP_GL_GET_ERROR:
        rets[0] = (uint64_t)glGetError();
        return send_rsp(c, GLP_OK, 1, rets, NULL, 0);

    case GLP_GL_GET_INTEGER_V: {
        int n = (int)q->args[1];
        if (n <= 0 || n > 64) return send_err(c, GLP_E_ARGS, "glGetIntegerv count 非法: %d", n);
        GLint v[64];
        glGetIntegerv((GLenum)q->args[0], v);
        return send_rsp(c, GLP_OK, 0, NULL, v, (uint32_t)(n * sizeof(GLint)));
    }
    case GLP_GL_CLEAR_COLOR: {
        float f[4];
        for (int i = 0; i < 4; i++) { uint32_t b = (uint32_t)q->args[i]; memcpy(&f[i], &b, 4); }
        glClearColor(f[0], f[1], f[2], f[3]);
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    }
    case GLP_GL_CLEAR:
        glClear((GLbitfield)q->args[0]);
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    case GLP_GL_FINISH:
        glFinish();
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    case GLP_GL_FLUSH:
        glFlush();
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    case GLP_GL_VIEWPORT:
        glViewport((GLint)q->args[0], (GLint)q->args[1], (GLsizei)q->args[2], (GLsizei)q->args[3]);
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    case GLP_GL_SCISSOR:
        glScissor((GLint)q->args[0], (GLint)q->args[1], (GLsizei)q->args[2], (GLsizei)q->args[3]);
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    case GLP_GL_ENABLE:
        glEnable((GLenum)q->args[0]);
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    case GLP_GL_DISABLE:
        glDisable((GLenum)q->args[0]);
        return send_rsp(c, GLP_OK, 0, NULL, NULL, 0);
    case GLP_GL_READ_PIXELS: {
        GLsizei w = (GLsizei)q->args[2], h = (GLsizei)q->args[3];
        size_t bytes = (size_t)w * h * 4;      /* 暂时只支持 RGBA/UNSIGNED_BYTE */
        unsigned char *px = malloc(bytes ? bytes : 1);
        if (!px) return send_err(c, GLP_E_ARGS, "readPixels 分配失败");
        glReadPixels((GLint)q->args[0], (GLint)q->args[1], w, h,
                     (GLenum)q->args[4], (GLenum)q->args[5], px);
        int rc = send_rsp(c, GLP_OK, 0, NULL, px, (uint32_t)bytes);
        free(px);
        return rc;
    }

    case GLP_OP_BYE:
        return 1;                            /* 让调用方收尾 */

    default:
        return send_err(c, GLP_E_BADOP, "未知 opcode %u", q->op);
    }
}

/* ------------------------------------------------------------------ 每连接线程 */

static void *conn_thread(void *arg) {
    client_t *c = (client_t *)arg;
    LOGI("客户端接入 fd=%d", c->fd);

    for (;;) {
        struct glp_req q;
        int r = read_full(c->fd, &q, sizeof q);
        if (r <= 0) break;
        if (q.len < sizeof q || q.argc > GLP_MAX_ARGS) { LOGE("坏消息 len=%u argc=%u", q.len, q.argc); break; }

        uint32_t bloblen = q.len - (uint32_t)sizeof q;
        unsigned char *blob = NULL;
        if (bloblen) {
            if (bloblen > GLP_MAX_BLOB) { LOGE("blob 过大 %u", bloblen); break; }
            blob = malloc(bloblen);
            if (!blob || read_full(c->fd, blob, bloblen) <= 0) { free(blob); break; }
        }

        int done = handle(c, &q, blob);
        free(blob);
        if (done) break;
    }

    /* 收尾：清掉这个连接的 EGL 资源（不清会漏显存） */
    if (c->dpy) {
        eglMakeCurrent(c->dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        for (int i = 0; i < MAX_SURF; i++) if (c->surfs[i]) eglDestroySurface(c->dpy, c->surfs[i]);
        for (int i = 0; i < MAX_CTX; i++)  if (c->ctxs[i])  eglDestroyContext(c->dpy, c->ctxs[i]);
        if (c->dpy != EGL_NO_DISPLAY) eglTerminate(c->dpy);
    }
    LOGI("客户端断开 fd=%d", c->fd);
    close(c->fd);
    free(c->out);
    free(c);
    return NULL;
}

int main(int argc, char **argv) {
    const char *path = (argc > 1) ? argv[1] : GLP_DEFAULT_SOCK;

    int lfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (lfd < 0) { LOGE("socket: %s", strerror(errno)); return 1; }
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof sa.sun_path) { LOGE("路径太长"); return 1; }
    strcpy(sa.sun_path, path);
    unlink(path);
    if (bind(lfd, (struct sockaddr *)&sa, sizeof sa) != 0 || listen(lfd, 16) != 0) {
        LOGE("bind/listen %s: %s", path, strerror(errno));
        return 1;
    }
    chmod(path, 0777);
    LOGI("glproxy-server 监听 %s", path);
    LOGI("EGL 版本: %s", eglQueryString(EGL_NO_DISPLAY, EGL_VERSION) ?: "(查询失败)");

    for (;;) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) { if (errno == EINTR) continue; LOGE("accept: %s", strerror(errno)); break; }
        client_t *c = calloc(1, sizeof *c);
        if (!c) { close(cfd); continue; }
        c->fd = cfd;
        c->out_cap = GLP_MAX_BLOB;
        c->out = malloc(c->out_cap);
        if (!c->out) { free(c); close(cfd); continue; }
        pthread_t t;
        if (pthread_create(&t, NULL, conn_thread, c) != 0) { LOGE("pthread_create 失败"); close(cfd); free(c); continue; }
        pthread_detach(t);
    }
    return 0;
}
