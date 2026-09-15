shader_type canvas_item;

// V301：只在 GPU 顶点阶段做吸管头渐进弯曲。
// Polygon2D 的 authored polygon/uv 不再逐帧改写，因此不会因大角度变形产生自交后重新三角剖分失败。
uniform vec2 root_local = vec2(0.0);
uniform vec2 axis_dir = vec2(0.0, 1.0);
uniform float axis_length = 1.0;
uniform float root_hold_ratio : hint_range(0.0, 0.65, 0.01) = 0.18;
uniform float curve_exponent : hint_range(0.35, 3.0, 0.05) = 2.0;
uniform float bend_angle : hint_range(-3.141593, 3.141593, 0.001) = 0.0;

void vertex() {
    vec2 p = VERTEX - root_local;
    float progress = clamp(dot(p, axis_dir) / max(axis_length, 0.001), 0.0, 1.0);
    float denom = max(1.0 - root_hold_ratio, 0.001);
    float t = clamp((progress - root_hold_ratio) / denom, 0.0, 1.0);
    t = t * t * (3.0 - 2.0 * t);
    float weight = pow(t, max(curve_exponent, 0.35));
    float a = bend_angle * weight;
    float c = cos(a);
    float s = sin(a);
    vec2 rotated = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
    VERTEX = root_local + rotated;
}
