#!/system/bin/sh
# run-chrome.sh —— 不经 App 直接重启 chroot 里的 Chrome，用来快速 A/B 对比 GL 后端。
#
# 为什么可以绕过 App 启动：窗口归属是由**中继那条 socketpair** 决定的（对端在 App 进程里
# 创建，守护进程看到的凭据就是 App 的 uid）。Chrome 只是按路径连中继，
# 所以随便谁把它拉起来，窗口照样归 App，App 的 autoAttach 照样挂载。
# 好处：换 GL 环境不用改配置、不用重装 APK、不用重启 App。
#
# 用法（root）：
#   echo 'MESA_LOADER_DRIVER_OVERRIDE=msm LIBGL_ALWAYS_SOFTWARE=0' > /data/local/tmp/glenv
#   sh /data/local/tmp/run-chrome.sh
#   ARGS='...' URL='...' sh /data/local/tmp/run-chrome.sh     # 覆盖参数/网址
set -u
R=/data/adb/anland-chrome/root
RT=/data/local/tmp/awl
LOG=/data/local/tmp/chrome.log

ARGS="${ARGS:---no-sandbox --no-zygote --ozone-platform=wayland --disable-dev-shm-usage --no-first-run --no-default-browser-check --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader --autoplay-policy=no-user-gesture-required --force-device-scale-factor=0.5 --num-raster-threads=4}"
URL="${URL:-https://www.bilibili.com}"
GL=""
[ -f /data/local/tmp/glenv ] && GL=$(cat /data/local/tmp/glenv)

# 注意：这里只能按**进程名**杀（pkill chrome 匹配 comm），绝不能用 pkill -f ——
# 脚本路径里就带 "chrome"，-f 会把执行它的 shell 一起杀掉。
pkill chrome 2>/dev/null
pkill chrome_crashpad_handler 2>/dev/null
sleep 1
rm -f "$R/root/.chrome/SingletonLock" "$R/root/.chrome/SingletonCookie" \
      "$R/root/.chrome/SingletonSocket" 2>/dev/null

mkdir -p "$R/proc" "$R/sys" "$R/dev/shm" "$R/tmp" "$R/run/anland" 2>/dev/null
grep -q " $R/proc " /proc/mounts || mount -t proc proc "$R/proc" 2>/dev/null || mount --bind /proc "$R/proc"
grep -q " $R/sys " /proc/mounts || mount -t sysfs sysfs "$R/sys" 2>/dev/null || mount --bind /sys "$R/sys"
grep -q " $R/dev " /proc/mounts || mount --bind /dev "$R/dev" 2>/dev/null
grep -q " $R/dev/shm " /proc/mounts || mount -t tmpfs -o mode=1777,size=512m tmpfs "$R/dev/shm" 2>/dev/null
grep -q " $R/run/anland " /proc/mounts || mount --bind "$RT" "$R/run/anland" 2>/dev/null

if [ ! -S "$R/tmp/wayland-0" ]; then
  echo "!! $R/tmp/wayland-0 不存在 —— 中继没在跑（先在 App 里点一次启动）"
  exit 7
fi

echo "GL   = ${GL:-(无，走 Chrome 自己的默认)}"
echo "ARGS = $ARGS"
echo "URL  = $URL"

: > "$LOG"
setsid chroot "$R" /usr/bin/env -i \
    HOME=/root USER=root LOGNAME=root TERM=xterm-256color \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    XDG_RUNTIME_DIR=/tmp XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=/tmp/wayland-0 \
    PULSE_SERVER=unix:/run/anland/pulse.sock $GL \
    /opt/google/chrome/chrome $ARGS "$URL" >> "$LOG" 2>&1 < /dev/null &

sleep 8
echo "--- 进程 ---"
pgrep chrome >/dev/null 2>&1 && echo "chrome 已启动" || echo "chrome 没起来"
echo "--- 日志尾部 ---"
tail -12 "$LOG" 2>&1
echo "--- GL 渲染器线索（日志里搜 GL_RENDERER / SwiftShader / freedreno / Adreno）---"
grep -iE 'gl_renderer|swiftshader|freedreno|adreno|mesa|vulkan|egl' "$LOG" 2>/dev/null | head -10
