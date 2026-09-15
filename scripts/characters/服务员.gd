extends ball

# ============================================================
# 服务员
# - 技能：在离自己最近的一面地图墙上打开一扇向外开的门。
# - 门开启期间服务员保持在发动技能时的位置，且继续保留实体碰撞。
# - 其他角色可以从门口穿过地图墙。
# - 敌人确实从这扇门跨出地图后，会获得“自动回拉豁免”；
#   仍然保留 World 原本的出界倒计时 / 淘汰规则。
# ============================================================

const IMAGE_DIR:String = "res://Images/characters/人物/服务员"
const DOOR_OPEN_SFX:AudioStream = preload("res://audio/characters/服务员/开门.mp3")
const DOOR_CLOSE_SFX:AudioStream = preload("res://audio/characters/服务员/关门.mp3")

@export_category("服务员 - 外观（可留空，会自动找图片）")
@export var normal_texture:Texture2D
@export var opening_texture:Texture2D

@export_category("服务员 - 门")
# 只有中心距离地图墙不超过这个值时，状态机才允许进入开门技能。
# 默认 24px：角色碰撞半径约 7px，实际视觉上需要先走到墙边才能开门。
@export_range(8.0,64.0,1.0) var door_skill_wall_distance:float = 24.0
@export_range(12.0,120.0,1.0) var door_width:float = 38.0
@export_range(0.05,1.0,0.01) var door_open_animation:float = 0.28
@export_range(0.5,12.0,0.1) var door_hold_duration:float = 3.2
@export_range(0.05,1.0,0.01) var door_close_animation:float = 0.28
# 地图内侧提前多少距离开始临时忽略墙体，这样高速角色不会在门线前被 TileMap 截停。
@export_range(8.0,80.0,1.0) var door_inner_tunnel_depth:float = 28.0
# 地图外侧保持多久的“门通道”，保证角色完整穿出后再恢复普通墙碰撞。
@export_range(8.0,100.0,1.0) var door_outer_tunnel_depth:float = 46.0

@export_category("服务员 - 音效")
# 上传的开/关门录音整体电平较轻，默认略微提高，仍可在 Inspector 调整。
@export_range(-30.0,12.0,0.5) var door_open_sfx_volume_db:float = 5.0
@export_range(-30.0,12.0,0.5) var door_close_sfx_volume_db:float = 4.0
@export_range(100.0,3000.0,50.0) var door_sfx_max_distance:float = 900.0

var _door_channeling:bool = false
var _active_door_id:int = -1
var _default_texture:Texture2D = null


func _ready() -> void:
	Can_Attack = false
	Can_Skill = true
	super._ready()
	_auto_load_textures()
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_set_opening_visual(false)


# 不能只在 Skill() 里拒绝远距离开门：ball.get_next_state() 会在技能冷却完成后
# 每帧尝试进入 Skill，造成状态/音效反复触发。这里从状态机入口就限制为“墙边才能开门”。
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority():
		return -1
	if health <= 0 and Type != Ball_Type.Creature:
		if state != State.Die:
			return State.Die
		return -1
	if dizziness:
		return -1

	# V129：直接控制时统一交回 ball 的“只响应玩家鼠标、不自动起手”状态逻辑。
	# 本角色仍可在玩家点击后执行自己的 Attack()/Skill()，这里只阻止自定义 AI 冷却分支抢先出招。
	if is_player_controlled():
		return super.get_next_state(state)

	# 本脚本自定义了状态切换，未直接走父类入口；未开战时交回父类统一闸门处理。
	if not is_combat_runtime_active():
		return super.get_next_state(state)

	var offense_disabled:bool = is_damage_output_disabled()
	if offense_disabled:
		Attacking = false
		Using_Skill = false
	else:
		if Using_Skill and state != State.Skill:
			return State.Skill
		# 关键：冷却照常累计，但只有人在墙边时才允许真正进入技能。
		# 不像把 Can_Skill 临时设 false 那样把技能计时重置为 0。
		if (
			Can_Skill
			and not Using_Skill
			and state_machine.last_state_dis.Skill >= Skill_Cooling
			and _can_open_door_from_here()
		):
			return State.Skill

		if Attacking and state != State.Attack:
			return State.Attack
		if Can_Attack:
			if state_machine.last_state_dis.Attack >= Attack_Cooling:
				return State.Attack
		else:
			state_machine.last_state_dis.Attack = 0

	match state:
		State.Move:
			if Speed <= 0:
				return State.Stand
		State.Stand:
			if Speed > 0:
				return State.Move
		State.Attack:
			if not Attacking:
				return State.Stand
		State.Hurt:
			if hurting_timer.is_stopped():
				return State.Stand
		State.Skill:
			if not Using_Skill:
				return State.Stand
	return -1


func _can_open_door_from_here() -> bool:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return false

	var map_group_value:Variant = world.get("map_group")
	var map_name_value:Variant = world.get("now_choose_map")
	if not map_group_value is Dictionary:
		return false
	var maps:Dictionary = map_group_value
	var map_name:String = str(map_name_value)
	if not maps.has(map_name):
		return false
	var map_node:Variant = maps[map_name]
	if not map_node is TileMapLayer:
		return false

	var rect_value:Variant = world.call("return_map_world_rect",map_node)
	if not rect_value is Rect2:
		return false
	var map_rect:Rect2 = rect_value
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return false

	# 门只能从地图内部的墙边开启。从门逃出后不能在地图外继续凭空开新门。
	if not map_rect.has_point(global_position):
		return false

	var horizontal_wall_distance:float = minf(
		absf(global_position.x - map_rect.position.x),
		absf(map_rect.end.x - global_position.x)
	)
	var vertical_wall_distance:float = minf(
		absf(global_position.y - map_rect.position.y),
		absf(map_rect.end.y - global_position.y)
	)
	var wall_distance:float = minf(horizontal_wall_distance,vertical_wall_distance)
	return wall_distance <= maxf(door_skill_wall_distance,0.0)


