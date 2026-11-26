#ifndef CrashSignalMarkerTestSupport_h
#define CrashSignalMarkerTestSupport_h

int crashOnThreadInChildProcess(const char * _Nonnull markerPath, const char * _Nonnull bundleVersion, const char * _Nonnull threadName, const char * _Nonnull queueLabel, int signalNumber);
int crashWithCorruptQueueSlotInChildProcess(const char * _Nonnull markerPath, const char * _Nonnull bundleVersion, int aborts);

#endif
