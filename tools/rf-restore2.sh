#!/system/bin/sh
# rf-restore2.sh —— 补回 pulse 客户端链路需要的库（pactl 要 libsndfile 等）
SRC=/data/adb/anland-chrome/root/usr/lib/aarch64-linux-gnu
DST=/data/local/tmp/rf-prune/root/usr/lib/aarch64-linux-gnu
for pat in libsndfile.so libFLAC.so libvorbis.so libvorbisenc.so libogg.so libopus.so \
           libmpg123.so libmp3lame.so libspeex.so libsoxr.so libasyncns.so; do
  for f in "$SRC/$pat"*; do
    [ -e "$f" ] || continue
    cp -a "$f" "$DST/" && echo "补 $(basename "$f")"
  done
done

R=/data/local/tmp/rf-prune/root
echo "--- 检查 ---"
for b in /usr/bin/pactl /opt/google/chrome/chrome /usr/bin/env; do
  out=$(chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd "$b" 2>&1 | grep 'not found')
  [ -n "$out" ] && { echo "  !! $b"; echo "$out" | sed 's/^/      /'; } || echo "  ok  $b"
done
