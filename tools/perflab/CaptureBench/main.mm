#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <mach/mach.h>
#include <sys/resource.h>
#include <atomic>
#include <optional>
#include <mutex>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "tgcalls/desktop_capturer/DesktopCaptureSource.h"
#include "tgcalls/desktop_capturer/DesktopCaptureSourceHelper.h"
#include "tgcalls/desktop_capturer/DesktopCaptureSourceManager.h"
#include "api/video/video_frame.h"
#include "api/video/video_sink_interface.h"
#include "third_party/libyuv/include/libyuv.h"
#import "tgcalls/platform/darwin/ScreenCaptureKitCapturer.h"
#import "base/RTCVideoFrameBuffer.h"
#import "base/RTCI420Buffer.h"
#include "modules/video_coding/codecs/h264/include/h264.h"
#include "api/video/i420_buffer.h"
#include "api/video_codecs/video_encoder.h"
#include "rtc_base/logging.h"

static double cpuSeconds() {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / 1e6 + usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / 1e6;
}

static mach_port_t mainThreadPort = MACH_PORT_NULL;

static double mainThreadSeconds() {
    thread_basic_info_data_t info;
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    if (thread_info(mainThreadPort, THREAD_BASIC_INFO, (thread_info_t)&info, &count) != KERN_SUCCESS) {
        return 0;
    }
    return info.user_time.seconds + info.user_time.microseconds / 1e6 + info.system_time.seconds + info.system_time.microseconds / 1e6;
}

