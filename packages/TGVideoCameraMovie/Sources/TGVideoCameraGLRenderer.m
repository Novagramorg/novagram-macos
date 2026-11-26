#import "TGVideoCameraGLRenderer.h"
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <AppKit/AppKit.h>
#import "TGPaintShader.h"


@interface TGVideoCameraGLRenderer ()
{
    CGLContextObj _currentContext;
    
    CVOpenGLTextureCacheRef _textureCache;
    CVOpenGLTextureCacheRef _prevTextureCache;
    CVOpenGLTextureCacheRef _renderTextureCache;
    CVPixelBufferPoolRef _bufferPool;
    CMFormatDescriptionRef _outputFormatDescription;
    
    CVPixelBufferRef _previousPixelBuffer;
    
    TGPaintShader *_shader;
    GLint _frameUniform;
    GLint _previousFrameUniform;
    GLint _opacityUniform;
    GLint _aspectRatioUniform;
    GLint _noMirrorUniform;
    GLint _rotationAngleUniform;
    GLint _watermarkUniform;
    GLint _planeUniform;
    GLint _decoratedUniform;
    GLint _planeFrameUniform;
    GLint _planeFrameCountUniform;
    GLuint _offscreenBufferHandle;
    
    CGImageRef _watermarkImage;
    CGImageRef _planeFramesImage;
    NSInteger _planeFrameCount;
    GLuint _watermarkTexture;
    GLuint _planeTexture;
    
    CGFloat _aspectRatio;
    float _textureVertices[8];
}

@end

static GLuint TGCreateTextureWithImage(CGImageRef image)
{
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL)
        return 0;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)width, (GLsizei)height, 0, GL_BGRA, GL_UNSIGNED_BYTE, data.bytes);
    glBindTexture(GL_TEXTURE_2D, 0);
    return texture;
}

@implementation TGVideoCameraGLRenderer

- (instancetype)init
{
    self = [super init];
    if ( self )
    {
        [self setupOffscreenRenderContext];
    }
    return self;
}

- (void)setupOffscreenRenderContext
{
    CGDirectDisplayID display = CGMainDisplayID (); // 1
    CGOpenGLDisplayMask myDisplayMask = CGDisplayIDToOpenGLDisplayMask (display); // 2
    
    // Check capabilities of display represented by display mask
    CGLPixelFormatAttribute attribs[13] = {
        // kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core, // This sets the context to 3.2
        kCGLPFAColorSize,     (CGLPixelFormatAttribute)24,
        kCGLPFAAlphaSize,     (CGLPixelFormatAttribute)8,
        kCGLPFAAccelerated,
        kCGLPFADoubleBuffer,
        kCGLPFASampleBuffers, (CGLPixelFormatAttribute)1,
        kCGLPFASamples,       (CGLPixelFormatAttribute)4,
        kCGLPFAAllowOfflineRenderers,
        (CGLPixelFormatAttribute)0
    };
    CGLPixelFormatObj pixelFormat = NULL;
    GLint numPixelFormats = 0;
    CGLContextObj myCGLContext = 0;
    
    CGLChoosePixelFormat (attribs, &pixelFormat, &numPixelFormats); // 5
    if (pixelFormat) {
        CGLCreateContext (pixelFormat, NULL, &myCGLContext); // 6
        CGLDestroyPixelFormat (pixelFormat); // 7
        //CGLSetCurrentContext (myCGLContext); // 8
        _currentContext = myCGLContext;
        CGLRetainContext(_currentContext);
    }
    
}

- (void)dealloc
{
    CGLSetCurrentContext(nil);
    CGLReleaseContext(_currentContext);
    [self deleteBuffers];
    CGImageRelease(_watermarkImage);
    CGImageRelease(_planeFramesImage);
}

- (void)setDecorationWatermark:(CGImageRef)watermark planeFrames:(CGImageRef)planeFrames planeFrameCount:(NSInteger)planeFrameCount
{
    CGImageRelease(_watermarkImage);
    CGImageRelease(_planeFramesImage);
    _watermarkImage = CGImageRetain(watermark);
    _planeFramesImage = CGImageRetain(planeFrames);
    _planeFrameCount = planeFrameCount;
}

