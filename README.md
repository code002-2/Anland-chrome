# Anland-chrome

在 Android 上用 **root + chroot** 跑**官方 Linux 版 Google Chrome**，并且把它做成一个
普通 App：装上 APK、点开图标，就是全屏 Chrome —— Wayland 原生窗口、Android 输入法、
声音走 Android 音频系统。**

底层是 [anland](https://github.com/SuperTurtleDev/anland) 的 `waylandbridge` 守护进程 +
`libawl`：窗口归属靠"本 App 自己创建的 socketpair"来确定，所以 Chrome 明明跑在 chroot 里、
以 root 身份，窗口仍然属于本 App，由本 App 的 `AwlWindowActivity` 全屏托管。



**安装**：下载 Release 里的 `anland-appwrap-release.apk`（约 162 MB，rootfs 已内置），
安装后授予 KernelSU/SukiSU root 权限即可。另外需要先装好 anland 的 KernelSU 模块
（`anland-awl`，提供 wayland 守护进程与 PulseAudio 音频）。

**第一次打开**：会自动解包内置 rootfs（约 500 MB，一分钟左右，界面有进度条），收尾时把
GL 转发壳装成 rootfs 里的系统 `libEGL/libGLESv2`，然后自动启动 GL 转发服务端与
Chrome。之后每次点开 App 都会直接回到 Chrome（已经有窗口就挂载回来，不会重启）。


## 致谢与许可

- [anland](https://github.com/SuperTurtleDev/anland)：守护进程、`libawl`、KernelSU 模块、
  rootfs 思路，本项目的基座。
- Google Chrome 是 Google 的专有软件，**不在本仓库内**；请自行取得并遵守其许可条款。

本项目以 **GPL-3.0** 发布（因为链接/依赖 GPL-3 的 anland 组件，见 `LICENSE`）。
