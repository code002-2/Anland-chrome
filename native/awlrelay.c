/* awlrelay.c — 把「unix 套接字上的 wayland 客户端」桥接到「我们持有的 wayland 连接」
 *
 * 为什么需要它：
 *   libwayland 的 wl_display_connect() 读到 WAYLAND_SOCKET 后会 unsetenv 掉它，而
 *   Chromium 在初始化 Ozone 之前会先探测一次 Wayland —— 那一探把变量消费掉，真正的
 *   连接就回退去连套接字文件（结果 ENOENT）。所以 Chrome 需要一条 **路径** 去连。
 *   但直接让 Chrome 连守护进程的套接字又会把客户端凭据变成 root，窗口就不再属于
 *   我们的 APK（SURFACE 鉴权是 uid 比对）。
 *
 *   本中继同时解决这两点：它继承 socketpair 端（libawl 在 App 进程里创建，SO_PEERCRED
 *   在创建时就固定成 App 的 uid —— 谁持有都改不了），另外在路径上 listen 让 chroot 里的
 *   Chrome 以普通 Wayland 客户端连过来。于是 Chrome 能拿到 zwp_text_input_v3（Android
 *   输入法），而守护进程看到的客户端 uid 仍然是 App 的。
 *
 * 为什么要**多条**上游：
 *   Chromium 不只开一条 Wayland 连接 —— 浏览器进程一条，GPU 进程往往自己再连一条
 *   （它不总能复用浏览器传过去的 fd）。如果中继只服务一条，第二条会烂在 listen backlog
 *   里，GPU 初始化不了，UI 就永远不建窗口（表现为"没有窗口可挂载"）。所以：
 *   App 侧多要几条连接（Awl.getWaylandFd() 各一次），经 --upstream 传进来，
 *   中继用**轮询多路复用**并发地把每个客户端桥到各自的上游。
 *
 * 用法：
 *   libawlrelay.so --listen /path/to/wayland-0 [--upstream FD]... [--verbose]
 *   --upstream 可重复；一个都不给时取环境变量 WAYLAND_SOCKET（libawl 的 spawnClient 设置）。
 *
 * 转发语义：
 *   wayland 的 fd（wl_shm pool、dma-buf）随消息用 SCM_RIGHTS 传，libwayland 发送时是
 *   「一次 sendmsg 携带一批消息 + 该批的 fd」。所以按 recvmsg 的结果**原样转发**
 *   （字节 + 控制数据一起）等价于保持发送方的分批，接收侧按序消费 fd 不会错位；
 *   绝不能按固定块大小切完字节再补 fd，那会把 fd 挂到错的消息上。
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define AWL_BUF 65536
#define AWL_MAX_FDS 28
#define AWL_MAX_UP 8

static int g_verbose;

struct pair {
    int client;         /* -1 = 空槽 */
    int up;
    long long bytes_up, bytes_down, fds_up, fds_down;
};

static struct pair g_pairs[AWL_MAX_UP];   /* 旧 poll 版本遗留（保留结构体定义，逻辑已不用） */
static int g_up_busy[AWL_MAX_UP];         /* 上游占用标记（accept 线程写、转发线程清） */
static int g_up_of[AWL_MAX_UP];           /* 校验后有效的上游 fd 表 */
static int g_nup;                    /* 上游 fd 数 */
static int g_up[AWL_MAX_UP];
static long long g_total_bytes, g_total_fds;

static void log_line(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("awlrelay: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    fflush(stderr);
    va_end(ap);
}

static int fd_count(struct msghdr *m) {
    int n = 0;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(m); c; c = CMSG_NXTHDR(m, c))
        if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS)
            n += (int)((c->cmsg_len - CMSG_LEN(0)) / sizeof(int));
    return n;
}

static void close_cmsg_fds(struct msghdr *m) {
    for (struct cmsghdr *c = CMSG_FIRSTHDR(m); c; c = CMSG_NXTHDR(m, c))
        if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS) {
            int n = (int)((c->cmsg_len - CMSG_LEN(0)) / sizeof(int));
            int *fds = (int *)CMSG_DATA(c);
            for (int i = 0; i < n; i++)
                if (fds[i] >= 0) close(fds[i]);
        }
}

/* 从 from 读一次（含控制数据）原样写到 to。
 * 返回 >0 = 转发字节数；0 = 暂时没数据；-1 = 对端关闭/出错。 */
