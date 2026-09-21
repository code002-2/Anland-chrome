#!/system/bin/sh
# glproxy-go.sh —— 后台跑 Spike A，输出写日志
setsid sh /data/local/tmp/glproxy-run.sh > /dev/null 2>&1 < /dev/null &
echo "已启动，日志 /data/local/tmp/glproxy-run.log"
