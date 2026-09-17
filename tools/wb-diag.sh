#!/system/bin/sh
# wb-diag.sh —— 诊断守护进程为什么起不来
set -u
M=/data/adb/modules/anland-awl
T=/data/local/tmp

echo "== 1) SELinux 策略里到底还有没有 awl_daemon_exec 这个类型 =="
touch "$T/lbltest" 2>/dev/null
if chcon u:object_r:awl_daemon_exec:s0 "$T/lbltest" 2>/dev/null; then
  echo "chcon OK → 类型存在（策略已加载）"
else
  echo "chcon 失败 → 类型不存在（模块 sepolicy 没生效！）"
fi
ls -lZ "$T/lbltest" 2>&1

echo
echo "== 2) 模块里那个二进制的标签 =="
ls -lZ "$M/waylandbridge" 2>&1

echo
echo "== 3) 拷贝副本、前台跑 5 秒、输出落盘 =="
cp -f "$M/waylandbridge" "$T/wb-test" 2>/dev/null
chmod 755 "$T/wb-test"
rm -f "$T/wb.out"
( cd "$T" && ./wb-test > "$T/wb.out" 2>&1 < /dev/null & )
sleep 5
echo "--- wb.out（$([ -f "$T/wb.out" ] && wc -c < "$T/wb.out" || echo 无) 字节） ---"
cat "$T/wb.out" 2>&1 | head -30

echo
echo "== 4) 进程 =="
ps -A -o PID,USER,CMD | grep -E 'waylandbridge|wb-test' | grep -v grep || echo "(没有)"

echo
echo "== 5) 套接字 =="
ls -l "$T/awl/" 2>&1
