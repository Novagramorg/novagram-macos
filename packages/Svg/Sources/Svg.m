#import "Svg.h"
#import <Cocoa/Cocoa.h>
#import "nanosvg.h"
#import <QuartzCore/QuartzCore.h>

CGSize aspectFillSize(CGSize size, CGSize bounds) {
    CGFloat scale = MAX(bounds.width / MAX(1.0, size.width), bounds.height / MAX(1.0, size.height));
    return CGSizeMake(floor(size.width * scale), floor(size.height * scale));
}

/// Describe a slot rectangle in SVG coordinates
typedef struct {
    CGRect rect;   // x,y,width,height in SVG user space (pre-CTM)
} GiftSlot;

static inline BOOL SvgIsMagentaFill(NSString * _Nullable fillStr) {
    if (fillStr.length == 0) return NO;
    NSRange r1 = [fillStr rangeOfString:@"#ff00ff" options:NSCaseInsensitiveSearch];
    NSRange r2 = [fillStr rangeOfString:@"#f0f"    options:NSCaseInsensitiveSearch];
    return (r1.location != NSNotFound) || (r2.location != NSNotFound);
}

static inline double SvgParseDouble(NSString * _Nullable s) {
    return s ? s.doubleValue : 0.0;
}

@interface SvgXMLParsingDelegate : NSObject <NSXMLParserDelegate> {
    NSString *_elementName;
    NSMutableString *_currentStyleString;
    NSInteger _giftGroupDepth;     // nesting depth counter for <g id="GiftPatterns">
}
@property (nonatomic, readonly) NSMutableDictionary<NSString*, NSString*> *styles;
@property (nonatomic, readonly) NSMutableArray<NSValue*> *slots; // NSValue-wrapped GiftSlot
@end

@implementation SvgXMLParsingDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _styles = [[NSMutableDictionary alloc] init];
        _slots = [[NSMutableArray alloc] init];
        _giftGroupDepth = 0;
    }
    return self;
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser
 didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
    attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    _elementName = elementName;

    // Track entering GiftPatterns group (supports nesting)
    if ([elementName isEqualToString:@"g"]) {
        NSString *gid = attributeDict[@"id"];
        if (gid && [gid isEqualToString:@"GiftPatterns"]) {
            _giftGroupDepth += 1;
        } else if (_giftGroupDepth > 0) {
            // nested <g> inside GiftPatterns — keep depth so we know we're still inside
            _giftGroupDepth += 1;
        }
    }

    // Start of <style> — reset the buffer
    if ([_elementName isEqualToString:@"style"]) {
        _currentStyleString = [NSMutableString new];
    }

    // If inside GiftPatterns, capture magenta <rect> as a slot
    if (_giftGroupDepth > 0 && [elementName isEqualToString:@"rect"]) {
        // 1) Inspect fill from attribute
        NSString *fillAttr = attributeDict[@"fill"];

        // 2) Or from style="..."
        NSString *styleAttr = attributeDict[@"style"];
        NSString *fillFromStyle = nil;
        if (styleAttr.length > 0) {
            // very small parse: look for "fill:" then read until ';' or end
            NSRange fr = [styleAttr rangeOfString:@"fill:" options:NSCaseInsensitiveSearch];
            if (fr.location != NSNotFound) {
                NSUInteger start = fr.location + fr.length;
                NSRange sub = NSMakeRange(start, styleAttr.length - start);
                NSRange semi = [styleAttr rangeOfString:@";" options:0 range:sub];
                if (semi.location != NSNotFound) {
                    fillFromStyle = [styleAttr substringWithRange:NSMakeRange(start, semi.location - start)];
                } else {
                    fillFromStyle = [styleAttr substringFromIndex:start];
                }
                fillFromStyle = [fillFromStyle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }

        NSString *fill = fillAttr ?: fillFromStyle;
        if (SvgIsMagentaFill(fill)) {
            CGFloat x  = SvgParseDouble(attributeDict[@"x"]);
            CGFloat y  = SvgParseDouble(attributeDict[@"y"]);
            CGFloat w  = SvgParseDouble(attributeDict[@"width"]);
            CGFloat h  = SvgParseDouble(attributeDict[@"height"]);
            CGFloat rx = SvgParseDouble(attributeDict[@"rx"]);
            CGFloat ry = SvgParseDouble(attributeDict[@"ry"]);

            GiftSlot slot;
            slot.rect = CGRectMake(x, y, w, h);

            [self.slots addObject:[NSValue valueWithBytes:&slot objCType:@encode(GiftSlot)]];
        }
    }
}

- (void)parser:(NSXMLParser *)parser
  didEndElement:(NSString *)elementName
   namespaceURI:(NSString *)namespaceURI
  qualifiedName:(NSString *)qName
{
    if ([_elementName isEqualToString:@"style"]) {
        // parse accumulated CSS classes -> styles
        NSInteger currentClassNameStartIndex = -1;
        NSInteger currentClassContentsStartIndex = -1;

        NSString *currentClassName = nil;
        NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];

        for (NSInteger i = 0; i < _currentStyleString.length; i++) {
            unichar c = [_currentStyleString characterAtIndex:i];
            if (currentClassNameStartIndex != -1) {
                if (![alphanumeric characterIsMember:c]) {
                    currentClassName = [_currentStyleString substringWithRange:
                                        NSMakeRange(currentClassNameStartIndex, i - currentClassNameStartIndex)];
                    currentClassNameStartIndex = -1;
                }
            } else if (currentClassContentsStartIndex != -1) {
                if (c == '}') {
                    NSString *classContents = [_currentStyleString substringWithRange:
                                               NSMakeRange(currentClassContentsStartIndex, i - currentClassContentsStartIndex)];
                    if (currentClassName != nil && classContents != nil) {
                        _styles[currentClassName] = classContents;
                        currentClassName = nil;
                    }
                    currentClassContentsStartIndex = -1;
                }
            }

            if (currentClassNameStartIndex == -1 && currentClassContentsStartIndex == -1) {
                if (c == '.') {
                    currentClassNameStartIndex = (NSInteger)i + 1;
                } else if (c == '{') {
                    currentClassContentsStartIndex = (NSInteger)i + 1;
                }
            }
        }
        // clear style buffer after use
        _currentStyleString = nil;
    }

    // Track leaving GiftPatterns group
    if ([elementName isEqualToString:@"g"] && _giftGroupDepth > 0) {
        _giftGroupDepth -= 1;
    }

    _elementName = nil;
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if ([_elementName isEqualToString:@"style"]) {
        if (_currentStyleString == nil) {
            _currentStyleString = [NSMutableString new];
        }
        [_currentStyleString appendString:string ?: @""];
    }
}

