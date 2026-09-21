/*
 * gltriangle.c —— 用**标准 GLES2 API** 画一个三角形，验证转发壳的 ABI 兼容性
 *
 * 它只 include 标准头文件、只调标准函数，链接的却是 /opt/glproxy/lib 下的转发壳
 * （不是 Mesa）。能画出来 = 转发壳对 GLES2 的覆盖足够，且真的在 Adreno 上渲染。
 * 同时测一批帧的耗时，用来判断这种"代理"方式的性能量级。
 */
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char *VS =
    "attribute vec4 aPos;\n"
    "attribute vec4 aCol;\n"
    "varying vec4 vCol;\n"
    "void main() { gl_Position = aPos; vCol = aCol; }\n";
static const char *FS =
    "precision mediump float;\n"
    "varying vec4 vCol;\n"
    "void main() { gl_FragColor = vCol; }\n";

static GLuint mk_shader(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024] = { 0 };
        glGetShaderInfoLog(s, sizeof log, NULL, log);
        fprintf(stderr, "shader 编译失败:\n%s\n", log);
    }
    return s;
}

int main(void) {
    const int W = 256, H = 256;
    EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLint maj, min;
    if (!eglInitialize(dpy, &maj, &min)) { printf("eglInitialize 失败\n"); return 1; }

    EGLint cfgAttr[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                         EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                         EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                         EGL_NONE };
    EGLConfig cfg; EGLint n = 0;
    EGLBoolean cok = eglChooseConfig(dpy, cfgAttr, &cfg, 1, &n);
    if (!cok || n < 1) { printf("chooseConfig 失败: ret=%d ncfg=%d eglErr=0x%x\n", (int)cok, (int)n, eglGetError()); return 1; }
    EGLint ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxAttr);
    EGLint pbAttr[] = { EGL_WIDTH, W, EGL_HEIGHT, H, EGL_NONE };
    EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, pbAttr);
    if (ctx == EGL_NO_CONTEXT || surf == EGL_NO_SURFACE) { printf("context/surface 创建失败\n"); return 1; }
    if (!eglMakeCurrent(dpy, surf, surf, ctx)) { printf("makeCurrent 失败\n"); return 1; }

    printf("GL_RENDERER = %s\n", glGetString(GL_RENDERER));
    printf("GL_VERSION  = %s\n", glGetString(GL_VERSION));

    GLuint prog = glCreateProgram();
    glAttachShader(prog, mk_shader(GL_VERTEX_SHADER, VS));
    glAttachShader(prog, mk_shader(GL_FRAGMENT_SHADER, FS));
    glBindAttribLocation(prog, 0, "aPos");
    glBindAttribLocation(prog, 1, "aCol");
    glLinkProgram(prog);
    GLint linked = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &linked);
    if (!linked) { char log[1024] = { 0 }; glGetProgramInfoLog(prog, sizeof log, NULL, log);
                   printf("链接失败:\n%s\n", log); return 1; }
    glUseProgram(prog);

    /* 顶点：位置 + 颜色（红绿蓝三角）*/
    const GLfloat verts[] = {
         0.0f,  0.8f, 0.0f,  1.0f, 0.0f, 0.0f, 1.0f,
        -0.8f, -0.8f, 0.0f,  0.0f, 1.0f, 0.0f, 1.0f,
         0.8f, -0.8f, 0.0f,  0.0f, 0.0f, 1.0f, 1.0f,
    };
    GLuint vbo = 0;
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof verts, verts, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 7 * sizeof(GLfloat), (void *)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 7 * sizeof(GLfloat), (void *)(3 * sizeof(GLfloat)));

    glViewport(0, 0, W, H);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glFinish();

    unsigned char px[4] = { 0 };
    glReadPixels(W / 2, (int)(H * 0.35), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    printf("三角内部像素 = %d %d %d %d（应偏红）\n", px[0], px[1], px[2], px[3]);
    printf("glGetError = 0x%x\n", glGetError());

    /* 批量画帧测性能：每帧清屏 + 画三角，看能到多少帧/秒 */
    const int FRAMES = 300;
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < FRAMES; i++) {
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES, 0, 3);
    }
    glFinish();
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double ms = ((t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6);
    printf("%d 帧用 %.1f ms → %.1f 帧/秒，每帧 %.3f ms\n",
           FRAMES, ms, FRAMES * 1000.0 / ms, ms / FRAMES);

    int ok = (px[0] > px[1] && px[0] > px[2] && px[0] > 40);
    printf("=== %s ===\n", ok ? "GLES2 经代理渲染成功 ✓" : "像素不对 ✗");
    return ok ? 0 : 2;
}
