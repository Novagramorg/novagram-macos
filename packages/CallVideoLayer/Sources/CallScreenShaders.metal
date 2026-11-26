#include <metal_stdlib>

using namespace metal;

struct Rectangle {
    float2 origin;
    float2 size;
};

struct ModelConstants {
    float4x4 modelMatrix;
};

constant static float2 quadVertices[6] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0)
};

struct QuadVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadVertexOut callBackgroundVertex(
    const device Rectangle &rect [[ buffer(0) ]],
    unsigned int vid [[ vertex_id ]]
) {
    float2 quadVertex = quadVertices[vid];
    
    QuadVertexOut out;
    
    out.position = float4(rect.origin.x + quadVertex.x * rect.size.x, rect.origin.y + quadVertex.y * rect.size.y, 0.0, 1.0);
    out.position.x = -1.0 + out.position.x * 2.0;
    out.position.y = -1.0 + out.position.y * 2.0;
    
    out.uv = quadVertex;
    
    return out;
}

half4 rgb2hsv(half4 c) {
    half4 K = half4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    half4 p = mix(half4(c.bg, K.wz), half4(c.gb, K.xy), step(c.b, c.g));
    half4 q = mix(half4(p.xyw, c.r), half4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return half4(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x, c.a);
}

half4 hsv2rgb(half4 c) {
    half4 K = half4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    half3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return half4(c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y), c.a);
}

fragment half4 callBackgroundFragment(
    QuadVertexOut in [[stage_in]],
    const device float2 *positions [[ buffer(0) ]],
    const device float4 *colors [[ buffer(1) ]],
    const device float &brightness [[ buffer(2) ]],
    const device float &saturation [[ buffer(3) ]],
    const device float4 &overlay [[ buffer(4) ]]
) {
    half centerDistanceX = in.uv.x - 0.5;
    half centerDistanceY = in.uv.y - 0.5;
    half centerDistance = distance(half2(in.uv), half2(0.5, 0.5));
    half swirlFactor = 0.35 * centerDistance;
    half theta = swirlFactor * swirlFactor * 0.8 * 8.0;
    half sinTheta = sin(theta);
    half cosTheta = cos(theta);
    
    half pixelX = max(0.0, min(1.0, 0.5 + centerDistanceX * cosTheta - centerDistanceY * sinTheta));
    half pixelY = max(0.0, min(1.0, 0.5 + centerDistanceX * sinTheta + centerDistanceY * cosTheta));

    half distanceSum = 0.0;

    half r = 0.0;
    half g = 0.0;
    half b = 0.0;
    
    for (int i = 0; i < 4; i++) {
        half4 color = half4(colors[i]);
        
        half2 colorXY = half2(positions[i]);
        half2 distanceXY = half2(pixelX - colorXY.x, pixelY - colorXY.y);

        half distance = max(0.0, 0.92 - sqrt(distanceXY.x * distanceXY.x + distanceXY.y * distanceXY.y));
        distance = distance * distance * distance;
        distanceSum += distance;

        r = r + distance * color.r;
        g = g + distance * color.g;
        b = b + distance * color.b;
    }
    
    if (distanceSum < 0.00001) {
        distanceSum = 0.00001;
    }

    half pixelB = b / distanceSum;
    half pixelG = g / distanceSum;
    half pixelR = r / distanceSum;
    
    half4 color(pixelR, pixelG, pixelB, 1.0);
    color = rgb2hsv(color);
    color.b = clamp(color.b * brightness, 0.0, 1.0);
    color.g = clamp(color.g * saturation, 0.0, 1.0);
    color = hsv2rgb(color);
    color.rgb += half3(overlay.rgb * overlay.a);
    color.rgb = min(color.rgb, half3(1.0, 1.0, 1.0));
    
    return color;
}


struct BlobVertexOut {
    float4 position [[position]];
};

float2 blobVertex(float2 center, float angle, float radius) {
    return float2(center.x + radius * cos(angle), center.y + radius * sin(angle));
}

float interpolateFloat(float value1, float value2, float factor) {
    return value1 * (1.0 - factor) + value2 * factor;
}

struct Wave {
    float time;
    float speed;
    float3 amplitude;
    float3 wavelength;
};

