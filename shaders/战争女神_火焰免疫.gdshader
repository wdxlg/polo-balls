shader_type canvas_item;

// 与 ball.gd 的人物 Shader 接口保持兼容。
instance uniform float power : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 hit_white_color : source_color = vec4(1.0);
instance uniform float defualt_color_mix : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 default_color : source_color = vec4(1.0);
instance uniform float sprite_flip_h : hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 motion_params = vec4(0.0, 0.105, 0.065, 0.028);
instance uniform vec2 motion_direction = vec2(1.0, 0.0);
instance uniform vec4 bounce_params_a = vec4(1.0, 0.0, 0.34, 0.20);
instance uniform vec4 bounce_params_b = vec4(0.17, 0.040, 0.0, 0.0);
instance uniform vec2 bounce_direction = vec2(1.0, 0.0);

// 免疫效果使用普通 uniform。每个战争女神实例都有独立 ShaderMaterial。
uniform float immunity_radius : hint_range(0.08, 0.55) = 0.50;
uniform vec4 immunity_content_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float immunity_global_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec2 immunity_quad_center = vec2(0.0, 0.0);
uniform float immunity_canvas_expand : hint_range(1.0, 4.0) = 3.0;

uniform vec2 immunity_hit_uv_0 = vec2(0.5, 0.5);
uniform float immunity_progress_0 : hint_range(0.0, 1.0) = 1.0;
uniform float immunity_seed_0 = 0.0;
uniform vec2 immunity_hit_uv_1 = vec2(0.5, 0.5);
uniform float immunity_progress_1 : hint_range(0.0, 1.0) = 1.0;
uniform float immunity_seed_1 = 0.0;
uniform vec2 immunity_hit_uv_2 = vec2(0.5, 0.5);
uniform float immunity_progress_2 : hint_range(0.0, 1.0) = 1.0;
uniform float immunity_seed_2 = 0.0;
uniform vec2 immunity_hit_uv_3 = vec2(0.5, 0.5);
uniform float immunity_progress_3 : hint_range(0.0, 1.0) = 1.0;
uniform float immunity_seed_3 = 0.0;

varying vec4 sprite_modulate;

float hash21(vec2 p, float fx_seed) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345 + fx_seed * 0.017);
    return fract(p.x * p.y);
}

float bell(float x, float center, float width) {
    float q = (x - center) / max(width, 0.0001);
    return exp(-(q * q));
}

void bounce_curves(float t, out float impact, out float rebound, out float jelly) {
    float impact_in = smoothstep(0.0, 0.055, t);
    float impact_out = 1.0 - smoothstep(0.140, 0.220, t);
    impact = impact_in * impact_out;
    rebound = bell(t, 0.300, 0.090);
    float tail_t = max(t - 0.215, 0.0);
    float tail_gate = smoothstep(0.205, 0.285, t) * (1.0 - smoothstep(0.82, 0.98, t));
    jelly = sin(tail_t * 25.0) * exp(-5.8 * tail_t) * tail_gate;
}

// 固定小像素网格切块：单块更小、更密，seed 在一次免疫期间固定，因此不会每帧乱跳。
float chunk_pattern(vec2 uv, vec2 pixel_size, float fx_seed) {
    vec2 px = uv / pixel_size;
    vec2 cell2 = floor(px / 2.0);
    vec2 cell1 = floor(px);
    float coarse = hash21(cell2, fx_seed + 17.0);
    float fine = hash21(cell1, fx_seed + 71.0);
    return clamp(coarse * 0.62 + fine * 0.38, 0.0, 1.0);
}

