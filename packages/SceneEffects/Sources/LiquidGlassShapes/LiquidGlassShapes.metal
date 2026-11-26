#include <metal_stdlib>
using namespace metal;

struct LiquidGlassShapesUniforms {
    float4 gradientColor0;
    float4 gradientColor1;
    float4 layerStyle[3];
    float4 layerRimGlass[3];
    float2 boundsSize;
    float2 renderSize;
    float edgeInset;
    float gradientLength;
    float crestSpacing;
    float shadowStrength;
    float shadowSigma;
    float shadowDrop;
    float rimScale;
    float rimWidth;
    float glassBand;
    float glassShift;
    float glassAmount;
    int mode;
    float2 shapeCenter;
    float2 alignmentPadding;
};

constant static int liquidGlassCrestSampleCount = 128;
constant static int liquidGlassCrestPointCount = 6;

struct LiquidGlassCrestShape {
    float2 fromPoints[liquidGlassCrestPointCount];
    float2 toPoints[liquidGlassCrestPointCount];
    float progress;
    float offset;
};

struct LiquidGlassCrestParameters {
    LiquidGlassCrestShape shapes[3];
    float width;
    float restY;
    float amplitude;
    float smoothness;
};

struct LiquidGlassSegment {
    float2 start;
    float2 control1;
    float2 control2;
    float2 end;
};

static float2 liquidGlassCrestPoint(constant float2 *points, int index, constant LiquidGlassCrestParameters &parameters) {
    float2 point = points[clamp(index, 0, liquidGlassCrestPointCount - 1)];
    return float2(point.x * parameters.width, parameters.restY + point.y * parameters.amplitude);
}

static LiquidGlassSegment liquidGlassSmoothSegment(float2 previous, float2 start, float2 end, float2 afterEnd, float smoothness) {
    float handleLength = smoothness * distance(start, end);

    LiquidGlassSegment segment;
    segment.start = start;
    segment.control1 = start + normalize(end - previous) * handleLength;
    segment.control2 = end - normalize(afterEnd - start) * handleLength;
    segment.end = end;
    return segment;
}

static LiquidGlassSegment liquidGlassCrestSegment(constant float2 *points, int index, constant LiquidGlassCrestParameters &parameters) {
    return liquidGlassSmoothSegment(
        liquidGlassCrestPoint(points, index - 1, parameters),
        liquidGlassCrestPoint(points, index, parameters),
        liquidGlassCrestPoint(points, index + 1, parameters),
        liquidGlassCrestPoint(points, index + 2, parameters),
        parameters.smoothness
    );
}

static float2 liquidGlassSegmentPoint(LiquidGlassSegment segment, float t) {
    float u = 1.0 - t;
    return u * u * u * segment.start + 3.0 * u * u * t * segment.control1 + 3.0 * u * t * t * segment.control2 + t * t * t * segment.end;
}

kernel void liquidGlassCrestKernel(
    constant LiquidGlassCrestParameters &parameters [[ buffer(0) ]],
    device float *crests [[ buffer(1) ]],
    uint threadIndex [[ thread_position_in_threadgroup ]],
    uint threadCount [[ threads_per_threadgroup ]],
    uint shapeIndex [[ threadgroup_position_in_grid ]]
) {
    if (shapeIndex >= 3) {
        return;
    }
    constant LiquidGlassCrestShape &shape = parameters.shapes[shapeIndex];

    for (uint sampleIndex = threadIndex; sampleIndex < uint(liquidGlassCrestSampleCount); sampleIndex += threadCount) {
        float x = parameters.width * float(sampleIndex) / float(liquidGlassCrestSampleCount - 1);

        int segmentIndex = 0;
        for (int i = 1; i < liquidGlassCrestPointCount - 1; i++) {
            float knot = mix(shape.fromPoints[i].x, shape.toPoints[i].x, shape.progress) * parameters.width;
            if (x >= knot) {
                segmentIndex = i;
            }
        }

        LiquidGlassSegment from = liquidGlassCrestSegment(shape.fromPoints, segmentIndex, parameters);
        LiquidGlassSegment to = liquidGlassCrestSegment(shape.toPoints, segmentIndex, parameters);
        LiquidGlassSegment segment;
        segment.start = mix(from.start, to.start, shape.progress);
        segment.control1 = mix(from.control1, to.control1, shape.progress);
        segment.control2 = mix(from.control2, to.control2, shape.progress);
        segment.end = mix(from.end, to.end, shape.progress);

        float lower = 0.0;
        float upper = 1.0;
        for (int i = 0; i < 20; i++) {
            float middle = 0.5 * (lower + upper);
            if (liquidGlassSegmentPoint(segment, middle).x < x) {
                lower = middle;
            } else {
                upper = middle;
            }
        }
        float y = liquidGlassSegmentPoint(segment, 0.5 * (lower + upper)).y;

        crests[shapeIndex * liquidGlassCrestSampleCount + sampleIndex] = y + shape.offset;
    }
}

