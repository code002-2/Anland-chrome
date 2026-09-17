#!/system/bin/sh
# rf-prune-bg.sh —— 后台执行精简（长任务，输出写日志）
setsid sh /data/local/tmp/rf-prune.sh > /dev/null 2>&1 < /dev/null &
echo "已启动，日志 /data/local/tmp/rf-prune.log"
