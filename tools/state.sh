#!/system/bin/sh
# state.sh —— 一屏看清当前状态（pidof 比 ps 可靠：这个上下文里 ps 看不到别的进程 cmdline）
echo "waylandbridge: $(pidof waylandbridge)"
echo "  个数=$(pidof waylandbridge | wc -l)"
echo "chrome: $(pgrep chrome | wc -l) 个进程"
echo "relay: $(pidof libawlrelay)"
echo "surfaceflinger: $(pidof surfaceflinger)"
echo "app: $(pidof com.anland.appwrap)"
echo "音频 sink:"
chroot /data/adb/anland-chrome/root /usr/bin/env -i PULSE_SERVER=unix:/run/anland/pulse.sock \
  /usr/bin/pactl list short sinks 2>&1 | head -3
echo "守护进程日志尾部:"
logcat -d -s anland-daemon 2>/dev/null | tail -3