constant static int liquidGlassRadialSampleCount = 256;
constant static int liquidGlassRadialPointCount = 8;

struct LiquidGlassRadialShape {
    float2 fromPoints[liquidGlassRadialPointCount];
    float2 toPoints[liquidGlassRadialPointCount];
    float progress;
    float scale;
};

struct LiquidGlassRadialParameters {
    LiquidGlassRadialShape shapes[3];
    float size;
    float smoothness;
};

static float liquidGlassAngleDelta(float angle, float origin) {
    float delta = angle - origin;
    return delta - 6.28318531 * floor((delta + 3.14159265) / 6.28318531);
}

static float2 liquidGlassRadialPoint(constant float2 *points, int index) {
    return points[(index + liquidGlassRadialPointCount) % liquidGlassRadialPointCount];
}

static LiquidGlassSegment liquidGlassRadialSegment(constant float2 *points, int index, float smoothness) {
    return liquidGlassSmoothSegment(
        liquidGlassRadialPoint(points, index - 1),
        liquidGlassRadialPoint(points, index),
        liquidGlassRadialPoint(points, index + 1),
        liquidGlassRadialPoint(points, index + 2),
        smoothness
    );
}

kernel void liquidGlassRadialKernel(
    constant LiquidGlassRadialParameters &parameters [[ buffer(0) ]],
    device float *radii [[ buffer(1) ]],
    uint threadIndex [[ thread_position_in_threadgroup ]],
    uint threadCount [[ threads_per_threadgroup ]],
    uint shapeIndex [[ threadgroup_position_in_grid ]]
) {
    if (shapeIndex >= 3) {
        return;
    }
    constant LiquidGlassRadialShape &shape = parameters.shapes[shapeIndex];

    LiquidGlassSegment segments[liquidGlassRadialPointCount];
    float knotAngles[liquidGlassRadialPointCount];
    float meanRadius = 0.0;
    for (int i = 0; i < liquidGlassRadialPointCount; i++) {
        LiquidGlassSegment from = liquidGlassRadialSegment(shape.fromPoints, i, parameters.smoothness);
        LiquidGlassSegment to = liquidGlassRadialSegment(shape.toPoints, i, parameters.smoothness);
        segments[i].start = mix(from.start, to.start, shape.progress);
        segments[i].control1 = mix(from.control1, to.control1, shape.progress);
        segments[i].control2 = mix(from.control2, to.control2, shape.progress);
        segments[i].end = mix(from.end, to.end, shape.progress);
        knotAngles[i] = atan2(segments[i].start.y, segments[i].start.x);
        meanRadius += length(segments[i].start) / float(liquidGlassRadialPointCount);
    }

    for (uint sampleIndex = threadIndex; sampleIndex < uint(liquidGlassRadialSampleCount); sampleIndex += threadCount) {
        float angle = 6.28318531 * float(sampleIndex) / float(liquidGlassRadialSampleCount);
        float radius = meanRadius;
        for (int i = 0; i < liquidGlassRadialPointCount; i++) {
            float origin = knotAngles[i];
            float span = liquidGlassAngleDelta(knotAngles[(i + 1) % liquidGlassRadialPointCount], origin);
            float offset = liquidGlassAngleDelta(angle, origin);
            if (span != 0.0 && offset * span >= 0.0 && abs(offset) <= abs(span)) {
                float target = offset / span;
                float lower = 0.0;
                float upper = 1.0;
                for (int j = 0; j < 20; j++) {
                    float middle = 0.5 * (lower + upper);
                    float2 point = liquidGlassSegmentPoint(segments[i], middle);
                    if (liquidGlassAngleDelta(atan2(point.y, point.x), origin) / span < target) {
                        lower = middle;
                    } else {
                        upper = middle;
                    }
                }
                radius = length(liquidGlassSegmentPoint(segments[i], 0.5 * (lower + upper)));
                break;
            }
        }
        radii[shapeIndex * liquidGlassRadialSampleCount + sampleIndex] = radius * parameters.size * shape.scale;
    }
}

