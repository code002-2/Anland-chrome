#!/system/bin/sh
# setup.sh —— 一次性做三件事（必须经 App 的远程钩子跑，root + App 的 mount namespace）：
#   1. 修复被写坏的 coreutils 多调用二进制（115 个 applet 共享一个 inode）
#   2. 写守护进程 config.json：scale_mode=1 (FIT 等比+黑边)，治"网页比例崩了"
#      （守护进程默认 AWL_SCALE_STRETCH=0 按轴拉伸，config.json 缺失时就是它）
#   3. 重启 waylandbridge，并顺手验证「模块目录里的二进制能不能直接 exec」
#      （adb shell 的 su 里不行 —— KernelSU 的挂载命名空间差异，所以才一直用
#        /data/local/tmp/wb 这份拷贝；在 App 的命名空间里应该可以）
set -u
M=/data/adb/modules/anland-awl
R=/data/adb/anland-chrome/root
T=/data/local/tmp

echo "########## 1. 修 coreutils ##########"
ls -l "$T/coreutils.new" "$R/usr/bin/coreutils" 2>&1
if cp -f "$T/coreutils.new" "$R/usr/bin/coreutils"; then echo "cp 覆盖成功（inode 不变 → 115 个硬链接一起复活）"; else echo "!!! cp 失败"; fi
chown 0:0 "$R/usr/bin/coreutils" 2>/dev/null
chmod 755 "$R/usr/bin/coreutils" 2>/dev/null
ls -l "$R/usr/bin/coreutils" "$R/usr/bin/env" 2>&1
echo "--- 直接跑 /usr/bin/coreutils ---"
"$R/usr/bin/coreutils" --version 2>&1 | head -2
echo "--- 直接跑 /usr/bin/env ---"
"$R/usr/bin/env" --version 2>&1 | head -2
echo "--- chroot 里跑 env -i（Chrome 启动命令的第一段）---"
chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/env 2>&1 | head -3
echo "--- ls / rm / cat 这些 applet ---"
for a in ls rm cat cp mkdir sed grep; do "$R/usr/bin/coreutils" "$a" --version >/dev/null 2>&1 && echo "  $a ok" || echo "  $a FAIL"; done

echo ""
echo "########## 2. 写 config.json（scale_mode=1 FIT）##########"
cat > "$M/config.json" <<'EOF'
{
  "runtime_dir": "/data/local/tmp/awl",
  "socket_listen": 1,
  "scale_mode": 1,
  "auto_attach": 0,
  "sc_enabled": 1
}
EOF
chmod 644 "$M/config.json" 2>/dev/null
cat "$M/config.json" 2>&1

echo ""
echo "########## 3. 重启守护进程 ##########"
pkill waylandbridge 2>/dev/null
sleep 1
if [ -x "$M/waylandbridge" ]; then
  cd "$M" || cd /
  setsid ./waylandbridge > "$T/awl_daemon.log" 2>&1 < /dev/null &
  echo "已从模块目录启动"
else
  echo "模块目录里的 waylandbridge 不可执行，退回 $T/wb 拷贝"
  setsid "$T/wb" > "$T/awl_daemon.log" 2>&1 < /dev/null &
fi
sleep 3
echo "--- 进程 ---"
ps -A -o PID,USER,CMD 2>/dev/null | grep waylandbridge | grep -v grep || echo "(没起来)"
echo "--- 套接字 ---"
ls -l "$T/awl/" 2>&1
echo "--- 守护进程日志尾部 ---"
logcat -d -s anland-daemon -s anland-wl 2>/dev/null | tail -25
echo "--- pulse.sock ---"
ls -l "$T/awl/pulse.sock" 2>&1
echo "########## 结束 ##########"
