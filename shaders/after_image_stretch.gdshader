shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// V11 Stretch Trail：不生成一串快照，仅复用一个 Sprite，沿运动方向拉长/扭曲。
instance uniform float intensity : hint_range(0.0, 1.0) = 0.0;
instance uniform vec2 trail_direction = vec2(1.0, 0.0);
instance uniform float source_flip_h : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 head_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
instance uniform vec4 tail_color : source_color = vec4(0.42, 0.72, 1.0, 0.55);
// x=length_px, y=head_width, z=tail_width, w=distortion_px
instance uniform vec4 stretch_params = vec4(54.0, 1.0, 0.34, 3.0);
instance uniform float alpha_value : hint_range(0.0, 1.0) = 0.34;
instance uniform int style_mode = 1;
instance uniform int sample_count = 4;
// x/y = region origin, z/w = region size (normalized in texture).
instance uniform vec4 region_params = vec4(0.0, 0.0, 1.0, 1.0);

varying vec4 vertex_modulate;

vec2 safe_dir() {
    vec2 dir = trail_direction;
    if (length(dir) < 0.0001) {
        return vec2(1.0, 0.0);
    }
    return normalize(dir);
}

void vertex() {
    vertex_modulate = COLOR;
    vec2 dir = safe_dir();
    vec2 side = vec2(-dir.y, dir.x);
    vec2 region_size = max(abs(region_params.zw), vec2(0.000001));
    vec2 local_uv = (UV - region_params.xy) / region_size;
    vec2 centered_uv = local_uv - vec2(0.5);
    float along_uv = dot(centered_uv, dir);
    float tail_weight = smoothstep(-0.02, 0.62, -along_uv);

    // 只把运动反方向那一侧往后拉，前缘基本保持在角色附近。
    VERTEX -= dir * stretch_params.x * intensity * tail_weight;

    // 尾部宽度可以独立定义，能做尖尾、宽烟、能量带等不同形状。
    float width_scale = mix(stretch_params.y, stretch_params.z, tail_weight);
    float side_coord = dot(VERTEX, side);
    VERTEX += side * side_coord * (width_scale - 1.0) * intensity;
}

vec2 map_uv(vec2 local_uv, float flip_h_value) {
    if (flip_h_value > 0.5) {
        local_uv.x = 1.0 - local_uv.x;
    }
    vec2 region_size = max(abs(region_params.zw), vec2(0.000001));
    return region_params.xy + local_uv * region_size;
}

float region_inside(vec2 local_uv) {
    return step(0.0, local_uv.x) * step(local_uv.x, 1.0)
        * step(0.0, local_uv.y) * step(local_uv.y, 1.0);
}

void fragment() {
    vec2 dir = safe_dir();
    vec2 side = vec2(-dir.y, dir.x);
    vec2 region_size = max(abs(region_params.zw), vec2(0.000001));
    vec2 local_uv = (UV - region_params.xy) / region_size;
    vec2 centered_uv = local_uv - vec2(0.5);
    float along_uv = dot(centered_uv, dir);
    float tail_weight = smoothstep(-0.02, 0.62, -along_uv);

    float distortion = stretch_params.w * intensity;
    float style_distortion = 1.0;
    if (style_mode == 0) {
        style_distortion = 0.0;
    } else if (style_mode == 3) {
        style_distortion = 1.8;
    } else if (style_mode == 4) {
        style_distortion = 1.35;
    }

    float wave = sin(along_uv * 18.0 - TIME * 9.0) * distortion * style_distortion * tail_weight;
    vec2 local_pixel_size = TEXTURE_PIXEL_SIZE / region_size;
    vec2 base_uv = local_uv + side * wave * local_pixel_size;

    int count = min(max(sample_count, 1), 8);
    float alpha_sum = 0.0;
    vec3 premul_sum = vec3(0.0);
    float weight_sum = 0.0;

    for (int i = 0; i < 8; i++) {
        if (i >= count) {
            break;
        }
        float fi = count <= 1 ? 0.0 : float(i) / float(count - 1);
        float centered = fi - 0.5;
        vec2 sample_uv = base_uv + side * centered * (1.5 + distortion * 0.35) * local_pixel_size;
        vec4 texel = texture(TEXTURE, map_uv(sample_uv, source_flip_h));
        texel.a *= region_inside(sample_uv);
        float w = 1.0 - abs(centered) * 0.7;
        alpha_sum += texel.a * w;
        premul_sum += texel.rgb * texel.a * w;
        weight_sum += w;
    }

    float mask = alpha_sum / max(weight_sum, 0.0001);
    vec3 source_rgb = premul_sum / max(alpha_sum, 0.0001);
    vec4 gradient_color = mix(head_color, tail_color, tail_weight);

    vec3 styled_rgb = source_rgb;
    if (style_mode == 2) {
        styled_rgb = min(source_rgb * 1.15 + gradient_color.rgb * 0.20, vec3(2.0));
    } else if (style_mode == 3) {
        float lum = dot(source_rgb, vec3(0.299, 0.587, 0.114));
        styled_rgb = mix(vec3(lum), source_rgb, 1.25);
    } else if (style_mode == 4) {
        float lum = dot(source_rgb, vec3(0.299, 0.587, 0.114));
        styled_rgb = mix(vec3(lum), source_rgb, 0.25);
    } else if (style_mode == 5) {
        styled_rgb = vec3(1.0);
    }

    // 尾部自然衰减；intensity 归零时整个拖尾无缝消失。
    float tail_fade = mix(1.0, 0.08, pow(tail_weight, 1.15));
    float final_alpha = mask * alpha_value * intensity * gradient_color.a * tail_fade * vertex_modulate.a;
    vec3 final_rgb = styled_rgb * gradient_color.rgb * vertex_modulate.rgb;
    COLOR = vec4(final_rgb * final_alpha, final_alpha);
}
