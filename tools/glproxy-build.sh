#!/system/bin/sh
# glproxy-build.sh —— 生成 + 编译 GL 转发壳，并用标准 GLES2 程序验证
#
# 全程在旧 rootfs（/data/adb/anland-chrome/root，带 gcc/python3）里做；
# 产物同时装到精简版 rootfs（root-slim，Chrome 实际用的那个）的 /opt/glproxy/lib。
set -u
R=/data/adb/anland-chrome/root
RS=/data/adb/anland-chrome/root-slim
RT=/data/local/tmp/awl
SRC=/data/local/tmp/glproxy
B=$R/build/glproxy
LOG=/data/local/tmp/glproxy-build.log

ENV="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root"

{
echo "=== 1. 同步源码 ==="
mkdir -p "$B"
cp -f "$SRC"/glproxy.h "$SRC"/glp_client.h "$SRC"/glp_client.c "$SRC"/glp_manual.c \
      "$SRC"/glp_sizes.h "$SRC"/gltriangle.c "$SRC"/glproxy-gen.py "$B"/ 2>/dev/null
cp -f /data/local/tmp/glproxy-gen.py "$B"/ 2>/dev/null
ls "$B"

echo ""
echo "=== 2. 生成全量转发代码 ==="
chroot "$R" /usr/bin/env -i $ENV \
  /usr/bin/python3 /build/glproxy/glproxy-gen.py /usr/include /build/glproxy 2>&1 | tail -12
echo "--- 未实现入口（前 20）---"
head -20 "$B/glp_unsupported.txt" 2>&1
echo "--- 生成物 ---"
wc -l "$B/glp_gen.h" "$B/glp_gen_client.c" "$B/glp_gen_server.c" 2>&1

echo ""
echo "=== 3. 编译转发壳 libGLESv2.so.2 ==="
chroot "$R" /usr/bin/env -i $ENV /usr/bin/sh -c \
  "cd /build/glproxy && gcc -O2 -Wall -fPIC -shared -o libGLESv2.so.2 glp_gen_client.c glp_client.c glp_manual.c -lpthread -Wl,-soname,libGLESv2.so.2 > /tmp/gcc_shim.log 2>&1; tail -30 /tmp/gcc_shim.log"
if [ ! -f "$B/libGLESv2.so.2" ]; then echo "!! 转发壳编译失败"; echo "GLPROXY-BUILD-FAIL"; exit 1; fi
cp -f "$B/libGLESv2.so.2" "$B/libEGL.so.1"
ls -l "$B/libGLESv2.so.2" "$B/libEGL.so.1"
echo "--- 导出符号数 ---"
chroot "$R" /usr/bin/env -i $ENV /usr/bin/sh -c \
  "nm -D --defined-only /build/glproxy/libGLESv2.so.2 2>/dev/null | grep -cE ' T (gl|egl)'" 2>&1

echo ""
echo "=== 4. 装到两个 rootfs 的 /opt/glproxy/lib ==="
for root in "$R" "$RS"; do
  [ -d "$root" ] || continue
  mkdir -p "$root/opt/glproxy/lib"
  cp -f "$B/libGLESv2.so.2" "$B/libEGL.so.1" "$root/opt/glproxy/lib/" 2>/dev/null
  chmod 755 "$root/opt/glproxy/lib/"*.so* 2>/dev/null
  echo "  $root/opt/glproxy/lib: $(ls "$root/opt/glproxy/lib" 2>/dev/null | tr '\n' ' ')"
done

echo ""
echo "=== 5. 编译三角形测试（链接我们的壳，不是 Mesa）==="
chroot "$R" /usr/bin/env -i $ENV /usr/bin/sh -c \
  "cd /build/glproxy && gcc -O2 -Wall -o gltriangle gltriangle.c -L/opt/glproxy/lib -lGLESv2 -lEGL -Wl,-rpath,/opt/glproxy/lib > /tmp/gcc_tri.log 2>&1; tail -20 /tmp/gcc_tri.log"
ls -l "$B/gltriangle" 2>&1

echo ""
echo "=== 6. 起服务端并跑测试 ==="
pkill glproxy-server 2>/dev/null
sleep 1
rm -f "$RT/glproxy.sock"
chmod 755 /data/local/tmp/glproxy/glproxy-server
setsid /data/local/tmp/glproxy/glproxy-server "$RT/glproxy.sock" > /data/local/tmp/glproxy.log 2>&1 < /dev/null &
sleep 2
echo "服务端 pid=$(pidof glproxy-server)"
mkdir -p "$R/run/anland"
grep -q " $R/run/anland " /proc/mounts || mount --bind "$RT" "$R/run/anland"
chroot "$R" /usr/bin/env -i $ENV GLPROXY_SOCK=/run/anland/glproxy.sock \
  /build/glproxy/gltriangle 2>&1 | tail -25

echo ""
echo "=== 7. 服务端日志 ==="
logcat -d -s glproxy:* 2>/dev/null | tail -10
echo "GLPROXY-BUILD-DONE"
} > "$LOG" 2>&1
