#!/system/bin/sh
# rf-prune3b.sh -- 第三轮精简的"扫尾"：在白名单之外的大文件里再扫一遍
#
# 逻辑：
#   保护表 = 依赖白名单(keep.txt) 里的库名
#          + 白名单符号链接解析出来的"真身"文件名（例如 keep 里有 libsqlite3.so.0，
#            它的真身 libsqlite3.so.0.8.6 也必须留）
#          + 一份"dlopen 敏感"前缀黑名单（pulse/alsa/nss/wayland/gtk/gbm…）
#   然后扫 /usr/lib/aarch64-linux-gnu、/usr/lib、/usr/share 里 >=64K 的文件，
#   不在保护表里的删掉。目录级保护：gconv/alsa-lib/nss/gdk-pixbuf-2.0/gtk-3.0/gio。
set -u
DST=/data/local/tmp/rf3/root
KEEP=/data/local/tmp/rf3/keep.txt
PROTF=/data/local/tmp/rf3/protect.txt
LOG=/data/local/tmp/rf-prune3b.log
SAVED=0

DENY='^(libEGL|libGLESv2|libgbm|libdrm|libsqlite3|libsoftokn|libfreebl|libnssckbi|libnssdbm|libnsssysinit|libpulse|libasound|libgdbm|libtdb|libltdl|libpipewire|libwireplumber|libspa|liborc|libwebrtc|libspeex|libsamplerate|libsoxr|libfftw3|libsndfile|libFLAC|libogg|libvorbis|libopus|libmp3lame|libmpg123|libapparmor|libasyncns|libcap|libwayland|libxkbcommon|libgtk|libgdk|libgdk_pixbuf|libglib|libgio|libgmodule|libgobject|libpango|libatk|libcairo|libpixman|libfontconfig|libfreetype|libexpat|libpng|libharfbuzz|libgraphite2|libfribidi|libthai|libdatrie|libX|libxcb|libnss|libnspr|libudev|libsystemd|libcups|libavahi|libgnutls|libnettle|libhogweed|libp11-kit|libtasn1|libunistring|libidn2|libgmp|libkrb5|libk5crypto|libkrb5support|libgssapi|libcom_err|libkeyutils|libbrotli|libbz2|liblzma|libz\.|libzstd|libstdc|libgcc|libmvec|libselinux|libpcre2|libmount|libblkid|libuuid|libacl|libattr|libtinfo|libncurses|libepoxy|libGL|libGLX|libGLdispatch|libdecor|libei\.|liboeffis|libgcrypt|libgpg-error|libXfont|libfontenc|libtirpc|libxcvt|libxshmfence|libtalloc)'

PROT_DIRS="gconv alsa-lib nss gdk-pixbuf-2.0 gtk-3.0 gio anland fonts X11 xkeyboard-config-2 zoneinfo terminfo fontconfig alsa glib-2.0 dbus-1"

{
echo "=== 1. 建保护表 ==="
cp "$KEEP" "$PROTF"
iskep() { grep -qxF "$1" "$KEEP" 2>/dev/null; }
addprot() { echo "$1" >> "$PROTF"; }
# 两轮解析符号链接真身
pass=0
while [ $pass -lt 2 ]; do
  pass=$((pass+1))
  for d in "$DST/usr/lib/aarch64-linux-gnu" "$DST/usr/lib" "$DST/lib" "$DST/usr/bin" "$DST/bin" "$DST/usr/sbin" "$DST/sbin"; do
    [ -d "$d" ] || continue
    for l in "$d"/*; do
      [ -L "$l" ] || continue
      bn="${l##*/}"
      iskep "$bn" || continue
      t=$(readlink "$l")
      case "$t" in
        /*) tgt="$DST$t" ;;
        *)  tgt="$(dirname "$l")/$t" ;;
      esac
      if [ -e "$tgt" ]; then addprot "${tgt##*/}"; fi
    done
  done
done
sort -u "$PROTF" -o "$PROTF"
echo "  保护表 $(wc -l < "$PROTF") 条"

