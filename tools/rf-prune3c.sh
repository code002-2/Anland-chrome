#!/system/bin/sh
# rf-prune3c.sh -- 最后一刀：usr/bin 的大文件、usr/libexec 与 /usr/lib 残留目录、/usr/share 杂项
DST=/data/local/tmp/rf3/root
LOG=/data/local/tmp/rf-prune3c.log
SAVED=0

# usr/bin 里必须留的（注意 coreutils 那一百多个都是符号链接，find -type f 不会碰它们）
KEEPBIN="coreutils Xwayland bash tar find ps mawk sh dash busybox locale pactl ldconfig anland-miniwm"
# /usr/share 里整块保护的目录
PROTSHARE="fonts X11 xkeyboard-config-2 zoneinfo terminfo fontconfig alsa glib-2.0 dbus-1 mime icons pixmaps locale anland"

{
echo "=== A. usr/bin 里 >=64K 的普通文件，除了必须留的都删 ==="
cd "$DST/usr/bin" || exit 1
find . -maxdepth 1 -type f -size +64k 2>/dev/null | while read -r f; do
  n="${f#./}"
  keep=0
  for k in $KEEPBIN; do [ "$n" = "$k" ] && keep=1; done
  if [ $keep = 1 ]; then echo "  保 $n"; continue; fi
  sz=$(du -sk "$f" 2>/dev/null | cut -f1)
  echo "$sz usr/bin/$n" >> /data/local/tmp/rf3c-deleted.txt
  rm -f "$f"
  echo "  -${sz}K usr/bin/$n"
done

echo ""
echo "=== B. usr/libexec 与 /usr/lib 残留 ==="
for d in usr/libexec/sudo usr/libexec/udisks2 usr/libexec/geoclue usr/libexec/upowerd \
         usr/libexec/rust-coreutils usr/libexec/awk usr/libexec/gvfs-udisks2-volume-monitor \
         usr/libexec/gvfsd usr/libexec/gvfsd-fuse usr/libexec/gnome-keyring-daemon \
         usr/lib/apt usr/lib/android-sdk usr/lib/kf6 usr/lib/gnupg usr/lib/dpkg \
         usr/lib/pcrlock.d usr/lib/sysusers.d usr/lib/tmpfiles.d usr/lib/sysctl.d \
         usr/lib/kernel usr/lib/xorg usr/lib/libepub.so.0.2.1 usr/lib/cpp usr/lib/environment.d ; do
  [ -e "$DST/$d" ] || continue
  sz=$(du -sk "$DST/$d" 2>/dev/null | cut -f1)
  echo "$sz $d/" >> /data/local/tmp/rf3c-deleted.txt
  rm -rf "$DST/$d"
  echo "  -${sz}K $d/"
done
for f in "$DST"/usr/libexec/*; do
  [ -e "$f" ] || continue
  sz=$(du -sk "$f" 2>/dev/null | cut -f1)
  echo "$sz usr/libexec/${f##*/}" >> /data/local/tmp/rf3c-deleted.txt
  rm -rf "$f"
  echo "  -${sz}K usr/libexec/${f##*/}"
done

echo ""
echo "=== C. /usr/share 杂项（>=64K，保护 fonts/X11/xkeyboard/zoneinfo/terminfo…）==="
find "$DST/usr/share" -type f -size +64k 2>/dev/null | while read -r f; do
  rel="${f#$DST/usr/share/}"
  keep=0
  for pd in $PROTSHARE; do
    case "$rel" in $pd/*|$pd) keep=1 ;; esac
  done
  if [ $keep = 1 ]; then continue; fi
  sz=$(du -sk "$f" 2>/dev/null | cut -f1)
  echo "$sz usr/share/$rel" >> /data/local/tmp/rf3c-deleted.txt
  rm -f "$f"
  echo "  -${sz}K usr/share/$rel"
done
find "$DST/usr/share" -mindepth 1 -type d -empty -delete 2>/dev/null

echo ""
echo "=== D. 复查 ==="
CS="chroot $DST /usr/bin/env -i PATH=/usr/bin:/bin:/sbin:/usr/sbin HOME=/root"
for b in /opt/google/chrome/chrome /usr/bin/Xwayland /usr/lib/anland/Xwayland /usr/bin/anland-miniwm /usr/bin/pactl /usr/bin/coreutils /usr/bin/bash; do
  n=$($CS /usr/bin/ldd "$b" 2>&1 | grep -c 'not found')
  echo "  $b 缺 $n 个"
done
$CS /usr/bin/env echo "  env ok"
$CS /bin/sh -c 'echo "  sh ok"' 2>&1
$CS /opt/google/chrome/chrome --version 2>&1 | tail -1 | sed 's/^/  chrome: /'
$CS /usr/bin/bash -c 'echo "  bash ok"' 2>&1
echo "  断链总数: $(find "$DST" -type l 2>/dev/null | while read -r l; do [ -e "$l" ] || echo x; done | wc -l)"
echo ""
echo "=== E. 体积 ==="
du -sh "$DST"
echo "文件数: $(find "$DST" -type f | wc -l)"
echo "本刀合计: $(awk '{s+=$1} END {printf "%.0f", s/1024}' /data/local/tmp/rf3c-deleted.txt) MB / $(wc -l < /data/local/tmp/rf3c-deleted.txt) 项"
echo "RF3C-DONE"
} > "$LOG" 2>&1
echo "logged to $LOG"
