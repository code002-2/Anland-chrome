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
安装后授予 KernelSU/SukiSU root 权限即可。

**第一次打开**：会自动解包内置 rootfs（约 2.3 GB，几分钟，界面有进度条），装完自动启动
Chrome。之后每次点开 App 都会直接回到 Chrome（已经有窗口就挂载回来，不会重启）。

**两个性能档**（首页可切换，选完自动重启 Chrome 生效）：

| 档位 | 内容 | 实测 CPU 占用 |
|---|---|---|
| **流畅**（默认） | 0.4 倍渲染 + 关闭 GPU 合成 + 减少动画 + 低端机模式 | ~120% |
| **原版** | 0.6 倍渲染，动画特效照旧 | ~600% |

**必须知道的限制**（都是实测结论，不是没做）：

- **不能用真 GPU**。chroot 里让 Mesa 直连 GPU 会让 Android 的 SurfaceFlinger 崩掉
  （`kgsl` 与 `msm`/freedreno 两条路都试过，三次 SIGABRT → 框架软重启），所以渲染是
  纯 CPU（Chrome 自带的 SwiftShader），靠降分辨率换流畅。唯一安全的方向是 GL 代理
  （让 GL 调用落到 Android 自己那套 EGL/GLES），尚未实现。
- **需要 root**：要 `mount`/`chroot`。
- **占用大**：解包后 2.3 GB，首次启动慢。
- 个别站点可能因网络/DRM 原因播不了视频（Widevine L3 在 rootfs 里，但未验证全站可用）。

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

中继（`libawlrelay.so`）需要 NDK 重新编译时见文末「重新编译中继」。

**发布包会关掉远程排障钩子**：`--es sh/shf` 与 `CmdReceiver` 广播只在 debug 构建里生效
（`buildConfigField DEBUG_HOOKS`）。这两个入口能以 root 执行任意命令，绝不能进 release。

## 致谢与许可

