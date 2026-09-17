#!/system/bin/sh
# rf-inv-bg.sh —— 把盘点丢到后台写文件（RootExec 要等进程结束才回传输出，长任务看不到进度）
setsid sh /data/local/tmp/rf-inventory.sh > /data/local/tmp/rf-inv.txt 2>&1 < /dev/null &
echo "已启动，输出写到 /data/local/tmp/rf-inv.txt"
