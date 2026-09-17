package com.anland.appwrap;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import com.anlandnext.awl.Awl;

import java.io.BufferedReader;
import java.io.FileDescriptor;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * anland-appwrap —— 把 Linux 程序（这里是 Chrome）包成独立 APK 的控制台。
 *
 * 主路径（chroot）：
 *   1. 「安装 rootfs」把 APK 内置的 rootfs.tar.xz 解到 /data/adb/anland-chrome/root
 *      （Java 解 xz → root 侧 toybox tar 接收流；之后补 /dev/shm、resolv.conf、ldconfig）
 *   2. 「启动」：Awl.getWaylandFd() 拿连接 → su -c <chroot 脚本>
 *      （挂 /proc /sys /dev /dev/shm → chroot → WAYLAND_SOCKET=<fd> → chrome）
 *   3. Chrome 建窗口 → 本 App 收到事件 → Awl.attachWindow 交给 libawl 的
 *      AwlWindowActivity 接管 Surface，守护进程把画面渲染上去
 */
public final class MainActivity extends Activity {

    private static final String TAG = "appwrap";
    private static final int BUF_MAX = 64 * 1024;

    private AppCfg cfg;
    private TextView statusView, logView;
    private EditText rootEdit, chromeArgsEdit, urlEdit, exeEdit, ctrEdit, userEdit, dsEdit, rtEdit, envEdit;
    private RadioGroup modeGroup, dispGroup, perfGroup;
    private CheckBox autoAttachBox, gpuBox, twoStepBox, relayVerboseBox;
    private ProgressBar progress;
    private LinearLayout panel;              /* 控制台面板（配置/日志/诊断），默认隐藏 */

    private final StringBuilder logBuf = new StringBuilder();
    private FileDescriptor conn;
    private Awl.ClientProcess proc;
    private Process shProc;              /* 中继模式下 Chrome 的 su 进程（无 fd，走普通管道） */
    private final java.util.List<ParcelFileDescriptor> relayKeep = new java.util.ArrayList<>();
    private volatile boolean busy;
    /* 主线程 Handler：**不要**用 logView.postDelayed() —— 控制台面板现在不挂进视图树，
     * 而没 attach 的 View 的 post 回调要等 attach 才执行，等于永远不执行
     * （自动流程因此静默失效过一轮：点开 App 什么都不会发生）。 */
    private final android.os.Handler ui = new android.os.Handler(android.os.Looper.getMainLooper());
    private long lastUiFlush;               /* 日志框刷新节流（见 appendRaw） */
    private boolean uiFlushPending;
    private boolean prepared;               /* 本次启动是否已经做过"清残留 + 音频自检" */
    private boolean forceRelaunch;          /* 「重新打开」= 即使已有窗口也要重启 Chrome */
    private boolean autoFlowDone;           /* 首屏自动流程是否已经跑过（避免 onResume 重复触发） */
    private boolean installAutoPending;     /* 首次运行：解包完成后自动接着启动 Chrome */
    private boolean autostartPending;       /* 已收到 autostart 指令 → autoFlow 让路，别启动两遍 */

    private final Awl.Callback wcb = new Awl.Callback() {
        @Override public void onWindowCreated(long id, String title) {
            logLine("窗口创建 id=" + id + " title=" + title);
            if (cfg != null && cfg.autoAttach) attach(id, title);
        }
        @Override public void onWindowDestroyed(long id) { logLine("窗口销毁 id=" + id); }
        @Override public void onWindowAttached(long id) { logLine("窗口已挂载 id=" + id); }
        @Override public void onWindowDetached(long id) { logLine("窗口已卸载 id=" + id); }
    };

    /* ------------------------------------------------------------------ 生命周期 */

    @Override protected void onCreate(Bundle st) {
        super.onCreate(st);
        cfg = AppCfg.load(this);

        /* 便于用 adb 远程驱动测试（extras 的语义见 handleIntentExtras）：
         *   am start -n com.anland.appwrap/.MainActivity --ez autostart true \
         *      --es args "<Chrome 参数>" --es url "<起始 URL>" --es env "K=V K=V" \
         *      --es shf /data/local/tmp/x.sh
         * 关键点：setIntent 之外还实现了 onNewIntent，所以 App 已经在跑（中继已就绪）时
         * 再下发命令**不会重启 App、不会掐断中继** —— 换 GL 后端做 A/B 就靠这个。
         * 注意必须放在 buildUi() 之后：handleIntentExtras 会 logLine，而 logLine 要往
         * 日志框里写（buildUi 之前 logView 是 null → 直接 NPE 闪退）。 */

        buildUi();
        logLine("守护进程: " + (Awl.available() ? "可用 (anland.host)" : "不可用 —— anland-awl 模块装了吗？"));
        handleIntentExtras(getIntent(), true);
        new Thread(() -> {
            boolean ok = Rootfs.installed(this, cfg);
            runOnUiThread(() -> logLine("rootfs(" + cfg.rootDir + "): "
                    + (ok ? "已安装" : "未安装 —— 点「安装 rootfs」")));
        }, "check-rootfs").start();

        /* 「打开 App 就是 Chrome」：等界面建好、extras 处理完，自动走一遍流程。
         * 已经有窗口就只是挂载回来（切回浏览器），没有才启动。 */
        ui.postDelayed(this::autoFlow, 600);
    }

    /** onNewIntent：App 已在运行时再收到 am start（不重建、不重启 → 中继不受影响）。 */
    @Override protected void onNewIntent(android.content.Intent it) {
        super.onNewIntent(it);
        setIntent(it);
        logLine("onNewIntent：收到新的 adb 指令");
        handleIntentExtras(it, false);
    }

