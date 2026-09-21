#!/usr/bin/env python3
# glproxy-gen.py —— 从 EGL/GLES 头文件生成全量转发桩（第二版）
#
# 在 chroot 里跑（有 python3 与 EGL/GLES 头文件）：
#   python3 glproxy-gen.py /usr/include /build/glproxy
# 产物：glp_gen.h（opcode 表）/ glp_gen_client.c（客户端桩）/ glp_gen_server.c（服务端 dispatch）
#
# 第一版踩过的坑，这版全部固化：
#   · 返回类型可能是多词带指针（const GLubyte *）—— 只允许一个词会让所有返回指针的入口
#     凭空消失（glGetString 找不到就是这个原因）
#   · 名字必须用 \b 锚定，否则贪婪的返回类型会把 eglXxx 的 e 吃掉，生成出 glXxx 假名字
#   · 返回类型里可能混进 GL_APIENTRY 宏，要剥掉，否则生成 "void GL_APIENTRY _r = ..."
#   · 解析不可靠的（函数指针参数、多级指针、空类型参）一律用**头文件原始声明**做桩
#   · 长度表达式引用的标识符必须真的在形参表里，否则降级
#   · **多出参**：eglChooseConfig(configs,num_config)、glGetShaderInfoLog(length,log) 这类
#     必须按顺序排布在回复缓冲里，客户端再逐段回拷（第一版只支持一个出参，卡在 eglChooseConfig）
import re, sys, os

HDRS = ["EGL/egl.h", "GLES2/gl2.h", "GLES3/gl3.h"]