- (bool)prepareForInputWithFormatDescription:(CMFormatDescriptionRef)inputFormatDescription outputRetainedBufferCountHint:(size_t)outputRetainedBufferCountHint
{
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(inputFormatDescription);
    CGFloat minSide = MIN(dimensions.width, dimensions.height);
    CGFloat maxSide = MAX(dimensions.width, dimensions.height);
    CGSize outputSize = CGSizeMake(minSide, minSide);
    
    _aspectRatio = minSide / maxSide;
    [self updateTextureVertices];
    
    [self deleteBuffers];
    bool success = [self initializeBuffersWithOutputSize:outputSize retainedBufferCountHint:outputRetainedBufferCountHint];
    return success && _outputFormatDescription != NULL;
}

- (void)setOrientation:(AVCaptureVideoOrientation)orientation
{
    _orientation = orientation;
    [self updateTextureVertices];
}

- (void)setMirror:(bool)mirror
{
    _mirror = mirror;
    [self updateTextureVertices];
}

- (void)updateTextureVertices
{
    GLfloat centerOffset = (GLfloat)((1.0f - _aspectRatio) / 2.0f);
    
    switch (_orientation)
    {
        case AVCaptureVideoOrientationPortrait:
            if (!_mirror)
            {
                _textureVertices[0] = centerOffset;
                _textureVertices[1] = 1.0f;
                _textureVertices[2] = centerOffset;
                _textureVertices[3] = 0.0f;
                _textureVertices[4] = (1.0f - centerOffset);
                _textureVertices[5] = 1.0f;
                _textureVertices[6] = (1.0f - centerOffset);
                _textureVertices[7] = 0.0f;
            }
            else
            {
                _textureVertices[0] = centerOffset;
                _textureVertices[1] = 0.0f;
                _textureVertices[2] = (1.0f - centerOffset);
                _textureVertices[3] = 0.0f;
                _textureVertices[4] = centerOffset;
                _textureVertices[5] = 1.0f;
                _textureVertices[6] = (1.0f - centerOffset);
                _textureVertices[7] = 1.0f;
            }
            break;
            
        case AVCaptureVideoOrientationLandscapeLeft:
            if (!_mirror)
            {
                _textureVertices[0] = (1.0f - centerOffset);
                _textureVertices[1] = 1.0f;
                _textureVertices[2] = centerOffset;
                _textureVertices[3] = 1.0f;
                _textureVertices[4] = (1.0f - centerOffset);
                _textureVertices[5] = 0.0f;
                _textureVertices[6] = centerOffset;
                _textureVertices[7] = 0.0f;
            }
            else
            {
                _textureVertices[0] = centerOffset;
                _textureVertices[1] = 0.0f;
                _textureVertices[2] = (1.0f - centerOffset);
                _textureVertices[3] = 0.0f;
                _textureVertices[4] = centerOffset;
                _textureVertices[5] = 1.0f;
                _textureVertices[6] = (1.0f - centerOffset);
                _textureVertices[7] = 1.0f;
            }
            break;
            
        case AVCaptureVideoOrientationLandscapeRight:
            if (!_mirror)
            {
                _textureVertices[0] = centerOffset;
                _textureVertices[1] = 0.0f;
                _textureVertices[2] = (1.0f - centerOffset);
                _textureVertices[3] = 0.0f;
                _textureVertices[4] = centerOffset;
                _textureVertices[5] = 1.0f;
                _textureVertices[6] = (1.0f - centerOffset);
                _textureVertices[7] = 1.0f;
            }
            else
            {
                _textureVertices[0] = (1.0f - centerOffset);
                _textureVertices[1] = 1.0f;
                _textureVertices[2] = centerOffset;
                _textureVertices[3] = 1.0f;
                _textureVertices[4] = (1.0f - centerOffset);
                _textureVertices[5] = 0.0f;
                _textureVertices[6] = centerOffset;
                _textureVertices[7] = 0.0f;
            }
            break;
            
        default:
            break;
    }
}

