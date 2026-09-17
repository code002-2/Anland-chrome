#!/system/bin/sh
# rf-inventory.sh —— rootfs 空间盘点（只读，不动任何文件）
R=/data/adb/anland-chrome/root
echo "=== 总大小 / 文件数 ==="
du -sh "$R" 2>/dev/null
echo "文件数: $(find "$R" -type f 2>/dev/null | wc -l)  目录: $(find "$R" -type d 2>/dev/null | wc -l)  符号链接: $(find "$R" -type l 2>/dev/null | wc -l)"

echo ""
echo "=== 一级目录（降序前 22）==="
du -sh "$R"/* 2>/dev/null | sort -h | tail -22

echo ""
echo "=== 重点子树 ==="
for d in usr/lib usr/share usr/bin usr/sbin bin sbin lib etc opt var usr/src usr/include \
         usr/lib/aarch64-linux-gnu usr/lib/locale usr/share/fonts usr/share/doc usr/share/man \
         usr/share/locale usr/share/perl usr/share/python3 usr/lib/python3 usr/lib/gcc \
         usr/lib/modules usr/share/icons usr/share/i18n root home srv tmp; do
  [ -e "$R/$d" ] && du -sh "$R/$d" 2>/dev/null
done

echo ""
echo "=== 单个大文件（>30MB，前 20）==="
find "$R" -type f -size +30M 2>/dev/null | while read f; do
  echo "$(du -m "$f" 2>/dev/null | cut -f1)MB $f"
done | sort -rn | head -20

echo ""
echo "=== Mesa/DRI 驱动（几十个只服务别的 GPU 的驱动）==="
du -sh "$R/usr/lib/aarch64-linux-gnu/dri" 2>/dev/null
ls "$R/usr/lib/aarch64-linux-gnu/dri" 2>/dev/null | wc -l
du -sh "$R/usr/lib/aarch64-linux-gnu/libgallium"* 2>/dev/null
ls -S "$R/usr/lib/aarch64-linux-gnu/dri" 2>/dev/null | head -8

echo ""
echo "=== Chrome 本体 ==="
du -sh "$R/opt/google/chrome" 2>/dev/null
du -sh "$R/opt/google/chrome/"* 2>/dev/null | sort -h | tail -8

echo ""
echo "=== 可删候选合计 ==="
for d in usr/share/doc usr/share/man usr/share/info usr/include usr/src usr/lib/gcc \
         var/cache/apt var/lib/apt/lists var/log usr/share/perl usr/share/i18n \
         usr/share/lintian usr/share/bug usr/lib/php; do
  [ -e "$R/$d" ] && du -sh "$R/$d" 2>/dev/null
done