// 计算人物本体在某个免疫槽中的白热、燃烧和缺口。
void accumulate_body_effect(
    vec2 uv,
    vec2 hit_uv,
    float progress,
    float fx_seed,
    vec2 pixel_size,
    float radius_px,
    inout float hot_mix,
    inout float fire_mix,
    inout float hole_mix
) {
    float p = clamp(progress, 0.0, 1.0);
    if (p >= 0.9999) {
        return;
    }

    vec2 delta_px = (uv - hit_uv) / pixel_size;
    float dist_px = length(delta_px);
    float region = 1.0 - smoothstep(radius_px * 0.70, radius_px, dist_px);
    if (region <= 0.0001) {
        return;
    }

    float flash = smoothstep(0.0, 0.018, p) * (1.0 - smoothstep(0.095, 0.17, p));
    float break_in = smoothstep(0.045, 0.18, p);
    float recover = 1.0 - smoothstep(0.68, 1.0, p);
    float active = break_in * recover;

    float chunks = chunk_pattern(uv, pixel_size, fx_seed);
    float core = 1.0 - smoothstep(radius_px * 0.12, radius_px * 0.78, dist_px);
    float edge = smoothstep(0.18, 0.55, core) * (1.0 - smoothstep(0.62, 0.92, core));

    hot_mix = max(hot_mix, region * flash);
    fire_mix = max(fire_mix, region * active * (0.35 + 0.65 * chunks));

    // 真正把人物纹理挖掉：中心区域缺口最明显，边缘呈不规则烧蚀状。
    float hole = region * active * clamp(core * 0.92 + chunks * 0.46, 0.0, 1.0);
    hole *= 0.82 + edge * 0.18;
    hole_mix = 1.0 - (1.0 - hole_mix) * (1.0 - hole * 0.98);
}

// V65：每次免疫拆成 12 个真正独立的小火焰碎块。
// 每一块都有自己的源中心、大小、方向、距离和起飞延迟；不再是一整层大遮罩一起平移。
// 这里仍然只计算坐标/遮罩，真正 texture(TEXTURE, ...) 只在 fragment() 内执行。
void shard_coords(
    vec2 output_uv,
    vec2 hit_uv,
    float progress,
    float fx_seed,
    float shard_id,
    vec2 pixel_size,
    float radius_px,
    out vec2 source_uv,
    out float piece_mask,
    out float heat_phase
) {
    source_uv = output_uv;
    piece_mask = 0.0;
    heat_phase = 0.0;

    float p = clamp(progress, 0.0, 1.0);
    if (p >= 0.9999) {
        return;
    }

    float r0 = hash21(vec2(fx_seed * 0.37 + shard_id * 11.17, 1.31 + shard_id * 2.03), fx_seed + 19.0);
    float r1 = hash21(vec2(2.71 + shard_id * 3.41, fx_seed * 0.53 + shard_id * 5.29), fx_seed + 47.0);
    float r2 = hash21(vec2(7.13 + shard_id * 1.73, fx_seed * 0.29 + shard_id * 7.61), fx_seed + 83.0);
    float r3 = hash21(vec2(3.97 + shard_id * 6.11, fx_seed * 0.71 + shard_id * 1.37), fx_seed + 131.0);

    // 同一批碎片错开极短时间起飞，但都在免疫前段出现。
    float start_delay = 0.025 + r3 * 0.085;
    float local_t = clamp((p - start_delay) / max(0.84 - start_delay, 0.10), 0.0, 1.0);

    // 透明度动画：快速显现 -> 飞行中保持 -> 末段平滑淡出。
    float appear = smoothstep(0.0, 0.10, local_t);
    float fade_out = 1.0 - smoothstep(0.62, 1.0, local_t);
    float alpha_envelope = appear * fade_out;
    if (alpha_envelope <= 0.0001) {
        return;
    }

    // 每块从受击区域内部不同的小位置脱离。
    float angle = r0 * 6.28318530718;
    vec2 radial = vec2(cos(angle), sin(angle));
    float origin_radius_px = radius_px * mix(0.10, 0.66, r1);
    vec2 source_center_uv = hit_uv + radial * origin_radius_px * pixel_size;

    // 保证源中心留在人物真实非透明包围盒附近，不被 PNG 透明留白拉走。
    vec2 content_min = immunity_content_rect.xy + pixel_size * 1.0;
    vec2 content_max = immunity_content_rect.xy + immunity_content_rect.zw - pixel_size * 1.0;
    source_center_uv = clamp(source_center_uv, content_min, content_max);

    // 向外散开并明显偏上；每一小块方向都独立。
    vec2 outward = radial * mix(0.55, 1.05, r2);
    vec2 upward = vec2(mix(-0.42, 0.42, r3), -mix(0.72, 1.28, r1));
    vec2 dir = outward + upward;
    if (length(dir) < 0.0001) {
        dir = vec2(0.0, -1.0);
    } else {
        dir = normalize(dir);
    }

    // 先快后慢：四次方 ease-out。前段迅速拉开距离，后段明显减速。
    float travel = 1.0 - pow(1.0 - local_t, 4.0);
    float distance_px = radius_px * mix(2.10, 4.00, r2) * travel;
    vec2 side = vec2(-dir.y, dir.x);
    float side_curve_px = sin(local_t * 3.14159265359) * radius_px * mix(-0.20, 0.20, r0);
    vec2 moved_center_uv = source_center_uv + (dir * distance_px + side * side_curve_px) * pixel_size;

    // 飞行中略微收缩，让碎块看起来像火焰逐渐散掉，而不是越飞越大。
    float size_scale = mix(1.0, 0.70, local_t);
    source_uv = source_center_uv + (output_uv - moved_center_uv) / max(size_scale, 0.20);
    if (source_uv.x < 0.0 || source_uv.y < 0.0 || source_uv.x > 1.0 || source_uv.y > 1.0) {
        piece_mask = 0.0;
        return;
    }

    // 每块只有约 1.25~2.35 像素半径，远小于 V64 的整片平移遮罩。
    float chunk_radius_px = mix(1.25, 2.35, r3);
    float source_distance_px = length((source_uv - source_center_uv) / pixel_size);
    float round_mask = 1.0 - smoothstep(chunk_radius_px * 0.52, chunk_radius_px, source_distance_px);

    // 固定锯齿边缘，只依赖源像素与 seed；动画过程中不会随机跳位置。
    vec2 source_px = floor(source_uv / pixel_size);
    float jagged = mix(0.72, 1.0, hash21(source_px, fx_seed + shard_id * 41.0));
    piece_mask = round_mask * jagged * alpha_envelope;
    heat_phase = clamp(1.0 - local_t * 0.78 + r1 * 0.30, 0.0, 1.0);
}