float curve(float point, Wave wave) {
    float curve = 0;
    float t = wave.time;
    
    float amp[3] = { wave.amplitude.x, wave.amplitude.y, wave.amplitude.z };
    float len[3] = { wave.wavelength.x, wave.wavelength.y, wave.wavelength.z };

    for (int i = 0; i < 3; i++) {
        float amplitude = amp[i];
        float wavelength = len[i];
        float w = 2.0 / wavelength;

        float speed = wave.speed;
        float q = speed * w;

        curve += amplitude * sin((w * point) + (q * t));
    }
    return curve;
}


float2 mapPointInRect(Rectangle rect, half2 point) {
    half2 out(rect.origin.x + rect.size.x * point.x, rect.origin.y + rect.size.y * point.y);
    out.x = -1.0 + out.x * 2.0;
    out.y = -1.0 + out.y * 2.0;
    return float2(out);
}

struct SmoothPoint {
    half2 point;
    half inAngle;
    half inLength;
    half outAngle;
    half outLength;
    
    half2 smoothIn() {
        return smooth(inAngle, inLength);
    }
    
    half2 smoothOut() {
        return smooth(outAngle, outLength);
    }
    
private:
    half2 smooth(half angle, half length) {
        return half2(
            point.x + length * cos(angle),
            point.y + length * sin(angle)
        );
    }
};

half2 evaluateBlobPoint(const device Rectangle &rect, int index, int count, int subdivisions, Wave wave) {
    float position = curve(index, wave);
    float segmentAngle = float(index) / float(count) * 2.0 * 3.1415926;
    return half2(blobVertex(float2(0.5, 0.5), segmentAngle, 0.45 + 0.05 * position));
}

SmoothPoint evaluateSmoothBlobPoint(const device Rectangle &rect, int index, int count, int subdivisions, Wave wave) {
    int prevIndex = (index - 1) < 0 ? (count - 1) : (index - 1);
    int nextIndex = (index + 1) % count;
    
    half2 prev = evaluateBlobPoint(rect, prevIndex, count, subdivisions, wave);
    half2 curr = evaluateBlobPoint(rect, index, count, subdivisions, wave);
    half2 next = evaluateBlobPoint(rect, nextIndex, count, subdivisions, wave);
    
    float dx = next.x - prev.x;
    float dy = -next.y + prev.y;
    float angle = atan2(dy, dx);
    if (angle < 0.0) {
        angle = abs(angle);
    } else {
        angle = 2 * 3.1415926 - angle;
    }
    
    float smoothAngle = (3.1415926 * 2.0) / float(count);
    float smoothness = ((4.0 / 3.0) * tan(smoothAngle / 4.0)) / sin(smoothAngle * 0.5) * 0.5;
    
    SmoothPoint point;
    point.point = curr;
    point.inAngle = angle + 3.1415926;
    point.inLength = smoothness * distance(curr, prev);
    point.outAngle = angle;
    point.outLength = smoothness * distance(curr, next);
    
    return point;
}

half2 evaluateBezierBlobPoint(thread SmoothPoint &curr, thread SmoothPoint &next, half t) {
    half oneMinusT = 1.0 - t;
    
    half2 p0 = curr.point;
    half2 p1 = curr.smoothOut();
    half2 p2 = next.smoothIn();
    half2 p3 = next.point;
    
    return oneMinusT * oneMinusT * oneMinusT * p0 + 3.0 * t * oneMinusT * oneMinusT * p1 + 3.0 * t * t * oneMinusT * p2 + t * t * t * p3;
}


vertex BlobVertexOut callBlobVertex(
    const device Rectangle &rect [[ buffer(0) ]],
    const device int &count [[ buffer(1) ]],
    const device Wave &wave [[ buffer(2) ]],
    unsigned int vid [[ vertex_id ]]
) {
    const int subdivisions = 8;
    
    int triangleIndex = vid / 3;
    
    
    int segmentIndex = triangleIndex / subdivisions;
    int nextIndex = (segmentIndex + 1) % count;
    
    half innerPosition = half(triangleIndex - segmentIndex * subdivisions) / half(subdivisions);
    half nextInnerPosition = half(triangleIndex + 1 - segmentIndex * subdivisions) / half(subdivisions);
    
    SmoothPoint curr = evaluateSmoothBlobPoint(rect, segmentIndex, count, subdivisions, wave);
    SmoothPoint next = evaluateSmoothBlobPoint(rect, nextIndex, count, subdivisions, wave);
    
    half2 triangle[3];
    triangle[0] = half2(0.5, 0.5);
    triangle[1] = evaluateBezierBlobPoint(curr, next, innerPosition);
    triangle[2] = evaluateBezierBlobPoint(curr, next, nextInnerPosition);
    
    BlobVertexOut out;
    out.position = float4(float2(mapPointInRect(rect, triangle[vid % 3])), 0.0, 1.0);
    

    return out;
}

