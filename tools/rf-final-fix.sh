#!/system/bin/sh
# rf-final-fix.sh —— 收尾：补 libmp3lame 的符号链接，复查 pactl / chrome 依赖
SRC=/data/adb/anland-chrome/root/usr/lib/aarch64-linux-gnu
DST=/data/local/tmp/rf-prune/root/usr/lib/aarch64-linux-gnu
R=/data/local/tmp/rf-prune/root

for f in libmp3lame.so libmp3lame.so.0 libmp3lame.so.0.0.0; do
  [ -e "$SRC/$f" ] && cp -a "$SRC/$f" "$DST/" 2>/dev/null
done
echo "--- libmp3lame ---"
ls -l "$DST" | grep mp3lame

echo "--- 依赖复查（not found 计数，都是 0 才好）---"
for b in /usr/bin/pactl /usr/bin/env /usr/bin/coreutils /opt/google/chrome/chrome \
         /usr/bin/anland-miniwm /usr/bin/Xwayland; do
  n=$(chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd "$b" 2>&1 | grep -c 'not found')
  echo "  $b → $n"
done

echo "--- xkb 自检（xkbcommon 需要 rules/evdev）---"
ls -l "$R/usr/share/X11/xkb/rules/evdev" 2>&1
echo "--- pactl 实跑 ---"
chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin PULSE_SERVER=unix:/run/anland/pulse.sock \
  /usr/bin/pactl list short sinks 2>&1 | head -3
echo "--- 大小 ---"
du -sh "$R"
echo "RF-FINAL-FIX-DONE"
