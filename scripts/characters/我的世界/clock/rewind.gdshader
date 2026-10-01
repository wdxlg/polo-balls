shader_type canvas_item;
// 时钟倒流：录像带倒带画面（向上滚动的撕裂条、错行抖动、扫描线、冷色调、雪花噪点）。
// 精灵需带透明边距（region 外扩），越界部分在这里裁掉。
render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.55, 0.86, 1.0);

varying vec4 v_color;

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	v_color = COLOR;
}

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 uv = UV;
	float row = floor(uv.y * tex_size.y);
	float frame = floor(TIME * 24.0);
	// 倒带：撕裂条从下往上扫。
	float span = tex_size.y + 12.0;
	float sweep = tex_size.y + 6.0 - mod(TIME * 70.0, span);
	float tear = 1.0 - smoothstep(0.0, 2.5, abs(row - sweep));
	float sweep2 = tex_size.y + 6.0 - mod(TIME * 70.0 + span * 0.5, span);
	tear = max(tear, 0.6 * (1.0 - smoothstep(0.0, 1.5, abs(row - sweep2))));
	float jitter = step(0.7, h1(row * 3.7 + frame * 11.0)) * (h1(row + frame * 5.3) - 0.5) * 2.0;
	float dir = h1(frame * 1.7) < 0.5 ? -1.0 : 1.0;
	float shift = (jitter * 1.2 + tear * 2.6 * dir) * strength;
	uv.x -= shift / tex_size.x;
	vec4 tex = texture(TEXTURE, uv);
	tex.a *= step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec3 col = tex.rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(vec3(0.16, 0.24, 0.5), tint * 1.5, lum);
	col = mix(col, graded, 0.62 * strength);
	col += tear * vec3(0.55, 0.78, 1.0) * 0.55 * strength;
	float scan = 0.82 + 0.18 * sin(FRAGCOORD.y * 3.14159 + TIME * 40.0);
	col *= mix(1.0, scan, strength);
	float n = h2(floor(FRAGCOORD.xy * 0.5) + frame * 17.0);
	col += step(0.965, n) * 0.45 * strength;
	COLOR = vec4(col, tex.a) * v_color;
}
