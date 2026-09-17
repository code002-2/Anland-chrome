#!/system/bin/sh
# set-fullscreen.sh —— 让窗口占满屏幕。
#
# 根因：守护进程 config.json 缺省是 init_w=800 / init_h=600（#33 的占位默认值），
# 它给新 toplevel 的 initial configure 就是 800x600 → Chrome 的窗口天生只有 800x600，
# 于是"没有全屏"（不是缩放/比例的问题，是窗口请求尺寸的问题）。
# 这里按 wm size 的物理分辨率写进去，并保持 scale_mode=1 (FIT)。
set -u
M=/data/adb/modules/anland-awl
T=/data/local/tmp

# 取物理分辨率（"Physical size: 1216x2688"）
WH=$(wm size 2>/dev/null | sed -n 's/.*Physical size: \([0-9]*x[0-9]*\).*/\1/p' | tail -1)
W=${WH%x*}
H=${WH#*x}
case "$W" in ''|*[!0-9]*) W=1216; H=2688; echo "wm size 取不到，用 1216x2688";; esac
echo "屏幕: ${W}x${H}"

cat > "$M/config.json" <<EOF
{
  "runtime_dir": "$T/awl",
  "socket_listen": 1,
  "scale_mode": 1,
  "auto_attach": 0,
  "sc_enabled": 1,
  "zoom": 100,
  "init_w": $W,
  "init_h": $H
}
EOF
chmod 644 "$M/config.json" 2>/dev/null
echo "--- config.json ---"; cat "$M/config.json"

echo "--- 重启守护进程（配置只在启动时读）---"
pkill waylandbridge 2>/dev/null
sleep 1
rm -f "$T/awl/wayland-0" "$T/awl/anland-wm.sock" 2>/dev/null
cd "$M" || exit 1
setsid ./waylandbridge > "$T/awl_daemon.log" 2>&1 < /dev/null &
sleep 3
if pidof waylandbridge >/dev/null 2>&1; then echo "DAEMON-OK"; else echo "DAEMON-FAIL"; fi
echo "--- 守护进程日志（应看到 init/zoom/scale_mode 生效）---"
logcat -d -s anland-daemon -s anland-wl 2>/dev/null | tail -14