static ssize_t relay_once(int from, int to, const char *tag, long long *nb, long long *nf) {
    char buf[AWL_BUF];
    char cbuf[CMSG_SPACE(sizeof(int) * AWL_MAX_FDS)];
    struct iovec iov;
    struct msghdr in;
    ssize_t n;

    memset(&in, 0, sizeof in);
    memset(&cbuf, 0, sizeof cbuf);
    iov.iov_base = buf;
    iov.iov_len = sizeof buf;
    in.msg_iov = &iov;
    in.msg_iovlen = 1;
    in.msg_control = cbuf;
    in.msg_controllen = sizeof cbuf;

    n = recvmsg(from, &in, MSG_CMSG_CLOEXEC);
    if (n < 0) {
        if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) return 0;
        log_line("%s recvmsg: %s", tag, strerror(errno));
        return -1;
    }
    if (n == 0) return -1;                       /* EOF */

    int nfd = fd_count(&in);
    if (nb) *nb += n;
    if (nf) *nf += nfd;
    g_total_bytes += n;
    g_total_fds += nfd;
    if (g_verbose)
        log_line("%s %zd 字节%s", tag, n, nfd ? "（带 fd）" : "");

    {
        struct iovec oiov;
        struct msghdr out;
        size_t off = 0;
        int first = 1;
        while (off < (size_t)n) {
            memset(&out, 0, sizeof out);
            oiov.iov_base = buf + off;
            oiov.iov_len = (size_t)n - off;
            out.msg_iov = &oiov;
            out.msg_iovlen = 1;
            if (first && nfd > 0 && in.msg_controllen > 0) {
                out.msg_control = in.msg_control;
                out.msg_controllen = in.msg_controllen;
            }
            ssize_t w = sendmsg(to, &out, MSG_NOSIGNAL);
            if (w < 0) {
                if (errno == EINTR) continue;
                log_line("%s sendmsg: %s", tag, strerror(errno));
                close_cmsg_fds(&in);
                return -1;
            }
            off += (size_t)w;
            first = 0;                            /* fd 只跟第一批字节走 */
        }
    }
    close_cmsg_fds(&in);                          /* 接收方已有自己的副本 */
    return n;
}

/* ------------------------------------------------------------------ 转发线程
 *
 * 为什么不是单线程 poll 多路复用（最初的写法）：
 *   poll 版本在转发时用的是**阻塞** sendmsg。只要某个方向的对端一时读得慢
 *   （套接字缓冲写满），这一次 sendmsg 就会一直阻塞 —— 而它是所有连接共用的那一个
 *   线程，于是**另一条连接（比如浏览器进程 vs GPU 进程）的帧确认也一起停住**。
 *   实测表现就是 Chrome 的合成器卡死：
 *     CompositorAnimationObserver is active for too long (71.65s)
 *   即"网页持续卡死"，而且和 CPU 快慢无关。
 *
 * 现在：每条 client↔上游 连接起两个线程（两个方向各一个），阻塞只发生在自己那条
 * 连接里；互不干扰。一端结束时 shutdown 两端，让另一个线程也醒过来退出。 */
struct pump_arg {
    int from;
    int to;
    int to_up;              /* 1 = client→守护进程 */
    int up_idx;             /* 占用的上游下标（退出时释放） */
    int up_fd;
    int client_fd;
};

static void *pump_thread(void *p) {
    struct pump_arg *a = (struct pump_arg *)p;
    long long nb = 0, nf = 0;

    for (;;) {
        ssize_t n = relay_once(a->from, a->to,
                               a->to_up ? "→守护进程" : "→客户端", &nb, &nf);
        if (n < 0) break;
    }
    /* 一个方向结束（对端关闭/出错）：把两端都关掉，另一个方向的线程随即返回 */
    shutdown(a->from, SHUT_RDWR);
    shutdown(a->to, SHUT_RDWR);
    __atomic_store_n(&g_up_busy[a->up_idx], 0, __ATOMIC_RELEASE);
    log_line("client fd %d ↔ 上游 fd %d 的 %s 方向结束（本方向 %lldB / %lldfd；累计 %lldB / %lldfd）",
             a->client_fd, a->up_fd, a->to_up ? "去" : "回", nb, nf,
             g_total_bytes, g_total_fds);
    free(a);
    return NULL;
}

