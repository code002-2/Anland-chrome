#!/system/bin/sh
# rf-repack.sh —— 把精简后的 rootfs 打成 tar（不压缩；压缩在 PC 上做，手机 CPU 太慢）
# 排除运行期产物与挂载点，保持与原 tarball 一致的 ./ 开头布局。
R=/data/local/tmp/rf-prune/root
OUT=/data/local/tmp/rf-new.tar
LOG=/data/local/tmp/rf-repack.log
{
  echo "开始 $(date)"
  rm -f "$OUT"
  cd "$R" || exit 1
  tar -cf "$OUT" \
      --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' \
      --exclude='./tmp/*' --exclude='./run/*' \
      --exclude='./root/.chrome' --exclude='./root/.config' --exclude='./root/.cache' \
      --exclude='./var/log/*' --exclude='./var/tmp/*' \
      . 2>/dev/null
  echo "打包完成 $(date)"
  ls -l "$OUT"
  echo "RF-REPACK-DONE"
} > "$LOG" 2>&1