# 指针参数的字节数表达式（C 表达式，可用形参名与 glp_* 辅助）
PTROS = {
    "glBufferData": {"data": "size"}, "glBufferSubData": {"data": "size"},
    "glTexImage2D": {"pixels": "glp_pixels_size(width, height, format, type)"},
    "glTexSubImage2D": {"pixels": "glp_pixels_size(width, height, format, type)"},
    "glTexImage3D": {"pixels": "glp_pixels_size(width, height, format, type) * depth"},
    "glTexSubImage3D": {"pixels": "glp_pixels_size(width, height, format, type) * depth"},
    "glReadPixels": {"pixels": "glp_pixels_size(width, height, format, type)"},
    "glShaderSource": {"string": "glp_strv_size(count, string)"},
    "glCompressedTexImage2D": {"data": "imageSize"},
    "glCompressedTexImage3D": {"data": "imageSize"},
    "glCompressedTexSubImage2D": {"data": "imageSize"},
    "glCompressedTexSubImage3D": {"data": "imageSize"},
    "glBindAttribLocation": {"name": "glp_strlen(name)"},
    "glGetAttribLocation": {"name": "glp_strlen(name)"},
    "glGetUniformLocation": {"name": "glp_strlen(name)"},
    "glGetUniformBlockIndex": {"name": "glp_strlen(uniformBlockName)"},
    "glGetFragDataLocation": {"name": "glp_strlen(name)"},
    "glObjectLabel": {"label": "glp_strlen(label)"},
    "glPushDebugGroup": {"message": "glp_strlen(message)"},
    # 多出参：键的书写顺序 = 回复缓冲里的排布顺序
    "eglChooseConfig": {"attrib_list": "glp_attribs_size(attrib_list)", "configs": "config_size * 8", "num_config": "4"},
    "eglGetConfigs": {"configs": "config_size * 8", "num_config": "4"},
    "eglInitialize": {"major": "4", "minor": "4"},
    "eglGetConfigAttrib": {"value": "4"},
    "eglQueryContext": {"value": "4"},
    "eglQuerySurface": {"value": "4"},
    "eglGetSyncAttrib": {"value": "4"},
    "glGenBuffers": {"buffers": "n * 4"}, "glGenTextures": {"textures": "n * 4"},
    "glGenFramebuffers": {"framebuffers": "n * 4"},
    "glGenRenderbuffers": {"renderbuffers": "n * 4"},
    "glGenSamplers": {"samplers": "count * 4"},
    "glGenQueries": {"ids": "n * 4"}, "glGenVertexArrays": {"arrays": "n * 4"},
    "glGenTransformFeedbacks": {"ids": "n * 4"},
    "glDeleteBuffers": {"buffers": "n * 4"}, "glDeleteTextures": {"textures": "n * 4"},
    "glDeleteFramebuffers": {"framebuffers": "n * 4"},
    "glDeleteRenderbuffers": {"renderbuffers": "n * 4"},
    "glDeleteSamplers": {"samplers": "count * 4"},
    "glDeleteQueries": {"ids": "n * 4"}, "glDeleteVertexArrays": {"arrays": "n * 4"},
    "glDeleteTransformFeedbacks": {"ids": "n * 4"},
    "glGetIntegerv": {"params": "glp_getint_size(pname)"},
    "glGetBooleanv": {"params": "glp_getint_size(pname)"},
    "glGetFloatv": {"params": "glp_getint_size(pname) * 4"},
    "glGetInteger64v": {"params": "glp_getint_size(pname) * 2"},
    "glGetIntegeri_v": {"params": "glp_getint_size(pname)"},
    "glGetInteger64i_v": {"params": "glp_getint_size(pname) * 2"},
    "glGetBufferParameteriv": {"params": "4"}, "glGetBufferParameteri64v": {"params": "8"},
    "glGetShaderiv": {"params": "4"}, "glGetProgramiv": {"params": "4"},
    "glGetRenderbufferParameteriv": {"params": "4"},
    "glGetFramebufferAttachmentParameteriv": {"params": "4"},
    "glGetTexParameterfv": {"params": "16"}, "glGetTexParameteriv": {"params": "16"},
    "glGetSamplerParameterfv": {"params": "16"}, "glGetSamplerParameteriv": {"params": "16"},
    "glGetVertexAttribfv": {"params": "16"}, "glGetVertexAttribiv": {"params": "16"},
    "glGetVertexAttribIiv": {"params": "16"}, "glGetVertexAttribIuiv": {"params": "16"},
    "glGetQueryiv": {"params": "4"}, "glGetQueryObjectuiv": {"params": "4"},
    "glGetUniformfv": {"params": "glp_uniform_size(program, location, 1)"},
    "glGetUniformiv": {"params": "glp_uniform_size(program, location, 0)"},
    "glGetUniformuiv": {"params": "glp_uniform_size(program, location, 0)"},
    "glGetShaderInfoLog": {"infoLog": "bufSize"},
    "glGetProgramInfoLog": {"infoLog": "bufSize"},
    "glGetShaderSource": {"source": "bufSize"},
    "glGetActiveUniform": {"name": "bufSize"},
    "glGetActiveAttrib": {"name": "bufSize"},
    "glGetActiveUniformBlockName": {"uniformBlockName": "bufSize"},
    "glGetActiveUniformName": {"uniformName": "bufSize"},
    "glGetTransformFeedbackVarying": {"name": "bufSize", "size": "4", "type": "4"},
    "glGetProgramResourceName": {"name": "bufSize"},
    "glGetAttachedShaders": {"shaders": "maxCount * 4"},
    "glGetActiveUniformsiv": {"params": "uniformCount * 4"},
    "glGetUniformIndices": {"uniformIndices": "uniformCount * 4"},
    "glGetSynciv": {"values": "bufSize"},
    "glGetInternalformativ": {"params": "bufSize"},
    "glClearBufferfv": {"value": "16"}, "glClearBufferiv": {"value": "16"},
    "glClearBufferuiv": {"value": "16"}, "glDrawBuffers": {"bufs": "n * 4"},
    "glGetProgramBinary": {"binary": "bufSize"},
    "glGetProgramResourceiv": {"params": "propCount * 4"},
    "glGetnUniformfv": {"params": "16"}, "glGetnUniformiv": {"params": "16"},
    "glGetShaderPrecisionFormat": {"range": "8", "precision": "4"},
    "glGetPointerv": {"params": "8"},
    "eglCreateContext": {"attrib_list": "glp_attribs_size(attrib_list)"},
    "eglCreatePbufferSurface": {"attrib_list": "glp_attribs_size(attrib_list)"},
    "eglCreatePixmapSurface": {"attrib_list": "glp_attribs_size(attrib_list)"},
    "glUniformMatrix2fv": {"value": "count * 16"},
    "glUniformMatrix3fv": {"value": "count * 36"},
    "glUniformMatrix4fv": {"value": "count * 64"},
    "glUniformMatrix2x3fv": {"value": "count * 24"},
    "glUniformMatrix3x2fv": {"value": "count * 24"},
    "glUniformMatrix2x4fv": {"value": "count * 32"},
    "glUniformMatrix4x2fv": {"value": "count * 32"},
    "glUniformMatrix3x4fv": {"value": "count * 48"},
    "glUniformMatrix4x3fv": {"value": "count * 48"},
    "glTexParameterfv": {"params": "4"}, "glTexParameteriv": {"params": "4"},
    "glSamplerParameterfv": {"param": "4"}, "glSamplerParameteriv": {"param": "4"},
    "glShaderSource": {"string": "glp_strv_size(count, string)", "length": "length ? count * 4 : 0"},
    "glTransformFeedbackVaryings": {"varyings": "glp_strv_size(count, varyings)"},
    "glProgramBinary": {"binary": "length"}, "glShaderBinary": {"shaders": "count * 4"},
    "glInvalidateFramebuffer": {"attachments": "numAttachments * 4"},
    "glInvalidateSubFramebuffer": {"attachments": "numAttachments * 4"},
    "glUniform1fv": {"value": "count * 4"},
    "glUniform1iv": {"value": "count * 4"},
    "glUniform1uiv": {"value": "count * 4"},
    "glUniform2fv": {"value": "count * 8"},
    "glUniform2iv": {"value": "count * 8"},
    "glUniform2uiv": {"value": "count * 8"},
    "glUniform3fv": {"value": "count * 12"},
    "glUniform3iv": {"value": "count * 12"},
    "glUniform3uiv": {"value": "count * 12"},
    "glUniform4fv": {"value": "count * 16"},
    "glUniform4iv": {"value": "count * 16"},
    "glUniform4uiv": {"value": "count * 16"},
    "glUniformMatrix2fv": {"value": "count * 0"},
    "glUniformMatrix3fv": {"value": "count * 0"},
    "glUniformMatrix4fv": {"value": "count * 0"},
    "glUniformMatrix2x3fv": {"value": "count * 0"},
    "glUniformMatrix3x2fv": {"value": "count * 0"},
    "glUniformMatrix2x4fv": {"value": "count * 0"},
    "glUniformMatrix4x2fv": {"value": "count * 0"},
    "glUniformMatrix3x4fv": {"value": "count * 0"},
    "glUniformMatrix4x3fv": {"value": "count * 0"},
    "glVertexAttrib1fv": {"v": "4"},
    "glVertexAttrib2fv": {"v": "8"},
    "glVertexAttrib3fv": {"v": "12"},
    "glVertexAttrib4fv": {"v": "16"},
    "glVertexAttribI4iv": {"v": "16"},
    "glVertexAttribI4uiv": {"v": "16"},
}

