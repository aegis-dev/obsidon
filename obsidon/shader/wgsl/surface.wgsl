// ---------------------------------------------------------------------------
// Obsidon engine library - surface shaders (meshes)
// ---------------------------------------------------------------------------

struct Draw_Data {
    model:         mat4x4f, // camera-relative model matrix
    normal_matrix: mat4x4f,
    tint:          vec4f,
}

struct Light {
    position_range: vec4f, // camera-relative position, range
    color:          vec4f, // linear rgb * intensity, w: 0 = point, 1 = spot
    direction_cone: vec4f, // spot direction (where it shines), cos(outer angle)
    cone_inner:     vec4f, // cos(inner angle), shadow slot (-1 = none), shadow texel angle
}

struct Vertex_In {
    @location(0) position: vec3f,
    @location(1) normal:   vec3f,
    @location(2) uv:       vec2f,
    @location(3) color:    vec4f,
    @location(4) tangent:  vec4f,
    @builtin(instance_index) instance: u32,
}

@group(0) @binding(1) var<storage, read> draws: array<Draw_Data>;
@group(0) @binding(2) var<storage, read> lights: array<Light>;
@group(0) @binding(3) var shadow_map: texture_depth_2d_array;
@group(0) @binding(4) var shadow_sampler: sampler_comparison;
@group(0) @binding(5) var ao_texture: texture_2d<f32>;
@group(0) @binding(6) var spot_shadow_map: texture_depth_2d_array;

var<private> obs_draw: Draw_Data;

fn obs_object_to_world(p: vec3f) -> vec3f {
    return (obs_draw.model * vec4f(p, 1.0)).xyz;
}

fn obs_object_to_world_dir(d: vec3f) -> vec3f {
    return normalize((obs_draw.normal_matrix * vec4f(d, 0.0)).xyz);
}

// Directions on the surface (tangents) follow the model matrix, not the normal matrix.
fn obs_object_to_world_vector(d: vec3f) -> vec3f {
    return normalize((obs_draw.model * vec4f(d, 0.0)).xyz);
}

// Apply a tangent space normal map sample (0..1 rgb) to a surface normal.
fn obs_perturb_normal(normal: vec3f, tangent: vec4f, map: vec3f, strength: f32) -> vec3f {
    let n = normalize(normal);
    if (dot(tangent.xyz, tangent.xyz) < 1e-8) {
        return n;
    }
    let t = normalize(tangent.xyz - n * dot(n, tangent.xyz));
    let b = cross(n, t) * select(1.0, -1.0, tangent.w < 0.0);
    var ts = map * 2.0 - 1.0;
    ts = vec3f(ts.xy * strength, ts.z);
    return normalize(t * ts.x + b * ts.y + n * ts.z);
}

fn obs_ambient(normal: vec3f) -> vec3f {
    let t = normalize(normal).y * 0.5 + 0.5;
    return mix(frame.ambient_ground.rgb, frame.ambient_sky.rgb, t);
}

fn obs_ao() -> f32 {
    if (frame.ssao_params.x < 0.5) {
        return 1.0;
    }
    return textureLoad(ao_texture, vec2i(obs_frag_coord.xy), 0).r;
}

fn obs_pcf_sun(uv: vec2f, layer: i32, depth: f32) -> f32 {
    let radius = i32(frame.shadow_params.z);
    let texel = frame.shadow_params2.x;
    var sum = 0.0;
    var count = 0.0;
    for (var y = -radius; y <= radius; y++) {
        for (var x = -radius; x <= radius; x++) {
            sum += textureSampleCompareLevel(shadow_map, shadow_sampler, uv + vec2f(f32(x), f32(y)) * texel, layer, depth);
            count += 1.0;
        }
    }
    return sum / count;
}

fn obs_pcf_spot(uv: vec2f, layer: i32, depth: f32) -> f32 {
    let radius = i32(frame.shadow_params.z);
    let texel = frame.shadow_params2.w;
    var sum = 0.0;
    var count = 0.0;
    for (var y = -radius; y <= radius; y++) {
        for (var x = -radius; x <= radius; x++) {
            sum += textureSampleCompareLevel(spot_shadow_map, shadow_sampler, uv + vec2f(f32(x), f32(y)) * texel, layer, depth);
            count += 1.0;
        }
    }
    return sum / count;
}

// Sun shadow factor (0 = shadowed, 1 = lit) using cascaded shadow maps.
fn obs_shadow(world_pos: vec3f, normal: vec3f) -> f32 {
    if (frame.shadow_params.x < 0.5) {
        return 1.0;
    }
    let count = i32(frame.shadow_params.y);
    let view_depth = -(frame.view * vec4f(world_pos, 1.0)).z;
    var cascade = -1;
    for (var i = 0; i < count; i++) {
        if (view_depth < frame.shadow_splits[i]) {
            cascade = i;
            break;
        }
    }
    if (cascade < 0) {
        return 1.0;
    }

    let n = normalize(normal);
    let ndl = clamp(dot(n, frame.sun_direction.xyz), 0.0, 1.0);
    // Normal offset: push the lookup out of the surface, more at grazing angles.
    let offset = n * frame.shadow_normal_bias[cascade] * (1.0 - ndl * 0.5);
    let lp = frame.light_view_proj[cascade] * vec4f(world_pos + offset, 1.0);
    let ndc = lp.xyz / lp.w;
    let uv = vec2f(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0 || ndc.z >= 1.0 || ndc.z <= 0.0) {
        return 1.0;
    }
    let lit = obs_pcf_sun(uv, cascade, ndc.z - frame.shadow_depth_bias[cascade]);

    // Fade out towards the end of the shadow distance.
    let fade_start = frame.shadow_params2.z;
    let fade = clamp((view_depth - fade_start) / max(frame.shadow_params2.y - fade_start, 0.0001), 0.0, 1.0);
    return mix(lit, 1.0, fade);
}

