#!/system/bin/sh
# glproxy-buildenv.sh —— 给 chroot 装编译环境（gcc），用来编译 GL 转发的 glibc 客户端壳
#
# 用**未精简的旧 rootfs**（/data/adb/anland-chrome/root）当编译环境：精简版里没有编译器，
# 而我们要产物是 glibc 的（不能是 bionic —— 它要被 Chrome 这种 glibc 进程加载）。
set -u
R=/data/adb/anland-chrome/root
LOG=/data/local/tmp/glproxy-buildenv.log
{
echo "=== 0. 挂载点 ==="
mkdir -p "$R/proc" "$R/sys" "$R/dev" "$R/dev/shm" "$R/tmp"
grep -q " $R/proc " /proc/mounts || mount -t proc proc "$R/proc" 2>/dev/null || mount --bind /proc "$R/proc"
grep -q " $R/sys "  /proc/mounts || mount -t sysfs sysfs "$R/sys" 2>/dev/null || mount --bind /sys "$R/sys"
grep -q " $R/dev "  /proc/mounts || mount --bind /dev "$R/dev"
grep -q " $R/dev/shm " /proc/mounts || mount -t tmpfs -o mode=1777,size=512m tmpfs "$R/dev/shm"
echo ok

echo ""
echo "=== 1. DNS / 网络 ==="
cat "$R/etc/resolv.conf" 2>&1 | head -3
chroot "$R" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
  /usr/bin/getent hosts archive.ubuntu.com 2>&1 | head -2

echo ""
echo "=== 2. 源里的发行版 ==="
head -6 "$R/etc/apt/sources.list" 2>/dev/null || ls "$R/etc/apt/sources.list.d/" 2>&1

echo ""
echo "=== 3. apt-get update ==="
chroot "$R" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  HOME=/root DEBIAN_FRONTEND=noninteractive \
  /usr/bin/apt-get update 2>&1 | tail -6

echo ""
echo "=== 4. 装 gcc / libc6-dev ==="
chroot "$R" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  HOME=/root DEBIAN_FRONTEND=noninteractive \
  /usr/bin/apt-get install -y --no-install-recommends gcc libc6-dev 2>&1 | tail -12

echo ""
echo "=== 5. 验证 ==="
chroot "$R" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
  /usr/bin/gcc --version 2>&1 | head -2
echo "GLPROXY-BUILDENV-DONE"
} > "$LOG" 2>&1
