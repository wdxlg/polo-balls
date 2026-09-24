shader_type canvas_item;
render_mode unshaded, blend_mix;

// 天陨箭雨的天穹带：与裂隙同一套原生星空（cosmic atlas、20Hz 原生时序），
// 但作为“远景天空”随镜头做与地图外棋盘背景相同比例的视差滚动。
// 显现：前沿用欠阻尼弹簧弹性弹出（reveal 可短暂 >1：过冲），可见部分始终是
// “顶部实、自上而下渐隐到底缘”的完整形态随当前高度伸缩；
// 收回：整带统一不透明度渐隐——渐变形状（45% 起渐隐、底缘长软边）全程不变。
// 网格以画面（canvas）像素为单位（脚本把全局变换钉在 canvas 逆变换上），
// 这里的 band_height / band_local 都是画面像素，与镜头 zoom 无关。
uniform sampler2D cosmic_atlas : filter_nearest, repeat_disable;
uniform float cosmic_time = 0.0;
uniform bool linear_output = false;
uniform float band_height = 80.0;
uniform float reveal_front = 0.0; // 弹性弹出的显现前沿（0~1+，可短暂过冲）
uniform float fade_front = 0.0;  // 收回程度（0~1）：只乘整带不透明度，不改形状
uniform vec2 parallax_anchor = vec2(0.0); // 镜头世界位置（与世界外棋盘背景同源）
uniform float parallax_scale = 0.32;      // 与地图外棋盘背景相同的视差比例
// 取自 av_bow_idle.png 的天堂弓深青 #14534f：暗星区里混入一层底色、
// 前沿/底缘加一道微光，让带在地图外的蓝色棋盘背景上也读得出来
// （与裂隙的弓色描边同一视觉语言）。
uniform vec4 band_tint : source_color = vec4(0.078431, 0.325490, 0.309804, 1.0);

varying vec2 band_local;
varying vec2 cosmic_plane;

#include "res://shaders/heavenfall_cosmic_common.gdshaderinc"

void vertex() {
	// UV 存自定义带内局部像素坐标：(0,0) 在带左上，y 向下增长；顶部的屏幕外余量为负值。
	band_local = UV;
	vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	// 视差：星空平面 = 世界位置 - (1-比例)·镜头位置。比例=1 时与世界锁定
	// （退化为裂隙的同一平面），比例=0 时完全固定在屏幕上；
	// 0.32 与地图外棋盘背景同速滚动，星点在屏幕上的大小保持不变。
	cosmic_plane = (world_pos - (1.0 - clamp(parallax_scale, 0.0, 1.0)) * parallax_anchor) / 180.0;
}

void fragment() {
	float edge = reveal_front * band_height;
	if (edge <= 0.0001) { discard; }
	// 收回：整带统一不透明度。可见形态永远是同一梯度：顶部实，
	// 从 45% 前沿高度起自上而下渐隐到前沿；收回时它原样变淡，不被压缩。
	float opacity = clamp(1.0 - fade_front, 0.0, 1.0);
	if (opacity <= 0.004) { discard; }
	float window = 1.0 - smoothstep(edge * 0.45, edge, band_local.y);
	if (window <= 0.004) { discard; }
	// 星空为主（70%），底色用天堂弓深青压暗：地图背景自带星点夜空，
	// 带必须比背景更“深空”才读得出是一条独立的星空区域。
	vec3 rgb = mix(band_tint.rgb * 0.6, cosmic_colour(cosmic_plane), 0.7);
	// 移动前沿的青绿微光：渐显/渐退的推进位置一眼可辨（与裂隙弓色描边同一视觉语言）。
	rgb += band_tint.rgb * exp(-abs(band_local.y - edge) / 7.0) * 0.6;
	COLOR = vec4(rgb, window * opacity);
}
