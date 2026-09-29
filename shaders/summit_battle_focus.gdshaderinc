// Summit-only, world-anchored grading of BACKGROUND surfaces, never a screen overlay.
// No screen/depth readback, blur, TIME, extra light, geometry or alpha modification.
uniform float focus_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 focus_playfield = vec4(0.0); // center.xy, protected half-size.zw
uniform float focus_near_width = 24.0;
uniform float focus_outer_span = 192.0;
uniform float focus_daylight : hint_range(0.0, 1.0) = 1.0;

vec3 summit_focus_grade(vec3 rgb, vec2 world_point, float role) {
	if (focus_strength <= 0.0 || role < 0.5) { return rgb; }
	vec2 outside = max(abs(world_point - focus_playfield.xy) - focus_playfield.zw, vec2(0.0));
	float distance_outside = length(outside);
	float peripheral = smoothstep(focus_near_width, max(focus_outer_span, focus_near_width + 1.0), distance_outside);
	float daylight = clamp(focus_daylight, 0.0, 1.0);
	// At midnight retain only a gentle 30% of the softening/highlight adjustment.
	// Perimeter darkening itself is zero at night; the shared world tint still runs once.
	float amount = focus_strength * mix(0.30, 1.0, daylight);
	float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	if (role < 1.5) {
		// Far mountains/trees: 25% lower contrast, 15% less saturation at noon.
		rgb = mix(vec3(luminance), rgb, 1.0 - 0.15 * amount);
		rgb = mix(rgb, vec3(0.27, 0.30, 0.35), 0.25 * amount);
		// Light aerial haze only in the scenery image; original pixel edges stay sharp.
		rgb = mix(rgb, vec3(0.32, 0.37, 0.43), mix(0.025, 0.055, peripheral) * amount);
		rgb *= 1.0 - 0.06 * amount * smoothstep(0.50, 0.95, luminance);
	} else if (role < 2.5) {
		// Seats/column edges weaken gently outward; the playable interior is protected.
		float decoration = smoothstep(0.0, focus_near_width, distance_outside);
		float local_amount = amount * decoration;
		rgb = mix(vec3(luminance), rgb, 1.0 - 0.10 * local_amount);
		// Compress real linear-space stone highlights, never lift dark trim toward gray.
		rgb *= 1.0 - local_amount * (0.06 + 0.06 * smoothstep(0.12, 0.40, luminance));
	} else {
		// Opaque original flat clouds retain the exact top/side ratio and silhouette.
		rgb *= 1.0 - 0.13 * amount;
	}
	// Integrated into the existing map/cloud composites, below terrain and actors.
	// The permanent Game vignette and all HUD/recording overlays are untouched.
	rgb *= 1.0 - 0.12 * focus_strength * daylight * peripheral;
	return rgb;
}
