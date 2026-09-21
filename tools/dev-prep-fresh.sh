#!/system/bin/sh
# dev-prep-fresh.sh -- 造出"全新安装"的现场：干掉 Chrome/中继，把在用的 rootfs 挪走留备份
echo "=== 1. 停掉 chrome / 中继 / Xwayland / miniwm ==="
pkill chrome 2>/dev/null; pkill chrome_crashpad 2>/dev/null
pkill libawlrelay.so 2>/dev/null; pkill Xwayland 2>/dev/null; pkill anland-miniwm 2>/dev/null
sleep 2
pgrep -l chrome 2>/dev/null | head -3
echo "=== 2. 把 root-slim 挪成备份 ==="
if [ -d /data/adb/anland-chrome/root-slim ]; then
  rm -rf /data/adb/anland-chrome/root-slim.v02bak
  mv /data/adb/anland-chrome/root-slim /data/adb/anland-chrome/root-slim.v02bak
fi
ls -l /data/adb/anland-chrome/
df -h /data | tail -1
echo PREPOK
