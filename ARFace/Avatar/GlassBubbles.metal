#include <metal_stdlib>
using namespace metal;

static float2 glassUV(float3 position, float4x4 projection) {
    float4 clip = projection * float4(position, 1.0);
    return float2(clip.x, -clip.y) / clip.w * 0.5 + 0.5;
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
    // The scene's look (SceneLook): white balance gains, what bubbles reflect below and above, and
    // the vignette (strength, start and end radius in halves of the narrow side).
    constant float4 *look [[buffer(8)]],
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
    // Seen through moving water: the image wavers in a slow, swirling flow (look[4]: strength,
    // time), measured in the screen's narrow side so it's the same in portrait and on the round
    // display, with a faint colour fringe where it bends.
    float4 color;
    if (look[4].x > 0.0) {
        float t = look[4].y;
        float2 p = (float2(pixel) + 0.5) / min(size.x, size.y);
        float2 flow = float2(
            sin(p.y * 9.0 + t * 0.9 + sin(p.x * 5.0 + t * 0.53) * 1.6)
                + 0.5 * sin(p.y * 21.0 - t * 1.7 + p.x * 7.0),
            sin(p.x * 8.0 - t * 0.8 + sin(p.y * 6.0 - t * 0.61) * 1.6)
                + 0.5 * sin(p.x * 19.0 + t * 1.4 - p.y * 9.0));
        float2 shift = flow * look[4].x * 0.018 * min(size.x, size.y) / size;
        color = scene.sample(linearSampler, uv + shift * 0.9);
        if (look[4].z > 0.0) {   // the fringe (off while the phone is hot)
            color.b = scene.sample(linearSampler, uv + shift * 1.25).b;
        }
    } else {
        color = scene.sample(linearSampler, uv);
    }

    uint tile = (pixel.y / tileInfo.y) * tileInfo.x + pixel.x / tileInfo.y;
    for (uint k = tileOffsets[tile]; k < tileOffsets[tile + 1]; ++k) {
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
        float3 environment = mix(look[1].rgb, look[2].rgb,
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

    color.rgb *= look[0].rgb;   // white balance
    // Vignette: round, from the middle, in halves of the narrow side (the round display's edge is 1).
    if (look[3].x > 0.0) {
        float radius = length(float2(pixel) + 0.5 - size * 0.5) / (0.5 * min(size.x, size.y));
        float edge = saturate((radius - look[3].y) / (look[3].z - look[3].y));
        edge = edge * edge * edge * (edge * (edge * 6.0 - 15.0) + 10.0);   // eases in very gently
        color.rgb *= 1.0 - look[3].x * edge;
    }
    output.write(color, pixel);
}
