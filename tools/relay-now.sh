#!/system/bin/sh
# relay-now.sh —— 帧还在流吗？（配合 --ez rv true 打开中继 verbose 时用）
# 8 秒内中继转发消息数的增量 = 画面是否还在更新。0 就是画面已经停了。
n1=$(logcat -d -s appwrap:* 2>/dev/null | grep -c '字节')
sleep 8
n2=$(logcat -d -s appwrap:* 2>/dev/null | grep -c '字节')
echo "中继消息增量 8s = $((n2 - n1))   （0 = 画面已停；几十以上 = 在动）"

echo "--- 守护进程最近窗口事件 ---"
logcat -d -s anland-daemon -s anland-wl 2>/dev/null | grep -iE 'window|attached|ACTIVATED|commit' | tail -5

echo "--- App 侧 ---"
logcat -d -s appwrap:* 2>/dev/null | grep -E '窗口创建|挂载窗口|关闭旧窗口|流结束' | tail -4
echo "  chrome=$(pgrep chrome | wc -l) relay=$(pgrep libawlrelay | wc -l) sf=$(pidof surfaceflinger)"
echo "  合成器卡死报错=$(logcat -d -s appwrap:* | grep -c CompositorAnimationObserver)"
