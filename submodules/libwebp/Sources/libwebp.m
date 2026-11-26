#import "libwebp.h"
#import <AppKit/AppKit.h>
#import "decode.h"
#import "encode.h"
#import "demux.h"
#import "mux.h"
#import "WebPImageCoder.h"
NSImage * _Nullable convertFromWebP(NSData *imgData) {
   
    if (imgData == nil) {
        return nil;
    }
    WebPImageDecoder *decoder = [WebPImageDecoder decoderWithData:imgData scale: 2];
    
    return [decoder frameAtIndex:0 decodeForDisplay:YES].image;
    
}

NSData * _Nullable convertToWebP(CGImageRef image, CGFloat quality) {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        return nil;
    }
    size_t bytesPerRow = width * 4;
    uint8_t *rgba = calloc(height * bytesPerRow, 1);
    if (rgba == NULL) {
        return nil;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(rgba, width, height, 8, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        free(rgba);
        return nil;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    
    for (size_t i = 0; i < width * height; i++) {
        uint8_t *pixel = rgba + i * 4;
        uint8_t alpha = pixel[3];
        if (alpha != 0 && alpha != 255) {
            for (int c = 0; c < 3; c++) {
                pixel[c] = (uint8_t)MIN(255, (pixel[c] * 255 + alpha / 2) / alpha);
            }
        }
    }
    
    uint8_t *output = NULL;
    size_t size = WebPEncodeRGBA(rgba, (int)width, (int)height, (int)bytesPerRow, (float)quality, &output);
    free(rgba);
    if (size == 0 || output == NULL) {
        return nil;
    }
    NSData *data = [NSData dataWithBytes:output length:size];
    WebPFree(output);
    return data;
}
