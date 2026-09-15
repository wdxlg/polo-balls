shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// V11 Snapshot Trail Studio.
// 支持：多种样式、开头/结尾颜色与 Alpha、动态采样数、模糊/拖尾/扭曲曲线。
instance uniform float progress : hint_range(0.0, 1.0) = 0.0;
instance uniform vec2 trail_direction = vec2(1.0, 0.0);
instance uniform float source_flip_h : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 start_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
instance uniform vec4 end_color : source_color = vec4(0.68, 0.82, 1.0, 1.0);
// x=start_alpha, y=end_alpha, z=start_blur_px, w=end_blur_px
instance uniform vec4 visual_params_a = vec4(0.38, 0.0, 1.8, 3.0);
// x=start_smear_px, y=end_smear_px, z=start_distort_px, w=end_distort_px
instance uniform vec4 visual_params_b = vec4(6.0, 2.5, 0.0, 1.25);
instance uniform int style_mode = 1;
instance uniform int sample_count = 9;
instance uniform int fade_mode = 1;

varying vec4 vertex_modulate;

void vertex() {
    vertex_modulate = COLOR;
}

vec2 map_region_uv(vec2 local_uv, vec2 region_origin, vec2 region_size, float flip_h_value) {
    vec2 mapped = local_uv;
    if (flip_h_value > 0.5) {
        mapped.x = 1.0 - mapped.x;
    }
    return region_origin + mapped * region_size;
}

float region_inside(vec2 local_uv) {
    return step(0.0, local_uv.x) * step(local_uv.x, 1.0)
        * step(0.0, local_uv.y) * step(local_uv.y, 1.0);
}

float curve_t(float t, int mode) {
    t = clamp(t, 0.0, 1.0);
    if (mode == 0) {
        return t;
    }
    if (mode == 2) {
        return 1.0 - (1.0 - t) * (1.0 - t);
    }
    if (mode == 3) {
        return t * t;
    }
    return t * t * (3.0 - 2.0 * t);
}

void fragment() {
    vec2 region_a = REGION_RECT.xy;
    vec2 region_b = REGION_RECT.xy + REGION_RECT.zw;
    vec2 region_origin = min(region_a, region_b);
    vec2 region_size = max(abs(REGION_RECT.zw), vec2(0.000001));
    vec2 local_uv = (UV - region_origin) / region_size;

    vec2 dir = trail_direction;
    if (length(dir) < 0.0001) {
        dir = vec2(1.0, 0.0);
    } else {
        dir = normalize(dir);
    }
    vec2 side = vec2(-dir.y, dir.x);

    float raw_t = clamp(progress, 0.0, 1.0);
    float t = curve_t(raw_t, fade_mode);
    float alpha_value = mix(visual_params_a.x, visual_params_a.y, t);
    float blur_px = mix(visual_params_a.z, visual_params_a.w, t);
    float smear_px = mix(visual_params_b.x, visual_params_b.y, t);
    float distort_px = mix(visual_params_b.z, visual_params_b.w, t);
    vec4 tint = mix(start_color, end_color, t);

    // 样式只改变采样/着色方式，不改变用户设置的基础数值。
    float smear_mul = 1.0;
    float blur_mul = 1.0;
    float distortion_mul = 1.0;
    float edge_power = 1.0;
    if (style_mode == 0) { // Clean
        blur_mul = 0.22;
        distortion_mul = 0.0;
        edge_power = 0.35;
    } else if (style_mode == 2) { // Glow
        blur_mul = 1.35;
        smear_mul = 1.15;
        edge_power = 0.72;
    } else if (style_mode == 3) { // Energy
        smear_mul = 1.25;
        distortion_mul = 1.8;
        edge_power = 0.60;
    } else if (style_mode == 4) { // Smoke
        blur_mul = 1.75;
        smear_mul = 0.82;
        distortion_mul = 1.25;
        edge_power = 1.55;
    } else if (style_mode == 5) { // Silhouette
        blur_mul = 0.55;
        smear_mul = 0.75;
        distortion_mul = 0.45;
        edge_power = 0.45;
    }

    float smear = max(smear_px * smear_mul, 0.0);
    float blur = max(blur_px * blur_mul, 0.0);
    float distortion = max(distort_px * distortion_mul, 0.0);
    vec2 pixel_dir = vec2(dir.x * TEXTURE_PIXEL_SIZE.x, dir.y * TEXTURE_PIXEL_SIZE.y);
    vec2 pixel_side = vec2(side.x * TEXTURE_PIXEL_SIZE.x, side.y * TEXTURE_PIXEL_SIZE.y);

    int count = min(max(sample_count, 1), 16);
    float gathered_alpha_sum = 0.0;
    vec3 gathered_premul_rgb = vec3(0.0);
    float gathered_weight = 0.0;

    // 动态采样数：1~16。Godot shader 支持 for/break；采样数越高越顺滑但越贵。
    for (int i = 0; i < 16; i++) {
        if (i >= count) {
            break;
        }
        float fi = count <= 1 ? 0.0 : float(i) / float(count - 1);
        float spread = pow(fi, 1.12);
        float jitter = sin(float(i) * 2.399963 + raw_t * 3.0);
        float wave = sin(fi * 12.0 + raw_t * 5.0) * distortion * (0.25 + spread * 0.75);
        if (style_mode == 4) {
            wave += sin(fi * 5.0 - raw_t * 4.0) * distortion * 0.65;
        }

        vec2 sample_local = local_uv
            + pixel_dir * (smear * spread)
            + pixel_side * (blur * jitter * spread + wave);

        vec4 texel = texture(TEXTURE, map_region_uv(sample_local, region_origin, region_size, source_flip_h));
        texel.a *= region_inside(sample_local);

        float weight = exp(-2.15 * spread);
        if (style_mode == 0) {
            weight = exp(-3.2 * spread);
        } else if (style_mode == 4) {
            weight = exp(-1.35 * spread);
        }

        gathered_alpha_sum += texel.a * weight;
        gathered_premul_rgb += texel.rgb * texel.a * weight;
        gathered_weight += weight;
    }

    float averaged_alpha = gathered_alpha_sum / max(gathered_weight, 0.0001);
    vec3 source_rgb = gathered_premul_rgb / max(gathered_alpha_sum, 0.0001);

    // 不同样式的颜色处理。
    vec3 styled_rgb = source_rgb;
    if (style_mode == 1) { // Soft
        vec3 gray = vec3(dot(source_rgb, vec3(0.299, 0.587, 0.114)));
        styled_rgb = mix(gray, source_rgb, 0.88);
    } else if (style_mode == 2) { // Glow
        styled_rgb = min(source_rgb * 1.18 + tint.rgb * 0.18, vec3(2.0));
    } else if (style_mode == 3) { // Energy
        float lum = dot(source_rgb, vec3(0.299, 0.587, 0.114));
        styled_rgb = mix(vec3(lum), source_rgb, 1.25);
    } else if (style_mode == 4) { // Smoke
        float lum = dot(source_rgb, vec3(0.299, 0.587, 0.114));
        styled_rgb = mix(vec3(lum), source_rgb, 0.28);
    } else if (style_mode == 5) { // Silhouette
        styled_rgb = vec3(1.0);
    }

    float edge_alpha = pow(clamp(averaged_alpha * 1.18, 0.0, 1.0), edge_power);
    float final_alpha = edge_alpha * alpha_value * tint.a * vertex_modulate.a;
    vec3 final_rgb = styled_rgb * tint.rgb * vertex_modulate.rgb;

    COLOR = vec4(final_rgb * final_alpha, final_alpha);
}
