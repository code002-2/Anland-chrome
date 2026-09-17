#!/system/bin/sh
# devtools.sh —— 直接问 Chrome：你现在开着哪些页面、标题是什么、URL 是什么。
# 需要启动时带 --remote-debugging-port=9222。chroot 与宿主同一个网络命名空间，
# 所以 chroot 里 curl 127.0.0.1:9222 就能拿到。
R=/data/adb/anland-chrome/root
echo "=== 页面列表（DevTools /json）==="
chroot "$R" /usr/bin/env -i /usr/bin/curl -s --max-time 6 http://127.0.0.1:9222/json 2>&1 | head -60
echo ""
echo "=== 版本信息 ==="
chroot "$R" /usr/bin/env -i /usr/bin/curl -s --max-time 6 http://127.0.0.1:9222/json/version 2>&1 | head -12