constant static float2 liquidGlassQuadVertices[6] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0)
};

struct LiquidGlassShapesVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex LiquidGlassShapesVertexOut liquidGlassShapesVertex(
    constant float4 &rect [[ buffer(0) ]],
    unsigned int vid [[ vertex_id ]]
) {
    float2 quadVertex = liquidGlassQuadVertices[vid];

    LiquidGlassShapesVertexOut out;
    float x = rect.x + quadVertex.x * rect.z;
    float y = rect.y + (1.0 - quadVertex.y) * rect.w;
    out.position = float4(-1.0 + x * 2.0, -1.0 + y * 2.0, 0.0, 1.0);
    out.uv = quadVertex;
    return out;
}

constant int liquidGlassShapeKind [[function_constant(0)]];

struct LiquidGlassShapeSample {
    float distance;
    float2 inwardNormal;
};

static LiquidGlassShapeSample liquidGlassCrestSample(constant float *crests, int shape, float2 point, float spacing) {
    constant float *crest = crests + shape * liquidGlassCrestSampleCount;

    float position = clamp(point.x / spacing, 0.0, float(liquidGlassCrestSampleCount - 1));
    int index = min(int(position), liquidGlassCrestSampleCount - 2);
    float t = position - float(index);
    float y0 = crest[index];
    float y1 = crest[index + 1];
    float slope = (y1 - y0) / spacing;
    float normalization = rsqrt(1.0 + slope * slope);

    LiquidGlassShapeSample result;
    result.distance = (mix(y0, y1, t) - point.y) * normalization;
    result.inwardNormal = float2(slope, -1.0) * normalization;
    return result;
}

static LiquidGlassShapeSample liquidGlassRadialSample(constant float *samples, int shape, float2 point, float2 center) {
    constant float *radius = samples + shape * liquidGlassRadialSampleCount;

    float2 offset = point - center;
    float distanceFromCenter = max(length(offset), 0.001);
    float angle = atan2(offset.y, offset.x);
    if (angle < 0.0) {
        angle += 6.28318531;
    }
    float step = 6.28318531 / float(liquidGlassRadialSampleCount);
    float position = angle / step;
    int index = min(int(position), liquidGlassRadialSampleCount - 1);
    float t = position - float(index);
    float r0 = radius[index];
    float r1 = radius[(index + 1) % liquidGlassRadialSampleCount];
    float slope = (r1 - r0) / step;

    float tangentialSlope = slope / distanceFromCenter;
    float normalization = rsqrt(1.0 + tangentialSlope * tangentialSlope);
    float2 radial = offset / distanceFromCenter;
    float2 tangential = float2(-radial.y, radial.x);

    LiquidGlassShapeSample result;
    result.distance = (mix(r0, r1, t) - distanceFromCenter) * normalization;
    result.inwardNormal = (-radial + tangentialSlope * tangential) * normalization;
    return result;
}

