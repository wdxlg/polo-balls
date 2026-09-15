shader_type canvas_item;

// V252：只由 health_bar.gd 在真正角色上运行时挂载。
// arm_half_width 越小，四角空缺越大，十字感越明显。
uniform float arm_half_width : hint_range(0.10, 0.40, 0.01) = 0.19;

void fragment() {
    vec4 tex = texture(TEXTURE, UV) * COLOR;
    vec2 centered = abs(UV - vec2(0.5));
    float in_vertical_arm = 1.0 - step(arm_half_width, centered.x);
    float in_horizontal_arm = 1.0 - step(arm_half_width, centered.y);
    float cross_mask = max(in_vertical_arm, in_horizontal_arm);
    tex.a *= cross_mask;
    COLOR = tex;
}
