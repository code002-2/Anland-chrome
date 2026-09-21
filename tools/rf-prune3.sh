#!/system/bin/sh
# rf-prune3.sh -- 第三轮 rootfs 精简
#
# 思路（比前两轮更狠，但可验证）：
#   1) 在 /data/local/tmp/rf3 克隆一份 root-slim（排除运行期产物 /root/*、挂载点）
#   2) 先用 ldd 把"必须留"的库名收成一个白名单：
#        Chrome 本体 + /opt/google/chrome/*.so + 我们脚本要用的工具 + Xwayland/miniwm/pactl
#        + dlopen 才加载的目录（gconv / alsa-lib / nss / gdk-pixbuf / gtk-3.0 模块）
#      再手工补一批"按名字 dlopen"的库（wayland/egl/pulse/gtk…）
#   3) 删候选文件/目录时逐个查白名单：命中就跳过并打印"保 xxx"
#   4) 删完再跑一遍 ldd 复查，任何 "not found" 都会打出来
#
# 注意：本脚本只动克隆，不动 /data/adb/anland-chrome/root-slim 本身。
set -u
SRC=/data/adb/anland-chrome/root-slim
W=/data/local/tmp/rf3
DST=$W/root
LOG=/data/local/tmp/rf-prune3.log
KEEPF=$W/keep.txt
SAVED=0

{
echo "=== 0. 克隆（排除运行期产物与挂载点）==="
rm -rf "$W"; mkdir -p "$DST"
cd "$SRC" || exit 1
tar -cf - \
    --exclude='./root/*' \
    --exclude='./tmp/*' --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' \
    --exclude='./run/*' --exclude='./var/log/*' --exclude='./var/tmp/*' \
    --exclude='./var/cache/*' . 2>/dev/null \
  | ( cd "$DST" && tar -xf - 2>/dev/null )
echo "克隆完成: $(du -sh "$DST" 2>/dev/null | cut -f1)  文件数 $(find "$DST" -type f 2>/dev/null | wc -l)"

echo ""
echo "=== 1. 收集依赖白名单 ==="
: > "$KEEPF"
addk() { for n in "$@"; do echo "$n" >> "$KEEPF"; done; }
lddk() {
  [ -e "$DST$1" ] || return 0
  chroot "$DST" /usr/bin/env -i PATH=/usr/bin:/bin:/sbin:/usr/sbin \
      /usr/bin/ldd "$1" 2>/dev/null | awk '{print $1}' | grep '\.so' | sed 's|.*/||' >> "$KEEPF"
}
for b in /opt/google/chrome/chrome /usr/bin/pactl /usr/bin/Xwayland /usr/lib/anland/Xwayland \
         /usr/bin/anland-miniwm /usr/bin/bash /bin/sh /usr/bin/env /usr/bin/coreutils /usr/bin/tar \
         /usr/sbin/ldconfig /usr/bin/grep /usr/bin/sed /usr/bin/awk /usr/bin/find /usr/bin/du \
         /usr/bin/ps /usr/bin/pgrep /usr/bin/pkill /usr/bin/tee /usr/bin/date /usr/bin/dd \
         /usr/bin/stat /usr/bin/id /usr/bin/ls /usr/bin/cat /usr/bin/mkdir /usr/bin/rm /usr/bin/ln \
         /usr/bin/cp /usr/bin/mv /usr/bin/chmod /usr/bin/chown /usr/bin/sleep /usr/bin/head \
         /usr/bin/tail /usr/bin/sort /usr/bin/uniq /usr/bin/wc /usr/bin/cut /usr/bin/tr \
         /usr/bin/xargs /usr/bin/touch /usr/bin/true /usr/bin/which /usr/bin/readlink \
         /usr/bin/basename /usr/bin/dirname /usr/bin/nohup /usr/bin/setsid /usr/bin/timeout \
         /usr/bin/hostname /usr/bin/printf /usr/bin/seq /usr/bin/mktemp /usr/bin/expr \
         /usr/bin/df /usr/bin/mount /usr/bin/umount /usr/bin/kill /usr/bin/ldd; do
  lddk "$b"
done
for s in "$DST"/opt/google/chrome/*.so; do
  [ -e "$s" ] && lddk "/opt/google/chrome/${s##*/}"
