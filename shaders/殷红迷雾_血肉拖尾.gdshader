shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform vec4 tint : source_color = vec4(0.92,0.025,0.045,1.0);
uniform float head_progress = 1.0;
uniform float tail_progress = 0.0;
uniform float opacity = 1.0;
uniform float anim_time = 0.0;
uniform float seed = 1.0;
uniform float ego_strength = 0.0;
uniform float eye_density = 0.25;
uniform float flow_speed = 1.0;
uniform int blade_kind = 1;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void fragment() {
 // 恢复项目的真实刀光遮罩：斩击由窄到厚、撕裂尾缘和孔洞；突刺由粗到尖。
 // 不能再用统一解析月牙覆盖两张素材，否则类型只剩颜色差异。
 vec4 mask = texture(TEXTURE,UV);
 float body = mask.r * mask.a;
 float x = UV.x;
 float reveal = (1.0-smoothstep(head_progress-0.02,head_progress+0.015,x))
              * smoothstep(tail_progress-0.02,tail_progress+0.06,x);
 float flow = noise(vec2(x*17.0-anim_time*5.0*flow_speed,UV.y*31.0+seed));
 float fibres = noise(vec2(x*8.0-anim_time*7.0,UV.y*83.0+seed));
 vec3 deep = vec3(0.085,0.004,0.012);
 vec3 blood = mix(deep,tint.rgb,0.36+0.48*flow);
 blood *= 0.70+0.30*fibres;
 float rim = clamp(length(vec2(dFdx(body),dFdy(body)))*2.2,0.0,1.0);
 blood = mix(blood,vec3(1.0,0.25,0.22),rim*0.8);
 blood = mix(blood,vec3(1.0,0.84,0.70),rim*exp(-anim_time*22.0));
 // E.G.O 的拟态眼只嵌在血肉中；普通形态完全不显示。
 for(int i=0;i<3;i++) {
  float ex = 0.32+float(i)*0.24;
  vec2 ep = (UV-vec2(ex,0.54+0.08*sin(float(i)*2.1)))/vec2(0.055,0.075);
  float eye = 1.0-smoothstep(0.75,1.0,abs(ep.x)+pow(abs(ep.y),0.8));
  float pupil = 1.0-smoothstep(0.10,0.21,abs(ep.x));
  float open_eye = smoothstep(0.035,0.10,anim_time)*(1.0-smoothstep(0.3,0.55,anim_time));
  blood = mix(blood,mix(vec3(0.94,0.78,0.55),deep,pupil),eye*ego_strength*eye_density*3.0*open_eye);
 }
 COLOR = vec4(blood,body*reveal*opacity);
}
