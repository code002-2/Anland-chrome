#!/system/bin/sh
# set-daemon-config.sh —— 写守护进程 config.json 并重启它
#   scale_mode: 0=STRETCH(按轴拉伸, legacy) 1=FIT(等比缩放+黑边) 2=CENTER(1:1 居中, 超出裁掉)
#   auto_attach 保持 0（第三方 APK 自己挂窗口）
set -u
M=/data/adb/modules/anland-awl
CFG="$M/config.json"

echo "== 改前 =="
cat "$CFG" 2>/dev/null || echo "(无)"

cat > "$CFG" <<'EOF'
{
  "runtime_dir": "/data/local/tmp/awl",
  "socket_listen": 1,
  "scale_mode": 1,
  "auto_attach": 0,
  "sc_enabled": 1
}
EOF
chmod 644 "$CFG"
echo "== 改后 =="
cat "$CFG"

echo
echo "== 重启守护进程 =="
pkill waylandbridge 2>/dev/null
sleep 1
cd "$M" && nohup ./waylandbridge > /data/local/tmp/awl_daemon.log 2>&1 &
sleep 2
ps -A -o PID,CMD | grep waylandbridge | grep -v grep
echo "--- 守护进程日志尾部 ---"
tail -8 /data/local/tmp/awl_daemon.log 2>&1
