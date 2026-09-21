/*
 * glp_client.h —— 客户端运行时（glibc 侧）
 *
 * 生成出来的转发桩只调用这里的几个入口：
 *   GLP_VOID  —— 无需回包：追加进写缓冲（流水线），成本是一次 memcpy
 *   GLP_SCALAR —— 标量参数打包（float 按位、指针按整数）
 *   glp_call_sync —— 需要回包：先 flush 再等回复（只有少数调用走这条）
 */
#ifndef GLP_CLIENT_H
#define GLP_CLIENT_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <EGL/egl.h>
#include <GLES2/gl2.h>

#include "glproxy.h"
#include "glp_gen.h"

/* ---- 打包标量：float 按位塞进 u64，指针按整数（偏移量）---- */
static inline uint64_t glp_f2u(float f) { uint32_t b; memcpy(&b, &f, 4); return b; }
#define GLP_SCALAR(x) _Generic((x),                    \
        float:        glp_f2u((float)(x)),             \
        double:       glp_f2u((float)(x)),             \
        default:      (uint64_t)(intptr_t)(x))

/* ---- 运行时入口 ---- */
int  glp_conn(void);                       /* 惰性连接，返回 fd（-1 = 失败） */
void glp_void(uint16_t op, uint16_t argc, const uint64_t *args,
              const void *bin, uint32_t blen);
int  glp_call_sync(uint16_t op, uint16_t argc, const uint64_t *args,
                   const void *bin, uint32_t blen,
                   uint64_t *rets, uint16_t *retc, void *bout, uint32_t *boutlen);
const char *glp_last_string(void);
const unsigned char *glp_last_blob(void);   /* 上一次同步调用的回复 blob（多出参逐段回拷用） */
uint32_t glp_last_blob_len(void);         /* 同步调用拿到的字符串（返回缓冲） */

#define GLP_VOID(op, argc, args, bin, blen) glp_void((op), (argc), (args), (bin), (blen))

/* ---- blob 长度辅助（生成器用到的表达式都调这些）---- */
size_t glp_pixels_size(GLsizei w, GLsizei h, GLenum format, GLenum type);
size_t glp_strlen(const char *s);
size_t glp_strv_size(GLsizei count, const char *const *v);
size_t glp_getint_size(GLenum pname);
size_t glp_uniform_size(GLuint program, GLint location, int is_float);
size_t glp_index_size(GLsizei count, GLenum type);
size_t glp_attribs_size(const EGLint *list);
size_t glp_strlen(const char *s);
size_t glp_strv_size(GLsizei count, const char *const *v);

/* 未实现入口的统一入口（glp_manual.c）：记一次日志、返回安全值 */
void  glp_unsupported(const char *name);
void *glp_lookup(const char *name);

#endif /* GLP_CLIENT_H */
