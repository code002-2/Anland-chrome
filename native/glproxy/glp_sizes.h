/*
 * glp_sizes.h —— blob 长度辅助（客户端与服务端**共用**）
 *
 * 为什么放头文件里做成 static inline：生成出来的服务端 dispatch 也要用这些表达式算
 * 出参长度（例如 glTexImage2D 的 pixels 大小），而服务端是 bionic、客户端是 glibc，
 * 两边编译单元不同。做成头文件里 inline，谁 include 谁有，不用额外链接。
 */
#ifndef GLP_SIZES_H
#define GLP_SIZES_H

#include <stddef.h>
#include <string.h>

#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <GLES3/gl3.h>

static inline size_t glp_pixels_size(GLsizei w, GLsizei h, GLenum format, GLenum type) {
    int comps = 4;
    switch (format) {
        case GL_ALPHA: case GL_LUMINANCE: case GL_DEPTH_COMPONENT:
        case GL_RED: case GL_RED_INTEGER: case GL_GREEN: case GL_BLUE: comps = 1; break;
        case GL_LUMINANCE_ALPHA: case GL_RG: case GL_RG_INTEGER: comps = 2; break;
        case GL_RGB: case GL_RGB_INTEGER: case GL_SRGB: comps = 3; break;
        default: comps = 4; break;
    }
    int bpc = 4;
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

static inline size_t glp_strlen(const char *s) { return s ? strlen(s) + 1 : 0; }

static inline size_t glp_strv_size(GLsizei count, const char *const *v) {
    size_t n = 0;
    if (!v || count <= 0) return 0;
    for (GLsizei i = 0; i < count; i++) n += v[i] ? strlen(v[i]) + 1 : 1;
    return n;
}

/* 只回**确切**字节数：调用方按 pname 准备了刚好够的空间，多写会踩坏它的栈 */
static inline size_t glp_getint_size(GLenum pname) {
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

static inline size_t glp_uniform_size(GLuint program, GLint location, int is_float) {
    (void)program; (void)location;
    return (size_t)16 * (is_float ? sizeof(GLfloat) : sizeof(GLint));
}

static inline size_t glp_index_size(GLsizei count, GLenum type) {
    size_t es = (type == GL_UNSIGNED_BYTE) ? 1 : (type == GL_UNSIGNED_SHORT) ? 2 : 4;
    return (count > 0 ? (size_t)count : 0) * es;
}

/* EGL 属性表都是 EGL_NONE 结尾 → 可以安全扫长度 */
static inline size_t glp_attribs_size(const EGLint *list) {
    if (!list) return 0;
    size_t n = 0;
    while (n < 256 && list[n] != EGL_NONE) n++;
    return (n + 1) * sizeof(EGLint);
}

#endif /* GLP_SIZES_H */