# 这些指针参数其实是**偏移量**（绑定 VBO/EBO 时 GL 的用法）→ 当标量传，千万别解引用
PTR_AS_SCALAR = {"glVertexAttribPointer": ["pointer"], "glDrawElements": ["indices"],
                 "glDrawRangeElements": ["indices"], "glDrawElementsInstanced": ["indices"],
                 "glVertexAttribIPointer": ["pointer"],
                 "glDrawElementsBaseVertex": ["indices"],
                 "glDrawRangeElementsBaseVertex": ["indices"]}

# 不再跳过任何入口：缺符号会让整个 .so 加载失败（es2_info 与 Chrome 都栽在这）。
# 不支持的入口一律生成"返回失败值"的桩（eglCreateWindowSurface -> EGL_NO_SURFACE 等）。
SKIP = set()

# 栅栏类调用必须**同步**：它们的作用就是"等到前面都做完"，当成流水线调用会让
# 帧节奏/错误上报全乱（实测 glFinish 被流水线化后，300 帧只用了 0.1ms）
FORCE_SYNC = {"glFinish", "glFlush", "eglSwapBuffers", "eglWaitClient", "eglWaitGL",
              "eglWaitNative", "glReadPixels"}
MANUAL_IMPL = {"eglQueryString", "eglGetPlatformDisplay", "eglGetPlatformDisplayEXT", "glFinish", "glShaderSource", "glTransformFeedbackVaryings", "eglGetProcAddress", "eglGetCurrentDisplay", "eglGetCurrentContext",
               "eglGetCurrentSurface", "eglMakeCurrent", "eglReleaseThread"}

