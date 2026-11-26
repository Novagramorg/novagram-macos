#!/bin/bash
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd)
TG=$ROOT/submodules/tgcalls
H=$TG/SharedHeaders/webrtc
OUT=$DIR/build
APP=$OUT/CaptureBench.app
mkdir -p $OUT/obj $APP/Contents/MacOS
DEFINES="-DWEBRTC_POSIX=1 -DWEBRTC_MAC=1 -DNDEBUG=1 -DRTC_ENABLE_VP9=1 -DABSL_ALLOCATOR_NOTHROW=1 -DHAVE_WEBRTC_VIDEO -DNO_MAIN_THREAD_WRAPPING -DRTC_DISABLE_TRACE_EVENTS -DWEBRTC_ARCH_ARM64 -DWEBRTC_HAS_NEON -DWEBRTC_LIBRARY_IMPL -DWEBRTC_NON_STATIC_TRACE_EVENT_HANDLERS=1 -DWEBRTC_USE_H264"
INCLUDES="-I$TG -I$TG/tgcalls -I$H -I$H/third_party/abseil-cpp -I$H/third_party/libyuv/include -I$H/sdk/objc -I$H/sdk/objc/base -I$H/sdk/objc/components/video_frame_buffer"
FLAGS="-std=c++20 -O2 -arch arm64 -mmacosx-version-min=11.0 $DEFINES $INCLUDES"
for f in DesktopCaptureSourceHelper DesktopCaptureSource DesktopCaptureSourceManager; do
    clang++ $FLAGS -c $TG/tgcalls/desktop_capturer/$f.cpp -o $OUT/obj/$f.o
done
clang++ $FLAGS -DTGCALLS_USE_SCREENCAPTUREKIT=1 -fobjc-arc -x objective-c++ -c $TG/tgcalls/platform/darwin/ScreenCaptureKitCapturer.mm -o $OUT/obj/ScreenCaptureKitCapturer.o
clang++ $FLAGS -DTGCALLS_USE_SCREENCAPTUREKIT=1 -fobjc-arc -x objective-c++ -c $DIR/main.mm -o $OUT/obj/main.o
clang++ -arch arm64 -mmacosx-version-min=11.0 $OUT/obj/*.o $ROOT/core-xprojects/webrtc/build/arm64/libtg_owt.a $ROOT/core-xprojects/webrtc/build/webrtc/libmac_framework_objc_static.a $ROOT/core-xprojects/Mozjpeg/build/arm64/libjpeg.a \
    $ROOT/core-xprojects/OpenH264/build/arm64/libopenh264.a $ROOT/core-xprojects/ffmpeg/build/ffmpeg/lib/libavcodec.a $ROOT/core-xprojects/ffmpeg/build/ffmpeg/lib/libavutil.a $ROOT/core-xprojects/ffmpeg/build/ffmpeg/lib/libswresample.a \
    $ROOT/core-xprojects/libopus/build/arm64/libopus.a $ROOT/core-xprojects/libvpx/build/arm64/libvpx.a $ROOT/core-xprojects/dav1d/build/arm64/src/libdav1d.a -lz -lbz2 -liconv -lc++ \
    -framework AppKit -framework QuartzCore -framework CoreVideo -framework CoreMedia -framework IOSurface -framework Metal \
    -framework CoreGraphics -framework ApplicationServices -framework AVFoundation -framework VideoToolbox -framework AudioToolbox \
    -framework CoreAudio -framework Foundation -framework Security -framework SystemConfiguration -framework IOKit \
    -weak_framework ScreenCaptureKit -o $APP/Contents/MacOS/CaptureBench
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CaptureBench</string>
    <key>CFBundleIdentifier</key><string>org.telegram.perflab.capturebench</string>
    <key>CFBundleName</key><string>CaptureBench</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
IDENTITY=${CAPTUREBENCH_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}
codesign --force --sign "${IDENTITY:--}" $APP
echo "built $APP"