done
# dlopen 才会加载的目录：把这些 .so 的依赖也加进白名单
for d in /usr/lib/aarch64-linux-gnu/gconv /usr/lib/aarch64-linux-gnu/alsa-lib \
         /usr/lib/aarch64-linux-gnu/nss /usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0 \
         /usr/lib/aarch64-linux-gnu/gtk-3.0 /usr/lib/aarch64-linux-gnu/pulseaudio; do
  for f in "$DST$d"/*.so "$DST$d"/*/*.so; do
    [ -e "$f" ] && lddk "${f#$DST}"
  done
done
# 手工补：按名字 dlopen / 由上面的 closure 覆盖不到的
addk libEGL.so.1 libEGL.so.1.1.0 libGLESv2.so.2 libGLESv2.so.2.1.0 \
  libwayland-client.so.0 libwayland-server.so.0 libwayland-cursor.so.0 libwayland-egl.so.1 \
  libxkbcommon.so.0 libxkbcommon-x11.so.0 libgtk-3.so.0 libgdk-3.so.0 libgdk_pixbuf-2.0.so.0 \
  libsqlite3.so.0 libsoftokn3.so libfreebl3.so libfreeblpriv3.so libnssdbm3.so libnssckbi.so \
  libnsssysinit.so libpulse.so.0 libpulsecommon-17.0.so libpulse-simple.so.0 libltdl.so.7 \
  libspeexdsp.so.1 libwebrtc_audio_processing.so.1 libfftw3f.so.3 libsamplerate.so.0 libsoxr.so.0 \
  libasyncns.so.0 libapparmor.so.1 libcap.so.2 libtdb.so.1 liborc-0.4.so.0 libdbus-1.so.3 \
  libgbm.so.1 libdrm.so.2 libz.so.1 libzstd.so.1 libstdc++.so.6 libgcc_s.so.1 libmvec.so.1 \
  libxcb-shm.so.0 libxcb-render.so.0 libxcb.so.1 libX11.so.6 libX11-xcb.so.1 libXau.so.6 \
  libXdmcp.so.6 libfontconfig.so.1 libfreetype.so.6 libexpat.so.1 libpng16.so.16 \
  libharfbuzz.so.0 libpango-1.0.so.0 libpangoft2-1.0.so.0 libpangocairo-1.0.so.0 \
  libcairo.so.2 libcairo-gobject.so.2 libatk-1.0.so.0 libatk-bridge-2.0.so.0 libatspi.so.0 \
  libepoxy.so.0 libGL.so.1 libGLX.so.0 libGLdispatch.so.0 libpixman-1.so.0 libffi.so.8 \
  libgmodule-2.0.so.0 libgio-2.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0 libselinux.so.1 \
  libpcre2-8.so.0 libmount.so.1 libblkid.so.1 libuuid.so.1 libacl.so.1 libattr.so.1 \
  libnss3.so libnssutil3.so libsmime3.so libplc4.so libplds4.so libnspr4.so \
  libudev.so.1 libsystemd.so.0 libcups.so.2 libavahi-client.so.3 libavahi-common.so.3 \
  libgnutls.so.30 libnettle.so.8 libhogweed.so.6 libp11-kit.so.0 libtasn1.so.6 libunistring.so.5 \
  libidn2.so.0 libgmp.so.10 libkrb5.so.3 libk5crypto.so.3 libkrb5support.so.0 \
  libgssapi_krb5.so.2 libcom_err.so.2 libkeyutils.so.1 libbrotlicommon.so.1 libbrotlidec.so.1 \
  libbz2.so.1.0 liblzma.so.5 libgraphite2.so.3 libdatrie.so.1 libthai.so.0 libfribidi.so.0 \
  libXcomposite.so.1 libXdamage.so.1 libXext.so.6 libXfixes.so.3 libXi.so.6 libXrandr.so.2 \
  libXrender.so.1 libXRes.so.1 libxcb-render-util.so.0 libxcb-util.so.1 libtinfo.so.6 \
  libncursesw.so.6 libXfont2.so.2 libfontenc.so.1 libtirpc.so.3 libxcvt.so.0 libxshmfence.so.1 \
  libdecor-0.so.0 libei.so.1 liboeffis.so.1 libgcrypt.so.20 libgpg-error.so.0
addk mount umount ldconfig init
sort -u "$KEEPF" -o "$KEEPF"
echo "白名单 $(wc -l < "$KEEPF") 个库名"