PROTO = re.compile(
    r'^\s*(?:GL_APICALL|EGLAPI)\s+(?P<ret>(?:[A-Za-z_][A-Za-z0-9_]*\s+)*[A-Za-z_][A-Za-z0-9_]*\s*\*?)\s*'
    r'(?:GL_APIENTRY|EGLAPIENTRY)\s+(?P<name>\b(?:gl|egl)[A-Za-z0-9_]+)\s*\((?P<args>[^;]*)\)\s*;', re.M)

def ident_ok(expr, names):
    for i in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", expr):
        if i.startswith("glp_") or i in ("sizeof", "int", "unsigned"):
            continue
        if i not in names:
            return False
    return True

def parse(path):
    try:
        src = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        return []
    out = []
    for m in PROTO.finditer(src):
        name = m.group("name")
        if name in SKIP:
            continue
        ret = re.sub(r"\s*(GL_APIENTRY|EGLAPIENTRY)\s*$", "", m.group("ret")).strip()
        args = m.group("args").strip()
        raw = m.group(0).strip().rstrip(";")
        f = {"name": name, "ret": ret, "raw": raw, "params": [], "stub": False}
        if name in MANUAL_IMPL:
            pass
        elif "(" in args or "[" in args:            # 函数指针参数：解析不可靠 → 用原始声明做桩
            f["stub"] = True; f["why"] = "funcptr"; out.append(f); continue
        if args and args != "void":
            bad = False
            for p in args.split(","):
                p = p.strip()
                mm = re.match(r'^(?P<type>.+?)\s*(?P<ptr>\*+)?\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)$', p)
                if not mm:
                    bad = True; break
                t = mm.group("type").replace("const ", "").strip()
                depth = len(mm.group("ptr") or "")
                if (not t) or (t in ("void", "GLvoid") and depth == 0) or depth > 1:
                    bad = True; break
                f["params"].append({"type": t, "const": p.startswith("const"), "decl_ptr": depth > 0, "off": depth > 0 and mm.group("name") in PTR_AS_SCALAR.get(name, []),
                                    "ptr": depth > 0 and mm.group("name") not in PTR_AS_SCALAR.get(name, []),
                                    "name": mm.group("name")})
            if bad:
                f["params"] = []; f["stub"] = True; f["why"] = "badparam:" + p; out.append(f); continue
        tab = PTROS.get(name)
        for p in f["params"]:
            if p["ptr"] and p["const"] and (not tab or p["name"] not in tab):
                f["params"] = []; f["stub"] = True; f["why"] = "insize:" + p["name"]; break
        if f["stub"]:
            out.append(f); continue
        if tab:
            names = {p["name"] for p in f["params"]}
            for pn, ex in tab.items():
                if pn not in names or not ident_ok(ex, names):
                    f["params"] = []; f["stub"] = True; f["why"] = "expr:" + pn + "=" + ex; break
        out.append(f)
    return out

def cname(f):
    return ("glp_fwd_" + f["name"]) if f["name"] in MANUAL_IMPL else f["name"]

def out_params(f):
    """非 const 指针 = 出参（GL 的约定）"""
    return [p for p in f["params"] if p["ptr"] and not p["const"]]

def in_params(f):
    return [p for p in f["params"] if p["ptr"] and p["const"]]

def scalar_expr(t, n, off=False):
    if off:
        return "(uint64_t)(uintptr_t)(%s)" % n
    if t in ("GLfloat", "GLclampf", "EGLfloat", "float", "double"):
        return "glp_f2u(%s)" % n
    if "*" in t:
        return "(uint64_t)(uintptr_t)(%s)" % n
    return "(uint64_t)(intptr_t)(%s)" % n

def gen_sizes(f):
    tab = PTROS.get(f["name"], {})
    return [tab.get(p["name"], "0") for p in out_params(f)]

