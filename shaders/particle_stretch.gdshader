shader_type particles;

uniform float stretch_scale = 1.0;

void process() {
	vec2 velocity = VELOCITY.xy;
	float speed = length(velocity);
	
	float stretch_amount = speed * stretch_scale;
	
	if (speed > 0.01) {
		vec2 dir = normalize(velocity);
		
		float cos_angle = dir.x;
		float sin_angle = dir.y;
		
		vec3 new_x_axis = vec3(dir * stretch_amount,0.0);
		vec3 new_y_axis = vec3(-sin_angle,cos_angle,0.0);
		vec3 new_z_axis = vec3(0.0,0.0,1);
		
		TRANSFORM = mat4(
			vec4(new_x_axis,0),
			vec4(new_y_axis,0),
			vec4(new_z_axis,0),
			vec4(0,0,0,1)
		);
		
	}
}