static LiquidGlassShapeSample liquidGlassShape(constant float *samples, int shape, float2 point, constant LiquidGlassShapesUniforms &uniforms) {
    if (liquidGlassShapeKind == 1) {
        return liquidGlassRadialSample(samples, shape, point, uniforms.shapeCenter);
    }
    return liquidGlassCrestSample(samples, shape, point, uniforms.crestSpacing);
}

static float liquidGlassCoverage(float distance, float pixelsPerPoint) {
    return saturate(distance * pixelsPerPoint + 0.5);
}

static float liquidGlassErf(float x) {
    const float a = 0.147;
    float x2 = x * x;
    float t = 1.0 - exp(-x2 * (1.2732395 + a * x2) / (1.0 + a * x2));
    return sign(x) * sqrt(max(t, 0.0));
}

static float liquidGlassBlurredCoverage(float distance, float sigma) {
    return 0.5 * (1.0 + liquidGlassErf(distance / (sigma * 1.41421356)));
}

static float2 liquidGlassPoint(float2 uv, constant LiquidGlassShapesUniforms &uniforms, thread float &pixelsPerPoint) {
    float2 allocationSize = uniforms.renderSize + 2.0 * uniforms.edgeInset;
    float2 pixel = uv * allocationSize - uniforms.edgeInset;
    pixelsPerPoint = uniforms.renderSize.y / uniforms.boundsSize.y;
    return pixel * uniforms.boundsSize / uniforms.renderSize;
}

struct LiquidGlassComposite {
    float3 multiplier;
    float3 addend;
};

static void liquidGlassApplyOver(thread LiquidGlassComposite &composite, float3 premultipliedColor, float alpha) {
    composite.multiplier *= 1.0 - alpha;
    composite.addend = composite.addend * (1.0 - alpha) + premultipliedColor;
}

static LiquidGlassComposite liquidGlassComposite(float2 point, float pixelsPerPoint, constant LiquidGlassShapesUniforms &uniforms, constant float *samples) {
    float3 gradient = mix(uniforms.gradientColor0.rgb, uniforms.gradientColor1.rgb, saturate(point.x / uniforms.gradientLength));

    LiquidGlassComposite composite;
    composite.multiplier = float3(1.0);
    composite.addend = float3(0.0);

    LiquidGlassShapeSample shapes[3];
    float coverage[3];
    for (int i = 0; i < 3; i++) {
        shapes[i] = liquidGlassShape(samples, i, point, uniforms);
        coverage[i] = liquidGlassCoverage(shapes[i].distance, pixelsPerPoint);
    }

    if (uniforms.mode == 2) {
        liquidGlassApplyOver(composite, gradient * coverage[2], coverage[2]);
        return composite;
    }

    float shadowDistance = shapes[0].distance - uniforms.shadowDrop * shapes[0].inwardNormal.y;
    float shadow = uniforms.shadowStrength * liquidGlassBlurredCoverage(shadowDistance, uniforms.shadowSigma);
    liquidGlassApplyOver(composite, float3(0.0), shadow);

    if (uniforms.mode == 0) {
        float transparency = 1.0;
        for (int i = 0; i < 3; i++) {
            transparency *= 1.0 - uniforms.layerRimGlass[i].z * coverage[i];
        }
        float alpha = 1.0 - transparency;
        liquidGlassApplyOver(composite, gradient * alpha, alpha);
        return composite;
    }

    for (int i = 0; i < 3; i++) {
        float4 style = uniforms.layerStyle[i];
        float fillAlpha = style.x * style.y;
        float matteAlpha = style.w * style.x;
        float3 groupColor = gradient * fillAlpha * (1.0 - matteAlpha) + matteAlpha;
        float groupAlpha = fillAlpha + matteAlpha - fillAlpha * matteAlpha;
        liquidGlassApplyOver(composite, groupColor * coverage[i], groupAlpha * coverage[i]);
    }
    for (int i = 0; i < 3; i++) {
        float amount = uniforms.layerStyle[i].z * coverage[i];
        float3 factor = 1.0 - amount * (1.0 - gradient);
        composite.multiplier *= factor;
        composite.addend *= factor;
    }
    for (int i = 0; i < 3; i++) {
        float rim = uniforms.layerRimGlass[i].x * uniforms.rimScale;
        float line = saturate((0.5 * uniforms.rimWidth - abs(shapes[i].distance)) * pixelsPerPoint + 0.5);
        float alpha = rim * line;
        liquidGlassApplyOver(composite, float3(alpha), alpha);
    }
    return composite;
}

