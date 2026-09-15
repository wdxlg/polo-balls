extends ball

const BOTTLE_BREAK_AUDIO:AudioStream = preload("res://audio/characters/醉汉/酒瓶碎裂.mp3")

@export_range(0.2,10.0,0.1) var lifetime:float = 4.0
@export var bottle_glass_color:Color = Color(0.33,0.18,0.07,1.0)
@export var bottle_label_color:Color = Color(0.94,0.82,0.50,1.0)

@export_category("飞行翻滚")
@export_range(60.0,2160.0,10.0) var spin_degrees_per_second:float = 900.0
@export_range(0.0,1.0,0.01) var spin_randomness:float = 0.18
@export var randomize_spin_direction:bool = true

@export_category("撞墙碎裂音")
@export_range(-40.0,12.0,0.5) var wall_break_volume_db:float = -2.0
@export_range(0.5,2.0,0.01) var wall_break_pitch_scale:float = 1.0
@export_range(0.0,0.25,0.01) var wall_break_random_pitch:float = 0.05
@export_range(100.0,3000.0,10.0) var wall_break_max_distance:float = 1100.0

var _visual_root:Node2D = null
var _dying:bool = false
var _spin_speed:float = 0.0


func _ready() -> void:
	super._ready()

	# 酒瓶是攻击投射物，不是可以被攻击的单位。
	# 它继承 ball 后默认有 1 点生命和 Hurtbox；如果敌方 Hitbox 打到酒瓶，
	# 原先会把酒瓶自身的 1 点生命扣掉，并从隐藏血条位置弹出固定“-1”。
	# 关闭酒瓶自身 Hurtbox 的可检测性，同时屏蔽酒瓶自己的生命浮字。
	# 酒瓶自己的攻击 Hitbox、实体撞墙和命中后销毁逻辑不受影响。
	if health_bar != null:
		health_bar.suppress_floating_text = true
	if self_hurtbox != null:
		self_hurtbox.collision_layer = 0
		self_hurtbox.collision_mask = 0
		self_hurtbox.monitorable = false

	_build_bottle_visual()
	_roll_spin_speed()
	call_deferred("_start_lifetime")


func _process(delta:float) -> void:
	# 只转酒瓶的可视层，不转 CharacterBody2D 本体。
	# 因此飞行方向、碰撞盒和伤害判定保持稳定，画面上酒瓶持续翻滚。
	if _dying or _visual_root == null or not is_instance_valid(_visual_root):
		return
	_visual_root.rotation += _spin_speed * delta


func _roll_spin_speed() -> void:
	var random_scale:float = randf_range(
		maxf(1.0 - spin_randomness,0.05),
		1.0 + spin_randomness
	)
	var spin_sign:float = 1.0
	if randomize_spin_direction and randf() < 0.5:
		spin_sign = -1.0
	_spin_speed = deg_to_rad(spin_degrees_per_second * random_scale) * spin_sign


func _build_bottle_visual() -> void:
	if image != null:
		image.visible = false

	_visual_root = Node2D.new()
	_visual_root.name = "BottleVisual"
	_visual_root.z_index = 5
	graphics.add_child(_visual_root)

	# 酒瓶横着飞，瓶口朝本地 +X。BottleVisual 自己持续绕中心旋转，
	# CharacterBody2D 则只负责朝投掷方向移动。
	var glass := Polygon2D.new()
	glass.name = "Glass"
	glass.color = bottle_glass_color
	glass.polygon = PackedVector2Array([
		Vector2(-42,-22),
		Vector2(18,-22),
		Vector2(26,-13),
		Vector2(45,-10),
		Vector2(55,-7),
		Vector2(55,7),
		Vector2(45,10),
		Vector2(26,13),
		Vector2(18,22),
		Vector2(-42,22),
	])
	_visual_root.add_child(glass)

	var label := Polygon2D.new()
	label.name = "Label"
	label.color = bottle_label_color
	label.polygon = PackedVector2Array([
		Vector2(-24,-15),
		Vector2(2,-15),
		Vector2(2,15),
		Vector2(-24,15),
	])
	_visual_root.add_child(label)

	var cap := Polygon2D.new()
	cap.name = "Cap"
	cap.color = Color(0.18,0.10,0.04,1.0)
	cap.polygon = PackedVector2Array([
		Vector2(52,-9),
		Vector2(62,-9),
		Vector2(62,9),
		Vector2(52,9),
	])
	_visual_root.add_child(cap)


func _start_lifetime() -> void:
	await get_tree().create_timer(maxf(lifetime,0.2)).timeout
	if is_instance_valid(self) and state_machine.current_state != State.Die:
		state_machine.current_state = State.Die


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if _dying:
		return
	super(hurt)
	if is_multiplayer_authority():
		state_machine.current_state = State.Die


func when_collide(_speed:float,collision:KinematicCollision2D) -> void:
	if not is_multiplayer_authority() or _dying:
		return

	# 酒瓶撞到角色时仍由 Hitbox 的角色命中音效负责；只有撞到墙体/地图实体
	# 才播放这次新增的玻璃碎裂声，避免一次攻击叠两个碎裂音。
	var collider = collision.get_collider()
	if not collider is ball:
		_play_wall_break_audio.rpc(collision.get_position())

	state_machine.current_state = State.Die


@rpc("authority","call_local","unreliable")
func _play_wall_break_audio(impact_position:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null or BOTTLE_BREAK_AUDIO == null:
		return

	# 播放器挂在世界节点而不是酒瓶下面：酒瓶碰墙后会立刻销毁，
	# 独立播放器可以让不到 1 秒的碎裂尾音完整播完。
	var player := AudioStreamPlayer2D.new()
	player.name = "BottleWallBreakAudio"
	player.stream = BOTTLE_BREAK_AUDIO
	player.volume_db = wall_break_volume_db
	player.pitch_scale = wall_break_pitch_scale * randf_range(
		maxf(1.0 - wall_break_random_pitch,0.05),
		1.0 + wall_break_random_pitch
	)
	player.max_distance = wall_break_max_distance
	player.bus = &"GameplayRecord"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(player)
	player.global_position = impact_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func Die() -> void:
	if _dying:
		return
	_dying = true

	if _visual_root != null and is_instance_valid(_visual_root):
		var tween := create_tween()
		tween.tween_property(_visual_root,"modulate",Color(1,1,1,0),0.08)

	await get_tree().create_timer(0.09).timeout
	if is_instance_valid(self):
		Game.free_node(self)