def main():
    incdir = sys.argv[1] if len(sys.argv) > 1 else "/usr/include"
    outdir = sys.argv[2] if len(sys.argv) > 2 else "."
    funcs, seen = [], set()
    for h in HDRS:
        for f in parse(os.path.join(incdir, h)):
            if f["name"] in seen:
                continue
            seen.add(f["name"]); funcs.append(f)
    funcs.sort(key=lambda f: f["name"])

    H, C, S = [], [], []
    H.append("/* auto-generated by glproxy-gen.py */\n#ifndef GLP_GEN_H\n#define GLP_GEN_H\n"
             "#include <stdint.h>\n#include <EGL/egl.h>\n#include <GLES2/gl2.h>\n"
             "#include <GLES3/gl3.h>\n#include \"glproxy.h\"\n")
    H.append("enum {\n")
    for i, f in enumerate(funcs):
        H.append("    GLP_%s = GLP_OP_GL_BASE + %d,\n" % (f["name"].upper(), i))
    H.append("    GLP_GEN_COUNT = %d\n};\n" % len(funcs))
    for f in funcs:
        if f["name"] in MANUAL_IMPL:
            H.append("%s %s(%s);\n" % (f["ret"], cname(f), ", ".join(
                (("const " if p["const"] else "") + p["type"] + " *" + p["name"]) if (p["ptr"] or p.get("off"))
                else (p["type"] + " " + p["name"]) for p in f["params"]) or "void"))
    H.append("#endif\n")

    C.append('#include <string.h>\n#include "glp_client.h"\n#include "glp_gen.h"\n#include "glp_sizes.h"\n\n')
    for f in funcs:
        if f["stub"]:
            if f["name"] in MANUAL_IMPL:
                continue          # 手写实现负责，不能再生成本名的桩（否则 multiple definition）
            C.append(f["raw"] + " {\n")
            C.append('    glp_unsupported("%s");\n' % f["name"])
            if f["ret"] != "void":
                C.append("    return (%s)0;\n" % f["ret"])
            C.append("}\n\n")
            continue
        nm, ret, ps = cname(f), f["ret"], f["params"]
        scal = [p for p in ps if not p["ptr"]]
        ins, outs = in_params(f), out_params(f)
        decl = "%s %s(%s)" % (ret, nm, ", ".join(
            (("const " if p["const"] else "") + p["type"] + " *" + p["name"]) if (p["ptr"] or p.get("off"))
            else (p["type"] + " " + p["name"]) for p in ps) or "void")
        C.append(decl + " {\n")
        C.append("    uint64_t a[%d] = { %s };\n" % (max(1, len(scal)),
                 ", ".join(scalar_expr(p["type"], p["name"], p.get("off")) for p in scal) or "0"))
        bin_ = ins[0]["name"] if ins else "NULL"
        blen = ("(uint32_t)(%s)" % PTROS[f["name"]][ins[0]["name"]]) if ins else "0"
        C.append("    const void *bin = %s; uint32_t blen = %s;\n" % (bin_, blen))
        if not outs and ret == "void" and f["name"] not in FORCE_SYNC:
            C.append("    GLP_VOID(GLP_%s, %d, a, bin, blen);\n" % (f["name"].upper(), len(scal)))
        else:
            exps = gen_sizes(f)
            for i, e in enumerate(exps):
                C.append("    uint32_t olen%d = (uint32_t)(%s);\n" % (i, e))
            C.append("    uint64_t r[4]; uint16_t rc = 0;\n")
            C.append("    int st = glp_call_sync(GLP_%s, %d, a, bin, blen, r, &rc, NULL, NULL);\n"
                     % (f["name"].upper(), len(scal)))
            if outs:
                C.append("    const unsigned char *rb = glp_last_blob(); uint32_t rbl = glp_last_blob_len();\n")
                off = "0"
                for i, p in enumerate(outs):
                    C.append("    if (%s && rbl >= (uint32_t)(%s + olen%d)) memcpy(%s, rb + (%s), olen%d);\n"
                             % (p["name"], off, i, p["name"], off, i))
                    off = "%s + olen%d" % (off, i)
            if ret != "void":
                if ret.strip() == "const GLubyte *":
                    C.append("    return (st == GLP_OK && rc >= 1) ? (const GLubyte *)glp_last_string() : NULL;\n")
                else:
                    C.append("    return (%s)((st == GLP_OK && rc >= 1) ? r[0] : 0);\n" % ret)
            else:
                C.append("    (void)st; (void)rc;\n")
        C.append("}\n\n")

    # eglGetProcAddress 用的名字表（glp_manual.c 里查它）
    C.append("/* name -> function pointer table, used by eglGetProcAddress */\n")
    C.append("/* name -> function pointer table, used by eglGetProcAddress */\n")
    C.append("const struct glp_named { const char *name; void *fn; } glp_names[] = {\n")
    for f in funcs:
        # 手写实现也必须登记：ANGLE 用 eglGetProcAddress 取扩展入口
        # （eglGetPlatformDisplayEXT 就是），表里没有它 → 返回 NULL → ANGLE 直接放弃。
        C.append('    { "%s", (void *)%s },\n' % (f["name"], f["name"] if f["stub"] else cname(f)))
    C.append("    { 0, 0 }\n};\n")
    C.append("const unsigned glp_names_count = sizeof glp_names / sizeof glp_names[0];\n\n")
    S.append("/* auto-generated server dispatch */\n#include <string.h>\n"
             '#include "glp_gen.h"\n#include "glp_sizes.h"\n'
             "int glp_gen_exec(uint16_t op, const uint64_t *a, const unsigned char *blob,\n"
             "                 uint32_t bloblen, uint64_t *rets, uint16_t *retc,\n"
             "                 unsigned char *out, uint32_t *outlen) {\n"
             "    (void)bloblen; (void)out; (void)outlen; (void)rets; (void)retc;\n"
             "    switch (op) {\n")
    for f in funcs:
        if f["stub"]:
            continue
        ins, outs = in_params(f), out_params(f)
        amap, k = {}, 0
        for p in f["params"]:
            if not p["ptr"]:
                amap[p["name"]] = "a[%d]" % k; k += 1
        def mapex(e):
            for nmx, rep in amap.items():
                e = re.sub(r"\b%s\b" % re.escape(nmx), rep, e)
            return e
        exps = [mapex(e) for e in gen_sizes(f)]
        args, si, acc, i_out = [], 0, "0", 0
        for p in f["params"]:
            if p["ptr"]:
                if p["const"]:
                    args.append("(%s *)blob" % p["type"])
                else:
                    args.append("(%s *)(out + (%s))" % (p["type"], acc))
                    if i_out < len(exps):
                        acc = "(uint32_t)(%s) + (uint32_t)(%s)" % (acc, exps[i_out])
                    i_out += 1
            else:
                if p["type"] in ("void", "GLvoid"):
                    # 这个"标量"其实是指针偏移量（PTR_AS_SCALAR），服务端要按指针传
                    args.append("(GLvoid *)(uintptr_t)a[%d]" % si)
                else:
                    args.append("(%s)a[%d]" % (p["type"], si))
                si += 1
        S.append("    case GLP_%s: {\n" % f["name"].upper())
        call = "%s(%s)" % (f["name"], ", ".join(args))
        if f["ret"] != "void":
            S.append("        %s _r = %s;\n" % (f["ret"], call))
        if outs:
            total = " + ".join("(uint32_t)(%s)" % e for e in exps) if exps else "0"
            S.append("        *outlen = %s;\n" % total)
        if f["ret"] == "void":
            if not outs:
                S.append("        %s;\n        (void)blob; return GLP_NO_REPLY;\n" % call)
            else:
                S.append("        %s;\n        return GLP_OK;\n" % call)
        elif f["ret"].strip() == "const GLubyte *":
            S.append("        rets[0] = 0; *retc = 1;\n")
            S.append("        *outlen = _r ? (uint32_t)strlen((const char *)_r) + 1 : 1;\n")
            S.append("        if (_r) memcpy(out, _r, *outlen); else out[0] = 0;\n")
            S.append("        return GLP_OK;\n")
        else:
            S.append("        rets[0] = (uint64_t)_r; *retc = 1; return GLP_OK;\n")
        S.append("    }\n")
    S.append("    default: return GLP_E_BADOP;\n    }\n}\n")
    # eglGetProcAddress name table: MUST be appended before the files are written
    C.append("/* name -> fp table for eglGetProcAddress */\n")
    C.append("/* name -> fp table for eglGetProcAddress */\n")
    open(os.path.join(outdir, "glp_gen.h"), "w").write("".join(H))
    open(os.path.join(outdir, "glp_gen_client.c"), "w").write("".join(C))
    open(os.path.join(outdir, "glp_gen_server.c"), "w").write("".join(S))
    stubs = [f["name"] for f in funcs if f["stub"]]
    open(os.path.join(outdir, "glp_unsupported.txt"), "w").write("\n".join(sorted(stubs)) + "\n")
    sync = sum(1 for f in funcs if (not f["stub"]) and (out_params(f) or f["ret"] != "void"))
    for f in funcs[:400]:
        if f["stub"]:
            print("  stub %-34s %s" % (f["name"], f.get("why", "?")))
    print("入口 %d 个（桩 %d）；同步 %d，流水线 %d"
          % (len(funcs), len(stubs), sync, len(funcs) - len(stubs) - sync))

if __name__ == "__main__":
    main()
