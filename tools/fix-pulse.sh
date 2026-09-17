#!/system/bin/sh
# fix-pulse.sh —— 修模块里 pulse 的可执行位，并按 service.sh 的方式启动 PulseAudio
# （模块 zip 里的 pulse/bin/* 过来时丢了 exec 位，导致 service.sh 的 PA 段被静默跳过）
set -u
MODDIR=/data/adb/modules/anland-awl
RT=/data/local/tmp/awl
PA="$MODDIR/pulse"

echo "== 修权限 =="
chmod 755 "$MODDIR/pulse/bin/"* 2>/dev/null
chmod 755 "$MODDIR/service.sh" "$MODDIR/waylandbridge" 2>/dev/null
ls -l "$PA/bin/pulseaudio"

if [ ! -x "$PA/bin/pulseaudio" ]; then
  echo "!! pulseaudio 仍不可执行，放弃"
  exit 1
fi

PAUID=$(awk '$1=="com.anlandnext"{print $2; exit}' /data/system/packages.list 2>/dev/null)
if [ -z "$PAUID" ]; then
  echo "!! com.anlandnext 没装（模块要用它的 uid 跑 PA，Android 12+ 才允许创建音频流）"
  exit 1
fi
echo "== com.anlandnext uid = $PAUID =="

PAR="$RT/pulse"
rm -rf "$PAR"
cp -r "$PA" "$PAR"
chmod -R 755 "$PAR"
chcon u:object_r:awl_daemon_exec:s0 "$PAR/bin/pulseaudio" 2>/dev/null
echo "dl-search-path = $PAR/lib/pulseaudio/modules" >> "$PAR/etc/pulse/daemon.conf"

PH="$RT/pulse-home"
rm -rf "$PH"; mkdir -p "$PH/run" "$PH/state"
chown -R "$PAUID:$PAUID" "$PH"; chmod 700 "$PH" "$PH/run" "$PH/state"
rm -f "$RT/pulse.sock"

nohup su "$PAUID" -c "export HOME='$PH' TMPDIR='$PH' PULSE_RUNTIME_PATH='$PH/run' \
PULSE_STATE_PATH='$PH/state' PULSE_CONFIG_PATH='$PAR/etc/pulse' \
LD_LIBRARY_PATH='$PAR/lib:$PAR/lib/pulseaudio:$PAR/lib/pulseaudio/modules'; \
exec '$PAR/bin/pulseaudio' --daemonize=no --exit-idle-time=-1 --disallow-exit \
--log-target=stderr -n -F '$PAR/etc/pulse/default.pa' \
-L 'module-native-protocol-unix auth-anonymous=1 socket=$RT/pulse.sock'" \
  > /data/local/tmp/awl_pulse.log 2>&1 &

sleep 3
echo "== 结果 =="
ls -l "$RT/pulse.sock" 2>&1
echo "--- pulse 日志尾部 ---"
tail -15 /data/local/tmp/awl_pulse.log 2>&1
