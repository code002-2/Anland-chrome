#!/system/bin/sh
# what-gl.sh —— 看清"实际生效"的是什么：Chrome 用的 GL 后端 + chroot 环境的 MESA 变量
R=/data/adb/anland-chrome/root

echo "=== Chrome 主进程命令行里的 GL 相关参数 ==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in
    *"--type="*) continue;;
  esac
  echo "$cl" | tr ' ' '\n' | grep -E 'use-gl|use-angle|swiftshader|ozone|device-scale' | sed 's/^/  /'
done

echo "=== Chrome 进程环境里的 MESA/KGSL 变量（有没有真的传进去）==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in
    *"--type=gpu-process"*) ;;
    *) continue;;
  esac
  echo "  gpu-process pid=$p:"
  tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -iE 'MESA|GALLIUM|LIBGL|KGSL|DRM|ANGLE' | sed 's/^/    /'
  echo "    (以上为空 = 没有任何 Mesa 变量进去)"
  break
done

echo "=== GPU 进程实际加载了哪个 GL 库 ==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in
    *"--type=gpu-process"*) ;;
    *) continue;;
  esac
  grep -iE 'swiftshader|libEGL|libGLES|mesa|kgsl|freedreno|vulkan' /proc/$p/maps 2>/dev/null \
    | sed 's/.*\//  /' | sort -u | head -12
  break
done

echo "=== 谁真的用了 Mesa（只有这些才会碰真 GPU）==="
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  if grep -qi 'mesa\|gallium\|kgsl_dri\|msm_dri' /proc/$p/maps 2>/dev/null; then
    echo "  pid=$p $(cat /proc/$p/comm 2>/dev/null) → $(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-60)"
  fi
done

echo "=== 现状 ==="
echo "  surfaceflinger=$(pidof surfaceflinger)"
echo "  SkImage 崩溃累计=$(logcat -d -b crash | grep -c 'Unable to generate SkImage')"
echo "  合成器卡死报错=$(logcat -d -s appwrap:* | grep -c CompositorAnimationObserver)"
top -n 1 -b 2>/dev/null | grep -E 'gpu-process' | head -2 | cut -c1-120