iskep() { grep -qxF "$1" "$KEEPF" 2>/dev/null; }
onef() {
  f="$1"
  if [ ! -e "$f" ] && [ ! -L "$f" ]; then return 0; fi
  bn="${f##*/}"
  if iskep "$bn"; then echo "  保 ${f#$DST}  (依赖白名单)"; return 0; fi
  sz=$(du -sk "$f" 2>/dev/null | cut -f1); sz=${sz:-0}
  rm -rf "$f"
  SAVED=$((SAVED + sz))
  echo "  -${sz}K  ${f#$DST}"
}
globs() {
  for pat in "$@"; do
    for f in "$DST"$pat; do
      if [ -e "$f" ] || [ -L "$f" ]; then onef "$f"; fi
    done
  done
}
deld() {
  d="$1"
  [ -d "$d" ] || return 0
  hit=$(find "$d" -type f 2>/dev/null | while read -r f; do bn="${f##*/}"; iskep "$bn" && echo "$bn"; done | head -3)
  if [ -n "$hit" ]; then
    echo "  !! 跳过 ${d#$DST}/（含依赖: $(echo "$hit" | tr '\n' ' '))"
    return 0
  fi
  sz=$(du -sk "$d" 2>/dev/null | cut -f1); sz=${sz:-0}
  rm -rf "$d"
  SAVED=$((SAVED + sz))
  echo "  -${sz}K  ${d#$DST}/"
}

echo ""
echo "=== 2. Mesa / Vulkan / 诊断工具（GL 走自研转发壳，系统 Mesa 不再用）==="
deld "$DST/usr/lib/aarch64-linux-gnu/dri"
deld "$DST/usr/share/vulkan"
deld "$DST/usr/share/glvnd"
deld "$DST/usr/share/mesa-demos"
globs "/usr/lib/aarch64-linux-gnu/libEGL_mesa*" "/usr/lib/aarch64-linux-gnu/libGLX_mesa*" \
      "/usr/lib/aarch64-linux-gnu/libGLX_indirect*" "/usr/lib/aarch64-linux-gnu/libglapi*" \
      "/usr/lib/aarch64-linux-gnu/libOSMesa*" "/usr/lib/aarch64-linux-gnu/libvulkan*" \
      "/usr/lib/aarch64-linux-gnu/libGLESv1*" "/usr/lib/aarch64-linux-gnu/libEGL.so.1.[0-9]*" \
      "/usr/lib/aarch64-linux-gnu/libGLESv2.so.2.[0-9]*" "/usr/lib/aarch64-linux-gnu/libvdpau*" \
      "/usr/lib/aarch64-linux-gnu/libd3dadapter*"
globs "/usr/bin/eglinfo" "/usr/bin/es2_info" "/usr/bin/es2gears*" "/usr/bin/glxinfo" \
      "/usr/bin/glxgears" "/usr/bin/vulkaninfo" "/usr/bin/vkmark" "/usr/bin/vkcube*" \
      "/usr/bin/glmark2*" "/usr/bin/kmscube" "/usr/bin/clinfo"

echo ""
echo "=== 3. KDE / Qt 桌面套件 ==="
deld "$DST/usr/lib/qt6"
deld "$DST/usr/lib/qt5"
deld "$DST/usr/lib/qml"
deld "$DST/usr/lib/aarch64-linux-gnu/qml"
deld "$DST/usr/lib/aarch64-linux-gnu/libexec"
deld "$DST/usr/share/kf6"
deld "$DST/usr/share/kservices6"
deld "$DST/usr/share/katexmltools"
globs "/usr/lib/aarch64-linux-gnu/libKF6*" "/usr/lib/aarch64-linux-gnu/libkf6*" \
      "/usr/lib/aarch64-linux-gnu/libkonsole*" "/usr/lib/aarch64-linux-gnu/libKirigami*" \
      "/usr/lib/aarch64-linux-gnu/libkate*" "/usr/lib/aarch64-linux-gnu/libKUserFeedback*" \
      "/usr/lib/aarch64-linux-gnu/libKDevelop*" "/usr/lib/aarch64-linux-gnu/libKDecoration*" \
      "/usr/lib/aarch64-linux-gnu/libKWayland*" "/usr/lib/aarch64-linux-gnu/libdolphin*" \
      "/usr/lib/aarch64-linux-gnu/libqca-qt6*" "/usr/lib/aarch64-linux-gnu/libqalculate*" \
      "/usr/lib/aarch64-linux-gnu/libZXing*" "/usr/lib/aarch64-linux-gnu/libmm-glib*" \
      "/usr/lib/aarch64-linux-gnu/libtag*" "/usr/lib/aarch64-linux-gnu/libKF*" \
      "/usr/lib/aarch64-linux-gnu/libkwindowsystem*" "/usr/lib/aarch64-linux-gnu/libkde*" \
      "/usr/lib/aarch64-linux-gnu/libkolourpaint*" "/usr/lib/aarch64-linux-gnu/libokular*" \
      "/usr/lib/aarch64-linux-gnu/libgwenview*" "/usr/lib/aarch64-linux-gnu/libkdeconnect*" \
      "/usr/lib/aarch64-linux-gnu/libplasma*" "/usr/lib/aarch64-linux-gnu/libakonadi*"
