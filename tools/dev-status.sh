#!/system/bin/sh
# dev-status.sh -- 装机前/后的状态快照
echo "=== /data/adb/anland-chrome ==="
ls -l /data/adb/anland-chrome/ 2>&1
echo ""
echo "=== app 版本 ==="
dumpsys package com.anland.appwrap 2>/dev/null | grep -m3 -E 'versionName|versionCode|lastUpdateTime'
echo ""
echo "=== 进程 ==="
for n in chrome libglproxysrv waylandbridge libawlrelay Xwayland anland-miniwm pulseaudio; do
  p=$(pgrep -f "$n" 2>/dev/null | head -3 | tr '\n' ' ')
  echo "  $n: ${p:-（无）}"
done
echo ""
echo "=== glproxy 套接字 ==="
ls -l /data/local/tmp/awl/glproxy.sock 2>&1
echo ""
echo "=== glproxy 日志尾巴 ==="
tail -5 /data/local/tmp/glproxy.log 2>/dev/null
echo ""
echo "=== chrome GPU 进程命令行 ==="
for p in $(pgrep -f 'chrome .*--type=gpu-process' 2>/dev/null); do
  echo "  pid $p:"
  tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | tr ' ' '\n' | grep -E 'use-angle|use-gl|swiftshader|type=' | sed 's/^/    /'
done
echo ""
echo "=== chrome 映射到的 libEGL/libGLESv2 ==="
for p in $(pgrep -f '/opt/google/chrome/chrome' 2>/dev/null | head -3); do
  echo "  pid $p:"
  grep -E 'libEGL|libGLESv2' /proc/$p/maps 2>/dev/null | awk '{print $6}' | sort -u | sed 's/^/    /'
done
echo ""
echo "=== chrome://gpu 依据：GPU 进程里的 Adreno/ANGLE 字样 ==="
for p in $(pgrep -f 'chrome .*--type=gpu-process' 2>/dev/null); do
  grep -c -i 'libGLESv2\|libEGL' /proc/$p/maps 2>/dev/null | sed 's/^/    maps 命中 /'
done
echo DEVSTATUS-DONE
