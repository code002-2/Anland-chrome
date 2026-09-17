#!/system/bin/sh
# perf.sh —— 采样 Chrome 各进程的 CPU 占用 + 稳定性指标。用来客观对比不同参数组合。
#   am broadcast -n com.anland.appwrap/.CmdReceiver -a com.anland.appwrap.CMD \
#       -f 0x00000020 --es shf /data/local/tmp/perf.sh
echo "=== Chrome 进程 CPU（%CPU 一列，软件渲染时 gpu-process 会非常夸张）==="
top -n 1 -b 2>/dev/null | grep -E 'type=gpu-process|type=renderer|chrome --no-sandbox' | head -4 \
  | awk '{ printf "  %-6s %-5s %s\n", $1, $9, substr($0, index($0,"chrome")) }' | cut -c1-120

echo "=== 全部 chrome 进程 CPU 合计 ==="
top -n 1 -b 2>/dev/null | grep chrome | awk '{s+=$9} END {printf "  合计 %.0f%%（8 核 = 800%%）\n", s}'

echo "=== 稳定性 ==="
echo "  surfaceflinger=$(pidof surfaceflinger)"
echo "  chrome 进程数=$(pgrep chrome | wc -l)"
echo "  SkImage 崩溃累计=$(logcat -d -b crash | grep -c 'Unable to generate SkImage')"
echo "  合成器卡死报错=$(logcat -d -s appwrap:* | grep -c CompositorAnimationObserver)"

echo "=== 内存 ==="
free -m 2>/dev/null | sed -n '2p' | sed 's/^/  /'

echo "=== 当前生效的渲染参数 ==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in *"--type="*) continue;; esac
  echo "$cl" | tr ' ' '\n' | grep -E 'use-gl|use-angle|device-scale|reduced-motion|gpu-compositing|raster-threads' | sed 's/^/  /'
done
