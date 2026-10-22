#include <metal_stdlib>
using namespace metal;

static float2 glassUV(float3 position, float4x4 projection) {
    float4 clip = projection * float4(position, 1.0);
    return float2(clip.x, -clip.y) / clip.w * 0.5 + 0.5;
}

// The water surface's ripples (WaterRipples in GlassBubbleEffect.swift): a heightfield across the
// screen (x) and from the front edge back (depth), one wave-equation step per frame.
constant int kRippleWidth = 128;
constant int kRippleDepth = 48;

static float rippleAt(device const float *heights, int x, int z) {
    return heights[clamp(z, 0, kRippleDepth - 1) * kRippleWidth + clamp(x, 0, kRippleWidth - 1)];
}

/// Bilinear height at `cell` (in cells).
static float rippleSample(device const float *heights, float2 cell) {
    float2 base = floor(cell);
    float2 f = cell - base;
    int x = int(base.x), z = int(base.y);
    return mix(mix(rippleAt(heights, x, z), rippleAt(heights, x + 1, z), f.x),
               mix(rippleAt(heights, x, z + 1), rippleAt(heights, x + 1, z + 1), f.x), f.y);
}

kernel void waterRipplesClear(device float *heights [[buffer(0)]], uint2 id [[thread_position_in_grid]]) {
    if (int(id.x) >= kRippleWidth || int(id.y) >= kRippleDepth) return;
    heights[int(id.y) * kRippleWidth + int(id.x)] = 0.0;
}

// next = (sum of the 4 neighbours) / 2 - previous, damped; walls reflect. `previous` is overwritten
// with the next heights (each cell only reads its own previous value), plus Gaussian drops
// (x 0...1, depth 0...1, radius in cells, strength).
kernel void waterRipples(
    device const float *current [[buffer(0)]],
    device float *previous [[buffer(1)]],
    constant float4 *drops [[buffer(2)]],
    constant uint &dropCount [[buffer(3)]],
    uint2 id [[thread_position_in_grid]]
) {
    int x = int(id.x), z = int(id.y);
    if (x >= kRippleWidth || z >= kRippleDepth) return;
    float neighbours = rippleAt(current, x - 1, z) + rippleAt(current, x + 1, z)
        + rippleAt(current, x, z - 1) + rippleAt(current, x, z + 1);
    int index = z * kRippleWidth + x;
    float next = (neighbours * 0.5 - previous[index]) * 0.985;
    for (uint i = 0; i < dropCount; ++i) {
        float2 d = float2(x, z) - drops[i].xy * float2(kRippleWidth - 1, kRippleDepth - 1);
        next += drops[i].w * exp(-dot(d, d) / (drops[i].z * drops[i].z));
    }
    previous[index] = clamp(next, -4.0, 4.0);
}

