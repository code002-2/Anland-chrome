package com.anland.appwrap;

import android.content.Context;
import android.content.SharedPreferences;

/** 目标程序的配置（每台设备一份）。 */
public final class AppCfg {

    /** 目标程序跑在哪一侧。 */
    public static final int MODE_CHROOT = 3;      /* su + chroot 自带 glibc rootfs（Chrome 用这个） */
    public static final int MODE_CONTAINER = 1;   /* 经 su + droidspaces 进容器，fd 靠继承传进去 */
    public static final int MODE_NATIVE = 0;      /* APK 自带 arm64 二进制，spawnClient 直接 exec */
    public static final int MODE_EXTERNAL = 2;    /* 不 spawn：只做窗口宿主（连接已由外部建立） */

    private static final String FILE = "appwrap";

    /** 默认 rootfs 落点：/data/adb 只有 root 能读写，比 /data/local/tmp 干净 */
    public static final String DEFAULT_ROOT = "/data/adb/anland-chrome/root";
    public static final String ALT_ROOT = "/data/local/tmp/anland-chrome/root";

    /* ------------------------------------------------------------------ 性能模式
     *
     * 懒人版只暴露三个档，界面上一选就写好整串 Chrome 参数（console 里能看到、也能手改）。
     * 实测背景（REDMAGIC NX809J / Adreno 840）：chroot 里没法用真 GPU —— kgsl 与 msm
     * 两条路都会把 SurfaceFlinger 打成 SIGABRT → 软重启（见下），所以"流畅"只能靠
     * 降低软件光栅化的像素量。 */

    public static final int PERF_SMOOTH = 0;   /* 流畅：0.4 倍 + 关闭 GPU 合成 + 减动画 */
    public static final int PERF_STOCK  = 1;   /* 原版：0.6 倍，动画特效照旧 */

    private static final String COMMON =
            "--no-sandbox --no-zygote --ozone-platform=wayland --disable-dev-shm-usage "
            + "--no-first-run --no-default-browser-check --enable-unsafe-swiftshader "
            + "--autoplay-policy=no-user-gesture-required ";

    private static final String SMOOTH = COMMON
            + "--use-gl=angle --use-angle=swiftshader "
            + "--force-device-scale-factor=0.4 "        /* 只画 16% 的像素，守护进程再硬件放大 */
            + "--disable-gpu-compositing "              /* 渲染进程直接软件合成，少绕 GPU 进程一圈 */
            + "--force-prefers-reduced-motion "         /* 少画动画 = 少重新光栅化 */
            + "--enable-low-end-device-mode --renderer-process-limit=1 --num-raster-threads=4 "
            + "--js-flags=--max-old-space-size=512";

    private static final String STOCK = COMMON
            + "--use-gl=angle --use-angle=swiftshader "
            + "--force-device-scale-factor=0.6 "
            + "--enable-low-end-device-mode --renderer-process-limit=1 --num-raster-threads=4 "
            + "--js-flags=--max-old-space-size=512";

    /** 取某一档的完整 Chrome 参数 */
    public static String presetArgs(int perfMode) {
        return perfMode == PERF_STOCK ? STOCK : SMOOTH;
    }

    public static String presetName(int perfMode) {
        return perfMode == PERF_STOCK ? "原版（特效）" : "流畅";
    }

    /** 应用档位：写 chromeArgs。kgsl 永远关着 —— 实测它既不能让 Chrome 变快
     *  （Chrome 走自己的 ANGLE/SwiftShader，不加载 Mesa），又会把 SurfaceFlinger
     *  打成 SIGABRT 导致软重启，所以界面上不再提供这个开关。 */
    public void applyPreset() {
        chromeArgs = presetArgs(perfMode);
        kgsl = false;
    }

    public static final String DEFAULT_CHROME_ARGS = SMOOTH;

    /* 自动播放：没有它，没点过页面的站点出声会被 autoplay policy 拦掉 */
    public static final String AUTOPLAY = "--autoplay-policy=no-user-gesture-required";

    public String name = "chrome";
    public int mode = MODE_CHROOT;
    public String exe = "";          /* native: 二进制名/路径；container: 容器内命令行 */
    public String args = "";         /* native: 额外参数 */
    public String container = "";    /* container 模式：droidspaces 容器名 */
    public String user = "";         /* container 模式：容器内用户 */
    public String dsPath = "droidspaces";
    public boolean autoAttach = true;