fragment half4 liquidGlassShapesContentFragment(
    LiquidGlassShapesVertexOut in [[stage_in]],
    constant LiquidGlassShapesUniforms &uniforms [[ buffer(0) ]],
    constant float *samples [[ buffer(1) ]]
) {
    float pixelsPerPoint;
    float2 point = liquidGlassPoint(in.uv, uniforms, pixelsPerPoint);
    LiquidGlassComposite composite = liquidGlassComposite(point, pixelsPerPoint, uniforms, samples);

    if (uniforms.mode == 1) {
        return half4(half3(composite.addend), 0.0);
    } else {
        return half4(half3(composite.addend), half(1.0 - composite.multiplier.r));
    }
}

fragment half4 liquidGlassShapesMultiplyFragment(
    LiquidGlassShapesVertexOut in [[stage_in]],
    constant LiquidGlassShapesUniforms &uniforms [[ buffer(0) ]],
    constant float *samples [[ buffer(1) ]]
) {
    float pixelsPerPoint;
    float2 point = liquidGlassPoint(in.uv, uniforms, pixelsPerPoint);
    LiquidGlassComposite composite = liquidGlassComposite(point, pixelsPerPoint, uniforms, samples);

    float3 multiplier = composite.multiplier;
    float minimum = min(multiplier.r, min(multiplier.g, multiplier.b));
    return half4(half3(multiplier - minimum), half(1.0 - minimum));
}

fragment half4 liquidGlassShapesMaskFragment(
    LiquidGlassShapesVertexOut in [[stage_in]],
    constant LiquidGlassShapesUniforms &uniforms [[ buffer(0) ]],
    constant float *samples [[ buffer(1) ]]
) {
    float pixelsPerPoint;
    float2 point = liquidGlassPoint(in.uv, uniforms, pixelsPerPoint);

    float coverage = 0.0;
    for (int i = 0; i < 3; i++) {
        LiquidGlassShapeSample shape = liquidGlassShape(samples, i, point, uniforms);
        coverage = max(coverage, liquidGlassCoverage(shape.distance, pixelsPerPoint));
    }
    return half4(half(coverage));
}

fragment half4 liquidGlassShapesDisplacementFragment(
    LiquidGlassShapesVertexOut in [[stage_in]],
    constant LiquidGlassShapesUniforms &uniforms [[ buffer(0) ]],
    constant float *samples [[ buffer(1) ]]
) {
    float pixelsPerPoint;
    float2 point = liquidGlassPoint(in.uv, uniforms, pixelsPerPoint);

    float2 sampleOffset = float2(0.0);
    for (int i = 0; i < 3; i++) {
        if (uniforms.layerRimGlass[i].y == 0.0) {
            continue;
        }
        LiquidGlassShapeSample shape = liquidGlassShape(samples, i, point, uniforms);
        float coverage = liquidGlassCoverage(shape.distance, pixelsPerPoint);
        float falloff = 1.0 - saturate(max(shape.distance, 0.0) / uniforms.glassBand);
        sampleOffset += shape.inwardNormal * (uniforms.glassShift * falloff * falloff * coverage);
    }

    float2 encoded = saturate(0.5 - 0.5 * sampleOffset / uniforms.glassAmount);
    return half4(half(encoded.x), half(encoded.y), 1.0, 1.0);
}
