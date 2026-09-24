shader_type canvas_item;
render_mode unshaded;

// 天陨落箭的“钻地”裁剪（箭身）：burrow 开始后，全局坐标低于裂缝口（clip_y）
// 的像素全部丢弃——已进入地下的部分不再绘制，箭看起来是插进了裂缝里。
uniform bool clip_enabled = false;
uniform float clip_y = 1.0e9; // 裂缝口的全局 y（世界坐标）

varying vec2 world_pos;

void vertex() {
	// MODEL_MATRIX 乘出的即全局坐标（Node2D 世界），裁剪线直接用落点的全局 y；
	// 镜头缩放/平移不影响 MODEL_MATRIX，裁剪在任何镜头下都精确。
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (clip_enabled && world_pos.y > clip_y) {
		discard;
	}
	COLOR = texture(TEXTURE, UV) * COLOR;
}