    /**
     * extras 语义（都能从 adb 下发，且会写回配置）：
     *   --ez autostart true     3 秒后自动「保存 + 启动」
     *   --es args "<chrome 参数>"   覆盖 Chrome 参数
     *   --es url  "<URL>"           覆盖起始页
     *   --es env  "K=V K=V"         额外环境变量（注入 chroot 的 env -i，用来换 GL 后端）
     *   --ez kgsl true/false        kgsl 真 GPU（危险，见 AppCfg 注释）
     *   --ez rv   true/false        中继逐条日志（排障用，会拖慢）
     *   --es shf /path/script.sh    以 root 执行脚本（排障钩子，见 remoteShell）
     *   --es sh  "命令"             同上，直接给命令
     */
    private void handleIntentExtras(android.content.Intent it, boolean first) {
        if (it == null) return;
        String a = it.getStringExtra("args");
        if (a != null && !a.isEmpty()) { cfg.chromeArgs = a; cfg.save(this); }
        String u = it.getStringExtra("url");
        if (u != null && !u.isEmpty()) { cfg.url = u; cfg.save(this); }
        String ev = it.getStringExtra("env");
        if (ev != null) { cfg.envExtra = ev.trim(); cfg.save(this); }
        if (it.hasExtra("kgsl")) { cfg.kgsl = it.getBooleanExtra("kgsl", false); cfg.save(this); }
        if (it.hasExtra("rv")) { cfg.relayVerbose = it.getBooleanExtra("rv", false); cfg.save(this); }
        /* 后端/模式也能直接指定：--ei disp 3（3=wayland 中继）--ei mode 3（3=chroot）。
         * 没有它就只能靠界面单选组，而单选组状态一旦异常，saveCfg() 会把错的写回配置
         * （曾经因此持久化成 display=0=X11，窗口标题直接变成 "Xwayland"）。 */
        if (it.hasExtra("disp")) { cfg.display = it.getIntExtra("disp", cfg.display); cfg.save(this); }
        if (it.hasExtra("mode")) { cfg.mode = it.getIntExtra("mode", cfg.mode); cfg.save(this); }
        /* --ei perf 0|1|2 → 流畅/原版/kgsl 档位（会重写 chromeArgs 与 kgsl 开关） */
        if (it.hasExtra("perf")) {
            cfg.perfMode = it.getIntExtra("perf", cfg.perfMode);
            cfg.applyPreset();
            cfg.save(this);
        }
        /* --es root <目录>：换一个 rootfs 目录跑（测试精简版 rootfs 用，也方便多份共存） */
        String rd = it.getStringExtra("root");
        if (rd != null && !rd.isEmpty()) { cfg.rootDir = rd; cfg.save(this); }

        /* 远程 root-shell 钩子：设备上对 /data/adb 下 rootfs 的写入必须由本进程的
         * su 子进程完成（adb shell 的 su 在另一个 mount namespace / 上下文里，
         * 常常 Permission denied），所以修复 rootfs、跑 GL 实验都从这里下发。
         * 带 root 权限，发布版应删掉。 */
        final String rsh = it.getStringExtra("sh");
        final String rshf = it.getStringExtra("shf");
        if ((rsh != null || rshf != null) && !BuildConfig.DEBUG_HOOKS) {
            logLine("忽略 --es sh/shf：release 包里没有远程 root 命令钩子（用 debug 包排障）");
            syncUiFromCfg();
            return;
        }

        /* 改了 cfg 就得回填控件，否则 launch()→saveCfg() 会用旧文本把它盖回去 */
        syncUiFromCfg();

        if (rsh != null || rshf != null)
            remoteShell((rshf != null && !rshf.isEmpty()) ? ("sh " + rshf) : rsh);

        if (it.getBooleanExtra("autostart", false)) {
            /* 一定要置 forceRelaunch：否则 autoFlow 会先把**旧窗口**挂起来，
             * 3 秒后 autostart 又把旧 Chrome 杀掉重启 —— 屏幕上留下一个死窗口
             * （画面冻结），而新 Chrome 在后台出声（音频不走中继）。
             * 症状就是"窗口出来了但卡死，声音正常"。 */
            forceRelaunch = true;
            autostartPending = true;
            logLine(first ? "autostart：3 秒后自动「保存 + 启动」"
                          : "autostart（onNewIntent）：3 秒后重新「保存 + 启动」");
            ui.postDelayed(() -> { autostartPending = false; saveCfg(); launch(); }, 3000);
        }
    }

    /**
     * 把 cfg 回填到界面控件。
     * 必须做：handleIntentExtras 改的是 cfg，而 launch() 里的 saveCfg() 是拿**控件里的文本**
     * 反过来覆盖 cfg 的 —— 不回填的话，adb 用 --es args/--es env 下发的值和配置里存的
     * 完全是两码事（曾经因此让"换参数重启"一直用着旧参数，白折腾好几轮）。
     */
    private void syncUiFromCfg() {
        if (rootEdit == null) return;
        rootEdit.setText(cfg.rootDir);
        chromeArgsEdit.setText(cfg.chromeArgs);
        urlEdit.setText(cfg.url);
        envEdit.setText(cfg.envExtra);
        exeEdit.setText(cfg.exe);
        ctrEdit.setText(cfg.container);
        userEdit.setText(cfg.user);
        dsEdit.setText(cfg.dsPath);
        rtEdit.setText(cfg.runtimeDir);
        autoAttachBox.setChecked(cfg.autoAttach);
        gpuBox.setChecked(cfg.kgsl);
        relayVerboseBox.setChecked(cfg.relayVerbose);
        modeGroup.check(cfg.mode + 1);
        dispGroup.check(1000 + cfg.display);
        perfGroup.check(100 + cfg.perfMode);
    }

    /** 排障钩子：让 App（的 su 子进程）去执行一段 root 脚本，输出镜像到 logcat。 */
    private void remoteShell(String script) {
        logLine("远程命令: " + script);
        new Thread(() -> {
            RootExec.Result r = RootExec.run(script, 900_000);
            runOnUiThread(() -> {
                for (String l : r.out.split("\n")) if (!l.trim().isEmpty()) logLine("  " + l);
                for (String l : r.err.split("\n")) if (!l.trim().isEmpty()) logLine("  ! " + l);
                logLine("远程命令结束 exit=" + r.exit);
            });
        }, "remote-sh").start();
    }

    @Override protected void onResume() {
        super.onResume();
        Awl.registerCallback(wcb);
        Awl.ensureSubscribed();
        refreshWindows();
    }

    @Override protected void onPause() {
        Awl.unregisterCallback(wcb);
        super.onPause();
    }

    /* ------------------------------------------------------------------ 界面 */

