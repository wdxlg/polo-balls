extends "res://scripts/characters/我的世界/new5/base.gd"
# 弓：蓄力决定初速，重力改变飞行速度；命中伤害与实际速度成正比。
# 蓄满自动射出，敌人贴近也会提前松弦；击退随蓄力从小幅变中幅。
# 拉满后再屏息一小段时间作为最后蓄力：弓身微微颤抖，抖幅随蓄力增加而增大；
# 松弦时弓被反向震回，震幅随整段蓄力时长增加，随后弹性回归原位。
const ARROW: PackedScene = preload("res://scenes/shooter/我的世界/骷髅箭.tscn")
const TEX_IDLE: Texture2D = preload("res://Images/characters/默认/盔甲架/Bow.png")
const TEX_PULL0: Texture2D = preload("res://Images/characters/默认/盔甲架/Bow_Pulling_0.png")
const TEX_PULL1: Texture2D = preload("res://Images/characters/默认/盔甲架/Bow_Pulling_1.png")
const TEX_PULL2: Texture2D = preload("res://Images/characters/默认/盔甲架/Bow_Pulling_2.png")
const FX = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")
# Minecraft 弓原图斜向构图；+135° 后弓弧朝敌人、弓弦在后（与弓箭盔甲架一致）。
const TEX_OFFSET: float = PI * 0.75
# 后坐是欠阻尼弹簧 exp(-RECOIL_DECAY*t)*sin(RECOIL_OMEGA*t)：
# 6Hz 振荡，约 32ms 到达最大后移，随后每半周期衰减到 30%，0.45s 内归位。
const RECOIL_OMEGA: float = TAU * 6.0
const RECOIL_DECAY: float = 14.4
const RECOIL_LIFETIME: float = 0.45

@export var shoot_range: float = 200.0
@export var draw_time: float = 1.6
# 拉满之后的最后蓄力：弓弦已到底，屏息颤抖这么久后自动松弦。
@export var full_hold_time: float = 0.35
@export var cooldown: float = 0.8
@export var arrow_speed: float = 1000.0
@export var arrow_min_speed: float = 280.0
@export var arrow_gravity: float = 700.0
@export var arrow_damage_reference_speed: float = 280.0
@export var arrow_afterimage_speed: float = 780.0
@export var knockback_near: float = 20.0
@export var knockback_full: float = 60.0
@export var close_range: float = 85.0
# 弓图像缩放 0.115 时的局部出箭偏移，不是世界像素。
# 经 Image 的完整变换后，角色默认 0.2 缩放下约为 11.6 世界像素。
@export var muzzle_offset: float = 58.0
@export var arrow_max_dist: float = 240.0
@export var draw_move_ratio: float = 0.6
# 颤抖 / 后坐位移都写在 Image.position（Graphics 空间），角色默认 0.2 缩放下 ×0.2 即世界像素。
# 最后蓄力结束时的最大颤抖位移与最大颤抖倾角。
@export var tremble_shift: float = 6.0
@export var tremble_tilt: float = 0.045
# 整段蓄力拉满时的最大后坐位移与后仰角；后坐强度按 (蓄力时长 / 总蓄力时长) 缩放。
@export var recoil_shift: float = 36.0
@export var recoil_tilt: float = 0.16
# 刚搭箭就松弦也要有一点反馈，不至于完全没有动静。
@export var recoil_min_ratio: float = 0.25

var facing: Vector2 = Vector2.RIGHT
# 蓄力秒数；超过 draw_time 的部分就是拉满后的最后蓄力（颤抖段）。
var drawing: float = 0.0
var _cool: float = 0.0
var _draw_audio_stage: int = 0
var _draw_player: AudioStreamPlayer2D
var _rest_image_position: Vector2 = Vector2.ZERO
var _rest_image_cached: bool = false
# 后坐状态：强度 0~1、方向（松弦瞬间的 -facing）、倾斜方向、松弦时刻（与 _view_clock 同一时间轴）。
var _recoil_power: float = 0.0
var _recoil_dir: Vector2 = Vector2.ZERO
var _recoil_tilt_sign: float = 1.0
var _recoil_start: float = -RECOIL_LIFETIME
# 每次松弦递增；客户端据此只重放一次后坐，而不是每个同步包都重放。
var _shot_seq: int = 0
var _last_shot_charge: float = 0.0
var _visual_synced: bool = false


func _ready() -> void:
	super._ready()
	if direction.length_squared() > 0.001:
		facing = direction.normalized()
	if image is Sprite2D:
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func total_draw_time() -> float:
	return maxf(draw_time, 0.01) + maxf(full_hold_time, 0.0)


# 弓弦拉开程度 0~1；拉满后保持 1。
func charge_ratio() -> float:
	return clampf(drawing / maxf(draw_time, 0.01), 0.0, 1.0)


# 拉满后最后蓄力的进度 0~1；未拉满为 0，颤抖幅度跟着它增长。
func hold_ratio() -> float:
	if full_hold_time <= 0.0:
		return 1.0 if drawing >= draw_time else 0.0
	return clampf((drawing - draw_time) / full_hold_time, 0.0, 1.0)


