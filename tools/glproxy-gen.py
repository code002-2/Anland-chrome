#!/usr/bin/env python3
# glproxy-gen.py —— 从 EGL/GLES 头文件生成全量转发桩
#
# 在 chroot 里跑（那里有 python3 和 #include <EGL/egl.h> <GLES2/gl2.h> <GLES3/gl3.h>）：
#   python3 glproxy-gen.py /usr/include /build/glproxy
#
# 产物：
#   glp_gen.h          opcode 表（客户端/服务端共用）+ 是否同步的表
#   glp_gen_client.c   客户端转发桩（标量型全部自动生成；指针型按 PTROS 表生成）
#   glp_gen_server.c   服务端 dispatch（把参数喂给真 EGL/GLES，输出参数回传）
#   glp_unsupported.txt 没能自动生成、需要手工补的入口（迭代用）
#
# 设计要点：
#   · 标量参数一律塞进 args[]（float 按位）；指针参数的内容走 blob。
#   · 只有"要取返回值"的调用才需要回包（glp_is_sync）—— 其余走流水线，
#     这是性能的关键（实测同步往返 34.8µs，Chrome 每帧上千条调用等不起）。
import re, sys, os

HDRS = [
    ("EGL/egl.h",   "egl"),
    ("GLES2/gl2.h", "gl"),
    ("GLES3/gl3.h", "gl"),
]

