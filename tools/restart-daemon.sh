#!/system/bin/sh
# restart-daemon.sh —— 可靠地重启 waylandbridge（su 会话退出时不会把它带走）
set -u
M=/data/adb/modules/anland-awl

pkill waylandbridge 2>/dev/null
sleep 1

# 确保可执行 + 标签（模块的 service.sh 也是这么做的）
chmod 755 "$M/waylandbridge" 2>/dev/null
chcon u:object_r:awl_daemon_exec:s0 "$M/waylandbridge" 2>/dev/null

# setsid 脱离当前会话，重定向 stdio，避免被 su/sh 退出时收走
cd "$M" || exit 1
setsid ./waylandbridge > /data/local/tmp/awl_daemon.log 2>&1 < /dev/null &
sleep 3

echo "== 进程 =="
ps -A -o PID,USER,CMD | grep waylandbridge | grep -v grep || echo "!! 没起来"

echo "== 套接字 =="
ls -l /data/local/tmp/awl/wayland-0 2>&1

echo "== 日志 =="
tail -12 /data/local/tmp/awl_daemon.log 2>&1
