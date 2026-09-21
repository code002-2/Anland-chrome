/*
 * glproxy-client.c —— GL 转发的客户端（chroot 内，glibc）
 *
 * 它就是将来要替换 chroot 里 libEGL.so.1 / libGLESv2.so.2 的那个壳：函数签名与
 * EGL/GLES2 头文件完全一致，内部把调用打包成 glproxy 协议发给 Android 侧的服务端。
 * 编译进 chroot 后，任何 glibc 程序（包括 Chrome 的 ANGLE）都以为自己在用普通 GL。
 *
 * Spike A 阶段只实现一小撮入口，用来验证「chroot 里的 GL 调用能落到 Adreno 上」。
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <GLES2/gl2.h>

#include "glproxy.h"

/* ------------------------------------------------------------------ 连接管理 */

static int g_fd = -1;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static char g_strbuf[4096];          /* glGetString/eglQueryString 的返回缓冲（GL 语义允许被下次调用覆盖） */

static const char *sock_path(void) {
    const char *p = getenv("GLPROXY_SOCK");
    return (p && *p) ? p : GLP_DEFAULT_SOCK;
}

static int glp_connect(void) {
    if (g_fd >= 0) return g_fd;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof sa.sun_path, "%s", sock_path());
    if (connect(fd, (struct sockaddr *)&sa, sizeof sa) != 0) {
        fprintf(stderr, "glproxy: 连不上 %s: %s\n", sa.sun_path, strerror(errno));
        close(fd);
        return -1;
    }
    g_fd = fd;
    return g_fd;
}

static int wfull(int fd, const void *b, size_t n) {
    const char *p = b; size_t off = 0;
    while (off < n) { ssize_t w = write(fd, p + off, n - off); if (w <= 0) return -1; off += (size_t)w; }
    return 0;
}
static int rfull(int fd, void *b, size_t n) {
    char *p = b; size_t off = 0;
    while (off < n) { ssize_t r = read(fd, p + off, n - off); if (r <= 0) return -1; off += (size_t)r; }
    return 0;
}

/* 发一条请求并等回复。rets/blob 可为 NULL。blob_in 为请求负载，blob_out 收回复负载。 */
static int glp_call(uint16_t op, uint16_t argc, const uint64_t *args,
                    const void *blob_in, uint32_t blob_in_len,
                    uint64_t *rets_out, uint16_t *retc_out,
                    void *blob_out, uint32_t *blob_out_len) {
    if (glp_connect() < 0) return -1;

    struct glp_req q;
    memset(&q, 0, sizeof q);
    q.len = (uint32_t)(sizeof q + blob_in_len);
    q.op = op;
    q.argc = argc;
    if (argc) memcpy(q.args, args, argc * sizeof(uint64_t));

    if (wfull(g_fd, &q, sizeof q) != 0) return -1;
    if (blob_in_len && wfull(g_fd, blob_in, blob_in_len) != 0) return -1;

    struct glp_rsp r;
    if (rfull(g_fd, &r, sizeof r) != 0) return -1;
    uint32_t rblob = (r.len > sizeof r) ? (r.len - (uint32_t)sizeof r) : 0;
    if (rblob > GLP_MAX_BLOB) return -1;
    if (rblob) {
        if (!blob_out && !blob_out_len) {                   /* 调用方不要内容：丢掉 */
            char tmp[4096];
            uint32_t left = rblob;
            while (left) {
                uint32_t n = left > sizeof tmp ? (uint32_t)sizeof tmp : left;
                if (rfull(g_fd, tmp, n) != 0) return -1;
                left -= n;
            }
        } else {
            uint32_t cap = blob_out_len ? *blob_out_len : rblob;
            uint32_t want = rblob < cap ? rblob : cap;
            if (blob_out && rfull(g_fd, blob_out, want) != 0) return -1;
            if (want < rblob) {                              /* 多余部分丢掉 */
                char tmp[4096];
                uint32_t left = rblob - want;
                while (left) {
                    uint32_t n = left > sizeof tmp ? (uint32_t)sizeof tmp : left;
                    if (rfull(g_fd, tmp, n) != 0) return -1;
                    left -= n;
                }
            }
            if (blob_out_len) *blob_out_len = rblob;
        }
    }
    if (retc_out) *retc_out = r.retc;
    if (rets_out) memcpy(rets_out, r.rets, r.retc * sizeof(uint64_t));
    return (int)r.status;
}

