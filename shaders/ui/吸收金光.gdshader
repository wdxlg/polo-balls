shader_type canvas_item;

// Render the original health-bar texture and cross silhouette. Gold and its
// animated highlight stay strictly within that texture's existing alpha.
uniform float arm_half_width : hint_range(0.10, 0.40, 0.01) = 0.19;

void fragment() {
    vec4 tex = texture(TEXTURE, UV) * COLOR;
    vec2 centered = abs(UV - vec2(0.5));
    float cross_mask = max(1.0 - step(arm_half_width, centered.x),
                           1.0 - step(arm_half_width, centered.y));
    float glint = 0.5 + 0.5 * sin(TIME * 4.0 + UV.y * 16.0);
    vec3 gold = vec3(0.91, 0.63, 0.06) + vec3(0.09, 0.28, 0.15) * glint;
    COLOR = vec4(tex.rgb * gold, tex.a * cross_mask);
}
