#ifndef CrashSignalMarker_h
#define CrashSignalMarker_h

void armCrashSignalMarker(const char * _Nonnull markerPath, const char * _Nonnull bundleVersion);
void disarmCrashSignalMarker(void);

#endif
