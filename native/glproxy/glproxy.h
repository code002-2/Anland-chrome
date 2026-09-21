/*
 * glproxy.h —— GL 转发的线协议（客户端 = chroot 里的 glibc 壳，服务端 = Android 侧 bionic 进程）
 *
 * 为什么要转发：chroot 里让 Mesa 直连 GPU 会把 SurfaceFlinger 打死（kgsl 与 msm 两条路都验证过，
 * 第二套用户态驱动和 Android 的 Adreno 驱动抢同一个 GPU → GPU 复位 → SF 的 GL 上下文报废）。
 * 所以 GL 调用必须落到 **Android 自己那套 EGL/GLES** 上：由 Android 侧的 bionic 进程代跑。
 *
 * 消息格式（小端）：
 *   struct glp_req  { u32 len; u16 op; u16 argc; u64 args[argc]; <blob> }
 *   struct glp_rsp  { u32 len; u16 status; u16 retc; u64 rets[retc]; <blob> }
 * len 含自身。blob 紧跟定长部分，长度 = len - sizeof(header) - argc*8。
 * 指针类参数（attrib 列表、像素数据、字符串）一律拷进 blob —— chroot 与服务端是不同
 * 地址空间（甚至不同 libc），不能传裸指针。
 */
#ifndef GLPROXY_H
#define GLPROXY_H

#include <stdint.h>

#define GLP_MAGIC      0x47504c31u   /* "GPL1" */
#define GLP_MAX_ARGS   10
#define GLP_MAX_BLOB   (4u * 1024 * 1024)   /* 单条消息 blob 上限（纹理上传要放大） */

/* ---- 操作码 ---- */
enum {
    GLP_OP_PING = 1,            /* → blob<字符串> ; ← blob<版本串>：探活 */

    GLP_EGL_GET_DISPLAY = 10,   /* arg0=display_id ; ← ret0=display 句柄 */
    GLP_EGL_INITIALIZE,         /* arg0=display ; ← ret0=ok ret1=major ret2=minor */
    GLP_EGL_TERMINATE,          /* arg0=display */
    GLP_EGL_QUERY_STRING,       /* arg0=display arg1=name ; ← blob<字符串> */
    GLP_EGL_GET_CONFIGS,        /* arg0=display blob<attribs(int[])> ; ← blob<configs> */
    GLP_EGL_CHOOSE_CONFIG,      /* arg0=display blob<attribs(int[])> ; ← ret0=config 句柄 */
    GLP_EGL_GET_CONFIG_ATTRIB,  /* arg0=display arg1=config arg2=attrib ; ← ret0=value */
    GLP_EGL_CREATE_CONTEXT,     /* arg0=display arg1=config arg2=share blob<attribs> ; ← ret0=ctx */
    GLP_EGL_DESTROY_CONTEXT,    /* arg0=display arg1=ctx */
    GLP_EGL_CREATE_PBUFFER,     /* arg0=display arg1=config arg2=w arg3=h blob<attribs> ; ← ret0=surf */
    GLP_EGL_DESTROY_SURFACE,    /* arg0=display arg1=surf */
    GLP_EGL_MAKE_CURRENT,       /* arg0=display arg1=draw arg2=read arg3=ctx ; ← ret0=ok */
    GLP_EGL_SWAP_BUFFERS,       /* arg0=display arg1=surf ; ← ret0=ok */
    GLP_EGL_GET_ERROR,          /* ← ret0=err */
    GLP_EGL_QUERY_CONTEXT,      /* arg0=display arg1=ctx arg2=attrib ; ← ret0=value */
    GLP_EGL_BIND_API,           /* arg0=api ; ← ret0=ok */
    GLP_EGL_QUERY_API,          /* ← ret0=api */

    GLP_GL_GET_STRING = 60,     /* arg0=name ; ← blob<字符串> */
    GLP_GL_GET_ERROR,
    GLP_GL_GET_INTEGER_V,       /* arg0=pname arg1=count ; ← blob<int[count]> */
    GLP_GL_CLEAR_COLOR,         /* arg0..3 = float bits */
    GLP_GL_CLEAR,               /* arg0=mask */
    GLP_GL_FINISH,
    GLP_GL_FLUSH,
    GLP_GL_VIEWPORT,            /* arg0..3 */
    GLP_GL_SCISSOR,             /* arg0..3 */
    GLP_GL_ENABLE,              /* arg0=cap */
    GLP_GL_DISABLE,             /* arg0=cap */
    GLP_GL_READ_PIXELS,         /* arg0..6 blob<像素> ; ← blob<像素>（服务端写完回传）*/

    GLP_OP_BYE = 99,
    GLP_OP_ERR = 100,           /* 服务端回：status 非 0 时 blob = 错误文本 */
};

/* status */
enum { GLP_OK = 0, GLP_E_BADOP = 1, GLP_E_ARGS = 2, GLP_E_GL = 3, GLP_E_IO = 4,
       GLP_NO_REPLY = 5 };      /* 服务端内部用：这条 op 不回包（流水线调用） */

struct glp_req {
    uint32_t len;
    uint16_t op;
    uint16_t argc;
    uint64_t args[GLP_MAX_ARGS];
    /* blob 紧随其后 */
};

struct glp_rsp {
    uint32_t len;
    uint16_t status;
    uint16_t retc;
    uint64_t rets[GLP_MAX_ARGS];
    /* blob 紧随其后 */
};

#define GLP_DEFAULT_SOCK "/run/anland/glproxy.sock"

/* ------------------------------------------------------------------ 生成的 GL 接口
 *
 * 全量 EGL/GLES 入口由 tools/glproxy-gen.py 从 chroot 里的头文件生成：
 *   op  = GLP_OP_GL_BASE + 函数序号（序号表在生成的头文件里）
 *   args[] = 标量参数（float 按位塞进 u64）
 *   blob   = 指针参数的内容（输入原样带上；输出由服务端填好回传）
 *
 * 是否需要回包由生成的表决定（glp_is_sync）：只有取返回值的调用才需要，
 * 其余走**流水线**——客户端只往写缓冲里追加，攒满或遇到同步调用才刷出去。
 * 这样每条 void 调用的成本从 34.8µs 的往返降到一次 memcpy。
 */
#define GLP_OP_GL_BASE 0x1000
/* 自定义：字符串数组入参（glShaderSource 这类"指向指针数组的指针"） */
#define GLP_OP_CUSTOM_STRARRAY 0x3001
/* 自定义：栅栏调用（glFinish 必须等 GPU 做完，不能流水线化） */
#define GLP_OP_CUSTOM_SYNC 0x3002
#define GLP_WBUF_SIZE  (256 * 1024)      /* 客户端写缓冲 */

/* 写缓冲：连续追加请求，攒满/同步时 flush */
typedef struct {
    int fd;
    unsigned char *buf;
    uint32_t len, cap;
} glp_wbuf;

/* 在写缓冲里预留一条请求（返回可填 args 的结构体指针） */
struct glp_req *glp_wbuf_begin(glp_wbuf *w, uint16_t op, uint16_t argc, uint32_t bloblen);
/* 定长并把偏移推进 */
void glp_wbuf_commit(glp_wbuf *w, struct glp_req *q, uint32_t bloblen);
/* 把缓冲里攒的请求全发出去 */
int glp_wbuf_flush(glp_wbuf *w);

#endif /* GLPROXY_H */
