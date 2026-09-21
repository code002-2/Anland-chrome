/* 自动生成的服务端 dispatch */
#include <string.h>
#include "glp_gen.h"
int glp_gen_exec(uint16_t op, const uint64_t *a, const unsigned char *blob,
                  uint32_t bloblen, uint64_t *rets, uint16_t *retc,
                  unsigned char *out, uint32_t *outlen) {
    (void)bloblen;
    switch (op) {
    case GLP_EGLBINDAPI: {
        EGLBoolean _r = eglBindAPI((EGLenum)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLBINDTEXIMAGE: {
        EGLBoolean _r = eglBindTexImage((EGLDisplay)a[0], (EGLSurface)a[1], (EGLint)a[2]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLCHOOSECONFIG: {
        EGLBoolean _r = eglChooseConfig((EGLDisplay)a[0], (EGLint *)blob, (EGLConfig *)(out), (EGLint)a[1], (EGLint *)(out));
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLCLIENTWAITSYNC: {
        EGLint _r = eglClientWaitSync((EGLDisplay)a[0], (EGLSync)a[1], (EGLint)a[2], (EGLTime)a[3]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLCOPYBUFFERS: {
        EGLBoolean _r = eglCopyBuffers((EGLDisplay)a[0], (EGLSurface)a[1], (EGLNativePixmapType)a[2]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLCREATECONTEXT: {
        EGLContext _r = eglCreateContext((EGLDisplay)a[0], (EGLConfig)a[1], (EGLContext)a[2], (EGLint *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLCREATEPBUFFERSURFACE: {
        EGLSurface _r = eglCreatePbufferSurface((EGLDisplay)a[0], (EGLConfig)a[1], (EGLint *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLCREATEPIXMAPSURFACE: {
        EGLSurface _r = eglCreatePixmapSurface((EGLDisplay)a[0], (EGLConfig)a[1], (EGLNativePixmapType)a[2], (EGLint *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLDESTROYCONTEXT: {
        EGLBoolean _r = eglDestroyContext((EGLDisplay)a[0], (EGLContext)a[1]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLDESTROYSURFACE: {
        EGLBoolean _r = eglDestroySurface((EGLDisplay)a[0], (EGLSurface)a[1]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLDESTROYSYNC: {
        EGLBoolean _r = eglDestroySync((EGLDisplay)a[0], (EGLSync)a[1]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETCONFIGATTRIB: {
        EGLBoolean _r = eglGetConfigAttrib((EGLDisplay)a[0], (EGLConfig)a[1], (EGLint)a[2], (EGLint *)(out));
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETCONFIGS: {
        EGLBoolean _r = eglGetConfigs((EGLDisplay)a[0], (EGLConfig *)(out), (EGLint)a[1], (EGLint *)(out));
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETCURRENTCONTEXT: {
        EGLContext _r = eglGetCurrentContext();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETCURRENTDISPLAY: {
        EGLDisplay _r = eglGetCurrentDisplay();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETCURRENTSURFACE: {
        EGLSurface _r = eglGetCurrentSurface((EGLint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETDISPLAY: {
        EGLDisplay _r = eglGetDisplay((EGLNativeDisplayType)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETERROR: {
        EGLint _r = eglGetError();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETPROCADDRESS: {
        __eglMustCastToProperFunctionPointerType _r = eglGetProcAddress((char *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLGETSYNCATTRIB: {
        EGLBoolean _r = eglGetSyncAttrib((EGLDisplay)a[0], (EGLSync)a[1], (EGLint)a[2], (EGLAttrib *)(out));
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLINITIALIZE: {
        EGLBoolean _r = eglInitialize((EGLDisplay)a[0], (EGLint *)(out), (EGLint *)(out));
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLMAKECURRENT: {
        EGLBoolean _r = eglMakeCurrent((EGLDisplay)a[0], (EGLSurface)a[1], (EGLSurface)a[2], (EGLContext)a[3]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLQUERYAPI: {
        EGLenum _r = eglQueryAPI();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLQUERYCONTEXT: {
        EGLBoolean _r = eglQueryContext((EGLDisplay)a[0], (EGLContext)a[1], (EGLint)a[2], (EGLint *)(out));
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLQUERYSTRING: {
        const char * _r = eglQueryString((EGLDisplay)a[0], (EGLint)a[1]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLQUERYSURFACE: {
        EGLBoolean _r = eglQuerySurface((EGLDisplay)a[0], (EGLSurface)a[1], (EGLint)a[2], (EGLint *)(out));
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLRELEASETEXIMAGE: {
        EGLBoolean _r = eglReleaseTexImage((EGLDisplay)a[0], (EGLSurface)a[1], (EGLint)a[2]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLRELEASETHREAD: {
        EGLBoolean _r = eglReleaseThread();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLSURFACEATTRIB: {
        EGLBoolean _r = eglSurfaceAttrib((EGLDisplay)a[0], (EGLSurface)a[1], (EGLint)a[2], (EGLint)a[3]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLSWAPBUFFERS: {
        EGLBoolean _r = eglSwapBuffers((EGLDisplay)a[0], (EGLSurface)a[1]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLSWAPINTERVAL: {
        EGLBoolean _r = eglSwapInterval((EGLDisplay)a[0], (EGLint)a[1]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLTERMINATE: {
        EGLBoolean _r = eglTerminate((EGLDisplay)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLWAITCLIENT: {
        EGLBoolean _r = eglWaitClient();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLWAITGL: {
        EGLBoolean _r = eglWaitGL();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLWAITNATIVE: {
        EGLBoolean _r = eglWaitNative((EGLint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_EGLWAITSYNC: {
        EGLBoolean _r = eglWaitSync((EGLDisplay)a[0], (EGLSync)a[1], (EGLint)a[2]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLACTIVETEXTURE: {
        glActiveTexture((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLATTACHSHADER: {
        glAttachShader((GLuint)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBEGINQUERY: {
        glBeginQuery((GLenum)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBEGINTRANSFORMFEEDBACK: {
        glBeginTransformFeedback((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDATTRIBLOCATION: {
        glBindAttribLocation((GLuint)a[0], (GLuint)a[1], (GLchar *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDBUFFER: {
        glBindBuffer((GLenum)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDBUFFERBASE: {
        glBindBufferBase((GLenum)a[0], (GLuint)a[1], (GLuint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDBUFFERRANGE: {
        glBindBufferRange((GLenum)a[0], (GLuint)a[1], (GLuint)a[2], (GLintptr)a[3], (GLsizeiptr)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDFRAMEBUFFER: {
        glBindFramebuffer((GLenum)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDRENDERBUFFER: {
        glBindRenderbuffer((GLenum)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDSAMPLER: {
        glBindSampler((GLuint)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDTEXTURE: {
        glBindTexture((GLenum)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDTRANSFORMFEEDBACK: {
        glBindTransformFeedback((GLenum)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBINDVERTEXARRAY: {
        glBindVertexArray((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBLENDCOLOR: {
        glBlendColor((GLfloat)a[0], (GLfloat)a[1], (GLfloat)a[2], (GLfloat)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBLENDEQUATION: {
        glBlendEquation((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBLENDEQUATIONSEPARATE: {
        glBlendEquationSeparate((GLenum)a[0], (GLenum)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBLENDFUNC: {
        glBlendFunc((GLenum)a[0], (GLenum)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBLENDFUNCSEPARATE: {
        glBlendFuncSeparate((GLenum)a[0], (GLenum)a[1], (GLenum)a[2], (GLenum)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBLITFRAMEBUFFER: {
        glBlitFramebuffer((GLint)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLint)a[4], (GLint)a[5], (GLint)a[6], (GLint)a[7], (GLbitfield)a[8], (GLenum)a[9]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBUFFERDATA: {
        glBufferData((GLenum)a[0], (GLsizeiptr)a[1], (void *)blob, (GLenum)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLBUFFERSUBDATA: {
        glBufferSubData((GLenum)a[0], (GLintptr)a[1], (GLsizeiptr)a[2], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCHECKFRAMEBUFFERSTATUS: {
        GLenum _r = glCheckFramebufferStatus((GLenum)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLCLEAR: {
        glClear((GLbitfield)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCLEARBUFFERFI: {
        glClearBufferfi((GLenum)a[0], (GLint)a[1], (GLfloat)a[2], (GLint)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCLEARBUFFERFV: {
        glClearBufferfv((GLenum)a[0], (GLint)a[1], (GLfloat *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCLEARBUFFERIV: {
        glClearBufferiv((GLenum)a[0], (GLint)a[1], (GLint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCLEARBUFFERUIV: {
        glClearBufferuiv((GLenum)a[0], (GLint)a[1], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCLEARCOLOR: {
        glClearColor((GLfloat)a[0], (GLfloat)a[1], (GLfloat)a[2], (GLfloat)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCLEARDEPTHF: {
        glClearDepthf((GLfloat)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCLEARSTENCIL: {
        glClearStencil((GLint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOLORMASK: {
        glColorMask((GLboolean)a[0], (GLboolean)a[1], (GLboolean)a[2], (GLboolean)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOMPILESHADER: {
        glCompileShader((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOMPRESSEDTEXIMAGE2D: {
        glCompressedTexImage2D((GLenum)a[0], (GLint)a[1], (GLenum)a[2], (GLsizei)a[3], (GLsizei)a[4], (GLint)a[5], (GLsizei)a[6], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOMPRESSEDTEXIMAGE3D: {
        glCompressedTexImage3D((GLenum)a[0], (GLint)a[1], (GLenum)a[2], (GLsizei)a[3], (GLsizei)a[4], (GLsizei)a[5], (GLint)a[6], (GLsizei)a[7], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOMPRESSEDTEXSUBIMAGE2D: {
        glCompressedTexSubImage2D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLsizei)a[4], (GLsizei)a[5], (GLenum)a[6], (GLsizei)a[7], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOMPRESSEDTEXSUBIMAGE3D: {
        glCompressedTexSubImage3D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLint)a[4], (GLsizei)a[5], (GLsizei)a[6], (GLsizei)a[7], (GLenum)a[8], (GLsizei)a[9], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOPYBUFFERSUBDATA: {
        glCopyBufferSubData((GLenum)a[0], (GLenum)a[1], (GLintptr)a[2], (GLintptr)a[3], (GLsizeiptr)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOPYTEXIMAGE2D: {
        glCopyTexImage2D((GLenum)a[0], (GLint)a[1], (GLenum)a[2], (GLint)a[3], (GLint)a[4], (GLsizei)a[5], (GLsizei)a[6], (GLint)a[7]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOPYTEXSUBIMAGE2D: {
        glCopyTexSubImage2D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLint)a[4], (GLint)a[5], (GLsizei)a[6], (GLsizei)a[7]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCOPYTEXSUBIMAGE3D: {
        glCopyTexSubImage3D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLint)a[4], (GLint)a[5], (GLint)a[6], (GLsizei)a[7], (GLsizei)a[8]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLCREATEPROGRAM: {
        GLuint _r = glCreateProgram();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLCREATESHADER: {
        GLuint _r = glCreateShader((GLenum)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLCULLFACE: {
        glCullFace((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETEBUFFERS: {
        glDeleteBuffers((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETEFRAMEBUFFERS: {
        glDeleteFramebuffers((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETEPROGRAM: {
        glDeleteProgram((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETEQUERIES: {
        glDeleteQueries((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETERENDERBUFFERS: {
        glDeleteRenderbuffers((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETESAMPLERS: {
        glDeleteSamplers((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETESHADER: {
        glDeleteShader((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETETEXTURES: {
        glDeleteTextures((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETETRANSFORMFEEDBACKS: {
        glDeleteTransformFeedbacks((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDELETEVERTEXARRAYS: {
        glDeleteVertexArrays((GLsizei)a[0], (GLuint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDEPTHFUNC: {
        glDepthFunc((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDEPTHMASK: {
        glDepthMask((GLboolean)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDEPTHRANGEF: {
        glDepthRangef((GLfloat)a[0], (GLfloat)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDETACHSHADER: {
        glDetachShader((GLuint)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDISABLE: {
        glDisable((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDISABLEVERTEXATTRIBARRAY: {
        glDisableVertexAttribArray((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDRAWARRAYS: {
        glDrawArrays((GLenum)a[0], (GLint)a[1], (GLsizei)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDRAWARRAYSINSTANCED: {
        glDrawArraysInstanced((GLenum)a[0], (GLint)a[1], (GLsizei)a[2], (GLsizei)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLDRAWBUFFERS: {
        glDrawBuffers((GLsizei)a[0], (GLenum *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLENABLE: {
        glEnable((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLENABLEVERTEXATTRIBARRAY: {
        glEnableVertexAttribArray((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLENDQUERY: {
        glEndQuery((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLENDTRANSFORMFEEDBACK: {
        glEndTransformFeedback();
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLFINISH: {
        glFinish();
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLFLUSH: {
        glFlush();
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLFRAMEBUFFERRENDERBUFFER: {
        glFramebufferRenderbuffer((GLenum)a[0], (GLenum)a[1], (GLenum)a[2], (GLuint)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLFRAMEBUFFERTEXTURE2D: {
        glFramebufferTexture2D((GLenum)a[0], (GLenum)a[1], (GLenum)a[2], (GLuint)a[3], (GLint)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLFRAMEBUFFERTEXTURELAYER: {
        glFramebufferTextureLayer((GLenum)a[0], (GLenum)a[1], (GLuint)a[2], (GLint)a[3], (GLint)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLFRONTFACE: {
        glFrontFace((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLGENBUFFERS: {
        glGenBuffers((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENFRAMEBUFFERS: {
        glGenFramebuffers((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENQUERIES: {
        glGenQueries((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENRENDERBUFFERS: {
        glGenRenderbuffers((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENSAMPLERS: {
        glGenSamplers((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENTEXTURES: {
        glGenTextures((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENTRANSFORMFEEDBACKS: {
        glGenTransformFeedbacks((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENVERTEXARRAYS: {
        glGenVertexArrays((GLsizei)a[0], (GLuint *)(out));
        *outlen = (uint32_t)(a[0] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGENERATEMIPMAP: {
        glGenerateMipmap((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLGETACTIVEATTRIB: {
        glGetActiveAttrib((GLuint)a[0], (GLuint)a[1], (GLsizei)a[2], (GLsizei *)(out), (GLint *)(out), (GLenum *)(out), (GLchar *)(out));
        *outlen = (uint32_t)(0); (void)blob; return GLP_OK;
    }
    case GLP_GLGETACTIVEUNIFORM: {
        glGetActiveUniform((GLuint)a[0], (GLuint)a[1], (GLsizei)a[2], (GLsizei *)(out), (GLint *)(out), (GLenum *)(out), (GLchar *)(out));
        *outlen = (uint32_t)(0); (void)blob; return GLP_OK;
    }
    case GLP_GLGETACTIVEUNIFORMBLOCKNAME: {
        glGetActiveUniformBlockName((GLuint)a[0], (GLuint)a[1], (GLsizei)a[2], (GLsizei *)(out), (GLchar *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETACTIVEUNIFORMBLOCKIV: {
        glGetActiveUniformBlockiv((GLuint)a[0], (GLuint)a[1], (GLenum)a[2], (GLint *)(out));
        *outlen = (uint32_t)(64); (void)blob; return GLP_OK;
    }
    case GLP_GLGETACTIVEUNIFORMSIV: {
        glGetActiveUniformsiv((GLuint)a[0], (GLsizei)a[1], (GLuint *)blob, (GLenum)a[2], (GLint *)(out));
        *outlen = (uint32_t)(a[1] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETATTACHEDSHADERS: {
        glGetAttachedShaders((GLuint)a[0], (GLsizei)a[1], (GLsizei *)(out), (GLuint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETATTRIBLOCATION: {
        GLint _r = glGetAttribLocation((GLuint)a[0], (GLchar *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLGETBUFFERPARAMETERI64V: {
        glGetBufferParameteri64v((GLenum)a[0], (GLenum)a[1], (GLint64 *)(out));
        *outlen = (uint32_t)(8); (void)blob; return GLP_OK;
    }
    case GLP_GLGETBUFFERPARAMETERIV: {
        glGetBufferParameteriv((GLenum)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETERROR: {
        GLenum _r = glGetError();
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLGETFRAGDATALOCATION: {
        GLint _r = glGetFragDataLocation((GLuint)a[0], (GLchar *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLGETFRAMEBUFFERATTACHMENTPARAMETERIV: {
        glGetFramebufferAttachmentParameteriv((GLenum)a[0], (GLenum)a[1], (GLenum)a[2], (GLint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETPROGRAMBINARY: {
        glGetProgramBinary((GLuint)a[0], (GLsizei)a[1], (GLsizei *)(out), (GLenum *)(out), (void *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETPROGRAMINFOLOG: {
        glGetProgramInfoLog((GLuint)a[0], (GLsizei)a[1], (GLsizei *)(out), (GLchar *)(out));
        *outlen = (uint32_t)(0); (void)blob; return GLP_OK;
    }
    case GLP_GLGETPROGRAMIV: {
        glGetProgramiv((GLuint)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETQUERYOBJECTUIV: {
        glGetQueryObjectuiv((GLuint)a[0], (GLenum)a[1], (GLuint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETQUERYIV: {
        glGetQueryiv((GLenum)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETRENDERBUFFERPARAMETERIV: {
        glGetRenderbufferParameteriv((GLenum)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETSAMPLERPARAMETERFV: {
        glGetSamplerParameterfv((GLuint)a[0], (GLenum)a[1], (GLfloat *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLGETSAMPLERPARAMETERIV: {
        glGetSamplerParameteriv((GLuint)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLGETSHADERINFOLOG: {
        glGetShaderInfoLog((GLuint)a[0], (GLsizei)a[1], (GLsizei *)(out), (GLchar *)(out));
        *outlen = (uint32_t)(0); (void)blob; return GLP_OK;
    }
    case GLP_GLGETSHADERPRECISIONFORMAT: {
        glGetShaderPrecisionFormat((GLenum)a[0], (GLenum)a[1], (GLint *)(out), (GLint *)(out));
        *outlen = (uint32_t)(8); (void)blob; return GLP_OK;
    }
    case GLP_GLGETSHADERSOURCE: {
        glGetShaderSource((GLuint)a[0], (GLsizei)a[1], (GLsizei *)(out), (GLchar *)(out));
        *outlen = (uint32_t)(0); (void)blob; return GLP_OK;
    }
    case GLP_GLGETSHADERIV: {
        glGetShaderiv((GLuint)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETSTRING: {
        const GLubyte * _r = glGetString((GLenum)a[0]);
        *retc = 0; *outlen = _r ? (uint32_t)strlen((const char *)_r) + 1 : 1;
        if (_r) memcpy(out, _r, *outlen); else out[0] = 0;
        return GLP_OK;
    }
    case GLP_GLGETSTRINGI: {
        const GLubyte * _r = glGetStringi((GLenum)a[0], (GLuint)a[1]);
        *retc = 0; *outlen = _r ? (uint32_t)strlen((const char *)_r) + 1 : 1;
        if (_r) memcpy(out, _r, *outlen); else out[0] = 0;
        return GLP_OK;
    }
    case GLP_GLGETTEXPARAMETERFV: {
        glGetTexParameterfv((GLenum)a[0], (GLenum)a[1], (GLfloat *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLGETTEXPARAMETERIV: {
        glGetTexParameteriv((GLenum)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLGETTRANSFORMFEEDBACKVARYING: {
        glGetTransformFeedbackVarying((GLuint)a[0], (GLuint)a[1], (GLsizei)a[2], (GLsizei *)(out), (GLsizei *)(out), (GLenum *)(out), (GLchar *)(out));
        *outlen = (uint32_t)(4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETUNIFORMBLOCKINDEX: {
        GLuint _r = glGetUniformBlockIndex((GLuint)a[0], (GLchar *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLGETUNIFORMINDICES: {
        glGetUniformIndices((GLuint)a[0], (GLsizei)a[1], (GLchar *const *)blob, (GLuint *)(out));
        *outlen = (uint32_t)(a[1] * 4); (void)blob; return GLP_OK;
    }
    case GLP_GLGETUNIFORMLOCATION: {
        GLint _r = glGetUniformLocation((GLuint)a[0], (GLchar *)blob);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLGETUNIFORMFV: {
        glGetUniformfv((GLuint)a[0], (GLint)a[1], (GLfloat *)(out));
        *outlen = (uint32_t)(glp_uniform_size(a[0], a[1], 1)); (void)blob; return GLP_OK;
    }
    case GLP_GLGETUNIFORMIV: {
        glGetUniformiv((GLuint)a[0], (GLint)a[1], (GLint *)(out));
        *outlen = (uint32_t)(glp_uniform_size(a[0], a[1], 0)); (void)blob; return GLP_OK;
    }
    case GLP_GLGETUNIFORMUIV: {
        glGetUniformuiv((GLuint)a[0], (GLint)a[1], (GLuint *)(out));
        *outlen = (uint32_t)(glp_uniform_size(a[0], a[1], 0)); (void)blob; return GLP_OK;
    }
    case GLP_GLGETVERTEXATTRIBIIV: {
        glGetVertexAttribIiv((GLuint)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLGETVERTEXATTRIBIUIV: {
        glGetVertexAttribIuiv((GLuint)a[0], (GLenum)a[1], (GLuint *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLGETVERTEXATTRIBFV: {
        glGetVertexAttribfv((GLuint)a[0], (GLenum)a[1], (GLfloat *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLGETVERTEXATTRIBIV: {
        glGetVertexAttribiv((GLuint)a[0], (GLenum)a[1], (GLint *)(out));
        *outlen = (uint32_t)(16); (void)blob; return GLP_OK;
    }
    case GLP_GLHINT: {
        glHint((GLenum)a[0], (GLenum)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLISBUFFER: {
        GLboolean _r = glIsBuffer((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISENABLED: {
        GLboolean _r = glIsEnabled((GLenum)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISFRAMEBUFFER: {
        GLboolean _r = glIsFramebuffer((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISPROGRAM: {
        GLboolean _r = glIsProgram((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISQUERY: {
        GLboolean _r = glIsQuery((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISRENDERBUFFER: {
        GLboolean _r = glIsRenderbuffer((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISSAMPLER: {
        GLboolean _r = glIsSampler((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISSHADER: {
        GLboolean _r = glIsShader((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISTEXTURE: {
        GLboolean _r = glIsTexture((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISTRANSFORMFEEDBACK: {
        GLboolean _r = glIsTransformFeedback((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLISVERTEXARRAY: {
        GLboolean _r = glIsVertexArray((GLuint)a[0]);
        rets[0] = (uint64_t)_r; *retc = 1; *outlen = 0; return GLP_OK;
    }
    case GLP_GLLINEWIDTH: {
        glLineWidth((GLfloat)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLLINKPROGRAM: {
        glLinkProgram((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLPAUSETRANSFORMFEEDBACK: {
        glPauseTransformFeedback();
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLPIXELSTOREI: {
        glPixelStorei((GLenum)a[0], (GLint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLPOLYGONOFFSET: {
        glPolygonOffset((GLfloat)a[0], (GLfloat)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLPROGRAMPARAMETERI: {
        glProgramParameteri((GLuint)a[0], (GLenum)a[1], (GLint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLREADBUFFER: {
        glReadBuffer((GLenum)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLREADPIXELS: {
        glReadPixels((GLint)a[0], (GLint)a[1], (GLsizei)a[2], (GLsizei)a[3], (GLenum)a[4], (GLenum)a[5], (void *)(out));
        *outlen = (uint32_t)(glp_pixels_size(a[2], a[3], a[4], a[5])); (void)blob; return GLP_OK;
    }
    case GLP_GLRELEASESHADERCOMPILER: {
        glReleaseShaderCompiler();
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLRENDERBUFFERSTORAGE: {
        glRenderbufferStorage((GLenum)a[0], (GLenum)a[1], (GLsizei)a[2], (GLsizei)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLRENDERBUFFERSTORAGEMULTISAMPLE: {
        glRenderbufferStorageMultisample((GLenum)a[0], (GLsizei)a[1], (GLenum)a[2], (GLsizei)a[3], (GLsizei)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLRESUMETRANSFORMFEEDBACK: {
        glResumeTransformFeedback();
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSAMPLECOVERAGE: {
        glSampleCoverage((GLfloat)a[0], (GLboolean)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSAMPLERPARAMETERF: {
        glSamplerParameterf((GLuint)a[0], (GLenum)a[1], (GLfloat)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSAMPLERPARAMETERI: {
        glSamplerParameteri((GLuint)a[0], (GLenum)a[1], (GLint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSCISSOR: {
        glScissor((GLint)a[0], (GLint)a[1], (GLsizei)a[2], (GLsizei)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSHADERSOURCE: {
        glShaderSource((GLuint)a[0], (GLsizei)a[1], (GLchar *const *)blob, (GLint *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSTENCILFUNC: {
        glStencilFunc((GLenum)a[0], (GLint)a[1], (GLuint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSTENCILFUNCSEPARATE: {
        glStencilFuncSeparate((GLenum)a[0], (GLenum)a[1], (GLint)a[2], (GLuint)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSTENCILMASK: {
        glStencilMask((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSTENCILMASKSEPARATE: {
        glStencilMaskSeparate((GLenum)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSTENCILOP: {
        glStencilOp((GLenum)a[0], (GLenum)a[1], (GLenum)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLSTENCILOPSEPARATE: {
        glStencilOpSeparate((GLenum)a[0], (GLenum)a[1], (GLenum)a[2], (GLenum)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXIMAGE2D: {
        glTexImage2D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLsizei)a[3], (GLsizei)a[4], (GLint)a[5], (GLenum)a[6], (GLenum)a[7], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXIMAGE3D: {
        glTexImage3D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLsizei)a[3], (GLsizei)a[4], (GLsizei)a[5], (GLint)a[6], (GLenum)a[7], (GLenum)a[8], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXPARAMETERF: {
        glTexParameterf((GLenum)a[0], (GLenum)a[1], (GLfloat)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXPARAMETERI: {
        glTexParameteri((GLenum)a[0], (GLenum)a[1], (GLint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXSTORAGE2D: {
        glTexStorage2D((GLenum)a[0], (GLsizei)a[1], (GLenum)a[2], (GLsizei)a[3], (GLsizei)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXSTORAGE3D: {
        glTexStorage3D((GLenum)a[0], (GLsizei)a[1], (GLenum)a[2], (GLsizei)a[3], (GLsizei)a[4], (GLsizei)a[5]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXSUBIMAGE2D: {
        glTexSubImage2D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLsizei)a[4], (GLsizei)a[5], (GLenum)a[6], (GLenum)a[7], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLTEXSUBIMAGE3D: {
        glTexSubImage3D((GLenum)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLint)a[4], (GLsizei)a[5], (GLsizei)a[6], (GLsizei)a[7], (GLenum)a[8], (GLenum)a[9], (void *)blob);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM1F: {
        glUniform1f((GLint)a[0], (GLfloat)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM1I: {
        glUniform1i((GLint)a[0], (GLint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM1UI: {
        glUniform1ui((GLint)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM2F: {
        glUniform2f((GLint)a[0], (GLfloat)a[1], (GLfloat)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM2I: {
        glUniform2i((GLint)a[0], (GLint)a[1], (GLint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM2UI: {
        glUniform2ui((GLint)a[0], (GLuint)a[1], (GLuint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM3F: {
        glUniform3f((GLint)a[0], (GLfloat)a[1], (GLfloat)a[2], (GLfloat)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM3I: {
        glUniform3i((GLint)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM3UI: {
        glUniform3ui((GLint)a[0], (GLuint)a[1], (GLuint)a[2], (GLuint)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM4F: {
        glUniform4f((GLint)a[0], (GLfloat)a[1], (GLfloat)a[2], (GLfloat)a[3], (GLfloat)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM4I: {
        glUniform4i((GLint)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLint)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORM4UI: {
        glUniform4ui((GLint)a[0], (GLuint)a[1], (GLuint)a[2], (GLuint)a[3], (GLuint)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUNIFORMBLOCKBINDING: {
        glUniformBlockBinding((GLuint)a[0], (GLuint)a[1], (GLuint)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLUSEPROGRAM: {
        glUseProgram((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVALIDATEPROGRAM: {
        glValidateProgram((GLuint)a[0]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVERTEXATTRIB1F: {
        glVertexAttrib1f((GLuint)a[0], (GLfloat)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVERTEXATTRIB2F: {
        glVertexAttrib2f((GLuint)a[0], (GLfloat)a[1], (GLfloat)a[2]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVERTEXATTRIB3F: {
        glVertexAttrib3f((GLuint)a[0], (GLfloat)a[1], (GLfloat)a[2], (GLfloat)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVERTEXATTRIB4F: {
        glVertexAttrib4f((GLuint)a[0], (GLfloat)a[1], (GLfloat)a[2], (GLfloat)a[3], (GLfloat)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVERTEXATTRIBDIVISOR: {
        glVertexAttribDivisor((GLuint)a[0], (GLuint)a[1]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVERTEXATTRIBI4I: {
        glVertexAttribI4i((GLuint)a[0], (GLint)a[1], (GLint)a[2], (GLint)a[3], (GLint)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVERTEXATTRIBI4UI: {
        glVertexAttribI4ui((GLuint)a[0], (GLuint)a[1], (GLuint)a[2], (GLuint)a[3], (GLuint)a[4]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    case GLP_GLVIEWPORT: {
        glViewport((GLint)a[0], (GLint)a[1], (GLsizei)a[2], (GLsizei)a[3]);
        (void)blob; (void)out; (void)outlen; return GLP_NO_REPLY;
    }
    default: return GLP_E_BADOP;
    }
}