# 指针参数的字节数表达式（C 表达式，可用函数的形参名）。
# 没列进来的指针型函数会被标成 unsupported，留给手工实现 —— 迭代时按日志补。
PTROS = {
    # 数据上传/下载
    "glBufferData":        {"data": "size"},
    "glBufferSubData":     {"data": "size"},
    "glTexImage2D":        {"pixels": "glp_pixels_size(width, height, format, type)"},
    "glTexSubImage2D":     {"pixels": "glp_pixels_size(width, height, format, type)"},
    "glReadPixels":        {"pixels": "glp_pixels_size(width, height, format, type)"},
    "glShaderSource":      {"string": "glp_strv_size(count, string)"},
    "glGetShaderSource":   {"source": "bufSize"},          # 出参
    "glGetShaderInfoLog":  {"infoLog": "bufSize"},         # 出参
    "glGetProgramInfoLog": {"infoLog": "bufSize"},         # 出参
    "glGetActiveUniform":  {"name": "bufSize"},            # 出参
    "glGetActiveAttrib":   {"name": "bufSize"},            # 出参
    "glGetAttribLocation": {"name": "glp_strlen(name)"},   # 入参（字符串）
    "glGetUniformLocation":{"name": "glp_strlen(name)"},   # 入参
    "glGetUniformfv":      {"params": "glp_uniform_size(program, location, 1)"},
    "glGetUniformiv":      {"params": "glp_uniform_size(program, location, 0)"},
    "glDrawElements":      {"indices": "glp_index_size(count, type)"},
    "glGenBuffers":        {"buffers": "n * 4"},           # 出参
    "glGenTextures":       {"textures": "n * 4"},          # 出参
    "glGenFramebuffers":   {"framebuffers": "n * 4"},      # 出参
    "glGenRenderbuffers":  {"renderbuffers": "n * 4"},     # 出参
    "glDeleteBuffers":     {"buffers": "n * 4"},
    "glDeleteTextures":    {"textures": "n * 4"},
    "glDeleteFramebuffers":{"framebuffers": "n * 4"},
    "glDeleteRenderbuffers":{"renderbuffers": "n * 4"},
    "glGetIntegerv":       {"params": "glp_getint_size(pname)"},
    "glGetBooleanv":       {"params": "glp_getint_size(pname)"},
    "glGetFloatv":         {"params": "glp_getint_size(pname) * 4"},

    # ---- EGL：属性表都是 EGL_NONE 结尾，可以安全扫长度 ----
    "eglChooseConfig":       {"attrib_list": "glp_attribs_size(attrib_list)", "configs": "config_size * 8"},
    "eglCreateContext":      {"attrib_list": "glp_attribs_size(attrib_list)"},
    "eglCreatePbufferSurface":{"attrib_list": "glp_attribs_size(attrib_list)"},
    "eglCreatePixmapSurface": {"attrib_list": "glp_attribs_size(attrib_list)"},
    "eglGetConfigAttrib":    {"value": "4"},
    "eglGetConfigs":         {"configs": "config_size * 8"},
    "eglQueryContext":       {"value": "4"},
    "eglQuerySurface":       {"value": "4"},
    "eglInitialize":         {"major": "4", "minor": "4"},
    "eglGetSyncAttrib":      {"value": "4"},

    # ---- GLES3 的查询类（出参长度按最坏情况给足；默认绝不乱猜，猜错会踩坏调用方栈）----
    "glGenSamplers":         {"samplers": "count * 4"},
    "glDeleteSamplers":      {"samplers": "count * 4"},
    "glGenTransformFeedbacks": {"ids": "n * 4"},
    "glDeleteTransformFeedbacks": {"ids": "n * 4"},
    "glGetInteger64v":       {"params": "glp_getint_size(pname) * 2"},
    "glGetInteger64i_v":     {"params": "glp_getint_size(pname) * 2"},
    "glGetIntegeri_v":       {"params": "glp_getint_size(pname)"},
    "glGetBufferParameteri64v": {"params": "8"},
    "glGetVertexAttribIiv":  {"params": "16"},
    "glGetVertexAttribIuiv": {"params": "16"},
    "glGetActiveUniformBlockiv": {"params": "64"},
    "glGetActiveUniformBlockName": {"uniformBlockName": "bufSize", "length": "4"},
    "glGetUniformBlockIndex": {"uniformBlockName": "glp_strlen(uniformBlockName)"},
    "glGetFragDataLocation":  {"name": "glp_strlen(name)"},
    "glGetAttachedShaders":   {"count": "4", "shaders": "maxCount * 4"},
    "glGetProgramResourceName": {"name": "bufSize", "length": "4"},
    "glGetProgramResourceiv": {"params": "propCount * 4", "length": "4"},
    "glGetProgramResourceIndex": {"name": "glp_strlen(name)"},
    "glGetProgramResourceLocation": {"name": "glp_strlen(name)"},
    "glGetnUniformfv":        {"params": "16"},
    "glGetnUniformiv":        {"params": "16"},

    # ---- 着色器/程序：字符串与查询 ----
    "glBindAttribLocation":  {"name": "glp_strlen(name)"},
    "glGetAttribLocation":   {"name": "glp_strlen(name)"},
    "glGetUniformLocation":  {"name": "glp_strlen(name)"},
    "glGetShaderiv":         {"params": "4"},
    "glGetProgramiv":        {"params": "4"},
    "glGetRenderbufferParameteriv": {"params": "4"},
    "glGetFramebufferAttachmentParameteriv": {"params": "4"},
    "glGetVertexAttribfv":   {"params": "16"},
    "glGetVertexAttribiv":   {"params": "16"},
    "glGetTexParameterfv":   {"params": "16"},
    "glGetTexParameteriv":   {"params": "16"},
    "glGetBufferParameteriv":{"params": "4"},
    "glGetShaderPrecisionFormat": {"range": "8", "precision": "4"},

    # ---- GLES3 的缓冲/纹理/绘制 ----
    "glCompressedTexImage2D":    {"data": "imageSize"},
    "glCompressedTexImage3D":    {"data": "imageSize"},
    "glCompressedTexSubImage2D": {"data": "imageSize"},
    "glCompressedTexSubImage3D": {"data": "imageSize"},
    "glTexImage3D":              {"pixels": "glp_pixels_size(width, height, format, type) * depth"},
    "glTexSubImage3D":           {"pixels": "glp_pixels_size(width, height, format, type) * depth"},
    "glClearBufferfv":           {"value": "16"},
    "glClearBufferiv":           {"value": "16"},
    "glClearBufferuiv":          {"value": "16"},
    "glClearBufferfi":           {},
    "glDrawBuffers":             {"bufs": "n * 4"},
    "glDeleteVertexArrays":      {"arrays": "n * 4"},
    "glGenVertexArrays":         {"arrays": "n * 4"},
    "glDeleteQueries":           {"ids": "n * 4"},
    "glGenQueries":              {"ids": "n * 4"},
    "glGetQueryObjectuiv":       {"params": "4"},
    "glGetQueryiv":              {"params": "4"},
    "glGetProgramBinary":        {"binary": "bufSize", "length": "4"},
    "glGetSamplerParameterfv":   {"params": "16"},
    "glGetSamplerParameteriv":   {"params": "16"},
    "glGetSynciv":               {"values": "bufSize"},
    "glGetUniformuiv":           {"params": "glp_uniform_size(program, location, 0)"},
    "glGetUniformIndices":       {"uniformIndices": "uniformCount * 4"},
    "glGetActiveUniformsiv":     {"params": "uniformCount * 4"},
    "glGetTransformFeedbackVarying": {"name": "bufSize", "size": "4", "type": "4", "length": "4"},
    "glGetInternalformativ":     {"params": "bufSize"},
    "glPushDebugGroup":          {"message": "glp_strlen(message)"},
    "glObjectLabel":             {"label": "glp_strlen(label)"},
    "glObjectPtrLabel":          {"label": "glp_strlen(label)"},
}