static NSString *runCommand(NSString *path, NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = path;
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static double windowServerSeconds() {
    NSString *pid = [[runCommand(@"/usr/bin/pgrep", @[@"-x", @"WindowServer"]) componentsSeparatedByString:@"\n"] firstObject];
    NSString *value = [runCommand(@"/bin/ps", @[@"-o", @"time=", @"-p", pid ?: @"0"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    double total = 0;
    for (NSString *part in [value componentsSeparatedByString:@":"]) {
        total = total * 60 + part.doubleValue;
    }
    return total;
}

static int gpuUtilization() {
    NSString *output = runCommand(@"/usr/sbin/ioreg", @[@"-r", @"-d", @"1", @"-w", @"0", @"-c", @"IOAccelerator"]);
    NSRange range = [output rangeOfString:@"\"Device Utilization %\"="];
    if (range.location == NSNotFound) {
        return -1;
    }
    return [[output substringFromIndex:range.location + range.length] intValue];
}

struct FrameStats {
    std::atomic<int> frames{0};
    std::atomic<int> width{0};
    std::atomic<int> height{0};
    std::mutex lock;
    std::vector<uint8_t> lastI420;
    int lastWidth = 0;
    int lastHeight = 0;
    bool keepLast = false;
};

static void storeI420(FrameStats *stats, int width, int height, const uint8_t *y, int strideY, const uint8_t *u, int strideU, const uint8_t *v, int strideV) {
    std::lock_guard<std::mutex> guard(stats->lock);
    int chromaWidth = (width + 1) / 2;
    int chromaHeight = (height + 1) / 2;
    stats->lastI420.resize((size_t)width * height + (size_t)chromaWidth * chromaHeight * 2);
    uint8_t *out = stats->lastI420.data();
    libyuv::I420Copy(y, strideY, u, strideU, v, strideV, out, width, out + width * height, chromaWidth, out + width * height + chromaWidth * chromaHeight, chromaWidth, width, height);
    stats->lastWidth = width;
    stats->lastHeight = height;
}

class CountingSink : public rtc::VideoSinkInterface<webrtc::VideoFrame> {
public:
    explicit CountingSink(std::shared_ptr<FrameStats> stats) : _stats(std::move(stats)) {
    }
    void OnFrame(const webrtc::VideoFrame &frame) override {
        _stats->frames++;
        _stats->width = frame.width();
        _stats->height = frame.height();
        if (_stats->keepLast) {
            auto i420 = frame.video_frame_buffer()->ToI420();
            storeI420(_stats.get(), i420->width(), i420->height(), i420->DataY(), i420->StrideY(), i420->DataU(), i420->StrideU(), i420->DataV(), i420->StrideV());
        }
    }
private:
    std::shared_ptr<FrameStats> _stats;
};

@protocol BenchPipeline <NSObject>
- (void)start;
- (void)stop;
@end

@interface LegacyPipeline : NSObject <BenchPipeline>
- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats windowTitle:(NSString *)windowTitle;
@end

@implementation LegacyPipeline {
    std::unique_ptr<tgcalls::DesktopCaptureSourceHelper> _helper;
}

- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats windowTitle:(NSString *)windowTitle {
    self = [super init];
    if (self != nil) {
        tgcalls::DesktopCaptureSourceManager manager(windowTitle != nil ? tgcalls::DesktopCaptureType::Window : tgcalls::DesktopCaptureType::Screen);
        auto sources = manager.sources();
        std::optional<tgcalls::DesktopCaptureSource> selected;
        for (const auto &source : sources) {
            if (windowTitle == nil || source.title() == std::string(windowTitle.UTF8String)) {
                selected = source;
                break;
            }
        }
        if (!selected) {
            NSLog(@"CaptureBench: legacy source not found");
            return nil;
        }
        tgcalls::DesktopCaptureSourceData data{{1920, 1080}, 25, true};
        _helper = std::make_unique<tgcalls::DesktopCaptureSourceHelper>(*selected, data);
        _helper->setOutput(std::make_shared<CountingSink>(stats));
        _helper->setOnPause([](bool paused) {
            NSLog(@"CaptureBench: legacy capturer paused=%d", paused);
        });
        _helper->setOnFatalError([] {
            NSLog(@"CaptureBench: legacy capturer fatal error");
        });
    }
    return self;
}

- (void)start {
    _helper->start();
}

- (void)stop {
    _helper->stop();
}

@end

API_AVAILABLE(macos(12.3))
@interface SCKPipeline : NSObject <BenchPipeline, SCStreamOutput>
- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats convertToI420:(BOOL)convertToI420 windowTitle:(NSString *)windowTitle;
@end

@implementation SCKPipeline {
    std::shared_ptr<FrameStats> _stats;
    BOOL _convertToI420;
    SCStream *_stream;
    NSString *_windowTitle;
    dispatch_queue_t _queue;
    std::vector<uint8_t> _i420;
}

- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats convertToI420:(BOOL)convertToI420 windowTitle:(NSString *)windowTitle {
    self = [super init];
    if (self != nil) {
        _stats = stats;
        _convertToI420 = convertToI420;
        _windowTitle = windowTitle;
        _queue = dispatch_queue_create("CaptureBench.sck", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
        SCDisplay *display = content.displays.firstObject;
        if (display == nil) {
            NSLog(@"CaptureBench: no display %@", error);
            return;
        }
        CGDirectDisplayID displayId = display.displayID;
        size_t pixelWidth = CGDisplayPixelsWide(displayId);
        size_t pixelHeight = CGDisplayPixelsHigh(displayId);
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayId);
        double backingScale = 1.0;
        if (mode != NULL) {
            backingScale = (double)CGDisplayModeGetPixelWidth(mode) / MAX(1.0, (double)CGDisplayModeGetWidth(mode));
            pixelWidth = CGDisplayModeGetPixelWidth(mode);
            pixelHeight = CGDisplayModeGetPixelHeight(mode);
            CGDisplayModeRelease(mode);
        }
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
        if (self->_windowTitle != nil) {
            SCWindow *window = nil;
            for (SCWindow *candidate in content.windows) {
                if ([candidate.title isEqualToString:self->_windowTitle]) {
                    window = candidate;
                    break;
                }
            }
            if (window == nil) {
                NSLog(@"CaptureBench: window not found");
                return;
            }
            filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
            pixelWidth = (size_t)(window.frame.size.width * backingScale);
            pixelHeight = (size_t)(window.frame.size.height * backingScale);
        }
        double scale = MIN(1.0, MIN(1920.0 / pixelWidth, 1080.0 / pixelHeight));
        SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
        configuration.width = ((size_t)(pixelWidth * scale)) & ~(size_t)1;
        configuration.height = ((size_t)(pixelHeight * scale)) & ~(size_t)1;
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        configuration.minimumFrameInterval = CMTimeMake(1, 25);
        configuration.showsCursor = YES;
        configuration.queueDepth = 5;
        self->_stream = [[SCStream alloc] initWithFilter:filter configuration:configuration delegate:nil];
        NSError *addError = nil;
        if (![self->_stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self->_queue error:&addError]) {
            NSLog(@"CaptureBench: addStreamOutput %@", addError);
            return;
        }
        [self->_stream startCaptureWithCompletionHandler:^(NSError *startError) {
            if (startError != nil) {
                NSLog(@"CaptureBench: startCapture %@", startError);
            }
        }];
    }];
}

- (void)stop {
    [_stream stopCaptureWithCompletionHandler:^(NSError *error) {
    }];
    _stream = nil;
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sampleBuffer)) {
        return;
    }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (attachments == NULL || CFArrayGetCount(attachments) == 0) {
        return;
    }
    NSDictionary *info = (__bridge NSDictionary *)CFArrayGetValueAtIndex(attachments, 0);
    NSNumber *status = info[SCStreamFrameInfoStatus];
    if (status == nil || status.integerValue != SCFrameStatusComplete) {
        return;
    }
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer == NULL) {
        return;
    }
    int width = (int)CVPixelBufferGetWidth(pixelBuffer);
    int height = (int)CVPixelBufferGetHeight(pixelBuffer);
    if (getenv("CAPTUREBENCH_LOG_INFO") != NULL && (_stats->frames % 25) == 0) {
        CGRect contentRect = CGRectZero;
        NSDictionary *rectDictionary = info[SCStreamFrameInfoContentRect];
        if (rectDictionary != nil) {
            CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)rectDictionary, &contentRect);
        }
        NSLog(@"CaptureBench info buffer=%dx%d contentRect=%@ contentScale=%@ scaleFactor=%@", width, height, NSStringFromRect(contentRect), info[SCStreamFrameInfoContentScale], info[SCStreamFrameInfoScaleFactor]);
    }
    if (_convertToI420) {
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        size_t ySize = (size_t)width * height;
        size_t uvWidth = (width + 1) / 2;
        size_t uvSize = uvWidth * ((height + 1) / 2);
        if (_i420.size() < ySize + uvSize * 2) {
            _i420.resize(ySize + uvSize * 2);
        }
        libyuv::NV12ToI420((const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0), (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0), (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1), (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1), _i420.data(), width, _i420.data() + ySize, (int)uvWidth, _i420.data() + ySize + uvSize, (int)uvWidth, width, height);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    }
    _stats->frames++;
    _stats->width = width;
    _stats->height = height;
}

