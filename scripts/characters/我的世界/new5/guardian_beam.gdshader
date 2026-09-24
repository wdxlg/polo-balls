shader_type canvas_item;
render_mode unshaded;
// Mojang's guardian_beam.png: U goes around the tube; V goes along it.
// Adapt its native UV layout to a 2D ribbon; no invented solid laser core.
uniform sampler2D native_beam : source_color, filter_nearest, repeat_enable;
uniform float along_scale = 0.2916667;
uniform float scroll = 0.0;
uniform float emission_strength = 0.0;
varying vec4 beam_color;
void vertex() { beam_color = COLOR; }
void fragment() {
	vec2 native_uv = vec2(UV.y * 0.5, UV.x * along_scale - scroll);
	COLOR = beam_color * texture(native_beam, native_uv);
	COLOR.rgb *= 1.0 + emission_strength;
}
