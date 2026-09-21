#!/system/bin/sh
# dev-gl-retry.sh -- 同一个服务端上连跑 5 次客户端：看是不是"第一次失败、重试就成"
RT=/data/local/tmp/awl
APKSRV=$(ls /data/app/*/com.anland.appwrap*/lib/arm64/libglproxysrv.so 2>/dev/null | head -1)
NEW=/data/adb/anland-chrome/root-slim

pkill -f libglproxysrv 2>/dev/null; pkill -f glproxy-server 2>/dev/null; sleep 1
rm -f "$RT/glproxy.sock"
setsid "$APKSRV" "$RT/glproxy.sock" > /data/local/tmp/glproxy-retry.log 2>&1 < /dev/null &
sleep 3
echo "服务端 pid=$(pgrep -f libglproxysrv | head -1)"
mount | grep -q " $NEW/run/anland " || mount --bind "$RT" "$NEW/run/anland"
for i in 1 2 3 4 5; do
  echo "--- 第 $i 次 ---"
  chroot "$NEW" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root /tmp/glt/gltriangle 2>&1 | tail -6
  sleep 2
done
echo ""
echo "=== 服务端日志 ==="
logcat -d -s glproxy:* 2>/dev/null | tail -10
echo GLRETRY-DONE
