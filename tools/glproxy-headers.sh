#!/system/bin/sh
# glproxy-headers.sh —— 装 EGL/GLES 开发头文件，然后重跑 Spike A
R=/data/adb/anland-chrome/root
L=/data/local/tmp/glproxy-headers.log
{
  echo "=== apt-get install libegl-dev libgles-dev libglvnd-dev ==="
  chroot "$R" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root \
    DEBIAN_FRONTEND=noninteractive \
    /usr/bin/apt-get install -y --no-install-recommends libegl-dev libgles-dev libglvnd-dev 2>&1 | tail -8
  echo "=== 头文件是否到位 ==="
  ls -l "$R/usr/include/EGL/egl.h" "$R/usr/include/GLES2/gl2.h" 2>&1
} > "$L" 2>&1
# 接着跑 Spike A
sh /data/local/tmp/glproxy-run.sh
