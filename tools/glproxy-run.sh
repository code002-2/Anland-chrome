#!/system/bin/sh
# glproxy-run.sh —— GL 转发 Spike A：编译 chroot 侧、起服务端、跑探针
#
# 架构：chroot 内(glibc) 的转发壳 ── unix socket ──> Android 侧(bionic) 服务端 ──> 真 EGL/GLES(Adreno)
# 用旧 rootfs 当编译环境（里面有 gcc；精简版里没有编译器）。
set -u
R=/data/adb/anland-chrome/root            # 带 gcc 的 rootfs
RT=/data/local/tmp/awl                    # 守护进程 runtime（chroot 内 = /run/anland）
SRC=/data/local/tmp/glproxy
B=$R/build/glproxy
LOG=/data/local/tmp/glproxy-run.log

{
echo "=== 1. 准备源码与目录 ==="
mkdir -p "$B" "$RT"
cp -f "$SRC"/glproxy.h "$SRC"/glproxy-client.c "$SRC"/glprobe.c "$B"/ 2>&1
ls -l "$B"

echo ""
echo "=== 2. 在 chroot 里编译转发壳 + 探针（glibc/gcc）==="
# 先删旧二进制：否则编译失败时会拿上次的旧程序跑，看不出问题（踩过）
rm -f "$B/glprobe"
chroot "$R" /usr/bin/env -i \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
  /usr/bin/sh -c "cd /build/glproxy && gcc -O2 -Wall -o glprobe glproxy-client.c glprobe.c -lpthread" 2>&1 | tail -20
if [ ! -x "$B/glprobe" ]; then echo "!! 编译失败"; echo "GLPROXY-RUN-FAIL"; exit 1; fi
ls -l "$B/glprobe"

echo ""
echo "=== 3. 起 Android 侧服务端（bionic，root）==="
pkill glproxy-server 2>/dev/null
sleep 1
rm -f "$RT/glproxy.sock"
chmod 755 /data/local/tmp/glproxy/glproxy-server 2>/dev/null
setsid /data/local/tmp/glproxy/glproxy-server "$RT/glproxy.sock" > /data/local/tmp/glproxy.log 2>&1 < /dev/null &
sleep 2
if pgrep glproxy-server > /dev/null 2>&1; then echo "服务端已启动 pid=$(pidof glproxy-server)"; else echo "!! 服务端没起来"; tail -10 /data/local/tmp/glproxy.log; fi
ls -l "$RT/glproxy.sock" 2>&1

echo ""
echo "=== 4. 把 runtime 目录绑进 chroot（chroot 内就是 /run/anland）==="
mkdir -p "$R/run/anland"
grep -q " $R/run/anland " /proc/mounts || mount --bind "$RT" "$R/run/anland"
grep -q " $R/run/anland " /proc/mounts && echo "已绑定" || echo "!! 绑定失败"

echo ""
echo "=== 5. 跑探针（chroot 内，连 /run/anland/glproxy.sock）==="
chroot "$R" /usr/bin/env -i \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
  GLPROXY_SOCK=/run/anland/glproxy.sock \
  /build/glproxy/glprobe 2>&1 | tee /data/local/tmp/glprobe.out

echo ""
echo "=== 6. 服务端日志 ==="
tail -15 /data/local/tmp/glproxy.log 2>&1
echo "GLPROXY-RUN-DONE"
} > "$LOG" 2>&1
