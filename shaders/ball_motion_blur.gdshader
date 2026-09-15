shader_type canvas_item;
render_mode unshaded, blend_mix;

// V114：ball 通用方向性运动模糊。
// 不是历史残影；只处理当前帧，并允许 ball.gd Inspector 自由调节强度/长度/扩散/清晰核心。
instance uniform vec2 blur_direction = vec2(1.0, 0.0);
instance uniform vec2 blur_uv_direction = vec2(1.0, 0.0);
instance uniform float blur_strength : hint_range(0.0, 1.0) = 0.0;
instance uniform float blur_pixels : hint_range(0.0, 256.0) = 56.0;
instance uniform float blur_alpha : hint_range(0.0, 1.0) = 1.0;
instance uniform float forward_stretch : hint_range(0.0, 4.0) = 1.35;
instance uniform float sample_spread : hint_range(0.1, 4.0) = 1.55;
instance uniform float core_sharpness : hint_range(0.0, 1.0) = 0.05;
instance uniform vec2 frame_uv_min = vec2(0.0, 0.0);
instance uniform vec2 frame_uv_max = vec2(1.0, 1.0);
instance uniform vec4 tint_color : source_color = vec4(1.0);
instance uniform float tint_mix : hint_range(0.0, 1.0) = 0.0;

varying vec4 vertex_modulate;

vec2 safe_direction(vec2 value) {
    float len = length(value);
    if (len < 0.0001) {
        return vec2(1.0, 0.0);
    }
    return value / len;
}

float uv_inside_frame(vec2 uv, vec2 uv_min, vec2 uv_max) {
    return step(uv_min.x, uv.x) * step(uv.x, uv_max.x)
        * step(uv_min.y, uv.y) * step(uv.y, uv_max.y);
}

void vertex() {
    vertex_modulate = COLOR;

    vec2 dir = safe_direction(blur_direction);
    float strength = clamp(blur_strength, 0.0, 1.0);

    // 只把运动方向前缘往前展开；forward_stretch 完全由 Inspector 控制。
    float leading_side = step(0.0, dot(VERTEX, dir));
    VERTEX += dir * blur_pixels * strength * max(forward_stretch, 0.0) * leading_side;
}

void fragment() {
    vec2 dir = safe_direction(blur_uv_direction);
    float strength = clamp(blur_strength, 0.0, 1.0);

    vec2 uv_min = min(frame_uv_min, frame_uv_max);
    vec2 uv_max = max(frame_uv_min, frame_uv_max);
    vec2 step_uv = dir * TEXTURE_PIXEL_SIZE * blur_pixels * strength * max(sample_spread, 0.01);

    // 16 个连续采样点组成更密的方向卷积核。sample_spread 决定采样展开距离。
    vec2 uv0  = UV;
    vec2 uv1  = UV - step_uv * 0.045;
    vec2 uv2  = UV - step_uv * 0.095;
    vec2 uv3  = UV - step_uv * 0.150;
    vec2 uv4  = UV - step_uv * 0.210;
    vec2 uv5  = UV - step_uv * 0.275;
    vec2 uv6  = UV - step_uv * 0.345;
    vec2 uv7  = UV - step_uv * 0.420;
    vec2 uv8  = UV - step_uv * 0.500;
    vec2 uv9  = UV - step_uv * 0.585;
    vec2 uv10 = UV - step_uv * 0.675;
    vec2 uv11 = UV - step_uv * 0.770;
    vec2 uv12 = UV - step_uv * 0.870;
    vec2 uv13 = UV - step_uv * 0.975;
    vec2 uv14 = UV - step_uv * 1.085;
    vec2 uv15 = UV - step_uv * 1.200;

    vec4 c0  = texture(TEXTURE, clamp(uv0,  uv_min, uv_max)) * uv_inside_frame(uv0,  uv_min, uv_max);
    vec4 c1  = texture(TEXTURE, clamp(uv1,  uv_min, uv_max)) * uv_inside_frame(uv1,  uv_min, uv_max);
    vec4 c2  = texture(TEXTURE, clamp(uv2,  uv_min, uv_max)) * uv_inside_frame(uv2,  uv_min, uv_max);
    vec4 c3  = texture(TEXTURE, clamp(uv3,  uv_min, uv_max)) * uv_inside_frame(uv3,  uv_min, uv_max);
    vec4 c4  = texture(TEXTURE, clamp(uv4,  uv_min, uv_max)) * uv_inside_frame(uv4,  uv_min, uv_max);
    vec4 c5  = texture(TEXTURE, clamp(uv5,  uv_min, uv_max)) * uv_inside_frame(uv5,  uv_min, uv_max);
    vec4 c6  = texture(TEXTURE, clamp(uv6,  uv_min, uv_max)) * uv_inside_frame(uv6,  uv_min, uv_max);
    vec4 c7  = texture(TEXTURE, clamp(uv7,  uv_min, uv_max)) * uv_inside_frame(uv7,  uv_min, uv_max);
    vec4 c8  = texture(TEXTURE, clamp(uv8,  uv_min, uv_max)) * uv_inside_frame(uv8,  uv_min, uv_max);
    vec4 c9  = texture(TEXTURE, clamp(uv9,  uv_min, uv_max)) * uv_inside_frame(uv9,  uv_min, uv_max);
    vec4 c10 = texture(TEXTURE, clamp(uv10, uv_min, uv_max)) * uv_inside_frame(uv10, uv_min, uv_max);
    vec4 c11 = texture(TEXTURE, clamp(uv11, uv_min, uv_max)) * uv_inside_frame(uv11, uv_min, uv_max);
    vec4 c12 = texture(TEXTURE, clamp(uv12, uv_min, uv_max)) * uv_inside_frame(uv12, uv_min, uv_max);
    vec4 c13 = texture(TEXTURE, clamp(uv13, uv_min, uv_max)) * uv_inside_frame(uv13, uv_min, uv_max);
    vec4 c14 = texture(TEXTURE, clamp(uv14, uv_min, uv_max)) * uv_inside_frame(uv14, uv_min, uv_max);
    vec4 c15 = texture(TEXTURE, clamp(uv15, uv_min, uv_max)) * uv_inside_frame(uv15, uv_min, uv_max);

    vec4 smeared =
        c0  * 0.110 + c1  * 0.105 + c2  * 0.100 + c3  * 0.095 +
        c4  * 0.090 + c5  * 0.085 + c6  * 0.080 + c7  * 0.075 +
        c8  * 0.065 + c9  * 0.055 + c10 * 0.045 + c11 * 0.035 +
        c12 * 0.025 + c13 * 0.018 + c14 * 0.012 + c15 * 0.005;

    // core_sharpness=0 时完全使用方向卷积结果；提高后逐渐恢复当前像素清晰度。
    vec4 current = c0;
    vec4 blurred = mix(smeared, current, clamp(core_sharpness, 0.0, 1.0));
    blurred.rgb = mix(blurred.rgb, tint_color.rgb, clamp(tint_mix, 0.0, 1.0));
    blurred *= vertex_modulate;

    // 模糊层覆盖在原人物上方；高速时可以达到完全覆盖，默认比 V113 明显得多。
    float overlay_alpha = mix(0.50, clamp(blur_alpha, 0.0, 1.0), strength);
    blurred.a *= overlay_alpha;
    COLOR = blurred;
}
