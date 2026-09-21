#!/system/bin/sh
# rf-repack3.sh -- 把第三轮精简后的树重打成 tar（不压缩，压缩在 PC 上做，手机 CPU 慢）
R=/data/local/tmp/rf3/root
OUT=/data/local/tmp/rf3-new.tar
LOG=/data/local/tmp/rf-repack3.log
{
  echo "开始 $(date)"
  rm -f "$OUT"
  cd "$R" || exit 1
  tar -cf "$OUT" \
      --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' \
      --exclude='./tmp/*' --exclude='./run/*' \
      --exclude='./root/*' \
      --exclude='./var/log/*' --exclude='./var/tmp/*' --exclude='./var/cache/*' \
      . 2>/dev/null
  echo "打包完成 $(date)"
  ls -l "$OUT"
  echo "RF-REPACK3-DONE"
} > "$LOG" 2>&1
echo "logged to $LOG"
