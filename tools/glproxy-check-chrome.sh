#!/system/bin/sh
# gq2.sh -- did Chrome's GPU process load our shim?
echo "=== processes mapping /opt/glproxy or system libEGL ==="
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  c=$(cat /proc/$p/comm 2>/dev/null)
  case "$c" in chrome|chrome_crashpad*) ;; *) continue;; esac
  if grep -qE 'glproxy/lib|aarch64-linux-gnu/lib(GL|EGL)' /proc/$p/maps 2>/dev/null; then
    echo "  pid=$p comm=$c"
    grep -oE '/[^ ]*lib(GL|EGL)[^ ]*' /proc/$p/maps 2>/dev/null | sort -u | sed 's/^/      /'
  fi
done
echo "=== glproxy-server ==="
echo "  pid=$(pidof glproxy-server)  sock=$(ls /data/local/tmp/awl/glproxy.sock 2>&1)"
echo "=== server log (client connections?) ==="
logcat -d -s glproxy:* 2>/dev/null | tail -8
echo "=== Firefox-style: chrome gpu process gl flags ==="
for p in $(pgrep chrome); do
  cl=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cl" in
    *--type=gpu-process*)
      echo "$cl" | tr ' ' '\n' | grep -E 'use-gl|use-angle|ozone-platform' | sed 's/^/  /'
      ;;
  esac
done
echo "GQ-DONE"
