#!/system/bin/sh
# rf-restore.sh —— 把精简时误删的运行时库补回来（从在用的原 rootfs 拷）
# 教训：libgcc_s.so.1 / libstdc++.so.6 不是"开发工具"，是运行时必需品 ——
# 连 /usr/bin/env 都链接 libgcc_s，缺了它 Chrome 根本起不来（ldd 检查清单必须包含
# env / coreutils 这些启动链路里的二进制，只看 chrome 会漏掉）。
SRC=/data/adb/anland-chrome/root/usr/lib/aarch64-linux-gnu
DST=/data/local/tmp/rf-prune/root/usr/lib/aarch64-linux-gnu

for pat in 'libgcc_s.so*' 'libstdc++.so*' 'libatomic.so*'; do
  for f in $SRC/$pat; do
    [ -e "$f" ] || continue
    echo "补 $(basename "$f")  $(du -h "$f" 2>/dev/null | cut -f1)"
    cp -a "$f" "$DST/" 2>/dev/null
  done
done
echo "--- 现在有 ---"
ls -l "$DST" | grep -E 'libgcc_s|libstdc\+\+|libatomic'

echo "--- 启动链路依赖检查（这次带上 env / coreutils）---"
R=/data/local/tmp/rf-prune/root
for b in /usr/bin/env /usr/bin/coreutils /usr/bin/bash /usr/bin/sh /opt/google/chrome/chrome \
         /usr/bin/anland-miniwm /usr/bin/Xwayland /usr/bin/pactl; do
  if [ -e "$R$b" ]; then
    out=$(chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/ldd "$b" 2>&1 | grep 'not found')
    [ -n "$out" ] && { echo "  !! $b"; echo "$out" | sed 's/^/      /'; } || echo "  ok  $b"
  fi
done
echo "--- 直接跑一下环境 ---"
chroot "$R" /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/env 2>&1 | head -3
chroot "$R" /opt/google/chrome/chrome --version 2>&1 | head -3
echo "RF-RESTORE-DONE"
