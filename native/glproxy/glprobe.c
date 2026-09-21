/*
 * glprobe.c —— GL 转发探针（Spike A）
 *
 * 只用极小的 EGL + GLES2 子集，验证三件事：
 *   1) chroot 里的 GL 调用能经代理到达 Android 侧的进程
 *   2) 那个进程用的是 **Android 自己的 Adreno 驱动**（GL_RENDERER 会说 Adreno，而不是 llvmpipe）
 *   3) 真的画了东西（清成指定颜色后读回像素核对）
 *
 * 注意：它链接的是 glproxy-client.c（我们的转发壳），**不是**系统的 libEGL/libGLESv2，
 * 所以跑出来的结果只可能来自代理。
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int main(void) {
    printf("=== glprobe（经 GL 代理）===\n");
    printf("socket = %s\n", getenv("GLPROXY_SOCK") ? getenv("GLPROXY_SOCK") : "(默认 /run/anland/glproxy.sock)");

    EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (dpy == EGL_NO_DISPLAY) { printf("!! eglGetDisplay 失败（代理没起来？）err=0x%x\n", eglGetError()); return 1; }
    printf("eglGetDisplay  ok\n");

    EGLint maj = 0, min = 0;
    if (!eglInitialize(dpy, &maj, &min)) { printf("!! eglInitialize 失败 err=0x%x\n", eglGetError()); return 1; }
    printf("EGL %d.%d\n", maj, min);
    printf("  vendor     : %s\n", eglQueryString(dpy, EGL_VENDOR));
    printf("  version    : %s\n", eglQueryString(dpy, EGL_VERSION));
    printf("  clientAPIs : %s\n", eglQueryString(dpy, EGL_CLIENT_APIS));

    EGLint cfgAttr[] = {
        EGL_SURFACE_TYPE,    EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLConfig cfg = NULL; EGLint ncfg = 0;
    if (!eglChooseConfig(dpy, cfgAttr, &cfg, 1, &ncfg) || ncfg < 1) {
        printf("!! eglChooseConfig 失败 err=0x%x\n", eglGetError()); return 1;
    }
    EGLint rsz = 0;
    eglGetConfigAttrib(dpy, cfg, EGL_RED_SIZE, &rsz);
    printf("eglChooseConfig ok（RED_SIZE=%d）\n", rsz);

    EGLint ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxAttr);
    if (ctx == EGL_NO_CONTEXT) { printf("!! eglCreateContext 失败 err=0x%x\n", eglGetError()); return 1; }

    const int W = 64, H = 64;
    EGLint pbAttr[] = { EGL_WIDTH, W, EGL_HEIGHT, H, EGL_NONE };
    EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, pbAttr);
    if (surf == EGL_NO_SURFACE) { printf("!! eglCreatePbufferSurface 失败 err=0x%x\n", eglGetError()); return 1; }
    if (!eglMakeCurrent(dpy, surf, surf, ctx)) { printf("!! eglMakeCurrent 失败 err=0x%x\n", eglGetError()); return 1; }
    printf("context + pbuffer(%dx%d) + makeCurrent  ok\n", W, H);

    printf("---- GL 自报身份 ----\n");
    printf("  GL_VENDOR   : %s\n", glGetString(GL_VENDOR));
    printf("  GL_RENDERER : %s\n", glGetString(GL_RENDERER));
    printf("  GL_VERSION  : %s\n", glGetString(GL_VERSION));
    printf("  GLSL        : %s\n", glGetString(GL_SHADING_LANGUAGE_VERSION));

    GLint maxtex = 0;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxtex);
    printf("  GL_MAX_TEXTURE_SIZE = %d\n", maxtex);

    /* 画一笔：清成 (0.25, 0.5, 0.75, 1.0) 再读回中心像素 */
    glViewport(0, 0, W, H);
    glClearColor(0.25f, 0.50f, 0.75f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();

    unsigned char px[4] = { 0, 0, 0, 0 };
    glReadPixels(W / 2, H / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    printf("中心像素 = %d %d %d %d   (期望 64 128 191 255)\n", px[0], px[1], px[2], px[3]);

    GLenum e = glGetError();
    printf("glGetError = 0x%x\n", e);

    int ok = (px[0] == 64 && px[1] == 128 && px[2] == 191 && px[3] == 255);
    printf("=== 结论: %s ===\n", ok ? "渲染经代理成功 ✓" : "像素不对 ✗");

    /* ---- 延迟测量：这决定 Chrome 能不能用（它每帧要发上千条 GL 调用）----
     * 同步调用（glGetError 必须等服务端回包）是最坏情况；批量型调用（glClear 之类）
     * 将来可以流水线化，这里先量最坏值。 */
    {
        struct timespec t0, t1;
        const int N = 2000;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        for (int i = 0; i < N; i++) glGetError();
        clock_gettime(CLOCK_MONOTONIC, &t1);
        double us = ((t1.tv_sec - t0.tv_sec) * 1e6 + (t1.tv_nsec - t0.tv_nsec) / 1e3) / N;
        printf("同步往返延迟: %.1f µs/次（%d 次 glGetError）\n", us, N);

        clock_gettime(CLOCK_MONOTONIC, &t0);
        for (int i = 0; i < N; i++) glClear(GL_COLOR_BUFFER_BIT);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        double us2 = ((t1.tv_sec - t0.tv_sec) * 1e6 + (t1.tv_nsec - t0.tv_nsec) / 1e3) / N;
        printf("流水线调用延迟: %.1f µs/次（%d 次 glClear，仍是同步实现）\n", us2, N);
    }

    return ok ? 0 : 2;
}
