#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

constant int kWaveCount = 8;   // fewer waves = cheaper caustics; 8 still looks organic

// Water colour by world height; shared by the backdrop and distance fog so they meet seamlessly.
static half3 waterColor(float y) {
    float t = saturate((y + 0.7) / 1.4);
    half3 deep = half3(0.0, 0.05, 0.14);
    half3 mid = half3(0.02, 0.26, 0.44);
    half3 shallow = half3(0.18, 0.62, 0.78);
    return t < 0.6 ? mix(deep, mid, half(t / 0.6)) : mix(mid, shallow, half((t - 0.6) / 0.4));
}

static half3 underwaterBackdrop(float3 position, float time) {
    half3 color = waterColor(position.y);
    float u = position.x;
    float rays = 0;
    rays += pow(saturate(sin(u * 23.0 + time * 0.23) * 0.5 + 0.5), 6.0);
    rays += pow(saturate(sin(u * 13.7 - time * 0.17 + 1.3) * 0.5 + 0.5), 8.0) * 0.8;
    rays += pow(saturate(sin(u * 37.3 + time * 0.31 + 4.1) * 0.5 + 0.5), 10.0) * 0.5;
    rays += pow(saturate(sin(u * 51.9 - time * 0.27 + 2.6) * 0.5 + 0.5), 12.0) * 0.4;
    float rayFade = pow(saturate((position.y + 0.5) / 1.2), 2.0);
    return color + half3(0.35, 0.7, 0.8) * half(rays * rayFade * 0.35);
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

// Seen through water: reds are absorbed a little and the water's own blue scatters in.
// `tintScale` (the material's tint brightness) scales the scatter with the material.
static half3 underwaterTint(half3 color, float3 position, half tintScale) {
    // Reds absorbed, and a slow shimmer of brightness as surface light passes over.
    half3 tinted = color * half3(0.86, 0.96, 1.0);
    return mix(tinted, waterColor(position.y + 0.3), half(0.06));
}

static half3 waterScatter(float3 position, half tintScale, float time) {
    float flicker = 0.85 + 0.15 * sin(time * 0.9 + position.x * 6.0) * sin(time * 0.53 + position.y * 4.0 + 1.3);
    return waterColor(position.y + 0.3) * half(0.07 * flicker) * tintScale;
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
    half tintScale = half(dot(float3(material.base_color_tint()), float3(0.333)));
    baseColor = underwaterTint(baseColor, position, tintScale);
    emissive += waterScatter(position, tintScale, params.uniforms().time());
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
    surface.set_opacity(tex.opacity().sample(s, uv).r * half(material.opacity_scale())
                        * tex.base_color().sample(s, uv).a);
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

// Lightweight PBR passthrough used while caustics are disabled. Keeping a CustomMaterial on
// animated meshes avoids changing RealityKit's render path for skinning and blend shapes.
[[visible]]
void baseSurface(realitykit::surface_parameters params) {
    constexpr sampler s(address::repeat, filter::linear, mip_filter::linear);
    auto tex = params.textures();
    auto material = params.material_constants();

    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;

    auto surface = params.surface();
    surface.set_base_color(tex.base_color().sample(s, uv).rgb * half3(material.base_color_tint()));
    surface.set_emissive_color(tex.emissive_color().sample(s, uv).rgb * half3(material.emissive_color()));
    surface.set_roughness(tex.roughness().sample(s, uv).r * half(material.roughness_scale()));
    surface.set_metallic(tex.metallic().sample(s, uv).r * half(material.metallic_scale()));
    surface.set_specular(tex.specular().sample(s, uv).r * half(material.specular_scale()));
    surface.set_ambient_occlusion(tex.ambient_occlusion().sample(s, uv).r);
    surface.set_clearcoat(tex.clearcoat().sample(s, uv).r * half(material.clearcoat_scale()));
    surface.set_clearcoat_roughness(tex.clearcoat_roughness().sample(s, uv).r * half(material.clearcoat_roughness_scale()));
    surface.set_opacity(tex.opacity().sample(s, uv).r * half(material.opacity_scale())
                        * tex.base_color().sample(s, uv).a);
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

// Transparent fallback for systems without scene-color post-processing.
[[visible]]
void bubbleSurface(realitykit::surface_parameters params) {
    float3 normal = normalize(params.geometry().normal());
    float3 view = normalize(params.geometry().view_direction());
    float3 sun = normalize(float3(0.1, 1.0, 0.25));

    float nv = saturate(dot(normal, view));
    float3 reflected = reflect(-view, normal);
    float fresnel = 0.0204 + 0.9796 * pow(1.0 - nv, 5.0);
    half3 reflectedColor = mix(
        half3(0.18, 0.42, 0.55),
        half3(0.7, 0.9, 1.0),
        half(saturate(reflected.y * 0.5 + 0.5))
    );
    float sunReflection = pow(saturate(dot(reflected, sun)), 160.0);
    float spec = pow(saturate(dot(normal, normalize(sun + view))), 90.0);
    float surfaceReflection = smoothstep(0.45, 0.95, reflected.y)
        * smoothstep(0.05, 0.3, normal.y);

    half3 tint = half3(params.material_constants().base_color_tint());
    float reflectionWeight = 0.22 * fresnel;
    float highlightWeight = saturate(spec * 0.7 + sunReflection * 0.5 + surfaceReflection * 0.6);
    float opacity = reflectionWeight + highlightWeight;
    half3 color = (
        reflectedColor * half(reflectionWeight)
        + tint * half(highlightWeight)
    ) / half(max(opacity, 0.001));

    params.surface().set_base_color(color);
    params.surface().set_emissive_color(color);
    params.surface().set_opacity(half(saturate(opacity)));
}

[[visible]]
void backdropBaseSurface(realitykit::surface_parameters params) {
    half3 color = waterColor(params.geometry().world_position().y);
    params.surface().set_base_color(color);
    params.surface().set_emissive_color(color);
}

// Unlit sea backdrop: depth gradient and vertical god rays.
[[visible]]
void backdropSurface(realitykit::surface_parameters params) {
    float3 position = params.geometry().world_position();
    float time = params.uniforms().time();

    half3 color = underwaterBackdrop(position, time);

    params.surface().set_base_color(color);
    params.surface().set_emissive_color(color);
}

// MARK: - Face caustics (the body)

// Swimming: everything behind the gills bends sideways in a wave travelling toward the tail,
// growing toward the tail stalk; the face and front stay still. Mesh space keeps Blender's axes:
// +Y runs from the snout (-1.1) to the tail stalk (+0.7), +X is the fish's left.
// custom_parameter: x = bend amplitude (mesh units at the tail), y = wave phase.
static float bodyBendWeight(float y) {
    float w = smoothstep(0.1, 0.72, y);
    return w * w;
}

[[visible]]
void faceBodyBend(realitykit::geometry_parameters params) {
    float4 custom = params.uniforms().custom_parameter();
    if (custom.x == 0.0) { return; }
    float3 p = params.geometry().model_position();
    float offset = custom.x * bodyBendWeight(p.y) * sin(custom.y - 3.2 * p.y);
    params.geometry().set_model_position_offset(float3(offset, 0, 0));
}

// Strong caustics on the fish's body, projected from a fake water surface above and a little in
// front, so they land on the front-facing face too, not only the top of the head.
// custom_parameter: x = swim bend amplitude, y = bend phase (both for faceBodyBend), z = caustic strength, w = blush.
[[visible]]
void faceCausticSurface(realitykit::surface_parameters params) {
    constexpr sampler s(address::repeat, filter::linear, mip_filter::linear);
    auto tex = params.textures();
    auto material = params.material_constants();
    float4 custom = params.uniforms().custom_parameter();

    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;

    half3 baseColor = tex.base_color().sample(s, uv).rgb * half3(material.base_color_tint());
    float3 position = params.geometry().world_position();
    float3 normal = normalize(params.geometry().normal());
    half tintScale = half(dot(float3(material.base_color_tint()), float3(0.333)));
    baseColor = underwaterTint(baseColor, position, tintScale);

    // Light falls from above, tilted toward the viewer: project along that direction.
    float2 projected = float2(position.x, position.z - position.y * 0.9);
    float t = params.uniforms().time();
    half3 light = caustics(projected * 22.0, t * 0.6, 9.0);   // pattern per metre, focus
    light = pow(light, half3(1.7)) * half(1.8);          // thin, bright lines
    float facing = saturate(0.45 + 0.55 * normal.y + 0.25 * normal.z);
    half3 emissive = baseColor * light * half3(0.8, 0.97, 1.0) * half(custom.z * facing);
    baseColor *= half(1.0 - 0.25 * saturate(custom.z));  // a little darker between the lines

    emissive += waterScatter(position, tintScale, t);

    // Blush (custom.w, 0...1): rosy cheeks under the eyes. Model space keeps Blender's axes
    // (+X the fish's left, -Y forward, +Z up); only the front of the face, not the back of the head.
    if (custom.w > 0.0) {
        float3 p = params.geometry().model_position();
        float2 d = float2((abs(p.x) - 0.45) / 0.17, (p.z + 0.3) / 0.12);
        float cheek = saturate(1.0 - dot(d, d)) * (1.0 - smoothstep(-0.65, -0.45, p.y));
        half amount = half(custom.w * cheek * cheek * (3.0 - 2.0 * cheek));
        baseColor = mix(baseColor, baseColor * half3(1.3, 0.5, 0.6), amount * half(0.85));
        emissive += half3(0.3, 0.03, 0.08) * amount;
    }

    // Shine: the metallic map marks the purple dots; they get a smoother, glossier surface.
    half dots = tex.metallic().sample(s, uv).r;
    half roughness = tex.roughness().sample(s, uv).r * half(material.roughness_scale());
    roughness *= half(1.0) - half(0.65) * dots;
    half clearcoat = max(tex.clearcoat().sample(s, uv).r * half(material.clearcoat_scale()), dots * half(0.9));

    // Normal map (the dots' relief), a bit stronger on the dots so they catch the light.
    // Only red/green are used and blue is rebuilt (the map is flat grey off the dots, not blue).
    half2 slope = tex.normal().sample(s, uv).rg * half(2.0) - half(1.0);
    slope *= half(1.0) + half(1.2) * dots;
    half3 bump = half3(slope, sqrt(max(half(0.0), half(1.0) - dot(slope, slope))));

    auto surface = params.surface();
    surface.set_base_color(baseColor);
    surface.set_emissive_color(emissive);
    surface.set_normal(float3(normalize(bump)));
    surface.set_roughness(roughness);
    surface.set_metallic(tex.metallic().sample(s, uv).r * half(material.metallic_scale()));
    surface.set_specular(saturate(tex.specular().sample(s, uv).r * half(material.specular_scale()) + dots * half(0.3)));
    surface.set_ambient_occlusion(tex.ambient_occlusion().sample(s, uv).r);
    surface.set_clearcoat(clearcoat);
    surface.set_clearcoat_roughness(half(0.08));
}