    public String rootDir = DEFAULT_ROOT;      /* chroot 模式：rootfs 目录 */
    public String chromeArgs = DEFAULT_CHROME_ARGS;
    public String url = "https://www.bing.com";
    public boolean kgsl = false;               /* kgsl 硬件渲染（MESA_LOADER_DRIVER_OVERRIDE 等） */

    /** 额外环境变量（空格分隔的 K=V），插进 chroot 的 `env -i` 里。
     *  用来试各种 GL 后端而不必改代码、不必往 rootfs 里塞 wrapper。
     *
     *  ⚠ 已实测：**任何让 chroot 里的 Mesa 直连 GPU 的写法都会打死 SurfaceFlinger**
     *    （kgsl 与 msm/freedreno 都试过，见 DEFAULT_CHROME_ARGS 上面的长注释）。
     *    安全的组合是纯软件：
     *      LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
     *    可以放心用的还有视频解码之类的开关：
     *      LIBVA_DRIVER_NAME=msm_drm_drv_video
     *  不要在这里/也不要勾 kgsl 去开真 GPU。 */
    public String envExtra = "";

    /** 性能档位（界面首页那三个选项）。改档位会重写 chromeArgs，并决定 kgsl 开关。 */
    public int perfMode = PERF_SMOOTH;

    /** 中继（libawlrelay.so）的逐条消息日志。
     *  **默认必须关掉**：它每条 Wayland 消息都 fputs 到 stderr，App 又把 stderr 镜像到
     *  日志框（64KB TextView 反复 setText）+ logcat，实测每秒几十 MB 分配 → GC 抖动 +
     *  挤压 Chrome 的 CPU。只有排查"中继到底转没转发"时才打开。 */
    public boolean relayVerbose = false;

    /** 画面后端：3 = wayland(relay，走 anland 的 wayland 协议，能拿 Android 输入法)、
     *  0 = Xwayland(X11)、1 = 直接 WAYLAND_SOCKET、2 = wayland 套接字(root 身份) */
    public int display = 3;
    /** display=2 时守护进程的 runtime 目录（config.json 的 runtime_dir） */
    public String runtimeDir = "/data/local/tmp/awl";

    private static SharedPreferences sp(Context c) {
        return c.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    public static AppCfg load(Context c) {
        SharedPreferences p = sp(c);
        AppCfg f = new AppCfg();
        f.name = p.getString("name", f.name);
        f.mode = p.getInt("mode", f.mode);
        f.exe = p.getString("exe", f.exe);
        f.args = p.getString("args", f.args);
        f.container = p.getString("container", f.container);
        f.user = p.getString("user", f.user);
        f.dsPath = p.getString("dsPath", f.dsPath);
        f.autoAttach = p.getBoolean("autoAttach", f.autoAttach);
        f.rootDir = p.getString("rootDir", f.rootDir);
        f.chromeArgs = p.getString("chromeArgs", f.chromeArgs);
        f.url = p.getString("url", f.url);
        f.kgsl = p.getBoolean("kgsl", f.kgsl);
        f.envExtra = p.getString("envExtra", f.envExtra);
        f.perfMode = p.getInt("perfMode", f.perfMode);
        f.relayVerbose = p.getBoolean("relayVerbose", f.relayVerbose);
        f.display = p.getInt("display", f.display);
        f.runtimeDir = p.getString("runtimeDir", f.runtimeDir);
        return f;
    }

    public void save(Context c) {
        sp(c).edit()
                .putString("name", name)
                .putInt("mode", mode)
                .putString("exe", exe)
                .putString("args", args)
                .putString("container", container)
                .putString("user", user)
                .putString("dsPath", dsPath)
                .putBoolean("autoAttach", autoAttach)
                .putString("rootDir", rootDir)
                .putString("chromeArgs", chromeArgs)
                .putString("url", url)
                .putBoolean("kgsl", kgsl)
                .putString("envExtra", envExtra)
                .putInt("perfMode", perfMode)
                .putBoolean("relayVerbose", relayVerbose)
                .putInt("display", display)
                .putString("runtimeDir", runtimeDir)
                .apply();
    }
}
