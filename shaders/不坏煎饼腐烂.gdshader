shader_type canvas_item;

uniform float rot_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rot_tint : source_color = vec4(0.08, 0.29, 0.10, 1.0);

float soft_hole(vec2 uv, vec2 center, float base_radius, float growth) {
    float r = base_radius + growth * rot_amount;
    float d = distance(uv, center);
    return smoothstep(max(r - 0.022, 0.001), r, d);
}

void fragment() {
    vec4 tex = texture(TEXTURE, UV) * COLOR;
    float tint_weight = smoothstep(0.06, 0.92, rot_amount) * 0.88;
    vec3 spoiled = mix(tex.rgb, rot_tint.rgb, tint_weight);
    spoiled *= mix(1.0, 0.58, rot_amount);

    float holes = 1.0;
    float open_1 = smoothstep(0.20, 0.52, rot_amount);
    float open_2 = smoothstep(0.34, 0.68, rot_amount);
    float open_3 = smoothstep(0.48, 0.80, rot_amount);
    float open_4 = smoothstep(0.60, 0.92, rot_amount);
    float open_5 = smoothstep(0.72, 1.00, rot_amount);

    holes *= mix(1.0, soft_hole(UV, vec2(0.10, 0.30), 0.025, 0.115), open_1);
    holes *= mix(1.0, soft_hole(UV, vec2(0.88, 0.23), 0.020, 0.110), open_2);
    holes *= mix(1.0, soft_hole(UV, vec2(0.91, 0.69), 0.018, 0.122), open_3);
    holes *= mix(1.0, soft_hole(UV, vec2(0.23, 0.89), 0.022, 0.120), open_4);
    holes *= mix(1.0, soft_hole(UV, vec2(0.60, 0.94), 0.018, 0.105), open_5);
    holes *= mix(1.0, soft_hole(UV, vec2(0.48, 0.09), 0.016, 0.092), open_5);

    // 后期从边缘继续被“啃掉”，但保留足够主体让弹体仍然可读。
    float edge_distance = distance(UV, vec2(0.5));
    float ragged = sin(UV.x * 43.0 + UV.y * 31.0) * 0.012 + sin(UV.x * 79.0 - UV.y * 17.0) * 0.008;
    float edge_cut = 1.0 - smoothstep(0.475 + ragged, 0.515 + ragged, edge_distance);
    holes *= mix(1.0, edge_cut, smoothstep(0.76, 1.0, rot_amount) * 0.72);

    tex.rgb = spoiled;
    tex.a *= holes;
    COLOR = tex;
}
