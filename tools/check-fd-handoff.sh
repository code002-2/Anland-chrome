#!/system/bin/sh
# check-fd-handoff.sh —— 容器路线的前置验证：**继承的 fd 能不能活着穿过 droidspaces 进容器**
#
# 为什么必须先验这一步：libawl 的容器路线完全建立在一个事实上 ——
# Awl.getWaylandFd() 在 APK 进程里创建 socketpair，SO_PEERCRED 在创建时就被固定成
# APK 的 uid；之后这个 fd 被 su → sh → droidspaces → 容器内程序一路继承，容器里的
# 程序拿它当 wayland 连接，守护进程就仍然认为客户端是 APK 的 uid，于是 SURFACE 鉴权
# （awl_window_client_uid(id) == 调用方 uid）通过，窗口能挂到 APK 自己名下。
#
# 如果 droidspaces 在进容器时把非 stdio 的 fd 关掉了，这条路就不通（改用第一方宿主
# APK 或走下面的「替代方案」注释）。
#
# 用法（设备上 root shell，或用 adb shell su）：
#   sh /data/local/tmp/check-fd-handoff.sh <容器名> [droidspaces路径]
#
# 判读：
#   FD9-ALIVE  → fd 继承链通，容器路线可行
#   FD9-MISSING→ droidspaces 关掉了继承的 fd（或 sh 开了 CLOEXEC），容器路线需要替代方案

CT="${1:?用法: check-fd-handoff.sh <容器名> [droidspaces路径]}"
DS="${2:-droidspaces}"

echo "== 0) droidspaces 与容器状态 =="
command -v "$DS" || echo "(PATH 里没有 $DS)"
"$DS" -n "$CT" pid

echo
echo "== 1) 打开一个测试 fd（fd 9，指向普通文件；shell 重定向默认不带 CLOEXEC）=="
# 这个 fd 与 wayland socketpair 在继承语义上等价：都是非 CLOEXEC 的已打开描述符
exec 9</system/build.prop
ls -l /proc/self/fd/9

echo
echo "== 2) 让 droidspaces 在容器里列 fd（看 9 是否还在）=="
"$DS" -n "$CT" run 'if [ -e /proc/self/fd/9 ]; then echo FD9-ALIVE; ls -l /proc/self/fd/9; else echo FD9-MISSING; ls -l /proc/self/fd | head -20; fi'

echo
echo "== 3) 再验一次环境变量是否也能带进容器（WAYLAND_SOCKET 靠它传播）=="
WAYLAND_SOCKET=9 "$DS" -n "$CT" run 'echo "容器内 WAYLAND_SOCKET=[$WAYLAND_SOCKET]"'

echo
echo "== 结论 =="
echo "两步都正常 → APK 的「容器」模式应该可用（fd 号在容器内保持不变）。"
echo "FD9-MISSING 或环境变量为空 → 容器路线不通，可选："
echo "  a) 用第一方宿主 APK（com.anlandnext）显示容器窗口（它是 allowlist 身份，跳过 per-window uid 鉴权）；"
echo "  b) 在容器里用套接字文件连接（/run/anland/wayland-0，需要 daemon socket_listen=1），"
echo "     但那条连接的凭据是容器 uid，第三方 APK 无法挂载它的窗口；"
echo "  c) 写一个 Android 侧的 wayland 中继（按 wayland 消息边界转发，含 SCM_RIGHTS fd 转发）。"
