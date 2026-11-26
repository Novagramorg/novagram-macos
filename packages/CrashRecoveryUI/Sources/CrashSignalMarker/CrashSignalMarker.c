#include "CrashSignalMarker.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static const int crashSignals[] = { SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGSYS, SIGTRAP };
#define CRASH_SIGNAL_COUNT (sizeof(crashSignals) / sizeof(crashSignals[0]))

static char crashMarkerPath[PATH_MAX];
static char crashMarkerBundleVersion[64];
static struct sigaction previousCrashActions[CRASH_SIGNAL_COUNT];
static volatile time_t crashClockStart = 0;
static volatile sig_atomic_t crashMarkerArmed = 0;
static volatile sig_atomic_t crashMarkerWritten = 0;
static volatile sig_atomic_t crashMarkerDone = 0;
static volatile sig_atomic_t crashMarkerReadsThreadName = 0;
static pthread_t volatile crashMarkerWriter = NULL;
static int crashSignalHandlerInstalled = 0;

static size_t appendCrashNumber(char *buffer, size_t offset, long long value) {
    char digits[24];
    size_t count = 0;
    if (value < 0) {
        value = 0;
    }
    do {
        digits[count++] = (char)('0' + value % 10);
        value /= 10;
    } while (value > 0 && count < sizeof(digits));
    while (count > 0) {
        buffer[offset++] = digits[--count];
    }
    return offset;
}

static size_t appendCrashText(char *buffer, size_t offset, size_t limit, const char *text) {
    for (size_t i = 0; text[i] != 0 && offset < limit; i++) {
        unsigned char character = (unsigned char)text[i];
        buffer[offset++] = (character < 0x20 || character > 0x7e) ? '?' : (char)character;
    }
    return offset;
}

static size_t appendCrashLine(char *buffer, size_t offset, size_t capacity, const char *key, const char *value) {
    offset = appendCrashText(buffer, offset, capacity - 1, key);
    offset = appendCrashText(buffer, offset, capacity - 1, value);
    if (offset < capacity) {
        buffer[offset++] = '\n';
    }
    return offset;
}

static void handleCrashSignal(int signalNumber, siginfo_t *info, void *context) {
    int savedErrno = errno;
    if (crashMarkerArmed && __sync_lock_test_and_set(&crashMarkerWritten, 1) != 0) {
        if (crashMarkerWriter != pthread_self()) {
            for (unsigned long spins = 0; !crashMarkerDone && spins < 200000000UL; spins++) {
            }
        }
    } else if (crashMarkerArmed) {
        crashMarkerWriter = pthread_self();
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        char text[512];
        size_t length = appendCrashNumber(text, 0, signalNumber);
        text[length++] = ' ';
        length = appendCrashNumber(text, length, (long long)(now.tv_sec - crashClockStart));
        text[length++] = '\n';
        length = appendCrashLine(text, length, sizeof(text), "bundle ", crashMarkerBundleVersion);
        int fd = open(crashMarkerPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            ssize_t written = write(fd, text, length);
            sigset_t faults;
            sigemptyset(&faults);
            sigaddset(&faults, SIGSEGV);
            sigaddset(&faults, SIGBUS);
            pthread_sigmask(SIG_UNBLOCK, &faults, NULL);
            const char *queueLabel = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
            length = appendCrashLine(text, 0, sizeof(text), "queue ", queueLabel != NULL ? queueLabel : "");
            written = write(fd, text, length);
            if (crashMarkerReadsThreadName) {
                char threadName[64];
                if (pthread_getname_np(pthread_self(), threadName, sizeof(threadName)) != 0) {
                    threadName[0] = 0;
                }
                char line[96];
                size_t lineLength = appendCrashLine(line, 0, sizeof(line), "thread ", threadName);
                written = write(fd, line, lineLength);
            }
            (void)written;
            close(fd);
        }
        crashMarkerDone = 1;
    }
    for (size_t i = 0; i < CRASH_SIGNAL_COUNT; i++) {
        sigaction(crashSignals[i], &previousCrashActions[i], NULL);
    }
    if (signalNumber == SIGSYS) {
        sigset_t unblocked;
        sigemptyset(&unblocked);
        sigaddset(&unblocked, signalNumber);
        pthread_sigmask(SIG_UNBLOCK, &unblocked, NULL);
        raise(signalNumber);
    }
    errno = savedErrno;
}

void armCrashSignalMarker(const char * _Nonnull markerPath, const char * _Nonnull bundleVersion) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    crashClockStart = now.tv_sec;
    crashMarkerWritten = 0;
    crashMarkerDone = 0;
    crashMarkerWriter = NULL;
    crashMarkerArmed = 1;
    if (crashSignalHandlerInstalled || strlcpy(crashMarkerPath, markerPath, sizeof(crashMarkerPath)) >= sizeof(crashMarkerPath)) {
        return;
    }
    strlcpy(crashMarkerBundleVersion, bundleVersion, sizeof(crashMarkerBundleVersion));
    if (__builtin_available(macOS 10.14, *)) {
        crashMarkerReadsThreadName = 1;
    }
    crashSignalHandlerInstalled = 1;
    stack_t currentStack;
    if (sigaltstack(NULL, &currentStack) == 0 && (currentStack.ss_flags & SS_DISABLE) != 0) {
        stack_t alternateStack;
        alternateStack.ss_size = SIGSTKSZ;
        alternateStack.ss_sp = malloc(alternateStack.ss_size);
        alternateStack.ss_flags = 0;
        if (alternateStack.ss_sp != NULL) {
            sigaltstack(&alternateStack, NULL);
        }
    }
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = handleCrashSignal;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    for (size_t i = 0; i < CRASH_SIGNAL_COUNT; i++) {
        sigaction(crashSignals[i], &action, &previousCrashActions[i]);
    }
}

void disarmCrashSignalMarker(void) {
    crashMarkerArmed = 0;
}