globs "/usr/bin/ksecretd" "/usr/bin/kded*" "/usr/bin/kdesu" "/usr/bin/kbuildsycoca*" \
      "/usr/bin/kmenuedit" "/usr/bin/kpackagetool*" "/usr/bin/kwalletd*" "/usr/bin/kreadconfig*" \
      "/usr/bin/kwriteconfig*" "/usr/bin/kdialog" "/usr/bin/kmimetypefinder*" "/usr/bin/kquitapp*" \
      "/usr/bin/gmenudbusmenuproxy" "/usr/bin/kaccess" "/usr/bin/kglobalaccel*" \
      "/usr/bin/kactivitymanagerd" "/usr/bin/ksmserver" "/usr/bin/kwin*" "/usr/bin/plasmashell" \
      "/usr/bin/konsole" "/usr/bin/kate" "/usr/bin/dolphin" "/usr/bin/okular" "/usr/bin/gwenview"

echo ""
echo "=== 4. 图像/相册/文档链（Chrome 不用 gdk-pixbuf 那套）==="
deld "$DST/usr/libexec/glycin-loaders"
deld "$DST/usr/share/libwacom"
deld "$DST/usr/share/thumbnailers"
globs "/usr/lib/aarch64-linux-gnu/libjxl*" "/usr/lib/aarch64-linux-gnu/libhwy*" \
      "/usr/lib/aarch64-linux-gnu/libdraco*" "/usr/lib/aarch64-linux-gnu/libexiv2*" \
      "/usr/lib/aarch64-linux-gnu/libgexiv2*" "/usr/lib/aarch64-linux-gnu/libgphoto2*" \
      "/usr/lib/aarch64-linux-gnu/libOpenEXR*" "/usr/lib/aarch64-linux-gnu/libImath*" \
      "/usr/lib/aarch64-linux-gnu/libIex*" "/usr/lib/aarch64-linux-gnu/libIlmThread*" \
      "/usr/lib/aarch64-linux-gnu/libOpenThreads*" "/usr/lib/aarch64-linux-gnu/libpoppler*" \
      "/usr/lib/aarch64-linux-gnu/libraw*" "/usr/lib/aarch64-linux-gnu/libheif*" \
      "/usr/lib/aarch64-linux-gnu/libaom*" "/usr/lib/aarch64-linux-gnu/libdav1d*" \
      "/usr/lib/aarch64-linux-gnu/libgav1*" "/usr/lib/aarch64-linux-gnu/libopenjp2*" \
      "/usr/lib/aarch64-linux-gnu/libjbig*" "/usr/lib/aarch64-linux-gnu/libwebp*" \
      "/usr/lib/aarch64-linux-gnu/libwmf*" "/usr/lib/aarch64-linux-gnu/libgegl*" \
      "/usr/lib/aarch64-linux-gnu/libgimp*" "/usr/lib/aarch64-linux-gnu/liblensfun*" \
      "/usr/lib/aarch64-linux-gnu/libopenslide*" "/usr/lib/aarch64-linux-gnu/libavif*" \
      "/usr/lib/aarch64-linux-gnu/libfreeimage*" "/usr/lib/aarch64-linux-gnu/libspng*" \
      "/usr/lib/aarch64-linux-gnu/librsvg*" "/usr/lib/aarch64-linux-gnu/libglycin*" \
      "/usr/lib/aarch64-linux-gnu/libvips*" "/usr/lib/aarch64-linux-gnu/libmagick*" \
      "/usr/lib/aarch64-linux-gnu/libMagick*" "/usr/lib/aarch64-linux-gnu/libraqm*"