@end

API_AVAILABLE(macos(12.3))
@interface TGSCKPipeline : NSObject <BenchPipeline>
- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats windowTitle:(NSString *)windowTitle;
@end

@implementation TGSCKPipeline {
    ScreenCaptureKitCapturer *_capturer;
}

- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats windowTitle:(NSString *)windowTitle {
    self = [super init];
    if (self != nil) {
        tgcalls::DesktopCaptureSourceManager manager(windowTitle != nil ? tgcalls::DesktopCaptureType::Window : tgcalls::DesktopCaptureType::Screen);
        std::optional<tgcalls::DesktopCaptureSource> selected;
        for (const auto &source : manager.sources()) {
            if (windowTitle == nil || source.title() == std::string(windowTitle.UTF8String)) {
                selected = source;
                break;
            }
        }
        if (!selected) {
            return nil;
        }
        tgcalls::DesktopCaptureSourceData data{{1920, 1080}, 25, true};
        _capturer = [[ScreenCaptureKitCapturer alloc] initWithSource:*selected data:data frameReceived:^(RTC_OBJC_TYPE(RTCVideoFrame) *frame) {
            id<RTC_OBJC_TYPE(RTCI420Buffer)> i420 = [frame.buffer toI420];
            if (stats->width != frame.width || stats->height != frame.height) {
                NSLog(@"CaptureBench: tg capturer frame size %dx%d", (int)frame.width, (int)frame.height);
            }
            stats->frames++;
            stats->width = frame.width;
            stats->height = frame.height;
            if (stats->keepLast) {
                storeI420(stats.get(), i420.width, i420.height, i420.dataY, i420.strideY, i420.dataU, i420.strideU, i420.dataV, i420.strideV);
            }
        }];
        [_capturer setOnPause:[](bool paused) {
            NSLog(@"CaptureBench: tg capturer paused=%d", paused);
        }];
        [_capturer setOnFatalError:[] {
            NSLog(@"CaptureBench: tg capturer fatal error");
        }];
    }
    return self;
}

- (void)start {
    [_capturer start];
}

- (void)stop {
    [_capturer stop];
}

@end


struct EncoderStats {
    std::atomic<int> inputFrames{0};
    std::atomic<int> encodedFrames{0};
    std::atomic<int64_t> encodedBytes{0};
    std::atomic<int> skipWarnings{0};
    std::atomic<int> openH264Messages{0};

    void reset() {
        inputFrames = 0;
        encodedFrames = 0;
        encodedBytes = 0;
        skipWarnings = 0;
        openH264Messages = 0;
    }
};

static std::shared_ptr<EncoderStats> currentEncoderStats;

