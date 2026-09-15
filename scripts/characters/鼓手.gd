extends ball

# ============================================================
# 鼓手（碰撞触发稳定版）
#
# 关键修复：
# 1. 不再只依赖 when_collide() 触发节拍。
#    ball.gd 对“被别的 CharacterBody2D 撞到”的一方可能只走
#    notify_bounce_feedback() -> _trigger_collision_feedback()。
#    因此统一在 _trigger_collision_feedback() 上触发鼓点。
# 2. 攻击图直接切换主 Image.texture，不再创建覆盖 Sprite。
#    只改视觉，不调用 CharacterAutoFit，不修改碰撞框。
# 3. 使用 physics frame + 毫秒双重去重，避免同一次角色碰撞双方反馈导致连打多拍。
# ============================================================

@export_category("鼓手 - 外观")
@export var normal_texture:Texture2D
@export var attack_texture:Texture2D
@export_range(0.15,3.0,0.05) var attack_visual_duration:float = 0.90

@export_category("鼓手 - 节拍范围")
@export_range(5.0,200.0,0.1) var beat_1_radius:float = 29.3333
@export_range(5.0,200.0,0.1) var beat_2_radius:float = 48.3333
@export_range(5.0,200.0,0.1) var beat_3_radius:float = 51.6667
@export_range(5.0,200.0,0.1) var beat_4_radius:float = 59.3333

@export_category("鼓手 - 伤害")
@export_range(0.0,10.0,0.05) var beat_1_damage_multiplier:float = 1.0
@export_range(0.0,10.0,0.05) var beat_2_damage_multiplier:float = 1.0
@export_range(0.0,10.0,0.05) var beat_3_damage_multiplier:float = 1.0
@export_range(0.0,10.0,0.05) var beat_4_damage_multiplier:float = 2.0

@export_category("鼓手 - 第三拍拉近")
@export_range(0.0,300.0,5.0) var beat_3_pull_distance:float = 36.0
@export_range(50.0,1800.0,10.0) var beat_3_pull_speed:float = 500.0

@export_category("鼓手 - 第四拍推远")
@export_range(0.0,400.0,5.0) var beat_4_push_distance:float = 56.0
@export_range(50.0,2200.0,10.0) var beat_4_push_speed:float = 620.0

@export_category("鼓手 - 防重复触发")
@export_range(0.0,0.5,0.01) var collision_beat_guard:float = 0.12
@export var drum_audio_node:String = ""
@export var debug_drummer:bool = false

const VISUAL_NORMAL:int = 0
const VISUAL_ATTACK:int = 1
const DRUMMER_IMAGE_DIR:String = "res://Images/characters/人物/鼓手"
const FALLBACK_ATTACK_PATH:String = "res://Images/characters/人物/鼓手/鼓手_攻击_补丁.svg"
const DRUM_AUDIO_CHOICES = [
	"鼓手/鼓点01",
	"鼓手/鼓点02",
	"鼓手/鼓点03",
	"鼓手/鼓点04",
	"鼓手/鼓点05",
	"鼓手/鼓点06",
]

var _beat:int = 0
var _last_beat_msec:int = -1000000
var _last_beat_physics_frame:int = -1
var _visual_serial:int = 0
var _last_drum_audio_index:int = -1

# 正常图经过 CharacterAutoFit 后的最终显示布局。
# 攻击时只临时换 Texture/Scale/Offset；恢复时原样还回去。
var _normal_visual_captured:bool = false
var _normal_image_texture:Texture2D = null
var _normal_image_scale:Vector2 = Vector2.ONE
var _normal_image_offset:Vector2 = Vector2.ZERO
var _normal_image_position:Vector2 = Vector2.ZERO
var _normal_image_rotation:float = 0.0
var _normal_image_skew:float = 0.0


func _ready() -> void:
	super._ready()
	_auto_load_textures()

	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		if normal_texture == null:
			normal_texture = sprite.texture
		elif sprite.texture != normal_texture:
			# 场景已经明确指定“鼓手_正常”时，以场景资源为准。
			sprite.texture = normal_texture

		# 如果旧版本运行时曾创建覆盖层，确保不会残留。
		var old_overlay:Node = sprite.get_parent().get_node_or_null("DrumAttackOverlay")
		if old_overlay != null:
			old_overlay.queue_free()

		_capture_normal_visual()

	_set_visual_state_local(VISUAL_NORMAL)


