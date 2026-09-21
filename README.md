# Anland-chrome

在 Android 上用 **root + chroot** 跑**官方 Linux 版 Google Chrome**，并且把它做成一个
普通 App：装上 APK、点开图标，就是全屏 Chrome —— Wayland 原生窗口、Android 输入法、
声音走 Android 音频系统。**不需要 Droidspaces，不需要电脑，不需要 adb。**

底层是 [anland](https://github.com/SuperTurtleDev/anland) 的 `waylandbridge` 守护进程 +
`libawl`：窗口归属靠"本 App 自己创建的 socketpair"来确定，所以 Chrome 明明跑在 chroot 里、
以 root 身份，窗口仍然属于本 App，由本 App 的 `AwlWindowActivity` 全屏托管。

> 当前版本：v0.3（个人自用向，实测机型 REDMAGIC NX809S / Android 16 / Adreno 840）

## 使用者看这里

**安装**：下载 Release 里的 `anland-appwrap-release.apk`（约 162 MB，rootfs 已内置），
安装后授予 KernelSU/SukiSU root 权限即可。另外需要先装好 anland 的 KernelSU 模块
（`anland-awl`，提供 wayland 守护进程与 PulseAudio 音频）。

**第一次打开**：会自动解包内置 rootfs（约 500 MB，一分钟左右，界面有进度条），收尾时把
GL 转发壳装成 rootfs 里的系统 `libEGL/libGLESv2`，然后自动启动 GL 转发服务端与
Chrome。之后每次点开 App 都会直接回到 Chrome（已经有窗口就挂载回来，不会重启）。

**两个性能档**（首页可切换，选完自动重启 Chrome 生效）：

| 档位 | 内容 | 实测 CPU 占用 |
|---|---|---|
| **流畅**（默认） | 0.4 倍渲染 + 关闭 GPU 合成 + 减少动画 + 低端机模式 | ~3%（走 GL 代理后） |
| **原版** | 0.6 倍渲染，动画特效照旧 | ~3%（走 GL 代理后） |

> 这两个档位原来的作用是用降分辨率换 CPU；GL 打通后 CPU 已经不是瓶颈（见下面 GL 转发一节），
> 档位的区别只剩下渲染分辨率与动画效果。

**必须知道的限制**（都是实测结论，不是没做）：

- **不能用 Mesa 直连 GPU**：chroot 里让 Mesa 自己开 `/dev/kgsl`、`/dev/dri` 会把 Android 的
  SurfaceFlinger 打崩（`kgsl` 与 `msm`/freedreno 两条路都试过，三次 SIGABRT → 框架软重启），
  根因是两套用户态驱动抢同一个 GPU。**已改走 GL 转发**（GL 调用转给 Android 自己那套
  EGL/GLES，与 SurfaceFlinger 同一套驱动）—— 真 GPU、且不影响 SF，相关开关已从界面移除。
- **需要 root**：要 `mount`/`chroot`。
- **占用**：解包后约 500 MB，首次启动慢；APK 本身约 162 MB。
- **WebGL 仍可能回落 SwiftShader**，个别站点可能因网络或 DRM 原因播不了视频
  （Widevine L3 在 rootfs 里，但未验证全站可用）。

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

**精简 rootfs**（本项目历次战果：rootfs 2.9 GB → 1.05 GB，xz 591 MB → 247 MB，APK 622 MB → 250 MB；
第三轮再砍到 **499 MB / xz 159 MB / APK ≈ 162 MB**）：
`tools/rf-*.sh` 是一整套流程 —— 克隆一份 → 删掉跟 Chrome 无关的桌面/多媒体/开发栈 → 重新打包。
要点（都是踩过的坑）：

- **用依赖闭包驱动删除，别靠"看名字像不像有用"**。第三轮的做法是：先用 `ldd` 把
  `chrome` + `/opt/google/chrome/*.so` + 启动链上的工具（`env`/`coreutils`/`bash`/`Xwayland`/
  `anland-miniwm`/`pactl`/`tar`/`ldconfig`）以及**只能 dlopen 的目录**
  （`gconv`/`alsa-lib`/`nss`/`gdk-pixbuf-2.0`/`gtk-3.0`）的库名收成白名单（`rf3/keep.txt`），
  删每个文件前查白名单，删完再 `ldd` 复验一遍。
- **白名单要连"符号链接指向的真身"一起保护**：`keep.txt` 里是 `libsqlite3.so.0`，
  真身却是 `libsqlite3.so.0.8.6`；只按名字保护会把真身删掉、留下断链（`rf-prune3b.sh` 里的
  `protect.txt` 就是干这个的）。
- **多调用二进制被删会让整棵 `/usr/bin` 变砖**：`/usr/bin/{env,ls,cat,…}` 全是指向
  `../lib/cargo/bin/coreutils/` 的符号链接，把 `/usr/lib/cargo` 当"开发工具"删掉后
  109 个链接同时断掉，chroot 里连 `/usr/bin/env` 都起不来（`rf-symfix.sh` 把它们重指向同目录的
  `coreutils` 修回来）。
- 判断"空目录"要用 `ls -la`：`/usr/share/X11/xkb` 是**符号链接**，`find -type f` 数出来是 0，
  照它删就会让 xkbcommon 建不出 keymap，Chrome 直接退出。
- `libgcc_s.so.1` / `libstdc++.so.6` 不是开发工具，是**运行时**（`/usr/bin/env` 都链接它）。
- `ldd` 只能看直接依赖闭包，**dlopen 的库看不出来**（pactl 要 libsndfile 就属于这类），
  所以不只是看 `ldd` 干净，还要 `sh`/`env`/`chrome --version` 真跑一遍，最后装机实测。
- 校验清单要包含启动链路：`env`、`coreutils`、`chrome`、`anland-miniwm`、`Xwayland`、`pactl`。
- 压缩在 PC 上用 `tools/xz-pack.py`（Windows 没有 xz.exe，用 Python 自带的 `lzma`，
  `preset 9e` + 64 MB 字典，490 MB 的 tar 约 5 分钟）。

**发布包会关掉远程排障钩子**：`--es sh/shf` 与 `CmdReceiver` 广播只在 debug 构建里生效
（`buildConfigField DEBUG_HOOKS`）。这两个入口能以 root 执行任意命令，绝不能进 release。

## GL 转发（已可用：Chrome 走真 GPU）

**为什么需要它**：chroot 里没法直接用真 GPU —— 让 Mesa 直连（`kgsl` 与 `msm`/freedreno 两条路都试过）
会把 Android 的 SurfaceFlinger 打成 SIGABRT 并软重启，根因是**两套用户态驱动抢同一个 GPU**。
唯一安全的做法是让 GL 调用落到 **Android 自己那套 EGL/GLES**（与 SurfaceFlinger 同一套驱动）：

```
chroot 内 (glibc)                            Android 侧 (bionic, root)
Chrome / ANGLE ─► libEGL.so.1 ─┐
                 libGLESv2.so.2├─► unix socket ─► glproxy-server ─► 真 EGL/GLES (Adreno)
                  (转发壳，本仓库)                   (NDK 编译)
```

**实测结果**：

| 指标 | SwiftShader（原方案） | 经 GL 代理 |
|---|---|---|
| Chrome 总 CPU（bilibili） | DSF 0.4 ≈ 120%，DSF 0.6 ≈ 600% | **≈ 3%** |
| `chrome://gpu` | SwiftShader | **ANGLE OpenGL ES 3.0** |
| 自研 GLES2 测试（三角形） | — | `GL_RENDERER = Adreno (TM) 840`，91,556 帧/秒，每帧 0.011 ms（含 `glFinish` 栅栏） |
| SurfaceFlinger | — | pid 不变、SkImage abort 累计 0、设备 3.3 天未重启 |

默认参数已使用 `--use-angle=gles`（保留 `--enable-unsafe-swiftshader` 作为 WebGL 兜底）。

**实现（代码在 `native/glproxy/`，构建与验证脚本 `tools/glproxy-*.sh`）**：

- **壳**：`libEGL.so.1` / `libGLESv2.so.2`（glibc，导出 296 个符号 = 290 个接口条目 +
  手写的 `eglGetProcAddress` 名字表）。接口表由 `tools/glproxy-gen.py` 从 chroot 里的
  `EGL/egl.h`、`GLES2/gl2.h`、`GLES3/gl3.h` **生成**；暂不支持的条目生成"返回失败"的桩
  （少一个符号会让整个壳加载失败，进而让 Chrome 回落 —— 这个坑踩过一次）。
- **服务端**：`libglproxysrv.so`（NDK 编的 bionic 程序，链接 Android 自己的
  `-lEGL -lGLESv2 -lGLESv3`），随 App 启动（`MainActivity` 准备阶段 `setsid` 起，
  套接字在 `<runtime_dir>/glproxy.sock`）。所以**没有任何 Mesa 参与**，也就不会和 SF 抢驱动。
- **壳的安装位置**：rootfs 解包收尾时写成 `usr/lib/aarch64-linux-gnu/libEGL.so.1.1.0` /
  `libGLESv2.so.2.1.0`，再把短名字 `libEGL.so.1`、`libGLESv2.so.2` 指向它们
  —— **不能靠 `LD_LIBRARY_PATH`**：Chrome 会给子进程清掉它，只能走正常库搜索路径。
- **协议**：无返回值/无出参的调用只写进 256 KB 写缓冲、不等回包（实测 ~0.33 µs/条），
  同步调用才往返（34.8 µs/次）。同理 `glFinish` 这类**栅栏必须走同步**（不然顺序错了会花屏）；
  `glShaderSource` 的字符串数组、`glVertexAttribPointer`/`glDrawElements` 的指针
  （当偏移传）、多出参（`glGetIntegerv` 等，按顺序摆在回包 blob 里）都有专门的编组格式。
  对象名（buffer/texture/program）由客户端自己分配，所以 `glGenBuffers` 之类不必往返。

**已知遗留**：`eglCreateWindowSurface` 目前是失败桩 —— 也就是说 **Chrome 自己那个窗口的呈现
不走代理**（窗口呈现仍由 Wayland/Xwayland 那条路负责，这也是它能和 SF 相安无事的原因之一）；
因此 **WebGL 仍可能回落到 SwiftShader**（`--enable-unsafe-swiftshader` 保留着做兜底）。

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
| `glproxy-verify-chrome.sh` | 装完后验证"Chrome 是否真的在用代理 + 服务端是否在跑" |
| `glproxy-check-chrome.sh` | 看 Chrome 进程的参数与它实际加载的 `libEGL` |
| `glproxy-server-trace.sh` | 抓服务端收到的 op 流（排查花屏/调用缺失）|
| `glproxy-diag-ns.sh` | 比对"App 起的服务端"与"adb 起的服务端"的 env/命名空间（排查 GPU 不可用）|
| `glproxy-retry-test.sh` | 同一个服务端上连跑多次客户端，看是不是"第一次失败、重试就成" |
| `dev-status.sh` | 一屏快照：rootfs / App 版本 / 进程 / 套接字 / GPU 进程参数 |
| `dev-prep-fresh.sh` | 造出"全新安装"现场：停 Chrome、把在用的 rootfs 挪成备份 |
| `xz-pack.py` | PC 侧：把重打包的 rootfs tar 压成 `rootfs.tar.xz`（Python 的 lzma，preset 9e）|
| `rf-prune3.sh` `rf-prune3b.sh` `rf-prune3c.sh` `rf-symfix.sh` `rf-repack3.sh` | rootfs 第三轮精简全流程（白名单驱动删除 / 扫尾 / 修断链 / 重打包）|
| `gl-probe.sh` | 探测 chroot 里各 GL 后端的可用性（**会碰真 GPU，有软重启风险**）|

## 致谢与许可

- [anland](https://github.com/SuperTurtleDev/anland)：守护进程、`libawl`、KernelSU 模块、
  rootfs 思路，本项目的基座。
- Google Chrome 是 Google 的专有软件，**不在本仓库内**；请自行取得并遵守其许可条款。

本项目以 **GPL-3.0** 发布（因为链接/依赖 GPL-3 的 anland 组件，见 `LICENSE`）。
