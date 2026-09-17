#!/system/bin/sh
# rf-prune2.sh —— 第二轮精简：干掉跟 Chrome 无关的桌面/多媒体/开发栈
#
# 保留原则：Chrome 的 .deb 依赖闭包（nss/nspr/cups/dbus/atk/atspi/xkbcommon/x11 系/
# gbm/pango/cairo/asound/vulkan）+ 我们自己的工具（Xwayland / anland-miniwm / pactl /
# bash / coreutils）+ 字体（拉丁 + CJK）。
# 验证手段：删完跑 ldd（chrome / Xwayland / anland-miniwm / pactl 都不能有 not found），
# 再实际启动一次 Chrome —— dlopen 的库 ldd 看不出来，只有真跑才算数。
set -u
R=/data/local/tmp/rf-prune/root
L=$R/usr/lib/aarch64-linux-gnu
LOG=/data/local/tmp/rf-prune2.log

du_() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1; }
del() {
  for p in "$@"; do
    if [ -e "$p" ]; then
      echo "  删 $(du_ "$p")	$(echo "$p" | sed "s|$R||")"
      rm -rf "$p"
    fi
  done
}
# 按 glob 删（先报总大小）
delglob() {
  label="$1"; shift
  sz=0; n=0
  for p in "$@"; do [ -e "$p" ] && { sz=$((sz + $(du -sk "$p" 2>/dev/null | cut -f1))); n=$((n+1)); rm -rf "$p"; }; done
  echo "  删 ${sz}K ($((sz/1024))M) 共 $n 项	$label"
}