- (void)reset
{
    [self deleteBuffers];
}

- (bool)hasPreviousPixelbuffer
{
    return _previousPixelBuffer != NULL;
}

- (void)setPreviousPixelBuffer:(CVPixelBufferRef)previousPixelBuffer
{
    if (_previousPixelBuffer != NULL)
    {
        CFRelease(_previousPixelBuffer);
        _previousPixelBuffer = NULL;
    }
    
    _previousPixelBuffer = previousPixelBuffer;
    if (_previousPixelBuffer != NULL)
        CFRetain(_previousPixelBuffer);
}

- (CVPixelBufferRef)copyRenderedPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    
    
    static const GLfloat squareVertices[] =
    {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    if (_offscreenBufferHandle == 0)
        return NULL;
    
    if (pixelBuffer == NULL)
        return NULL;
    
    CGLContextObj oldContext = CGLGetCurrentContext();
    
    if (oldContext != _currentContext) {
        CGLSetCurrentContext(_currentContext);
    }
    CGLLockContext(_currentContext);
    
    
    const CMVideoDimensions dstDimensions = CMVideoFormatDescriptionGetDimensions(_outputFormatDescription);
    
    
    
    CVReturn err = noErr;
    CVOpenGLTextureRef prevTexture = NULL;
    CVOpenGLTextureRef dstTexture = NULL;
    CVPixelBufferRef dstPixelBuffer = NULL;
    
    

    
    bool hasPreviousTexture = false;
    if (_previousPixelBuffer != NULL)
    {
        err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _prevTextureCache, _previousPixelBuffer, NULL, &prevTexture);
        
        if (!prevTexture || err)
            goto bail;
        
        hasPreviousTexture = true;
    }
    
    
    
    err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _bufferPool, &dstPixelBuffer);
    if (err || !dstPixelBuffer)
    {
        CVOpenGLTextureCacheFlush(_renderTextureCache, 0);
        err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _bufferPool, &dstPixelBuffer);
    }
    
    
    if (err)
        goto bail;
    
    err = CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _renderTextureCache, dstPixelBuffer, NULL, &dstTexture);
    
    
    if (!dstTexture || err)
        goto bail;
    
    // glBegin(GL_TRIANGLE_STRIP);
    
    
    
    glBindFramebuffer(GL_FRAMEBUFFER, _offscreenBufferHandle);
    glViewport(0, 0, dstDimensions.width, dstDimensions.height);
    glUseProgram(_shader.program);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(CVOpenGLTextureGetTarget(dstTexture), CVOpenGLTextureGetName(dstTexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, CVOpenGLTextureGetTarget(dstTexture), CVOpenGLTextureGetName(dstTexture), 0);
    

    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    int width = CVPixelBufferGetWidth(pixelBuffer);
    int height = CVPixelBufferGetHeight(pixelBuffer);
    int stride=CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    glPixelStorei(GL_UNPACK_ROW_LENGTH, stride/4);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, CVPixelBufferGetBaseAddress(pixelBuffer));
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    glGenerateMipmap(GL_TEXTURE_2D);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    
    if (hasPreviousTexture)
    {
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(CVOpenGLTextureGetTarget(prevTexture), CVOpenGLTextureGetName(prevTexture));
        glUniform1i(_previousFrameUniform, 2);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    glVertexAttribPointer(0, 2, GL_FLOAT, 0, 0, squareVertices);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 2, GL_FLOAT, 0, 0, _textureVertices);
    glEnableVertexAttribArray(1);
    
    glUniform1f(_opacityUniform, (GLfloat)_opacity);
    glUniform1f(_aspectRatioUniform, (GLfloat)(1.0f / _aspectRatio));
    glUniform1f(_noMirrorUniform, (GLfloat)(_mirror ? 1 : -1));
    glUniform1f(_rotationAngleUniform, (GLfloat)(-90.0/180.0*M_PI));
    
    bool decorated = _watermarkTexture != 0 && _planeTexture != 0 && _planeFrameCount > 0;
    glUniform1f(_decoratedUniform, decorated ? 1.0f : 0.0f);
    if (decorated)
    {
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, _watermarkTexture);
        glUniform1i(_watermarkUniform, 3);
        
        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_2D, _planeTexture);
        glUniform1i(_planeUniform, 4);
        
        glUniform1f(_planeFrameUniform, (GLfloat)(_decorationFrame % _planeFrameCount));
        glUniform1f(_planeFrameCountUniform, (GLfloat)_planeFrameCount);
        
        glActiveTexture(GL_TEXTURE0);
    }
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindTexture(GL_TEXTURE_2D, 0);
    
    if (hasPreviousTexture)
        glBindTexture(CVOpenGLTextureGetTarget(prevTexture), 0);
    glBindTexture(CVOpenGLTextureGetTarget(dstTexture), 0);
    
    
    glFlush();
    
    
    
