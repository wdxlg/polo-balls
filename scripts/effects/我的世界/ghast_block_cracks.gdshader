shader_type canvas_item;
render_mode unshaded;
uniform bool round_surface = false;
void fragment() {
 vec4 ink = texture(TEXTURE, UV);
 if (round_surface && distance(UV, vec2(0.5)) > 0.5) ink.a = 0.0;
 COLOR = ink;
}