func step_mob(delta: float) -> void:
	_cool -= delta
	var want_fire: bool = false
	if is_player_controlled() and has_player_control_aim():
		facing = player_control_aim_direction(facing)
		want_fire = true
	else:
		var target: ball = U.nearest(self)
		if target != null and global_position.distance_to(target.global_position) <= shoot_range + U.radius(target) and U.line_clear(self, global_position, target.global_position):
			facing = (target.global_position - global_position).normalized()
			want_fire = true
	if want_fire and can_act() and _cool <= 0.0:
		drawing += delta
		_set_draw_audio_stage(1 if drawing < draw_time * 0.5 else 2)
		if drawing >= total_draw_time():
			_fire(1.0, true)
		elif drawing >= 0.15:
			var near: ball = U.nearest(self)
			if near != null and global_position.distance_to(near.global_position) <= close_range:
				# 弓弦已拉满（正在最后蓄力）时被迫松弦仍算蓄满一箭。
				var ratio: float = charge_ratio()
				_fire(ratio, ratio >= 1.0)
	else:
		_set_draw_audio_stage(0)
		drawing = maxf(0.0, drawing - delta * 4.0)


func _set_draw_audio_stage(stage: int) -> void:
	if not is_multiplayer_authority() or stage == _draw_audio_stage:
		return
	if multiplayer.has_multiplayer_peer():
		_receive_draw_audio_stage.rpc(stage)
	_receive_draw_audio_stage(stage)


@rpc("authority", "call_remote", "reliable")
func _receive_draw_audio_stage(stage: int) -> void:
	_stop_draw_player()
	_draw_audio_stage = stage
	if stage == 0:
		return
	# Vanilla normal bows have no draw sample; these are official crossbow sounds.
	var event: String = "item.crossbow.loading_start" if stage == 1 else "item.crossbow.loading_middle"
	_draw_player = AUDIO.play(self, event, global_position, 2.0, false, false, true, true)


func _stop_draw_player() -> void:
	if is_instance_valid(_draw_player):
		_draw_player.stop()
		_draw_player.remove_from_group("MCNativeSFX")
		_draw_player.queue_free()
	_draw_player = null


func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_draw_player):
		_draw_player.global_position = global_position
		_draw_player.stream_paused = not is_combat_runtime_active()


func Die() -> void:
	_set_draw_audio_stage(0)
	_stop_draw_player()
	super.Die()


func _exit_tree() -> void:
	_stop_draw_player()
	super._exit_tree()


func play_arrow_terrain_hit(at_position: Vector2) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_receive_arrow_terrain_hit.rpc(at_position)
	_receive_arrow_terrain_hit(at_position)


@rpc("authority", "call_remote", "reliable")
func _receive_arrow_terrain_hit(at_position: Vector2) -> void:
	# Same three original arrow-hit OGGs as skeleton arrows, one event per impact.
	AUDIO.play(self, "entity.arrow.hit", at_position, 1.2, false, true, true, true)


func arrow_muzzle_world_position() -> Vector2:
	# The asset points diagonally up-left before TEX_OFFSET rotation.
	# Converting through Image includes character/Graphics scale and offsets.
	var sprite: Sprite2D = image as Sprite2D
	if sprite == null:
		return to_global(facing.normalized() * muzzle_offset)
	var local_tip: Vector2 = Vector2(muzzle_offset / 0.115, 0.0).rotated(-TEX_OFFSET)
	local_tip += sprite.offset
	if not sprite.centered and sprite.texture != null:
		local_tip += sprite.texture.get_size() * 0.5
	return sprite.to_global(local_tip)


func _fire(ratio: float, full: bool) -> void:
	_set_draw_audio_stage(0)
	var charge: float = clampf(ratio, 0.0, 1.0)
	# 后坐强度看整段蓄力时长：拉满并颤抖到底才是 1，刚搭箭就松弦接近下限。
	var held: float = clampf(maxf(drawing, charge * draw_time) / total_draw_time(), 0.0, 1.0)
	# Aim can change in physics before the next visual frame; refresh before sampling.
	# 出箭点要从静止的弓身取：清掉上一箭残余的后坐，drawing 不超过 draw_time 时也没有颤抖。
	drawing = charge * draw_time
	_recoil_power = 0.0
	visual_mob()
	var muzzle: Vector2 = arrow_muzzle_world_position()
	drawing = 0.0
	_cool = cooldown
	_shot_seq += 1
	_start_recoil(lerpf(recoil_min_ratio, 1.0, held), facing, clock)
	var world: Node = get_tree().current_scene
	if world == null:
		return
	var arrow: Area2D = ARROW.instantiate() as Area2D
	world.add_child(arrow, true)
	arrow.global_position = muzzle
	var launch_speed: float = lerpf(arrow_min_speed, arrow_speed, charge)
	var damage_per_speed: float = attack_damage(1.0) / maxf(arrow_damage_reference_speed, 1.0)
	var kb: float = lerpf(knockback_near, knockback_full, charge)
	arrow.call("configure_plain", self, Team, facing, launch_speed, damage_per_speed * launch_speed, kb, 220.0, 5.5)
	arrow.call("configure_ballistics", arrow_gravity, damage_per_speed, arrow_afterimage_speed)
	arrow.set("_new6_hit_sfx", true)
	arrow.set("_new6_max_dist", arrow_max_dist)
	play_sound("entity.arrow.shoot", -4.0)
	if full:
		play_sound("entity.player.attack.crit", -2.0)
		FX.burst(world, "crit", muzzle, facing, 6, 90.0, 0.35, 7.0)