echo ""
echo "=== 5. 音频多余件（宿主的 PA 在 anland 模块里，rootfs 只需要 pactl 的依赖）==="
deld "$DST/usr/lib/aarch64-linux-gnu/pipewire-0.3"
deld "$DST/usr/lib/aarch64-linux-gnu/spa-0.2"
deld "$DST/usr/lib/aarch64-linux-gnu/wireplumber-0.5"
deld "$DST/usr/share/pipewire"
deld "$DST/usr/share/wireplumber"
globs "/usr/lib/aarch64-linux-gnu/libpipewire*" "/usr/lib/aarch64-linux-gnu/libspa*" \
      "/usr/lib/aarch64-linux-gnu/libwireplumber*" "/usr/lib/aarch64-linux-gnu/libroc*" \
      "/usr/lib/aarch64-linux-gnu/libfreeaptx*" "/usr/lib/aarch64-linux-gnu/libldac*" \
      "/usr/lib/aarch64-linux-gnu/libopenaptx*" "/usr/lib/aarch64-linux-gnu/libldacbt*" \
      "/usr/bin/wireplumber" "/usr/bin/pipewire*" "/usr/bin/pw-*" "/usr/bin/spa-*" \
      "/usr/bin/wpctl" "/usr/bin/pavucontrol"

echo ""
echo "=== 6. 开发/网络/加密工具（chroot 里用不到）==="
deld "$DST/usr/lib/git-core"
deld "$DST/usr/lib/cargo"
deld "$DST/usr/lib/7zip"
deld "$DST/usr/lib/file"
deld "$DST/usr/lib/openssh"
deld "$DST/usr/share/coreutils"
deld "$DST/usr/share/misc"
deld "$DST/usr/share/doc"
deld "$DST/usr/share/man"
deld "$DST/usr/lib/aarch64-linux-gnu/security"
deld "$DST/usr/lib/aarch64-linux-gnu/android"
deld "$DST/usr/local/etc/tmoe-linux"
globs "/usr/bin/git" "/usr/bin/git-*" "/usr/bin/scalar" "/usr/bin/ssh" "/usr/bin/ssh-*" \
      "/usr/bin/scp" "/usr/bin/sftp" "/usr/bin/openssl" "/usr/bin/gpg" "/usr/bin/gpg-*" \
      "/usr/bin/gpgsm" "/usr/bin/gpgtar" "/usr/bin/gpgv" "/usr/bin/gpgconf" "/usr/bin/dirmngr" \
      "/usr/bin/perl" "/usr/bin/perl*" "/usr/bin/cpan*" "/usr/bin/wget" "/usr/bin/file" \
      "/usr/bin/gawk" "/usr/bin/awk" "/usr/bin/socat1" "/usr/bin/vim*" "/usr/bin/nano" \
      "/usr/bin/passwd" "/usr/bin/chsh" "/usr/bin/chfn" "/usr/bin/sudo" "/usr/bin/su" \
      "/usr/bin/curl" "/usr/bin/ip" "/usr/bin/ss" "/usr/bin/netstat" "/usr/bin/tcpdump" \
      "/usr/bin/nc*" "/usr/bin/telnet" "/usr/bin/ftp" "/usr/bin/mail*" "/usr/bin/mutt" \
      "/usr/lib/aarch64-linux-gnu/libperl*" "/usr/lib/aarch64-linux-gnu/libgit*" \
      "/usr/lib/aarch64-linux-gnu/libcurl*" "/usr/lib/aarch64-linux-gnu/libnghttp*" \
      "/usr/lib/aarch64-linux-gnu/libpsl*" "/usr/lib/aarch64-linux-gnu/libssh*" \
      "/usr/lib/aarch64-linux-gnu/libldap*" "/usr/lib/aarch64-linux-gnu/liblber*" \
      "/usr/lib/aarch64-linux-gnu/libsasl*" "/usr/lib/aarch64-linux-gnu/libksba*" \
      "/usr/lib/aarch64-linux-gnu/libassuan*" "/usr/lib/aarch64-linux-gnu/libnpth*" \
      "/usr/lib/aarch64-linux-gnu/libevent*" "/usr/lib/aarch64-linux-gnu/libunbound*"

