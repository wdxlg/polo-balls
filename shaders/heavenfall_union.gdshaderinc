// Exact live ribbon triangles, including growth and obstacle-clipped widths.
// Union the coverages BEFORE colouring: a neighbour's cavity removes this rim.
uniform sampler2D union_triangles : filter_nearest, repeat_disable;
uniform int union_count = 0;

vec2 union_coverage(vec2 point, float aa) {
	vec2 coverage = vec2(0.0);
	int rows = textureSize(union_triangles, 0).y;
	for (int i = 0; i < union_count; i++) {
		ivec2 base = ivec2((i / rows) * 4, i % rows);
		vec4 a = texelFetch(union_triangles, base, 0);
		vec4 b = texelFetch(union_triangles, base + ivec2(1, 0), 0);
		vec4 c = texelFetch(union_triangles, base + ivec2(2, 0), 0);
		vec2 lo = min(a.xy, min(b.xy, c.xy));
		vec2 hi = max(a.xy, max(b.xy, c.xy));
		if (any(lessThan(point, lo)) || any(greaterThan(point, hi))) { continue; }
		vec2 ab = b.xy - a.xy;
		vec2 ac = c.xy - a.xy;
		vec2 ap = point - a.xy;
		float determinant = ab.x * ac.y - ab.y * ac.x;
		if (abs(determinant) < 0.000001) { continue; }
		float v = (ap.x * ac.y - ap.y * ac.x) / determinant;
		float w = (ab.x * ap.y - ab.y * ap.x) / determinant;
		float u = 1.0 - v - w;
		if (min(u, min(v, w)) < -0.00001) { continue; }
		vec4 birth = texelFetch(union_triangles, base + ivec2(3, 0), 0);
		if (dot(vec3(u, v, w), birth.xyz) >= birth.w) { continue; }
		vec2 profile = a.zw * u + b.zw * v + c.zw * w;
		float radius = profile.y;
		if (radius <= 0.0001) { continue; }
		float distance = abs(profile.x) * radius;
		float inner = max(radius - min(0.85, radius * 0.28), 0.0001);
		vec2 mask = vec2(
			1.0 - smoothstep(max(inner - aa, 0.0), inner, distance),
			1.0 - smoothstep(max(radius - aa, 0.0), radius, distance));
		coverage = max(coverage, mask);
		if (coverage.x >= 0.9999) { break; }
	}
	return coverage;
}