class OpenH264LogCounter : public rtc::LogSink {
public:
    explicit OpenH264LogCounter(std::shared_ptr<EncoderStats> stats) : _stats(std::move(stats)) {
    }
    void OnLogMessage(const std::string &message) override {
        if (message.find("[OpenH264]") == std::string::npos) {
            return;
        }
        _stats->openH264Messages++;
        if (message.find("iContinualSkipFrames") != std::string::npos) {
            _stats->skipWarnings++;
        }
    }
private:
    std::shared_ptr<EncoderStats> _stats;
};

class EncodedCounter : public webrtc::EncodedImageCallback {
public:
    explicit EncodedCounter(std::shared_ptr<EncoderStats> stats) : _stats(std::move(stats)) {
    }
    Result OnEncodedImage(const webrtc::EncodedImage &image, const webrtc::CodecSpecificInfo *info) override {
        _stats->encodedFrames++;
        _stats->encodedBytes += image.size();
        return Result(Result::OK);
    }
private:
    std::shared_ptr<EncoderStats> _stats;
};

@interface ThumbnailEncoderPipeline : NSObject <BenchPipeline>
- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats encoderStats:(std::shared_ptr<EncoderStats>)encoderStats maxFramerate:(double)maxFramerate;
@end

@implementation ThumbnailEncoderPipeline {
    ScreenCaptureKitCapturer *_capturer;
    dispatch_queue_t _encodeQueue;
    std::shared_ptr<EncoderStats> _encoderStats;
    std::unique_ptr<webrtc::VideoEncoder> _encoder;
    std::unique_ptr<EncodedCounter> _callback;
    std::unique_ptr<OpenH264LogCounter> _logCounter;
    double _maxFramerate;
    int64_t _nextKeepNs;
    bool _sentKeyframe;
    bool _stopped;
}

- (instancetype)initWithStats:(std::shared_ptr<FrameStats>)stats encoderStats:(std::shared_ptr<EncoderStats>)encoderStats maxFramerate:(double)maxFramerate {
    self = [super init];
    if (self != nil) {
        _encoderStats = encoderStats;
        _maxFramerate = maxFramerate;
        _encodeQueue = dispatch_queue_create("CaptureBench.encode", DISPATCH_QUEUE_SERIAL);
        _logCounter = std::make_unique<OpenH264LogCounter>(encoderStats);
        rtc::LogMessage::AddLogToStream(_logCounter.get(), rtc::LS_VERBOSE);
        tgcalls::DesktopCaptureSourceManager manager(tgcalls::DesktopCaptureType::Screen);
        auto sources = manager.sources();
        if (sources.empty()) {
            return nil;
        }
        tgcalls::DesktopCaptureSourceData data{{1920, 1080}, 25, true};
        __weak ThumbnailEncoderPipeline *weakSelf = self;
        _capturer = [[ScreenCaptureKitCapturer alloc] initWithSource:sources.front() data:data frameReceived:^(RTC_OBJC_TYPE(RTCVideoFrame) *frame) {
            stats->frames++;
            stats->width = frame.width;
            stats->height = frame.height;
            [weakSelf encodeFrame:frame];
        }];
    }
    return self;
}

- (void)encodeFrame:(RTC_OBJC_TYPE(RTCVideoFrame) *)frame {
    int64_t timestampNs = frame.timeStampNs;
    if (_maxFramerate < 24.0) {
        int64_t interval = (int64_t)(1e9 / _maxFramerate);
        if (_nextKeepNs != 0 && timestampNs < _nextKeepNs - interval / 20) {
            return;
        }
        _nextKeepNs = (_nextKeepNs == 0 || timestampNs - _nextKeepNs > interval) ? timestampNs + interval : _nextKeepNs + interval;
    }
    id<RTC_OBJC_TYPE(RTCI420Buffer)> i420 = [frame.buffer toI420];
    int width = (i420.width / 2) & ~1;
    int height = (i420.height / 2) & ~1;
    rtc::scoped_refptr<webrtc::I420Buffer> scaled = webrtc::I420Buffer::Create(width, height);
    libyuv::I420Scale(i420.dataY, i420.strideY, i420.dataU, i420.strideU, i420.dataV, i420.strideV, i420.width, i420.height, scaled->MutableDataY(), scaled->StrideY(), scaled->MutableDataU(), scaled->StrideU(), scaled->MutableDataV(), scaled->StrideV(), width, height, libyuv::kFilterBox);
    dispatch_async(_encodeQueue, ^{
        if (self->_stopped) {
            return;
        }
        if (!self->_encoder) {
            [self createEncoderWithWidth:width height:height];
        }
        webrtc::VideoFrame videoFrame = webrtc::VideoFrame::Builder()
            .set_video_frame_buffer(scaled)
            .set_timestamp_rtp((uint32_t)(timestampNs / 1000000 * 90))
            .set_timestamp_us(timestampNs / 1000)
            .set_ntp_time_ms(timestampNs / 1000000)
            .build();
        std::vector<webrtc::VideoFrameType> types{self->_sentKeyframe ? webrtc::VideoFrameType::kVideoFrameDelta : webrtc::VideoFrameType::kVideoFrameKey};
        self->_sentKeyframe = true;
        self->_encoderStats->inputFrames++;
        self->_encoder->Encode(videoFrame, &types);
    });
}