    private void buildUi() {
        /* 整页可滚动：配置行 + 两组单选 + 复选框 + 11 个按钮 + 日志，竖着放一屏装不下，
         * 之前直接塞进不可滚动的 LinearLayout，结果屏幕以下的部分全被裁掉（只能看到上半部分）。
         * 现在外层是 ScrollView，日志区给固定高度并自己滚动。 */
        ScrollView page = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(12);
        root.setPadding(pad, pad, pad, pad);

        statusView = new TextView(this);
        statusView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        root.addView(statusView);

        /* ---- 简洁首页：状态 + 进度 + 三个按钮 ----
         * 目标形态：从桌面点开这个 App 就直接是 Chrome（已装好 rootfs 时）。
         * 配置项/日志/诊断这些排障用控件依然会构建（panel），但**不挂进视图树**，
         * 所以界面上看不到「设置/诊断」入口了。要用时把 root.addView(panel) 加回来即可；
         * 也可以继续用广播钩子远程排障（见 tools/ 下的脚本与 README「排障脚本」）。 */
        LinearLayout home = new LinearLayout(this);
        home.setOrientation(LinearLayout.HORIZONTAL);
        home.addView(button("重新打开", v -> { forceRelaunch = true; autoFlow(); }));
        home.addView(button("停止", v -> stop()));
        root.addView(home);

        /* 懒人版首页就这三个选项：选完立刻写好整串 Chrome 参数并自动重启 Chrome 生效。 */
        TextView pl = new TextView(this);
        pl.setText("性能模式（选了会自动重启 Chrome 生效）:");
        pl.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        root.addView(pl);
        perfGroup = new RadioGroup(this);
        perfGroup.setOrientation(RadioGroup.VERTICAL);
        addPerf(perfGroup, "流畅（0.4 倍 + 关 GPU 合成，推荐）", AppCfg.PERF_SMOOTH);
        addPerf(perfGroup, "原版（0.6 倍，动画特效照旧）", AppCfg.PERF_STOCK);
        perfGroup.check(100 + cfg.perfMode);
        perfGroup.setOnCheckedChangeListener((g, id) -> {
            if (id <= 0) return;
            int m = id - 100;
            if (m == cfg.perfMode) return;
            cfg.perfMode = m;
            cfg.applyPreset();               /* 重写 chromeArgs */
            syncUiFromCfg();                 /* 参数框跟着更新，否则 saveCfg() 又会用旧文本盖回去 */
            cfg.save(this);
            logLine("性能模式 → " + AppCfg.presetName(m));
            logLine("参数: " + cfg.chromeArgs);
            forceRelaunch = true;
            autoFlow();
        });
        root.addView(perfGroup);
        /* 已经选中的档位不会再触发 RadioGroup 回调（比如参数被手改过想恢复），所以留个按钮 */
        LinearLayout perfBar = new LinearLayout(this);
        perfBar.addView(button("应用此档位并重启 Chrome", v -> {
            cfg.applyPreset();
            syncUiFromCfg();
            cfg.save(this);
            logLine("已应用档位「" + AppCfg.presetName(cfg.perfMode) + "」");
            logLine("参数: " + cfg.chromeArgs);
            forceRelaunch = true;
            autoFlow();
        }));
        root.addView(perfBar);

        panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setVisibility(android.view.View.GONE);
        /* 注意：这里**故意不** root.addView(panel) —— 控制台不显示。 */

        rootEdit = addRow(panel, "rootfs 目录", cfg.rootDir);
        chromeArgsEdit = addRow(panel, "Chrome 参数", cfg.chromeArgs);
        urlEdit = addRow(panel, "起始 URL", cfg.url);
        envEdit = addRow(panel, "额外环境变量", cfg.envExtra);

        /* 不常用的项折叠起来：手机屏幕小，默认只留常用的三行 */
        final LinearLayout advanced = new LinearLayout(this);
        advanced.setOrientation(LinearLayout.VERTICAL);
        advanced.setVisibility(android.view.View.GONE);
        exeEdit = addRow(advanced, "命令(容器/原生)", cfg.exe);
        ctrEdit = addRow(advanced, "容器名", cfg.container);
        userEdit = addRow(advanced, "容器内用户", cfg.user);
        dsEdit = addRow(advanced, "droidspaces", cfg.dsPath);
        rtEdit = addRow(advanced, "守护进程 runtime", cfg.runtimeDir);

        modeGroup = new RadioGroup(this);
        modeGroup.setOrientation(RadioGroup.HORIZONTAL);
        addMode(modeGroup, "chroot", AppCfg.MODE_CHROOT);
        addMode(modeGroup, "容器", AppCfg.MODE_CONTAINER);
        addMode(modeGroup, "原生", AppCfg.MODE_NATIVE);
        addMode(modeGroup, "仅宿主", AppCfg.MODE_EXTERNAL);
        modeGroup.check(cfg.mode + 1);
        panel.addView(modeGroup);

        /* 画面后端（只对 chroot 模式有意义） */
        TextView dl = new TextView(this);
        dl.setText("画面后端（chroot 模式）:");
        dl.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        panel.addView(dl);
        dispGroup = new RadioGroup(this);
        dispGroup.setOrientation(RadioGroup.HORIZONTAL);
        addDisp(dispGroup, "wayland(relay)", Launcher.DISP_WAYLAND_RELAY);
        addDisp(dispGroup, "x11(Xwayland)", Launcher.DISP_X11);
        addDisp(dispGroup, "wayland(fd)", Launcher.DISP_WAYLAND_FD);
        addDisp(dispGroup, "wl-socket(root)", Launcher.DISP_WAYLAND_SOCKET);
        dispGroup.check(1000 + cfg.display);
        panel.addView(dispGroup);

        CheckBox advBox = check(panel, "显示高级项", false);
        advBox.setOnCheckedChangeListener((b, on) ->
                advanced.setVisibility(on ? android.view.View.VISIBLE : android.view.View.GONE));
        panel.addView(advanced);

        autoAttachBox = check(panel, "新窗口自动挂载", cfg.autoAttach);
        gpuBox = check(panel, "⚠ kgsl 真 GPU（与 Android 抢 GPU，实测会把 SurfaceFlinger 搞崩→软重启）", cfg.kgsl);
        gpuBox.setOnCheckedChangeListener((b, on) -> {
            if (on) logLine("⚠ 已开启 kgsl：chroot 里的 Mesa 会和 Android 的 Adreno 驱动共用 GPU，"
                    + "实测导致 SurfaceFlinger SIGABRT + 软重启。除非你在做实验，否则不要开。");
        });
        twoStepBox = check(panel, "两步解包（排查 tar 管道问题时用）", false);
        /* 中继逐条消息日志：默认关。开着会每秒几十 MB 分配（App 要把它镜像到
         * 日志框和 logcat），把 Chrome 的 CPU 抢走 —— 只有查"中继到底转没转"才开。 */
        relayVerboseBox = check(panel, "中继 verbose 日志（排障用，会拖慢）", cfg.relayVerbose);

        LinearLayout bar1 = new LinearLayout(this);
        bar1.addView(button("保存", v -> saveCfg()));
        bar1.addView(button("安装 rootfs", v -> installRootfs()));
        bar1.addView(button("启动", v -> launch()));
        bar1.addView(button("停止", v -> stop()));
        panel.addView(bar1);

        LinearLayout bar2 = new LinearLayout(this);
        bar2.addView(button("刷新窗口", v -> refreshWindows()));
        bar2.addView(button("全部挂载", v -> attachAll()));
        bar2.addView(button("清理 rootfs", v -> wipeRootfs()));
        bar2.addView(button("自检", v -> selfTest()));
        /* 跑设备上的 /data/local/tmp/appwrap-sh.sh（以 root，在 App 的命名空间里）——
         * 排障钩子的 UI 入口，和 Intent 的 --es shf 等价。 */
        bar2.addView(button("跑远程脚本", v -> remoteShell("sh /data/local/tmp/appwrap-sh.sh")));
        bar2.addView(button("清日志", v -> { logBuf.setLength(0); logView.setText(""); }));
        panel.addView(bar2);

        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(1000);
        progress.setVisibility(android.view.View.GONE);
        root.addView(progress);

        ScrollView scroll = new ScrollView(this);
        logView = new TextView(this);
        logView.setTypeface(Typeface.MONOSPACE);
        logView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        logView.setTextIsSelectable(true);
        scroll.addView(logView, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        /* 日志区给固定高度（自己滚），把剩下的高度留给整页滚动 */
        panel.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(240)));

