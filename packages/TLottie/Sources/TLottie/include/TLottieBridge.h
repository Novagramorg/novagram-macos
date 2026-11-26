#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLottieBridge : NSObject
- (instancetype _Nullable)initWithJson:(NSString *)json;
- (void)renderFrameWithIndex:(int32_t)index into:(uint8_t *)buffer width:(int32_t)width height:(int32_t)height bytesPerRow:(int32_t)bytesPerRow;
- (int32_t)startFrame;
- (int32_t)endFrame;
- (int32_t)fps;
- (void)setColor:(NSColor *)color forKeyPath:(NSString *)keyPath;
@end

NS_ASSUME_NONNULL_END
