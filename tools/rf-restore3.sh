#!/system/bin/sh
# rf-restore3.sh —— 补 xkb 键盘布局数据 + pulse 客户端库，然后复查
SRC=/data/adb/anland-chrome/root
DST=/data/local/tmp/rf-prune/root
L_SRC=$SRC/usr/lib/aarch64-linux-gnu
L_DST=$DST/usr/lib/aarch64-linux-gnu

echo "=== xkb 数据对比 ==="
echo "原 rootfs:   $(du -sh "$SRC/usr/share/X11/xkb" 2>/dev/null | cut -f1)  文件数 $(find "$SRC/usr/share/X11/xkb" -type f 2>/dev/null | wc -l)"
echo "精简 rootfs: $(du -sh "$DST/usr/share/X11/xkb" 2>/dev/null | cut -f1)  文件数 $(find "$DST/usr/share/X11/xkb" -type f 2>/dev/null | wc -l)"

if [ -d "$SRC/usr/share/X11/xkb" ] && [ "$(find "$SRC/usr/share/X11/xkb" -type f 2>/dev/null | wc -l)" -gt 0 ]; then
  echo "--- 补 xkb ---"
  rm -rf "$DST/usr/share/X11/xkb"
  mkdir -p "$DST/usr/share/X11/xkb"
  cp -a "$SRC/usr/share/X11/xkb/." "$DST/usr/share/X11/xkb/" && echo "  已补 $(du -sh "$DST/usr/share/X11/xkb" | cut -f1)"
else
  echo "!! 原 rootfs 里也没有有意义的数据 —— 说明 Chrome 用的是别处的 keymap（看 XKB_CONFIG_ROOT）"
fi

echo ""
echo "=== 补 pulse 客户端库 ==="
for pat in libsndfile.so libFLAC.so libvorbis.so libvorbisenc.so libogg.so libopus.so \
           libmpg123.so libsoxr.so libasyncns.so; do
  for f in "$L_SRC/$pat"*; do
    [ -e "$f" ] || continue
    cp -a "$f" "$L_DST/" && echo "  补 $(basename "$f")"
  done
done

echo ""
echo "=== 复查 ldd ==="
for b in /usr/bin/env /usr/bin/pactl /opt/google/chrome/chrome /usr/bin/anland-miniwm /usr/bin/Xwayland; do
  out=$(chroot "$DST" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd "$b" 2>&1 | grep 'not found')
  [ -n "$out" ] && { echo "  !! $b"; echo "$out" | sed 's/^/      /'; } || echo "  ok  $b"
done

echo ""
echo "=== xkbcommon 能不能建出 keymap（真正决定 Chrome 能否启动）==="
chroot "$DST" /usr/bin/env -i PATH=/usr/bin:/bin HOME=/root \
  /usr/bin/python3 -c 'print(1)' 2>/dev/null || true
# 用 chrome 自己跑一次最干净的验证：只做启动、打到日志
chroot "$DST" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  HOME=/root XDG_RUNTIME_DIR=/tmp /opt/google/chrome/chrome --version 2>&1 | tail -3
echo "RF-RESTORE3-DONE"