# 这些入口完全手工实现：生成器会给它们生成一个改名版（glp_fwd_<name>）供手写实现调用，
# 自己不再定义同名函数（否则冲突）。eglMakeCurrent 需要客户端记住 current 状态、
# eglGetCurrent* 必须立刻回答不回往返、eglGetProcAddress 走名字查表。
MANUAL_IMPL = {
    "eglGetProcAddress", "eglGetCurrentDisplay", "eglGetCurrentContext",
    "eglGetCurrentSurface", "eglMakeCurrent", "eglReleaseThread",
}

# 这些指针参数其实是**偏移量**（绑定了 VBO/EBO 时 GL 就是这么用的），
# 当标量原样传过去即可 —— 千万别去解引用它（会读到非法地址直接崩）。
# ANGLE 的 ES2 后端总是走 VBO/EBO（客户端数组会被它自己打包进 VBO），所以这样是对的。
PTR_AS_SCALAR = {
    "glVertexAttribPointer": ["pointer"],
    "glDrawElements":        ["indices"],
    "glDrawRangeElements":   ["indices"],
    "glDrawElementsInstanced": ["indices"],
}

# 明确的出参名（其余非 const 指针默认也当出参，这个表只是给"名字不直观"的用）
# GL 的约定：const 指针=入参、非 const 指针=出参。所以这里不再按名字猜
# （曾经把 glBindAttribLocation 的 const GLchar* name 当成出参 → 服务端把名字写回调用方的
#  字符串字面量，直接崩）。保留空集合是为了将来放个别例外。
OUTPARAM_HINT = set()

# 直接跳过（行为无法用简单转发表达，或本来就不该转发）
SKIP = {
    "glMapBufferRange", "glUnmapBuffer", "glFlushMappedBufferRange", "glMapBuffer",
    "glClientWaitSync", "glWaitSync", "glFenceSync", "glIsSync", "glDeleteSync",
    "glGetSynciv", "glGetPointerv", "glGetBufferPointerv",
    "glFramebufferTexture2DMultisampleEXT", "glEGLImageTargetTexture2DOES",
    "glEGLImageTargetRenderbufferStorageOES", "glDebugMessageCallback",
    "glDebugMessageCallbackKHR", "glDebugMessageControl", "glDebugMessageControlKHR",
    "glGetGraphicsResetStatus", "glGetGraphicsResetStatusKHR", "glReadnPixels",
    "glReadnPixelsKHR", "glGetnUniformfv", "glGetnUniformiv",
    "eglCreateWindowSurface", "eglCreatePlatformWindowSurface",
    "eglCreatePlatformWindowSurfaceEXT", "eglCreateStreamKHR",
    "eglCreateSyncKHR", "eglClientWaitSyncKHR", "eglDestroySyncKHR",
    "eglGetSyncAttribKHR", "eglWaitSyncKHR", "eglSwapBuffersWithDamageKHR",
    "eglSetDamageRegionKHR", "eglCreateImageKHR", "eglDestroyImageKHR",
    "eglCreateImage", "eglDestroyImage", "eglGetPlatformDisplay",
    "eglGetPlatformDisplayEXT", "eglCreatePlatformPixmapSurface",
    "eglQuerySurfacePointerANGLE", "eglLockSurfaceKHR", "eglUnlockSurfaceKHR",
    "eglCreateNativeClientBufferANDROID", "eglGetNativeClientBufferANDROID",
}

SCALAR = {
    "GLenum", "GLboolean", "GLbitfield", "GLbyte", "GLshort", "GLint", "GLsizei",
    "GLubyte", "GLushort", "GLuint", "GLfloat", "GLclampf", "GLfixed", "GLclampx",
    "GLintptr", "GLsizeiptr", "GLint64", "GLuint64", "GLchar",
    "EGLint", "EGLBoolean", "EGLenum", "EGLAttrib", "EGLint64KHR",
}

