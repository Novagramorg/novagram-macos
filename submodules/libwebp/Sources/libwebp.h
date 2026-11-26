#import <Foundation/Foundation.h>

//! Project version number for libwebp.
FOUNDATION_EXPORT double libwebpVersionNumber;

//! Project version string for libwebp.
FOUNDATION_EXPORT const unsigned char libwebpVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <libwebp/PublicHeader.h>

#import "WebPImageCoder.h"


NSImage * _Nullable  convertFromWebP(NSData * _Nullable data);

NSData * _Nullable convertToWebP(CGImageRef _Nonnull image, CGFloat quality);

