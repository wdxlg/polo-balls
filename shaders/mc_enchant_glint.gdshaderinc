// 附魔光：原版 enchanted_item_glint 两层斜向滚动，叠加在人物自己的像素上。
// 人物主 Shader 引入后，光效和人物共用同一套朝向镜像、软体形变、区域裁切与透明度，
// 不再需要单独的覆盖层去追。mc_enchantments.gd 每帧写 enchant_glint：
// x=强度（0 关闭）、y=附魔时钟（暂停时冻结）、z=世界缩放（让光纹按屏幕像素粗细保持一致）。
instance uniform vec4 enchant_glint = vec4(0.0);
uniform sampler2D enchant_glint_texture : hint_default_black, repeat_enable, filter_nearest;

// texture_uv：最终采样 TEXTURE 用的坐标（已做镜像/形变）；返回要加到 rgb 上的光。
vec3 mc_enchant_glint_rgb(vec2 texture_uv, vec2 texel_size) {
	if (enchant_glint.x <= 0.0) {
		return vec3(0.0);
	}
	vec2 p = (texture_uv / max(texel_size, vec2(0.000001))) * max(enchant_glint.z, 0.01) * 0.045;
	vec2 a = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
	vec2 b = vec2(p.x * 0.6 + p.y * 0.8, -p.x * 0.8 + p.y * 0.6);
	float t = enchant_glint.y;
	float first = texture(enchant_glint_texture, a + vec2(t * 0.12, -t * 0.07)).r;
	float second = texture(enchant_glint_texture, b + vec2(-t * 0.09, t * 0.11)).r;
	float shine = clamp((first - 0.25) * 0.95 + (second - 0.25) * 0.52, 0.0, 0.70);
	return vec3(0.66, 0.24, 1.0) * shine * 0.8 * enchant_glint.x;
}
