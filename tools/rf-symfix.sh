#!/system/bin/sh
# rf-symfix.sh -- 第三轮精简后的收尾：查所有断链符号链接，并把 coreutils 那批修回来
#
# 背景：/usr/bin/{env,ls,cat,...} 原本都是指向 ../lib/cargo/bin/coreutils/<name> 的符号链接，
# 而本轮把 /usr/lib/cargo 整块删了 -> 115 个符号链接全断 -> chroot 里连 /usr/bin/env 都起不来。
# 修法：把这些链接改成指向同目录的 coreutils（GNU coreutils 单文件多调用，靠 argv[0] 分派）。
DST=/data/local/tmp/rf3/root
LOG=/data/local/tmp/rf-symfix.log
{
echo "=== A. 修 coreutils 那批断链 ==="
fixed=0
for d in "$DST"/usr/bin "$DST"/bin "$DST"/sbin "$DST"/usr/sbin "$DST"/usr/local/bin; do
  [ -d "$d" ] || continue
  for l in "$d"/*; do
    [ -L "$l" ] || continue
    t=$(readlink "$l")
    case "$t" in
      *cargo/bin/coreutils*)
        n="${l##*/}"
        if [ -e "$d/coreutils" ] && [ "$n" != coreutils ]; then
          rm -f "$l"; ln -s coreutils "$l"; fixed=$((fixed+1))
        else
          echo "  !! $l -> $t（同目录没有 coreutils 可用）"
        fi
        ;;
    esac
  done
done
echo "  重指向 $fixed 个符号链接"

echo ""
echo "=== B. 全部断链符号链接 ==="
: > /data/local/tmp/rf-dangling.txt
cnt=0
find "$DST" -type l 2>/dev/null | while read -r l; do
  if [ ! -e "$l" ]; then echo "${l#$DST} -> $(readlink "$l")" >> /data/local/tmp/rf-dangling.txt; fi
done
cnt=$(wc -l < /data/local/tmp/rf-dangling.txt)
echo "  断链总数: $cnt"
echo "  --- 前 40 条 ---"
head -40 /data/local/tmp/rf-dangling.txt | sed 's/^/    /'
echo "  --- /usr/bin 下的断链 ---"
grep '^/usr/bin/' /data/local/tmp/rf-dangling.txt | head -20 | sed 's/^/    /'
echo "  --- /etc 下的断链 ---"
grep '^/etc/' /data/local/tmp/rf-dangling.txt | head -20 | sed 's/^/    /'
echo "  --- /usr/lib 下的断链（前 20）---"
grep '^/usr/lib' /data/local/tmp/rf-dangling.txt | head -20 | sed 's/^/    /'

echo ""
echo "=== C. chroot 功能冒烟 ==="
CS="chroot $DST /usr/bin/env -i PATH=/usr/bin:/bin:/sbin:/usr/sbin HOME=/root"
$CS /usr/bin/env echo "  env ok"
$CS /usr/bin/coreutils --version 2>&1 | head -1 | sed 's/^/  /'
$CS /bin/sh -c 'echo "  sh ok: $(id -u)"' 2>&1 | sed 's/^/  /'
$CS /usr/bin/ls /usr/bin/env 2>&1 | sed 's/^/  ls: /'
$CS /usr/bin/ln -sf /tmp/x /tmp/y && echo "  ln ok"
$CS /usr/bin/rm -f /tmp/y && echo "  rm ok"
$CS /usr/bin/mkdir -p /tmp/t1 && echo "  mkdir ok"
$CS /usr/bin/chmod 755 /tmp/t1 && echo "  chmod ok"
$CS /usr/bin/rmdir /tmp/t1 && echo "  rmdir ok"
$CS /usr/bin/sleep 0 && echo "  sleep ok"
$CS /usr/bin/pgrep -l waylandbridge 2>&1 | head -2 | sed 's/^/  pgrep: /'
$CS /usr/bin/tar --version 2>&1 | head -1 | sed 's/^/  tar: /'
$CS /usr/bin/ldd /opt/google/chrome/chrome 2>&1 | grep -c 'not found' | sed 's/^/  chrome not-found 数: /'
$CS /opt/google/chrome/chrome --version 2>&1 | head -2 | sed 's/^/  chrome --version: /'

echo ""
echo "=== D. 体积 ==="
du -sh "$DST"
echo "文件数: $(find "$DST" -type f | wc -l)"
echo "SYMFIX-DONE"
} > "$LOG" 2>&1
echo "logged to $LOG"
