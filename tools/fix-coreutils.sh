#!/system/bin/sh
# fix-coreutils.sh —— 修复被写坏的 coreutils 多调用二进制
#
# 事故：/usr/bin/env 是指向 /usr/lib/cargo/bin/coreutils/env 的符号链接，而整个
# /usr/lib/cargo/bin/coreutils/* 的 115 个 applet（含 env）都是**硬链接**，共享
# /usr/bin/coreutils 这一个 inode。当时用 `cat > /usr/bin/env` 写 wrapper，直接
# 把共享 inode 覆盖成了 227 字节的脚本 → 115 个 applet 全废。
# 硬链接无法单独恢复，只能把真正的二进制重新灌进同一个 inode（cp 覆盖内容，
# inode 不变，所有硬链接一起复活）。
#
# 真身从 PC 侧 tar 里抽：tar -xJf <rootfs.tar.xz> ./usr/bin/coreutils
# 用法（经 App 的远程钩子跑，必须由 App 的 su 子进程执行）：
#   am start -n com.anland.appwrap/.MainActivity --es shf /data/local/tmp/fix-coreutils.sh
set -x
CU=/data/adb/anland-chrome/root/usr/bin/coreutils
NEW=/data/local/tmp/coreutils.new

ls -l "$NEW" "$CU"
cp -f "$NEW" "$CU" || echo "!!! cp 失败"
chown 0:0 "$CU" 2>/dev/null
chmod 755 "$CU" 2>/dev/null
ls -l "$CU"

echo "--- coreutils 自检 ---"
"$CU" --version 2>&1 | head -2
echo "--- env 自检（chroot 里也试一次）---"
/data/adb/anland-chrome/root/usr/bin/env --version 2>&1 | head -2
R=/data/adb/anland-chrome/root
chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/env --version 2>&1 | head -2
echo "--- ls/cat 之类的 applet ---"
"$CU" ls / >/dev/null 2>&1 && echo "ls-ok" || echo "ls-FAIL"
