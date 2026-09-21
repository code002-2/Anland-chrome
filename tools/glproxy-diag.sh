#!/system/bin/sh
# gdiag.sh -- diagnose why Chrome falls back: does a real EGL consumer work with the shim
# installed as the SYSTEM libEGL/libGLESv2?
set -u
R=/data/adb/anland-chrome/root
RT=/data/local/tmp/awl
E="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root"

echo "=== 0. glproxy server ==="
if ! pgrep glproxy-server >/dev/null 2>&1; then
  rm -f "$RT/glproxy.sock"
  setsid /data/local/tmp/glproxy/glproxy-server "$RT/glproxy.sock" > /data/local/tmp/glproxy.log 2>&1 < /dev/null &
  sleep 2
fi
echo "  pid=$(pidof glproxy-server)  sock=$(ls -l "$RT/glproxy.sock" 2>&1 | awk '{print $1, $NF}')"

echo "=== 1. 系统库位置上的到底是谁 ==="
ls -l "$R/usr/lib/aarch64-linux-gnu/libEGL.so.1" "$R/usr/lib/aarch64-linux-gnu/libEGL.so.1.1.0" 2>&1
chroot "$R" /usr/bin/env -i $E /usr/bin/sh -c \
  "nm -D --defined-only /usr/lib/aarch64-linux-gnu/libEGL.so.1.1.0 2>/dev/null | grep -c ' T egl'; echo '--- glp 符号 ---'; nm -D --defined-only /usr/lib/aarch64-linux-gnu/libGLESv2.so.2.1.0 2>/dev/null | grep -c glp_" 2>&1

echo "=== 2. 绑定 /run/anland ==="
mkdir -p "$R/run/anland"
grep -q " $R/run/anland " /proc/mounts || mount --bind "$RT" "$R/run/anland"
grep -q " $R/run/anland " /proc/mounts && echo "  bound: $(ls -l "$R/run/anland/glproxy.sock" 2>&1 | awk '{print $1, $NF}')" || echo "  !! not bound"

echo "=== 3. 真实 EGL 消费者 es2_info（会走我们的壳）==="
chroot "$R" /usr/bin/env -i $E GLPROXY_SOCK=/run/anland/glproxy.sock \
  /usr/bin/es2_info 2>&1 | head -22

echo "=== 4. 服务端日志（有没有客户端接入）==="
logcat -d -s glproxy:* 2>/dev/null | tail -8

echo "=== 5. Chrome 侧：GPU 进程实际用了什么 ==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in *--type=gpu-process*) echo "$cl" | tr ' ' '\n' | grep -E 'use-gl|use-angle' | sed 's/^/  /';; esac
done
echo "GDIAG-DONE"