kernel void glassBubbles(
    texture2d<float, access::sample> scene [[texture(0)]],
    texture2d<float, access::sample> depth [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant float4 *spheres [[buffer(0)]],
    constant uint &count [[buffer(1)]],
    constant float4x4 &projection [[buffer(2)]],
    constant float4x4 &inverseProjection [[buffer(3)]],
    constant float4 *bounds [[buffer(4)]],
    // Screen tiles (tileInfo: tiles across, tile size in pixels); each tile lists only the bubbles
    // touching it, back to front, as tileIndices[tileOffsets[tile] ..< tileOffsets[tile + 1]].
    constant uint *tileOffsets [[buffer(5)]],
    constant ushort *tileIndices [[buffer(6)]],
    constant uint2 &tileInfo [[buffer(7)]],
    // The water surface: [on, level from the top (0...1), tilt (height per width, up), underside
    // band height, ripple height at the line, time, -, -], 64 extra heights across the screen
    // (up), and the ripple heightfield.
    constant float *water [[buffer(8)]],
    constant float *waterHeights [[buffer(9)]],
    device const float *ripples [[buffer(10)]],
    uint2 pixel [[thread_position_in_grid]]
) {
    if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler depthSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 size = float2(output.get_width(), output.get_height());
    float2 uv = (float2(pixel) + 0.5) / size;
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    float4 rayPoint = inverseProjection * float4(ndc, 0.5, 1.0);
    float3 ray = normalize(rayPoint.xyz / rayPoint.w);
    float4 scenePoint = inverseProjection * float4(ndc, depth.sample(depthSampler, uv).r, 1.0);
    float3 scenePosition = scenePoint.xyz / scenePoint.w;
    float sceneDistance = -scenePosition.z > 0.0 ? length(scenePosition) : INFINITY;
    float4 color = scene.sample(linearSampler, uv);

    // Where the water line is at this column (screen y, down), and how far below it this pixel is.
    bool waterOn = water[0] > 0.5;
    float lineY = -1.0;
    if (waterOn) {
        float fx = uv.x * 63.0;
        int i0 = min(int(fx), 62);
        float lift = mix(waterHeights[i0], waterHeights[i0 + 1], fx - float(i0));
        float frontRipple = rippleSample(ripples, float2(uv.x * float(kRippleWidth - 1), 0.0));
        lineY = water[1] - water[2] * (uv.x - 0.5) * (size.x / size.y) - lift - water[4] * frontRipple;
    }
    float below = uv.y - lineY;

    // Bubbles only under the water: they end at the surface.
    uint tile = (pixel.y / tileInfo.y) * tileInfo.x + pixel.x / tileInfo.y;
    uint tileEnd = below > 0.0 ? tileOffsets[tile + 1] : tileOffsets[tile];
    for (uint k = tileOffsets[tile]; k < tileEnd; ++k) {
        uint i = tileIndices[k];
        float4 bound = bounds[i];
        if (any(uv < bound.xy) || any(uv > bound.zw)) continue;
        float3 center = spheres[i].xyz;
        float radius = spheres[i].w;
        if (radius <= 0.0 || center.z >= -radius) continue;
        float2 screenRadius = (bound.zw - bound.xy) * 0.5;

        float along = dot(ray, center);
        float discriminant = along * along - dot(center, center) + radius * radius;
        if (discriminant <= 0.0) continue;
        float hitDistance = along - sqrt(discriminant);
        if (hitDistance <= 0.0 || hitDistance >= sceneDistance) continue;
        float3 hit = ray * hitDistance;
        float3 normal = normalize(hit - center);
        float facing = saturate(dot(normal, -ray));

        // A glass sphere in water, tracing both interfaces rather than tinting a disk.
        constexpr float relativeIOR = 1.5 / 1.333;
        float3 inside = refract(ray, normal, 1.0 / relativeIOR);
        float travel = -2.0 * dot(hit - center, inside);
        float3 exit = hit + inside * travel;
        float3 exitNormal = normalize(exit - center);
        float3 transmitted = refract(inside, -exitNormal, relativeIOR);
        float backgroundZ = min(scenePosition.z, exit.z - 0.05);
        if (!isfinite(backgroundZ)) backgroundZ = -1.5;
        float distance = max(0.0, (backgroundZ - exit.z) / min(transmitted.z, -0.001));
        float2 refractedUV = glassUV(exit + transmitted * distance, projection);
        // Bound screen-space artifacts where the source image has no off-screen information.
        constexpr float refractionStrength = 0.25;
        refractedUV = uv + clamp(refractedUV - uv, float2(-0.04), float2(0.04)) * refractionStrength;
        float4 refracted = scene.sample(linearSampler, refractedUV);

        // Do not pull foreground objects into bubbles behind them.
        float2 refractedNDC = float2(refractedUV.x * 2.0 - 1.0, 1.0 - refractedUV.y * 2.0);
        float4 sampledPoint = inverseProjection
            * float4(refractedNDC, depth.sample(depthSampler, refractedUV).r, 1.0);
        if (sampledPoint.w != 0.0 && sampledPoint.z / sampledPoint.w > hit.z) {
            refracted = scene.sample(linearSampler, uv);
        }

        float3 reflected = reflect(ray, normal);
        float fresnel = 0.0035 + 0.9965 * pow(1.0 - facing, 5.0);
        float3 environment = mix(float3(0.12, 0.3, 0.4), float3(0.7, 0.9, 1.0),
                                 saturate(reflected.y * 0.5 + 0.5));
        float key = pow(saturate(dot(reflected, normalize(float3(-0.35, 0.65, 0.68)))), 110.0);
        float fill = pow(saturate(dot(reflected, normalize(float3(0.65, 0.15, 0.74)))), 65.0);
        float surfaceReflection = smoothstep(0.45, 0.95, reflected.y)
            * smoothstep(0.05, 0.3, normal.y);
        float3 glass = mix(refracted.rgb, environment, min(0.65, fresnel));
        glass += float3(1.0, 0.98, 0.92) * key * 1.4 + float3(0.65, 0.85, 1.0) * fill * 0.45;
        glass += float3(0.85, 0.95, 1.0) * surfaceReflection * 0.75;
        float coverage = saturate(sqrt(discriminant) / radius
            * max(1.0, min(screenRadius.x * size.x, screenRadius.y * size.y)));
        color.rgb = mix(color.rgb, glass, coverage);
    }

    if (waterOn) {
        float band = water[3];
        if (below < 0.0) {
            // Above the water: out of the water's blue, into a light haze of air, brighter toward
            // the top. The same for everything (the fish included), so see-through edges like the
            // lashes blend with no fringe.
            float3 air = mix(float3(0.62, 0.80, 0.90), float3(0.86, 0.94, 0.98),
                             saturate(-below / max(lineY, 0.05)));
            float3 dry = color.rgb * float3(1.07, 1.02, 0.93) + 0.02;
            color.rgb = mix(dry, air, 0.25);
        } else if (below < band) {
            // Just under the line: the underside of the surface, seen from below at a grazing
            // angle, reflecting the water beneath it (total internal reflection), rippling.
            float t = below / band;
            float2 cell = float2(uv.x * float(kRippleWidth - 1), pow(t, 0.75) * float(kRippleDepth - 1));
            float hx = rippleSample(ripples, cell + float2(1, 0)) - rippleSample(ripples, cell - float2(1, 0));
            float hz = rippleSample(ripples, cell + float2(0, 1)) - rippleSample(ripples, cell - float2(0, 1));
            float bottom = lineY + band;
            float2 mirrored = float2(uv.x + hx * 0.02, bottom + (bottom - uv.y) * 0.9 + hz * 0.02);
            float3 reflected = scene.sample(linearSampler, clamp(mirrored, float2(0.0), float2(1.0))).rgb;
            float sparkle = pow(saturate(0.5 + 2.0 * (hx + hz)), 6.0);
            float3 underside = reflected * float3(1.05, 1.12, 1.15) + float3(0.08, 0.12, 0.14) + sparkle * 0.35;
            color.rgb = mix(color.rgb, underside, 0.85 * (1.0 - smoothstep(0.6, 1.0, t)));
            // Where the surface meets the back of the bowl: a soft dark line.
            float edge = (t - 1.0) * band * size.y / 3.0;
            color.rgb *= 1.0 - 0.18 * exp(-edge * edge);
        }
        // The line itself: a thin bright edge, anti-aliased.
        float px = below * size.y / 1.6;
        color.rgb += float3(0.9, 0.97, 1.0) * 0.55 * exp(-px * px);
    }
    output.write(color, pixel);
}