@end

NSDictionary * _Nullable svgSlotsDataFromSVG(NSData * _Nonnull data, CGSize imageSize) {
    // 1) Parse SVG to collect slots
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    if (!parser) return nil;
    SvgXMLParsingDelegate *delegate = [[SvgXMLParsingDelegate alloc] init];
    parser.delegate = delegate;
    [parser parse];
    
    if (delegate.slots.count == 0) {
        return nil;
    }

    // 2) Get SVG viewBox size via NanoSVG (width/height)
    NSMutableString *xmlString = [[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!xmlString) return nil;
    
    NSUInteger count = delegate.slots.count;
    if (count == 0) return nil;

    NSUInteger mid = count / 2; // middle index
    NSInteger offset = ((NSInteger)[xmlString hash] % 5) - 2;
    // gives value in range -2..+2

    NSInteger candidate = (NSInteger)mid + offset;

    // clamp to valid range
    if (candidate < 0) candidate = 0;
    if (candidate >= count) candidate = count - 1;

    NSUInteger neatSpot = (NSUInteger)candidate;

    
    NSVGimage *img = nsvgParse(xmlString.UTF8String, "px", 96);
    if (!img || img->width < 1.0f || img->height < 1.0f) {
        if (img) nsvgDelete(img);
        return nil;
    }
    const CGFloat svgW = img->width;
    const CGFloat svgH = img->height;

    // 3) Recreate the same aspectFill + centering as drawSvgImageNano
    CGSize svgSize = CGSizeMake(svgW, svgH);
    CGSize target  = imageSize;

    // aspectFill size
    CGFloat scale = MAX(target.width / MAX(1.0, svgSize.width),
                        target.height / MAX(1.0, svgSize.height));
    CGSize drawingSize = CGSizeMake(svgSize.width * scale, svgSize.height * scale);
    CGFloat offsetX = (target.width  - drawingSize.width)  * 0.5;
    CGFloat offsetY = (target.height - drawingSize.height) * 0.5;

    // 4) Build the same CTM: flipY about image height, then scale, then center translate
    CGAffineTransform t = CGAffineTransformIdentity;
    t = CGAffineTransformTranslate(t, 0.0, target.height);
    t = CGAffineTransformScale(t, 1.0, -1.0);
    t = CGAffineTransformScale(t, scale, scale);
    t = CGAffineTransformTranslate(t, offsetX / scale, offsetY / scale); // keep identical to CG pipeline

    // Helper to transform a rect via four corners and get bbox
    CGRect (^rectApply)(CGRect, CGAffineTransform) = ^CGRect(CGRect r, CGAffineTransform tr) {
        CGPoint p1 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r)), tr);
        CGPoint p2 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMaxX(r), CGRectGetMinY(r)), tr);
        CGPoint p3 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMinX(r), CGRectGetMaxY(r)), tr);
        CGPoint p4 = CGPointApplyAffineTransform(CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)), tr);
        CGFloat minX = fmin(fmin(p1.x, p2.x), fmin(p3.x, p4.x));
        CGFloat maxX = fmax(fmax(p1.x, p2.x), fmax(p3.x, p4.x));
        CGFloat minY = fmin(fmin(p1.y, p2.y), fmin(p3.y, p4.y));
        CGFloat maxY = fmax(fmax(p1.y, p2.y), fmax(p3.y, p4.y));
        return CGRectMake(minX, minY, maxX - minX, maxY - minY);
    };

    // 5) Build slots array
    NSMutableArray *slotsOut = [NSMutableArray arrayWithCapacity:delegate.slots.count];
    for (NSUInteger i = 0; i < delegate.slots.count; i++) {
        GiftSlot s = {0};
        [delegate.slots[i] getValue:&s];

        CGRect svgRect   = s.rect;
        CGRect pixelRect = rectApply(svgRect, t);

        [slotsOut addObject:@{
            @"i": @(i),
            @"pixel": @{ @"x": @(pixelRect.origin.x), @"y": @(pixelRect.origin.y),
                         @"w": @(pixelRect.size.width), @"h": @(pixelRect.size.height) }
        }];
    }

    NSDictionary *payload = @{
        @"version": @1,
        @"imageSize":  @{ @"w": @(imageSize.width), @"h": @(imageSize.height) },
        @"scale": @(scale),
        @"offset": @{ @"x": @(offsetX), @"y": @(offsetY) },
        @"slots": slotsOut,
        @"neatSpot": @(neatSpot)
    };

    nsvgDelete(img);
    return payload;
}


