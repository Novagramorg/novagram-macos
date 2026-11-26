#import <AppKit/AppKit.h>
#import <malloc/malloc.h>
#include "jpeglib.h"

static size_t peakInUse = 0;
static void sample(void) { malloc_statistics_t s; malloc_zone_statistics(NULL, &s); if (s.size_in_use > peakInUse) peakInUse = s.size_in_use; }

static NSData *finish(struct jpeg_compress_struct *cinfo, uint8_t **outBuffer, unsigned long *outSize) {
    jpeg_finish_compress(cinfo);
    sample();
    NSData *result = [[NSData alloc] initWithBytes:*outBuffer length:*outSize];
    jpeg_destroy_compress(cinfo);
    free(*outBuffer);
    return result;
}

static void setup(struct jpeg_compress_struct *cinfo, struct jpeg_error_mgr *jerr, uint8_t **outBuffer, unsigned long *outSize, int width, int height, int components, J_COLOR_SPACE space, int quality) {
    cinfo->err = jpeg_std_error(jerr);
    jpeg_create_compress(cinfo);
    jpeg_mem_dest(cinfo, outBuffer, outSize);
    cinfo->image_width = (uint32_t)width;
    cinfo->image_height = (uint32_t)height;
    cinfo->input_components = components;
    cinfo->in_color_space = space;
    jpeg_c_set_int_param(cinfo, JINT_COMPRESS_PROFILE, JCP_FASTEST);
    jpeg_set_defaults(cinfo);
    cinfo->arith_code = FALSE;
    cinfo->dct_method = JDCT_ISLOW;
    cinfo->optimize_coding = TRUE;
    jpeg_set_quality(cinfo, quality, 1);
    jpeg_simple_progression(cinfo);
    jpeg_start_compress(cinfo, 1);
}

static uint8_t *drawTarget(CGImageRef sourceImage, int width, int height, int *bytesPerRow) {
    int targetBytesPerRow = ((4 * (int)width) + 15) & (~15);
    uint8_t *targetMemory = malloc((int)(targetBytesPerRow * height));
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef targetContext = CGBitmapContextCreate(targetMemory, width, height, 8, targetBytesPerRow, colorSpace, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(colorSpace);
    CGContextSetFillColorWithColor(targetContext, [NSColor whiteColor].CGColor);
    CGContextFillRect(targetContext, CGRectMake(0, 0, width, height));
    CGContextDrawImage(targetContext, CGRectMake(0, 0, width, height), sourceImage);
    CGContextRelease(targetContext);
    *bytesPerRow = targetBytesPerRow;
    return targetMemory;
}

static NSData *compressOld(CGImageRef sourceImage, int quality) {
    int width = (int)CGImageGetWidth(sourceImage), height = (int)CGImageGetHeight(sourceImage);
    int targetBytesPerRow;
    uint8_t *targetMemory = drawTarget(sourceImage, width, height, &targetBytesPerRow);
    int bufferBytesPerRow = ((3 * (int)width) + 15) & (~15);
    uint8_t *buffer = malloc(bufferBytesPerRow * height);
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            uint32_t *color = ((uint32_t *)&targetMemory[y * targetBytesPerRow + x * 4]);
            buffer[y * bufferBytesPerRow + x * 3 + 0] = ((*color >> 16) & 0xff);
            buffer[y * bufferBytesPerRow + x * 3 + 1] = ((*color >> 8) & 0xff);
            buffer[y * bufferBytesPerRow + x * 3 + 2] = (*color & 0xff);
        }
    }
    sample();
    free(targetMemory);
    struct jpeg_compress_struct cinfo; struct jpeg_error_mgr jerr; uint8_t *outBuffer = NULL; unsigned long outSize = 0;
    setup(&cinfo, &jerr, &outBuffer, &outSize, width, height, 3, JCS_RGB, quality);
    JSAMPROW rowPointer[1];
    while (cinfo.next_scanline < cinfo.image_height) {
        rowPointer[0] = (JSAMPROW)(buffer + cinfo.next_scanline * bufferBytesPerRow);
        jpeg_write_scanlines(&cinfo, rowPointer, 1);
    }
    NSData *result = finish(&cinfo, &outBuffer, &outSize);
    free(buffer);
    return result;
}

static NSData *compressNew(CGImageRef sourceImage, int quality) {
    int width = (int)CGImageGetWidth(sourceImage), height = (int)CGImageGetHeight(sourceImage);
    int targetBytesPerRow;
    uint8_t *targetMemory = drawTarget(sourceImage, width, height, &targetBytesPerRow);
    sample();
    struct jpeg_compress_struct cinfo; struct jpeg_error_mgr jerr; uint8_t *outBuffer = NULL; unsigned long outSize = 0;
    setup(&cinfo, &jerr, &outBuffer, &outSize, width, height, 4, JCS_EXT_BGRX, quality);
    JSAMPROW rowPointer[1];
    while (cinfo.next_scanline < cinfo.image_height) {
        rowPointer[0] = (JSAMPROW)(targetMemory + cinfo.next_scanline * targetBytesPerRow);
        jpeg_write_scanlines(&cinfo, rowPointer, 1);
    }
    NSData *result = finish(&cinfo, &outBuffer, &outSize);
    free(targetMemory);
    return result;
}

static CGImageRef makePhoto(int w, int h) {
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, CGColorSpaceCreateWithName(kCGColorSpaceSRGB), kCGImageAlphaPremultipliedLast);
    for (int j = 0; j < 3000; j++) {
        CGContextSetRGBFillColor(ctx, (j % 255) / 255.0, ((j * 7) % 255) / 255.0, ((j * 13) % 255) / 255.0, 0.8);
        CGContextFillEllipseInRect(ctx, CGRectMake((j * 37) % w, (j * 53) % h, 10 + j % 120, 8 + j % 90));
    }
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return image;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        int w = atoi(argv[2]), h = atoi(argv[3]);
        CGImageRef image = makePhoto(w, h);
        task_vm_info_data_t info; mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
        uint64_t before = info.phys_footprint;
        NSData *data = strcmp(argv[1], "old") == 0 ? compressOld(image, 87) : compressNew(image, 87);
        count = TASK_VM_INFO_COUNT;
        task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
        printf("%s %dx%d: peak footprint +%llu KB during compression (%lu bytes out)\n", argv[1], w, h, (info.ledger_phys_footprint_peak - before) / 1024, (unsigned long)data.length);
        CGImageRelease(image);
    }
    return 0;
}