# ------------------------------------------------------------
# 碰撞触发
# ------------------------------------------------------------
# 不在 when_collide() 里直接打鼓。
# 父类 when_collide()、notify_bounce_feedback()、运动变化兜底最终都会进入
# _trigger_collision_feedback()，因此这里是项目现有碰撞系统最完整的入口。
func _trigger_collision_feedback(
	impact_dir:Vector2,
	power:float,
	collision:KinematicCollision2D = null,
	suppress_audio:bool = false
) -> void:
	super._trigger_collision_feedback(impact_dir,power,collision,suppress_audio)

	if not is_multiplayer_authority():
		return

	_try_trigger_drum_beat_from_collision(collision)


func _try_trigger_drum_beat_from_collision(collision:KinematicCollision2D = null) -> void:
	var physics_frame:int = Engine.get_physics_frames()
	if physics_frame == _last_beat_physics_frame:
		return

	var now_msec:int = Time.get_ticks_msec()
	var guard_msec:int = int(round(maxf(collision_beat_guard,0.0) * 1000.0))
	if now_msec - _last_beat_msec < guard_msec:
		return

	_last_beat_physics_frame = physics_frame
	_last_beat_msec = now_msec
	_beat = (_beat % 4) + 1

	if debug_drummer:
		print(
			"[鼓手] beat=",_beat,
			" frame=",physics_frame,
			" collider=",collision.get_collider() if collision != null else null
		)

	_trigger_drum_beat(_beat)


func _trigger_drum_beat(beat:int) -> void:
	var radius:float = _radius_for_beat(beat)
	var multiplier:float = _damage_multiplier_for_beat(beat)
	var outgoing_damage:float = attack_damage(multiplier)

	# 先结算玩法，再做任何图片/声音表现。
	# 即使攻击图缺失，也绝不会阻断伤害、拉近、击退。
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue
		if global_position.distance_to(target.global_position) > radius:
			continue

		if outgoing_damage > 0.0:
			target.receive_spatial_damage(
				outgoing_damage,
				{"shape":"circle","center":global_position,"radius":radius,"source":self},
				false
			)

		if beat == 3 and beat_3_pull_distance > 0.0:
			var pull_dir:Vector2 = global_position - target.global_position
			if pull_dir.length_squared() > 0.000001:
				target.apply_knockback(
					pull_dir.normalized(),
					beat_3_pull_distance,
					beat_3_pull_speed,
					0.20,
					0.0,
					{
						"source":self,
						"max_wall_bounces":1,
						"stop_on_character":true,
					}
				)
		elif beat == 4 and beat_4_push_distance > 0.0:
			var push_dir:Vector2 = target.global_position - global_position
			if push_dir.length_squared() <= 0.000001:
				push_dir = Vector2.RIGHT.rotated(randf_range(0.0,TAU))
			target.apply_knockback(
				push_dir.normalized(),
				beat_4_push_distance,
				beat_4_push_speed,
				0.45,
				0.0,
				{
					"source":self,
					"max_wall_bounces":1,
					"stop_on_character":true,
				}
			)

	_show_beat_everywhere(beat,radius)
	_play_drum_audio()
	_show_attack_visual_everywhere()


func _radius_for_beat(beat:int) -> float:
	match beat:
		1: return beat_1_radius
		2: return beat_2_radius
		3: return beat_3_radius
		4: return beat_4_radius
	return beat_1_radius


func _damage_multiplier_for_beat(beat:int) -> float:
	match beat:
		1: return beat_1_damage_multiplier
		2: return beat_2_damage_multiplier
		3: return beat_3_damage_multiplier
		4: return beat_4_damage_multiplier
	return 1.0


func _is_valid_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == self or not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and Team != "" and target.Team != "" and Team == target.Team:
		return false
	return true


# ------------------------------------------------------------
# 声音 / 圆环
# ------------------------------------------------------------
func _play_drum_audio() -> void:
	if Audios == null:
		return

	# 如果 Inspector 没有手动指定，则从用户提供的 6 个鼓点中随机选一个。
	# 由权威端先选定具体文件，再把同一个节点路径发给所有客户端，避免多人游戏时各端听到不同鼓点。
	var audio_node:String = drum_audio_node
	if audio_node == "":
		audio_node = _pick_random_drum_audio()

	if audio_node == "":
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_play_drum_audio.rpc(audio_node)
	else:
		_rpc_play_drum_audio(audio_node)


func _pick_random_drum_audio() -> String:
	var count:int = DRUM_AUDIO_CHOICES.size()
	if count <= 0:
		return ""

	var index:int = randi_range(0,count - 1)
	if count > 1 and index == _last_drum_audio_index:
		index = (index + randi_range(1,count - 1)) % count
	_last_drum_audio_index = index
	return str(DRUM_AUDIO_CHOICES[index])


