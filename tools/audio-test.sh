#!/system/bin/sh
# audio-test.sh —— 逐级验证 chroot → PulseAudio → Android 音频链路
set -u
R=/data/adb/anland-chrome/root
RT=/data/local/tmp/awl
PS=unix:/run/anland/pulse.sock

mkdir -p "$R/run/anland"
grep -q " $R/run/anland " /proc/mounts || mount --bind "$RT" "$R/run/anland"

echo "== 宿主侧 =="
ls -l "$RT/pulse.sock"
ps -A -o PID,USER,CMD | grep -E 'pulseaudio' | grep -v grep

echo
echo "== chroot 内 pactl info =="
chroot "$R" /usr/bin/env PULSE_SERVER="$PS" /usr/bin/pactl info 2>&1 | head -25

echo
echo "== sinks（输出设备） =="
chroot "$R" /usr/bin/env PULSE_SERVER="$PS" /usr/bin/pactl list short sinks 2>&1

echo
echo "== sink-inputs（当前在放音的流） =="
chroot "$R" /usr/bin/env PULSE_SERVER="$PS" /usr/bin/pactl list short sink-inputs 2>&1

echo
echo "== 音量/静音状态 =="
chroot "$R" /usr/bin/env PULSE_SERVER="$PS" /usr/bin/pactl list sinks 2>&1 | grep -E 'Name:|Volume:|Mute:|State:' | head -12

echo
echo "== 试放铃声（设备应该响） =="
ls "$R/usr/share/sounds/freedesktop/stereo/" 2>/dev/null | head -6
chroot "$R" /usr/bin/env PULSE_SERVER="$PS" /usr/bin/paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>&1
echo "paplay exit=$?"

echo
echo "== Android 侧媒体音量 =="
media volume --stream 3 --get 2>&1 | head -3