proto_re = re.compile(
    r'^\s*(?:GL_APICALL|EGLAPI)\s+(?P<ret>[A-Za-z_][A-Za-z0-9_]*)\s*(?:GL_APIENTRY|EGLAPIENTRY)?\s*'
    r'(?P<name>(?:gl|egl)[A-Za-z0-9_]+)\s*\((?P<args>[^;]*)\)\s*;', re.M)

def scalar_expr(ptype, name):
    """标量打包表达式。注意不能用 _Generic：它要求所有分支都是合法表达式，
    而 (float)(指针) 本身非法 → 编译直接报错（踩过）。按解析出的类型分派最稳。"""
    if ptype.strip() in ("GLfloat", "GLclampf", "EGLfloat", "float", "double"):
        return "glp_f2u(%s)" % name
    if "*" in ptype:
        return "(uint64_t)(uintptr_t)(%s)" % name
    return "(uint64_t)(intptr_t)(%s)" % name

def is_manual(f):
    return (f["name"] not in MANUAL_IMPL) and any(p["ptr"] and f["name"] not in PTROS for p in f["params"])

def bad_void_param(f):
    """解析出"没有 * 的 void 参数"（如 (void x)）是非法的 C 形参 —— 多半是头文件跨行
    或宏导致的解析产物，直接跳过（交给手工桩），否则生成出来的代码编不过。"""
    return any((p["type"] in ("void", "GLvoid")) and not p["ptr"] for p in f["params"])

def cname(f):
    """手工实现的两个入口，自动生成的那份改名，避免符号冲突"""
    return ("glp_fwd_" + f["name"]) if f["name"] in MANUAL_IMPL else f["name"]

def is_ptr_as_scalar(fname, pname):
    return pname in PTR_AS_SCALAR.get(fname, [])

def parse_header(path):
    try:
        src = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        return []
    out = []
    for m in proto_re.finditer(src):
        name, ret, args = m.group("name"), m.group("ret"), m.group("args").strip()
        if name in SKIP:
            continue
        params = []
        if args and args != "void":
            for p in args.split(","):
                p = p.strip()
                mm = re.match(r'^(?P<type>.+?)\s*(?P<ptr>\*+)?\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)$', p)
                if not mm:
                    params = None; break
                t = mm.group("type").strip()
                params.append({"type": t.replace("const ", "").strip(),
                               "const": p.startswith("const"),
                               "ptr": bool(mm.group("ptr")) and not is_ptr_as_scalar(name, mm.group("name")),
                               "name": mm.group("name")})
        if params is None:
            continue
        out.append({"name": name, "ret": ret, "params": params})
    return out

