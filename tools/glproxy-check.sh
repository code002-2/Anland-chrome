#!/system/bin/sh
# glproxy-check.sh —— 查转发壳的导出符号与生成结果（nm 在 chroot 里有，Android shell 里没有）
R=/data/adb/anland-chrome/root
B=$R/build/glproxy
E="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root"
echo "=== 产物 ==="
ls -l "$B/libGLESv2.so.2" "$B/libEGL.so.1" "$B/gltriangle" 2>&1
echo ""
echo "=== 导出符号统计 ==="
chroot "$R" /usr/bin/env -i $E /usr/bin/sh -c \
  "nm -D --defined-only $B/libGLESv2.so.2 2>/dev/null | grep -c ' T '; echo '--- gl*/egl* 各多少 ---'; nm -D --defined-only $B/libGLESv2.so.2 2>/dev/null | grep -c ' T gl'; nm -D --defined-only $B/libGLESv2.so.2 2>/dev/null | grep -c ' T egl'; echo '--- glGetString 在不在 ---'; nm -D --defined-only $B/libGLESv2.so.2 2>/dev/null | grep glGetString" 2>&1
echo ""
echo "=== 生成文件里 glGetString / 定义总数 ==="
chroot "$R" /usr/bin/env -i $E /usr/bin/sh -c \
  "grep -c 'glGetString' $B/glp_gen_client.c; echo '--- 生成文件里函数定义数（行首非空白 + 括号 + {）---'; grep -cE '^(void|GL_|const|EGL)' $B/glp_gen_client.c" 2>&1
echo ""
echo "=== 三角形测试运行时到底加载了哪个 libGLESv2 ==="
chroot "$R" /usr/bin/env -i $E GLPROXY_SOCK=/run/anland/glproxy.sock \
  /usr/bin/shy 2>/dev/null || true
chroot "$R" /usr/bin/env -i $E /usr/bin/sh -c \
  "cd $B && ldd ./gltriangle 2>&1 | grep -i gles; echo '--- 直接跑 ---'; GLPROXY_SOCK=/run/anland/glproxy.sock ./gltriangle 2>&1 | head -12" 2>&1
