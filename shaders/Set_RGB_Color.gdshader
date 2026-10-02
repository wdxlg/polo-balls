shader_type canvas_item;

instance uniform float power:hint_range(0.0, 1.0) = 0.0;
// Optional copy style; default0 preserves every existing character.
instance uniform float character_grayscale:hint_range(0.0,1.0) = 0.0;
instance uniform vec4 hit_white_color:source_color;

instance uniform float defualt_color_mix:hint_range(0.0, 1.0) = 0.0;
instance uniform vec4 default_color:source_color;

// V6：人物左右朝向也在 Shader 内完成。
// 不再依赖 Sprite2D.flip_h 的负目标矩形，避免与 UV 软体形变/区域裁切冲突。
instance uniform float sprite_flip_h:hint_range(0.0, 1.0) = 0.0;

// ============================================================
// V7 移动软体惯性：持续按真实移动方向与速度轻微拉伸。
// 例如向右移动：X 变大、Y 变小；斜向移动则沿斜向轴拉伸。
// 只改变纹理表现，不改变碰撞体。
// ============================================================
// V7.1：打包移动参数，避免超过 Godot 每个 Shader 最多 16 个 instance uniform。
// x=strength, y=stretch, z=squash, w=lean
instance uniform vec4 motion_params = vec4(0.0, 0.105, 0.065, 0.028);
instance uniform vec2 motion_direction = vec2(1.0, 0.0);

// ============================================================
// V5 丝滑反弹：只给每个实例一个 phase + 撞击参数。
// Sprite2D 只有四个顶点，仅做顶点 scale 看起来会像硬纸片。
// 这里主要在 fragment() 中非线性重映射 UV，让人物真的出现
// “撞击面凹陷 -> 中段鼓起 -> 顺势拉长 -> 果冻余震”的视觉形变。
// ============================================================
// V7.1：打包反弹参数。
// A: x=phase, y=strength, z=squash, w=bulge
// B: x=rebound, y=wobble, z=recoil, w=tilt
instance uniform vec4 bounce_params_a = vec4(1.0, 0.0, 0.34, 0.20);
instance uniform vec4 bounce_params_b = vec4(0.17, 0.040, 68.0, 0.070);
instance uniform vec2 bounce_direction = vec2(1.0, 0.0);

// Snow-cold tint is independent of team color, poison modulation and hit flashes.
instance uniform float snow_cold:hint_range(0.0, 1.0) = 0.0;
// Default-zero, per-instance visual-only freeze tremor. It never moves physics
// or the Graphics transform used by the independent ordinary-stun system.
instance uniform vec2 snow_freeze_offset = vec2(0.0);
// 形变外扩：UV 形变会把人物画到原贴图矩形之外，而像素只在绘制矩形内产生。
// 形变期间由 ball.gd 填入图片局部绘制矩形（xy=中心，zw=尺寸），顶点每边外扩 DEFORM_PAD，
// 越界的部分才能画出来；zw 为 0 时不外扩，与原来完全一致。
instance uniform vec4 deform_rect = vec4(0.0);
const float DEFORM_PAD = 0.35;
varying vec2 deform_local_uv;

varying vec4 sprite_modulate;
#include "res://shaders/mc_enchant_glint.gdshaderinc"

float bell(float x, float center, float width) {
	float q = (x - center) / max(width, 0.0001);
	return exp(-(q * q));
}

// V7：更像软体小球的连续曲线。
// impact 不是一闪而过的尖峰，而是“迅速压住 -> 很短保持 -> 松开”；
// rebound 紧接着反向拉长，jelly 再做两三次衰减余震。
void bounce_curves(float t, out float impact, out float rebound, out float jelly) {
	// V8 默认更“硬”：更快进入最大压缩，更早释放，余震更短更快衰减。
	float impact_in = smoothstep(0.0, 0.055, t);
	float impact_out = 1.0 - smoothstep(0.140, 0.220, t);
	impact = impact_in * impact_out;

	rebound = bell(t, 0.300, 0.090);

	float tail_t = max(t - 0.215, 0.0);
	float tail_gate = smoothstep(0.205, 0.285, t) * (1.0 - smoothstep(0.82, 0.98, t));
	jelly = sin(tail_t * 25.0) * exp(-5.8 * tail_t) * tail_gate;
}