@rpc("authority","call_local","reliable")
func _rpc_play_drum_audio(audio_node:String) -> void:
	if audio_node == "" or Audios == null or Audios.Sfx == null:
		return

	var source:Node = Audios.Sfx.get_node_or_null(audio_node)
	if source is AudioStreamPlayer:
		Audios.play_sfx(audio_node,{},false,true)
	elif source != null:
		# 保留 drum_audio_node 指向一个“音效文件夹节点”的旧用法。
		Audios.play_sfx_from_node(audio_node,{},false,true)


func _show_beat_everywhere(beat:int,radius:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_drum_pulse.rpc(beat,radius)
	else:
		_rpc_show_drum_pulse(beat,radius)


@rpc("authority","call_local","reliable")
func _rpc_show_drum_pulse(beat:int,radius:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var ring := Line2D.new()
	ring.closed = true
	ring.width = 3.0 + float(beat) * 0.8
	ring.default_color = _beat_color(beat)
	ring.z_index = 32

	var points := PackedVector2Array()
	const SEGMENTS:int = 44
	for i:int in range(SEGMENTS):
		var angle:float = TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(angle),sin(angle)) * radius)
	ring.points = points
	ring.global_position = global_position
	ring.scale = Vector2(0.16,0.16)
	world.add_child(ring)
	ring.add_to_group("BattleTransient")

	var tween:Tween = ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring,"scale",Vector2.ONE,0.20 if beat < 4 else 0.26)
	tween.tween_property(ring,"modulate",Color(1.0,1.0,1.0,0.0),0.26 if beat < 4 else 0.34)
	tween.finished.connect(ring.queue_free)


func _beat_color(beat:int) -> Color:
	match beat:
		1: return Color(0.88,0.88,0.92,0.82)
		2: return Color(0.45,0.78,1.0,0.88)
		3: return Color(0.62,0.35,1.0,0.92)
		4: return Color(1.0,0.28,0.10,0.96)
	return Color.WHITE


# ------------------------------------------------------------
# 贴图加载
# ------------------------------------------------------------
func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _find_drummer_texture(["鼓手_正常","鼓手正常","正常"])
	if attack_texture == null:
		# 正式文件名：鼓手_打鼓
		attack_texture = _find_drummer_texture([
			"鼓手_打鼓","鼓手打鼓","打鼓",
			"鼓手_攻击","鼓手攻击","攻击"
		])
	if attack_texture == null:
		attack_texture = _try_load_texture(FALLBACK_ATTACK_PATH)


func _find_drummer_texture(base_names:Array[String]) -> Texture2D:
	var extensions:Array[String] = ["png","webp","jpg","jpeg","svg"]
	for base_name:String in base_names:
		for extension:String in extensions:
			var texture:Texture2D = _try_load_texture(DRUMMER_IMAGE_DIR.path_join(base_name + "." + extension))
			if texture != null:
				return texture

	var dir := DirAccess.open(DRUMMER_IMAGE_DIR)
	if dir != null:
		for file_name:String in dir.get_files():
			var lower_ext:String = file_name.get_extension().to_lower()
			if not (lower_ext in extensions):
				continue
			for base_name:String in base_names:
				if file_name.get_basename().contains(base_name):
					var found:Texture2D = _try_load_texture(DRUMMER_IMAGE_DIR.path_join(file_name))
					if found != null:
						return found
	return null


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


# ------------------------------------------------------------
# 攻击视觉：直接切主 Sprite2D，不碰 CollisionShape2D
# ------------------------------------------------------------
func _capture_normal_visual() -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D
	_normal_image_texture = normal_texture if normal_texture != null else sprite.texture
	_normal_image_scale = sprite.scale
	_normal_image_offset = sprite.offset
	_normal_image_position = sprite.position
	_normal_image_rotation = sprite.rotation
	_normal_image_skew = sprite.skew
	_normal_visual_captured = true


func _show_attack_visual_everywhere() -> void:
	_visual_serial += 1
	var serial:int = _visual_serial
	var duration:float = maxf(attack_visual_duration,0.15)
	if multiplayer.has_multiplayer_peer():
		_rpc_show_attack_visual.rpc(serial,duration)
	else:
		_rpc_show_attack_visual(serial,duration)


@rpc("authority","call_local","reliable")
func _rpc_show_attack_visual(serial:int,duration:float) -> void:
	if serial < _visual_serial:
		return
	_visual_serial = serial
	_set_visual_state_local(VISUAL_ATTACK)
	_restore_normal_visual_after(duration,serial)


