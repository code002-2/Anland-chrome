package com.anland.appwrap;

import android.content.Context;
import android.util.Base64;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * 启动目标程序的三条路径 + shell 拼装工具。
 *
 * 【chroot 模式】—— 独立 APK 跑 glibc 桌面程序（Chrome）走这条
 *   前提：本 App 有 root（KernelSU 授权）。不依赖 Droidspaces、不依赖容器。
 *
 *   三种"画面怎么进守护进程"的后端（cfg.display）：
 *
 *   · DISP_X11（默认，推荐）：先在 chroot 里起 Xwayland，**由它**继承
 *     WAYLAND_SOCKET 连守护进程，Chrome 走 X11。原因：libwayland 读到
 *     WAYLAND_SOCKET 后会 unsetenv 掉它，而 Chromium 在初始化 Ozone 前会先探测
 *     一次 Wayland，那一探把变量吃掉，真正的连接就回退去连套接字文件 →
 *     "Failed to create wl_display (No such file or directory)"。Xwayland 是标准
 *     libwayland 客户端，不做预探测，把 fd 交给它最省事。窗口归属仍是本 App
 *     （凭据在 socketpair 创建时就固定了）。
 *   · DISP_WAYLAND_FD：直接把 WAYLAND_SOCKET 给 Chrome（保留用于对照/调试）。
 *   · DISP_WAYLAND_SOCKET：把守护进程 runtime 目录 bind 进 chroot，Chrome 以
 *     root 身份连 wayland-0 套接字。窗口属于 root —— 本 App 挂不上，需要第一方
 *     宿主 APK（com.anlandnext）来显示，属兜底方案。
 *
 * 【container 模式】droidspaces 容器（保留，给非 glibc-only 的场景）
 * 【native 模式】APK 自带 bionic arm64 二进制，spawnClient 直接 exec
 */
public final class Launcher {

    private Launcher() {}

    public static final String SU = "/system/bin/su";
    public static final String CHROME = "/opt/google/chrome/chrome";

    /* 画面后端 */
    public static final int DISP_X11 = 0;
    public static final int DISP_WAYLAND_FD = 1;
    public static final int DISP_WAYLAND_SOCKET = 2;
    /** 中继：App 侧起 libawlrelay.so 在 $R/tmp/wayland-0 上 listen，
     *  Chrome 以**普通 Wayland 客户端**用路径连过来；守护进程看到的凭据仍是本 App。
     *  只有这条能让 Chrome 走 zwp_text_input_v3 → 守护进程 ime_show → Android 键盘。 */
    public static final int DISP_WAYLAND_RELAY = 3;

    /** 中继可执行文件（放在 jniLibs 里，从 nativeLibraryDir exec） */
    public static final String RELAY_LIB = "libawlrelay.so";

    /** POSIX 单引号包裹（' → '\''）。 */
    public static String shQuote(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }

    /** native 模式：裸名 → <nativeLibraryDir>/lib<name>.so；含 '/' 视为路径 */
    public static String resolveExe(Context c, String exe) {
        if (exe == null || exe.isEmpty()) return null;
        if (exe.indexOf('/') >= 0) return exe;
        return c.getApplicationInfo().nativeLibraryDir + "/lib" + exe + ".so";
    }