- [anland](https://github.com/SuperTurtleDev/anland)：守护进程、`libawl`、KernelSU 模块、
  rootfs 思路，本项目的基座。
- Google Chrome 是 Google 的专有软件，**不在本仓库内**；请自行取得并遵守其许可条款。

本项目以 **GPL-3.0** 发布（因为链接/依赖 GPL-3 的 anland 组件，见 `LICENSE`）。

---

# 工程笔记

以下是开发过程中踩过的坑与实测数据，留档用。

## anland-appwrap —— 把 Linux Chrome 打成独立 APK

一句话：**APK 里内置一份 Ubuntu-26 glibc rootfs（已含 Chrome）+ anland 客户端库**，
装上、解包、点启动就能用；**不依赖 Droidspaces、不需要联网**。窗口由 anland 守护进程
渲染，宿主就是本 APK 自己的 `AwlWindowActivity`。

```
APK(≈620MB)
├─ assets/rootfs.tar.xz        Ubuntu-26 aarch64 rootfs（2.29GB 解包，内含 google-chrome 153.0.8010.47）
├─ libs/anland-awllib.aar      libawl：拿 wayland 连接 + 窗口托管（AwlWindowActivity）
└─ Java 控制台                  首次解包 / 启动 / 停止 / 清理 / 自检

运行链路（全程 root，但**不碰 droidspaces**）：
  Awl.getWaylandFd()  →  socketpair 在**本进程**创建，一端交给守护进程 binder 服务 anland.host
        │                 （SO_PEERCRED 在创建时固定 = 本 App uid，之后谁持有 fd 都改不了）
        ▼
  Awl.spawnClient(fd, /system/bin/su, -c, <chroot 脚本>)   ← fd 经 su → chroot → Chrome 继承
        │
        ▼
  mount -t proc/sysfs + --bind /dev + tmpfs /dev/shm   →  chroot rootfs
        │
        ▼
  /usr/bin/env -i … WAYLAND_SOCKET=<fd> /opt/google/chrome/chrome --no-sandbox --ozone-platform=wayland
        │
        ▼
  Chrome 建 xdg_toplevel → 守护进程认为客户端是**本 App** → 本 App 收到事件
        │
        ▼
  Awl.attachWindow → AwlWindowActivity 把 Surface 交给守护进程 → 画面出现在本 App 的窗口里
```

## 一、必须先接受的硬事实

1. **这份 `google-chrome-stable_153.0.8010.36-1_arm64.deb` 是 glibc/Debian 二进制**
   （`Depends: libc6 (>= 2.25)`，Chrome 本体 286MB，依赖 GTK3/NSS/GBM/Vulkan/X11 全家桶）。
   Android 的 libc 是 bionic，内核里没有 glibc 兼容层 —— **必须自带一个 glibc 用户态**。
   这不是配置问题，"完全不要 Linux 环境"物理上不成立。
2. 所以本方案 = **自带 rootfs + root + chroot**：省掉 Droidspaces，但没有省掉"用户态 Linux"。
3. **需要 root**（KernelSU/SukiSU 给本 App 授权），因为要 `mount`/`chroot`。
   窗口链路本身不需要 root，是 chroot 需要。
4. **体积**：APK ≈620MB；解包后 **2.29GB**（58450 个文件 + 29817 个符号链接），
   目标分区要留 **≥2.6GB**。
5. **性能**：先跑通优先。默认参数走软件渲染（`--disable-gpu`），Chrome 在 chroot 里
   还要 `--no-sandbox`。这份 rootfs 里带了 Mesa 26 + libgallium + LLVM，所以**理论上**
   能走 kgsl 硬件路径（界面上的「kgsl 硬件渲染」开关就是给它准备的），但先软后硬。

## 二、你那份 .deb 的处置

rootfs 里的 Chrome 是 **153.0.8010.47-1**，你给的 deb 是 **153.0.8010.36-1**
（同一大版本、**旧 11 个补丁位**），所以默认**不装你那份**——rootfs 里已经是更新的构建。

要固定到你那份版本（比如为了对齐某个测试基线），设备上 root shell 里一条命令即可
（deb 的 payload 只有 `/opt/google/chrome`、`/usr/bin/google-chrome-stable`、
`/usr/share/applications`、`/etc` 四块，直接覆盖解包就行）：

```sh
adb push google-chrome-stable_153.0.8010.36-1_arm64.deb /data/local/tmp/chrome.deb
adb shell su -c 'cd /data/local/tmp && mkdir -p x && cd x && \
  tar -xf ../chrome.deb data.tar.xz 2>/dev/null; \
  tar -xf data.tar.xz -C /data/adb/anland-chrome/root && echo DONE'
# 或者更正规：chroot 进去用 dpkg（rootfs 里有 dpkg/perl）
adb shell su -c 'chroot /data/adb/anland-chrome/root /usr/bin/dpkg -i /tmp/chrome.deb'
```

## 三、前置条件

1. **anland-awl 模块**已刷入且守护进程在跑：`anland.host` binder 服务可用
   （自检里会打印 `binder anland.host: true`）。
2. **`config.json` 里 `auto_attach` 必须是 0（默认值）**：设成 1 时守护进程会对新窗口去
   `am start com.anlandnext/...`（包名硬编码），第三方 App 的窗口就永远等不到宿主。
3. **给本 App 授予 root**（KernelSU 里勾上 `com.anland.appwrap`）。首次点「启动」会触发授权。

## 四、安装与使用

```powershell
.\build.ps1                                       # 产出 build\outputs\apk\release\anland-appwrap-release.apk
adb install -r build\outputs\apk\release\anland-appwrap-release.apk
```

App 里按顺序：

1. **保存**（确认 rootfs 目录 `/data/adb/anland-chrome/root`；空间紧张就改成
   `/data/local/tmp/anland-chrome/root`）
2. **安装 rootfs** —— 解包 620MB→2.29GB，进度条会走；完成后日志里出现
   `rootfs 安装完成 ✓`。这一步只做一次（标记文件 `.appwrap-ok`）。
3. **启动** —— 起 Chrome（Wayland 客户端，fd 继承）。首次会自动挂载窗口。
4. 之后从最近任务切走 = 最小化（守护进程 detach，Chrome 继续跑）；杀掉本 App 的宿主
   Activity 会请求 Chrome 关窗；**停止**按钮 = `pkill` Chrome。

**两台设备之间迁移**：APK 自带 rootfs，装完解包即可，无需下载任何东西。

## 五、为什么必须用继承 fd，而不能让 Chrome 连 socket 文件

守护进程对每个窗口做归属校验：`awl_window_client_uid(id) == 调用方 uid`
（`waylandbridge.cpp` 的 `window_ok` / `SURFACE` 鉴权）。

* 如果让 chroot 里的 Chrome 去连 `/data/local/tmp/awl/wayland-0`，它的凭据是 **root(0)**
  → 本 App（uid 10xxx，不在 allowlist 里）挂载时会被拒，日志里是
  `SURFACE <id>: uid=<our uid> rejected (not the wayland client's uid)`。
* 用 `Awl.getWaylandFd()` 的 socketpair 则不同：**凭据在创建时就被固定**成创建者（本 App）的 uid，
  fd 之后被 su/chroot/Chrome 继承都不改变它 → 窗口仍属于本 App → 挂载成功。
  这正是守护进程注释里那句"the socketpair must be created by the wayland client app itself"。

唯一前提是 **Chrome 不能把这个继承来的 fd 关掉**：libwayland 的 `wl_display_connect(NULL)`
会读 `WAYLAND_SOCKET` 环境变量并接管该 fd，Chromium 的 Ozone/Wayland 正是这么连的。
（设备侧要盯的就是这一条——见排错表第 2 行。）

## 六、Chrome 参数（界面里可直接改）

默认（软件渲染，最稳）：

```
--no-sandbox --no-zygote --ozone-platform=wayland --disable-dev-shm-usage
--disable-gpu --no-first-run --no-default-browser-check
```

设备上按需替换：

| 目标 | 参数 |
|---|---|
| 硬件渲染（这份 rootfs 的 kgsl 路径，**同时勾上界面上的 kgsl 开关**） | 去掉 `--disable-gpu`，加 `--use-gl=angle --use-angle=gles` |
| 只走软件 GL（llvmpipe） | `--use-gl=angle --use-angle=swiftshader` |
| 窗口尺寸/缩放异常 | `--force-device-scale-factor=1` |
| 排查启动即退 | 加 `--enable-logging=stderr --v=1`（日志会进本 App 的日志区） |

`kgsl` 开关会额外注入（照抄 anland 的约定）：
`MESA_LOADER_DRIVER_OVERRIDE=kgsl GALLIUM_DRIVER=kgsl FD_FORCE_KGSL=1 LIBGL_ALWAYS_SOFTWARE=0`。

## 七、排错表

| 现象 | 原因 / 处理 |
|---|---|
| 自检 `binder anland.host: false` | 模块没装或守护进程没起来 |
| 日志 `appwrap: WAYLAND_SOCKET 没有继承到 su 子进程` | `su` 清了环境；换 KernelSU 的 `su`，或把 fd 号显式写进脚本 |
| Chrome 起来但连不上 Wayland（`Failed to connect to Wayland display`） | 继承的 fd 被 Chrome 关掉了 → 试 `--ozone-platform=wayland` 与去掉 `--no-zygote`；仍不行就在日志里看它到底读没读到 `WAYLAND_SOCKET` |
| Chrome 跑起来、没有窗口 | 看守护进程侧日志：`SURFACE … rejected` = 凭据不是本 App；`no such window` = id 过期 |
| 挂载瞬间自我结束 | 同上：`AwlClient.surface` 返回 -1 时 AwlWindowActivity 直接 finish（不留占位） |
| `mount: Permission denied` | su 域被 SELinux 拦了 mount（部分 ROM）→ 给模块 sepolicy 加 `allow su self:capability sys_admin;` 之类，或用 KernelSU 的 permissive 域 |
| 解包失败 / `tar: unknown option` | 界面勾上「两步解包」重试（先落 2.3GB 的 .tar 再解，绕开 `tar -f -` 管道） |
| 空间不足 | 换 rootfs 目录；解包需要 ≥2.6GB 空闲 |
| 窗口黑屏但 Chrome 在跑 | 软件渲染出来了但合成失败 → 试 `--disable-gpu` 与 `--use-angle=swiftshader` 组合，或反过来开 kgsl |
| 切回本 App 后 Chrome 画面不动 | 正常：pre-Q（targetSdk 29）下一个进程只能有一个 RESUMED Activity，宿主 Activity 暂停 → 守护进程 detach（= 最小化语义） |

## 八、本机已验证 / 待设备验证

**已验证（PC 侧）**

| 项 | 结果 |
|---|---|
| rootfs 内容 | `google-chrome 153.0.8010.47-1` 已安装；CTK3/NSS/GBM/Vulkan/ALSA/CUPS/ATK/AT-SPI/xkbcommon/Wayland/X11/Pango/Cairo/epoxy/DRM/curl/pulse/zstd/snappy 全部齐备；`dpkg`/`perl`/`openssl`/`Xwayland` 在位；244 个 CA 证书；字体 32 个文件 |
| 缺失项（首启补） | `/dev/shm`、`/etc/resolv.conf`、`/etc/hosts`、`ldconfig` 缓存 —— 见 `Rootfs.fixups()` |
| 体积 | xz 619,869,008 B（0.58GB）→ 解包 2.29GB（58450 文件 / 29817 符号链接） |
| manifest 合并 | `com.anlandnext.awl.AwlWindowActivity` 自动 merge（`exported=false`、`launchMode=standard`、`documentLaunchMode=intoExisting`、可缩放属性） |
| 签名 | v2/v3，`CN=AppWrap Debug` |
| 容器脚本逻辑 | `tools/test-container-script.sh` 逐字节回归通过（引号/`$`/`#`/中文穿越 su→sh→进程，`@FD@` 只在外层替换） |

**设备侧已实测通过（2026-09-17，真机 KernelSU）**

| 环节 | 结果 / 证据 |
|---|---|
| rootfs 解包 | `su -c tar -xf -` 收下 Java 解出的 tar 流，2.29GB 落地；`Chrome 286,199,176 B`、可执行位正确 |
| root 域 | `uid=0 context=u:r:ksu:s0`；`mount -t proc` / `mount --bind` / `chroot` 全部放行 |
| fd 继承 | 启动脚本打印 `WAYLAND_SOCKET=172 -> socket:[202412]` ⇒ socketpair 的 fd 穿过 su 仍然有效 |
| Chrome in chroot | `Read channel stable from /opt/google/chrome/CHROME_VERSION_EXTRA` + 已经在发网络请求 ⇒ glibc/加载器/GTK3/NSS 等依赖齐全 |
| Xwayland | `X0 就绪` + Xwayland 用继承的 fd 连上守护进程（**X11 后端**可用，但没有 IME） |
| **最终可用形态** | **`wayland(relay)` 后端**：Chrome 走 anland 的 Wayland 协议、窗口归属本 App、**Android 键盘可用** ✓（2026-09-17 实测通过） |

## 八之二、最终可用配置：`wayland(relay)`

```
Awl.getWaylandFd() ×3   三条 socketpair 都在 App 进程创建（SO_PEERCRED 固定成本 App uid）
      ↓ dup + 清 CLOEXEC（ParcelFileDescriptor 保活），fd 号经 fork 传给中继
libawlrelay.so --listen <rootfs>/tmp/wayland-0 --upstream <fd1> --upstream <fd2> --upstream <fd3>
      ↓ 单线程 poll 多路复用，按 recvmsg 结果原样转发（字节 + SCM_RIGHTS 一起）
Chrome（chroot 内）用 WAYLAND_DISPLAY=/tmp/wayland-0 连过来
      ↓ Chrome 是正经 Wayland 客户端 → 绑定 zwp_text_input_v3
守护进程 ime_show → AwlWindowActivity 弹软键盘 → 键字经 text-input 回到 Chrome ✓
```

为什么非要中继（两个约束同时成立才需要它）：

1. Chrome 不能用 `WAYLAND_SOCKET`：`libwayland` 读到该变量后 `unsetenv`，而 Chromium 初始化 Ozone 前会**先探测一次** Wayland，那一探把变量吃掉，真正的连接回退去连套接字文件 → `Failed to create wl_display (No such file or directory)`（ENOENT 而非 EBADF，因为根本没走 fd 那条路）。所以要给它一条**路径**。
2. Chrome 也不能直接连守护进程的套接字：那样客户端凭据是 root，而 `SURFACE` 鉴权是 uid 比对（第三方 App 只放行 root/自 uid），窗口就不属于本 App 了。所以凭据必须是"我们创建的 socketpair"。
→ 中继同时满足：**路径给 Chrome，凭据是我们的**。

三个必须记住的实现细节（都踩过）：

| 坑 | 现象 | 修法 |
|---|---|---|
| Chromium 不只开一条 Wayland 连接（浏览器 + GPU 进程） | 只服务一条时第二条烂在 listen backlog → GPU 初始化不了 → **没有窗口** | 中继支持多条上游 + poll 多路复用；App 侧 `getWaylandFd()` 三次，重复 `--upstream` |
| `ParcelFileDescriptor.dup()` **默认带 CLOEXEC** | 中继报 `上游 fd N 无效（Bad file descriptor）` 后退出 | `Os.fcntlInt(F_GETFD/F_SETFD)` 清掉 `FD_CLOEXEC`，并保活 PFD（被 GC 会关 fd） |
| 就绪检查只看套接字文件 | 上一轮残留的套接字造成**假阳性**，"就绪"了但中继早死了 | 起中继前先 `rm -f` 残留；就绪判据 = 文件存在 **且** `pgrep libawlrelay.so` 活着 |

**X11 后端（`x11(Xwayland)`）保留为对照**：它也能出画面，但 rootless Xwayland 只有在 WM 调了 `XCompositeRedirectWindow(Manual)` 之后才会 surface 窗口（见 `anland-session/miniwm.c` 头部注释），所以要额外跑 `anland-miniwm`；且 X11 应用拿 IME 走 XIM，**Android 键盘进不来** —— 这正是最终选 Wayland 的原因。

**踩过的自杀 bug（写脚本时警惕）**：`pkill -f <模式>` 会匹配**整条命令行**，而我们的脚本本身就是 `sh -c '<脚本文本>'`，
文本里含 `Xwayland` / `chrome` 这些词 → pkill 把运行脚本的 shell 自己杀了（表现为日志在中间**静默中断**）。
现在一律用 PID 文件精确 kill，`停止` 用**按进程名**的 `pkill chrome` / `pkill Xwayland` / `pkill anland-miniwm` / `pkill libawlrelay.so`（不带 `-f`）。

## 九、编译（本机环境）

前置：**JDK 17**、Android SDK（platform 36 + build-tools 36.1.0）、网络（首次下 Gradle 9.6 / AGP 9.4.0）。
**不需要 NDK**。

```powershell
.\build.ps1     # JAVA_HOME 默认 C:\Program Files\Java\jdk-17，ANDROID_HOME 默认 %LOCALAPPDATA%\Android\Sdk
```

踩过的坑（已处理）：AGP 对 compileSdk 36 默认要 `build-tools;36.0.0`（本机只有 36.1.0/37.0.0，
已在 `build.gradle` 钉住）；`platforms;android-36` 用 `sdkmanager` 手工装（AGP 自带下载会卡）；
本机直连 `repo.maven.apache.org` 403，`settings.gradle` 里已把阿里云镜像排在前面；
`rootfs.tar.xz` 用同盘**硬链接**挂进 `src/main/assets/`，不额外占磁盘。

## 十、目录

```
awlwrap/
├─ build.gradle / settings.gradle        AGP 9.4.0, minSdk/targetSdk 29, noCompress(xz,tar), org.tukaani:xz
├─ build.ps1                             一键编译
├─ libs/anland-awllib.aar                libawl（flatDir 引入）
├─ native/awlrelay.c                     ★ wayland 中继源码（NDK 交叉编译 → jniLibs/arm64-v8a/libawlrelay.so）
├─ src/main/jniLibs/arm64-v8a/            libawlrelay.so（中继）+ libawlspawn.so（libawl 带的）
├─ src/main/assets/rootfs.tar.xz         ← 硬链接到你的 rootfs 包（620MB）
├─ src/main/java/com/anland/appwrap/
│   ├─ MainActivity.java                 控制台：安装/启动/停止/清理/自检/窗口（整页可滚 + 高级项折叠）
│   ├─ Rootfs.java                       首次解包（Java 解 xz → root 侧 tar 流）+ 收尾
│   ├─ RootExec.java                     su 命令执行（含 stdin 流式写入）
│   ├─ Launcher.java                     四种画面后端的脚本拼装（relay / X11 / fd / 套接字）
│   └─ AppCfg.java                       配置（display 默认 3 = wayland(relay)）
├─ tools/check-fd-handoff.sh             fd 继承前置验证（容器路线）
├─ tools/test-container-script.sh        容器脚本逻辑回归（已通过）
└─ reference/upstream-testapp/           上游被删掉的第三方示例 App（git 8ef536d^ 取回）
```

**重新编译中继**（改了 `native/awlrelay.c` 之后）：

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\ndk\27.0.12077973\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android29-clang.cmd" `
  -O2 -Wall -fPIE -pie native\awlrelay.c -o src\main\jniLibs\arm64-v8a\libawlrelay.so
```

其余三条路线（`容器` = droidspaces、`原生` = APK 自带 bionic 二进制、`仅宿主`）仍保留在界面里，
用于非 glibc-only 的场景。

---

## 2026-09-17 实测结论（真机 REDMAGIC NX809J / Android 16 / Adreno 840）

### 1. GPU：**两条真 GPU 路线都被否掉了**（会打死 SurfaceFlinger）

| 路线 | 结果 |
|---|---|
| 无（SwiftShader/llvmpipe，默认） | ✅ 稳定，纯 CPU 光栅化 —— 1216×2688 下很吃力，这是"卡"的物理上限 |
| `MESA_LOADER_DRIVER_OVERRIDE=kgsl` | ❌ SurfaceFlinger SIGABRT → 框架软重启 |
| `MESA_LOADER_DRIVER_OVERRIDE=msm`（freedreno / `/dev/dri/renderD128`） | ❌ 同样 SIGABRT |

msm 那条**看着非常像成功**——`eglinfo` 在 GBM 平台报 `freedreno / Adreno (TM) 840 /
OpenGL ES 3.2 Mesa 26.3.0`，`es2_info` 也能跑，SurfaceFlinger 当时还活着。但 Chrome 一
开始真正渲染就崩，三次 abort 全在同一处：

```
Abort message: 'Unable to generate SkImage. isTextureValid:1 dataspace:... GrGLTextureInfo: success: 1 fTarget: 36197'
  #03 GaneshBackendTexture::logFatalTexture  /system/bin/surfaceflinger
```

根因不是"驱动选错了"，而是**同一个 GPU 上并存两套用户态驱动**：Android 显示栈用
kgsl/Adreno 驱动，chroot 里的 Mesa 另起一套提交，GPU 一 hang/复位就把 SurfaceFlinger 的
GL 上下文打废。所以：
- **不要**用 `env` 字段或 kgsl 勾选框开真 GPU（代码里已把这段教训写进 AppCfg 注释）；
- 唯一安全的方向是 **GL 代理**：GL 调用走 Android 自己那套 EGL/GLES（由守护进程代跑），
  不引入第二套驱动。这是个大工程（EGL/GLES over IPC + dma-buf 共享），分阶段做。

### 2. 到处踩过的坑（都已修）

- **没有全屏**：守护进程 `config.json` 缺省是 `init_w=800 / init_h=600`（#33 占位值），
  它给新窗口的 initial configure 就是 800×600 —— 得写成本机物理分辨率（1216×2688）。
  `tools/set-fullscreen.sh` 用 `wm size` 自动取。
- **没有声音**：PA 是在框架软重启刚结束时启动的，音频服务还没就绪 →
  `module-sles-sink.c: Failed to initialize OpenSL ES: error 9`（= DEVICE_UNAVAILABLE）→
  `module-always-sink` 顶上 `auto_null`，声音进黑洞。App 现在**每次启动前先查 sink**
  （`Launcher.pulseEnsureScript`），坏了就照 `module/service.sh` 的方式把 PA 重起一遍
  （以 `com.anlandnext` 的 uid 起，sles 不行自动换 AAudio）。
- **视频播不了**：Chrome 已拒绝"自动回退到软件 WebGL"，缺 `--enable-unsafe-swiftshader`
  时 `getContext('webgl')` 直接返回 null，B 站播放器初始化失败。默认参数里已带上。
- **持续卡死**：中继原先是**单线程 poll + 阻塞 sendmsg** —— 一个方向写不进去（对端读得慢）
  就把所有连接一起卡住，实测 Chrome 合成器：
  `CompositorAnimationObserver is active for too long (71.65s)`。现在改成**每条连接一对
  独立线程**（两个方向各一个），已无该报错。
- **中继逐条日志**：每条 Wayland 消息都写 stderr → App 镜像进日志框（64KB TextView 反复
  setText）+ logcat，每秒几十 MB 分配。默认关闭（`--verbose` 才开），UI 刷新也做了 250ms 节流。
- **adb 下发的参数不生效**：`handleIntentExtras` 改的是 cfg，但 `launch()` 里的 `saveCfg()`
  拿界面控件文本反覆盖 cfg，控件没回填 → 下发值被丢回旧值。加 `syncUiFromCfg()` 修掉。
- **`selectedDisp()` 兜底是 X11**：单选组状态异常时会把 `display=0` 写进配置 → 莫名其妙按
  X11 启动（窗口标题直接是 `Xwayland`）。兜底改成 relay，并新增 `--ei disp/mode` 直接指定。
- **重启后守护进程不回来**：`launch()` 发现 `Awl.available()==false` 会用 root 从模块目录
  `setsid ./waylandbridge` 拉起来（模块目录里那个二进制从 `adb shell su` 执行会
  "inaccessible or not found"，但**从 App 的 su 子进程里可以执行**）。

### 3. 「刚进去就卡死，但声音正常」= 守护进程的 SurfaceControl 连接发霉了

最迷惑的一次故障。症状四件套：

1. 窗口正常出现、也挂载上了（binder 侧全部成功）
2. **中继 8 秒消息增量 = 0**（没有任何帧在流）
3. 触摸毫无反应（输入要经守护进程转发）
4. **音频完全正常**（音频走 `pulse.sock`，不经过守护进程）

根因：守护进程用 SurfaceControl/HWC 把画面交给 SurfaceFlinger。SF 一旦重启
（本文档第 1 节那三次 SIGABRT → framework 软重启就是），守护进程手里那条 SC 连接
就废了 —— 它**不报错**，只是一直等不到帧。判据很硬：

```
/proc/<pid>/stat 第 22 个字段 = 进程启动时刻（jiffies since boot）
SF 的启动时刻 > 守护进程的  →  守护进程是旧世界的人，必须重启
```

实测：`sf=375986 > daemon=388` → 重启守护进程后立刻恢复。

已做进 App（自愈，不用人判断）：`Launcher.daemonHealthScript()` /
`restartDaemonScript()`，在每次启动的 prepare 阶段检查；`autoFlow()` 里若发现过期
就**不再挂载旧窗口**（挂上去只会得到一张冻住的画面），而是强制重启 Chrome。
之前"窗口出来了但卡死"的另一半原因也在这里：旧窗口的客户端已经被
`cleanupScript` 杀掉，屏幕上留着的就是那张死画面，而新 Chrome 在后台出声。



### 4. 远程排障通道（广播钩子）

`am start --es shf` 会被 Activity 栈挡住（栈顶常是挂窗口的 AwlWindowActivity，
只会把 task 提到前台，intent 进不了 `onNewIntent`）。改用广播：

```powershell
# 注意 1：显式指定组件（隐式广播会被 Android 8+ 的后台限制拦掉）
# 注意 2：App 被 force-stop 后处于 stopped 状态，要 -f 0x00000020 才叫得醒
adb shell am broadcast -n com.anland.appwrap/.CmdReceiver -a com.anland.appwrap.CMD `
    -f 0x00000020 --es shf /data/local/tmp/set-fullscreen.sh
```

命令必须由 **App 的 su 子进程**执行：`/data/adb` 下的 rootfs 只有它的 mount namespace /
上下文才写得动、才看得见 bind mount（`adb shell su` 去写常常 Permission denied）。
它也能顺手改配置：`--es env "K=V"`、`--es args "..."`、`--es url "..."`、`--ez kgsl false`。
⚠ 这个接收器是 `exported` 的，等于把 root 命令执行权交给任何 App，**发布版要删掉**。

### 5. 事故记录：coreutils 被打坏又救回

`/usr/bin/env` → `../lib/cargo/bin/coreutils/env` 是符号链接，而 `/usr/lib/cargo/bin/coreutils/`
下 115 个 applet 全是**硬链接**，共享 `/usr/bin/coreutils` 那一个 inode。当时用
`cat > /usr/bin/env` 写 wrapper，直接把共享 inode 覆盖成 227 字节的脚本 → 115 个 applet 全废
（Chrome 启动命令第一段就是 `env -i`）。
硬链接没法单独恢复，只能把真身重新灌进同一 inode：
PC 侧 `tar -xJf rootfs.tar.xz ./usr/bin/coreutils`（10,577,824 B）→ push 到设备 →
由 **App 的钩子** `cp -f` 覆盖（inode 不变，115 个硬链接一起复活）。
`tools/fix-coreutils.sh` 就是这段修复脚本。