bail:
    CGLUnlockContext(_currentContext);
    if (oldContext != _currentContext) {
        CGLSetCurrentContext(oldContext);
    }
    
    
    if (prevTexture)
        CFRetain(prevTexture);
    
    if (dstTexture)
        CFRelease(dstTexture);
    
    return dstPixelBuffer;
}

- (CMFormatDescriptionRef)outputFormatDescription
{
    return _outputFormatDescription;
}

- (bool)initializeBuffersWithOutputSize:(CGSize)outputSize retainedBufferCountHint:(size_t)clientRetainedBufferCountHint
{
    bool success = true;
    
    
    CGLContextObj oldContext = CGLGetCurrentContext();
    if (oldContext != _currentContext) {
        CGLSetCurrentContext(_currentContext);
    }
    CGLLockContext(_currentContext);
    
    
    glDisable(GL_DEPTH_TEST);
    
    glGenFramebuffers(1, &_offscreenBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _offscreenBufferHandle);
    
    
    
    CVReturn err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, _currentContext, CGLGetPixelFormat(_currentContext), NULL, &_textureCache);
    if (err)
    {
        success = false;
        goto bail;
    }
    
    err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, _currentContext, CGLGetPixelFormat(_currentContext), NULL, &_prevTextureCache);
    if (err)
    {
        success = false;
        goto bail;
    }
    
    err = CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, _currentContext, CGLGetPixelFormat(_currentContext), NULL, &_renderTextureCache);
    if (err)
    {
        success = false;
        goto bail;
    }
    
    _shader = [[TGPaintShader alloc] initWithVertexShader:@"VideoMessage" fragmentShader:@"VideoMessage" attributes:@[ @"inPosition", @"inTexcoord" ] uniforms:@[ @"texture", @"previousTexture", @"opacity", @"aspectRatio", @"noMirror", @"rotationAngle", @"watermarkTexture", @"planeTexture", @"decorated", @"planeFrame", @"planeFrameCount" ]];
    
    _frameUniform = [_shader uniformForKey:@"texture"];
    _previousFrameUniform = [_shader uniformForKey:@"previousTexture"];
    _opacityUniform = [_shader uniformForKey:@"opacity"];
    _aspectRatioUniform = [_shader uniformForKey:@"aspectRatio"];
    _noMirrorUniform = [_shader uniformForKey:@"noMirror"];
    _rotationAngleUniform = [_shader uniformForKey:@"rotationAngle"];
    _watermarkUniform = [_shader uniformForKey:@"watermarkTexture"];
    _planeUniform = [_shader uniformForKey:@"planeTexture"];
    _decoratedUniform = [_shader uniformForKey:@"decorated"];
    _planeFrameUniform = [_shader uniformForKey:@"planeFrame"];
    _planeFrameCountUniform = [_shader uniformForKey:@"planeFrameCount"];
    
    if (_watermarkImage != NULL && _planeFramesImage != NULL)
    {
        _watermarkTexture = TGCreateTextureWithImage(_watermarkImage);
        _planeTexture = TGCreateTextureWithImage(_planeFramesImage);
    }
    
    size_t maxRetainedBufferCount = clientRetainedBufferCountHint + 1;
    _bufferPool = [TGVideoCameraGLRenderer createPixelBufferPoolWithWidth:(int32_t)outputSize.width height:(int32_t)outputSize.height pixelFormat:kCVPixelFormatType_32BGRA maxBufferCount:(int32_t)maxRetainedBufferCount];
    
    if (!_bufferPool)
    {
        success = NO;
        goto bail;
    }
    
    CMFormatDescriptionRef outputFormatDescription = NULL;
    CVPixelBufferRef testPixelBuffer = NULL;
    CVReturn testErr = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _bufferPool, &testPixelBuffer);
    if (testErr || !testPixelBuffer)
    {
        success = false;
        goto bail;
    }
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, testPixelBuffer, &outputFormatDescription);
    _outputFormatDescription = outputFormatDescription;
    CFRelease( testPixelBuffer );
    
