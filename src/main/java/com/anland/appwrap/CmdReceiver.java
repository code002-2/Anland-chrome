package com.anland.appwrap;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * 远程排障通道：`am broadcast` 进来的 root-shell 钩子。
 *
 * 用法（设备上以 root 执行任意脚本）：
 *   adb shell am broadcast -a com.anland.appwrap.CMD --es shf /data/local/tmp/x.sh
 *   adb shell am broadcast -a com.anland.appwrap.CMD --es sh "命令"
 *   也可以顺带改配置：--es env "K=V"、--es args "<chrome 参数>"、--es url "<URL>"、--ez kgsl false
 *
 * 为什么不用 `am start --es shf`：那要经过 Activity，而本 App 的栈顶常常是挂窗口用的
 * AwlWindowActivity —— `am start` 只会把 task 提到前台，intent 根本不进 onNewIntent
 * （"Activity not started, its current task has been brought to the front"），命令就丢了。
 * 广播不受 Activity 栈影响，随叫随到。
 *
 * 必须由 **App 自己的进程**去执行命令：/data/adb 下的 rootfs 只有 App 的 su 子进程
 * （它的 mount namespace / SELinux 上下文）才写得动、才看得见 bind mount，
 * adb shell 的 su 去做往往 Permission denied。
 *
 * ⚠ 这个接收器是 exported 的：任何 App 都能广播它 → 等于交出 root 命令执行。
 * 只适合自己调试用，发布版请删掉（或加签名级权限校验）。
 */
public final class CmdReceiver extends BroadcastReceiver {

    private static final String TAG = "appwrap";
    public static final String ACTION = "com.anland.appwrap.CMD";

    @Override public void onReceive(Context ctx, Intent it) {
        if (it == null) return;
        /* 这个接收器是 exported 的，等于"谁都能以 root 执行命令"。release 包里必须关掉：
         * 只有 debug 构建（BuildConfig.DEBUG_HOOKS=true）才响应。组件本身在 release 里
         * 依然存在（manifest 是静态的），但收到广播会立刻返回。 */
        if (!BuildConfig.DEBUG_HOOKS) {
            android.util.Log.i(TAG, "[cmd] 忽略：本包未开启远程排障钩子（release 构建）");
            return;
        }
        final AppCfg cfg = AppCfg.load(ctx);
        boolean cfgChanged = false;

        String a = it.getStringExtra("args");
        if (a != null && !a.isEmpty()) { cfg.chromeArgs = a; cfgChanged = true; }
        String u = it.getStringExtra("url");
        if (u != null && !u.isEmpty()) { cfg.url = u; cfgChanged = true; }
        String ev = it.getStringExtra("env");
        if (ev != null) { cfg.envExtra = ev.trim(); cfgChanged = true; }
        if (it.hasExtra("kgsl")) { cfg.kgsl = it.getBooleanExtra("kgsl", false); cfgChanged = true; }
        if (it.hasExtra("rv")) { cfg.relayVerbose = it.getBooleanExtra("rv", false); cfgChanged = true; }
        if (it.hasExtra("disp")) { cfg.display = it.getIntExtra("disp", cfg.display); cfgChanged = true; }
        if (it.hasExtra("mode")) { cfg.mode = it.getIntExtra("mode", cfg.mode); cfgChanged = true; }
        if (it.hasExtra("perf")) {
            cfg.perfMode = it.getIntExtra("perf", cfg.perfMode);
            cfg.applyPreset();
            cfgChanged = true;
        }
        String rd = it.getStringExtra("root");
        if (rd != null && !rd.isEmpty()) { cfg.rootDir = rd; cfgChanged = true; }
        if (cfgChanged) {
            cfg.save(ctx);
            android.util.Log.i(TAG, "[cmd] 配置已更新: kgsl=" + cfg.kgsl + " rv=" + cfg.relayVerbose
                    + " env=" + cfg.envExtra);
        }

        final String sh = it.getStringExtra("sh");
        final String shf = it.getStringExtra("shf");
        if (sh == null && shf == null) {
            android.util.Log.i(TAG, "[cmd] 收到广播（没有 sh/shf，只改了配置）");
            return;
        }
        final String script = (shf != null && !shf.isEmpty()) ? ("sh " + shf) : sh;

        /* 接收器的生命周期只有 onReceive 的几毫秒，跑后台任务前必须 goAsync()，
         * 否则进程可能被回收、脚本输出也回不来。 */
        final PendingResult pr = goAsync();
        new Thread(() -> {
            android.util.Log.i(TAG, "[cmd] 执行: " + script);
            try {
                RootExec.Result r = RootExec.run(script, 900_000);
                for (String l : r.out.split("\n"))
                    if (!l.trim().isEmpty()) android.util.Log.i(TAG, "[cmd] " + l);
                for (String l : r.err.split("\n"))
                    if (!l.trim().isEmpty()) android.util.Log.i(TAG, "[cmd] ! " + l);
                android.util.Log.i(TAG, "[cmd] 结束 exit=" + r.exit);
            } catch (Throwable t) {
                android.util.Log.i(TAG, "[cmd] 异常: " + t);
            } finally {
                pr.finish();
            }
        }, "cmd-sh").start();
    }
}