func Skill() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		Using_Skill = false
		return
	if is_damage_output_disabled() or _door_channeling:
		Using_Skill = false
		return

	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("open_waiter_door"):
		Using_Skill = false
		return
	# 状态切换与真正执行技能之间可能隔一个物理帧；这里再次验证，
	# 避免角色刚好被击退离墙后仍远距离开门。
	if not _can_open_door_from_here():
		Using_Skill = false
		return

	Using_Skill = true
	_door_channeling = true
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_set_opening_visual(true)

	_active_door_id = int(world.call(
		"open_waiter_door",
		self,
		door_width,
		door_inner_tunnel_depth,
		door_outer_tunnel_depth,
		door_open_animation
	))

	if _active_door_id < 0:
		_finish_door_action()
		return

	# 门已经在服务员当前位置旁边创建；服务员本身不挪位置，也不关闭任何角色碰撞。
	_play_door_sfx_everywhere(true)

	await get_tree().create_timer(maxf(door_open_animation + door_hold_duration,0.05)).timeout
	if not is_instance_valid(self):
		return

	world = get_tree().current_scene
	if world != null and world.has_method("close_waiter_door"):
		# 关门动画开始的同一帧播放关门音效。
		_play_door_sfx_everywhere(false)
		world.call("close_waiter_door",_active_door_id,door_close_animation)

	await get_tree().create_timer(maxf(door_close_animation,0.05)).timeout
	if is_instance_valid(self):
		_finish_door_action()


func _play_door_sfx_everywhere(opening:bool) -> void:
	var point:Vector2 = global_position
	if multiplayer.has_multiplayer_peer():
		_rpc_play_door_sfx.rpc(opening,point)
	else:
		_rpc_play_door_sfx(opening,point)


@rpc("authority","call_local","reliable")
func _rpc_play_door_sfx(opening:bool,point:Vector2) -> void:
	var stream:AudioStream = DOOR_OPEN_SFX if opening else DOOR_CLOSE_SFX
	var volume:float = door_open_sfx_volume_db if opening else door_close_sfx_volume_db
	_spawn_local_positional_sfx(stream,point,volume)


func _spawn_local_positional_sfx(stream:AudioStream,point:Vector2,volume:float) -> void:
	if stream == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player:= AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = 1.0
	player.max_distance = maxf(door_sfx_max_distance,100.0)
	player.attenuation = 0.75
	world.add_child(player)
	player.global_position = point
	player.finished.connect(player.queue_free)
	player.play()


func tick_physics(state:State,delta:float) -> void:
	if _door_channeling:
		# ball 的 Skill 状态默认仍会调用 move(Speed)。这里和建筑工人的施工逻辑一致，
		# 强制按 Stand 处理并清掉击退，保证“门开着时服务员无法移动”。
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		super.tick_physics(State.Stand,delta)
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	super.tick_physics(state,delta)


func _finish_door_action() -> void:
	_door_channeling = false
	_active_door_id = -1
	_set_opening_visual(false)
	Using_Skill = false


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _try_load_texture([
			IMAGE_DIR + "/服务员_普通状态.png",
			IMAGE_DIR + "/服务员.png",
			IMAGE_DIR + "/服务员_正常.png",
			IMAGE_DIR + "/正常.png",
		])
	if opening_texture == null:
		opening_texture = _try_load_texture([
			IMAGE_DIR + "/服务员_弯腰请进状态.png",
			IMAGE_DIR + "/服务员_开门.png",
			IMAGE_DIR + "/开门.png",
		])


func _try_load_texture(paths:Array[String]) -> Texture2D:
	for path:String in paths:
		if ResourceLoader.exists(path):
			var loaded:Resource = ResourceLoader.load(path)
			if loaded is Texture2D:
				return loaded as Texture2D
	return null


func _set_opening_visual(opening:bool) -> void:
	if not image is Sprite2D:
		return
	var sprite:Sprite2D = image as Sprite2D
	if opening and opening_texture != null:
		sprite.texture = opening_texture
	elif normal_texture != null:
		sprite.texture = normal_texture
	elif _default_texture != null:
		sprite.texture = _default_texture

	# 两张人物图姿态不同，换图后重新套用项目现有的角色视觉自适应，
	# 保证普通/请进状态在战场上的人物尺寸一致。
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func Die() -> void:
	# 死亡时如果门仍开着，主动请求关门，避免留下永久缺口。
	var world:Node = get_tree().current_scene
	if _active_door_id >= 0 and world != null and world.has_method("close_waiter_door"):
		world.call("close_waiter_door",_active_door_id,0.12)
	_door_channeling = false
	_active_door_id = -1
	Using_Skill = false
	super.Die()
	# 服务员没有死亡动画或复活阶段，清理完门后直接离场。
	queue_free()
