shader_type canvas_item;
// Simple fallback for otherwise unshaded visual nodes; no gameplay changes.
instance uniform float character_grayscale : hint_range(0.0,1.0) = 1.0;
void fragment() {
	vec4 original = texture(TEXTURE,UV) * COLOR;
	float luminance = dot(original.rgb,vec3(0.299,0.587,0.114));
	COLOR = vec4(mix(original.rgb,vec3(luminance),character_grayscale),original.a);
}
