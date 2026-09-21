#!/system/bin/sh
# glproxy-pull-gen.sh —— 把设备上生成的 glp_gen.* 拷到 /data/local/tmp 以便拉到 PC
# （服务端是 bionic，必须在 PC 上用 NDK 编译；生成却是在 chroot 里跑的）
R=/data/adb/anland-chrome/root
D=/data/local/tmp/glproxy-gen-out
mkdir -p "$D"
cp -f "$R/build/glproxy/glp_gen.h" "$R/build/glproxy/glp_gen_server.c" \
      "$R/build/glproxy/glp_unsupported.txt" "$D/" 2>&1
chmod 644 "$D"/* 2>/dev/null
ls -l "$D"
