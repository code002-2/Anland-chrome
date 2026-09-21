#!/system/bin/sh
# rf-final-check.sh -- 打包前的关键文件清点
DST=/data/local/tmp/rf3/root
for f in \
  opt/google/chrome/chrome opt/google/chrome/resources.pak opt/google/chrome/icudtl.dat \
  opt/google/chrome/locales/zh-CN.pak opt/google/chrome/locales/en-US.pak \
  opt/google/chrome/libvk_swiftshader.so opt/google/chrome/vk_swiftshader_icd.json \
  opt/google/chrome/chrome_crashpad_handler opt/google/chrome/WidevineCdm/_platform_specific/linux_arm64/libwidevinecdm.so \
  usr/bin/env usr/bin/coreutils usr/bin/bash usr/bin/Xwayland usr/bin/anland-miniwm usr/bin/pactl \
  usr/lib/anland/Xwayland usr/lib/anland/bwrap \
  usr/lib/aarch64-linux-gnu/libEGL.so.1 usr/lib/aarch64-linux-gnu/libEGL.so.1.1.0 \
  usr/lib/aarch64-linux-gnu/libGLESv2.so.2 usr/lib/aarch64-linux-gnu/libGLESv2.so.2.1.0 \
  usr/lib/aarch64-linux-gnu/gconv/gconv-modules.cache usr/lib/aarch64-linux-gnu/libgtk-3.so.0 \
  usr/lib/aarch64-linux-gnu/libnss3.so usr/lib/aarch64-linux-gnu/nss/libsoftokn3.so \
  usr/lib/aarch64-linux-gnu/libsqlite3.so.0 usr/lib/aarch64-linux-gnu/libgbm.so.1 \
  usr/lib/aarch64-linux-gnu/alsa-lib usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0 \
  usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc usr/share/fonts/truetype/dejavu \
  usr/share/xkeyboard-config-2/rules/evdev usr/share/zoneinfo/Asia/Shanghai \
  usr/share/zoneinfo/UTC usr/share/alsa usr/share/X11/locale usr/share/X11/xkb \
  etc/fonts etc/ssl etc/pulse etc/ld.so.cache etc/ld.so.conf.d usr/share/dbus-1 \
  usr/lib/aarch64-linux-gnu/gio/modules usr/lib/aarch64-linux-gnu/gtk-3.0 ; do
  if [ -e "$DST/$f" ]; then echo "  ok   $f"; else echo "  缺失 $f"; fi
done
echo ""
echo "=== 顶层体积 ==="
du -sm "$DST"/usr "$DST"/opt "$DST"/etc "$DST"/var "$DST"/usr/share "$DST"/usr/lib "$DST"/usr/bin 2>/dev/null
echo "=== 总计 ==="
du -sh "$DST"; find "$DST" -type f | wc -l
echo "=== ld.so.cache 时间戳（ldconfig 是否跑过）==="
ls -l "$DST/etc/ld.so.cache" 2>/dev/null
echo FINALCHECK-DONE