        page.addView(root, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(page);
    }

    private EditText addRow(LinearLayout parent, String label, String value) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView t = new TextView(this);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        t.setMinWidth(dp(104));
        row.addView(t);
        EditText e = new EditText(this);
        e.setText(value);
        e.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        e.setSingleLine(true);
        row.addView(e, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        parent.addView(row);
        return e;
    }

    private Button button(String text, android.view.View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(text);
        b.setOnClickListener(l);
        return b;
    }

    private CheckBox check(LinearLayout parent, String text, boolean on) {
        CheckBox c = new CheckBox(this);
        c.setText(text);
        c.setChecked(on);
        parent.addView(c);
        return c;
    }

    private void addMode(RadioGroup g, String label, int mode) {
        RadioButton r = new RadioButton(this);
        r.setText(label);
        r.setId(mode + 1);
        g.addView(r);
    }

    private void addDisp(RadioGroup g, String label, int disp) {
        RadioButton r = new RadioButton(this);
        r.setText(label);
        r.setId(1000 + disp);
        g.addView(r);
    }

    /** 性能档位的单选按钮（id = 100 + mode） */
    private void addPerf(RadioGroup g, String label, int mode) {
        RadioButton r = new RadioButton(this);
        r.setText(label);
        r.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        r.setId(100 + mode);
        g.addView(r);
    }

    private int selectedDisp() {
        int id = dispGroup.getCheckedRadioButtonId();
        /* 兜底必须是 relay（默认后端），不能是 X11：syncUiFromCfg()/单选组状态异常时
         * 会走这里，曾经因此莫名其妙地按 X11 启动（窗口标题直接变成 "Xwayland"）。 */
        return id <= 0 ? Launcher.DISP_WAYLAND_RELAY : id - 1000;
    }

    private int selectedMode() {
        int id = modeGroup.getCheckedRadioButtonId();
        return id <= 0 ? AppCfg.MODE_CHROOT : id - 1;
    }

    /* ------------------------------------------------------------------ 动作 */

    private void saveCfg() {
        /* 懒人版没有配置界面了：cfg 自己就是唯一真相，这里只负责落盘。
         * 以前 saveCfg() 拿界面控件反覆盖 cfg（mode/display/chromeArgs 都因此被写坏过：
         * 面板一旦不挂进视图树，单选组状态就不对，display 会被写成 0 = X11，
         * 于是莫名其妙按 Xwayland 启动）。现在配置只能由下面这些途径改：
         *   · 首页的「性能模式」两个档
         *   · adb extras（--ei disp/mode/perf、--es args/url/env、--ez kgsl/rv）
         *   · 广播钩子 */
        cfg.save(this);
        logLine("已保存: mode=" + cfg.mode + " display=" + cfg.display
                + " perf=" + AppCfg.presetName(cfg.perfMode)
                + " kgsl=" + cfg.kgsl + " env='" + cfg.envExtra + "'");
    }

    private static String text(EditText e, String def) {
        String s = e.getText().toString().trim();
        return s.isEmpty() ? def : s;
    }

    /** 首次安装：解包内置 rootfs（几分钟，跑在后台线程）。 */
    private void installRootfs() {
        saveCfg();
        if (busy) { toast("正在忙，先等一会儿"); return; }
        busy = true;
        showProgress(true, true, 0);
        new Thread(() -> {
            Rootfs.Progress cb = new Rootfs.Progress() {
                @Override public void phase(String note) {
                    runOnUiThread(() -> { logLine(note); showProgress(true, true, 0); });
                }
                @Override public void bytes(long done, long total) {
                    runOnUiThread(() -> {
                        statusView.setText("解包中: " + (done / 1024 / 1024) + " MB");
                        showProgress(true, false, 0);
                    });
                }
            };
            RootExec.Result r = Rootfs.install(this, cfg, cb, twoStepBox.isChecked());
            runOnUiThread(() -> {
                busy = false;
                showProgress(false, false, 0);
                statusView.setText("");
                logLine(r.ok ? "rootfs 安装完成 ✓" : "rootfs 安装失败: " + r.why());
                if (r.ok) refreshWindows();
                /* 首次运行的自动流程：装完直接接着启动 Chrome，不用再点按钮 */
                if (r.ok && installAutoPending) {
                    installAutoPending = false;
                    ui.postDelayed(this::launch, 1500);
                }
            });
        }, "install-rootfs").start();
    }