    /** 空格分隔 + 单/双引号 + 反斜杠，解析成 argv（给 native 模式用）。 */
    public static List<String> splitArgs(String s) {
        List<String> out = new ArrayList<>();
        if (s == null) return out;
        StringBuilder cur = new StringBuilder();
        boolean inS = false, inD = false, has = false;
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (inS) {
                if (ch == '\'') inS = false; else cur.append(ch);
            } else if (inD) {
                if (ch == '"') inD = false;
                else if (ch == '\\' && i + 1 < s.length()) cur.append(s.charAt(++i));
                else cur.append(ch);
                has = true;
            } else if (ch == '\\' && i + 1 < s.length()) {
                cur.append(s.charAt(++i)); has = true;
            } else if (ch == '\'') { inS = true; has = true; }
            else if (ch == '"') { inD = true; has = true; }
            else if (ch == ' ' || ch == '\t') {
                if (has) out.add(cur.toString());
                cur.setLength(0); has = false;
            } else { cur.append(ch); has = true; }
        }
        if (has) out.add(cur.toString());
        return out;
    }

    /* ------------------------------------------------------------------ chroot */

    /** X11 后端下把 ozone 平台改成 x11（用户填的是 wayland 那份默认参数）。 */
    static String x11Args(String args) {
        if (args == null) return "";
        String a = args.replace("--ozone-platform=wayland", "--ozone-platform=x11");
        if (!a.contains("--ozone-platform=")) a = a + " --ozone-platform=x11";
        return a.trim();
    }

    /**
     * 交给 `su -c` 的一整段脚本：挂载点 → （Xwayland）→ chroot → Chrome。
     * WAYLAND_SOCKET 由最外层 shell 展开成字面数字再交给 chroot 内的进程。
     */
    public static String chrootScript(AppCfg cfg) {
        String r = shQuote(cfg.rootDir);
        String base = "HOME=/root USER=root LOGNAME=root TERM=xterm-256color "
                + "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "
                + "XDG_RUNTIME_DIR=/tmp XDG_SESSION_TYPE=";
        String kgsl = cfg.kgsl
                ? "MESA_LOADER_DRIVER_OVERRIDE=kgsl GALLIUM_DRIVER=kgsl FD_FORCE_KGSL=1 LIBGL_ALWAYS_SOFTWARE=0 "
                : "";
        /* 用户自定义的额外环境变量：插在基础变量之后、kgsl 之前（kgsl 优先级更高） */
        String extra = (cfg.envExtra == null || cfg.envExtra.trim().isEmpty())
                ? "" : cfg.envExtra.trim() + " ";
        String args = cfg.chromeArgs == null ? "" : cfg.chromeArgs.trim();
        String url = cfg.url == null ? "" : cfg.url.trim();
        String urlArg = url.isEmpty() ? "" : " " + shQuote(url);

        StringBuilder s = new StringBuilder();
        s.append("R=").append(r).append("\n");
        s.append("if [ ! -x \"$R").append(CHROME)
         .append("\" ]; then echo 'appwrap: 找不到 $R").append(CHROME)
         .append("（先点「安装 rootfs」）' >&2; exit 8; fi\n");
        /* 只有需要把 fd 交给 chroot 内进程的后端才要求 WAYLAND_SOCKET */
        boolean needFd = (cfg.display == DISP_X11 || cfg.display == DISP_WAYLAND_FD);
        if (needFd) {
            s.append("if [ -z \"$WAYLAND_SOCKET\" ]; then echo 'appwrap: WAYLAND_SOCKET 没有继承到 su 子进程"
                    + "（su 清了环境？）' >&2; exit 9; fi\n");
            s.append("echo \"appwrap: fd 诊断 WAYLAND_SOCKET=$WAYLAND_SOCKET -> ")
             .append("$(ls -l /proc/self/fd/$WAYLAND_SOCKET 2>&1 | sed 's/.*-> //')\" >&2\n");
        }
        /* 挂载点 */
        s.append("mkdir -p \"$R/proc\" \"$R/sys\" \"$R/dev/shm\" \"$R/tmp\" \"$R/run\" \"$R/root/.chrome\" 2>/dev/null\n");
        s.append("grep -q \" $R/proc \" /proc/mounts || { mount -t proc proc \"$R/proc\" "
               + "|| mount --bind /proc \"$R/proc\"; } 2>&1\n");
        s.append("grep -q \" $R/sys \" /proc/mounts || { mount -t sysfs sysfs \"$R/sys\" "
               + "|| mount --bind /sys \"$R/sys\"; } 2>&1\n");
        s.append("grep -q \" $R/dev \" /proc/mounts || mount --bind /dev \"$R/dev\" 2>&1\n");
        s.append("grep -q \" $R/dev/shm \" /proc/mounts "
               + "|| mount -t tmpfs -o mode=1777,size=512m tmpfs \"$R/dev/shm\" 2>&1\n");
        s.append("echo 'appwrap: 挂载完成' >&2\n");

        if (cfg.display == DISP_WAYLAND_RELAY) {
            String rt = (cfg.runtimeDir == null || cfg.runtimeDir.isEmpty())
                    ? "/data/local/tmp/awl" : cfg.runtimeDir;
            /* 音频：宿主 anland 模块的 PulseAudio（Termux OpenSL ES/AAudio sink）听在
             * <runtime_dir>/pulse.sock；把它 bind 进 chroot 并设 PULSE_SERVER，
             * 容器里的 libpulse 客户端就能出声（anland-session 也是这么做的）。
             * 没有这个 socket 时 Chrome 拿不到输出设备 —— 有些站点会一直卡在缓冲。 */
            s.append("mkdir -p \"$R/run/anland\"\n");
            s.append("grep -q \" $R/run/anland \" /proc/mounts || mount --bind ")
             .append(shQuote(rt)).append(" \"$R/run/anland\" 2>&1\n");
            s.append("AUD=\"\"\n");
            s.append("[ -S \"$R/run/anland/pulse.sock\" ] && AUD=\"PULSE_SERVER=unix:/run/anland/pulse.sock\"\n");
            s.append("if [ -n \"$AUD\" ]; then echo 'appwrap: 音频已接上 pulse.sock' >&2; "
                   + "else echo 'appwrap: 没找到 ").append(rt)
             .append("/pulse.sock —— 音频不可用（宿主模块的 PulseAudio 没起？）' >&2; fi\n");
            /* 中继已经在 App 侧（root）起好并 listen 在 $R/tmp/wayland-0；
             * Chrome 用**路径**连接（不依赖 WAYLAND_SOCKET，绕开 Chromium 的预探测）。 */
            s.append("if [ ! -S \"$R/tmp/wayland-0\" ]; then "
                   + "echo 'appwrap: $R/tmp/wayland-0 不存在 —— 中继没起来？' >&2; exit 7; fi\n");
            s.append("echo 'appwrap: chroot → chrome(Wayland 经中继) ")
             .append(args.replace("'", "")).append("' >&2\n");
            s.append("exec chroot \"$R\" /usr/bin/env -i ").append(base).append("wayland ").append(extra).append(kgsl)
             .append("WAYLAND_DISPLAY=/tmp/wayland-0 $AUD ").append(CHROME)
             .append(" ").append(args).append(urlArg).append("\n");
        } else if (cfg.display == DISP_X11) {
            String rt = (cfg.runtimeDir == null || cfg.runtimeDir.isEmpty())
                    ? "/data/local/tmp/awl" : cfg.runtimeDir;
            /* mini-wm 的控制 socket 建在 $ANLAND_WM_SOCK，守护进程从自己的 runtime_dir
             * 连过来 → 必须把守护进程的 runtime 目录 bind 进 chroot 的同一路径，
             * 否则窗口的 resize/close/raise 通道不通（画面能出，但关不掉/缩不了）。 */
            s.append("mkdir -p \"$R/run/anland\" \"$R/tmp/.X11-unix\" && chmod 1777 \"$R/tmp/.X11-unix\" 2>/dev/null\n");
            s.append("grep -q \" $R/run/anland \" /proc/mounts || mount --bind ")
             .append(shQuote(rt)).append(" \"$R/run/anland\" 2>&1\n");
            s.append("AUD=\"\"\n");
            s.append("[ -S \"$R/run/anland/pulse.sock\" ] && AUD=\"PULSE_SERVER=unix:/run/anland/pulse.sock\"\n");
            s.append("echo 'appwrap: 准备启动 Xwayland + anland-miniwm' >&2\n");
            /* 清掉上一次残留（PID 文件精确杀，绝不用 pkill -f：本脚本自身命令行里就含这些词） */
            s.append("[ -f \"$R/tmp/appwrap-x.pid\" ] && kill $(cat \"$R/tmp/appwrap-x.pid\") 2>/dev/null; "
                   + "[ -f \"$R/tmp/appwrap-wm.pid\" ] && kill $(cat \"$R/tmp/appwrap-wm.pid\") 2>/dev/null; "
                   + "sleep 0.3; rm -f \"$R/tmp/.X11-unix/X0\" \"$R/tmp/.X0-lock\"\n");
            s.append("chroot \"$R\" /usr/bin/env -i ").append(base).append("wayland ").append(extra).append(kgsl)
             .append("WAYLAND_SOCKET=$WAYLAND_SOCKET /usr/bin/Xwayland :0 -rootless -noreset -ac -terminate &\n");
            s.append("XPID=$!\n");
            s.append("echo $XPID > \"$R/tmp/appwrap-x.pid\"\n");
            s.append("echo \"appwrap: Xwayland 已启动 pid=$XPID，等 X0 套接字...\" >&2\n");
            s.append("i=0; while [ $i -lt 150 ]; do [ -S \"$R/tmp/.X11-unix/X0\" ] && break; "
                   + "kill -0 $XPID 2>/dev/null || { echo 'appwrap: Xwayland 退出了' >&2; break; }; "
                   + "sleep 0.2; i=$((i+1)); done\n");
            s.append("[ -S \"$R/tmp/.X11-unix/X0\" ] && echo 'appwrap: X0 就绪' >&2 "
                   + "|| echo 'appwrap: X0 未出现（Xwayland 没起来？看上面的报错）' >&2\n");
            /* 关键一步：rootless Xwayland 只有在 WM 做了 XCompositeRedirectWindow(Manual)
             * 之后才会 surface 窗口（见 anland-session/miniwm.c 头部注释），
             * 所以没有 WM 时守护进程一个窗口都看不到。 */
            s.append("[ -x \"$R/usr/bin/anland-miniwm\" ] || echo 'appwrap: 警告：rootfs 里没有 "
                   + "/usr/bin/anland-miniwm —— 没有 WM 时 rootless Xwayland 不会 surface 窗口，"
                   + "守护进程将看不到任何窗口' >&2\n");
            s.append("chroot \"$R\" /usr/bin/env -i ").append(base).append("x11 ").append(extra).append(kgsl)
             .append("DISPLAY=:0 XDG_RUNTIME_DIR=/tmp ANLAND_WM_SOCK=/run/anland/anland-wm.sock ")
             .append("/usr/bin/anland-miniwm &\n");            s.append("WMPID=$!\n");
            s.append("echo $WMPID > \"$R/tmp/appwrap-wm.pid\"\n");
            s.append("echo \"appwrap: anland-miniwm 已启动 pid=$WMPID（rootless Xwayland 靠它 surface 窗口）\" >&2\n");
            s.append("sleep 0.6\n");
            s.append("kill -0 $WMPID 2>/dev/null && echo 'appwrap: mini-wm 存活' >&2 "
                   + "|| echo 'appwrap: mini-wm 已退出（看上面的报错）' >&2\n");
            s.append("echo 'appwrap: chroot → chrome(X11) ").append(x11Args(args).replace("'", ""))
             .append("' >&2\n");
            s.append("exec chroot \"$R\" /usr/bin/env -i ").append(base).append("x11 ").append(extra).append(kgsl)
             .append("DISPLAY=:0 $AUD ").append(CHROME)
             .append(" ").append(x11Args(args)).append(urlArg).append("\n");
        } else if (cfg.display == DISP_WAYLAND_SOCKET) {
            String rt = (cfg.runtimeDir == null || cfg.runtimeDir.isEmpty())
                    ? "/data/local/tmp/awl" : cfg.runtimeDir;
            s.append("mkdir -p \"$R/run/anland\"\n");
            s.append("grep -q \" $R/run/anland \" /proc/mounts "
                   + "|| mount --bind ").append(shQuote(rt)).append(" \"$R/run/anland\" 2>&1\n");
            s.append("echo 'appwrap: 警告——此模式下 Chrome 以 root 连 wayland-0，窗口属于 root，"
                   + "需要第一方宿主 APK(com.anlandnext) 显示' >&2\n");
            s.append("exec chroot \"$R\" /usr/bin/env -i ").append(base).append("wayland ").append(extra).append(kgsl)
             .append("WAYLAND_DISPLAY=/run/anland/wayland-0 ").append(CHROME)
             .append(" ").append(args).append(urlArg).append("\n");
        } else {
            s.append("echo 'appwrap: chroot → chrome(WAYLAND_SOCKET=").append("$WAYLAND_SOCKET")
             .append(") ").append(args.replace("'", "")).append("' >&2\n");
            s.append("exec chroot \"$R\" /usr/bin/env -i ").append(base).append("wayland ").append(extra).append(kgsl)
             .append("WAYLAND_SOCKET=$WAYLAND_SOCKET ").append(CHROME)
             .append(" ").append(args).append(urlArg).append("\n");
        }
        return s.toString();
    }

    /** 把 chroot 脚本包成 spawnClient 的 (exe, args)：直接 exec su，不额外加 shell 层。 */
    public static String[] chrootArgv(AppCfg cfg) {
        return new String[]{SU, "-c", chrootScript(cfg)};
    }

    /* ------------------------------------------------------------------ 中继 */

    /** 中继监听的套接字路径（在 rootfs 目录里，chroot 内就是 /tmp/wayland-0） */
    public static String relaySockPath(AppCfg cfg) {
        return cfg.rootDir + "/tmp/wayland-0";
    }

    /** App 侧起中继：经 su（root，为了能在 /data/adb 下建套接字文件）。
     *  第一条上游走 spawnClient 继承的 fd（环境变量 WAYLAND_SOCKET，由 libawl 设置），
     *  其余上游用额外创建、经 dup 保活的连接（号码在 fork 后的子进程里同样有效）。
     *  Chromium 不只开一条 Wayland 连接（浏览器 + GPU 进程），所以要多备几条。 */
    public static String[] relayArgv(AppCfg cfg, String relayExe, java.util.List<Integer> extraFds) {
        StringBuilder a = new StringBuilder("exec " + shQuote(relayExe)
                + " --listen " + shQuote(relaySockPath(cfg))
                + " --upstream $WAYLAND_SOCKET");
        if (extraFds != null)
            for (Integer fd : extraFds)
                if (fd != null && fd >= 0) a.append(" --upstream ").append(fd);
        if (cfg.relayVerbose) a.append(" --verbose");
        return new String[]{SU, "-c", a.toString()};
    }

    /** 守护进程没在跑时，由本 App 以 root 把它拉起来。
     *
     *  实测要点：/data/adb/modules/anland-awl/waylandbridge 从 `adb shell su` 里执行会报
     *  "inaccessible or not found"（KernelSU 的挂载命名空间差异），但**从 App 的 su 子进程
     *  里可以正常执行** —— 所以把启动逻辑放在 App 里即可，不再依赖模块 service.sh 或
     *  /data/local/tmp/wb 那份拷贝。
     *  另外框架软重启（SurfaceFlinger 挂掉）后守护进程不会自动回来，这里也是恢复入口。 */
    public static String startDaemonScript() {
        return "M=/data/adb/modules/anland-awl\n"
             + "if pgrep waylandbridge >/dev/null 2>&1; then echo DAEMON-ALREADY; exit 0; fi\n"
             /* 陈旧套接字会让客户端连上一个死掉的 socket —— 先清掉 */
             + "rm -f /data/local/tmp/awl/wayland-0 /data/local/tmp/awl/anland-wm.sock 2>/dev/null\n"
             + "chmod 755 \"$M/waylandbridge\" 2>/dev/null\n"
             + "cd \"$M\" 2>/dev/null || { echo '模块目录进不去'; exit 1; }\n"
             + "setsid ./waylandbridge > /data/local/tmp/awl_daemon.log 2>&1 < /dev/null &\n"
             + "i=0; while [ $i -lt 60 ]; do pgrep waylandbridge >/dev/null 2>&1 && break; "
             + "sleep 0.25; i=$((i+1)); done\n"
             + "if pgrep waylandbridge >/dev/null 2>&1; then echo DAEMON-OK; "
             + "else echo DAEMON-FAIL; tail -5 /data/local/tmp/awl_daemon.log 2>&1; fi\n";
    }

    /** 确保 PulseAudio 挂的是**真正的 Android sink**（module-sles-sink），而不是兜底的 null sink。
     *
     *  为什么需要：模块 service.sh 只在**开机**时起 PA。实测框架软重启（SurfaceFlinger 崩溃）
     *  之后音频服务刚起来那会儿 PA 拿不到设备：
     *    E: module-sles-sink.c: Failed to initialize OpenSL ES: error 9   （= DEVICE_UNAVAILABLE）
     *    E: main.c: Sink android does not exist.
     *  于是 module-always-sink 顶上 auto_null —— 声音进黑洞，Chrome 一点声都没有（"没有声音"）。
     *  这里在启动 Chrome 前查一次，坏了就照 service.sh 的方式把 PA 重起一遍（sles 不行换 AAudio）。
     *
     *  两个细节：PA 必须以 com.anlandnext 的 uid 起（Android 12+ 拒绝 uid 不对应任何包的进程建音频流），
     *  /data/adb 是 0700，模块里的 pulse/ 要拷到 runtime 目录再用。 */
    public static String pulseEnsureScript(AppCfg cfg) {
        String rt = (cfg.runtimeDir == null || cfg.runtimeDir.isEmpty())
                ? "/data/local/tmp/awl" : cfg.runtimeDir;
        String r = shQuote(cfg.rootDir);
        return "R=" + r + "\n"
             + "RT=" + shQuote(rt) + "\n"
             + "M=/data/adb/modules/anland-awl\n"
             + "PAR=\"$RT/pulse\"; PH=\"$RT/pulse-home\"; LOG=/data/local/tmp/awl_pulse.log\n"
             + "mkdir -p \"$R/run/anland\" 2>/dev/null\n"
             + "grep -q \" $R/run/anland \" /proc/mounts || mount --bind \"$RT\" \"$R/run/anland\" 2>/dev/null\n"
             + "PC() { chroot \"$R\" /usr/bin/env -i PULSE_SERVER=unix:/run/anland/pulse.sock /usr/bin/pactl \"$@\" 2>&1; }\n"
             + "if [ -S \"$RT/pulse.sock\" ] && PC list short sinks 2>/dev/null | grep -q '[[:space:]]android[[:space:]]'; then\n"
             + "  echo PULSE-OK; PC list short sinks | sed 's/^/  /'; exit 0\n"
             + "fi\n"
             + "echo 'PULSE-BAD：没有 android sink，按 service.sh 的方式重启 PA'\n"
             + "PAUID=$(awk '$1==\"com.anlandnext\"{print $2; exit}' /data/system/packages.list 2>/dev/null)\n"
             + "if [ -z \"$PAUID\" ]; then echo '找不到 com.anlandnext 的 uid —— 跳过（音频不可用）'; exit 0; fi\n"
             + "pkill pulseaudio 2>/dev/null; sleep 1\n"
             + "rm -rf \"$PAR\"; cp -r \"$M/pulse\" \"$PAR\" 2>/dev/null; chmod -R 755 \"$PAR\" 2>/dev/null\n"
             + "grep -q '^dl-search-path' \"$PAR/etc/pulse/daemon.conf\" 2>/dev/null "
             +   "|| echo \"dl-search-path = $PAR/lib/pulseaudio/modules\" >> \"$PAR/etc/pulse/daemon.conf\"\n"
             + "rm -rf \"$PH\"; mkdir -p \"$PH/run\" \"$PH/state\"; chown -R \"$PAUID:$PAUID\" \"$PH\"; chmod 700 \"$PH\" \"$PH/run\" \"$PH/state\"\n"
             + "rm -f \"$RT/pulse.sock\"\n"
             + "start_pa() { nohup su \"$PAUID\" -c \"export HOME='$PH' TMPDIR='$PH' PULSE_RUNTIME_PATH='$PH/run' "
             +   "PULSE_STATE_PATH='$PH/state' PULSE_CONFIG_PATH='$PAR/etc/pulse' "
             +   "LD_LIBRARY_PATH='$PAR/lib:$PAR/lib/pulseaudio:$PAR/lib/pulseaudio/modules'; "
             +   "exec '$PAR/bin/pulseaudio' --daemonize=no --exit-idle-time=-1 --disallow-exit --log-target=stderr "
             +   "-n -F '$PAR/etc/pulse/default.pa' "
             +   "-L 'module-native-protocol-unix auth-anonymous=1 socket=$RT/pulse.sock'\" > \"$LOG\" 2>&1 & }\n"
             + "start_pa; sleep 4\n"
             + "if PC list short sinks 2>/dev/null | grep -q '[[:space:]]android[[:space:]]'; then\n"
             + "  echo 'PULSE-OK（OpenSL ES）'\n"
             + "else\n"
             + "  echo 'OpenSL ES 还是不行，换 AAudio sink'\n"
             + "  sed -i 's/^load-module module-sles-sink/# &/' \"$PAR/etc/pulse/default.pa\"\n"
             + "  sed -i 's/^#load-module module-aaudio-sink/load-module module-aaudio-sink/' \"$PAR/etc/pulse/default.pa\"\n"
             + "  grep -q '^load-module module-aaudio-sink' \"$PAR/etc/pulse/default.pa\" "
             +   "|| sed -i 's|^set-default-sink android|load-module module-aaudio-sink sink_name=android sink_properties=device.description=Android\\nset-default-sink android|' \"$PAR/etc/pulse/default.pa\"\n"
             + "  pkill pulseaudio 2>/dev/null; sleep 1; rm -f \"$RT/pulse.sock\"; start_pa; sleep 4\n"
             + "  PC list short sinks 2>/dev/null | grep -q '[[:space:]]android[[:space:]]' "
             +   "&& echo 'PULSE-OK（AAudio）' || { echo 'PULSE-FAIL：两种 sink 都起不来'; tail -6 \"$LOG\"; }\n"
             + "fi\n"
             /* 顺手确认 Chrome 真连上了：启动后可以用 pactl list short sink-inputs 看有没有它的流 */
             + "PC list short sinks | sed 's/^/  /'\n";
    }

    /** 守护进程健康检查：它是不是比 SurfaceFlinger 还"老"。
     *
     *  为什么要查：守护进程用 SurfaceControl/HWC 把画面交给 SurfaceFlinger。SF 一旦重启
     *  （实测被 Mesa 抢 GPU 打崩过三次：SIGABRT → framework 软重启），守护进程手里那条
     *  SC 连接就废了 —— 它不会报错，只是**一直等不到帧**。症状极具迷惑性：
     *    · 窗口正常出现、也挂载上了（binder 那边都成功）
     *    · 中继完全没有流量（8 秒增量 0）
     *    · 触摸毫无反应（输入要经守护进程转发）
     *    · **音频照常**（音频走 pulse.sock，不经过守护进程）
     *  也就是"刚进去就卡死，但能听到声音"。2026-09-17 实测就是这样，重启守护进程即恢复。
     *
     *  判据：/proc/<pid>/stat 第 22 个字段是进程启动时刻（jiffies since boot）。
     *  SF 的启动时刻 **大于** 守护进程的 → 守护进程是旧世界的人，必须重启。
     *  输出：DAEMON-STALE / DAEMON-OK / DAEMON-NONE */
    public static String daemonHealthScript() {
        return "s=$(pidof surfaceflinger 2>/dev/null | awk '{print $1}')\n"
             + "ds=0\n"
             /* 机器上可能有多个 waylandbridge（模块开机起的一个 + 后来手动/App 起的），
              * 必须取**最新**那个的启动时刻：取最老的会永远误报 STALE，
              * 于是每次打开 App 都白重启一遍守护进程 + Chrome（会话全丢）。 */
             + "for p in $(pidof waylandbridge 2>/dev/null); do\n"
             + "  v=$(awk '{print $22}' /proc/$p/stat 2>/dev/null)\n"
             + "  [ -n \"$v\" ] && [ \"$v\" -gt \"$ds\" ] && ds=$v\n"
             + "done\n"
             + "[ \"$ds\" -eq 0 ] && { echo DAEMON-NONE; exit 0; }\n"
             + "[ -z \"$s\" ] && { echo DAEMON-OK; exit 0; }\n"
             + "ss=$(awk '{print $22}' /proc/$s/stat 2>/dev/null)\n"
             + "if [ -n \"$ss\" ] && [ \"$ss\" -gt \"$ds\" ]; then\n"
             + "  echo \"DAEMON-STALE（SF 比守护进程晚起: sf=$ss > daemon=$ds）\"\n"
             + "else echo \"DAEMON-OK（daemon=$ds sf=$ss）\"; fi\n";
    }

    /** 强制重启守护进程（拿到全新的 SF/SurfaceControl 连接）。比 startDaemonScript 多一个
     *  "先杀掉已有的" —— 健康检查发现连接发霉时必须真的重启，而不是看到进程在就跳过。 */
    public static String restartDaemonScript() {
        return "M=/data/adb/modules/anland-awl\n"
             + "echo '重启守护进程…'\n"
             + "pkill waylandbridge 2>/dev/null\n"
             + "sleep 1\n"
             + "rm -f /data/local/tmp/awl/wayland-0 /data/local/tmp/awl/anland-wm.sock 2>/dev/null\n"
             + "chmod 755 \"$M/waylandbridge\" 2>/dev/null\n"
             + "cd \"$M\" 2>/dev/null || exit 1\n"
             + "setsid ./waylandbridge > /data/local/tmp/awl_daemon.log 2>&1 < /dev/null &\n"
             + "i=0; while [ $i -lt 80 ]; do pgrep waylandbridge >/dev/null 2>&1 && break; "
             + "sleep 0.25; i=$((i+1)); done\n"
             + "if pgrep waylandbridge >/dev/null 2>&1; then echo DAEMON-OK; "
             + "else echo DAEMON-FAIL; tail -5 /data/local/tmp/awl_daemon.log 2>&1; fi\n";
    }

    /** 启动前清理上一次的残留：Chrome / 中继 / Xwayland / miniwm + profile 单例锁 + 套接字。
     *  不清的话 Chrome 会发现旧的 SingletonLock，把 URL "交给已有会话" 然后自己退出
     *  （日志表现为 Opening in existing browser session. 然后流结束）。 */
    public static String cleanupScript(String rootDir) {
        return "R=" + shQuote(rootDir) + "\n"
             + "pkill chrome 2>/dev/null; pkill chrome_crashpad_handler 2>/dev/null; "
             + "pkill libawlrelay.so 2>/dev/null; pkill Xwayland 2>/dev/null; "
             + "pkill anland-miniwm 2>/dev/null\n"
             + "sleep 1\n"
             + "rm -f \"$R/root/.chrome/SingletonLock\" \"$R/root/.chrome/SingletonCookie\" "
             + "\"$R/root/.chrome/SingletonSocket\" 2>/dev/null\n"
             + "rm -f \"$R/tmp/wayland-0\" \"$R/tmp/.X11-unix/X0\" \"$R/tmp/.X0-lock\" 2>/dev/null\n"
             + "rm -f \"$R/tmp/appwrap-x.pid\" \"$R/tmp/appwrap-wm.pid\" 2>/dev/null\n"
             + "echo CLEANED";
    }

    /** 停掉 chroot 里的一切 + 中继，并清掉套接字文件。
     *  注意：**不能**用 `pkill -f <含 chrome/Xwayland 的模式>` —— 本脚本自身就是
     *  `sh -c '<脚本文本>'`，文本里就含这些词，-f 按整条命令行匹配会把运行脚本的
     *  shell 一起杀掉。这里按进程名匹配（toybox 默认不匹配命令行）。 */
    public static String stopAllScript(String rootDir) {
        return "pkill chrome 2>/dev/null; "
             + "pkill chrome_crashpad_handler 2>/dev/null; "
             + "pkill anland-miniwm 2>/dev/null; "
             + "pkill Xwayland 2>/dev/null; "
             + "pkill libawlrelay.so 2>/dev/null; "
             + "rm -f " + shQuote(rootDir + "/tmp/wayland-0") + " 2>/dev/null; "
             + "echo stopped";
    }

    /* --------------------------------------------------------------- container */

    /**
     * 容器模式：交给 `su -c` 的一整段脚本。容器侧脚本先 base64（引号/换行原样穿透），
     * 只在最外层把 @FD@ 换成真实 fd 号。
     */
    public static String containerScript(String dsPath, String container, String cmd,
                                         String user) {
        String ds = (dsPath == null || dsPath.isEmpty()) ? "droidspaces" : dsPath;
        String inner = "exec env WAYLAND_SOCKET=@FD@ " + cmd;
        String payload = (user == null || user.isEmpty() || "root".equals(user))
                ? inner
                : "exec su - " + user + " -c " + shQuote(inner);
        String b64 = Base64.encodeToString(payload.getBytes(StandardCharsets.UTF_8),
                Base64.NO_WRAP);
        return "if [ -z \"$WAYLAND_SOCKET\" ]; then "
                + "echo 'appwrap: WAYLAND_SOCKET 未继承到 su 子进程(su 清空环境?)' >&2; exit 9; fi\n"
                + "exec " + ds + " -n " + shQuote(container == null ? "" : container) + " run "
                + "\"$(printf %s '" + b64 + "' | base64 -d | sed \"s/@FD@/$WAYLAND_SOCKET/g\")\"";
    }

    public static String[] containerArgv(String dsPath, String container, String cmd, String user) {
        return new String[]{SU, "-c", containerScript(dsPath, container, cmd, user)};
    }
}
