#!/system/bin/sh
# dev-gl-rootcause.sh -- 决定性实验：服务端在"App 的 mount namespace"里起 vs 在全局 namespace 里起
RT=/data/local/tmp/awl
APKSRV=$(ls /data/app/*/com.anland.appwrap*/lib/arm64/libglproxysrv.so 2>/dev/null | head -1)
NEW=/data/adb/anland-chrome/root-slim
APP=com.anland.appwrap

echo "=== 0. 把 gltriangle 链的开发期壳换成当前壳 ==="
for R in /data/adb/anland-chrome/root "$NEW"; do
  mkdir -p "$R/opt/glproxy/lib"
  cp -f "$R/usr/lib/aarch64-linux-gnu/libEGL.so.1.1.0" "$R/opt/glproxy/lib/libEGL.so.1"
  cp -f "$R/usr/lib/aarch64-linux-gnu/libGLESv2.so.2.1.0" "$R/opt/glproxy/lib/libGLESv2.so.2"
  echo "  $R/opt/glproxy/lib -> $(md5sum $R/opt/glproxy/lib/libEGL.so.1 | cut -c1-8) / 系统壳 $(md5sum $R/usr/lib/aarch64-linux-gnu/libEGL.so.1.1.0 | cut -c1-8)"
done
mount | grep -q " $NEW/run/anland " || mount --bind "$RT" "$NEW/run/anland"
cp -f /data/adb/anland-chrome/root/build/glproxy/gltriangle "$NEW/tmp/glt/gltriangle" 2>/dev/null
chmod 755 "$NEW/tmp/glt/gltriangle"

tri() { chroot "$NEW" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root /tmp/glt/gltriangle 2>&1 | tail -7; }
srv_kill() { pkill -f libglproxysrv 2>/dev/null; pkill -f glproxy-server 2>/dev/null; sleep 1; rm -f "$RT/glproxy.sock"; }

APPPID=$(pgrep -f $APP | head -1)
echo "  app pid=$APPPID mnt=$(readlink /proc/$APPPID/ns/mnt)  我的 mnt=$(readlink /proc/self/ns/mnt)"

echo ""
echo "=== A. 服务端起在【全局 namespace】（adb 直起）==="
srv_kill
setsid "$APKSRV" "$RT/glproxy.sock" > /data/local/tmp/glproxy-A.log 2>&1 < /dev/null &
sleep 2
echo "  pid=$(pgrep -f libglproxysrv | head -1) mnt=$(readlink /proc/$(pgrep -f libglproxysrv | head -1)/ns/mnt)"
tri

echo ""
echo "=== B. 服务端起在【App 的 namespace】里（复现 App 的行为）==="
srv_kill
setsid nsenter -t "$APPPID" -m -- "$APKSRV" "$RT/glproxy.sock" > /data/local/tmp/glproxy-B.log 2>&1 < /dev/null &
sleep 2
echo "  pid=$(pgrep -f libglproxysrv | head -1) mnt=$(readlink /proc/$(pgrep -f libglproxysrv | head -1)/ns/mnt)"
tri

echo ""
echo "=== C. App 里改用 nsenter 进 init 的 namespace 起服务端 ==="
srv_kill
setsid nsenter -t "$APPPID" -m -- nsenter -t 1 -m -p -- "$APKSRV" "$RT/glproxy.sock" > /data/local/tmp/glproxy-C.log 2>&1 < /dev/null &
sleep 2
echo "  pid=$(pgrep -f libglproxysrv | head -1) mnt=$(readlink /proc/$(pgrep -f libglproxysrv | head -1)/ns/mnt)"
tri

echo ""
echo "=== D. logcat ==="
logcat -d -s glproxy:* 2>/dev/null | tail -8
echo GLROOTCAUSE-DONE