    /**
     * 打开 App 的自动流程 —— 目标形态：从桌面点开就是 Chrome。
     *   1) rootfs 没装 → 自动解包（几分钟，带进度），装完自动接着启动
     *   2) 守护进程不在 → 用 root 从模块目录拉起（软重启后它不会自己回来）
     *   3) 已经有活着的 Chrome 窗口 → 直接挂载回来，**不重启 Chrome**（等于"切回浏览器"）
     *   4) 否则 → 音频自检 → 启动 Chrome（wayland 中继）→ 窗口出现即自动挂载
     * 「重新打开」按钮会强制走 4)。
     */
    private void autoFlow() {
        /* autostart 的下发方（adb / 广播）3 秒后自己会调 launch()：这里必须让路，
         * 否则一口气启动两遍 —— 第一遍起的 Chrome/中继会被第二遍的 cleanup 杀掉，
         * 屏幕上留下第一个窗口的死画面（看着就是"刚进去就卡死"）。 */
        if (autostartPending) { logLine("已收到 autostart 指令，交给它启动"); return; }
        if (cfg.mode != AppCfg.MODE_CHROOT) {
            logLine("当前不是 chroot 模式（mode=" + cfg.mode + "）：展开「⚙ 设置/诊断」手动启动");
            return;
        }
        new Thread(() -> {
            boolean ok = Rootfs.installed(this, cfg);
            runOnUiThread(() -> {
                if (!ok) {
                    if (busy) { logLine("正在解包中…"); return; }
                    logLine("首次运行：开始解包内置 rootfs（约 2.3 GB，几分钟）");
                    installAutoPending = true;
                    installRootfs();
                    return;
                }
                List<Awl.WlWindow> ws = Awl.getWindows();
                boolean alive = ws != null && !ws.isEmpty();
                /* 守护进程比 SF 老 → 它那条 SurfaceControl 连接已经发霉：此时挂载旧窗口
                 * 只会得到一张冻住的画面，所以强制重启 Chrome（launch 的 prepare 阶段
                 * 会先重启守护进程）。 */
                if (alive) {
                    RootExec.Result hr = RootExec.run(Launcher.daemonHealthScript(), 30_000);
                    if (!hr.out.contains("DAEMON-OK")) {
                        logLine("守护进程连接已过期（" + hr.out.trim() + "）→ 重启 Chrome 而不是挂旧窗口");
                        forceRelaunch = true;
                    }
                }
                if (alive && !forceRelaunch) {
                    logLine("已有 Chrome 窗口（" + ws.size() + " 个）→ 直接挂载回来，不重启");
                    attachAll();
                } else {
                    forceRelaunch = false;
                    launch();
                }
            });
        }, "autoflow").start();
    }

    private void wipeRootfs() {        saveCfg();
        new Thread(() -> {
            RootExec.Result r = Rootfs.wipe(this, cfg);
            runOnUiThread(() -> logLine("清理: " + (r.ok ? "完成" : r.why())));
        }, "wipe-rootfs").start();
    }

    private void launch() {
        saveCfg();
        /* 守护进程不在就自己拉起来：框架软重启（SurfaceFlinger 挂掉）后它不会自动回来，
         * 用户看到的现象是"点了启动没反应"。这里补上恢复路径，装上就能用。 */
        if (!Awl.available()) {
            logLine("守护进程不可用 —— 用 root 拉起来（模块目录里的二进制在 App 命名空间里可执行）");
            new Thread(() -> {
                RootExec.Result r = RootExec.run(Launcher.startDaemonScript(), 90_000);
                for (String l : r.out.split("\n")) if (!l.trim().isEmpty()) logLine("  " + l);
                for (String l : r.err.split("\n")) if (!l.trim().isEmpty()) logLine("  ! " + l);
                try { Thread.sleep(1500); } catch (InterruptedException ignored) { }
                runOnUiThread(() -> {
                    if (!Awl.available()) {
                        toast("守护进程仍然起不来：检查 anland-awl 模块 / 重启一次设备");
                        return;
                    }
                    logLine("守护进程已就绪");
                    launchInternal();
                });
            }, "start-daemon").start();
            return;
        }
        launchInternal();
    }

