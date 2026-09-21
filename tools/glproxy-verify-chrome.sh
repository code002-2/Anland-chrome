#!/system/bin/sh
# gverify.sh -- hard evidence that Chrome's GPU process goes through our proxy
echo "=== 1. Chrome 进程里谁加载了我们的 libEGL/libGLESv2 ==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in *--type=gpu-process*) tag=GPU;; *--type=renderer*) tag=RENDERER;; *) tag=BROWSER;; esac
  hit=$(grep -oE '/(usr/lib/aarch64-linux-gnu|opt/glproxy/lib)/lib(GLESv2|EGL)[^ ]*' /proc/$p/maps 2>/dev/null | sort -u | tr '\n' ' ')
  [ -n "$hit" ] && echo "  [$tag] pid=$p -> $hit"
done
echo "=== 2. Chrome 自报的 GL 信息（gpu_init 日志）==="
logcat -d -s appwrap:* 2>/dev/null | grep -iE 'GL_RENDERER|GL_VENDOR|GL_VERSION|ANGLE|gl_implementation|EGL_VERSION' | grep -viE 'dbus' | tail -10
echo "=== 3. 代理服务端 ==="
echo "  glproxy-server pid=$(pidof glproxy-server)"
logcat -d -s glproxy:* 2>/dev/null | grep -cE '客户端接入'
echo "=== 4. 性能：Chrome 各进程 CPU ==="
top -n 1 -b 2>/dev/null | grep chrome | awk '{printf "  %-6s %-5s %s\n", $1, $9, substr($0, index($0,"chrome"))}' | cut -c1-90 | head -6
top -n 1 -b 2>/dev/null | grep chrome | awk '{s+=$9} END {printf "  chrome 合计 CPU %.0f%%（8 核 = 800%%）\n", s}'
echo "=== 5. 安全性 ==="
echo "  surfaceflinger pid=$(pidof surfaceflinger)  SkImage abort 累计=$(logcat -d -b crash 2>/dev/null | grep -c 'Unable to generate SkImage')"
echo "  uptime=$(cut -d' ' -f1 /proc/uptime) 秒"
echo "=== 6. 当前生效的渲染参数 ==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in *--type=gpu-process*)
    echo "$cl" | tr ' ' '\n' | grep -E 'use-gl|use-angle|device-scale|gpu-compositing' | sed 's/^/  /'
  ;; esac
done
echo "GVERIFY-DONE"
