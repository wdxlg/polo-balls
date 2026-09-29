shader_type canvas_item;
render_mode unshaded, skip_vertex_transform;
#include "res://shaders/summit_battle_focus.gdshaderinc"
instance uniform float focus_role = 0.0; // 0: untouched floor/shadow; 1: scenery; 2: architecture
varying vec2 focus_world_point;

// 只对两个墙体合成 Sprite 使用未取整的世界变换。
// 全局 2D transform pixel-snap 会取整 Sprite 的逆相机平移，
// 再经 Camera2D zoom 放大为数像素的墙体跳动；不关闭其它像素美术的吸附。
// 保留普通 UV（不改为 SCREEN_UV），共享 World2D 的录制/总览相机仍能重投影。
uniform vec4 quad_world_basis = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 quad_world_origin = vec2(0.0);

void vertex() {
	VERTEX = vec2(
		dot(quad_world_basis.xz, VERTEX),
		dot(quad_world_basis.yw, VERTEX)
	) + quad_world_origin;
	focus_world_point = VERTEX;
}

void fragment() {
	COLOR.rgb = summit_focus_grade(COLOR.rgb, focus_world_point, focus_role);
}
