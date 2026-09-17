#!/system/bin/sh
# diag.sh —— 窗口/进程全景：谁在跑、守护进程认得几个窗口、界面挂的是哪个。
echo "=== 把 logcat 环形缓冲调大（默认 4MiB 太容易被刷爆，前面因此丢过日志）==="
logcat -G 16M 2>&1
logcat -G 2>&1 | head -3

echo "=== Chrome 进程（PID / 运行时长 / 关键参数）==="
ps -A -o PID,ETIME,CMD 2>/dev/null | grep -E 'chrome' | grep -vE 'grep|appwrap' \
  | sed 's/--[a-z-]*=[^ ]*//g' | cut -c1-110 | head -10

echo "=== 守护进程认得的窗口（最近 12 条事件）==="
logcat -d -s anland-daemon -s anland-wl 2>/dev/null | grep -iE 'window|toplevel|surface .* (destroy|map)' | tail -12

echo "=== App 自己记的窗口状态 ==="
logcat -d -s appwrap:* 2>/dev/null | grep -E '窗口|挂载|已有 Chrome|中继就绪|Chrome 已启动|流结束' | tail -12

echo "=== 最前面的 Activity ==="
dumpsys activity activities 2>/dev/null | grep -m2 -E 'topResumedActivity|mResumedActivity' | cut -c1-120

echo "=== 稳定性 ==="
echo "  surfaceflinger=$(pidof surfaceflinger)  app=$(pidof com.anland.appwrap)  relay=$(pidof libawlrelay)"
echo "  SkImage 崩溃累计=$(logcat -d -b crash | grep -c 'Unable to generate SkImage')"
echo "  合成器卡死报错=$(logcat -d -s appwrap:* | grep -c CompositorAnimationObserver)"
top -n 1 -b 2>/dev/null | grep chrome | awk '{s+=$9} END {printf "  chrome 总 CPU %.0f%%\n", s}'