- (void)createEncoderWithWidth:(int)width height:(int)height {
    webrtc::VideoCodec codec;
    codec.codecType = webrtc::kVideoCodecH264;
    codec.width = width;
    codec.height = height;
    codec.startBitrate = 75;
    codec.minBitrate = 50;
    codec.maxBitrate = 100;
    codec.maxFramerate = _maxFramerate < 24.0 ? (uint32_t)_maxFramerate : 60;
    codec.qpMax = 51;
    codec.mode = webrtc::VideoCodecMode::kScreensharing;
    codec.SetFrameDropEnabled(true);
    *codec.H264() = webrtc::VideoEncoder::GetDefaultH264Settings();
    codec.numberOfSimulcastStreams = 1;
    codec.simulcastStream[0].width = width;
    codec.simulcastStream[0].height = height;
    codec.simulcastStream[0].maxFramerate = codec.maxFramerate;
    codec.simulcastStream[0].numberOfTemporalLayers = 1;
    codec.simulcastStream[0].maxBitrate = 100;
    codec.simulcastStream[0].targetBitrate = 75;
    codec.simulcastStream[0].minBitrate = 50;
    codec.simulcastStream[0].qpMax = 51;
    codec.simulcastStream[0].active = true;
    _encoder = webrtc::H264Encoder::Create();
    _callback = std::make_unique<EncodedCounter>(_encoderStats);
    _encoder->RegisterEncodeCompleteCallback(_callback.get());
    webrtc::VideoEncoder::Settings settings(webrtc::VideoEncoder::Capabilities(false), 1, 1200);
    int result = _encoder->InitEncode(&codec, settings);
    webrtc::VideoBitrateAllocation allocation;
    allocation.SetBitrate(0, 0, 75000);
    _encoder->SetRates(webrtc::VideoEncoder::RateControlParameters(allocation, MIN(_maxFramerate, 24.0)));
    NSLog(@"CaptureBench: thumbnail encoder %dx%d maxFramerate=%u init=%d", width, height, codec.maxFramerate, result);
}

- (void)start {
    [_capturer start];
}

- (void)stop {
    [_capturer stop];
    dispatch_sync(_encodeQueue, ^{
        self->_stopped = true;
        if (self->_encoder) {
            self->_encoder->Release();
            self->_encoder.reset();
        }
    });
    rtc::LogMessage::RemoveLogToStream(_logCounter.get());
}

@end

@interface BusyView : NSView
@end

@implementation BusyView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
        for (int i = 0; i < 6; i++) {
            CALayer *layer = [CALayer layer];
            layer.frame = CGRectMake(40 + i * 120, 80, 100, 100);
            layer.backgroundColor = [NSColor colorWithHue:i / 6.0 saturation:0.8 brightness:0.9 alpha:1].CGColor;
            [self.layer addSublayer:layer];
            CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position.y"];
            animation.fromValue = @(80);
            animation.toValue = @(frameRect.size.height - 80);
            animation.duration = 1.0 + i * 0.2;
            animation.autoreverses = YES;
            animation.repeatCount = HUGE_VALF;
            [layer addAnimation:animation forKey:@"move"];
        }
    }
    return self;
}

@end

static std::map<std::string, std::shared_ptr<FrameStats>> keptFrames;