    private void launchInternal() {
        if (!Awl.available()) { toast("守护进程不可用：anland-awl 模块没装或没起来"); return; }
        /* 准备阶段（清残留 + 查音频 sink）跑在后台线程：RootExec 是阻塞的，
         * 放 UI 线程上会卡住界面（这两步最坏要十几秒）。做完再回 UI 线程继续。 */
        if (cfg.mode == AppCfg.MODE_CHROOT && !prepared) {
            prepared = true;
            logLine("准备：清理上次残留 + 检查音频 sink …");
            new Thread(() -> {
                /* 先关掉还在挂着的旧窗口：客户端马上要被杀掉，留着的窗口会冻在最后一帧，
                 * 而新窗口是另一个 id —— 用户就会看到"死画面 + 有声音"。 */
                List<Awl.WlWindow> old = Awl.getWindows();
                if (old != null) for (Awl.WlWindow w : old) {
                    logLine("关闭旧窗口 id=" + w.id + "（" + w.title + "）");
                    Awl.closeWindow(w.id);
                }
                RootExec.Result hr = RootExec.run(Launcher.daemonHealthScript(), 30_000);
                logLine("守护进程健康检查: " + hr.out.trim());
                if (!hr.out.contains("DAEMON-OK")) {
                    /* SF 重启过 / 守护进程不在 → 必须换一条新的 SurfaceControl 连接，
                     * 否则画面会冻在最后一帧（输入也没反应），但声音照常 —— 见 Launcher 注释。 */
                    logLine("→ 重启守护进程以拿到新的 SurfaceControl 连接");
                    RootExec.Result rr = RootExec.run(Launcher.restartDaemonScript(), 90_000);
                    for (String l : rr.out.split("\n")) if (!l.trim().isEmpty()) logLine("  " + l);
                    try { Thread.sleep(1500); } catch (InterruptedException ignored) { }
                }
                RootExec.Result cr = RootExec.run(Launcher.cleanupScript(cfg.rootDir), 60_000);
                logLine(cr.ok ? "已清理上一次残留" : ("清理残留时: " + cr.why()));
                RootExec.Result pr = RootExec.run(Launcher.pulseEnsureScript(cfg), 180_000);
                for (String l : pr.out.split("\n")) if (!l.trim().isEmpty()) logLine("  " + l);
                for (String l : pr.err.split("\n")) if (!l.trim().isEmpty()) logLine("  ! " + l);
                runOnUiThread(this::launchInternal);
            }, "prepare").start();
            return;
        }
        prepared = false;
        if (cfg.mode == AppCfg.MODE_CHROOT && cfg.kgsl) {
            logLine("⚠ kgsl=true：chroot 里的 Mesa 会直连 GPU，与 Android 的 Adreno 驱动"
                    + "共用 /dev/kgsl-3d0 —— 实测会让 SurfaceFlinger SIGABRT 并软重启，风险自负");
        }
        FileDescriptor fd = Awl.getWaylandFd();
        if (fd == null) { logLine("getWaylandFd() 失败（socketpair / T_CONNECT 被拒）"); return; }
        logLine("wayland 连接已建立（本进程创建 → 守护进程记的 uid 就是我们）");

        switch (cfg.mode) {
            case AppCfg.MODE_CHROOT: {
                if (cfg.display == Launcher.DISP_WAYLAND_RELAY) {
                    launchChrootRelay(fd);
                    break;
                }
                String[] argv = Launcher.chrootArgv(cfg);
                logLine("chroot → " + cfg.rootDir + "/opt/google/chrome/chrome");
                logLine("画面后端: " + (cfg.display == Launcher.DISP_X11 ? "x11(Xwayland)"
                        : cfg.display == Launcher.DISP_WAYLAND_FD ? "wayland(fd)"
                        : "wayland 套接字(root 身份)"));
                logLine("参数: " + (cfg.display == Launcher.DISP_X11
                        ? Launcher.x11Args(cfg.chromeArgs) : cfg.chromeArgs));
                Awl.ClientProcess p = Awl.spawnClient(fd, argv[0], argv[1], argv[2]);
                if (p == null) { logLine("spawnClient(su) 失败"); return; }
                proc = p;
                logLine("Chrome 已启动 pid=" + p.pid);
                pump("out", p.stdout);
                pump("err", p.stderr);
                break;
            }
            case AppCfg.MODE_NATIVE: {
                String exe = Launcher.resolveExe(this, cfg.exe);
                List<String> argv = Launcher.splitArgs(cfg.args);
                logLine("exec " + exe + " " + argv);
                Awl.ClientProcess p = Awl.spawnClient(fd, exe, argv.toArray(new String[0]));
                if (p == null) { logLine("spawnClient 失败"); return; }
                proc = p;
                logLine("已启动 pid=" + p.pid);
                pump("out", p.stdout);
                pump("err", p.stderr);
                break;
            }
            case AppCfg.MODE_CONTAINER: {
                String[] argv = Launcher.containerArgv(cfg.dsPath, cfg.container, cfg.exe, cfg.user);
                logLine("su -c " + argv[2]);
                Awl.ClientProcess p = Awl.spawnClient(fd, argv[0], argv[1], argv[2]);
                if (p == null) { logLine("spawnClient(su) 失败"); return; }
                proc = p;
                logLine("已启动 pid=" + p.pid);
                pump("out", p.stdout);
                pump("err", p.stderr);
                break;
            }
            default: {
                conn = fd;
                logLine("仅宿主模式：连接已持有，请自行在外部启动目标程序（必须用这条连接）");
                break;
            }
        }
        ui.postDelayed(this::attachAll, 4000);
    }

