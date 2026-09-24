shader_type canvas_item;
render_mode unshaded;
uniform sampler2D reveal_mask : filter_linear, repeat_disable;
uniform float fog_time = 0.0;
uniform float opacity = 0.0;
uniform vec2 mask_texel = vec2(0.0052083333);
uniform vec2 world_size = vec2(1000.0);
uniform vec2 mask_origin = vec2(0.0);
uniform bool cloud_layer = true;
uniform int storm_count = 0;
uniform vec4 storms[16];
varying vec2 fog_world;
varying vec4 mist_tint;
void vertex() {
 fog_world = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy;
 mist_tint = COLOR;
}
void fragment() {
 vec2 uv = (fog_world-mask_origin)/world_size;
 vec2 d = mask_texel*1.2;
 float reveal = 0.0;
 if (all(greaterThanEqual(uv,vec2(0.0))) && all(lessThanEqual(uv,vec2(1.0)))) {
  reveal = texture(reveal_mask,uv).a*0.4;
  reveal += (texture(reveal_mask,uv+vec2(d.x,0)).a+texture(reveal_mask,uv-vec2(d.x,0)).a+texture(reveal_mask,uv+vec2(0,d.y)).a+texture(reveal_mask,uv-vec2(0,d.y)).a)*0.15;
 }
 // Only textured cloud pixels, never a solid-color backing plane.
 vec4 tex = texture(TEXTURE,UV);
 float density = mix(1.0,0.09,smoothstep(0.0,0.78,reveal));
 density *= mix(1.0,0.20,smoothstep(0.8,1.0,reveal)); // thunder clears more than ordinary sight
 for (int i=0; i<16; i++) {
  if (i>=storm_count) { break; }
  vec2 rel = fog_world-storms[i].xy;
  float angle = atan(rel.y,rel.x);
  float seed_value = storms[i].x*0.013+storms[i].y*0.007;
  float edge = storms[i].z*(1.0+0.10*sin(angle*5.0+seed_value)+0.07*sin(angle*9.0-seed_value)+0.04*sin(angle*13.0+seed_value*2.0));
  // Irregular cloud rim contracts inward; interior is completely cleared immediately.
  float fringe = sin(fog_world.x*0.065+fog_time*0.7)*sin(fog_world.y*0.047-fog_time*0.5)*9.0;
  float cleared = smoothstep(max(0.0,edge-55.0+fringe),edge+45.0+fringe,length(rel));
  density *= mix(1.0,cleared,storms[i].w); // w fades the tail of the regroup smoothly.
 }
 float cloud_alpha = 1.0-pow(1.0-tex.a,3.0);
 COLOR = vec4(tex.rgb*mist_tint.rgb,cloud_alpha*mist_tint.a*opacity*density);
}
