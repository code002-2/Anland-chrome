#!/system/bin/sh
# gl-probe.sh —— 在 chroot 里逐个试 GL 后端，看谁真能用（不启动 Chrome，炸的半径小）
#
# 为什么要有它：Chrome 之前用 --use-angle=swiftshader（纯 CPU 光栅化），1080p 视频
# 直接卡死；要上真 GPU 就得让 rootfs 里的 Mesa 摸到 Adreno。已知 kgsl 那条路会把
# SurfaceFlinger 打成 SIGABRT（软重启），所以先从渲染节点（DRM render node）试。
#
# 用法（经 App 的远程钩子，root）：
#   am start -n com.anland.appwrap/.MainActivity --es shf /data/local/tmp/gl-probe.sh
R=/data/adb/anland-chrome/root

echo "=== 设备节点 ==="
ls -l /dev/dri/ 2>&1
ls -l /dev/kgsl-3d0 2>&1

echo "=== 准备挂载 ==="
mkdir -p "$R/proc" "$R/sys" "$R/dev/shm" "$R/tmp" "$R/run" 2>/dev/null
grep -q " $R/proc " /proc/mounts || mount -t proc proc "$R/proc" 2>/dev/null || mount --bind /proc "$R/proc"
grep -q " $R/sys " /proc/mounts || mount -t sysfs sysfs "$R/sys" 2>/dev/null || mount --bind /sys "$R/sys"
grep -q " $R/dev " /proc/mounts || mount --bind /dev "$R/dev"
grep -q " $R/dev/shm " /proc/mounts || mount -t tmpfs -o mode=1777,size=512m tmpfs "$R/dev/shm"
echo ok

probe() {
  NAME="$1"; ENVS="$2"
  echo ""
  echo "########## $NAME ##########"
  echo "env: $ENVS"
  timeout 45 chroot "$R" /usr/bin/env -i \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      HOME=/root XDG_RUNTIME_DIR=/tmp $ENVS \
      /usr/bin/eglinfo -B 2>&1 | head -30
  echo "--- es2_info ---"
  timeout 45 chroot "$R" /usr/bin/env -i \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      HOME=/root XDG_RUNTIME_DIR=/tmp $ENVS \
      /usr/bin/es2_info 2>&1 | head -14
}

probe "swrast(基线,纯CPU)" "LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MESA_LOADER_DRIVER_OVERRIDE=swrast"
probe "msm(DRM renderD128,真GPU)" "MESA_LOADER_DRIVER_OVERRIDE=msm GALLIUM_DRIVER=msm ANLAND_DRM_DEVICE=/dev/dri/renderD128 LIBGL_ALWAYS_SOFTWARE=0"

echo ""
echo "=== 内核日志尾部（看有没有 GPU fault）==="
dmesg | tail -15
echo "=== SurfaceFlinger 还活着吗 ==="
pidof surfaceflinger
