#!/system/bin/sh
# start-daemon.sh -- start waylandbridge detached from the adb/su session
# - copy out of the module dir: adb shell/su cannot exec it there (KernelSU mount ns)
# - setsid: so the su session exit does not take it down
set -u
T=/data/local/tmp

cp -f /data/adb/modules/anland-awl/waylandbridge "$T/wb" 2>/dev/null
chmod 755 "$T/wb"

pkill -f "$T/wb" 2>/dev/null
sleep 1

setsid "$T/wb" > /dev/null 2>&1 < /dev/null &
sleep 3

echo "== process =="
ps -A -o PID,CMD | grep "$T/wb" | grep -v grep || echo "(none)"
echo "== sockets =="
ls -l "$T/awl/" 2>&1
