// Shared Avaritia 1.12.2 cosmic implementation; provenance remains in
// av_cosmic_atlas.sources.json. The aperture mask belongs to each caller.
const float PI_VALUE = 3.14159265358979323846;

mat3 cosmic_rotation(vec3 axis, float angle) {
	axis = normalize(axis);
	float s = sin(angle);
	float c = cos(angle);
	float oc = 1.0 - c;
	return mat3(
		vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y - axis.z * s, oc * axis.z * axis.x + axis.y * s),
		vec3(oc * axis.x * axis.y + axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z - axis.x * s),
		vec3(oc * axis.z * axis.x - axis.y * s, oc * axis.y * axis.z + axis.x * s, oc * axis.z * axis.z + c)
	);
}

float cosmic_symbol(int symbol, vec2 tile_uv, float ticks) {
	// Native .mcmeta timelines are packed losslessly in rows 112..121.
	// Column 159 stores the timeline length; all other values are frame IDs.
	float row = 112.5 + float(symbol);
	float period = floor(texture(cosmic_atlas, vec2(159.5, row) / vec2(160.0, 128.0)).r * 255.0 + 0.5);
	float tick = mod(floor(ticks), max(period, 1.0));
	float frame = floor(texture(cosmic_atlas, vec2(tick + 0.5, row) / vec2(160.0, 128.0)).r * 255.0 + 0.5);
	vec2 pixel = floor(clamp(tile_uv, vec2(0.0), vec2(0.99999)) * 16.0);
	vec2 atlas_pixel = vec2(float(symbol) * 16.0, frame * 16.0) + pixel + vec2(0.5);
	return texture(cosmic_atlas, atlas_pixel / vec2(160.0, 128.0)).r;
}

vec3 cosmic_colour_at(vec2 plane, float time_value) {
	float ticks = time_value * 20.0;
	float pulse = mod(ticks, 400.0) / 400.0;
	vec3 col = vec3(0.1, sin(pulse * PI_VALUE * 2.0) * 0.075 + 0.225, cos(pulse * PI_VALUE * 2.0) * 0.05 + 0.3);
	// A 2D aperture looks into the same spherical star layers; no noisy
	// procedural replacement stars or nebula circles are drawn outside it.
	vec3 direction = normalize(vec3(-plane, -1.0));
	for (int i = 0; i < 16; i++) {
		float mult = float(16 - i);
		float j = float(i + 7);
		float k = j + 1.0;
		float rand1 = (j * j * 4321.0 + j * 8.0) * 2.0;
		float rand2 = (k * k * k * 239.0 + k * 37.0) * 3.6;
		float rand3 = rand1 * 347.4 + rand2 * 63.4;
		vec3 axis = normalize(vec3(sin(rand1), sin(rand2), cos(rand3)));
		vec3 ray = direction * cosmic_rotation(axis, mod(rand3, 2.0 * PI_VALUE));
		float raw_u = 0.5 + atan(ray.z, ray.x) / (2.0 * PI_VALUE);
		float raw_v = 0.5 + asin(clamp(ray.y, -1.0, 1.0)) / PI_VALUE;
		float layer_scale = mult * 0.5 + 2.75;
		vec2 uv = vec2(raw_u, (raw_v + ticks * 0.0002) * 0.6) * layer_scale;
		ivec2 tile = ivec2(mod(floor(uv * 16.0), vec2(16.0)));
		int tile_hash = (1777541 * tile.x + 7649689 * tile.y + 3612703 * (i + 31) + 1723609) ^ 50943779;
		int symbol = int(mod(float(tile_hash), 101.0));
		if (symbol < 0 || symbol >= 10) {
			continue;
		}
		// The original eight rotated/mirrored variants of each native icon.
		float power = tile.x == 0 && tile.y == 0 ? 1.0 : pow(float(tile.x), float(tile.y));
		int rotation = int(mod(power + float(tile.x + 3 + tile.y * i), 8.0));
		vec2 icon_uv = fract(uv * 16.0);
		if (rotation >= 4) {
			rotation -= 4;
			icon_uv.x = 1.0 - icon_uv.x;
		}
		if (rotation == 1) {
			icon_uv = vec2(1.0 - icon_uv.y, icon_uv.x);
		} else if (rotation == 2) {
			icon_uv = vec2(1.0) - icon_uv;
		} else if (rotation == 3) {
			icon_uv = vec2(icon_uv.y, 1.0 - icon_uv.x);
		}
		float intensity = cosmic_symbol(symbol, icon_uv, ticks);
		float strength = intensity * (0.5 + 1.0 / mult) * (1.0 - smoothstep(0.15, 0.48, abs(raw_v - 0.5)));
		vec3 tint = vec3(mod(rand1, 29.0) / 29.0 * 0.3 + 0.4, mod(rand2, 35.0) / 35.0 * 0.4 + 0.6, mod(rand1, 17.0) / 17.0 * 0.3 + 0.7);
		col += tint * strength;
	}
	col = clamp(col, vec3(0.0), vec3(1.0));
	// Preserve the native sRGB appearance in this project's HDR 2D viewport.
	if (linear_output) {
		return mix(col / 12.92, pow((col + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), col));
	}
	return col;
}


vec3 cosmic_colour(vec2 plane) {
	return cosmic_colour_at(plane, cosmic_time);
}
