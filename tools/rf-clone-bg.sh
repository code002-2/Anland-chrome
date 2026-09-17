#!/system/bin/sh
# rf-clone-bg.sh —— 后台克隆（RootExec 要等进程结束才回传输出，长任务必须丢后台 + 写日志）
setsid sh /data/local/tmp/rf-clone.sh > /dev/null 2>&1 < /dev/null &
echo "已启动，日志 /data/local/tmp/rf-clone.log"
