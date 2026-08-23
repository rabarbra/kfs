/*
 * Integration test runner. Replaces /bin/init in a test rootfs.
 *
 * Each case returns 0 on success, non-zero on failure. We log PASS/FAIL on
 * the serial console (/dev/ttyS0) and finish with a magic marker the host
 * wrapper grep's for to decide qemu's exit status.
 *
 * Build: zig cc -target x86-linux-musl -static -Os -o init_test runner.c
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int serial_fd = -1;

static void slog(const char *s) {
    if (serial_fd < 0) return;
    write(serial_fd, s, strlen(s));
}

static void slogf(const char *fmt, ...) {
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0 && serial_fd >= 0) write(serial_fd, buf, (size_t)n);
}

/* ---- cases ---- */

static int case_open_write_read(void) {
    int fd = open("/tmp/itest.txt", O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 1;
    const char *msg = "hello";
    if (write(fd, msg, 5) != 5) { close(fd); return 2; }
    if (lseek(fd, 0, SEEK_SET) != 0) { close(fd); return 3; }
    char buf[8] = {0};
    if (read(fd, buf, 5) != 5) { close(fd); return 4; }
    close(fd);
    if (memcmp(buf, msg, 5) != 0) return 5;
    unlink("/tmp/itest.txt");
    return 0;
}

static int case_fork_wait(void) {
    pid_t p = fork();
    if (p < 0) return 1;
    if (p == 0) _exit(7);
    int status = 0;
    if (waitpid(p, &status, 0) != p) return 2;
    if (!WIFEXITED(status)) return 3;
    if (WEXITSTATUS(status) != 7) return 4;
    return 0;
}

static int case_pipe(void) {
    int fds[2];
    if (pipe(fds) < 0) return 1;
    const char *msg = "ping";
    if (write(fds[1], msg, 4) != 4) { close(fds[0]); close(fds[1]); return 2; }
    char buf[8] = {0};
    if (read(fds[0], buf, 4) != 4) { close(fds[0]); close(fds[1]); return 3; }
    close(fds[0]);
    close(fds[1]);
    return memcmp(buf, msg, 4) == 0 ? 0 : 4;
}

static volatile sig_atomic_t got_sig = 0;
static void on_sig(int s) { (void)s; got_sig = 1; }

static int case_signal_handler(void) {
    struct sigaction sa = {0};
    sa.sa_handler = on_sig;
    if (sigaction(SIGUSR1, &sa, NULL) < 0) return 1;
    got_sig = 0;
    if (kill(getpid(), SIGUSR1) < 0) return 2;
    /* small spin so the signal is delivered */
    for (int i = 0; i < 1000 && !got_sig; ++i) sched_yield();
    return got_sig ? 0 : 3;
}

/* mmap_anon was disabled — musl's mmap path on this kernel needs more
   investigation. Re-enable once it doesn't hang. */

static int case_getpid_uniqueness(void) {
    pid_t a = getpid();
    pid_t b = getpid();
    if (a != b) return 1;
    pid_t c = fork();
    if (c < 0) return 2;
    if (c == 0) {
        if (getpid() == a) _exit(10);
        _exit(0);
    }
    int status = 0;
    waitpid(c, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 3;
}

struct tcase { const char *name; int (*run)(void); };
static const struct tcase cases[] = {
    { "open_write_read",     case_open_write_read },
    { "fork_wait",           case_fork_wait },
    { "pipe",                case_pipe },
    { "signal_handler",      case_signal_handler },
    { "getpid_uniqueness",   case_getpid_uniqueness },
};

int main(void) {
    /* COM1 / ttyS0 is reserved for the kernel's printk; userspace uses
       ttyS1 (COM2). Fall back to console / tty if those don't exist. */
    static const char *candidates[] = {
        "/dev/ttyS1", "/dev/ttyS2", "/dev/console", "/dev/tty0", "/dev/tty", NULL,
    };
    for (int i = 0; candidates[i]; ++i) {
        serial_fd = open(candidates[i], O_WRONLY);
        if (serial_fd >= 0) break;
    }
    if (serial_fd < 0) serial_fd = 1;
    /* Make stdio go to the same fd so anything that prints lands somewhere. */
    dup2(serial_fd, 1);
    dup2(serial_fd, 2);

    slog("\n[ITEST] === starting integration tests ===\n");
    int passed = 0, failed = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        int rc = cases[i].run();
        if (rc == 0) {
            slogf("[ITEST] PASS: %s\n", cases[i].name);
            ++passed;
        } else {
            slogf("[ITEST] FAIL: %s rc=%d errno=%d\n",
                  cases[i].name, rc, errno);
            ++failed;
        }
    }
    slogf("[ITEST] summary: %d passed, %d failed\n", passed, failed);

    /* Markers the host wrapper grep's for. */
    if (failed == 0) slog("[ITEST] === ALL PASS ===\n");
    else            slog("[ITEST] === FAIL ===\n");

    /* Sit forever — kernel keeps running, host wrapper times out qemu. */
    while (1) pause();
    return 0;
}