echo ""
echo "=== 7. systemd/udev 那一坨（libudev.so.1 保留，工具与 hwdb 删）==="
deld "$DST/usr/lib/udev"
deld "$DST/usr/share/bash-completion"
deld "$DST/usr/share/zsh"
deld "$DST/usr/share/vim"
globs "/usr/bin/udevadm" "/usr/bin/systemctl" "/usr/bin/systemd-*" "/usr/bin/journalctl" \
      "/usr/bin/loginctl" "/usr/bin/busctl" "/usr/bin/resolvectl" "/usr/bin/networkctl" \
      "/usr/bin/hostnamectl" "/usr/bin/timedatectl" "/usr/bin/localectl" "/usr/bin/bootctl" \
      "/usr/bin/coredumpctl" "/usr/bin/oomctl" "/usr/bin/portablectl" "/usr/bin/machinectl"

echo ""
echo "=== 8. usr/sbin 杂项（保留 ldconfig/mount/umount/init）==="
for f in "$DST"/usr/sbin/*; do
  if [ -e "$f" ] || [ -L "$f" ]; then
    case "${f##*/}" in
      ldconfig|mount|umount|init|ldconfig.real) echo "  保 usr/sbin/${f##*/}" ;;
      *) onef "$f" ;;
    esac
  fi
done

echo ""
echo "=== 9. Chrome 目录里可删的附件 ==="
globs "/opt/google/chrome/chrome-management-service" \
      "/opt/google/chrome/libLiteRtWebGpuAccelerator.so" \
      "/opt/google/chrome/libqt5_shim.so" "/opt/google/chrome/libqt6_shim.so" \
      "/opt/google/chrome/cron" "/opt/google/chrome/PrivacySandboxAttestationsPreloaded" \
      "/opt/google/chrome/liboptimization_guide_internal.so"

echo ""
echo "=== 10. 杂项清理 ==="
deld "$DST/var/lib/apt"
deld "$DST/var/lib/dpkg"
deld "$DST/var/lib/systemd"
deld "$DST/usr/share/gtk-3.0"
globs "/var/cache/*" "/var/log/*" "/var/tmp/*"

echo ""
echo "=== 11. 复查（删完再 ldd 一遍）==="
for b in /opt/google/chrome/chrome /usr/bin/Xwayland /usr/lib/anland/Xwayland \
         /usr/bin/anland-miniwm /usr/bin/pactl /usr/bin/coreutils /usr/bin/env; do
  miss=$(chroot "$DST" /usr/bin/env -i PATH=/usr/bin:/bin:/sbin:/usr/sbin \
         /usr/bin/ldd "$b" 2>&1 | grep 'not found')
  if [ -n "$miss" ]; then echo "  !! $b 缺: $miss"; else echo "  ok $b"; fi
done
echo "--- 关键文件 ---"
for f in opt/google/chrome/chrome usr/bin/env usr/bin/coreutils usr/bin/anland-miniwm \
         usr/lib/anland/Xwayland usr/bin/Xwayland usr/bin/pactl \
         usr/share/xkeyboard-config-2/rules/evdev usr/share/X11/xkb \
         usr/lib/aarch64-linux-gnu/libEGL.so.1.1.0 usr/lib/aarch64-linux-gnu/libGLESv2.so.2.1.0 \
         usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
         usr/lib/aarch64-linux-gnu/libgbm.so.1 usr/lib/aarch64-linux-gnu/libgtk-3.so.0 \
         usr/lib/aarch64-linux-gnu/libnss3.so usr/lib/aarch64-linux-gnu/gconv/gconv-modules.cache \
         opt/google/chrome/resources.pak opt/google/chrome/locales/zh-CN.pak \
         opt/google/chrome/libvk_swiftshader.so opt/google/chrome/vk_swiftshader_icd.json ; do
  if [ -e "$DST/$f" ]; then echo "  ok   $f"; else echo "  缺失 $f"; fi
done
echo ""
echo "=== 结果 ==="
echo "克隆后: 1.0GB 左右 -> 现在 $(du -sh "$DST" 2>/dev/null | cut -f1)"
echo "文件数: $(find "$DST" -type f 2>/dev/null | wc -l)"
echo "本轮共删: $((SAVED / 1024)) MB"
echo "RF3-DONE"
} > "$LOG" 2>&1
echo "logged to $LOG"