{
  echo "=== 第二轮开始，精简前 ==="
  du -sh "$R"

  echo ""
  echo "=== A. Qt / KDE / Plasma（跟 Chrome 无关的桌面栈）==="
  del "$R/usr/lib/aarch64-linux-gnu/qt5" "$R/usr/lib/aarch64-linux-gnu/qt6" \
      "$R/usr/share/qt5" "$R/usr/share/qt6" "$R/usr/share/plasma" "$R/usr/share/kservices6" \
      "$R/usr/share/kservices5" "$R/usr/share/color-schemes" "$R/usr/share/knotifications6" \
      "$R/usr/share/kglobalaccel" "$R/usr/share/knsrcfiles" "$R/usr/share/konsole" \
      "$R/etc/xdg/plasma-workspace" "$R/etc/xdg/autostart"
  delglob "libKF6*/libQt6*/libQt5*/libkwin*/libplasma*" \
      "$L"/libKF6* "$L"/libQt6* "$L"/libQt5* "$L"/libkwin* "$L"/libplasma* "$L"/libkdeinit6* \
      "$L"/libkworkspace* "$L"/libKScreenLocker* "$L"/liblayer-shell-qt* "$L"/libkpipewire* \
      "$L"/libkglobalacceld* "$L"/libkdecorations* "$L"/libkfontinst* "$L"/libnotificationmanager* \
      "$L"/libtaskmanager* "$L"/libweather_ion* "$L"/libmilou* "$L"/libkicker* "$L"/libklipper* \
      "$L"/libsystemstats* "$L"/libplasmaclock* "$L"/libbreeze* "$L"/libkdecoration* "$L"/liboxygen*
  delglob "KDE/Plasma 可执行" \
      "$R"/usr/bin/plasmashell "$R"/usr/bin/kwin* "$R"/usr/bin/plasma* "$R"/usr/bin/kstart* \
      "$R"/usr/bin/kded6 "$R"/usr/bin/ksmserver "$R"/usr/bin/ksplash* "$R"/usr/bin/kglobalacceld \
      "$R"/usr/bin/kaccess "$R"/usr/bin/kwrited "$R"/usr/bin/baloo* "$R"/usr/bin/dolphin \
      "$R"/usr/bin/kfind "$R"/usr/bin/kate* "$R"/usr/bin/konsole "$R"/usr/bin/spectacle \
      "$R"/usr/bin/kwrite "$R"/usr/bin/kdesu "$R"/usr/bin/kdeconnect* "$R"/usr/bin/systemsettings \
      "$R"/usr/bin/kmenuedit "$R"/usr/bin/krunner "$R"/usr/bin/kdialog "$R"/usr/bin/keditbookmarks

  echo ""
  echo "=== B. ffmpeg / 多媒体编解码（Chrome 自带 ffmpeg）==="
  delglob "ffmpeg 系" \
      "$L"/libavcodec* "$L"/libavformat* "$L"/libavutil* "$L"/libavfilter* "$L"/libavdevice* \
      "$L"/libswscale* "$L"/libswresample* "$L"/libpostproc* "$L"/libx264* "$L"/libx265* \
      "$L"/libplacebo* "$L"/libcodec2* "$L"/libvidstab* "$L"/libzvbi* "$L"/libdc1394* \
      "$L"/libopenmpt* "$L"/libchromaprint* "$L"/librabbitmq* "$L"/librubberband* \
      "$L"/libass* "$L"/libbs2b* "$L"/libflite* "$L"/libgme* "$L"/libgsm* "$L"/libmp3lame* \
      "$L"/libopencore-amr* "$L"/libshine* "$L"/libspeex* "$L"/libtwolame* "$L"/libwavpack* \
      "$L"/libsrt* "$L"/libudfread* "$L"/libbluray* "$L"/libmodplug* "$L"/libmysofa* \
      "$L"/libaom* "$L"/libdav1d* "$L"/librav1e* "$L"/libSvtAv1* "$L"/libvpx* "$L"/libtheora* \
      "$L"/libvorbis* "$L"/libogg* "$L"/libopus* "$L"/libmpg123* "$L"/libsndfile* "$L"/libsoxr*
  del "$R/usr/share/ffmpeg" "$R/usr/share/glmark2" "$R/usr/bin/ffmpeg" "$R/usr/bin/ffprobe" \
      "$R/usr/bin/ffplay" "$R/usr/bin/glmark2*" "$R/usr/bin/vulkaninfo" "$R/usr/bin/gst-*" \
      "$R/usr/bin/gstreamer*" "$L/gstreamer-1.0" "$R/usr/lib/gstreamer-1.0"
  delglob "gstreamer 插件" "$L"/gstreamer* "$R"/usr/lib/aarch64-linux-gnu/libgst* "$L"/libgstreamer*

  echo ""
  echo "=== C. 开发工具链 / 调试器（不要编译器，apt 里随时能装回来）==="
  del "$R/usr/libexec/gcc" "$R/usr/libexec/valgrind" "$R/usr/share/gcc" \
      "$R/usr/bin/gdb" "$R/usr/bin/gdbserver" "$R/usr/bin/gcc"* "$R/usr/bin/g++"* \
      "$R/usr/bin/aarch64-linux-gnu-gcc"* "$R/usr/bin/aarch64-linux-gnu-g++"* \
      "$R/usr/bin/aarch64-linux-gnu-cpp"* "$R/usr/bin/aarch64-linux-gnu-ld"* \
      "$R/usr/bin/aarch64-linux-gnu-as"* "$R/usr/bin/aarch64-linux-gnu-run" \
      "$R/usr/bin/cpp"* "$R/usr/bin/make" "$R/usr/bin/cmake" "$R/usr/bin/git" \
      "$R/usr/bin/pebble" "$R/usr/bin/fastfetch" "$R/usr/bin/ninja" "$R/usr/bin/meson" \
      "$R/usr/bin/perf" "$R/usr/bin/strace" "$R/usr/bin/ltrace" "$R/usr/bin/objdump" \
      "$R/usr/bin/readelf" "$R/usr/bin/nm" "$R/usr/bin/ar" "$R/usr/bin/ranlib" \
      "$R/usr/bin/strings" "$R/usr/bin/addr2line" "$R/usr/bin/size" "$R/usr/bin/elfedit" \
      "$L/libgcc"*.so* "$L/libstdc++"*.so* "$L/libcc1"* "$L/libgomp"* "$L/libitm"* \
      "$L/libasan"* "$L/libtsan"* "$L/libubsan"* "$L/liblsan"* "$L/libatomic"* "$L/libquadmath"*

  echo ""
  echo "=== D. 服务端杂项（samba / systemd / xtables / python 残留 / gconv）==="
  del "$L/samba" "$L/systemd" "$L/xtables" "$L/libpython3.14.so.1.0" \
      "$R/usr/lib/python3.14" "$R/usr/lib/python3" "$R/usr/bin/python3.14" \
      "$R/usr/lib/systemd" "$R/usr/bin/systemctl" "$R/usr/bin/journalctl" \
      "$R/lib/systemd" "$R/usr/share/dbus-1/system-services" \
      "$L/libsmbclient"* "$L/libsamba"* "$L/libwbclient"* "$L/libtevent"* "$L/libtdb"* \
      "$L/libldb"* "$L/libndr"* "$L/libsocket-blocking"* "$L/libcli-smb-common"*
  echo "  gconv（glibc 字符集转换，Chrome 用自带 ICU）:"
  delglob "gconv 大部分（保留 UTF-8/ASCII 相关）" \
      "$L"/gconv/lib*[!8].so "$L"/gconv/ANSI* "$L"/gconv/IBM* "$L"/gconv/ISO-8859* \
      "$L"/gconv/EUC-* "$L"/gconv/SJIS* "$L"/gconv/SHIFT* "$L"/gconv/BIG5* "$L"/gconv/GB* \
      "$L"/gconv/CP* "$L"/gconv/TSCII* "$L"/gconv/KOI8* "$L"/gconv/MAC* "$L"/gconv/ARMSCII* \
      "$L"/gconv/GEORGIAN* "$L"/gconv/TIS-620* "$L"/gconv/VISCII* "$L"/gconv/TCVN* \
      "$L"/gconv/HP-ROMAN* "$L"/gconv/BRF* "$L"/gconv/INTERNAL

  echo ""
  echo "=== E. 字体：只留 Sans CJK Regular（Serif/Bold 让 Chrome 自己合成）==="
  echo "  精简前: $(du_ "$R/usr/share/fonts")"
  del "$R/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc" \
      "$R/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc"
  # 只留 DejaVuSans / DejaVuSerif / DejaVuSansMono 的基础四个 + NotoSansCJK-Regular
  find "$R/usr/share/fonts" -type f 2>/dev/null | while read f; do
    case "$f" in
      *NotoSansCJK-Regular.ttc|*DejaVuSans.ttf|*DejaVuSans-Bold.ttf|*DejaVuSerif.ttf|\
      *DejaVuSansMono.ttf|*DejaVuSansMono-Bold.ttf) ;;
      *) rm -f "$f" ;;
    esac
  done
  echo "  精简后: $(du_ "$R/usr/share/fonts")"
  find "$R/usr/share/fonts" -type f 2>/dev/null | sed "s|$R||"

  echo ""
  echo "=== F. 其他杂项 ==="
  del "$R/usr/share/locale-langpack" "$R/usr/share/kconf_update" "$R/usr/share/kxmlgui5" \
      "$R/usr/share/knotifyrc" "$R/usr/share/kservicetypes5" "$R/usr/share/applications" \
      "$R/usr/share/mime" "$R/usr/share/metainfo" "$R/usr/share/thumbnailers" \
      "$R/usr/share/dbus-1" "$R/etc/xdg" "$R/usr/share/man-db" "$R/usr/share/pam" \
      "$R/usr/share/perl-base" "$R/usr/share/awk" "$R/usr/share/ca-certificates-java" \
      "$R/usr/lib/jvm" "$R/usr/share/java" "$R/usr/lib/mono" "$R/usr/share/doc-base"

  echo ""
  echo "=== 精简后 ==="
  du -sh "$R"
  echo "文件数: $(find "$R" -type f | wc -l)"

  echo ""
  echo "=== 依赖完整性检查（ldd，看有没有 not found）==="
  for b in /opt/google/chrome/chrome /usr/bin/Xwayland /usr/bin/anland-miniwm \
           /usr/bin/bash /usr/bin/pactl /usr/bin/es2_info /usr/bin/openssl; do
    if [ -x "$R$b" ]; then
      out=$(chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd "$b" 2>&1 | grep 'not found')
      if [ -n "$out" ]; then echo "  !! $b 缺库:"; echo "$out" | sed 's/^/       /'
      else echo "  ok  $b"; fi
    else
      echo "  --  $b 不存在"
    fi
  done
  echo "RF-PRUNE2-DONE"
} > "$LOG" 2>&1
