#!/system/bin/sh
# cleanup-chrome.sh —— 清掉上一次运行留下的 Chrome / 中继 / Xwayland / miniwm 与锁文件
# （Chrome 发现旧的 SingletonLock 时会"交给已有会话"然后自己退出，看起来像启动失败）
set -u
R=/data/adb/anland-chrome/root

pkill chrome 2>/dev/null
pkill chrome_crashpad_handler 2>/dev/null
pkill libawlrelay.so 2>/dev/null
pkill Xwayland 2>/dev/null
pkill anland-miniwm 2>/dev/null
sleep 1

rm -f "$R/root/.chrome/SingletonLock" "$R/root/.chrome/SingletonCookie" "$R/root/.chrome/SingletonSocket" 2>/dev/null
rm -f "$R/tmp/wayland-0" "$R/tmp/.X11-unix/X0" "$R/tmp/.X0-lock" 2>/dev/null
rm -f "$R/tmp/appwrap-x.pid" "$R/tmp/appwrap-wm.pid" 2>/dev/null

echo "== 剩余相关进程 =="
ps -A | grep -E 'chrome|awlrelay|Xwayland|miniwm' || echo "(无)"
echo "== rootfs profile 锁 =="
ls -l "$R/root/.chrome/SingletonLock" 2>&1 | head -2
