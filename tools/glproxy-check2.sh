#!/system/bin/sh
# glproxy-check2.sh —— 正确路径版（chroot 内是 /build/glproxy，不是宿主路径）
R=/data/adb/anland-chrome/root
E="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root"
echo "=== 产物 ==="
ls -l "$R/build/glproxy/libGLESv2.so.2" 2>&1
echo ""
echo "=== 导出符号（在 chroot 内用正确路径）==="
chroot "$R" /usr/bin/env -i $E /usr/bin/sh -c '
  L=/build/glproxy/libGLESv2.so.2
  echo "总导出 T 符号: $(nm -D --defined-only $L 2>/dev/null | grep -c " T ")"
  echo "gl* : $(nm -D --defined-only $L 2>/dev/null | grep -c " T gl")"
  echo "egl*: $(nm -D --defined-only $L 2>/dev/null | grep -c " T egl")"
  echo "glGetString: $(nm -D --defined-only $L 2>/dev/null | grep -c glGetString)"
  echo "glClear: $(nm -D --defined-only $L 2>/dev/null | grep -c "glClear$")"
  echo "--- 生成文件 ---"
  wc -l /build/glproxy/glp_gen_client.c
  echo "生成文件里 glGetString 出现次数: $(grep -c glGetString /build/glproxy/glp_gen_client.c)"
  echo "生成文件里函数定义数: $(grep -cE "^(void|GL_|const|EGL)[A-Za-z_ ]*\(" /build/glproxy/glp_gen_client.c)"
' 2>&1
echo ""
echo "=== 三角形测试 ==="
chroot "$R" /usr/bin/env -i $E /usr/bin/sh -c '
  cd /build/glproxy && ldd ./gltriangle 2>&1 | grep -i -e gles -e egl
  echo "--- 跑 ---"
  GLPROXY_SOCK=/run/anland/glproxy.sock ./gltriangle 2>&1 | head -14
' 2>&1
