# Anland-chrome

在 Android 上用 **root + chroot** 跑**官方 Linux 版 Google Chrome**，并且把它做成一个
普通 App：装上 APK、点开图标，就是全屏 Chrome —— Wayland 原生窗口、Android 输入法、
声音走 Android 音频系统。**不需要 Droidspaces，不需要电脑，不需要 adb。**

底层是 [anland](https://github.com/SuperTurtleDev/anland) 的 `waylandbridge` 守护进程 +
`libawl`：窗口归属靠"本 App 自己创建的 socketpair"来确定，所以 Chrome 明明跑在 chroot 里、
以 root 身份，窗口仍然属于本 App，由本 App 的 `AwlWindowActivity` 全屏托管。

> 当前版本：v0.1（个人自用向，实测机型 REDMAGIC NX809J / Android 16 / Adreno 840）

## 使用者看这里

**安装**：下载 Release 里的 `anland-appwrap-release.apk`（约 620 MB，rootfs 已内置），
安装后授予 KernelSU/SukiSU root 权限即可。另外需要先装好 anland 的 KernelSU 模块
（`anland-awl`，提供 wayland 守护进程与 PulseAudio 音频）。

**第一次打开**：会自动解包内置 rootfs（约 2.3 GB，几分钟，界面有进度条），装完自动启动
Chrome。之后每次点开 App 都会直接回到 Chrome（已经有窗口就挂载回来，不会重启）。

**两个性能档**（首页可切换，选完自动重启 Chrome 生效）：

| 档位 | 内容 | 实测 CPU 占用 |
|---|---|---|
| **流畅**（默认） | 0.4 倍渲染 + 关闭 GPU 合成 + 减少动画 + 低端机模式 | ~120% |
| **原版** | 0.6 倍渲染，动画特效照旧 | ~600% |

**必须知道的限制**（都是实测结论，不是没做）：

- **不能用真 GPU**。chroot 里让 Mesa 直连 GPU 会把 Android 的 SurfaceFlinger 打崩
  （`kgsl` 与 `msm`/freedreno 两条路都试过，三次 SIGABRT → 框架软重启），所以渲染是
  纯 CPU（Chrome 自带的 SwiftShader），靠降分辨率换流畅。唯一安全的方向是 GL 代理
  （让 GL 调用落到 Android 自己那套 EGL/GLES），尚未实现。
- **需要 root**：要 `mount`/`chroot`。
- **占用大**：解包后 2.3 GB，首次启动慢；APK 本身 620 MB。
- 个别站点可能因网络或 DRM 原因播不了视频（Widevine L3 在 rootfs 里，但未验证全站可用）。

## 构建者看这里

工具链：AGP 9.4.0 / Gradle 9.6 / JDK 17 / compileSdk 36 / minSdk=targetSdk=29。

```powershell
# 1) 依赖：libawl 的 AAR（本仓库已带 libs/anland-awllib.aar，来自 anland 的构建产物）
# 2) rootfs：本仓库**不包含** src/main/assets/rootfs.tar.xz（620MB，且内含 Google Chrome，
#    版权上不适合进 git）。自行准备一个 aarch64 glibc rootfs（内含 /opt/google/chrome/chrome），
#    xz 压好后放到 src/main/assets/rootfs.tar.xz。
# 3) 签名：build.ps1 会在缺失时生成 debug.keystore（口令 anland/anland，别名 anland）。
.\build.ps1              # = assembleRelease
```

改了 `native/awlrelay.c`（wayland 中继）之后要重新编译它：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\ndk\27.0.12077973\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android29-clang.cmd" `
  -O2 -Wall -fPIE -pie -pthread `
  -o src\main\jniLibs\arm64-v8a\libawlrelay.so native\awlrelay.c
```

**发布包会关掉远程排障钩子**：`--es sh/shf` 与 `CmdReceiver` 广播只在 debug 构建里生效
（`buildConfigField DEBUG_HOOKS`）。这两个入口能以 root 执行任意命令，绝不能进 release。

## 排障脚本（`tools/`）

设备侧一次性脚本，配合广播钩子（debug 包）使用：

```powershell
adb shell am broadcast -n com.anland.appwrap/.CmdReceiver -a com.anland.appwrap.CMD `
    --es shf /data/local/tmp/perf.sh
```

| 脚本 | 用途 |
|---|---|
| `perf.sh` | Chrome 各进程 CPU + 稳定性 + 当前生效的渲染参数 |
| `state.sh` | 一屏看清守护进程/Chrome/中继/音频 sink 状态 |
| `diag.sh` | 窗口与进程全景（排查"画面冻住"用）|
| `relay-now.sh` | 帧是否还在流（中继 8 秒消息增量）|
| `set-fullscreen.sh` | 按 `wm size` 写守护进程 `init_w/init_h`，让窗口占满屏幕 |
| `daemon-dedupe.sh` | 收掉重复的 `waylandbridge` 进程 |
| `restart-pa.sh` | 按模块 `service.sh` 的方式重启 PulseAudio（修"没声音"）|
| `fix-coreutils.sh` | 修复被写坏的 coreutils 多调用二进制 |
| `run-chrome.sh` | 不经 App 直接重启 chroot 里的 Chrome（换 GL 后端做 A/B）|
| `gl-probe.sh` | 探测 chroot 里各 GL 后端的可用性（**会碰真 GPU，有软重启风险**）|

## 致谢与许可

- [anland](https://github.com/SuperTurtleDev/anland)：守护进程、`libawl`、KernelSU 模块、
  rootfs 思路，本项目的基座。
- Google Chrome 是 Google 的专有软件，**不在本仓库内**；请自行取得并遵守其许可条款。

本项目以 **GPL-3.0** 发布（因为链接/依赖 GPL-3 的 anland 组件，见 `LICENSE`）。
