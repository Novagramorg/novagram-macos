#include "CrashSignalMarkerTestSupport.h"
#include "CrashSignalMarker.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct {
    const char *threadName;
    const char *queueLabel;
    int signalNumber;
} CrashingThreadArguments;

static void crash(void *argument) {
    CrashingThreadArguments *arguments = argument;
    pthread_kill(pthread_self(), arguments->signalNumber);
    _exit(0);
}

static void *runCrashingThread(void *argument) {
    CrashingThreadArguments *arguments = argument;
    if (arguments->threadName[0] != 0) {
        pthread_setname_np(arguments->threadName);
    }
    if (arguments->queueLabel[0] != 0) {
        dispatch_queue_t queue = dispatch_queue_create(arguments->queueLabel, DISPATCH_QUEUE_SERIAL);
        dispatch_sync_f(queue, arguments, crash);
        _exit(4);
    }
    crash(arguments);
    return NULL;
}

static const pthread_key_t dispatchQueueKey = 20;

static void exitOnFault(int signalNumber) {
    _exit(100 + signalNumber);
}

static void *runCorruptQueueThread(void *argument) {
    pthread_setname_np("mtproto-worker-0");
    pthread_setspecific(dispatchQueueKey, (void *)0x10);
    if (argument != NULL) {
        abort();
    }
    pthread_kill(pthread_self(), SIGSEGV);
    _exit(0);
    return NULL;
}

static int waitForChild(pid_t child) {
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) {
            return -1;
        }
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 128 + WTERMSIG(status);
}

int crashWithCorruptQueueSlotInChildProcess(const char * _Nonnull markerPath, const char * _Nonnull bundleVersion, int aborts) {
    fflush(NULL);
    pid_t child = fork();
    if (child < 0) {
        return -1;
    }
    if (child == 0) {
        alarm(10);
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = exitOnFault;
        sigemptyset(&action.sa_mask);
        sigaction(SIGSEGV, &action, NULL);
        sigaction(SIGBUS, &action, NULL);
        armCrashSignalMarker(markerPath, bundleVersion);
        pthread_t thread;
        if (pthread_create(&thread, NULL, runCorruptQueueThread, aborts ? (void *)1 : NULL) != 0) {
            _exit(2);
        }
        pthread_join(thread, NULL);
        _exit(3);
    }
    return waitForChild(child);
}

int crashOnThreadInChildProcess(const char * _Nonnull markerPath, const char * _Nonnull bundleVersion, const char * _Nonnull threadName, const char * _Nonnull queueLabel, int signalNumber) {
    pid_t child = fork();
    if (child < 0) {
        return -1;
    }
    if (child == 0) {
        alarm(10);
        armCrashSignalMarker(markerPath, bundleVersion);
        CrashingThreadArguments arguments = { threadName, queueLabel, signalNumber };
        pthread_t thread;
        if (pthread_create(&thread, NULL, runCrashingThread, &arguments) != 0) {
            _exit(2);
        }
        pthread_join(thread, NULL);
        _exit(3);
    }
    return waitForChild(child);
}