NSImage * _Nullable drawSvgImageNano(NSData * _Nonnull data, CGSize size, NSArray<NSDictionary *> * _Nullable slotItems) {
    NSDate *startTime = [NSDate date];
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    if (parser == nil) {
        return nil;
    }
    SvgXMLParsingDelegate *delegate = [[SvgXMLParsingDelegate alloc] init];
    parser.delegate = delegate;
    [parser parse];
    
    NSMutableString *xmlString = [[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (xmlString == nil) {
        return nil;
    }
    
    NSUInteger xmlHash = [xmlString hash];
    
    NSUInteger neatSpot = 0;
    
    NSUInteger count = delegate.slots.count;
    if (count != 0) {
        NSUInteger mid = count / 2; // middle index
        NSInteger offset = ((NSInteger)[xmlString hash] % 5) - 2;

        NSInteger candidate = (NSInteger)mid + offset;

        if (candidate < 0) candidate = 0;
        if (candidate >= count) candidate = count - 1;

        neatSpot = (NSUInteger)candidate;
    }
    
    NSRange groupRange = [xmlString rangeOfString:@"<g id=\"GiftPatterns\"" options:NSCaseInsensitiveSearch];
    if (groupRange.location != NSNotFound) {
        NSRange endRange = [xmlString rangeOfString:@"</g>" options:0 range:NSMakeRange(groupRange.location, xmlString.length - groupRange.location)];
        if (endRange.location != NSNotFound) {
            NSRange full = NSMakeRange(groupRange.location, endRange.location + endRange.length - groupRange.location);
            NSMutableString *sub = [[xmlString substringWithRange:full] mutableCopy];
            [sub replaceOccurrencesOfString:@"fill=\"#ff00ff\"" withString:@"fill=\"none\"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, sub.length)];
            [sub replaceOccurrencesOfString:@"fill=\"#f0f\""    withString:@"fill=\"none\"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, sub.length)];
            [xmlString replaceCharactersInRange:full withString:sub];
        }
    }
    
    for (NSString *styleName in delegate.styles) {
        NSString *styleValue = delegate.styles[styleName];
        [xmlString replaceOccurrencesOfString:[NSString stringWithFormat:@"class=\"%@\"", styleName]
                                   withString:[NSString stringWithFormat:@"style=\"%@\"", styleValue]
                                      options:0
                                        range:NSMakeRange(0, xmlString.length)];
    }
    
    char *zeroTerminatedData = xmlString.UTF8String;
    
    NSVGimage *image = nsvgParse(zeroTerminatedData, "px", 96);
    if (image == nil || image->width < 1.0f || image->height < 1.0f) {
        return nil;
    }
    
    double deltaTime = -1.0f * [startTime timeIntervalSinceNow];
    printf("parseTime = %f\n", deltaTime);
    
    startTime = [NSDate date];
    
    NSColor *backgroundColor = [NSColor clearColor];
    NSColor *foregroundColor = [NSColor blackColor];
    
    NSImage *result = [[NSImage alloc] initWithSize:size];
    NSBitmapImageRep  *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                                     pixelsWide:size.width
                                                                     pixelsHigh:size.height
                                                                  bitsPerSample:8
                                                                samplesPerPixel:4
                                                                       hasAlpha:false
                                                                       isPlanar:true
                                                                 colorSpaceName:NSCalibratedRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:0];
    
    
    
    [result addRepresentation:rep];
    
    [result lockFocus];
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1.0, -1.0);
    
    CGContextClearRect(context, CGRectMake(0.0f, 0.0f, size.width, size.height));
//    CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
//    CGContextFillRect(context, CGRectMake(0.0f, 0.0f, size.width, size.height));
    
    CGSize svgSize = CGSizeMake(image->width, image->height);
    CGSize drawingSize = aspectFillSize(svgSize, size);
    CGFloat scale = MAX(size.width / MAX(1.0, svgSize.width), size.height / MAX(1.0, svgSize.height));
    
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, (size.width - drawingSize.width) / 2.0, (size.height - drawingSize.height) / 2.0);
    
    // --- Draw the parsed SVG shapes (unchanged) ---
    for (NSVGshape *shape = image->shapes; shape != NULL; shape = shape->next) {
        if (!(shape->flags & NSVG_FLAGS_VISIBLE)) {
            continue;
        }
        
        if (shape->fill.type != NSVG_PAINT_NONE) {
            CGContextSetFillColorWithColor(context, [foregroundColor colorWithAlphaComponent:shape->opacity].CGColor);
            
            bool isFirst = true;
            bool hasStartPoint = false;
            CGPoint startPoint = CGPointZero;
            for (NSVGpath *path = shape->paths; path != NULL; path = path->next) {
                if (isFirst) {
                    CGContextBeginPath(context);
                    isFirst = false;
                    hasStartPoint = true;
                    startPoint.x = path->pts[0];
                    startPoint.y = path->pts[1];
                }
                CGContextMoveToPoint(context, path->pts[0], path->pts[1]);
                for (int i = 0; i < path->npts - 1; i += 3) {
                    float *p = &path->pts[i * 2];
                    CGContextAddCurveToPoint(context, p[2], p[3], p[4], p[5], p[6], p[7]);
                }
                
                if (path->closed) {
                    if (hasStartPoint) {
                        hasStartPoint = false;
                        CGContextAddLineToPoint(context, startPoint.x, startPoint.y);
                    }
                }
            }
            switch (shape->fillRule) {
                case NSVG_FILLRULE_EVENODD:
                    CGContextEOFillPath(context);
                    break;
                default:
                    CGContextFillPath(context);
                    break;
            }
        }
        
        if (shape->stroke.type != NSVG_PAINT_NONE) {
            CGContextSetStrokeColorWithColor(context, [foregroundColor colorWithAlphaComponent:shape->opacity].CGColor);
            CGContextSetMiterLimit(context, shape->miterLimit);
            CGContextSetLineWidth(context, shape->strokeWidth);
            switch (shape->strokeLineCap) {
                case NSVG_CAP_BUTT:   CGContextSetLineCap(context, kCGLineCapButt);   break;
                case NSVG_CAP_ROUND:  CGContextSetLineCap(context, kCGLineCapRound);  break;
                case NSVG_CAP_SQUARE: CGContextSetLineCap(context, kCGLineCapSquare); break;
                default: break;
            }
            switch (shape->strokeLineJoin) {
                case NSVG_JOIN_BEVEL: CGContextSetLineJoin(context, kCGLineJoinBevel); break;
                case NSVG_JOIN_MITER: CGContextSetLineJoin(context, kCGLineJoinMiter); break;
                case NSVG_JOIN_ROUND: CGContextSetLineJoin(context, kCGLineJoinRound); break;
                default: break;
            }
            
            for (NSVGpath *path = shape->paths; path != NULL; path = path->next) {
                CGContextBeginPath(context);
                CGContextMoveToPoint(context, path->pts[0], path->pts[1]);
                for (int i = 0; i < path->npts - 1; i += 3) {
                    float *p = &path->pts[i * 2];
                    CGContextAddCurveToPoint(context, p[2], p[3], p[4], p[5], p[6], p[7]);
                }
                
                if (path->closed) {
                    CGContextClosePath(context);
                }
                CGContextStrokePath(context);
            }
        }
    }
    
   
    
    if (delegate.slots.count > 0 && slotItems.count > 0) {
        for (NSUInteger i = 0; i < delegate.slots.count; i++) {
            if (neatSpot != i) {
                uint32_t idx = arc4random_uniform((uint32_t)slotItems.count);
                NSDictionary *item = slotItems[idx];
                
                
                
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                
                NSImage *slotImage = item[@"image"];
                NSNumber *patternNum = item[@"pattern"];
                BOOL isPattern = patternNum.boolValue;
                if (!slotImage) continue;
                
                // Unpack slot geometry
                GiftSlot slot = {0};
                [delegate.slots[i] getValue:&slot];
                
                NSSize isz = slotImage.size;
                if (isz.width < 1.0 || isz.height < 1.0) continue;
                
                // Aspect-fit rect inside the slot
                CGFloat sx = slot.rect.size.width  / isz.width;
                CGFloat sy = slot.rect.size.height / isz.height;
                CGFloat s  = MIN(sx, sy);
                CGSize drawSize = CGSizeMake(isz.width * s, isz.height * s);
                CGRect drawRect = CGRectMake(
                    CGRectGetMidX(slot.rect) - drawSize.width  * 0.5,
                    CGRectGetMidY(slot.rect) - drawSize.height * 0.5,
                    drawSize.width, drawSize.height
                );
                
                CGImageRef cgImg = [slotImage CGImageForProposedRect:NULL
                                                             context:[NSGraphicsContext currentContext]
                                                               hints:nil];
                if (!cgImg) continue;
                                
                CGFloat angleDeg = ((int32_t)arc4random_uniform(6001) - 3000) / 100.0f;
                CGFloat angleRad = (CGFloat)M_PI * angleDeg / 180.0f;

                CGContextSaveGState(context);

                // Clip to slot bounds (keeps rotated content inside the slot)
                CGContextClipToRect(context, slot.rect);

                // Draw the image upright + rotated about drawRect center
                CGContextSaveGState(context);

                // Rotate around center of the image we are drawing
                CGFloat cx = CGRectGetMidX(drawRect);
                CGFloat cy = CGRectGetMidY(drawRect);
                CGContextTranslateCTM(context, cx, cy);
                CGContextRotateCTM(context, angleRad);
                CGContextTranslateCTM(context, -cx, -cy);

                // Neutralize global Y-flip for image draw
                CGContextTranslateCTM(context, 0.0, CGRectGetMinY(drawRect) * 2.0 + CGRectGetHeight(drawRect));
                CGContextScaleCTM(context, 1.0, -1.0);

                CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
                CGContextDrawImage(context, drawRect, cgImg);

                if (isPattern) {
                    // Apply tint in the same rotated space so it matches the image
                    CGContextSetBlendMode(context, kCGBlendModeSourceAtop);
                    CGContextSetFillColorWithColor(context, [foregroundColor colorWithAlphaComponent:1.0].CGColor);
                    CGContextFillRect(context, drawRect);
                    CGContextSetBlendMode(context, kCGBlendModeNormal);
                }

                CGContextRestoreGState(context); // pop rotation + local flip
                CGContextRestoreGState(context); // pop clip
            }
        }
    }
    
    
    [result unlockFocus];
    
    deltaTime = -1.0f * [startTime timeIntervalSinceNow];
    printf("drawingTime = %f\n", deltaTime);
    
    nsvgDelete(image);
    
    return result;
}




@interface CGContextCoder : NSObject {
    NSMutableData *_data;
}

@property (nonatomic, readonly) NSData *data;

@end

@implementation CGContextCoder

- (instancetype)initWithSize:(CGSize)size {
    self = [super init];
    if (self != nil) {
        _data = [[NSMutableData alloc] init];
        
        int32_t intWidth = size.width;
        int32_t intHeight = size.height;
        [_data appendBytes:&intWidth length:sizeof(intWidth)];
        [_data appendBytes:&intHeight length:sizeof(intHeight)];
    }
    return self;
}

- (void)setFillColorWithOpacity:(CGFloat)opacity {
    uint8_t command = 1;
    [_data appendBytes:&command length:sizeof(command)];
    
    uint8_t intOpacity = opacity * 255.0;
    [_data appendBytes:&intOpacity length:sizeof(intOpacity)];
}

- (void)setupStrokeOpacity:(CGFloat)opacity mitterLimit:(CGFloat)mitterLimit lineWidth:(CGFloat)lineWidth lineCap:(CGLineCap)lineCap lineJoin:(CGLineJoin)lineJoin {
    uint8_t command = 2;
    [_data appendBytes:&command length:sizeof(command)];
    
    uint8_t intOpacity = opacity * 255.0;
    [_data appendBytes:&intOpacity length:sizeof(intOpacity)];
    
    float floatMitterLimit = mitterLimit;
    [_data appendBytes:&floatMitterLimit length:sizeof(floatMitterLimit)];
    
    float floatLineWidth = lineWidth;
    [_data appendBytes:&floatLineWidth length:sizeof(floatLineWidth)];
    
    uint8_t intLineCap = lineCap;
    [_data appendBytes:&intLineCap length:sizeof(intLineCap)];
    
    uint8_t intLineJoin = lineJoin;
    [_data appendBytes:&intLineJoin length:sizeof(intLineJoin)];
}

- (void)beginPath {
    uint8_t command = 3;
    [_data appendBytes:&command length:sizeof(command)];
}

- (void)moveToPoint:(CGPoint)point {
    uint8_t command = 4;
    [_data appendBytes:&command length:sizeof(command)];
    
    float floatX = point.x;
    [_data appendBytes:&floatX length:sizeof(floatX)];
   
    float floatY = point.y;
    [_data appendBytes:&floatY length:sizeof(floatY)];
}

- (void)addLineToPoint:(CGPoint)point {
    uint8_t command = 5;
    [_data appendBytes:&command length:sizeof(command)];
    
    float floatX = point.x;
    [_data appendBytes:&floatX length:sizeof(floatX)];
   
    float floatY = point.y;
    [_data appendBytes:&floatY length:sizeof(floatY)];
}

- (void)addCurveToPoint:(CGPoint)p1 p2:(CGPoint)p2 p3:(CGPoint)p3 {
    uint8_t command = 6;
    [_data appendBytes:&command length:sizeof(command)];
    
    float floatX1 = p1.x;
    [_data appendBytes:&floatX1 length:sizeof(floatX1)];
   
    float floatY1 = p1.y;
    [_data appendBytes:&floatY1 length:sizeof(floatY1)];
    
    float floatX2 = p2.x;
    [_data appendBytes:&floatX2 length:sizeof(floatX2)];
   
    float floatY2 = p2.y;
    [_data appendBytes:&floatY2 length:sizeof(floatY2)];
    
    float floatX3 = p3.x;
    [_data appendBytes:&floatX3 length:sizeof(floatX3)];
   
    float floatY3 = p3.y;
    [_data appendBytes:&floatY3 length:sizeof(floatY3)];
}

- (void)closePath {
    uint8_t command = 7;
    [_data appendBytes:&command length:sizeof(command)];
}

- (void)eoFillPath {
    uint8_t command = 8;
    [_data appendBytes:&command length:sizeof(command)];
}

- (void)fillPath {
    uint8_t command = 9;
    [_data appendBytes:&command length:sizeof(command)];
}

- (void)strokePath {
    uint8_t command = 10;
    [_data appendBytes:&command length:sizeof(command)];
}

@end


NSImage * _Nullable renderPreparedImage(NSData * _Nonnull data, CGSize size, NSColor *backgroundColor, CGFloat scale) {
    NSDate *startTime = [NSDate date];
    
    NSColor *foregroundColor = [NSColor whiteColor];
    
    
    int32_t ptr = 0;
    int32_t width;
    int32_t height;
    
    if (data.length < 4 * 2) {
        return nil;
    }
    
    [data getBytes:&width range:NSMakeRange(ptr, sizeof(width))];
    ptr += sizeof(width);
    [data getBytes:&height range:NSMakeRange(ptr, sizeof(height))];
    ptr += sizeof(height);
    
    if (CGSizeEqualToSize(size, CGSizeZero)) {
        size = CGSizeMake(width, height);
    }
    
    NSImage *result = [[NSImage alloc] initWithSize:size];
    
    NSBitmapImageRep  *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide: size.width pixelsHigh: size.height bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: false isPlanar: true  colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    [result addRepresentation:rep];
    
    [result lockFocus];

    
    bool isTransparent = [backgroundColor isEqual:[NSColor clearColor]];
    
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    if (isTransparent) {
        CGContextClearRect(context, CGRectMake(0.0f, 0.0f, size.width, size.height));
    } else {
        CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
        CGContextFillRect(context, CGRectMake(0.0f, 0.0f, size.width, size.height));
    }
    
    CGSize svgSize = CGSizeMake(width, height);
    CGSize drawingSize = aspectFillSize(svgSize, size);
    
    CGFloat renderScale = MAX(size.width / MAX(1.0, svgSize.width), size.height / MAX(1.0, svgSize.height));
    
    CGContextScaleCTM(context, renderScale, renderScale);
    CGContextTranslateCTM(context, (size.width - drawingSize.width) / 2.0, (size.height - drawingSize.height) / 2.0);
    
    while (ptr < data.length) {
        uint8_t cmd;
        [data getBytes:&cmd range:NSMakeRange(ptr, sizeof(cmd))];
        ptr += sizeof(cmd);
        
        switch (cmd) {
            case 1:
            {
                uint8_t opacity;
                [data getBytes:&opacity range:NSMakeRange(ptr, sizeof(opacity))];
                ptr += sizeof(opacity);
                CGContextSetFillColorWithColor(context, [foregroundColor colorWithAlphaComponent:opacity / 255.0].CGColor);
            }
                break;
                
            case 2:
            {
                uint8_t opacity;
                [data getBytes:&opacity range:NSMakeRange(ptr, sizeof(opacity))];
                ptr += sizeof(opacity);
                CGContextSetStrokeColorWithColor(context, [foregroundColor colorWithAlphaComponent:opacity / 255.0].CGColor);
                
                float mitterLimit;
                [data getBytes:&mitterLimit range:NSMakeRange(ptr, sizeof(mitterLimit))];
                ptr += sizeof(mitterLimit);
                CGContextSetMiterLimit(context, mitterLimit);
                
                float lineWidth;
                [data getBytes:&lineWidth range:NSMakeRange(ptr, sizeof(lineWidth))];
                ptr += sizeof(lineWidth);
                CGContextSetLineWidth(context, lineWidth);
                
                uint8_t lineCap;
                [data getBytes:&lineCap range:NSMakeRange(ptr, sizeof(lineCap))];
                ptr += sizeof(lineCap);
                CGContextSetLineCap(context, lineCap);
                
                uint8_t lineJoin;
                [data getBytes:&lineJoin range:NSMakeRange(ptr, sizeof(lineJoin))];
                ptr += sizeof(lineJoin);
                CGContextSetLineCap(context, lineJoin);
            }
                break;
                
            case 3:
            {
                CGContextBeginPath(context);
            }
                break;
                
            case 4:
            {
                float x;
                [data getBytes:&x range:NSMakeRange(ptr, sizeof(x))];
                ptr += sizeof(x);
                
                float y;
                [data getBytes:&y range:NSMakeRange(ptr, sizeof(y))];
                ptr += sizeof(y);
                
                CGContextMoveToPoint(context, x, y);
            }
                break;
                
            case 5:
            {
                float x;
                [data getBytes:&x range:NSMakeRange(ptr, sizeof(x))];
                ptr += sizeof(x);
                
                float y;
                [data getBytes:&y range:NSMakeRange(ptr, sizeof(y))];
                ptr += sizeof(y);
                
                CGContextAddLineToPoint(context, x, y);
            }
                break;
                
            case 6:
            {
                float x1;
                [data getBytes:&x1 range:NSMakeRange(ptr, sizeof(x1))];
                ptr += sizeof(x1);
                
                float y1;
                [data getBytes:&y1 range:NSMakeRange(ptr, sizeof(y1))];
                ptr += sizeof(y1);
                
                float x2;
                [data getBytes:&x2 range:NSMakeRange(ptr, sizeof(x2))];
                ptr += sizeof(x2);
                
                float y2;
                [data getBytes:&y2 range:NSMakeRange(ptr, sizeof(y2))];
                ptr += sizeof(y2);
                
                float x3;
                [data getBytes:&x3 range:NSMakeRange(ptr, sizeof(x3))];
                ptr += sizeof(x3);
                
                float y3;
                [data getBytes:&y3 range:NSMakeRange(ptr, sizeof(y3))];
                ptr += sizeof(y3);
                
                CGContextAddCurveToPoint(context, x1, y1, x2, y2, x3, y3);
            }
                break;
                
            case 7:
            {
                CGContextClosePath(context);
            }
                break;
                
            case 8:
            {
                CGContextEOFillPath(context);
            }
                break;
            
            case 9:
            {
                CGContextFillPath(context);
            }
                break;
                
            case 10:
            {
                CGContextStrokePath(context);
            }
                break;
                
            default:
                break;
        }
    }
    
    [result unlockFocus];
        
    double deltaTime = -1.0f * [startTime timeIntervalSinceNow];
    printf("drawingTime %fx%f = %f\n", size.width, size.height, deltaTime);
    
    return result;
}

NSData * _Nullable prepareSvgImage(NSData * _Nonnull data) {
    NSDate *startTime = [NSDate date];
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    if (parser == nil) {
        return nil;
    }
    SvgXMLParsingDelegate *delegate = [[SvgXMLParsingDelegate alloc] init];
    parser.delegate = delegate;
    [parser parse];
    
    NSMutableString *xmlString = [[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (xmlString == nil) {
        return nil;
    }
    
    for (NSString *styleName in delegate.styles) {
        NSString *styleValue = delegate.styles[styleName];
        [xmlString replaceOccurrencesOfString:[NSString stringWithFormat:@"class=\"%@\"", styleName] withString:[NSString stringWithFormat:@"style=\"%@\"", styleValue] options:0 range:NSMakeRange(0, xmlString.length)];
    }
    
    const char *zeroTerminatedData = xmlString.UTF8String;
    
    NSVGimage *image = nsvgParse((char *)zeroTerminatedData, "px", 96);
    if (image == nil || image->width < 1.0f || image->height < 1.0f) {
        return nil;
    }
    
    double deltaTime = -1.0f * [startTime timeIntervalSinceNow];
    printf("parseTime = %f\n", deltaTime);
    
    startTime = [NSDate date];
   
    CGContextCoder *context = [[CGContextCoder alloc] initWithSize:CGSizeMake(image->width, image->height)];
   
    for (NSVGshape *shape = image->shapes; shape != NULL; shape = shape->next) {
        if (!(shape->flags & NSVG_FLAGS_VISIBLE)) {
            continue;
        }
        
        if (shape->fill.type != NSVG_PAINT_NONE) {
            [context setFillColorWithOpacity:shape->opacity];

            bool isFirst = true;
            bool hasStartPoint = false;
            CGPoint startPoint;
            for (NSVGpath *path = shape->paths; path != NULL; path = path->next) {
                if (isFirst) {
                    [context beginPath];

                    isFirst = false;
                    hasStartPoint = true;
                    startPoint.x = path->pts[0];
                    startPoint.y = path->pts[1];
                }
                [context moveToPoint:CGPointMake(path->pts[0], path->pts[1])];
                for (int i = 0; i < path->npts - 1; i += 3) {
                    float *p = &path->pts[i * 2];
                    [context addCurveToPoint:CGPointMake(p[2], p[3]) p2:CGPointMake(p[4], p[5]) p3:CGPointMake(p[6], p[7])];
                }
                
                if (path->closed) {
                    if (hasStartPoint) {
                        hasStartPoint = false;
                        [context addLineToPoint:startPoint];
                    }
                }
            }
            switch (shape->fillRule) {
                case NSVG_FILLRULE_EVENODD:
                    [context eoFillPath];
                    break;
                default:
                    [context fillPath];
                    break;
            }
        }
        
        if (shape->stroke.type != NSVG_PAINT_NONE) {
            CGLineCap lineCap = kCGLineCapButt;
            CGLineJoin lineJoin = kCGLineJoinMiter;
            switch (shape->strokeLineCap) {
                case NSVG_CAP_BUTT:
                    lineCap = kCGLineCapButt;
                    break;
                case NSVG_CAP_ROUND:
                    lineCap = kCGLineCapRound;
                    break;
                case NSVG_CAP_SQUARE:
                    lineCap = kCGLineCapSquare;
                    break;
                default:
                    break;
            }
            switch (shape->strokeLineJoin) {
                case NSVG_JOIN_BEVEL:
                    lineJoin = kCGLineJoinBevel;
                    break;
                case NSVG_JOIN_MITER:
                    lineJoin = kCGLineJoinMiter;
                    break;
                case NSVG_JOIN_ROUND:
                    lineJoin = kCGLineJoinRound;
                    break;
                default:
                    break;
            }
            
            [context setupStrokeOpacity:shape->opacity mitterLimit:shape->miterLimit lineWidth:shape->strokeWidth lineCap:lineCap lineJoin:lineJoin];
            
            for (NSVGpath *path = shape->paths; path != NULL; path = path->next) {
                [context beginPath];
                [context moveToPoint:CGPointMake(path->pts[0], path->pts[1])];
                for (int i = 0; i < path->npts - 1; i += 3) {
                    float *p = &path->pts[i * 2];
                    [context addCurveToPoint:CGPointMake(p[2], p[3]) p2:CGPointMake(p[4], p[5]) p3:CGPointMake(p[6], p[7])];
                }
                
                if (path->closed) {
                    [context closePath];
                }
                [context strokePath];
            }
        }
    }
    
    nsvgDelete(image);
    return context.data;
}



NSImage * _Nullable drawSvgImage(NSData * _Nonnull data, CGSize size, NSColor *backgroundColor, NSColor *foregroundColor, CGFloat canvasScale, bool opaque) {
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    if (parser == nil) {
        return nil;
    }
    SvgXMLParsingDelegate *delegate = [[SvgXMLParsingDelegate alloc] init];
    parser.delegate = delegate;
    [parser parse];
    
    NSMutableString *xmlString = [[NSMutableString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (xmlString == nil) {
        return nil;
    }
    
    for (NSString *styleName in delegate.styles) {
        NSString *styleValue = delegate.styles[styleName];
        [xmlString replaceOccurrencesOfString:[NSString stringWithFormat:@"class=\"%@\"", styleName] withString:[NSString stringWithFormat:@"style=\"%@\"", styleValue] options:0 range:NSMakeRange(0, xmlString.length)];
    }
    
    const char *zeroTerminatedData = xmlString.UTF8String;
    
    NSVGimage *image = nsvgParse((char *)zeroTerminatedData, "px", 96);
    if (image == nil || image->width < 1.0f || image->height < 1.0f) {
        return nil;
    }
    
    if (CGSizeEqualToSize(size, CGSizeZero)) {
        size = CGSizeMake(image->width, image->height);
    }

    
    NSImage *result = [[NSImage alloc] initWithSize:size];
    
    NSBitmapImageRep  *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil pixelsWide: size.width pixelsHigh: size.height bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: false isPlanar: true  colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    [result addRepresentation:rep];
    
    [result lockFocus];
    
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    
    
    if (backgroundColor != nil) {
        CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
        CGContextFillRect(context, CGRectMake(0.0f, 0.0f, size.width, size.height));
    }
    
    CGSize svgSize = CGSizeMake(image->width, image->height);
    CGSize drawingSize = aspectFillSize(svgSize, size);
    
    CGFloat scale = MAX(size.width / MAX(1.0, svgSize.width), size.height / MAX(1.0, svgSize.height));
    
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, (size.width - drawingSize.width) / 2.0, (size.height - drawingSize.height) / 2.0);
    
    for (NSVGshape *shape = image->shapes; shape != NULL; shape = shape->next) {
        if (!(shape->flags & NSVG_FLAGS_VISIBLE)) {
            continue;
        }
        
        if (shape->fill.type != NSVG_PAINT_NONE) {
            CGContextSetFillColorWithColor(context, [foregroundColor colorWithAlphaComponent:shape->opacity].CGColor);

            bool isFirst = true;
            bool hasStartPoint = false;
            CGPoint startPoint;
            for (NSVGpath *path = shape->paths; path != NULL; path = path->next) {
                if (isFirst) {
                    CGContextBeginPath(context);
                    isFirst = false;
                    hasStartPoint = true;
                    startPoint.x = path->pts[0];
                    startPoint.y = path->pts[1];
                }
                CGContextMoveToPoint(context, path->pts[0], path->pts[1]);
                for (int i = 0; i < path->npts - 1; i += 3) {
                    float *p = &path->pts[i * 2];
                    CGContextAddCurveToPoint(context, p[2], p[3], p[4], p[5], p[6], p[7]);
                }
                
                if (path->closed) {
                    if (hasStartPoint) {
                        hasStartPoint = false;
                        CGContextAddLineToPoint(context, startPoint.x, startPoint.y);
                    }
                }
            }
            switch (shape->fillRule) {
                case NSVG_FILLRULE_EVENODD:
                    CGContextEOFillPath(context);
                    break;
                default:
                    CGContextFillPath(context);
                    break;
            }
        }
        
        if (shape->stroke.type != NSVG_PAINT_NONE) {
            CGContextSetStrokeColorWithColor(context, [foregroundColor colorWithAlphaComponent:shape->opacity].CGColor);
            CGContextSetMiterLimit(context, shape->miterLimit);
            
            CGContextSetLineWidth(context, shape->strokeWidth);
            switch (shape->strokeLineCap) {
                case NSVG_CAP_BUTT:
                    CGContextSetLineCap(context, kCGLineCapButt);
                    break;
                case NSVG_CAP_ROUND:
                    CGContextSetLineCap(context, kCGLineCapRound);
                    break;
                case NSVG_CAP_SQUARE:
                    CGContextSetLineCap(context, kCGLineCapSquare);
                    break;
                default:
                    break;
            }
            switch (shape->strokeLineJoin) {
                case NSVG_JOIN_BEVEL:
                    CGContextSetLineJoin(context, kCGLineJoinBevel);
                    break;
                case NSVG_JOIN_MITER:
                    CGContextSetLineJoin(context, kCGLineJoinMiter);
                    break;
                case NSVG_JOIN_ROUND:
                    CGContextSetLineJoin(context, kCGLineJoinRound);
                    break;
                default:
                    break;
            }
            
            for (NSVGpath *path = shape->paths; path != NULL; path = path->next) {
                CGContextBeginPath(context);
                CGContextMoveToPoint(context, path->pts[0], path->pts[1]);
                for (int i = 0; i < path->npts - 1; i += 3) {
                    float *p = &path->pts[i * 2];
                    CGContextAddCurveToPoint(context, p[2], p[3], p[4], p[5], p[6], p[7]);
                }
                
                if (path->closed) {
                    CGContextClosePath(context);
                }
                CGContextStrokePath(context);
            }
        }
    }
    
    [result unlockFocus];
    
    nsvgDelete(image);
    
    return result;
}

