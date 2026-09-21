package com.anland.appwrap;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * 以 root 执行命令：ProcessBuilder("su","-c", cmd)。
 *
 * 只引入一层 shell（su 自己拉起的那个），所以 cmd 就是一条普通 shell 命令行。
 * stdout/stderr 分线程读（否则写满管道会死锁）；支持一边把数据写进子进程 stdin
 * 一边等它结束（rootfs 解包就是这种：Java 侧解 xz，喂给设备侧 toybox tar）。
 */
public final class RootExec {

    public static final class Result {
        public final String out;
        public final String err;
        public final int exit;
        public final boolean ok;
        public final String error;

        Result(String out, String err, int exit, String error) {
            this.out = out == null ? "" : out;
            this.err = err == null ? "" : err;
            this.exit = exit;
            this.error = error;
            this.ok = error == null && exit == 0;
        }

        /** 失败原因（给日志/UI 用） */
        public String why() {
            if (error != null) return error;
            String e = err.trim();
            if (!e.isEmpty()) return e.length() > 400 ? e.substring(0, 400) : e;
            return "exit " + exit;
        }
    }

    public interface Sink {          /* 子进程输出的实时回调（可选） */
        void onLine(String s);
    }

    private RootExec() {}

    /** su 的绝对路径候选。为什么不用裸 "su"：实测换一台机器（NX809J → NX809S）后
     *  App 里 `ProcessBuilder("su", ...)` 直接 ENOENT —— 不同 ROM / KernelSU 版本下
     *  App 进程的 PATH 不一样，裸名字解析不到。按常见位置依次找，找不到再退回 PATH。 */
    private static final String[] SU_PATHS = {
            "/system/bin/su",            /* KernelSU / Magisk 最常见 */
            "/system/xbin/su",
            "/debug_ramdisk/su",
            "/data/adb/ksu/bin/su",
            "/sbin/su",
            "/su/bin/su",
    };

    public static String suPath() {
        for (String p : SU_PATHS) {
            try {
                if (new java.io.File(p).canExecute()) return p;
            } catch (Throwable ignored) { }
        }
        return "su";                     /* 退回 PATH */
    }

    public static Result run(String cmd) {
        return run(cmd, 60_000);
    }

    public static Result run(String cmd, long timeoutMs) {
        return run(cmd, null, null, timeoutMs);
    }

    /**
     * @param in       非 null 时写进子进程 stdin（写完关闭）
     * @param progress 已写入 stdin 的字节数回调（每 4MB 一次）
     */
    public static Result run(String cmd, InputStream in, Progress progress, long timeoutMs) {
        Process p = null;
        try {
            p = new ProcessBuilder(suPath(), "-c", cmd).start();
            final Process proc = p;

            StringBuilder out = new StringBuilder();
            StringBuilder err = new StringBuilder();
            Thread tOut = reader(proc.getInputStream(), out, null);
            Thread tErr = reader(proc.getErrorStream(), err, null);

            if (in != null) {
                try (OutputStream os = proc.getOutputStream()) {
                    byte[] buf = new byte[256 * 1024];
                    long total = 0, last = 0;
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        os.write(buf, 0, n);
                        total += n;
                        if (progress != null && total - last >= 4L * 1024 * 1024) {
                            last = total;
                            progress.onBytes(total);
                        }
                    }
                    if (progress != null) progress.onBytes(total);
                } catch (IOException e) {
                    /* 子进程提前退出（比如 tar 不支持 -f -）→ 下面用退出码/err 报错 */
                }
            }

            boolean done = proc.waitFor(timeoutMs, TimeUnit.MILLISECONDS);
            tOut.join(3000);
            tErr.join(3000);
            if (!done) {
                proc.destroyForcibly();
                return new Result(out.toString(), err.toString(), -1, "超时 " + timeoutMs + "ms");
            }
            return new Result(out.toString(), err.toString(), proc.exitValue(), null);
        } catch (IOException e) {
            if (p != null) p.destroyForcibly();
            return new Result("", "", -1, "su 启动失败: " + e.getMessage()
                    + "（本 App 拿到 root 授权了吗？）");
        } catch (InterruptedException e) {
            if (p != null) p.destroyForcibly();
            Thread.currentThread().interrupt();
            return new Result("", "", -1, "被中断");
        }
    }

    public interface Progress {
        void onBytes(long written);
    }

    private static Thread reader(InputStream is, StringBuilder sb, Sink sink) {
        Thread t = new Thread(() -> {
            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(is, StandardCharsets.UTF_8), 32 * 1024)) {
                char[] buf = new char[8192];
                int n;
                while ((n = r.read(buf)) > 0) {
                    sb.append(buf, 0, n);
                    if (sink != null) sink.onLine(new String(buf, 0, n));
                }
            } catch (IOException ignored) {
            }
        }, "rootexec-reader");
        t.setDaemon(true);
        t.start();
        return t;
    }
}
