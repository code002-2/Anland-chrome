#!/system/bin/sh
# gf.sh -- install the glproxy shim as the SYSTEM libEGL/libGLESv2 inside the rootfs.
# Chrome strips LD_LIBRARY_PATH from its child processes, so ANGLE's dlopen("libEGL.so.1")
# must find our shim through the normal library search path.
set -u
L=/usr/lib/aarch64-linux-gnu
for R in /data/adb/anland-chrome/root /data/adb/anland-chrome/root-slim; do
  [ -d "$R" ] || continue
  echo "=== $R ==="
  cd "$R$L" || { echo "  no such dir"; continue; }
  # keep Mesa's originals as *.mesa for easy rollback
  for f in libEGL.so.1 libGLESv2.so.2; do
    if [ -e "$f" ] && [ ! -e "$f.mesa" ] && [ ! -L "$f" ]; then
      cp -a "$f" "$f.mesa" && echo "  backed up $f -> $f.mesa"
    fi
  done
  cp -f "$R/opt/glproxy/lib/libGLESv2.so.2" "$R$L/libGLESv2.so.2"
  cp -f "$R/opt/glproxy/lib/libEGL.so.1"    "$R$L/libEGL.so.1"
  chmod 755 "$R$L/libGLESv2.so.2" "$R$L/libEGL.so.1"
  ls -l "$R$L/libEGL.so.1" "$R$L/libGLESv2.so.2"
  chroot "$R" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
    /usr/sbin/ldconfig 2>/dev/null && echo "  ldconfig ok" || echo "  (ldconfig skipped)"
done
echo "GF-DONE"