int main(int argc, char **argv) {
    const char *listen_path = NULL;
    int env_fd = -1;
    const char *e;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--listen") && i + 1 < argc) listen_path = argv[++i];
        else if ((!strcmp(argv[i], "--upstream") || !strcmp(argv[i], "--fd")) && i + 1 < argc) {
            if (g_nup < AWL_MAX_UP) g_up[g_nup++] = atoi(argv[++i]);
            else i++;
        } else if (!strcmp(argv[i], "--verbose")) g_verbose = 1;
    }
    e = getenv("WAYLAND_SOCKET");
    if (e && *e) env_fd = atoi(e);
    if (g_nup == 0 && env_fd >= 0) g_up[g_nup++] = env_fd;
    if (!listen_path) { log_line("缺少 --listen"); return 2; }
    if (g_nup == 0) { log_line("没有上游 fd（--upstream N 或 WAYLAND_SOCKET）"); return 2; }

    signal(SIGPIPE, SIG_IGN);

    /* 校验上游 fd：无效的**丢掉并继续**（只要还有一条能用的就别整个退出，
     * 否则一条坏 fd 会让整个中继起不来，而 App 侧只会看到"套接字就绪"的假象）。 */
    {
        int keep = 0;
        for (int i = 0; i < g_nup; i++) {
            if (fcntl(g_up[i], F_GETFD) < 0) {
                log_line("丢弃无效的上游 fd %d（%s）", g_up[i], strerror(errno));
            } else {
                g_up[keep++] = g_up[i];
            }
        }
        g_nup = keep;
    }
    if (g_nup == 0) { log_line("没有可用的上游 fd —— 退出"); return 2; }
    log_line("可用上游连接 %d 条:", g_nup);
    for (int i = 0; i < g_nup; i++) log_line("  #%d fd %d", i + 1, g_up[i]);

    /* 上游只应被一条客户端连接占用：客户端（浏览器/GPU 进程）各自一条连接 */
    memset((void *)g_up_busy, 0, sizeof g_up_busy);
    for (int i = 0; i < g_nup; i++) g_up_of[i] = g_up[i];

    int lfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (lfd < 0) { log_line("socket: %s", strerror(errno)); return 1; }
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    if (strlen(listen_path) >= sizeof sa.sun_path) { log_line("路径太长"); return 2; }
    strcpy(sa.sun_path, listen_path);
    unlink(listen_path);
    if (bind(lfd, (struct sockaddr *)&sa, sizeof sa) != 0 || listen(lfd, 16) != 0) {
        log_line("bind/listen %s: %s", listen_path, strerror(errno));
        return 1;
    }
    chmod(listen_path, 0777);
    log_line("listening on %s", listen_path);

    for (;;) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR) continue;
            log_line("accept: %s", strerror(errno));
            break;
        }

        int slot = -1;
        for (int i = 0; i < g_nup; i++) {
            if (!__atomic_load_n(&g_up_busy[i], __ATOMIC_ACQUIRE)) {
                if (!__atomic_test_and_set(&g_up_busy[i], __ATOMIC_ACQ_REL)) { slot = i; break; }
            }
        }
        if (slot < 0) {
            log_line("又一个客户端连接，但 %d 条上游都在忙 —— 拒绝（多给几条 --upstream）", g_nup);
            close(cfd);
            continue;
        }

        int up = g_up_of[slot];
        log_line("客户端已连接（client fd %d ↔ 上游 fd %d）", cfd, up);

        pthread_t t;
        struct pump_arg *a1 = calloc(1, sizeof *a1);
        a1->from = cfd; a1->to = up; a1->to_up = 1;
        a1->up_idx = slot; a1->up_fd = up; a1->client_fd = cfd;
        if (pthread_create(&t, NULL, pump_thread, a1) != 0) {
            log_line("pthread_create 失败: %s", strerror(errno));
            free(a1);
            __atomic_store_n(&g_up_busy[slot], 0, __ATOMIC_RELEASE);
            close(cfd);
            continue;
        }
        pthread_detach(t);

        struct pump_arg *a2 = calloc(1, sizeof *a2);
        a2->from = up; a2->to = cfd; a2->to_up = 0;
        a2->up_idx = slot; a2->up_fd = up; a2->client_fd = cfd;
        if (pthread_create(&t, NULL, pump_thread, a2) != 0) {
            log_line("pthread_create 失败: %s", strerror(errno));
            free(a2);
            shutdown(cfd, SHUT_RDWR);      /* 让另一方向的线程也退出，并释放 slot */
            continue;
        }
        pthread_detach(t);
    }
    return 0;
}
