#!/system/bin/sh
# daemon-dedupe.sh —— 收掉重复的 waylandbridge 进程，只留一个。
#
# 为什么会攒下多个：反复重启守护进程时 pkill 在 App 的 su 上下文里未必杀得掉
# （域/命名空间不同，信号可能被静默拒绝）。多个守护进程会抢同一个 socket
# （各自 unlink+bind，最后一个赢），其余持着死客户端白吃内存。
echo "=== 清理前 ==="
ps -A -o PID,USER,CMD 2>/dev/null | grep waylandbridge | grep -v grep

M=/data/adb/modules/anland-awl
for p in $(pidof waylandbridge); do
  kill -9 "$p" 2>/dev/null || echo "  kill -9 $p 失败（权限？）"
done
sleep 1
echo "=== kill 之后 ==="
ps -A -o PID,USER,CMD 2>/dev/null | grep waylandbridge | grep -v grep || echo "  (全部清掉)"

rm -f /data/local/tmp/awl/wayland-0 /data/local/tmp/awl/anland-wm.sock 2>/dev/null
cd "$M" 2>/dev/null || exit 1
setsid ./waylandbridge > /data/local/tmp/awl_daemon.log 2>&1 < /dev/null &
i=0; while [ $i -lt 60 ]; do pgrep waylandbridge >/dev/null 2>&1 && break; sleep 0.25; i=$((i+1)); done
sleep 1
echo "=== 清理后（应该只有 1 个）==="
ps -A -o PID,USER,CMD 2>/dev/null | grep waylandbridge | grep -v grep
echo "进程数=$(pgrep waylandbridge | wc -l)"
logcat -d -s anland-daemon 2>/dev/null | tail -6