void vertex() {
	// V9：反弹不再整体平移/旋转整张人物图片。
	// 所有“弹性”都留在 fragment UV 的局部软体形变里，角色视觉锚点始终固定。
	deform_local_uv = vec2(0.0);
	if (deform_rect.z > 0.0 && deform_rect.w > 0.0) {
		// 原始顶点在矩形哪个角（0 或 1）；外扩后局部坐标落在 [-PAD, 1+PAD]，片元里照常判越界。
		vec2 corner = step(deform_rect.xy, VERTEX);
		vec2 grow = (corner * 2.0 - 1.0) * DEFORM_PAD;
		VERTEX += grow * deform_rect.zw;
		deform_local_uv = corner + grow;
	}
	VERTEX += snow_freeze_offset;
	sprite_modulate = COLOR;
}

void fragment() {
	float t = clamp(bounce_params_a.x, 0.0, 1.0);
	float strength = clamp(bounce_params_a.y, 0.0, 1.25);
	float bounce_squash = bounce_params_a.z;
	float bounce_bulge = bounce_params_a.w;
	float bounce_rebound = bounce_params_b.x;
	float bounce_wobble = bounce_params_b.y;
	vec2 dir = bounce_direction;
	if (length(dir) < 0.0001) {
		dir = vec2(1.0, 0.0);
	} else {
		dir = normalize(dir);
	}
	vec2 side_dir = vec2(-dir.y, dir.x);

	float impact;
	float rebound;
	float jelly;
	bounce_curves(t, impact, rebound, jelly);

	// REGION_RECT 让开启 Sprite2D region/crop 的角色仍按自己的可见区域形变。
	// V6 额外对区域矩形做正向归一化：即使外部节点意外产生负向区域，
	// Shader 也不会把整个人物错误判定到 0..1 之外。
	vec2 region_a = REGION_RECT.xy;
	vec2 region_b = REGION_RECT.xy + REGION_RECT.zw;
	vec2 region_origin = min(region_a, region_b);
	vec2 region_size = max(abs(REGION_RECT.zw), vec2(0.000001));
	vec2 local_uv = (UV - region_origin) / region_size;
	if (deform_rect.z > 0.0 && deform_rect.w > 0.0) {
		local_uv = deform_local_uv;
	}
	vec2 p = local_uv - vec2(0.5);

	// ------------------------------------------------------------
	// A. 常驻移动惯性层
	// ------------------------------------------------------------
	vec2 move_dir = motion_direction;
	if (length(move_dir) < 0.0001) {
		move_dir = vec2(1.0, 0.0);
	} else {
		move_dir = normalize(move_dir);
	}
	vec2 move_side_dir = vec2(-move_dir.y, move_dir.x);
	float move_power = clamp(motion_params.x, 0.0, 1.0);
	float motion_stretch = motion_params.y;
	float motion_squash = motion_params.z;
	float motion_lean = motion_params.w;

	float move_along = dot(p, move_dir);
	float move_side = dot(p, move_side_dir);
	float move_axis_scale = 1.0 + motion_stretch * move_power;
	float move_side_scale = max(1.0 - motion_squash * move_power, 0.72);

	// 视觉目标是沿移动方向拉长，因此反向采样时沿轴除以 >1 的值。
	// 垂直轴则除以 <1 的值，从而得到轻微压扁。
	p = move_dir * (move_along / move_axis_scale)
		+ move_side_dir * (move_side / move_side_scale);

	// 身体下部稍微领先，头肩轻微滞后，制造惯性而不是整张卡片一起缩放。
	float upper_mask = 1.0 - smoothstep(0.18, 0.52, local_uv.y);
	p -= move_dir * (motion_lean * move_power * upper_mask);

	// ------------------------------------------------------------
	// B. 撞击软体层
	// ------------------------------------------------------------
	float along = dot(p, dir);
	float side = dot(p, side_dir);

	// 真人头脸只吃较少的 squash，胸口/衣服区域保持完整软体强度。
	float head_mask = 1.0 - smoothstep(0.10, 0.43, local_uv.y);
	float elastic_weight = mix(1.0, 0.58, head_mask);

	// 1) 撞击：沿碰撞方向压扁，垂直方向鼓起。
	// 2) 弹出：沿反弹轴 overshoot 拉长。
	// 3) 余震：小幅正负交替，逐渐衰减。
	float axis_scale = 1.0
		- bounce_squash * elastic_weight * strength * impact
		+ bounce_rebound * elastic_weight * strength * rebound
		+ 0.085 * elastic_weight * strength * jelly;
	float side_scale = 1.0
		+ bounce_bulge * elastic_weight * strength * impact
		- bounce_rebound * 0.50 * elastic_weight * strength * rebound
		- 0.055 * elastic_weight * strength * jelly;
	axis_scale = clamp(axis_scale, 0.46, 1.46);
	side_scale = clamp(side_scale, 0.70, 1.48);

	// 中部比上下两端更容易鼓起，让撞击轮廓有“肉感”。
	float along_center = 1.0 - smoothstep(0.05, 0.52, abs(along));
	float torso_mask = smoothstep(0.18, 0.48, local_uv.y);
	float local_bulge = 1.0 + bounce_bulge * 0.52 * strength * impact * along_center * mix(0.60, 1.0, torso_mask);

	float sample_along = along / axis_scale;
	float sample_side = side / (side_scale * local_bulge);

	// 撞墙的那一侧产生局部凹陷。中央最明显，头脚/边缘较弱，
	// 让轮廓像软体被墙面压进去，而不是整张照片一起平移。
	float hit_face = smoothstep(-0.08, 0.50, along);
	float side_center = 1.0 - smoothstep(0.10, 0.52, abs(side));
	float dent = 0.150 * strength * impact * hit_face * side_center * mix(0.62, 1.0, torso_mask);
	sample_along += dent;

	// 回弹后的果冻摆动：中心与上下/左右的位移略有相位差。
	// 只改采样坐标，不动碰撞体。
	float bend_profile = sin((along + 0.5) * 3.14159265);
	float ripple_profile = sin((along + 0.5) * 6.2831853);
	sample_side += bounce_wobble * strength * jelly * (0.75 * bend_profile + 0.25 * ripple_profile);

	// 弹出时让撞击面有一点“拖尾滞后”，增强肉感。
	float release_drag = 0.048 * strength * rebound * hit_face * side_center;
	sample_along -= release_drag;

	// 头部惯性：撞上时头继续往原运动方向一点，弹开时又比躯干慢半拍。
	// 只做很小的采样偏移，避免真人脸被明显扭曲。
	float head_lag = head_mask * strength * (0.024 * impact - 0.018 * rebound + 0.012 * jelly);
	sample_along -= head_lag;

	vec2 warped_local_uv = vec2(0.5) + dir * sample_along + side_dir * sample_side;

	// 是否越界只看“形变后的几何局部坐标”，与人物面朝哪边无关。
	// 这样向右/向左只是换纹理朝向，不会把整张图误裁成透明。
	float inside = step(0.0, warped_local_uv.x) * step(warped_local_uv.x, 1.0)
		* step(0.0, warped_local_uv.y) * step(warped_local_uv.y, 1.0);

	// 最后一步才做水平镜像采样。Sprite2D 本身始终保持 flip_h=false，
	// 所以软体形变、REGION_RECT 和裁切都处在稳定的正向坐标系里。
	vec2 sample_local_uv = warped_local_uv;
	if (sprite_flip_h > 0.5) {
		sample_local_uv.x = 1.0 - sample_local_uv.x;
	}
	vec2 warped_uv = region_origin + sample_local_uv * region_size;

	vec4 tex = texture(TEXTURE, warped_uv);
	tex.a *= inside;

	vec4 out_color = tex * sprite_modulate;
	out_color.rgb = mix(out_color.rgb, default_color.rgb, defualt_color_mix);
	out_color.rgb = mix(out_color.rgb, vec3(0.94, 0.98, 1.0), clamp(snow_cold, 0.0, 1.0) * 0.88);
	out_color.rgb = mix(out_color.rgb, hit_white_color.rgb, power);
	out_color.rgb += mc_enchant_glint_rgb(warped_uv, TEXTURE_PIXEL_SIZE);
	float luminance = dot(out_color.rgb,vec3(0.299,0.587,0.114));
	out_color.rgb = mix(out_color.rgb,vec3(luminance),character_grayscale);
	COLOR = out_color;
}
