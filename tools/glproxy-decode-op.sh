#!/system/bin/sh
# decode-op.sh -- which function is op 0x1020 (= GLP_OP_GL_BASE + 32)?
R=/data/adb/anland-chrome/root
B=$R/build/glproxy
echo "=== op 0x1020 (= base + 32) ==="
grep -E 'GLP_OP_GL_BASE \+ 32,' "$B/glp_gen.h"
echo "=== 附近几个（30..34）==="
grep -E 'GLP_OP_GL_BASE \+ (30|31|32|33|34),' "$B/glp_gen.h"
echo "=== 名字表里有没有这几个手写入口 ==="
for n in eglGetPlatformDisplayEXT eglGetPlatformDisplay glFinish; do
  printf "  %-26s %s\n" "$n" "$(grep -c "\"$n\"" "$B/glp_gen_client.c")"
done
echo "=== 客户端桩是否是 stub（body 里出现 glp_unsupported 的多不多）==="
grep -c 'glp_unsupported' "$B/glp_gen_client.c"
echo "DECODE-DONE"
