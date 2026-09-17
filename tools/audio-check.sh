#!/system/bin/sh
# audio-check.sh —— 验证「chroot 里的 Chrome → PulseAudio → Android」这条链路是不是真的在出声。
# 必须经 App 的远程钩子跑：pulse.sock 所在目录（runtime_dir）只在 App 的 mount namespace
# 里被 bind 到 rootfs 的 /run/anland，adb shell 的 su 看不到 → 会报 "Connection refused"。
R=/data/adb/anland-chrome/root

pactl_() {
  chroot "$R" /usr/bin/env -i PULSE_SERVER=unix:/run/anland/pulse.sock /usr/bin/pactl "$@" 2>&1
}

echo "=== sink-inputs（Chrome 播放时应该能看到它的流）==="
pactl_ list short sink-inputs
echo "=== sinks（状态 RUNNING 表示真有音频在跑）==="
pactl_ list short sinks
pactl_ list sinks | grep -E 'State:|Name:|Mute:|Volume: front-left' | head -8
echo "=== 播放器进程占 CPU（软件解码时会明显）==="
top -n 1 -b 2>/dev/null | grep chrome | head -3
echo "=== 窗口挂载情况 ==="
logcat -d -s appwrap:* 2>/dev/null | grep -E '窗口创建|挂载窗口|窗口已挂载' | tail -6
echo "=== 稳定性 ==="
echo "surfaceflinger=$(pidof surfaceflinger)  chrome进程=$(pgrep chrome | wc -l)  SkImage异常=$(logcat -d -b crash | grep -c 'Unable to generate SkImage')"