static NSString *compareKeptFrames() {
    auto legacy = keptFrames.find("legacy");
    auto modern = keptFrames.find("tgsck");
    if (legacy == keptFrames.end() || modern == keptFrames.end()) {
        return @"{\"parity\":\"missing frames\"}";
    }
    FrameStats *a = legacy->second.get();
    FrameStats *b = modern->second.get();
    std::lock_guard<std::mutex> guardA(a->lock);
    std::lock_guard<std::mutex> guardB(b->lock);
    if (a->lastWidth != b->lastWidth || a->lastHeight != b->lastHeight || a->lastI420.size() != b->lastI420.size()) {
        return [NSString stringWithFormat:@"{\"parity\":\"size mismatch\",\"legacy\":\"%dx%d\",\"tgsck\":\"%dx%d\"}", a->lastWidth, a->lastHeight, b->lastWidth, b->lastHeight];
    }
    size_t lumaSize = (size_t)a->lastWidth * a->lastHeight;
    double sums[2] = {0, 0};
    int maxima[2] = {0, 0};
    size_t over8[2] = {0, 0};
    size_t counts[2] = {0, 0};
    int rx = 0, ry = 0, rw = a->lastWidth, rh = a->lastHeight;
    NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
    NSUInteger rectIndex = [arguments indexOfObject:@"--parity-rect"];
    if (rectIndex != NSNotFound && rectIndex + 1 < arguments.count) {
        NSArray<NSString *> *parts = [arguments[rectIndex + 1] componentsSeparatedByString:@","];
        if (parts.count == 4) {
            rx = parts[0].intValue; ry = parts[1].intValue; rw = parts[2].intValue; rh = parts[3].intValue;
        }
    }
    int chromaWidth = (a->lastWidth + 1) / 2;
    int chromaHeight = (a->lastHeight + 1) / 2;
    for (int y = ry; y < ry + rh && y < a->lastHeight; y++) {
        for (int x = rx; x < rx + rw && x < a->lastWidth; x++) {
            size_t i = (size_t)y * a->lastWidth + x;
            int diff = abs((int)a->lastI420[i] - (int)b->lastI420[i]);
            sums[0] += diff; counts[0]++;
            maxima[0] = std::max(maxima[0], diff);
            if (diff > 8) over8[0]++;
        }
    }
    for (int plane = 0; plane < 2; plane++) {
        size_t base = lumaSize + (size_t)plane * chromaWidth * chromaHeight;
        for (int y = ry / 2; y < (ry + rh) / 2 && y < chromaHeight; y++) {
            for (int x = rx / 2; x < (rx + rw) / 2 && x < chromaWidth; x++) {
                size_t i = base + (size_t)y * chromaWidth + x;
                int diff = abs((int)a->lastI420[i] - (int)b->lastI420[i]);
                sums[1] += diff; counts[1]++;
                maxima[1] = std::max(maxima[1], diff);
                if (diff > 8) over8[1]++;
            }
        }
    }
    lumaSize = std::max<size_t>(counts[0], 1);
    size_t chromaSize = std::max<size_t>(counts[1], 1);
    return [NSString stringWithFormat:@"{\"parity\":\"%dx%d\",\"lumaMean\":%.3f,\"lumaMax\":%d,\"lumaOver8Percent\":%.3f,\"chromaMean\":%.3f,\"chromaMax\":%d,\"chromaOver8Percent\":%.3f}", a->lastWidth, a->lastHeight, sums[0] / lumaSize, maxima[0], over8[0] * 100.0 / lumaSize, sums[1] / chromaSize, maxima[1], over8[1] * 100.0 / chromaSize];
}

@interface PatternView : NSView
@end

@implementation PatternView

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    CGFloat half = floor(bounds.size.height / 2);
    int steps = 32;
    for (int i = 0; i < steps; i++) {
        CGFloat value = (CGFloat)i / (steps - 1);
        [[NSColor colorWithSRGBRed:value green:value blue:value alpha:1] setFill];
        NSRectFill(NSMakeRect(floor(bounds.size.width * i / steps), 0, ceil(bounds.size.width / steps) + 1, half));
    }
    NSArray<NSColor *> *colors = @[
        [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1], [NSColor colorWithSRGBRed:0 green:1 blue:0 alpha:1], [NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1],
        [NSColor colorWithSRGBRed:0 green:1 blue:1 alpha:1], [NSColor colorWithSRGBRed:1 green:0 blue:1 alpha:1], [NSColor colorWithSRGBRed:1 green:1 blue:0 alpha:1],
        [NSColor colorWithSRGBRed:0.9 green:0.7 blue:0.6 alpha:1], [NSColor colorWithSRGBRed:0.2 green:0.4 blue:0.7 alpha:1], [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:1]
    ];
    for (NSUInteger i = 0; i < colors.count; i++) {
        [colors[i] setFill];
        NSRectFill(NSMakeRect(floor(bounds.size.width * i / colors.count), half, ceil(bounds.size.width / colors.count) + 1, bounds.size.height - half));
    }
}

@end


@interface ScrollTextView : NSView
@end