/* 取字符串类回复到 g_strbuf（调用方持有 g_lock） */
static const char *glp_string(uint16_t op, uint16_t argc, const uint64_t *args) {
    uint32_t n = sizeof g_strbuf;
    g_strbuf[0] = 0;
    int st = glp_call(op, argc, args, NULL, 0, NULL, NULL, g_strbuf, &n);
    if (st != GLP_OK) return NULL;
    g_strbuf[sizeof g_strbuf - 1] = 0;
    return g_strbuf;
}

/* ------------------------------------------------------------------ EGL 接口 */

EGLDisplay eglGetDisplay(EGLNativeDisplayType id) {
    uint64_t a[1] = { (uint64_t)(uintptr_t)id };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_GET_DISPLAY, 1, a, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1 && r[0]) ? (EGLDisplay)(uintptr_t)1 : EGL_NO_DISPLAY;
}

EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor) {
    uint64_t a[1] = { (uint64_t)(uintptr_t)dpy };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_INITIALIZE, 1, a, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    if (st != GLP_OK || rc < 3) return EGL_FALSE;
    if (major) *major = (EGLint)r[1];
    if (minor) *minor = (EGLint)r[2];
    return (EGLBoolean)r[0];
}

EGLBoolean eglTerminate(EGLDisplay dpy) {
    uint64_t a[1] = { (uint64_t)(uintptr_t)dpy };
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_TERMINATE, 1, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return st == GLP_OK;
}

const char *eglQueryString(EGLDisplay dpy, EGLint name) {
    uint64_t a[2] = { (uint64_t)(uintptr_t)dpy, (uint64_t)name };
    pthread_mutex_lock(&g_lock);
    const char *s = glp_string(GLP_EGL_QUERY_STRING, 2, a);
    pthread_mutex_unlock(&g_lock);
    return s;
}

EGLBoolean eglGetConfigs(EGLDisplay dpy, EGLConfig *configs, EGLint cfg_size, EGLint *num) {
    uint64_t a[1] = { (uint64_t)(uintptr_t)dpy };
    uint64_t r[4]; uint16_t rc = 0;
    int32_t handles[64]; uint32_t hn = sizeof handles;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_GET_CONFIGS, 1, a, NULL, 0, r, &rc, handles, &hn);
    pthread_mutex_unlock(&g_lock);
    if (st != GLP_OK || rc < 1) return EGL_FALSE;
    int n = (int)r[0];
    if (num) *num = n;
    if (configs) for (int i = 0; i < n && i < cfg_size; i++) configs[i] = (EGLConfig)(uintptr_t)handles[i];
    return EGL_TRUE;
}

EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attribs, EGLConfig *configs,
                           EGLint cfg_size, EGLint *num) {
    int n = 0; while (attribs && attribs[n] != EGL_NONE) n++;
    uint32_t blob_len = (uint32_t)((n + 1) * sizeof(EGLint));
    uint64_t a[1] = { (uint64_t)(uintptr_t)dpy };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_CHOOSE_CONFIG, 1, a, attribs, blob_len, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    if (st != GLP_OK || rc < 1) return EGL_FALSE;
    if (configs && cfg_size > 0) configs[0] = (EGLConfig)(uintptr_t)r[0];
    if (num) *num = 1;
    return EGL_TRUE;
}

EGLBoolean eglGetConfigAttrib(EGLDisplay dpy, EGLConfig cfg, EGLint attrib, EGLint *value) {
    uint64_t a[3] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)cfg, (uint64_t)attrib };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_GET_CONFIG_ATTRIB, 3, a, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    if (st != GLP_OK || rc < 1) return EGL_FALSE;
    if (value) *value = (EGLint)r[0];
    return EGL_TRUE;
}

EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig cfg, EGLContext share, const EGLint *attribs) {
    int n = 0; while (attribs && attribs[n] != EGL_NONE) n++;
    uint32_t blob_len = (uint32_t)((n + 1) * sizeof(EGLint));
    uint64_t a[3] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)cfg, (uint64_t)(uintptr_t)share };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_CREATE_CONTEXT, 3, a, attribs, blob_len, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1 && r[0]) ? (EGLContext)(uintptr_t)r[0] : EGL_NO_CONTEXT;
}

EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx) {
    uint64_t a[2] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)ctx };
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_DESTROY_CONTEXT, 2, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return st == GLP_OK;
}

