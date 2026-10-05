#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

constant int kWaveCount = 14;

// Water colour by world height; shared by the backdrop and distance fog so they meet seamlessly.
static half3 waterColor(float y) {
    float t = saturate((y + 0.7) / 1.4);
    half3 deep = half3(0.0, 0.05, 0.14);
    half3 mid = half3(0.02, 0.26, 0.44);
    half3 shallow = half3(0.18, 0.62, 0.78);
    return t < 0.6 ? mix(deep, mid, half(t / 0.6)) : mix(mid, shallow, half((t - 0.6) / 0.4));
}

// Sunlight refracted through a wavy surface: brightness ~ 1/|det J| of the refraction map,
// where J = I + focus * Hessian(height). Evaluated per channel with slightly different focus for dispersion.
static half3 caustics(float2 p, float time, float focus) {
    float hxx = 0, hyy = 0, hxy = 0;
    for (int i = 0; i < kWaveCount; i++) {
        float fi = float(i);
        float angle = fi * 2.39996 + 0.3;
        float2 dir = float2(cos(angle), sin(angle));
        float freq = 1.0 + 0.37 * fmod(fi, 4.0) + 0.11 * fi;
        float speed = 0.6 + 0.13 * fi;
        float w = -sin(dot(dir, p) * freq + time * speed + fi * 1.7) / float(kWaveCount);
        hxx += w * dir.x * dir.x;
        hyy += w * dir.y * dir.y;
        hxy += w * dir.x * dir.y;
    }
    float3 f = focus * float3(0.96, 1.0, 1.04);
    float3 det = (1 + f * hxx) * (1 + f * hyy) - f * f * hxy * hxy;
    return half3(pow(0.6 / (abs(det) + 0.6), 2.2));
}

// PBR passthrough that adds caustic light on upward-facing surfaces.
static void causticSurfaceImpl(realitykit::surface_parameters params, float4 custom) {
    constexpr sampler s(address::repeat, filter::linear, mip_filter::linear);
    auto tex = params.textures();
    auto material = params.material_constants();

    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;

    half3 baseColor = tex.base_color().sample(s, uv).rgb * half3(material.base_color_tint());
    half3 emissive = tex.emissive_color().sample(s, uv).rgb * half3(material.emissive_color());

    float3 position = params.geometry().world_position();
    float3 normal = normalize(params.geometry().normal());
    float facing = saturate(normal.y * 0.7 + 0.3);
    half3 light = caustics(position.xz * custom.x, params.uniforms().time() * 0.5, custom.y);
    emissive += baseColor * light * half3(0.75, 0.95, 1.0) * half(custom.z * facing);

    float fog = saturate((-position.z - 0.2) / 1.3) * custom.w;
    baseColor *= half(1.0 - fog);
    emissive = mix(emissive, waterColor(position.y), half(fog));

    auto surface = params.surface();
    surface.set_base_color(baseColor);
    surface.set_emissive_color(emissive);
    surface.set_roughness(tex.roughness().sample(s, uv).r * half(material.roughness_scale()));
    surface.set_metallic(tex.metallic().sample(s, uv).r * half(material.metallic_scale()));
    surface.set_specular(tex.specular().sample(s, uv).r * half(material.specular_scale()));
    surface.set_ambient_occlusion(tex.ambient_occlusion().sample(s, uv).r);
    surface.set_clearcoat(tex.clearcoat().sample(s, uv).r * half(material.clearcoat_scale()));
    surface.set_clearcoat_roughness(tex.clearcoat_roughness().sample(s, uv).r * half(material.clearcoat_roughness_scale()));
    surface.set_opacity(half(material.opacity_scale()));
}

// custom_parameter: x = pattern frequency per metre, y = focus, z = strength, w = distance fog amount.
[[visible]]
void causticSurface(realitykit::surface_parameters params) {
    causticSurfaceImpl(params, params.uniforms().custom_parameter());
}

// Fin geometry uses the custom parameter for its ripple, so keep the caustic tuning fixed here.
[[visible]]
void causticFinSurface(realitykit::surface_parameters params) {
    causticSurfaceImpl(params, float4(32.0, 6.0, 1.4, 0.0));
}

static void finWave(realitykit::geometry_parameters params, float3 axis, float cross) {
    float4 custom = params.uniforms().custom_parameter();
    float2 uv = params.geometry().uv1();
    float u = clamp(uv.x, 0.0, 1.0);
    float wave = sin(6.2831853 * (u / custom.y - custom.w + uv.y * cross));
    params.geometry().set_model_position_offset(axis * custom.x * pow(u, custom.z) * wave);
}

[[visible]]
void finWaveTail(realitykit::geometry_parameters params) {
    finWave(params, float3(1.0, 0.0, 0.0), 2.11);
}

[[visible]]
void finWaveDorsal(realitykit::geometry_parameters params) {
    finWave(params, float3(0.0003, -0.0784, 0.9969), 2.11);
}

[[visible]]
void finWavePectoral(realitykit::geometry_parameters params) {
    finWave(params, float3(-0.5769, 0.7816, -0.2373), 2.11);
}

// Unlit clear bubble: only a sharp sun highlight and a faint fresnel rim are visible; tint comes from base_color_tint.
[[visible]]
void bubbleSurface(realitykit::surface_parameters params) {
    float3 normal = normalize(params.geometry().normal());
    float3 view = normalize(params.geometry().view_direction());
    float3 sun = normalize(float3(0.1, 1.0, 0.25));

    float nv = saturate(dot(normal, view));
    float rim = pow(1.0 - nv, 3.0) * 0.45;
    float spec = pow(saturate(dot(normal, normalize(sun + view))), 90.0);

    half3 tint = half3(params.material_constants().base_color_tint());
    half3 color = tint * half(rim + spec * 4.0);

    params.surface().set_base_color(color);
    params.surface().set_emissive_color(color);
    params.surface().set_opacity(half(saturate(rim + spec)));
}

// Unlit sea backdrop: depth gradient, slanted god rays and a shimmering surface band at the top.
[[visible]]
void backdropSurface(realitykit::surface_parameters params) {
    float3 position = params.geometry().world_position();
    float time = params.uniforms().time();

    half3 color = waterColor(position.y);

    float u = position.x + position.y * 0.35;
    float rays = 0;
    rays += pow(saturate(sin(u * 23.0 + time * 0.23) * 0.5 + 0.5), 6.0);
    rays += pow(saturate(sin(u * 13.7 - time * 0.17 + 1.3) * 0.5 + 0.5), 8.0) * 0.8;
    rays += pow(saturate(sin(u * 37.3 + time * 0.31 + 4.1) * 0.5 + 0.5), 10.0) * 0.5;
    rays += pow(saturate(sin(u * 51.9 - time * 0.27 + 2.6) * 0.5 + 0.5), 12.0) * 0.4;
    float rayFade = pow(saturate((position.y + 0.5) / 1.2), 2.0);
    color += half3(0.35, 0.7, 0.8) * half(rays * rayFade * 0.35);

    float surfaceBand = smoothstep(0.35, 0.65, position.y);
    half3 shimmer = caustics(float2(position.x * 12.0, position.y * 40.0), time * 0.5, 5.0);
    color += half3(0.5, 0.85, 0.95) * shimmer * half(surfaceBand * 0.5);

    params.surface().set_base_color(color);
    params.surface().set_emissive_color(color);
}