func _start_recoil(power: float, aim: Vector2, at: float) -> void:
	_recoil_power = clampf(power, 0.0, 1.0)
	_recoil_dir = -aim.normalized() if aim.length_squared() > 0.000001 else Vector2.ZERO
	# 交替向两侧后仰，连续射击时不会永远往同一边歪。
	_recoil_tilt_sign = -_recoil_tilt_sign
	_recoil_start = at
	_last_shot_charge = _recoil_power


# 归一化后坐曲线：0 → 1（最大后移）→ 反向小幅前冲 → 衰减归零。
static func recoil_curve(age: float) -> float:
	if age <= 0.0 or age >= RECOIL_LIFETIME:
		return 0.0
	var peak_age: float = atan(RECOIL_OMEGA / RECOIL_DECAY) / RECOIL_OMEGA
	var peak: float = exp(-RECOIL_DECAY * peak_age) * sin(RECOIL_OMEGA * peak_age)
	return exp(-RECOIL_DECAY * age) * sin(RECOIL_OMEGA * age) / peak


# 当前后坐波形（已乘强度）；不在后坐中为 0。
# 时间轴用 _view_clock：暂停时冻结，客户端与权威端节奏一致。
func recoil_wave() -> float:
	if _recoil_power <= 0.0 or health <= 0:
		return 0.0
	return _recoil_power * recoil_curve(_view_clock - _recoil_start)


# 拉满后的颤抖强度 0~1：随最后蓄力进度加速增长。
func tremble_level() -> float:
	if health <= 0:
		return 0.0
	var level: float = hold_ratio()
	return level * (0.35 + 0.65 * level)


# 两组不同频率、不同相位的正弦叠加成不规则抖动；
# 用 _view_clock 驱动，客户端与权威端看到同样的节奏。
func tremble_offset(level: float) -> Vector2:
	var t: float = _view_clock
	var along: float = sin(t * 71.0) * 0.6 + sin(t * 113.0 + 1.7) * 0.4
	var across: float = sin(t * 89.0 + 0.9) * 0.6 + sin(t * 137.0 + 2.3) * 0.4
	return (facing * (along * 0.5) + facing.orthogonal() * across) * (tremble_shift * level)


func tremble_angle(level: float) -> float:
	var t: float = _view_clock
	return (sin(t * 97.0 + 0.4) * 0.6 + sin(t * 151.0 + 2.9) * 0.4) * (tremble_tilt * level)


func move(speed_value: float, delta: float) -> void:
	if drawing > 0.0:
		super.move(speed_value * draw_move_ratio, delta)
	else:
		super.move(speed_value, delta)


func visual_mob() -> void:
	if image == null or not is_instance_valid(image):
		return
	if not _rest_image_cached:
		_rest_image_position = image.position
		_rest_image_cached = true
	var ratio: float = charge_ratio()
	if ratio >= 0.99:
		image.texture = TEX_PULL2
	elif ratio >= 0.62:
		image.texture = TEX_PULL1
	elif ratio > 0.05:
		image.texture = TEX_PULL0
	else:
		image.texture = TEX_IDLE
	set_character_visual_flip_h(false)
	var angle: float = facing.angle() + TEX_OFFSET
	var pose: Vector2 = _rest_image_position
	var shake: float = tremble_level()
	if shake > 0.0:
		angle += tremble_angle(shake)
		pose += tremble_offset(shake)
	var wave: float = recoil_wave()
	if wave != 0.0:
		angle += _recoil_tilt_sign * recoil_tilt * wave
		pose += _recoil_dir * (recoil_shift * wave)
	image.rotation = angle
	if not image.position.is_equal_approx(pose):
		image.position = pose


func visual_state() -> Dictionary:
	return {"time": clock, "facing": facing, "drawing": drawing, "shot": _shot_seq, "kick": _last_shot_charge}


func accept_visual(data: Dictionary) -> void:
	super.accept_visual(data)
	facing = data.get("facing", facing)
	drawing = float(data.get("drawing", 0.0))
	var shot: int = int(data.get("shot", _shot_seq))
	if shot != _shot_seq:
		# 刚加入的客户端不补放历史上的后坐；之后每次新松弦从收到的这一刻重放一次。
		if _visual_synced:
			_start_recoil(float(data.get("kick", 1.0)), facing, _view_clock)
		_shot_seq = shot
	_visual_synced = true