def main():
    incdir = sys.argv[1] if len(sys.argv) > 1 else "/usr/include"
    outdir = sys.argv[2] if len(sys.argv) > 2 else "."
    funcs, seen = [], set()
    for rel, _ in HDRS:
        for f in parse_header(os.path.join(incdir, rel)):
            if f["name"] in seen:
                continue
            if bad_void_param(f): continue
            seen.add(f["name"]); funcs.append(f)
    funcs.sort(key=lambda f: f["name"])

    gen_h, gen_c, gen_s, unsup = [], [], [], []
    gen_h.append("/* 自动生成，勿手改：python3 glproxy-gen.py */\n"
                 "#ifndef GLP_GEN_H\n#define GLP_GEN_H\n"
                 "#include <stdint.h>\n"
                 "#include <EGL/egl.h>\n"
                 "#include <GLES2/gl2.h>\n"
                 "#include <GLES3/gl3.h>\n"
                 "#include \"glproxy.h\"\n")
    gen_h.append("enum {\n")
    for i, f in enumerate(funcs):
        gen_h.append("    GLP_%s = GLP_OP_GL_BASE + %d,\n" % (f["name"].upper(), i))
    gen_h.append("    GLP_GEN_COUNT = %d\n};\n\n" % len(funcs))
    gen_h.append("/* 1 = 需要等服务端回包（有返回值或出参） */\nstatic const uint8_t glp_op_sync[GLP_GEN_COUNT] = {\n")
    syncs = []
    for i, f in enumerate(funcs):
        out_p = [p for p in f["params"] if p["ptr"] and (not p["const"] or p["name"] in OUTPARAM_HINT)]
        need = (f["ret"] != "void") or bool(out_p)
        manual = is_manual(f)
        syncs.append(0 if manual else (1 if need else 0))
        if manual:
            unsup.append(f["name"])
    gen_h.append(", ".join(str(s) for s in syncs))
    gen_h.append("\n};\n")
    # 手工实现的那几个，生成改名版给它们调用
    for f in funcs:
        if f["name"] in MANUAL_IMPL:
            gen_h.append("%s %s(%s);\n" % (f["ret"], cname(f), ", ".join(
                ("const " if p["const"] else "") + p["type"] + (" *" if p["ptr"] else " ") + p["name"]
                for p in f["params"]) or "void"))
    gen_h.append("#endif\n")

    # ---- 客户端桩 ----
    gen_c.append('/* 自动生成的客户端转发桩 */\n#include <string.h>\n#include <stdint.h>\n#include "glproxy.h"\n#include "glp_gen.h"\n#include "glp_client.h"\n\n')
    for f in funcs:
        if is_manual(f):
            continue
        ret, name, ps = f["ret"], cname(f), f["params"]
        scal = [p for p in ps if not p["ptr"]]
        ptrs = [p for p in ps if p["ptr"]]
        # 声明
        decl = "%s %s(%s)" % (ret, name, ", ".join(
            ("const " if p["const"] else "") + p["type"] + " *" + p["name"] if p["ptr"]
            else p["type"] + " " + p["name"] for p in ps) or "void")
        gen_c.append(decl + " {\n")
        gen_c.append("    uint64_t a[%d] = { %s };\n" % (max(1, len(scal)),
                     ", ".join(scalar_expr(p["type"], p["name"]) for p in scal) or "0"))
        if ptrs:
            # 指针入参算长度、拼 blob（简单起见先支持最多两个指针）
            for p in ptrs:
                if p["name"] in OUTPARAM_HINT or not p["const"]:
                    continue
                expr = PTROS.get(name, {}).get(p["name"], "0")
                gen_c.append("    uint32_t blen_%s = (uint32_t)(%s);\n" % (p["name"], expr))
            in_ptr = [p for p in ptrs if p["const"] and p["name"] not in OUTPARAM_HINT]
            out_ptr = [p for p in ptrs if not (p["const"] and p["name"] not in OUTPARAM_HINT)]
            blob = in_ptr[0]["name"] if in_ptr else "NULL"
            blen = ("blen_" + in_ptr[0]["name"]) if in_ptr else "0"
            gen_c.append("    const void *bin = %s; uint32_t blen = %s;\n" % (blob, blen))
            if out_ptr:
                op = out_ptr[0]["name"]
                oexpr = PTROS.get(name, {}).get(op, "0")
                gen_c.append("    uint32_t olen = (uint32_t)(%s);\n" % oexpr)
                gen_c.append("    uint64_t r[4]; uint16_t rc = 0;\n")
                gen_c.append("    int st = glp_call_sync(GLP_%s, %d, a, bin, blen, r, &rc, %s, &olen);\n"
                             % (f["name"].upper(), len(scal), op))
                gen_c.append("    (void)st; (void)rc;\n")
            else:
                gen_c.append("    GLP_VOID(GLP_%s, %d, a, bin, blen);\n" % (f["name"].upper(), len(scal)))
        else:
            if f["ret"] == "void":
                gen_c.append("    GLP_VOID(GLP_%s, %d, a, NULL, 0);\n" % (f["name"].upper(), len(scal)))
            else:
                gen_c.append("    uint64_t r[4]; uint16_t rc = 0;\n")
                gen_c.append("    int st = glp_call_sync(GLP_%s, %d, a, NULL, 0, r, &rc, NULL, NULL);\n"
                             % (f["name"].upper(), len(scal)))
                if ret.strip() == "const GLubyte *":
                    gen_c.append("    return (st == GLP_OK && rc >= 1) ? (const GLubyte *)glp_last_string() : NULL;\n")
                elif "*" in ret:
                    gen_c.append("    return (%s)(uintptr_t)((st == GLP_OK && rc >= 1) ? r[0] : 0);\n" % ret)
                else:
                    gen_c.append("    return (%s)((st == GLP_OK && rc >= 1) ? r[0] : 0);\n" % ret)
        gen_c.append("}\n\n")

    # ---- 手工/暂不支持的入口：生成"记日志 + 返回安全值"的桩 ----
    # 目的有两个：1) 保证 .so 导出符号完整（少了核心符号程序直接加载失败）；
    # 2) 日志里能看到 Chrome 到底调了哪些我们还没实现的入口，按需补。
    manual = [f for f in funcs if is_manual(f)]
    for f in manual:
        ps = f["params"]
        decl = "%s %s(%s)" % (f["ret"], f["name"], ", ".join(
            ("const " if p["const"] else "") + p["type"] + (" *" if p["ptr"] else " ") + p["name"]
            for p in ps) or "void")
        gen_c.append(decl + " {\n")
        argl = ", ".join("(void)%s;" % p["name"] for p in ps)
        if argl:
            gen_c.append("    " + argl + "\n")
        gen_c.append('    glp_unsupported("%s");\n' % f["name"])
        if f["ret"] != "void":
            gen_c.append("    return (%s)0;\n" % f["ret"])
        gen_c.append("}\n\n")

    # ---- 服务端 dispatch ----
    gen_s.append("/* 自动生成的服务端 dispatch */\n#include \"glp_gen.h\"\n")
    gen_s.append("int glp_gen_exec(uint16_t op, const uint64_t *a, const unsigned char *blob,\n"
                 "                  uint32_t bloblen, uint64_t *rets, uint16_t *retc,\n"
                 "                  unsigned char *out, uint32_t *outlen) {\n")
    gen_s.append("    (void)bloblen;\n    switch (op) {\n")
    for f in funcs:
        if is_manual(f):
            continue
        call_args, si, blob_used = [], 0, False
        for p in f["params"]:
            if p["ptr"]:
                if p["const"] and p["name"] not in OUTPARAM_HINT:
                    call_args.append("(%s *)blob" % p["type"]); blob_used = True
                else:
                    call_args.append("(%s *)(out)" % p["type"])   # 出参：直接写进回复缓冲
            else:
                call_args.append("(%s)a[%d]" % (p["type"], si)); si += 1
        cast = "(%s)" % f["ret"] if f["ret"] != "void" else ""
        gen_s.append("    case GLP_%s: {\n" % f["name"].upper())
        if f["ret"] == "void":
            gen_s.append("        %s(%s);\n" % (f["name"], ", ".join(call_args) or ""))
            # 出参长度
            outps = [p for p in f["params"] if p["ptr"] and not (p["const"] and p["name"] not in OUTPARAM_HINT)]
            if outps:
                expr = PTROS.get(f["name"], {}).get(outps[0]["name"], "0")
                gen_s.append("        *outlen = (uint32_t)(%s); (void)blob; return GLP_OK;\n" % expr)
            else:
                gen_s.append("        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;\n")
        else:
            gen_s.append("        %s _r = %s(%s);\n" % (f["ret"], f["name"], ", ".join(call_args) or ""))
            if f["ret"].strip() == "const GLubyte *":
                gen_s.append("        *retc = 0; *outlen = _r ? (uint32_t)strlen((const char *)_r) + 1 : 1;\n")
                gen_s.append("        if (_r) memcpy(out, _r, *outlen); else out[0] = 0;\n")
                gen_s.append("        return GLP_OK;\n")
            else:
                gen_s.append("        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;\n")
        gen_s.append("    }\n")
    gen_s.append("    default: return GLP_E_BADOP;\n    }\n}\n")

    # ---- eglGetProcAddress 用的名字表（Chrome/ANGLE 大量走它取扩展入口）----
    gen_c.append("/* 名字 → 函数指针表，供 eglGetProcAddress 使用 */\n")
    gen_c.append("const struct glp_named { const char *name; void *fn; } glp_names[] = {\n")
    for f in funcs:
        if is_manual(f):
            continue                     # 手工实现的在 glp_manual.c 里自己登记
        gen_c.append('    { "%s", (void *)%s },\n' % (f["name"], cname(f)))
    gen_c.append("    { 0, 0 }\n};\n")
    gen_c.append("const unsigned glp_names_count = sizeof glp_names / sizeof glp_names[0];\n")

    open(os.path.join(outdir, "glp_gen.h"), "w").write("".join(gen_h))
    open(os.path.join(outdir, "glp_gen_client.c"), "w").write("".join(gen_c))
    open(os.path.join(outdir, "glp_gen_server.c"), "w").write("".join(gen_s))
    open(os.path.join(outdir, "glp_unsupported.txt"), "w").write(
        "\n".join(sorted(set(unsup))) + "\n")
    print("入口总数 %d；自动生成客户端桩；需要手工补的 %d 个（见 glp_unsupported.txt）"
          % (len(funcs), len(set(unsup))))
    print("同步（需回包）%d 个，流水线 %d 个" % (sum(syncs), len(syncs) - sum(syncs)))

if __name__ == "__main__":
    main()
