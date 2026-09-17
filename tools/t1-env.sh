#!/system/bin/sh
# t1-env.sh -- 在 rootfs 里把 /usr/bin/env 换成包装脚本，用来注入 Mesa 后端（T1 = msm/DRM）
#   t1-env.sh on   → 注入 MESA_LOADER_DRIVER_OVERRIDE=msm（走 /dev/dri/renderD128，不碰 kgsl）
#   t1-env.sh off  → 还原成原样
# App 的 chroot 命令是 `env -i … chrome`，所以包住 env 就能改环境，不用改 App。
set -u
R=/data/adb/anland-chrome/root
ENV=$R/usr/bin/env
REAL=$R/usr/lib/cargo/bin/coreutils/env
BAK=$R/usr/bin/env.appwrap-orig

case "${1:-on}" in
on)
  if [ ! -e "$BAK" ]; then
    cp -a "$ENV" "$BAK" 2>/dev/null || ln -s ../lib/cargo/bin/coreutils/env "$BAK"
  fi
  cat > "$ENV" <<'EOF'
#!/bin/sh
# appwrap T1: 让 Mesa 走 DRM(msm) 而不是 kgsl
MESA_LOADER_DRIVER_OVERRIDE=msm
ANLAND_DRM_DEVICE=/dev/dri/renderD128
export MESA_LOADER_DRIVER_OVERRIDE ANLAND_DRM_DEVICE
exec /usr/lib/cargo/bin/coreutils/env "$@"
EOF
  chmod 755 "$ENV"
  echo "已注入 T1(msm) 环境："
  cat "$ENV"
  ;;
off)
  if [ -e "$BAK" ]; then
    rm -f "$ENV"
    cp -a "$BAK" "$ENV" 2>/dev/null || ln -s ../lib/cargo/bin/coreutils/env "$ENV"
    rm -f "$BAK"
    echo "已还原 /usr/bin/env"
  else
    echo "(没有备份，保持原样)"
  fi
  ;;
esac
ls -l "$ENV" "$REAL" 2>&1
