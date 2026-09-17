#!/system/bin/sh
# rf-prune2-bg.sh —— 后台执行第二轮精简
setsid sh /data/local/tmp/rf-prune2.sh > /dev/null 2>&1 < /dev/null &
echo "已启动，日志 /data/local/tmp/rf-prune2.log"
