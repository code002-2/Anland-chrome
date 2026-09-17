#!/system/bin/sh
# rf-fixdeps.sh —— 按 ldd 的结果**自动**把缺失的库从原 rootfs 补回来。
# 不再靠人肉猜哪个库能删：先删，再让 ldd 说缺什么，缺什么补什么，直到干净。
# 同时恢复被我误删的 X11 数据（原 rootfs 里 /usr/share/X11/xkb 是符号链接，
# find -type f 数出来 0 个文件，所以精简脚本把它当零字节垃圾删掉了 —— 教训：
# 判断"是不是空目录"要用 ls -la 看符号链接，不能只看 find 计数）。
SRC=/data/adb/anland-chrome/root
DST=/data/local/tmp/rf-prune/root
LSRC=$SRC/usr/lib/aarch64-linux-gnu
LDST=$DST/usr/lib/aarch64-linux-gnu
LOG=/data/local/tmp/rf-fixdeps.log

{
echo "=== 1. 恢复 X11 数据（含 xkb 符号链接）==="
echo "原: $(ls -ld "$SRC/usr/share/X11" 2>/dev/null)"
echo "原 xkb: $(ls -ld "$SRC/usr/share/X11/xkb" 2>/dev/null)"
rm -rf "$DST/usr/share/X11"
mkdir -p "$DST/usr/share"
cp -a "$SRC/usr/share/X11" "$DST/usr/share/" 2>/dev/null
echo "补后: $(ls -ld "$DST/usr/share/X11/xkb" 2>/dev/null)"
echo "     $(ls -l "$DST/usr/share/X11/xkb/rules/evdev"* 2>/dev/null | head -3)"

echo ""
echo "=== 2. 按 ldd 自动补库 ==="
fix() {
  bin="$1"; round=0
  while [ $round -lt 8 ]; do
    miss=$(chroot "$DST" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd "$bin" 2>/dev/null \
           | awk '/not found/{print $1}' | sort -u)
    [ -z "$miss" ] && { echo "  ok  $bin"; return 0; }
    round=$((round+1))
    for m in $miss; do
      f=$(find "$LSRC" -maxdepth 1 -name "$m" -o -maxdepth 1 -name "$m.*" 2>/dev/null | head -1)
      if [ -n "$f" ]; then
        cp -a "$f" "$LDST/" && echo "  补 $(basename "$f")  (for $bin)"
      else
        echo "  !! $m 在原 rootfs 里也找不到 —— $bin 需要它"
        return 1
      fi
    done
  done
  return 1
}
for b in /usr/bin/env /usr/bin/coreutils /usr/bin/pactl /usr/bin/es2_info /usr/bin/eglinfo \
         /usr/bin/bash /usr/bin/Xwayland /usr/bin/anland-miniwm /opt/google/chrome/chrome; do
  [ -e "$DST$b" ] && fix "$b"
done

echo ""
echo "=== 3. 复查 ==="
for b in /usr/bin/pactl /opt/google/chrome/chrome /usr/bin/env; do
  out=$(chroot "$DST" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd "$b" 2>&1 | grep 'not found')
  [ -n "$out" ] && { echo "  !! $b"; echo "$out" | sed 's/^/      /'; } || echo "  ok  $b"
done
chroot "$DST" /opt/google/chrome/chrome --version 2>&1 | tail -1
echo "大小: $(du -sh "$DST" 2>/dev/null | cut -f1)"
echo "RF-FIXDEPS-DONE"
} > "$LOG" 2>&1
