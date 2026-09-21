#!/system/bin/sh
# gl-check.sh —— GL 代理状态与安全性检查
echo "=== SurfaceFlinger 安危（GPU 加速安全性的核心指标）==="
echo "  SF pid            = $(pidof surfaceflinger)"
echo "  SkImage 崩溃累计  = $(logcat -d -b crash 2>/dev/null | grep -c 'Unable to generate SkImage')"
echo "  SF abort 累计     = $(logcat -d -b crash 2>/dev/null | grep -c 'surfaceflinger')"
echo "  uptime            = $(cut -d' ' -f1 /proc/uptime) 秒"
echo ""
echo "=== GL 代理服务端 ==="
echo "  pid = $(pidof glproxy-server)"
echo "  socket: $(ls -l /data/local/tmp/awl/glproxy.sock 2>&1)"
echo ""
echo "=== 探针结果（含延迟测量）==="
tail -16 /data/local/tmp/glproxy-run.log 2>&1
echo ""
echo "=== 服务端日志 ==="
logcat -d -s glproxy:* 2>/dev/null | tail -8