EGLSurface eglCreatePbufferSurface(EGLDisplay dpy, EGLConfig cfg, const EGLint *attribs) {
    EGLint w = 16, h = 16;
    int n = 0;
    while (attribs && attribs[n] != EGL_NONE) {
        if (attribs[n] == EGL_WIDTH  && attribs[n + 1] != EGL_NONE) w = attribs[n + 1];
        if (attribs[n] == EGL_HEIGHT && attribs[n + 1] != EGL_NONE) h = attribs[n + 1];
        n += 2;
    }
    /* 注意要把结尾的 EGL_NONE 一起发过去：服务端靠它判断属性表结束，
     * 少发一个就会读到 blob 之外的垃圾，报 EGL_BAD_ATTRIBUTE(0x3004) —— 踩过。 */
    uint32_t blob_len = (uint32_t)((n + 1) * sizeof(EGLint));
    uint64_t a[4] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)cfg, (uint64_t)w, (uint64_t)h };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_CREATE_PBUFFER, 4, a, attribs, blob_len, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1 && r[0]) ? (EGLSurface)(uintptr_t)r[0] : EGL_NO_SURFACE;
}

EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surf) {
    uint64_t a[2] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)surf };
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_DESTROY_SURFACE, 2, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return st == GLP_OK;
}

EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx) {
    uint64_t a[4] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)draw,
                      (uint64_t)(uintptr_t)read, (uint64_t)(uintptr_t)ctx };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_MAKE_CURRENT, 4, a, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1) ? (EGLBoolean)r[0] : EGL_FALSE;
}

EGLBoolean eglSwapBuffers(EGLDisplay dpy, EGLSurface surf) {
    uint64_t a[2] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)surf };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_SWAP_BUFFERS, 2, a, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1) ? (EGLBoolean)r[0] : EGL_FALSE;
}

EGLint eglGetError(void) {
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_GET_ERROR, 0, NULL, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1) ? (EGLint)r[0] : EGL_NOT_INITIALIZED;
}

EGLBoolean eglQueryContext(EGLDisplay dpy, EGLContext ctx, EGLint attrib, EGLint *value) {
    uint64_t a[3] = { (uint64_t)(uintptr_t)dpy, (uint64_t)(uintptr_t)ctx, (uint64_t)attrib };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_QUERY_CONTEXT, 3, a, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    if (st != GLP_OK || rc < 1) return EGL_FALSE;
    if (value) *value = (EGLint)r[0];
    return EGL_TRUE;
}

EGLBoolean eglBindAPI(EGLenum api) {
    uint64_t a[1] = { (uint64_t)api };
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_BIND_API, 1, a, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1) ? (EGLBoolean)r[0] : EGL_FALSE;
}

EGLenum eglQueryAPI(void) {
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_EGL_QUERY_API, 0, NULL, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1) ? (EGLenum)r[0] : EGL_NONE;
}

/* eglGetProcAddress：Spike A 只认自己实现的那几个，其余返回 NULL */
__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *name);

void *glp_lookup(const char *name);

void *glp_lookup(const char *name) {
    if (!strcmp(name, "eglGetDisplay"))            return (void *)eglGetDisplay;
    if (!strcmp(name, "eglInitialize"))            return (void *)eglInitialize;
    if (!strcmp(name, "eglTerminate"))             return (void *)eglTerminate;
    if (!strcmp(name, "eglQueryString"))           return (void *)eglQueryString;
    if (!strcmp(name, "eglGetConfigs"))            return (void *)eglGetConfigs;
    if (!strcmp(name, "eglChooseConfig"))          return (void *)eglChooseConfig;
    if (!strcmp(name, "eglGetConfigAttrib"))       return (void *)eglGetConfigAttrib;
    if (!strcmp(name, "eglCreateContext"))         return (void *)eglCreateContext;
    if (!strcmp(name, "eglDestroyContext"))        return (void *)eglDestroyContext;
    if (!strcmp(name, "eglCreatePbufferSurface"))  return (void *)eglCreatePbufferSurface;
    if (!strcmp(name, "eglDestroySurface"))        return (void *)eglDestroySurface;
    if (!strcmp(name, "eglMakeCurrent"))           return (void *)eglMakeCurrent;
    if (!strcmp(name, "eglSwapBuffers"))           return (void *)eglSwapBuffers;
    if (!strcmp(name, "eglGetError"))              return (void *)eglGetError;
    if (!strcmp(name, "eglQueryContext"))          return (void *)eglQueryContext;
    if (!strcmp(name, "eglBindAPI"))               return (void *)eglBindAPI;
    if (!strcmp(name, "eglQueryAPI"))              return (void *)eglQueryAPI;
    if (!strcmp(name, "glGetString"))              return (void *)glGetString;
    if (!strcmp(name, "glGetError"))               return (void *)glGetError;
    if (!strcmp(name, "glGetIntegerv"))            return (void *)glGetIntegerv;
    if (!strcmp(name, "glClearColor"))             return (void *)glClearColor;
    if (!strcmp(name, "glClear"))                  return (void *)glClear;
    if (!strcmp(name, "glFinish"))                 return (void *)glFinish;
    if (!strcmp(name, "glFlush"))                  return (void *)glFlush;
    if (!strcmp(name, "glViewport"))               return (void *)glViewport;
    if (!strcmp(name, "glScissor"))                return (void *)glScissor;
    if (!strcmp(name, "glEnable"))                 return (void *)glEnable;
    if (!strcmp(name, "glDisable"))                return (void *)glDisable;
    if (!strcmp(name, "glReadPixels"))             return (void *)glReadPixels;
    return NULL;
}