    /**
     * wayland(relay) 后端：
     *   1) 经 spawnClient 起中继（su=root，fd 继承给它）→ 它在 $R/tmp/wayland-0 上 listen，
     *      并把自己继承到的那个 socketpair 端当成"守护进程连接"来转发
     *   2) 等套接字就绪
     *   3) 普通 su 起 chroot + Chrome（Chrome 用**路径**连中继，不碰 WAYLAND_SOCKET）
     * 于是 Chrome 是正经 Wayland 客户端（能拿 zwp_text_input_v3 → Android 键盘），
     * 而守护进程看到的凭据仍然是本 App（socketpair 创建时固定）→ 窗口归属我们。
     */
    private void launchChrootRelay(FileDescriptor fd) {
        String relayExe = getApplicationInfo().nativeLibraryDir + "/" + Launcher.RELAY_LIB;

        /* 多备几条上游连接：Chromium 的浏览器进程与 GPU 进程会各开一条 Wayland 连接。
         * 做法：再多要两条 getWaylandFd()，dup 成非 CLOEXEC 的 fd 拿号码（fork 后子进程里
         * 号码不变），并把 ParcelFileDescriptor 保活（被 GC 会把这些 fd 关掉）。 */
        java.util.List<Integer> extras = new java.util.ArrayList<>();
        for (int i = 0; i < 2; i++) {
            FileDescriptor f = Awl.getWaylandFd();
            if (f == null) { logLine("附加连接 getWaylandFd() 失败（第 " + (i + 1) + " 条）"); break; }
            try {
                ParcelFileDescriptor p = ParcelFileDescriptor.dup(f);
                /* PFD.dup() 在 Android 上默认带 CLOEXEC —— 不清掉的话 fork 出去的中继
                 * 拿不到它（表现为中继报 "Bad file descriptor"）。 */
                FileDescriptor pf = p.getFileDescriptor();
                int fl = android.system.Os.fcntlInt(pf, android.system.OsConstants.F_GETFD, 0);
                if ((fl & android.system.OsConstants.FD_CLOEXEC) != 0) {
                    android.system.Os.fcntlInt(pf, android.system.OsConstants.F_SETFD,
                            fl & ~android.system.OsConstants.FD_CLOEXEC);
                    logLine("附加连接 fd " + p.getFd() + " 已清掉 CLOEXEC");
                }
                extras.add(p.getFd());
                relayKeep.add(p);                 /* 保活：被 GC 会把这个 fd 关掉 */
                android.system.Os.close(f);
            } catch (Exception ex) {
                logLine("附加连接 dup 失败: " + ex);
                break;
            }
        }
        logLine("上游连接数: " + (1 + extras.size()) + "（含主连接）");

        /* 清掉上一轮可能残留的套接字文件：否则"就绪"检查会假阳性 */
        final String sockPath = Launcher.relaySockPath(cfg);
        RootExec.run("rm -f " + Rootfs.q(sockPath), 10_000);

        String[] rv = Launcher.relayArgv(cfg, relayExe, extras);
        logLine("中继: " + rv[2]);
        Awl.ClientProcess rp = Awl.spawnClient(fd, rv[0], rv[1], rv[2]);
        if (rp == null) { logLine("中继启动失败（spawnClient 返回 null）"); return; }
        logLine("中继已启动 pid=" + rp.pid);
        pump("relay", rp.stdout);
        pump("relay", rp.stderr);

        final String sock = Launcher.relaySockPath(cfg);
        new Thread(() -> {
            boolean ok = false;
            for (int i = 0; i < 40 && !ok; i++) {
                /* 套接字存在 **且** 中继进程还活着，才算就绪：
                 * 只看文件会出现"上一轮残留的套接字"造成的假阳性。 */
                RootExec.Result r = RootExec.run(
                        "[ -S " + Rootfs.q(sock) + " ] && echo SOCK; "
                      + "pgrep libawlrelay.so >/dev/null 2>&1 && echo ALIVE", 5_000);
                boolean sockOk = r.out.contains("SOCK");
                boolean alive = r.out.contains("ALIVE");
                if (sockOk && alive) {
                    ok = true;
                } else if (sockOk && !alive) {
                    runOnUiThread(() -> logLine(
                            "套接字在、但中继进程已经不在了 —— 中继启动失败，看上面 [relay] 的输出"));
                    return;
                }
                try { Thread.sleep(200); } catch (InterruptedException e) { break; }
            }
            final boolean ready = ok;
            runOnUiThread(() -> {
                if (!ready) {
                    logLine("中继套接字 " + sock + " 8 秒内没出现 —— 放弃启动 Chrome（看上面中继的输出）");
                    return;
                }
                logLine("中继就绪: " + sock);
                startChromeViaRelay();
            });
        }, "relay-wait").start();
    }

    /** 中继模式下 Chrome 不需要 fd：普通 su 进程 + 合并输出即可 */
    private void startChromeViaRelay() {
        try {
            Process p = new ProcessBuilder("su", "-c", Launcher.chrootScript(cfg))
                    .redirectErrorStream(true).start();
            shProc = p;
            logLine("Chrome 已启动（经中继，无 fd）");
            pumpProcess("chrome", p);
        } catch (IOException e) {
            logLine("启动 Chrome 失败: " + e);
            return;
        }
        ui.postDelayed(this::attachAll, 4000);
    }

    private void stop() {
        if (cfg != null && (cfg.mode == AppCfg.MODE_CHROOT || cfg.mode == AppCfg.MODE_CONTAINER)) {
            final String script = Launcher.stopAllScript(cfg.rootDir);
            new Thread(() -> {
                RootExec.Result r = RootExec.run(script, 60_000);
                runOnUiThread(() -> logLine("停止: " + (r.ok ? "已发送" : r.why())));
            }, "stop-chrome").start();
        }
        if (shProc != null) {
            shProc.destroy();
            shProc = null;
        }
        if (proc != null) {
            try {
                if (proc.stdin != null) proc.stdin.close();
                if (proc.stdout != null) proc.stdout.close();
                if (proc.stderr != null) proc.stderr.close();
            } catch (Exception ignored) { }
            try { android.system.Os.kill(proc.pid, 15); } catch (Exception ignored) { }
            logLine("已结束 pid=" + proc.pid);
            proc = null;
        }
        if (conn != null) {
            try { android.system.Os.close(conn); } catch (Exception ignored) { }
            conn = null;
            logLine("已关闭我们持有的连接");
        }
        refreshWindows();
    }

    private void refreshWindows() {
        List<Awl.WlWindow> ws = Awl.getWindows();
        if (ws == null) { statusView.setText("窗口: 守护进程不可用"); return; }
        StringBuilder b = new StringBuilder("窗口 " + ws.size() + " 个:");
        for (Awl.WlWindow w : ws)
            b.append("\n  · id=").append(w.id)
             .append(w.attached ? " [已挂载]" : " [未挂载]")
             .append(" title=").append(w.title);
        statusView.setText(b.toString());
    }

    private void attachAll() {
        List<Awl.WlWindow> ws = Awl.getWindows();
        if (ws == null || ws.isEmpty()) { logLine("没有窗口可挂载"); return; }
        for (Awl.WlWindow w : ws) if (!w.attached) attach(w.id, w.title);
    }

    /** 把某个 toplevel 显示成自己的窗口（libawl 的 AwlWindowActivity 接管 Surface）。 */
    private void attach(long id, String title) {
        Awl.HostCallbacks cbs = new Awl.HostCallbacks() {
            @Override public void onHostResume(Awl.WlWindow w, Activity a) { Awl.ensureSubscribed(); }
            @Override public void onHostDestroy(Awl.WlWindow w, Activity a) {
                logLine("宿主销毁 → 请求客户端关闭 id=" + w.id);
                Awl.closeWindow(w.id);
            }
        };
        logLine("挂载窗口 id=" + id + " title=" + title);
        Awl.attachWindow(this, id, title, cbs);
    }

