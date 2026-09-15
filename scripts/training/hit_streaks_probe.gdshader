shader_type canvas_item;
uniform sampler2D streak_data : filter_nearest, repeat_disable;
instance uniform float elapsed = 0.0;
float smoother(float x) {
    float t = clamp(x,0.0,1.0);
    return t*t*t*(t*(t*6.0-15.0)+10.0);
}
void vertex() {
    int row = int(INSTANCE_CUSTOM.x + 0.5);
    vec4 p = texelFetch(streak_data,ivec2(0,row),0);
    vec4 q = texelFetch(streak_data,ivec2(1,row),0);
    vec4 r = texelFetch(streak_data,ivec2(2,row),0);
    vec4 c = texelFetch(streak_data,ivec2(3,row),0);
    vec4 flags = texelFetch(streak_data,ivec2(4,row),0);
    float local_time = elapsed - q.w;
    float progress = clamp(local_time/r.x,0.0,1.0);
    if (local_time < 0.0 || progress >= 1.0) {
        VERTEX = vec2(0.0);
        COLOR.a = 0.0;
    } else {
        float length_now = 0.0;
        float head = 0.0;
        float tail = 0.0;
        if (flags.x > 0.5) {
            if (progress <= q.z) {
                float g = smoother(progress/max(q.z,0.001));
                length_now = q.y*g;
                head = length_now;
            } else {
                float t = (progress-q.z)/max(1.0-q.z,0.001);
                float curve = smoother(t);
                length_now = q.y*(1.0-curve);
                head = q.y+max(q.x-q.y,0.0)*curve;
                tail = max(head-length_now,0.0);
            }
        } else {
            head = q.x*(1.0-pow(1.0-progress,3.0));
            if (progress <= q.z) {
                float t = clamp(progress/q.z,0.0,1.0);
                length_now = q.y*(1.0-pow(1.0-t,2.0));
            } else {
                float t = clamp((progress-q.z)/(1.0-q.z),0.0,1.0);
                length_now = q.y*pow(1.0-t,1.35);
            }
            tail = max(head-length_now,0.0);
        }
        float alpha_ratio = 1.0;
        if (progress < r.y) {
            alpha_ratio = smoother(progress/max(r.y,0.001));
        } else if (progress > r.z) {
            alpha_ratio = 1.0-smoother((progress-r.z)/max(1.0-r.z,0.001));
        }
        float width_fade = smoother(clamp((progress-0.52)/0.48,0.0,1.0));
        float width = max(r.w*mix(1.0,0.55,width_fade),0.16);
        vec2 n = vec2(-p.w,p.z);
        vec2 vertex_local = VERTEX;
        VERTEX = p.xy + p.zw*mix(tail,head,UV.x)
            + (p.zw*vertex_local.x + n*vertex_local.y)*width;
        COLOR *= vec4(c.rgb,c.a*alpha_ratio);
    }
}