@implementation ScrollTextView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.whiteColor.CGColor;
        NSMutableString *text = [NSMutableString string];
        for (int i = 0; i < 200; i++) {
            [text appendFormat:@"%03d Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore.\n", i];
        }
        CATextLayer *layer = [CATextLayer layer];
        layer.string = text;
        layer.fontSize = 14;
        layer.foregroundColor = NSColor.blackColor.CGColor;
        layer.contentsScale = 2.0;
        layer.wrapped = NO;
        layer.anchorPoint = CGPointMake(0, 1);
        layer.frame = CGRectMake(10, frameRect.size.height - 200 * 18, frameRect.size.width - 20, 200 * 18);
        [self.layer addSublayer:layer];
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position.y"];
        animation.fromValue = @(frameRect.size.height);
        animation.toValue = @(200 * 18);
        animation.duration = 30.0;
        animation.repeatCount = HUGE_VALF;
        [layer addAnimation:animation forKey:@"scroll"];
    }
    return self;
}

@end

@interface BenchController : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *scenarios;
@property (nonatomic, strong) NSMutableArray<NSString *> *results;
@property (nonatomic) double seconds;
@property (nonatomic, strong) NSString *outputPath;
@property (nonatomic, strong) NSWindow *busyWindow;
@property (nonatomic, strong) id<BenchPipeline> pipeline;
@end

@implementation BenchController