func _restore_normal_visual_after(delay:float,serial:int) -> void:
	await get_tree().create_timer(maxf(delay,0.15)).timeout
	if not is_instance_valid(self) or serial != _visual_serial:
		return
	_set_visual_state_local(VISUAL_NORMAL)


func _set_visual_state_local(state_value:int) -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D

	if not _normal_visual_captured:
		_capture_normal_visual()

	if state_value == VISUAL_ATTACK and attack_texture != null:
		_apply_attack_texture_layout(sprite)
		return

	# 恢复 CharacterAutoFit 已经算好的正常图最终布局。
	if _normal_image_texture != null:
		sprite.texture = _normal_image_texture
	elif normal_texture != null:
		sprite.texture = normal_texture
	sprite.scale = _normal_image_scale
	sprite.offset = _normal_image_offset
	sprite.position = _normal_image_position
	sprite.rotation = _normal_image_rotation
	sprite.skew = _normal_image_skew
	sprite.visible = true


func _apply_attack_texture_layout(sprite:Sprite2D) -> void:
	if attack_texture == null:
		return

	var normal:Texture2D = _normal_image_texture if _normal_image_texture != null else normal_texture
	var attack_metrics:Dictionary = _texture_visible_metrics(attack_texture)
	var normal_metrics:Dictionary = _texture_visible_metrics(normal)
	var attack_size:Vector2 = attack_metrics.get("size",attack_texture.get_size())
	var normal_size:Vector2 = normal_metrics.get("size",normal.get_size() if normal != null else attack_size)

	# 保持“人物可见主体”的世界尺寸与正常图接近，不调用 CharacterAutoFit。
	var normal_visible_long:float = maxf(
		normal_size.x * absf(_normal_image_scale.x),
		normal_size.y * absf(_normal_image_scale.y)
	)
	var attack_long:float = maxf(attack_size.x,attack_size.y)
	var fit:float = normal_visible_long / attack_long if attack_long > 0.001 else maxf(absf(_normal_image_scale.x),absf(_normal_image_scale.y))

	var sx:float = -fit if _normal_image_scale.x < 0.0 else fit
	var sy:float = -fit if _normal_image_scale.y < 0.0 else fit

	sprite.texture = attack_texture
	sprite.scale = Vector2(sx,sy)
	sprite.offset = attack_metrics.get("center_offset",Vector2.ZERO)
	sprite.position = _normal_image_position
	sprite.rotation = _normal_image_rotation
	sprite.skew = _normal_image_skew
	sprite.visible = true


func _texture_visible_metrics(texture:Texture2D) -> Dictionary:
	if texture == null:
		return {"size":Vector2.ONE,"center_offset":Vector2.ZERO}

	var texture_size:Vector2 = texture.get_size()
	var used_size:Vector2 = texture_size
	var center_offset:Vector2 = Vector2.ZERO
	var texture_image:Image = texture.get_image()
	if texture_image != null and not texture_image.is_empty():
		var used_rect:Rect2i = texture_image.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0:
			used_size = Vector2(used_rect.size)
			center_offset = texture_size * 0.5 - (Vector2(used_rect.position) + Vector2(used_rect.size) * 0.5)

	return {"size":used_size,"center_offset":center_offset}


func Die() -> void:
	_set_visual_state_local(VISUAL_NORMAL)
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)


# AI 通用威胁接口：鼓点触发时是以鼓手为中心的范围伤害/控制。
# 因为鼓点由物理碰撞触发，没有固定前摇；这里在目标进入最大鼓点半径时暴露潜在区域。
func get_ai_attack_threats(receiver:ball) -> Array:
	var result:Array = []
	if receiver == null or not is_instance_valid(receiver) or not _is_valid_enemy(receiver):
		return result
	var radius:float = maxf(maxf(beat_1_radius,beat_2_radius),maxf(beat_3_radius,beat_4_radius))
	if global_position.distance_to(receiver.global_position) > radius * 1.15:
		return result
	var next_beat:int = (_beat % 4) + 1
	var next_radius:float = _radius_for_beat(next_beat)
	var damage_amount:float = attack_damage(_damage_multiplier_for_beat(next_beat))
	result.append({
		"shape":"circle",
		"position":global_position,
		"radius":maxf(next_radius,1.0),
		"danger_in":0.0,
		"danger_duration":0.10,
		"damage":damage_amount,
		"control":1.0 if next_beat == 3 or next_beat == 4 else 0.0,
		"kind":"drum_beat",
		"source":self,
	})
	return result