// Shadow factor of a spot light (1 when it has no shadow map).
fn obs_spot_shadow(light: Light, world_pos: vec3f, normal: vec3f) -> f32 {
    let slot = i32(light.cone_inner.y);
    if (slot < 0) {
        return 1.0;
    }
    let n = normalize(normal);
    let dist = length(light.position_range.xyz - world_pos);
    let offset = n * dist * light.cone_inner.z * 1.5;
    let lp = frame.spot_view_proj[slot] * vec4f(world_pos + offset, 1.0);
    if (lp.w <= 0.0) {
        return 1.0;
    }
    let ndc = lp.xyz / lp.w;
    let uv = vec2f(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0 || ndc.z >= 1.0 || ndc.z <= 0.0) {
        return 1.0;
    }
    return obs_pcf_spot(uv, slot, ndc.z - 0.00005);
}

fn obs_light_attenuation(d: f32, range: f32) -> f32 {
    let x = clamp(1.0 - (d * d) / (range * range), 0.0, 1.0);
    return x * x;
}

fn obs_spot_factor(light: Light, to_light_dir: vec3f) -> f32 {
    if (light.color.w < 0.5) {
        return 1.0;
    }
    let cd = dot(-to_light_dir, light.direction_cone.xyz);
    return smoothstep(light.direction_cone.w, light.cone_inner.x, cd);
}

fn obs_direct_diffuse(world_pos: vec3f, normal: vec3f) -> vec3f {
    let n = normalize(normal);
    var result = vec3f(0.0);

    let sun_ndl = dot(n, frame.sun_direction.xyz);
    if (sun_ndl > 0.0) {
        result += frame.sun_color.rgb * sun_ndl * obs_shadow(world_pos, n);
    }

    for (var i = 0u; i < frame.counts.x; i++) {
        let light = lights[i];
        let to_light = light.position_range.xyz - world_pos;
        let d = length(to_light);
        if (d >= light.position_range.w) {
            continue;
        }
        let l = to_light / max(d, 0.0001);
        let ndl = max(dot(n, l), 0.0);
        var shadow = 1.0;
        if (light.color.w > 0.5) {
            shadow = obs_spot_shadow(light, world_pos, n);
        }
        result += light.color.rgb * ndl * obs_light_attenuation(d, light.position_range.w) * obs_spot_factor(light, l) * shadow;
    }
    return result;
}

fn obs_lighting_vs(world_pos: vec3f, normal: vec3f) -> vec3f {
    return obs_ambient(normal) + obs_direct_diffuse(world_pos, normal);
}

fn obs_lighting_fs(world_pos: vec3f, normal: vec3f) -> vec3f {
    let ao = obs_ao();
    let direct_ao = mix(1.0, ao, frame.ssao_params2.x);
    return obs_ambient(normal) * ao + obs_direct_diffuse(world_pos, normal) * direct_ao;
}

fn obs_specular(world_pos: vec3f, normal: vec3f, shininess: f32) -> vec3f {
    let n = normalize(normal);
    let v = normalize(-world_pos);
    var result = vec3f(0.0);
    let s = max(shininess, 1.0);
    // Energy-ish normalization so small highlights stay bright.
    let norm = (s + 8.0) / 25.13;

    let sun_ndl = dot(n, frame.sun_direction.xyz);
    if (sun_ndl > 0.0) {
        let h = normalize(frame.sun_direction.xyz + v);
        result += frame.sun_color.rgb * pow(max(dot(n, h), 0.0), s) * norm * sun_ndl * obs_shadow(world_pos, n);
    }

    for (var i = 0u; i < frame.counts.x; i++) {
        let light = lights[i];
        let to_light = light.position_range.xyz - world_pos;
        let d = length(to_light);
        if (d >= light.position_range.w) {
            continue;
        }
        let l = to_light / max(d, 0.0001);
        let ndl = dot(n, l);
        if (ndl <= 0.0) {
            continue;
        }
        let h = normalize(l + v);
        var shadow = 1.0;
        if (light.color.w > 0.5) {
            shadow = obs_spot_shadow(light, world_pos, n);
        }
        result += light.color.rgb * pow(max(dot(n, h), 0.0), s) * norm * ndl * obs_light_attenuation(d, light.position_range.w) * obs_spot_factor(light, l) * shadow;
    }
    return result;
}
