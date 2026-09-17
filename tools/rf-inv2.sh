#!/system/bin/sh
# rf-inv2.sh —— 精简后的第二轮盘点（看下一批能从哪砍）
R=/data/local/tmp/rf-prune/root
LOG=/data/local/tmp/rf-inv2.txt
{
  echo "=== 总量 ==="
  du -sh "$R"
  echo "文件数: $(find "$R" -type f | wc -l)"
  echo ""
  echo "=== 剩余一级/二级目录（前 30）==="
  du -m "$R"/* 2>/dev/null | sort -rn | head -20
  echo "--- usr/lib/aarch64-linux-gnu 里最大的 25 个 ---"
  du -m "$R"/usr/lib/aarch64-linux-gnu/* 2>/dev/null | sort -rn | head -25
  echo "--- usr/share 下 ---"
  du -m "$R"/usr/share/* 2>/dev/null | sort -rn | head -12
  echo "--- usr/bin 里最大的 15 个 ---"
  du -m "$R"/usr/bin/* 2>/dev/null | sort -rn | head -15
  echo "--- opt/google/chrome ---"
  du -m "$R"/opt/google/chrome/* 2>/dev/null | sort -rn | head -10
  echo ""
  echo "=== 大目录合计 ==="
  for d in usr/lib/aarch64-linux-gnu usr/lib usr/share usr/bin usr/libexec etc opt var \
           usr/share/fonts usr/lib/x86_64-linux-gnu; do
    [ -e "$R/$d" ] && du -sh "$R/$d"
  done
  echo ""
  echo "=== 看起来可以再砍的（X11/Qt/GTK 之外的东西）==="
  for d in usr/lib/aarch64-linux-gnu/qt5 usr/lib/aarch64-linux-gnu/qt6 usr/share/qt5 usr/share/qt6 \
           usr/lib/aarch64-linux-gnu/gio usr/lib/aarch64-linux-gnu/gdk-pixbuf-2.0 \
           usr/lib/aarch64-linux-gnu/gtk-3.0 usr/share/gtk-doc usr/share/glib-2.0 \
           usr/libexec usr/share/X11 usr/share/wayland-protocols usr/share/dbus-1 \
           usr/lib/aarch64-linux-gnu/nss usr/lib/aarch64-linux-gnu/pkcs11 \
           usr/share/man usr/share/openssl usr/share/ca-certificates \
           usr/lib/aarch64-linux-gnu/gconv usr/share/alsa usr/share/awk; do
    [ -e "$R/$d" ] && du -sh "$R/$d"
  done
  echo "RF-INV2-DONE"
} > "$LOG" 2>&1
setsid true
