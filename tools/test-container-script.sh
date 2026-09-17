#!/bin/sh
# test-container-script.sh —— 本地回归测试：验证 Launcher.containerScript 拼出来的那段脚本
#
# 用桩程序 su / droidspaces 在宿主 POSIX shell 里跑一遍完整链路，确认三件事：
#   1) base64 包装让**任意字符**的容器命令原样穿过 su → sh → droidspaces；
#   2) @FD@ 只在最外层被替换成真实 fd 号，容器侧看到的是一个数字；
#   3) 生成的容器侧脚本本身可执行（`exec env WAYLAND_SOCKET=<n> <cmd>`）。
#
# 用法: sh tools/test-container-script.sh     （Windows 上可用 Git 自带 sh.exe）
set -eu

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PATH="$TMP:$PATH"
export PATH
export DS_CAPTURE="$TMP/payload.txt"

# ---- 桩：su -c '<script>' → 跑该脚本（不碰环境，模拟 KernelSU su 的行为） ----
cat > "$TMP/su" <<'STUB'
#!/bin/sh
shift                       # 丢掉 -c
exec sh -c "$1"
STUB

# ---- 桩：droidspaces -n <ctr> run '<script>' → 捕获并在“容器内”执行 ----
cat > "$TMP/droidspaces" <<'STUB'
#!/bin/sh
[ "$1" = "-n" ] || { echo "stub: bad argv: $*" >&2; exit 2; }
[ "$3" = "run" ] || { echo "stub: bad argv: $*" >&2; exit 2; }
printf '%s' "$4" > "$DS_CAPTURE"      # 容器侧真正拿到的东西
exec sh -c "$4"
STUB
chmod +x "$TMP/su" "$TMP/droidspaces"

# ---- 与 Launcher.containerScript() 完全相同的构造方式（Java 侧是 android.util.Base64 NO_WRAP，
#      与 GNU base64 -w0 等价） ----
CTR='my container'                    # 故意带空格
CMD=$(cat <<'EOC'
foot --title "我的 终端 'x'" -e sh -c 'echo $HOME && echo "a b"; # 注释风格的行尾'
EOC
)
PAYLOAD="exec env WAYLAND_SOCKET=@FD@ $CMD"
B64=$(printf %s "$PAYLOAD" | base64 -w0)
SCRIPT='if [ -z "$WAYLAND_SOCKET" ]; then echo "appwrap: WAYLAND_SOCKET 未继承到 su 子进程(su 清空环境?)" >&2; exit 9; fi
exec droidspaces -n '"'$CTR'"' run "$(printf %s '"'$B64'"' | base64 -d | sed "s/@FD@/$WAYLAND_SOCKET/g")"'

echo "== 1) 未继承环境变量时应立即报错 =="
if (unset WAYLAND_SOCKET; su -c "$SCRIPT" >/dev/null 2>&1); then
    echo "FAIL: 少了 WAYLAND_SOCKET 竟然没报错"; exit 1
else
    echo "PASS: 退出码非 0（脚本里的前置检查生效）"
fi

echo
echo "== 2) 正常路径：WAYLAND_SOCKET=7 一路继承 =="
( WAYLAND_SOCKET=7 su -c "$SCRIPT" ) >/dev/null 2>&1 || true

printf '%s' "exec env WAYLAND_SOCKET=7 $CMD" > "$TMP/expected.txt"
if diff -u "$TMP/expected.txt" "$DS_CAPTURE" > "$TMP/diff.txt" 2>&1; then
    echo "PASS: 容器侧收到的 payload 与期望逐字节一致"
else
    echo "FAIL: payload 不一致"; cat "$TMP/diff.txt"; exit 1
fi
echo "--- 容器侧 payload ---"; cat "$DS_CAPTURE"; echo

echo
echo "== 3) 该 payload 可直接执行，且 fd 号是字面数字 =="
cat > "$TMP/foot" <<'STUB'
#!/bin/sh
echo "FOOT wayland_fd=[$WAYLAND_SOCKET] argc=$# argv=[$*]"
STUB
chmod +x "$TMP/foot"
sh -c "$(cat "$DS_CAPTURE")"

echo
echo "全部通过。"
