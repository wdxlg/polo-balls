shader_type canvas_item;
render_mode blend_mix, unshaded;

// Keep the original pixel silhouette/alpha, but flash every visible texel white.
void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	COLOR = vec4(vec3(1.0), pixel.a * COLOR.a);
}
