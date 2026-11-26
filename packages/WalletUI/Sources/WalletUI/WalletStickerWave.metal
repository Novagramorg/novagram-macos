#include <metal_stdlib>
using namespace metal;

struct WalletStickerWaveUniforms {
    float4 frame;
    float2 size;
    float front;
    float angle;
    float shadow;
    float border;
    float lod;
};

struct WalletStickerWaveVertex {
    float4 position [[position]];
    float2 point;
};

vertex WalletStickerWaveVertex walletStickerWaveVertex(uint index [[vertex_id]],
                                                      constant float4 &placement [[buffer(0)]],
                                                      constant WalletStickerWaveUniforms &uniforms [[buffer(1)]]) {
    const float2 corners[] = {float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1)};
    float2 corner = corners[index];
    float2 surface = placement.xy + float2(corner.x, 1 - corner.y) * placement.zw;
    return {float4(surface * 2 - 1, 0, 1), corner * uniforms.size};
}

static float2 walletStickerArc(float t, float angle, float curl) {
    float r = curl / max(angle, 0.001);
    if (t <= curl) {
        float a = t / r;
        return float2(r * sin(a), r * (1.0 - cos(a)));
    }
    return float2(r * sin(angle), r * (1.0 - cos(angle))) + (t - curl) * float2(cos(angle), sin(angle));
}

static float4 walletStickerSample(texture2d<float> base, texture2d<float> art,
                                  constant WalletStickerWaveUniforms &u, float2 position) {
    constexpr sampler sampleSticker(coord::normalized, address::clamp_to_zero, filter::linear, mip_filter::linear);
    float2 uv = (position - u.frame.xy) / u.frame.z;
    float4 a = art.sample(sampleSticker, uv, level(u.lod));
    float4 b = base.sample(sampleSticker, uv, level(u.lod)) * u.border;
    return a + b * (1.0 - a.a);
}

fragment float4 walletStickerWaveFragment(WalletStickerWaveVertex in [[stage_in]],
                                         constant WalletStickerWaveUniforms &u [[buffer(0)]],
                                         texture2d<float> base [[texture(0)]],
                                         texture2d<float> art [[texture(1)]]) {
    float2 position = in.point;
    float side = u.frame.z;
    float hinge = u.frame.y + u.front * side;
    if (position.y <= hinge || u.angle <= 0.0005) {
        return walletStickerSample(base, art, u, position);
    }

    float2 center = u.frame.xy + 0.5 * side;
    float camera = 2.8 * side;
    float curl = 0.3 * side;
    float reach = max(u.frame.w - hinge, 0.0);
    float2 tip = walletStickerArc(reach, u.angle, curl);

    float4 color = float4(0.0);
    float tipY = center.y + (hinge + tip.x - center.y) * camera / (camera - tip.y);
    if (position.y <= tipY) {
        float lo = 0.0, hi = reach;
        for (int i = 0; i < 18; i++) {
            float mid = 0.5 * (lo + hi);
            float2 a = walletStickerArc(mid, u.angle, curl);
            float y = center.y + (hinge + a.x - center.y) * camera / (camera - a.y);
            if (y < position.y) { lo = mid; } else { hi = mid; }
        }
        float t = 0.5 * (lo + hi);
        float2 a = walletStickerArc(t, u.angle, curl);
        float m = camera / (camera - a.y);
        color = walletStickerSample(base, art, u, float2(center.x + (position.x - center.x) / m, hinge + t));
        float theta = u.angle * min(t / curl, 1.0);
        float lambert = (0.45 * sin(theta) + 0.89 * cos(theta)) / 0.89;
        float glint = (theta - 0.26) / 0.09;
        float gloss = exp(-glint * glint) * smoothstep(0.2, 0.4, u.angle) * 0.5;
        color.rgb = min(color.rgb * lambert + gloss * color.a, float3(color.a));
    }

    if (u.shadow > 0.001) {
        const float k = 0.5;
        if (position.y < hinge + tip.x + k * tip.y) {
            float lo = 0.0, hi = reach;
            for (int i = 0; i < 18; i++) {
                float mid = 0.5 * (lo + hi);
                float2 a = walletStickerArc(mid, u.angle, curl);
                if (hinge + a.x + k * a.y < position.y) { lo = mid; } else { hi = mid; }
            }
            float t = 0.5 * (lo + hi);
            float z = walletStickerArc(t, u.angle, curl).y;
            float blur = 0.5 + 0.16 * z;
            float spin = 6.2831853 * fract(52.9829189 * fract(dot(position * 3.0, float2(0.06711056, 0.00583715))));
            float alpha = 0.0;
            for (int i = 0; i < 16; i++) {
                float r = sqrt((float(i) + 0.5) / 16.0) * blur;
                float a = float(i) * 2.3999632 + spin;
                alpha += walletStickerSample(base, art, u, float2(position.x, hinge + t) + r * float2(cos(a), sin(a))).a;
            }
            alpha *= u.shadow * 0.5 / 16.0 * smoothstep(0.0, 4.0, z);
            color += (1.0 - color.a) * float4(0.0, 0.0, 0.0, alpha);
        }
    }
    return color;
}
