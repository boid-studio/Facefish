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
    output.write(color, pixel);
}