void vertex() {
    sprite_modulate = COLOR;
    // 扩大 Sprite 的实际绘制四边形，让 Shader-only 火焰碎片可以飞出人物原贴图边界而不被裁掉。
    float expand_factor = max(immunity_canvas_expand, 1.0);
    VERTEX = immunity_quad_center + (VERTEX - immunity_quad_center) * expand_factor;
}

void fragment() {
    // 顶点四边形放大后，把 UV 反向映射回原贴图坐标；人物本体保持原尺寸，只额外获得四周绘制空间。
    float expand_factor = max(immunity_canvas_expand, 1.0);
    vec2 local_uv = (UV - vec2(0.5)) * expand_factor + vec2(0.5);
    vec2 p = local_uv - vec2(0.5);

    // 保留 ball.gd 的移动拉伸。
    vec2 move_dir = motion_direction;
    if (length(move_dir) < 0.0001) {
        move_dir = vec2(1.0, 0.0);
    } else {
        move_dir = normalize(move_dir);
    }
    vec2 move_side = vec2(-move_dir.y, move_dir.x);
    float move_strength = clamp(motion_params.x, 0.0, 1.0);
    float along = dot(p, move_dir);
    float side_value = dot(p, move_side);
    p = move_dir * (along / max(1.0 + motion_params.y * move_strength, 0.5))
        + move_side * (side_value / max(1.0 - motion_params.z * move_strength, 0.55));
    float upper_mask = 1.0 - smoothstep(0.18, 0.52, local_uv.y);
    p -= move_dir * (motion_params.w * move_strength * upper_mask);

    // 保留 ball.gd 的受撞软体接口。
    vec2 bounce_dir = bounce_direction;
    if (length(bounce_dir) < 0.0001) {
        bounce_dir = vec2(1.0, 0.0);
    } else {
        bounce_dir = normalize(bounce_dir);
    }
    vec2 bounce_side = vec2(-bounce_dir.y, bounce_dir.x);
    float impact;
    float rebound;
    float jelly;
    bounce_curves(clamp(bounce_params_a.x, 0.0, 1.0), impact, rebound, jelly);
    float strength = clamp(bounce_params_a.y, 0.0, 1.25);
    float ba = dot(p, bounce_dir);
    float bs = dot(p, bounce_side);
    float axis_scale = clamp(1.0 - bounce_params_a.z * strength * impact + bounce_params_b.x * strength * rebound + 0.06 * strength * jelly, 0.52, 1.42);
    float side_scale = clamp(1.0 + bounce_params_a.w * strength * impact - bounce_params_b.x * 0.45 * strength * rebound - 0.04 * strength * jelly, 0.68, 1.42);
    p = bounce_dir * (ba / axis_scale) + bounce_side * (bs / side_scale);

    vec2 sample_uv = vec2(0.5) + p;
    float inside = step(0.0, sample_uv.x) * step(sample_uv.x, 1.0) * step(0.0, sample_uv.y) * step(sample_uv.y, 1.0);
    if (sprite_flip_h > 0.5) {
        sample_uv.x = 1.0 - sample_uv.x;
    }

    vec4 base_tex = texture(TEXTURE, sample_uv);
    base_tex.a *= inside;

    // 半径以 PNG 实际非透明内容的真实纹理像素计算，不受四周透明留白比例影响。
    vec2 pixel_size = max(TEXTURE_PIXEL_SIZE, vec2(0.000001));
    vec2 content_px = immunity_content_rect.zw / pixel_size;
    float radius_px = max(min(content_px.x, content_px.y) * immunity_radius, 2.0);

    float hot_mix = 0.0;
    float fire_mix = 0.0;
    float hole_mix = 0.0;

    // 每次免疫都单独触发全身 50% 橙色叠加。
    // 与局部槽位进度解耦，因此同一位置续期时也能再次闪一下，而不用把局部破碎动画重置到 0。
    float body_orange_flash = clamp(immunity_global_flash, 0.0, 1.0);
    accumulate_body_effect(sample_uv, immunity_hit_uv_0, immunity_progress_0, immunity_seed_0, pixel_size, radius_px, hot_mix, fire_mix, hole_mix);
    accumulate_body_effect(sample_uv, immunity_hit_uv_1, immunity_progress_1, immunity_seed_1, pixel_size, radius_px, hot_mix, fire_mix, hole_mix);
    accumulate_body_effect(sample_uv, immunity_hit_uv_2, immunity_progress_2, immunity_seed_2, pixel_size, radius_px, hot_mix, fire_mix, hole_mix);
    accumulate_body_effect(sample_uv, immunity_hit_uv_3, immunity_progress_3, immunity_seed_3, pixel_size, radius_px, hot_mix, fire_mix, hole_mix);

    // 免疫触发的一瞬间：整个人物叠加 50% 橙色反馈，先让玩家明确看到“免疫成功”。
    base_tex.rgb = mix(base_tex.rgb, vec3(1.0, 0.34, 0.03), clamp(body_orange_flash * 0.50, 0.0, 0.50));

    // 受击瞬间强烈白热；随后受击区域转为火焰，并真正从人物本体挖掉。
    vec3 burn_color = mix(vec3(1.0, 0.11, 0.01), vec3(1.0, 0.56, 0.03), clamp(fire_mix, 0.0, 1.0));
    base_tex.rgb = mix(base_tex.rgb, burn_color, clamp(fire_mix * 0.96, 0.0, 0.96));
    base_tex.rgb = mix(base_tex.rgb, vec3(1.0, 0.97, 0.70), clamp(hot_mix, 0.0, 1.0));
    base_tex.rgb += vec3(1.0, 0.50, 0.04) * fire_mix * 0.22;
    base_tex.a *= 1.0 - clamp(hole_mix, 0.0, 0.985);

    // V65：每个活跃免疫槽生成 12 个独立小碎块；4 个不同受击位置同时存在时最多 48 块。
    // 使用局部数组和固定次数 for 循环，Godot 4.x Shader 语言原生支持这种写法。
    vec2 hit_uvs[4];
    float progresses[4];
    float seeds[4];
    hit_uvs[0] = immunity_hit_uv_0;
    hit_uvs[1] = immunity_hit_uv_1;
    hit_uvs[2] = immunity_hit_uv_2;
    hit_uvs[3] = immunity_hit_uv_3;
    progresses[0] = immunity_progress_0;
    progresses[1] = immunity_progress_1;
    progresses[2] = immunity_progress_2;
    progresses[3] = immunity_progress_3;
    seeds[0] = immunity_seed_0;
    seeds[1] = immunity_seed_1;
    seeds[2] = immunity_seed_2;
    seeds[3] = immunity_seed_3;

    vec3 fire_dark = vec3(1.0, 0.07, 0.003);
    vec3 fire_mid = vec3(1.0, 0.34, 0.012);
    vec3 fire_hot = vec3(1.0, 0.88, 0.24);
    vec3 scatter_premul = vec3(0.0);
    float scatter_alpha = 0.0;

    for (int slot_index = 0; slot_index < 4; slot_index++) {
        if (progresses[slot_index] < 0.9999) {
            for (int shard_index = 0; shard_index < 12; shard_index++) {
                vec2 shard_uv;
                float shard_mask;
                float shard_heat;
                shard_coords(
                    sample_uv,
                    hit_uvs[slot_index],
                    progresses[slot_index],
                    seeds[slot_index],
                    float(shard_index),
                    pixel_size,
                    radius_px,
                    shard_uv,
                    shard_mask,
                    shard_heat
                );

                if (shard_mask > 0.0001) {
                    vec4 piece = texture(TEXTURE, shard_uv);
                    float shard_alpha = clamp(piece.a * shard_mask * 0.88, 0.0, 0.88);
                    vec3 shard_color = mix(fire_dark, fire_mid, clamp(shard_heat * 1.25, 0.0, 1.0));
                    shard_color = mix(shard_color, fire_hot, clamp((shard_heat - 0.38) * 1.55, 0.0, 1.0));

                    // 正常 over 叠加，而不是只取最大的一块；相邻小碎片不会被合并成两大片。
                    float remain = 1.0 - scatter_alpha;
                    scatter_premul += shard_color * shard_alpha * remain;
                    scatter_alpha += shard_alpha * remain;
                }
            }
        }
    }

    vec4 scatter = vec4(0.0);
    if (scatter_alpha > 0.0001) {
        scatter = vec4(scatter_premul / scatter_alpha, scatter_alpha);
    }

    // 正常 Alpha 合成：散开的火焰块覆盖在被挖空的人物局部上。
    vec3 premul = base_tex.rgb * base_tex.a;
    premul = premul * (1.0 - scatter.a) + scatter.rgb * scatter.a;
    float final_alpha = base_tex.a + scatter.a * (1.0 - base_tex.a);
    vec4 tex = vec4(0.0);
    if (final_alpha > 0.0001) {
        tex = vec4(premul / final_alpha, final_alpha);
    }

    vec4 out_color = tex * sprite_modulate;
    out_color.rgb = mix(out_color.rgb, default_color.rgb, defualt_color_mix);
    out_color.rgb = mix(out_color.rgb, hit_white_color.rgb, power);
    COLOR = out_color;
}