bail:
    if (!success)
        [self deleteBuffers];
    
    CGLUnlockContext(_currentContext);
    if (oldContext != _currentContext) {
        CGLSetCurrentContext(oldContext);
    }
    
    
    return success;
}

- (void)deleteBuffers
{
    CGLContextObj oldContext = CGLGetCurrentContext();
    if (oldContext != _currentContext) {
        CGLSetCurrentContext(_currentContext);
    }
    CGLLockContext(_currentContext);
    
    
    if (_offscreenBufferHandle)
    {
        glDeleteFramebuffers(1, &_offscreenBufferHandle);
        _offscreenBufferHandle = 0;
    }
    
    if (_shader)
    {
        [_shader cleanResources];
        _shader = nil;
    }
    
    if (_watermarkTexture)
    {
        glDeleteTextures(1, &_watermarkTexture);
        _watermarkTexture = 0;
    }
    
    if (_planeTexture)
    {
        glDeleteTextures(1, &_planeTexture);
        _planeTexture = 0;
    }
    
    if (_textureCache)
    {
        CFRelease(_textureCache);
        _textureCache = 0;
    }
    
    if (_prevTextureCache)
    {
        CFRelease(_prevTextureCache);
        _prevTextureCache = 0;
    }
    
    if (_renderTextureCache)
    {
        CFRelease(_renderTextureCache);
        _renderTextureCache = 0;
    }
    
    if (_bufferPool)
    {
        CFRelease(_bufferPool);
        _bufferPool = NULL;
    }
    
    if (_outputFormatDescription)
    {
        CFRelease(_outputFormatDescription);
        _outputFormatDescription = NULL;
    }
    
    CGLUnlockContext(_currentContext);
    
    if (oldContext != _currentContext) {
        CGLSetCurrentContext(oldContext);
    }
    
    
    
}

+ (CVPixelBufferPoolRef)createPixelBufferPoolWithWidth:(int32_t)width height:(int32_t)height pixelFormat:(FourCharCode)pixelFormat maxBufferCount:(int32_t) maxBufferCount
{
    CVPixelBufferPoolRef outputPool = NULL;
    
    NSDictionary *sourcePixelBufferOptions = @
    {
        (id)kCVPixelBufferPixelFormatTypeKey : @(pixelFormat),
        (id)kCVPixelBufferWidthKey : @(width),
        (id)kCVPixelBufferHeightKey : @(height),
        (id)kCVPixelFormatOpenGLCompatibility : @true,
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{ }
    };
    
    NSDictionary *pixelBufferPoolOptions = @{ (id)kCVPixelBufferPoolMinimumBufferCountKey : @(maxBufferCount) };
    CVPixelBufferPoolCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)pixelBufferPoolOptions, (__bridge CFDictionaryRef)sourcePixelBufferOptions, &outputPool);
    
    return outputPool;
}

@end