__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *name) {
    return (__eglMustCastToProperFunctionPointerType)glp_lookup(name);
}

/* ------------------------------------------------------------------ GLES2 接口 */

static const char *gl_str(GLenum name) {
    uint64_t a[1] = { (uint64_t)name };
    pthread_mutex_lock(&g_lock);
    const char *s = glp_string(GLP_GL_GET_STRING, 1, a);
    pthread_mutex_unlock(&g_lock);
    return s;
}

const GLubyte *glGetString(GLenum name) { return (const GLubyte *)gl_str(name); }

GLenum glGetError(void) {
    uint64_t r[4]; uint16_t rc = 0;
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_GL_GET_ERROR, 0, NULL, NULL, 0, r, &rc, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
    return (st == GLP_OK && rc >= 1) ? (GLenum)r[0] : GL_INVALID_OPERATION;
}

void glGetIntegerv(GLenum pname, GLint *params) {
    if (!params) return;
    uint64_t a[2] = { (uint64_t)pname, 4 };          /* Spike A：一次最多取 4 个 */
    uint32_t n = 4 * sizeof(GLint);
    pthread_mutex_lock(&g_lock);
    int st = glp_call(GLP_GL_GET_INTEGER_V, 2, a, NULL, 0, NULL, NULL, params, &n);
    pthread_mutex_unlock(&g_lock);
    if (st != GLP_OK) memset(params, 0, 4 * sizeof(GLint));
}

void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a) {
    uint64_t args[4];
    float f[4] = { r, g, b, a };
    for (int i = 0; i < 4; i++) { uint32_t bits; memcpy(&bits, &f[i], 4); args[i] = bits; }
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_CLEAR_COLOR, 4, args, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glClear(GLbitfield mask) {
    uint64_t a[1] = { (uint64_t)mask };
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_CLEAR, 1, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glFinish(void) {
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_FINISH, 0, NULL, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glFlush(void) {
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_FLUSH, 0, NULL, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glViewport(GLint x, GLint y, GLsizei w, GLsizei h) {
    uint64_t a[4] = { (uint64_t)(int64_t)x, (uint64_t)(int64_t)y, (uint64_t)w, (uint64_t)h };
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_VIEWPORT, 4, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glScissor(GLint x, GLint y, GLsizei w, GLsizei h) {
    uint64_t a[4] = { (uint64_t)(int64_t)x, (uint64_t)(int64_t)y, (uint64_t)w, (uint64_t)h };
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_SCISSOR, 4, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glEnable(GLenum cap) {
    uint64_t a[1] = { (uint64_t)cap };
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_ENABLE, 1, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glDisable(GLenum cap) {
    uint64_t a[1] = { (uint64_t)cap };
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_DISABLE, 1, a, NULL, 0, NULL, NULL, NULL, NULL);
    pthread_mutex_unlock(&g_lock);
}

void glReadPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum fmt, GLenum type, void *pixels) {
    if (!pixels) return;
    uint64_t a[6] = { (uint64_t)(int64_t)x, (uint64_t)(int64_t)y, (uint64_t)w, (uint64_t)h,
                      (uint64_t)fmt, (uint64_t)type };
    uint32_t n = (uint32_t)((size_t)w * h * 4);
    pthread_mutex_lock(&g_lock);
    glp_call(GLP_GL_READ_PIXELS, 6, a, NULL, 0, NULL, NULL, pixels, &n);
    pthread_mutex_unlock(&g_lock);
}
