package com.anland.appwrap;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;

import org.tukaani.xz.XZInputStream;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * 首次安装：把 APK 里内置的 rootfs.tar.xz 解到设备上，让 chroot 能直接用。
 *
 * 为什么这样解：Android 自带的 toybox tar 不保证支持 xz，所以 Java 侧解 xz、
 * 把 tar 流直接喂给 root 起的 `tar -xf -`（管道背压，不会爆内存）。
 * 备用的两步模式：先落一个 2.3GB 的 .tar 到 App 缓存，再让 tar 从文件解
 * （排查管道/tar 版本问题时用）。
 *
 * 解包后必须补的东西（这份 rootfs 里 /dev/shm 与 /etc/resolv.conf 是缺的）：
 *   /dev/shm（0644→1777 的 tmpfs 挂载点在运行时补）、/tmp 权限、
 *   /etc/resolv.conf 与 /etc/hosts、ldconfig 缓存、以及一个 .appwrap-ok 标记。
 */
public final class Rootfs {

    public static final String ASSET = "rootfs.tar.xz";
    public static final String MARK = ".appwrap-ok";
    /** 解包后大约这么大（实测 2.29GB），少于这个数就先提示 */
    public static final long NEED_BYTES = 2_600L * 1024 * 1024;

    public interface Progress {
        void phase(String note);
        void bytes(long done, long total);   /* total < 0 = 未知 */
    }

    private Rootfs() {}

    public static String q(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }

    public static long assetLength(Context c) {
        try (AssetFileDescriptor afd = c.getAssets().openFd(ASSET)) {
            return afd.getLength();
        } catch (Exception e) {
            return -1;
        }
    }

    /** rootfs 是否已解好（看标记文件 + Chrome 本体）。 */
    public static boolean installed(Context c, AppCfg cfg) {
        RootExec.Result r = RootExec.run(
                "[ -f " + q(cfg.rootDir + "/" + MARK) + " ] && [ -x "
                + q(cfg.rootDir + "/opt/google/chrome/chrome") + " ] && echo OK", 20_000);
        return r.ok && r.out.contains("OK");
    }