isprot() {
  grep -qxF "$1" "$PROTF" 2>/dev/null && return 0
  echo "$1" | grep -qE "$DENY" && return 0
  return 1
}
indir() {
  for pd in $PROT_DIRS; do
    case "$1" in */$pd/*|*/$pd) return 0 ;; esac
  done
  return 1
}

echo ""
echo "=== 2. 扫描删除（>=64K，且不在保护表里）==="
: > /data/local/tmp/rf3b-deleted.txt
# 只扫 aarch64-linux-gnu 这个库目录（这里才是大头）；/usr/lib 下别的目录与 /usr/share 用显式清单，
# 免得扫掉 /usr/lib/anland/Xwayland、/usr/share/fonts 这类"不是库但必须留"的东西。
find "$DST/usr/lib/aarch64-linux-gnu" -type f -size +64k 2>/dev/null | while read -r f; do
  rel="${f#$DST}"
  indir "$rel" && continue
  isprot "${f##*/}" && continue
  sz=$(du -sk "$f" 2>/dev/null | cut -f1)
  echo "$sz $rel" >> /data/local/tmp/rf3b-deleted.txt
  rm -f "$f"
done
for d in usr/share/qalculate usr/share/kwin-wayland usr/share/libmysofa usr/share/xml \
         usr/share/metainfo usr/share/applications usr/share/kservices6 usr/share/kxmlgui5 \
         usr/share/knotifications6 usr/share/kglobalaccel5 usr/share/plasma usr/share/kpackage \
         usr/share/kconf_update usr/share/knsrcfiles usr/share/konsole usr/share/katepart5 \
         usr/share/color-schemes usr/share/aurorae usr/share/ksplash usr/share/kstyle \
         usr/share/ksysguard usr/share/kaccounts usr/share/kdevappwizard usr/share/kdevcppsupport \
         usr/share/pkgconfig usr/share/aclocal usr/share/gettext usr/share/gdb usr/share/vala \
         usr/share/gir-1.0 usr/lib/aarch64-linux-gnu/girepository-1.0 \
         usr/lib/aarch64-linux-gnu/vala usr/lib/aarch64-linux-gnu/qt-default \
         usr/lib/aarch64-linux-gnu/qtchooser usr/lib/environment.d usr/lib/cpp ; do
  [ -e "$DST/$d" ] || continue
  sz=$(du -sk "$DST/$d" 2>/dev/null | cut -f1)
  echo "$sz $d/" >> /data/local/tmp/rf3b-deleted.txt
  rm -rf "$DST/$d"
done
# 顺手清掉扫完变成空壳的目录（不删 lib 主目录本身）
find "$DST/usr/lib/aarch64-linux-gnu" -mindepth 1 -type d -empty -delete 2>/dev/null
echo "  删除条目 $(wc -l < /data/local/tmp/rf3b-deleted.txt) 个，合计 $(awk '{s+=$1} END {printf "%.0f", s/1024}' /data/local/tmp/rf3b-deleted.txt) MB"
echo "  --- 删掉的 40 个大头 ---"
sort -rn /data/local/tmp/rf3b-deleted.txt | head -40 | sed 's/^/    /'

echo ""
echo "=== 3. 复查 ==="
CS="chroot $DST /usr/bin/env -i PATH=/usr/bin:/bin:/sbin:/usr/sbin HOME=/root"
for b in /opt/google/chrome/chrome /usr/bin/Xwayland /usr/lib/anland/Xwayland /usr/bin/anland-miniwm /usr/bin/pactl /usr/bin/coreutils; do
  n=$($CS /usr/bin/ldd "$b" 2>&1 | grep -c 'not found')
  echo "  $b 缺 $n 个"
done
$CS /usr/bin/env echo "  env ok"
$CS /opt/google/chrome/chrome --version 2>&1 | tail -1 | sed 's/^/  chrome: /'
echo "  断链总数: $(find "$DST" -type l 2>/dev/null | while read -r l; do [ -e "$l" ] || echo x; done | wc -l)"
echo ""
echo "=== 4. 体积 ==="
du -sh "$DST"
echo "文件数: $(find "$DST" -type f | wc -l)"
echo "RF3B-DONE"
} > "$LOG" 2>&1
echo "logged to $LOG"