fragment half4 callBlobFragment(
    BlobVertexOut in [[stage_in]]
) {
    half alpha = 0.35;
    return half4(1.0 * alpha, 1.0 * alpha, 1.0 * alpha, alpha);
}

half2 evaluateMicBlobPoint(const device float *positions, int index, int count) {
    float position = positions[index];
    float segmentAngle = float(index) / float(count) * 2.0 * 3.1415926;
    return half2(blobVertex(float2(0.5, 0.5), segmentAngle, 0.45 + 0.05 * position));
}

SmoothPoint evaluateSmoothMicBlobPoint(const device float *positions, int index, int count) {
    int prevIndex = (index - 1) < 0 ? (count - 1) : (index - 1);
    int nextIndex = (index + 1) % count;

    half2 prev = evaluateMicBlobPoint(positions, prevIndex, count);
    half2 curr = evaluateMicBlobPoint(positions, index, count);
    half2 next = evaluateMicBlobPoint(positions, nextIndex, count);

    float dx = next.x - prev.x;
    float dy = -next.y + prev.y;
    float angle = atan2(dy, dx);
    if (angle < 0.0) {
        angle = abs(angle);
    } else {
        angle = 2 * 3.1415926 - angle;
    }

    float smoothAngle = (3.1415926 * 2.0) / float(count);
    float smoothness = ((4.0 / 3.0) * tan(smoothAngle / 4.0)) / sin(smoothAngle / 2.0) / 2.0;

    SmoothPoint point;
    point.point = curr;
    point.inAngle = angle + 3.1415926;
    point.inLength = smoothness * distance(curr, prev);
    point.outAngle = angle;
    point.outLength = smoothness * distance(curr, next);

    return point;
}

vertex BlobVertexOut callMicBlobVertex(
    const device Rectangle &rect [[ buffer(0) ]],
    const device float *positions [[ buffer(1) ]],
    const device int &count [[ buffer(2) ]],
    unsigned int vid [[ vertex_id ]]
) {
    const int subdivisions = 8;

    int triangleIndex = vid / 3;

    int segmentIndex = triangleIndex / subdivisions;
    int nextIndex = (segmentIndex + 1) % count;

    half innerPosition = half(triangleIndex - segmentIndex * subdivisions) / half(subdivisions);
    half nextInnerPosition = half(triangleIndex + 1 - segmentIndex * subdivisions) / half(subdivisions);

    SmoothPoint curr = evaluateSmoothMicBlobPoint(positions, segmentIndex, count);
    SmoothPoint next = evaluateSmoothMicBlobPoint(positions, nextIndex, count);

    half2 triangle[3];
    triangle[0] = half2(0.5, 0.5);
    triangle[1] = evaluateBezierBlobPoint(curr, next, innerPosition);
    triangle[2] = evaluateBezierBlobPoint(curr, next, nextInnerPosition);

    BlobVertexOut out;
    out.position = float4(float2(mapPointInRect(rect, triangle[vid % 3])), 0.0, 1.0);

    return out;
}

fragment half4 callMicBlobFragment(
    BlobVertexOut in [[stage_in]],
    const device float4 &color [[ buffer(0) ]]
) {
    return half4(color.r * color.a, color.g * color.a, color.b * color.a, color.a);
}


static half3 videoYUVToRGB(half y, half2 uv) {
    uv -= half2(0.5, 0.5);
    return half3(y + 1.403 * uv.y, y - 0.344 * uv.x - 0.714 * uv.y, y + 1.770 * uv.x);
}

constant int VIDEO_DOWNSCALE_TAPS = 4;