    /** 目标分区的可用空间（KB），失败返回 -1。 */
    public static long freeKb(Context c, String path) {
        String parent = path.contains("/") ? path.substring(0, path.lastIndexOf('/')) : path;
        RootExec.Result r = RootExec.run("df -k " + q(parent), 20_000);
        if (!r.ok) return -1;
        String[] lines = r.out.trim().split("\n");
        if (lines.length < 2) return -1;
        /* toybox df -k: Filesystem 1K-blocks Used Available Use% Mounted on */
        String[] f = lines[lines.length - 1].trim().split("\\s+");
        if (f.length < 4) return -1;
        try {
            return Long.parseLong(f[3]);
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /** 解包 + 首次收尾。返回最后一次 root 命令的结果（ok 即可）。 */
    public static RootExec.Result install(Context c, AppCfg cfg, Progress cb, boolean twoStep) {
        final String dir = cfg.rootDir;
        String parent = dir.contains("/") ? dir.substring(0, dir.lastIndexOf('/')) : dir;

        cb.phase("检查空间与目录 ...");
        RootExec.Result r = RootExec.run("mkdir -p " + q(dir) + " " + q(parent + "/.tmp"), 30_000);
        if (!r.ok) return r;
        long avail = freeKb(c, parent) * 1024L;
        if (avail > 0 && avail - 200L * 1024 * 1024 < NEED_BYTES) {
            return new RootExec.Result("", "", -1, "空间不足：" + parent + " 可用 "
                    + (avail / 1024 / 1024) + " MB，需要约 " + (NEED_BYTES / 1024 / 1024)
                    + " MB（换个 rootfs 目录或清点空间）");
        }

        long total = assetLength(c);

        if (twoStep) {
            File tar = new File(c.getCacheDir(), "rootfs.tar");
            cb.phase("两步模式：先解成 " + tar + "（App 缓存需要 ~2.3GB 临时空间）");
            try (InputStream raw = c.getAssets().open(ASSET);
                 XZInputStream xz = new XZInputStream(raw);
                 OutputStream os = new FileOutputStream(tar)) {
                copy(xz, os, total, cb);
            } catch (IOException e) {
                return new RootExec.Result("", "", -1, "解 xz 失败: " + e.getMessage());
            }
            cb.phase("tar 解包到 " + dir + " ...");
            r = RootExec.run("tar -xf " + q(tar.getAbsolutePath()) + " -C " + q(dir), 1_800_000);
            //noinspection ResultOfMethodCallIgnored
            tar.delete();
        } else {
            cb.phase("流式解包（Java 解 xz → root 侧 tar）→ " + dir);
            InputStream stream;
            try {
                stream = new XZInputStream(c.getAssets().open(ASSET));
            } catch (IOException e) {
                return new RootExec.Result("", "", -1, "打开 assets/" + ASSET + " 失败: " + e.getMessage());
            }
            r = RootExec.run("tar -xf - -C " + q(dir), stream, written -> {
                cb.bytes(written, -1);
            }, 1_800_000);
            if (!r.ok && r.err.contains("No such file")) {
                r = new RootExec.Result(r.out, r.err, r.exit,
                        r.why() + "（可能是 tar 不支持 -f -，改用两步模式重试）");
            }
        }
        if (!r.ok) return r;

        cb.phase("首次收尾（/dev/shm、/tmp、resolv.conf、ldconfig）...");
        RootExec.Result f = RootExec.run(fixups(dir), 600_000);
        if (!f.ok) return f;

        RootExec.Result v = RootExec.run(
                "[ -x " + q(dir + "/opt/google/chrome/chrome") + " ] && echo OK", 20_000);
        if (!v.ok || !v.out.contains("OK")) {
            return new RootExec.Result(v.out, v.err, v.exit,
                    "解包后没找到 " + dir + "/opt/google/chrome/chrome");
        }
        return f;
    }

    /** 卸载/清空 rootfs（先解挂载点，再删目录）。 */
    public static RootExec.Result wipe(Context c, AppCfg cfg) {
        String script =
                "D=" + q(cfg.rootDir) + "\n"
              + "for m in proc dev/shm dev sys; do\n"
              + "  grep -q \" $D/$m \" /proc/mounts && umount -l \"$D/$m\" 2>/dev/null\n"
              + "done\n"
              + "rm -rf \"$D\"\n"
              + "echo DONE\n";
        return RootExec.run(script, 600_000);
    }

    private static String fixups(String dir) {
        return "R=" + q(dir) + "\n"
             + "mkdir -p \"$R/dev/shm\" \"$R/tmp\" \"$R/run\" \"$R/root/.chrome\"\n"
             + "chmod 1777 \"$R/tmp\" \"$R/dev/shm\" 2>/dev/null\n"
             + "printf 'nameserver 223.5.5.5\\nnameserver 8.8.8.8\\n' > \"$R/etc/resolv.conf\"\n"
             + "printf '127.0.0.1 localhost\\n::1 localhost\\n' > \"$R/etc/hosts\"\n"
             + "{ [ -x \"$R/sbin/ldconfig\" ] && chroot \"$R\" /sbin/ldconfig ; } 2>/dev/null\n"
             + "{ [ -x \"$R/usr/sbin/ldconfig\" ] && chroot \"$R\" /usr/sbin/ldconfig ; } 2>/dev/null\n"
             + "touch \"$R/" + MARK + "\"\n"
             + "echo FIXUPS-DONE";
    }

    private static void copy(InputStream in, OutputStream out, long total, Progress cb)
            throws IOException {
        byte[] buf = new byte[256 * 1024];
        long done = 0;
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
            done += n;
            if (total > 0 && done % (8L * 1024 * 1024) < buf.length) cb.bytes(done, total);
        }
        cb.bytes(done, total);
    }
}