- (void)next {
    if (self.scenarios.count == 0) {
        if (!keptFrames.empty()) {
            NSString *parity = compareKeptFrames();
            printf("%s\n", parity.UTF8String);
            fflush(stdout);
            [self.results addObject:parity];
        }
        NSString *joined = [self.results componentsJoinedByString:@"\n"];
        if (self.outputPath != nil) {
            [joined writeToFile:self.outputPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [NSApp terminate:nil];
        return;
    }
    NSString *scenario = self.scenarios.firstObject;
    [self.scenarios removeObjectAtIndex:0];
    NSArray<NSString *> *parts = [scenario componentsSeparatedByString:@"-"];
    NSString *kind = parts.firstObject;
    BOOL captureWindow = [parts containsObject:@"window"];
    BOOL busy = [parts containsObject:@"busy"] || [parts containsObject:@"scroll"];
    BOOL scroll = [parts containsObject:@"scroll"];
    BOOL convert = [parts containsObject:@"i420"];
    auto stats = std::make_shared<FrameStats>();
    if ([parts containsObject:@"keep"]) {
        stats->keepLast = true;
        keptFrames[std::string(kind.UTF8String)] = stats;
    }
    if (busy) {
        NSRect frame = NSMakeRect(100, 100, 800, 500);
        self.busyWindow = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        self.busyWindow.releasedWhenClosed = NO;
        self.busyWindow.title = @"CaptureBench";
        NSRect bounds = NSMakeRect(0, 0, frame.size.width, frame.size.height);
        self.busyWindow.contentView = scroll ? [[ScrollTextView alloc] initWithFrame:bounds] : [[BusyView alloc] initWithFrame:bounds];
        [self.busyWindow orderFrontRegardless];
    }
    NSString *windowTitle = captureWindow ? @"CaptureBenchHost" : nil;
    if ([kind isEqualToString:@"legacy"]) {
        self.pipeline = [[LegacyPipeline alloc] initWithStats:stats windowTitle:windowTitle];
    } else if ([kind isEqualToString:@"sck"]) {
        if (@available(macOS 12.3, *)) {
            self.pipeline = [[SCKPipeline alloc] initWithStats:stats convertToI420:convert windowTitle:windowTitle];
        }
    } else if ([kind isEqualToString:@"tgsck"]) {
        if (@available(macOS 12.3, *)) {
            self.pipeline = [[TGSCKPipeline alloc] initWithStats:stats windowTitle:windowTitle];
        }
    } else if ([kind hasPrefix:@"thumb"]) {
        if (@available(macOS 12.3, *)) {
            currentEncoderStats = std::make_shared<EncoderStats>();
            self.pipeline = [[ThumbnailEncoderPipeline alloc] initWithStats:stats encoderStats:currentEncoderStats maxFramerate:[kind substringFromIndex:5].doubleValue];
        }
    } else {
        self.pipeline = nil;
    }
    [self.pipeline start];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        int framesStart = stats->frames;
        std::shared_ptr<EncoderStats> encoderStats = currentEncoderStats;
        if (encoderStats) {
            encoderStats->reset();
        }
        double cpuStart = cpuSeconds();
        double mainStart = mainThreadSeconds();
        double wsStart = windowServerSeconds();
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        __block std::vector<int> gpu;
        __block BOOL sampling = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            while (sampling) {
                int value = gpuUtilization();
                dispatch_sync(dispatch_get_main_queue(), ^{
                    gpu.push_back(value);
                });
                usleep(500000);
            }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            sampling = NO;
            double duration = CFAbsoluteTimeGetCurrent() - start;
            double gpuAverage = 0;
            for (int value : gpu) {
                gpuAverage += value;
            }
            gpuAverage = gpu.empty() ? -1 : gpuAverage / gpu.size();
            NSString *line = [NSString stringWithFormat:@"{\"scenario\":\"%@\",\"seconds\":%.1f,\"fps\":%.1f,\"size\":\"%dx%d\",\"appCores\":%.3f,\"mainThreadPercent\":%.2f,\"windowServerCores\":%.3f,\"gpuPercent\":%.1f}", scenario, duration, (stats->frames - framesStart) / duration, stats->width.load(), stats->height.load(), (cpuSeconds() - cpuStart) / duration, (mainThreadSeconds() - mainStart) / duration * 100, (windowServerSeconds() - wsStart) / duration, gpuAverage];
            if (encoderStats) {
                int input = encoderStats->inputFrames.load();
                int encoded = encoderStats->encodedFrames.load();
                line = [NSString stringWithFormat:@"%@,\"encoderInputFps\":%.1f,\"encodedFps\":%.1f,\"skippedPercent\":%.1f,\"kbps\":%.1f,\"skipWarnings\":%d,\"openH264Logs\":%d}", [line substringToIndex:line.length - 1], input / duration, encoded / duration, input > 0 ? (input - encoded) * 100.0 / input : 0, encoderStats->encodedBytes.load() * 8.0 / 1000.0 / duration, encoderStats->skipWarnings.load(), encoderStats->openH264Messages.load()];
                currentEncoderStats = nullptr;
            }
            printf("%s\n", line.UTF8String);
            fflush(stdout);
            [self.results addObject:line];
            [self.pipeline stop];
            self.pipeline = nil;
            [self.busyWindow orderOut:nil];
            self.busyWindow = nil;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self next];
            });
        });
    });
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        mainThreadPort = mach_thread_self();
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--host-window"]) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            BOOL fullscreen = [[[NSProcessInfo processInfo] arguments] containsObject:@"--fullscreen"];
            NSRect frame = fullscreen ? NSScreen.mainScreen.frame : NSMakeRect(160, 160, 800, 500);
            NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:fullscreen ? NSWindowStyleMaskBorderless : NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            if (fullscreen) {
                window.level = NSScreenSaverWindowLevel;
            }
            window.releasedWhenClosed = NO;
            window.title = @"CaptureBenchHost";
            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--pattern"]) {
                window.contentView = [[PatternView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
            } else {
                window.contentView = [[BusyView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
            }
            [window orderFrontRegardless];
            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--lifecycle"]) {
                window.styleMask |= NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskClosable;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    fprintf(stderr, "CaptureBenchHost: hide\n");
                    [window orderOut:nil];
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 9 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    fprintf(stderr, "CaptureBenchHost: show\n");
                    [window orderFrontRegardless];
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 14 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    fprintf(stderr, "CaptureBenchHost: exit\n");
                    exit(0);
                });
            }
            if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--resize"]) {
                __block int step = 0;
                [NSTimer scheduledTimerWithTimeInterval:4.0 repeats:YES block:^(NSTimer *timer) {
                    step += 1;
                    NSRect current = window.frame;
                    current.size = (step % 2) == 1 ? NSMakeSize(500, 360) : NSMakeSize(800, 500);
                    [window setFrame:current display:YES];
                }];
            }
            [NSApp run];
            return 0;
        }
        BenchController *controller = [[BenchController alloc] init];
        controller.scenarios = [NSMutableArray arrayWithArray:@[@"legacy-static", @"sck-static", @"legacy-busy", @"sck-busy", @"sck-i420-busy"]];
        controller.results = [NSMutableArray array];
        controller.seconds = 15;
        NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
        for (NSUInteger i = 1; i + 1 < arguments.count; i += 2) {
            if ([arguments[i] isEqualToString:@"--scenarios"]) {
                controller.scenarios = [NSMutableArray arrayWithArray:[arguments[i + 1] componentsSeparatedByString:@","]];
            } else if ([arguments[i] isEqualToString:@"--seconds"]) {
                controller.seconds = arguments[i + 1].doubleValue;
            } else if ([arguments[i] isEqualToString:@"--output"]) {
                controller.outputPath = arguments[i + 1];
            }
        }
        if (@available(macOS 10.15, *)) {
            if (!CGPreflightScreenCaptureAccess()) {
                printf("{\"error\":\"screen recording permission missing\"}\n");
                fflush(stdout);
                CGRequestScreenCaptureAccess();
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller next];
        });
        [NSApp run];
    }
    return 0;
}
