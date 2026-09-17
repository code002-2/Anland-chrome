#!/system/bin/sh
# rf-clone.sh —— 把在用的 rootfs 克隆一份到工作区，供精简实验用（不动原目录）。
# 顺带排除运行期产物（Chrome profile / 缓存 / 日志），这些不属于发布内容。
SRC=/data/adb/anland-chrome/root
W=/data/local/tmp/rf-prune
DST=$W/root
LOG=/data/local/tmp/rf-clone.log

rm -rf "$W"
mkdir -p "$DST"
{
  echo "开始 $(date)"
  echo "--- 克隆（排除运行期产物）---"
  # 用 tar 管道克隆：保留符号链接/硬链接/权限/时间戳，比 cp -a 在 6 万文件上更快
  cd "$SRC" || exit 1
  tar -cf - \
      --exclude='./root/.chrome' --exclude='./root/.config' --exclude='./root/.cache' \
      --exclude='./tmp/*' --exclude='./var/log/*' --exclude='./var/tmp/*' \
      --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' \
      . 2>/dev/null | ( cd "$DST" && tar -xf - 2>/dev/null )
  echo "克隆完成 $(date)"
  echo "--- 大小 ---"
  du -sh "$DST" 2>/dev/null
  echo "文件数: $(find "$DST" -type f 2>/dev/null | wc -l)"
  echo "--- 顶层 ---"
  ls "$DST"
  echo "RF-CLONE-DONE"
} > "$LOG" 2>&1
