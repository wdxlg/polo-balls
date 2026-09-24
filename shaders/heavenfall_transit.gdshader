shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float whitening : hint_range(0.0, 1.0) = 0.0;
uniform bool clip_opening = false;
uniform vec2 opening = vec2(0.0);
uniform vec2 emergence_up = vec2(0.0, -1.0);
varying vec2 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}
void fragment() {
	if (clip_opening && dot(world_position - opening, emergence_up) < 0.0) { discard; }
	vec4 texel = texture(TEXTURE, UV);
	COLOR = vec4(mix(texel.rgb, vec3(1.0), whitening), texel.a);
}
