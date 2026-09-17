#!/system/bin/sh
# rf-prune.sh —— 精简 rootfs（在工作区那份上做，不动在用的 rootfs）
#
# 原则：
#   1. Chrome 自己的资源（/opt/google/chrome 除多余语言包）一律保留
#   2. 字体只留拉丁基础 + 中日韩，否则中文网页会变方块
#   3. Mesa 的"重型件"（libLLVM 128M / libgallium 48M / 各 GPU 的 DRI 驱动）删掉 ——
#      Chrome 走自带的 ANGLE+SwiftShader，不加载系统 Mesa；libgbm/libdrm 保留（wayland 要用）
#   4. 只删确定无关的：文档、本地化、图标主题、perl/python、apt 缓存、内核头文件
set -u
R=/data/local/tmp/rf-prune/root
LOG=/data/local/tmp/rf-prune.log

du_() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1; }
del() {
  for p in "$@"; do
    if [ -e "$p" ]; then
      echo "  删 $(du_ "$p")	$(echo "$p" | sed "s|$R||")"
      rm -rf "$p"
    fi
  done
}

{
  echo "=== 精简前 ==="
  du -sh "$R"
  echo "文件数: $(find "$R" -type f 2>/dev/null | wc -l)"

  echo ""
  echo "=== 1. 文档/手册/头文件 ==="
  del "$R/usr/share/doc" "$R/usr/share/man" "$R/usr/share/info" "$R/usr/share/lintian" \
      "$R/usr/share/bug" "$R/usr/share/gettext" "$R/usr/src" "$R/usr/include" \
      "$R/usr/share/gdb" "$R/usr/share/aclocal" "$R/usr/share/pkgconfig" \
      "$R/usr/share/bash-completion" "$R/usr/share/zsh" "$R/usr/share/fish"

  echo ""
  echo "=== 2. 本地化（Chrome 有自带 locale，系统 locale 数据用不上）==="
  del "$R/usr/share/locale" "$R/usr/share/i18n" "$R/usr/lib/locale"

  echo ""
  echo "=== 3. 图标主题 / 桌面环境数据（chroot 里没有桌面）==="
  del "$R/usr/share/icons" "$R/usr/share/pixmaps" "$R/usr/share/desktop-directories" \
      "$R/usr/share/sounds" "$R/usr/share/wallpapers" "$R/usr/share/themes"

  echo ""
  echo "=== 4. perl / python（Chrome 不需要）==="
  del "$R/usr/share/perl" "$R/usr/share/perl5" "$R/usr/lib/python3" "$R/usr/lib/python3.13" \
      "$R/usr/share/python3"
  for f in "$R"/usr/lib/aarch64-linux-gnu/perl* "$R"/usr/lib/aarch64-linux-gnu/python3*; do
    [ -e "$f" ] && del "$f"
  done
  for f in "$R"/usr/bin/perl* "$R"/usr/bin/python3* "$R"/usr/bin/pydoc3* "$R"/usr/bin/pip3*; do
    [ -e "$f" ] && del "$f"
  done

  echo ""
  echo "=== 5. Mesa 重型件（Chrome 用自带 SwiftShader；libgbm/libdrm 保留）==="
  del "$R/usr/lib/aarch64-linux-gnu/dri"
  for f in "$R"/usr/lib/aarch64-linux-gnu/libgallium* "$R"/usr/lib/aarch64-linux-gnu/libLLVM* \
           "$R"/usr/lib/aarch64-linux-gnu/libvulkan_* "$R"/usr/lib/aarch64-linux-gnu/libvdpau* \
           "$R"/usr/lib/aarch64-linux-gnu/libOSMesa* "$R"/usr/lib/aarch64-linux-gnu/libglapi*; do
    [ -e "$f" ] && del "$f"
  done
  echo "  保留: $(ls "$R/usr/lib/aarch64-linux-gnu/" 2>/dev/null | grep -cE 'libgbm|libdrm|libEGL|libGLES') 个 GL/DRM 基础库"

  echo ""
  echo "=== 6. 包管理缓存 / 日志 ==="
  del "$R/var/cache/apt" "$R/var/lib/apt/lists" "$R/var/log" "$R/var/tmp" \
      "$R/var/lib/dpkg/info" "$R/var/cache/debconf" "$R/var/lib/ucf"

  echo ""
  echo "=== 7. 字体：只留拉丁基础 + CJK（否则中文网页是方块）==="
  echo "  精简前: $(du_ "$R/usr/share/fonts")"
  if [ -d "$R/usr/share/fonts" ]; then
    cd "$R/usr/share/fonts" || exit 1
    mkdir -p /data/local/tmp/fonts-keep
    # 先挑出要留的
    find . -type f \( -iname '*DejaVu*' -o -iname '*CJK*' -o -iname '*Droid*Fallback*' \
         -o -iname '*wqy*' -o -iname '*Noto*SC*' -o -iname '*Noto*TC*' -o -iname '*Noto*JP*' \
         -o -iname '*Noto*KR*' -o -iname '*arphic*' -o -iname '*uming*' -o -iname '*ukai*' \) \
         -exec cp -a --parents {} /data/local/tmp/fonts-keep/ \; 2>/dev/null
    rm -rf "$R/usr/share/fonts"
    mkdir -p "$R/usr/share/fonts"
    cp -a /data/local/tmp/fonts-keep/. "$R/usr/share/fonts/" 2>/dev/null
    rm -rf /data/local/tmp/fonts-keep
  fi
  echo "  精简后: $(du_ "$R/usr/share/fonts")"
  find "$R/usr/share/fonts" -type f 2>/dev/null | sed "s|$R||" | head -12

  echo ""
  echo "=== 8. Chrome 多余语言包（只留 en-US / zh-CN）==="
  if [ -d "$R/opt/google/chrome/locales" ]; then
    echo "  精简前: $(du_ "$R/opt/google/chrome/locales")  语言包数: $(ls "$R/opt/google/chrome/locales" | wc -l)"
    cd "$R/opt/google/chrome/locales" || exit 1
    ls | grep -vE '^(en-US|zh-CN|zh-TW)\.pak$' | while read f; do rm -f "$f"; done
    echo "  精简后: $(du_ "$R/opt/google/chrome/locales")  语言包数: $(ls | wc -l)"
  fi

  echo ""
  echo "=== 9. 其他零碎 ==="
  del "$R/usr/share/zoneinfo/right" "$R/usr/share/zoneinfo/posix" "$R/usr/share/emacs" \
      "$R/usr/share/vim" "$R/usr/share/nano" "$R/usr/share/X11/xkb" "$R/usr/share/iso-codes" \
      "$R/opt/google/chrome/nacl_irt"* "$R/opt/google/chrome/MEIPreload" \
      "$R/root/.chrome" "$R/root/.config" "$R/root/.cache" "$R/home" 

  echo ""
  echo "=== 精简后 ==="
  du -sh "$R"
  echo "文件数: $(find "$R" -type f 2>/dev/null | wc -l)"
  echo "=== 关键文件是否还在 ==="
  for f in opt/google/chrome/chrome opt/google/chrome/libvk_swiftshader.so \
           opt/google/chrome/icudtl.dat opt/google/chrome/resources.pak \
           usr/bin/anland-miniwm usr/bin/env usr/bin/coreutils \
           usr/lib/aarch64-linux-gnu/libgbm.so.1 etc/ld.so.cache; do
    [ -e "$R/$f" ] && echo "  ok   $f" || echo "  缺失 $f"
  done
  echo "=== 动态库依赖检查（chrome 的 DT_NEEDED 是否都能找到）==="
  chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd /opt/google/chrome/chrome 2>&1 \
    | grep -E 'not found' | head -20
  echo "(上面没有 not found 就说明依赖完整)"
  echo "RF-PRUNE-DONE"
} > "$LOG" 2>&1