kernel void videoBiPlanarDownscale(
    texture2d<half, access::sample> inTextureY [[ texture(0) ]],
    texture2d<half, access::sample> inTextureUV [[ texture(1) ]],
    texture2d<half, access::write> outTexture [[ texture(2) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    uint2 size = uint2(outTexture.get_width(), outTexture.get_height());
    if (any(gid >= size)) {
        return;
    }
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 cell = 1.0 / float2(size);
    half3 sum = half3(0.0);
    for (int j = 0; j < VIDEO_DOWNSCALE_TAPS; j++) {
        for (int i = 0; i < VIDEO_DOWNSCALE_TAPS; i++) {
            float2 position = (float2(gid) + (float2(i, j) + 0.5) / float(VIDEO_DOWNSCALE_TAPS)) * cell;
            sum += clamp(videoYUVToRGB(inTextureY.sample(sampler, position).r, inTextureUV.sample(sampler, position).rg), half3(0.0), half3(1.0));
        }
    }
    outTexture.write(half4(sum / half(VIDEO_DOWNSCALE_TAPS * VIDEO_DOWNSCALE_TAPS), 1.0), gid);
}

kernel void videoTriPlanarDownscale(
    texture2d<half, access::sample> inTextureY [[ texture(0) ]],
    texture2d<half, access::sample> inTextureU [[ texture(1) ]],
    texture2d<half, access::sample> inTextureV [[ texture(2) ]],
    texture2d<half, access::write> outTexture [[ texture(3) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    uint2 size = uint2(outTexture.get_width(), outTexture.get_height());
    if (any(gid >= size)) {
        return;
    }
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 cell = 1.0 / float2(size);
    half3 sum = half3(0.0);
    for (int j = 0; j < VIDEO_DOWNSCALE_TAPS; j++) {
        for (int i = 0; i < VIDEO_DOWNSCALE_TAPS; i++) {
            float2 position = (float2(gid) + (float2(i, j) + 0.5) / float(VIDEO_DOWNSCALE_TAPS)) * cell;
            half2 uv = half2(inTextureU.sample(sampler, position).r, inTextureV.sample(sampler, position).r);
            sum += clamp(videoYUVToRGB(inTextureY.sample(sampler, position).r, uv), half3(0.0), half3(1.0));
        }
    }
    outTexture.write(half4(sum / half(VIDEO_DOWNSCALE_TAPS * VIDEO_DOWNSCALE_TAPS), 1.0), gid);
}

kernel void videoBGRADownscale(
    texture2d<half, access::sample> inTexture [[ texture(0) ]],
    texture2d<half, access::write> outTexture [[ texture(1) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    uint2 size = uint2(outTexture.get_width(), outTexture.get_height());
    if (any(gid >= size)) {
        return;
    }
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 cell = 1.0 / float2(size);
    half3 sum = half3(0.0);
    for (int j = 0; j < VIDEO_DOWNSCALE_TAPS; j++) {
        for (int i = 0; i < VIDEO_DOWNSCALE_TAPS; i++) {
            float2 position = (float2(gid) + (float2(i, j) + 0.5) / float(VIDEO_DOWNSCALE_TAPS)) * cell;
            sum += inTexture.sample(sampler, position).rgb;
        }
    }
    outTexture.write(half4(sum / half(VIDEO_DOWNSCALE_TAPS * VIDEO_DOWNSCALE_TAPS), 1.0), gid);
}

vertex QuadVertexOut mainVideoVertex(
    const device Rectangle &rect [[ buffer(0) ]],
    const device uint2 &mirror [[ buffer(1) ]],
    const device float &angle [[ buffer(2) ]],
    const device float2 &edge [[ buffer(3) ]],
    unsigned int vid [[ vertex_id ]]
) {
    float2 quadVertex = quadVertices[vid];
   
    QuadVertexOut out;
    
    out.position = float4(rect.origin.x + quadVertex.x * rect.size.x, rect.origin.y + quadVertex.y * rect.size.y, 0.0, 1.0);
    out.position.x = -1.0 + out.position.x * 2.0;
    out.position.y = -1.0 + out.position.y * 2.0;
    
    float2 contentVertex = (quadVertex - edge) / (1.0 - 2.0 * edge);
    
    float sinX = sin(angle);
    float cosX = cos(angle);
    float2x2 rotationMatrix = float2x2( cosX, sinX, -sinX, cosX);
    contentVertex = (contentVertex - 0.5) * rotationMatrix + 0.5;
    
    out.uv = float2(contentVertex.x, 1.0 - contentVertex.y);
    out.uv.x = mix(out.uv.x, 1.0 - out.uv.x, mirror.x);
    out.uv.y = mix(out.uv.y, 1.0 - out.uv.y, mirror.y);
    
    return out;
}

fragment half4 mainVideoFragment(
    QuadVertexOut in [[stage_in]],
    texture2d<half> texture [[ texture(0) ]],
    const device float &brightness [[ buffer(0) ]],
    const device float &saturation [[ buffer(1) ]],
    const device float4 &overlay [[ buffer(2) ]]
) {
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    half4 color = texture.sample(sampler, in.uv);
    color = rgb2hsv(color);
    color.b = clamp(color.b * brightness, 0.0, 1.0);
    color.g = clamp(color.g * saturation, 0.0, 1.0);
    color = hsv2rgb(color);
    color.rgb += half3(overlay.rgb * overlay.a);
    color.rgb = min(color.rgb, half3(1.0, 1.0, 1.0));
    
    return half4(color.r, color.g, color.b, color.a);
}

fragment half4 videoBiPlanarFragment(
    QuadVertexOut in [[stage_in]],
    texture2d<half> textureY [[ texture(0) ]],
    texture2d<half> textureUV [[ texture(1) ]]
) {
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return half4(videoYUVToRGB(textureY.sample(sampler, in.uv).r, textureUV.sample(sampler, in.uv).rg), 1.0);
}

fragment half4 videoTriPlanarFragment(
    QuadVertexOut in [[stage_in]],
    texture2d<half> textureY [[ texture(0) ]],
    texture2d<half> textureU [[ texture(1) ]],
    texture2d<half> textureV [[ texture(2) ]]
) {
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    half2 uv = half2(textureU.sample(sampler, in.uv).r, textureV.sample(sampler, in.uv).r);
    return half4(videoYUVToRGB(textureY.sample(sampler, in.uv).r, uv), 1.0);
}

fragment half4 videoBGRAFragment(
    QuadVertexOut in [[stage_in]],
    texture2d<half> texture [[ texture(0) ]]
) {
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return half4(texture.sample(sampler, in.uv).rgb, 1.0);
}

constant int BLUR_SAMPLE_COUNT = 7;
constant float BLUR_OFFSETS[BLUR_SAMPLE_COUNT] = {
    -5.227545617192816,
    -3.3147990233346842,
    -1.4174297935376852,
    0.47225076494548685,
    2.364576440741639,
    4.268941421369995,
    6
};

constant float BLUR_WEIGHTS[BLUR_SAMPLE_COUNT] = {
    0.015167713616041436,
    0.10117053983645591,
    0.2894431725427234,
    0.3570581167968804,
    0.19014435646109845,
    0.0435647539906345,
    0.0034513467561660305
};

static void gaussianBlur(
    texture2d<half, access::sample> inTexture,
    texture2d<half, access::write> outTexture,
    float2 offset,
    uint2 gid
) {
    constexpr sampler sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    
    uint2 textureDim(outTexture.get_width(), outTexture.get_height());
    if(all(gid < textureDim)) {
        float3 outColor(0.0);
        
        float2 size(inTexture.get_width(), inTexture.get_height());
        
        float2 baseTexCoord = float2(gid);
        
        for (int i = 0; i < BLUR_SAMPLE_COUNT; i++) {
            outColor += float3(inTexture.sample(sampler, (baseTexCoord + offset * BLUR_OFFSETS[i]) / size).rgb) * BLUR_WEIGHTS[i];
        }

        outTexture.write(half4(half3(outColor * 0.65), 1.0), gid);
    }
}

kernel void gaussianBlurHorizontal(
    texture2d<half, access::sample> inTexture [[ texture(0) ]],
    texture2d<half,  access::write> outTexture [[ texture(1) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    gaussianBlur(inTexture, outTexture, float2(1, 0), gid);
}

kernel void gaussianBlurVertical(
    texture2d<half, access::sample> inTexture [[ texture(0) ]],
    texture2d<half, access::write> outTexture [[ texture(1) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    gaussianBlur(inTexture, outTexture, float2(0, 1), gid);
}

vertex QuadVertexOut edgeTestVertex(
    const device Rectangle &rect [[ buffer(0) ]],
    unsigned int vid [[ vertex_id ]]
) {
    float2 quadVertex = quadVertices[vid];
    
    QuadVertexOut out;
    
    out.position = float4(rect.origin.x + quadVertex.x * rect.size.x, rect.origin.y + quadVertex.y * rect.size.y, 0.0, 1.0);
    out.position.x = -1.0 + out.position.x * 2.0;
    out.position.y = -1.0 + out.position.y * 2.0;
    
    out.uv = quadVertex;
    
    return out;
}

fragment half4 edgeTestFragment(
    QuadVertexOut in [[stage_in]],
    const device float4 &colorIn
) {
    half4 color = half4(colorIn);
    return color;
}
