/*
 * glp_manual.c —— 手工实现的少数入口（生成器够不着的那几个）
 *
 * 为什么要手工：EGL 的语义要求这几个"立刻回答"，不适合每次都往返：
 *   · eglGetCurrentDisplay/Context/Surface —— 客户端自己记住 current 状态即可
 *   · eglMakeCurrent —— 转发之外还要更新本地状态（否则上面三个答不上来）
 *   · eglReleaseThread —— 清本地状态
 *   · eglGetProcAddress —— Chrome/ANGLE 大量用它取入口，走生成的名字表
 */
#include <string.h>

#include "glp_client.h"

/* 生成的名字表（glp_gen_client.c 尾部） */
struct glp_named { const char *name; void *fn; };
extern const struct glp_named glp_names[];
extern const unsigned glp_names_count;

/* 生成器为手工实现的入口生成的"改名版"，这里声明一下（glp_gen.h 里也有，
 * 但为稳妥起见显式声明，避免隐式声明导致 ABI 猜错） */
EGLBoolean glp_fwd_eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx);
EGLBoolean glp_fwd_eglReleaseThread(void);

static EGLDisplay s_dpy  = EGL_NO_DISPLAY;
static EGLContext s_ctx  = EGL_NO_CONTEXT;
static EGLSurface s_draw = EGL_NO_SURFACE;
static EGLSurface s_read = EGL_NO_SURFACE;

void *glp_lookup(const char *name) {
    if (!name || !*name) return NULL;
    for (unsigned i = 0; i < glp_names_count; i++)
        if (glp_names[i].name && !strcmp(glp_names[i].name, name))
            return glp_names[i].fn;
    /* 手工实现的这几个不在表里，单独登记 */
    if (!strcmp(name, "eglGetProcAddress"))       return (void *)eglGetProcAddress;
    if (!strcmp(name, "eglGetCurrentDisplay"))    return (void *)eglGetCurrentDisplay;
    if (!strcmp(name, "eglGetCurrentContext"))    return (void *)eglGetCurrentContext;
    if (!strcmp(name, "eglGetCurrentSurface"))    return (void *)eglGetCurrentSurface;
    if (!strcmp(name, "eglMakeCurrent"))          return (void *)eglMakeCurrent;
    if (!strcmp(name, "eglReleaseThread"))        return (void *)eglReleaseThread;
    return NULL;
}

EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext ctx) {
    EGLBoolean r = glp_fwd_eglMakeCurrent(dpy, draw, read, ctx);
    if (r) { s_dpy = dpy; s_ctx = ctx; s_draw = draw; s_read = read; }
    return r;
}

EGLDisplay eglGetCurrentDisplay(void) { return s_dpy; }
EGLContext eglGetCurrentContext(void) { return s_ctx; }
EGLSurface eglGetCurrentSurface(EGLint readdraw) {
    return (readdraw == EGL_READ) ? s_read : s_draw;
}

EGLBoolean eglReleaseThread(void) {
    EGLBoolean r = glp_fwd_eglReleaseThread();
    s_dpy = EGL_NO_DISPLAY; s_ctx = EGL_NO_CONTEXT;
    s_draw = EGL_NO_SURFACE; s_read = EGL_NO_SURFACE;
    return r;
}

__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *procname) {
    return (__eglMustCastToProperFunctionPointerType)glp_lookup(procname);
}