    private void selfTest() {
        logLine("---- 自检 ----");
        logLine("binder anland.host: " + Awl.available());
        FileDescriptor fd = Awl.getWaylandFd();
        logLine("getWaylandFd(): " + (fd != null ? "OK" : "失败"));
        if (fd != null) { try { android.system.Os.close(fd); } catch (Exception ignored) { } }
        logLine("uid=" + android.os.Process.myUid() + " pid=" + android.os.Process.myPid());
        logLine("assets/" + Rootfs.ASSET + " 长度: " + Rootfs.assetLength(this) + " bytes");

        final String r = Rootfs.q(cfg.rootDir);
        /* 注意：Chrome 是 glibc 程序，**必须在 chroot 内**执行。
         * 在 Android 侧直接跑会得到 "No such file or directory" —— 那是内核找不到
         * ELF 解释器 /lib/ld-linux-aarch64.so.1（它只在 rootfs 里），不是文件缺失。 */
        String script =
                "R=" + r + "\n"
              + "echo '--- root 身份 ---'; id\n"
              + "echo '--- rootfs 关键文件 ---'\n"
              + "ls -l \"$R/opt/google/chrome/chrome\" 2>&1\n"
              + "ls -l \"$R/lib/ld-linux-aarch64.so.1\" 2>&1\n"
              + "echo '--- 挂载 ---'\n"
              + "mkdir -p \"$R/proc\" \"$R/sys\" \"$R/dev/shm\" \"$R/tmp\" 2>/dev/null\n"
              + "grep -q \" $R/proc \" /proc/mounts || { mount -t proc proc \"$R/proc\" "
              +   "|| mount --bind /proc \"$R/proc\"; } 2>&1\n"
              + "grep -q \" $R/sys \" /proc/mounts || { mount -t sysfs sysfs \"$R/sys\" "
              +   "|| mount --bind /sys \"$R/sys\"; } 2>&1\n"
              + "grep -q \" $R/dev \" /proc/mounts || mount --bind /dev \"$R/dev\" 2>&1\n"
              + "grep -q \" $R/dev/shm \" /proc/mounts "
              +   "|| mount -t tmpfs -o mode=1777,size=512m tmpfs \"$R/dev/shm\" 2>&1\n"
              + "echo '--- chroot 内验证 ---'\n"
              + "chroot \"$R\" /bin/sh -c 'echo sh-ok; uname -m' 2>&1\n"
              + "chroot \"$R\" /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 --version 2>&1 | head -1\n"
              + "chroot \"$R\" /opt/google/chrome/chrome --no-sandbox --version 2>&1 | head -3\n";

        new Thread(() -> {
            RootExec.Result res = RootExec.run(script, 180_000);
            runOnUiThread(() -> {
                for (String l : res.out.split("\n")) if (!l.trim().isEmpty()) logLine("  " + l);
                for (String l : res.err.split("\n")) if (!l.trim().isEmpty()) logLine("  ! " + l);
                if (!res.ok) logLine("  (脚本退出码 " + res.exit + "：" + res.why() + ")");
                logLine("---- 自检结束 ----");
            });
        }, "selftest").start();
    }

    /* ------------------------------------------------------------------ 进度/日志 */

    private void showProgress(boolean visible, boolean indeterminate, int permille) {
        progress.setVisibility(visible ? android.view.View.VISIBLE : android.view.View.GONE);
        progress.setIndeterminate(indeterminate);
        if (!indeterminate) progress.setProgress(permille);
    }

    private void pump(final String tag, ParcelFileDescriptor pfd) {
        if (pfd == null) return;
        final InputStream in = new ParcelFileDescriptor.AutoCloseInputStream(pfd);
        Thread t = new Thread(() -> {
            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(in, StandardCharsets.UTF_8))) {
                char[] buf = new char[1024];
                int n;
                while ((n = r.read(buf)) > 0) {
                    final String s = new String(buf, 0, n);
                    android.util.Log.i(TAG, "[" + tag + "] " + s);   /* 镜像到 logcat，便于 adb 远程看 */
                    runOnUiThread(() -> appendRaw("[" + tag + "] " + s));
                }
            } catch (Exception ignored) {
            }
            runOnUiThread(() -> logLine("[" + tag + "] 流结束（进程退出？）"));
        }, "appwrap-" + tag);
        t.setDaemon(true);
        t.start();
    }

    /** 同 pump，但对象是普通 Process（中继模式的 Chrome） */
    private void pumpProcess(final String tag, Process p) {
        final InputStream in = p.getInputStream();
        Thread t = new Thread(() -> {
            try (BufferedReader r = new BufferedReader(
                    new InputStreamReader(in, StandardCharsets.UTF_8))) {
                char[] buf = new char[1024];
                int n;
                while ((n = r.read(buf)) > 0) {
                    final String s = new String(buf, 0, n);
                    android.util.Log.i(TAG, "[" + tag + "] " + s);   /* 镜像到 logcat，便于 adb 远程看 */
                    runOnUiThread(() -> appendRaw("[" + tag + "] " + s));
                }
            } catch (Exception ignored) {
            }
            runOnUiThread(() -> logLine("[" + tag + "] 流结束（进程退出？）"));
        }, "appwrap-" + tag);
        t.setDaemon(true);
        t.start();
    }

    private synchronized void appendRaw(String s) {
        logBuf.append(s);
        if (logBuf.length() > BUF_MAX) logBuf.delete(0, logBuf.length() - BUF_MAX);
        /* 节流：以前每来一段就 setText 整块日志（最多 64KB）。Chrome/中继输出密集时
         * 这会让 UI 线程和 GC 一直忙（实测每秒几十 MB 分配），反过来拖慢正在跑的程序。
         * 现在 250ms 内最多刷一次，剩下的等下一次或补一次延迟刷新。 */
        long now = android.os.SystemClock.uptimeMillis();
        if (now - lastUiFlush >= 250) {
            lastUiFlush = now;
            logView.setText(logBuf);
        } else if (!uiFlushPending) {
            uiFlushPending = true;
            ui.postDelayed(() -> {
                uiFlushPending = false;
                lastUiFlush = android.os.SystemClock.uptimeMillis();
                logView.setText(logBuf);
            }, 260);
        }
    }

    private void logLine(String s) {
        runOnUiThread(() -> {
            if (logView != null) appendRaw(s.endsWith("\n") ? s : s + "\n");
            android.util.Log.i(TAG, s);     /* logcat 始终要写：远程排障只靠它 */
        });
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_LONG).show();
        logLine(s);
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
