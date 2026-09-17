#!/system/bin/sh
# restart-pa.sh —— 重新拉起 PulseAudio 的"Android 真实 sink"。
#
# 背景：模块 service.sh 里 PA 是以 **com.anlandnext 的 uid** 起的（Android 12+ 的
# AudioPolicyService 拒绝"uid 不对应任何包"的进程建音频流 → root 起会 OpenSL ES error 9），
# default.pa 的主 sink 是 module-sles-sink，失败才由 module-always-sink 顶上 null sink。
# 本次故障日志：
#   E: module-sles-sink.c: Failed to initialize OpenSL ES: error 9
#   E: module.c: Failed to load module "module-sles-sink": initialization failed.
#   E: main.c: Sink android does not exist.
# error 9 = DEVICE_UNAVAILABLE —— PA 是在框架软重启刚结束时启动的，音频服务还没就绪。
# 本脚本就是"照 service.sh 再来一次"，sles 不行就自动改用 AAudio sink。
#
# 用法（必须经 App 的钩子/广播跑，root）：
#   am broadcast -n com.anland.appwrap/.CmdReceiver -a com.anland.appwrap.CMD --es shf /data/local/tmp/restart-pa.sh
set -u
M=/data/adb/modules/anland-awl
RT=/data/local/tmp/awl
PA="$M/pulse"
PAR="$RT/pulse"
PH="$RT/pulse-home"
LOG=/data/local/tmp/awl_pulse.log
R=/data/adb/anland-chrome/root

PAUID=$(awk '$1=="com.anlandnext"{print $2; exit}' /data/system/packages.list 2>/dev/null)
echo "com.anlandnext uid = ${PAUID:-（找不到！）}"
[ -n "$PAUID" ] || exit 1

pactl_() {
  chroot "$R" /usr/bin/env -i PULSE_SERVER=unix:/run/anland/pulse.sock /usr/bin/pactl "$@" 2>&1
}

start_pa() {
  nohup su "$PAUID" -c "export HOME='$PH' TMPDIR='$PH' PULSE_RUNTIME_PATH='$PH/run' \
PULSE_STATE_PATH='$PH/state' PULSE_CONFIG_PATH='$PAR/etc/pulse' \
LD_LIBRARY_PATH='$PAR/lib:$PAR/lib/pulseaudio:$PAR/lib/pulseaudio/modules'; \
exec '$PAR/bin/pulseaudio' --daemonize=no --exit-idle-time=-1 --disallow-exit \
--log-target=stderr -n -F '$PAR/etc/pulse/default.pa' \
-L 'module-native-protocol-unix auth-anonymous=1 socket=$RT/pulse.sock'" \
    > "$LOG" 2>&1 &
}

prepare() {
  pkill pulseaudio 2>/dev/null
  sleep 1
  rm -rf "$PAR"; cp -r "$PA" "$PAR"; chmod -R 755 "$PAR"
  chcon u:object_r:awl_daemon_exec:s0 "$PAR/bin/pulseaudio" 2>/dev/null
  grep -q '^dl-search-path' "$PAR/etc/pulse/daemon.conf" 2>/dev/null \
    || echo "dl-search-path = $PAR/lib/pulseaudio/modules" >> "$PAR/etc/pulse/daemon.conf"
  rm -rf "$PH"; mkdir -p "$PH/run" "$PH/state"
  chown -R "$PAUID:$PAUID" "$PH"; chmod 700 "$PH" "$PH/run" "$PH/state"
  rm -f "$RT/pulse.sock"
}

sink_ok() {
  # 有名为 android 的 sink（不是 null 兜底）就算成功
  pactl_ list short sinks | grep -q '[[:space:]]android[[:space:]]'
}

echo "########## 第一轮：默认（OpenSL ES sink）##########"
prepare
start_pa
sleep 5
pactl_ list short sinks
if sink_ok; then echo "RESULT: OpenSL ES sink 成功 ✓"; else
  echo "sles 没起来，看日志:"; tail -6 "$LOG"
  echo "########## 第二轮：换 AAudio sink ##########"
  sed -i 's/^load-module module-sles-sink/# &/' "$PAR/etc/pulse/default.pa"
  if grep -q '^#load-module module-aaudio-sink' "$PAR/etc/pulse/default.pa"; then
    sed -i 's/^#load-module module-aaudio-sink/load-module module-aaudio-sink/' "$PAR/etc/pulse/default.pa"
  else
    sed -i 's|^set-default-sink android|load-module module-aaudio-sink sink_name=android sink_properties=device.description=Android\nset-default-sink android|' "$PAR/etc/pulse/default.pa"
  fi
  grep -E 'load-module module-(sles|aaudio)' "$PAR/etc/pulse/default.pa"
  prepare
  start_pa
  sleep 5
  pactl_ list short sinks
  if sink_ok; then echo "RESULT: AAudio sink 成功 ✓"; else
    echo "RESULT: 两种 sink 都失败 ✗"; tail -8 "$LOG"
  fi
fi

echo "--- sink 详情 ---"
pactl_ list sinks | grep -E 'Name:|State:|Mute:|Volume: front-left' | head -6
echo "--- 日志尾部 ---"
tail -5 "$LOG"
