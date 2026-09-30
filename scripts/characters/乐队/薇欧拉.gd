extends ball

const PROPERTY_INDEX = preload("res://classes/property_index.gd")
const TEXT_PROJECTILE_SCRIPT = preload("res://scripts/effects/薇欧拉_文字弹.gd")
const FIRE_PROJECTILE_SCRIPT = preload("res://scripts/effects/薇欧拉_火焰弹.gd")
const KEYBOARD_SUPPORT_SCENE:PackedScene = preload("res://scenes/characters/人物/键盘侠.tscn")
const NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/薇欧拉(4).png")
const VICTORY_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/胜利.png")
const FIRE_POSE_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/火焰.png")
const VIOLA_PHOTO_SFX:AudioStream = preload("res://audio/characters/薇欧拉/拍照.mp3")
const VIOLA_RECORDER_SFX:AudioStream = preload("res://audio/characters/薇欧拉/开启录音器_[cut_0sec].mp3")
const VIOLA_LIGHT_LAUGH_VOICE:AudioStream = preload("res://audio/characters/薇欧拉/薇欧拉轻笑.MP3")
const VIOLA_FIRE_COUNTDOWN_VOICE:AudioStream = preload("res://audio/characters/薇欧拉/薇欧拉倒计时.MP3")
const VIOLA_FIRE_OPEN_VOICE:AudioStream = preload("res://audio/characters/薇欧拉/薇欧拉开.mp3")
const VIOLA_VICTORY_START_VOICE:AudioStream = preload("res://audio/characters/薇欧拉/薇欧拉笑开始.MP3")
const VIOLA_VICTORY_LOOP_VOICE:AudioStream = preload("res://audio/characters/薇欧拉/薇欧拉笑循环.MP3")
const COLLISION_DAMAGE_SFX:AudioStream = preload("res://audio/sfx/physics/balls_hit1.sfxr")
const WAR_BURN_TICK_SFX:AudioStream = preload("res://audio/status/debuff/烫伤.wav")

enum ViolaSfx {
	PHOTO,
	RECORDER,
	COLLISION_DAMAGE,
	LIGHT_LAUGH,
	FIRE_OPEN,
	BURN_TICK,
}

@export_category("薇欧拉 - 照相")
@export_range(0.2,8.0,0.05) var camera_cooldown:float = 2.1
@export_range(40.0,320.0,2.0) var camera_range:float = 150.0
@export_range(20.0,280.0,2.0) var camera_end_width:float = 125.0
@export_range(0.0,5.0,0.05) var camera_damage_multiplier:float = 0.65
@export_range(0.05,2.0,0.05) var camera_stun_duration:float = 0.34
@export_range(0.0,30.0,0.5) var camera_opinion_per_enemy:float = 5.0

@export_category("薇欧拉 - 舆论 / 录音")
@export_range(10.0,300.0,5.0) var opinion_max:float = 100.0
@export_range(0.5,8.0,0.1) var recording_duration:float = 3.0
@export_range(1.0,30.0,0.25) var recording_cooldown:float = 9.0
@export_range(0.0,0.95,0.05) var recording_damage_reduction:float = 0.75
@export_range(0.0,3.0,0.05) var recording_damage_to_opinion:float = 0.60
@export_range(1.0,30.0,0.5) var opinion_per_text:float = 3.0
@export_range(1,80,1) var text_projectile_cap:int = 42
@export_range(0.0,0.20,0.002) var text_spawn_delay_min:float = 0.010
@export_range(0.0,0.20,0.002) var text_spawn_delay_max:float = 0.028
@export_range(0.0,3.0,0.05) var text_damage_multiplier:float = 0.32
@export_range(100.0,1000.0,10.0) var text_projectile_speed:float = 470.0
@export_range(10.0,120.0,2.0) var text_spawn_outside_margin:float = 42.0
@export_range(0.15,1.5,0.05) var recording_keyboard_attack_cooldown:float = 0.45
@export_range(2.0,24.0,1.0) var recording_keyboard_edge_inset:float = 4.0
@export_range(18.0,160.0,1.0) var recording_keyboard_window_spawn_margin:float = 54.0
@export_range(70.0,360.0,5.0) var recording_keyboard_walk_speed:float = 145.0
@export_range(12.0,120.0,1.0) var recording_keyboard_exit_extra_distance:float = 28.0
@export_range(10.0,1500.0,10.0) var recording_keyboard_text_speed:float = 280.0
@export_range(0.0,20.0,0.25) var recording_keyboard_base_damage_per_character:float = 2.0

@export_category("薇欧拉 - 火焰终结")
@export_range(0.1,2.0,0.05) var fire_pose_duration:float = 0.72
@export_range(1,30,1) var text_hits_required_for_fire:int = 6
@export_range(0.05,0.95,0.01) var fire_target_health_ratio:float = 0.50
@export_range(0.5,30.0,0.25) var fire_cooldown:float = 8.0
@export_range(0.0,10.0,0.05) var fire_damage_multiplier:float = 4.0
@export_range(100.0,1200.0,10.0) var fire_projectile_speed:float = 620.0
@export_range(20.0,260.0,2.0) var fire_field_radius:float = 58.0
@export_range(0.5,12.0,0.25) var fire_field_duration:float = 5.0
@export_range(0.1,2.0,0.05) var fire_tick_interval:float = 0.55
@export_range(0.0,3.0,0.05) var fire_tick_damage_multiplier:float = 0.30
@export_range(0.2,10.0,0.1) var fire_burn_duration:float = 3.0
@export_range(0.1,2.0,0.05) var fire_burn_tick_interval:float = 0.5
@export_range(0.0,10.0,0.05) var fire_burn_tick_damage_multiplier:float = 1.0

@export_category("薇欧拉 - 胜利")
@export_range(0.05,1.0,0.05) var victory_scan_interval:float = 0.20

@export_category("薇欧拉 - 音量")
@export_range(0.0,12.0,0.5) var viola_audio_gain_db:float = 6.0

var public_opinion:float = 0.0
var _camera_cooldown_left:float = 0.0
var _record_cooldown_left:float = 1.8
var _recording_left:float = 0.0
var _recording:bool = false
var _fire_cooldown_left:float = 0.0
var _fire_charging:bool = false
var _fire_charge_left:float = 0.0
var _fire_target_ref:WeakRef = null
var _text_hit_counts:Dictionary = {}
var _network_effect_serial:int = 0
var _has_seen_enemy:bool = false
var _victory_pose:bool = false
var _victory_scan_elapsed:float = 0.0
var _fire_voice_player:AudioStreamPlayer2D = null
var _victory_voice_player:AudioStreamPlayer2D = null
var _victory_voice_started:bool = false
var _victory_voice_phase:int = 0
var _victory_intro_played_once:bool = false
var _record_indicator:Label = null
var _recording_keyboard_supports:Array[Dictionary] = []
var _recording_keyboard_serial:int = 0
var _current_recording_keyboard_serial:int = -1
var _recording_damage_attacker_ref:WeakRef = null
var _recording_saved_damage_reduction:float = 0.0
var _recording_damage_reduction_active:bool = false

@onready var _phone_sprite:Sprite2D = get_node_or_null("Graphics/手机") as Sprite2D
@onready var _recorder_sprite:Sprite2D = get_node_or_null("Graphics/录音器") as Sprite2D
@onready var _phone_display_timer:Timer = get_node_or_null("PhoneDisplayTimer") as Timer
@onready var _fire_pose_timer:Timer = get_node_or_null("FirePoseTimer") as Timer

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	_setup_character_visuals()
	_setup_record_indicator()
	_setup_voice_players()
	var damage_callable:=Callable(self,"_on_game_combat_damage_resolved")
	if Game.has_signal("combat_damage_resolved") and not Game.combat_damage_resolved.is_connected(damage_callable):
		Game.combat_damage_resolved.connect(damage_callable)
	if _phone_display_timer != null and not _phone_display_timer.timeout.is_connected(_hide_phone):
		_phone_display_timer.timeout.connect(_hide_phone)
	if _fire_pose_timer != null and not _fire_pose_timer.timeout.is_connected(_restore_after_fire_pose):
		_fire_pose_timer.timeout.connect(_restore_after_fire_pose)
	_update_opinion_ui()

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not is_multiplayer_authority():
		return
	if health <= 0:
		_begin_all_recording_keyboard_exits()
		return

	_update_recording_keyboard_supports(delta)

	_camera_cooldown_left = maxf(_camera_cooldown_left - delta,0.0)
	_record_cooldown_left = maxf(_record_cooldown_left - delta,0.0)
	_fire_cooldown_left = maxf(_fire_cooldown_left - delta,0.0)
	_victory_scan_elapsed += delta
	if not _victory_pose and _victory_scan_elapsed >= maxf(victory_scan_interval,0.05):
		_victory_scan_elapsed = 0.0
		_update_enemy_memory_and_victory()
	if _victory_pose:
		return

	if _fire_charging:
		_fire_charge_left = maxf(_fire_charge_left - delta,0.0)
		if _fire_charge_left <= 0.0:
			_finish_fire_charge()
		return

	if _recording:
		_recording_left = maxf(_recording_left - delta,0.0)
		if _recording_left <= 0.0:
			_finish_recording()
		return

	if is_player_controlled() or not is_combat_runtime_active():
		return

	var fire_target:ball = _select_fire_target()
	if fire_target != null and _fire_cooldown_left <= 0.0:
		_launch_fire_at(fire_target)
		return

	if _record_cooldown_left <= 0.0 and _has_any_enemy():
		_start_recording()
		return

	if _camera_cooldown_left <= 0.0:
		var target:ball = _find_nearest_enemy()
		if target != null:
			var aim:Vector2 = combat_target_position(target) - global_position
			_take_photo(aim.normalized() if aim.length_squared() > 0.000001 else Vector2.RIGHT)

func on_actual_health_damage_received(actual_health_damage:float,_health_before:float) -> void:
	# 火焰倒计时期间是完整无敌窗口。常规 hitbox / spatial / take_damage 会在入口被拒绝；
	# 这里再兜底恢复任何绕过公共伤害接口直接修改 health 的旧脚本伤害。
	if _fire_charging and actual_health_damage > 0.0:
		health = maxi(int(ceil(_health_before)),int(health))
		return
	if _recording and actual_health_damage > 0.0:
		_add_public_opinion(actual_health_damage * maxf(recording_damage_to_opinion,0.0))

func controlled_attack_action() -> void:
	if _recording or _fire_charging or _camera_cooldown_left > 0.0:
		return
	_take_photo(player_control_aim_direction(direction))

func controlled_skill_action() -> void:
	if _recording or _fire_charging or _record_cooldown_left > 0.0:
		return
	_start_recording()

func controlled_middle_action() -> void:
	if _recording or _fire_charging or _fire_cooldown_left > 0.0:
		return
	var target:ball = _select_fire_target()
	if target != null:
		_launch_fire_at(target)

func _take_photo(aim_direction:Vector2) -> void:
	if _recording or _fire_charging:
		return
	var dir:Vector2 = aim_direction.normalized() if aim_direction.length_squared() > 0.000001 else Vector2.RIGHT
	_camera_cooldown_left = maxf(camera_cooldown,0.05)
	_show_phone_for_attack(dir)
	var origin:Vector2 = _get_phone_photo_origin(dir)
	_play_viola_sfx_everywhere(ViolaSfx.PHOTO,origin,-2.0,1.0,950.0)
	var side:Vector2 = Vector2(-dir.y,dir.x)
	var tip_center:Vector2 = origin + dir * maxf(camera_range,1.0)
	var half_width:float = maxf(camera_end_width,2.0) * 0.5
	var a:Vector2 = origin
	var b:Vector2 = tip_center + side * half_width
	var c:Vector2 = tip_center - side * half_width
	var photo_contact_count:int = 0
	for target:ball in _all_valid_enemies():
		if not _point_in_triangle(target.global_position,a,b,c):
			continue
		# V414：照相三角实际扫到一个合法敌人，就计入同一个录音舆论池。
		# 舆论不再要求这次照相必须先成功扣到生命；伤害/眩晕本身仍按原 did_hit 结果处理。
		photo_contact_count += 1
		var did_hit:bool = target.receive_spatial_damage(
			attack_damage(camera_damage_multiplier),
			{"point":target.global_position,"source":self},
			false,
			false
		)
		if did_hit:
			_play_viola_sfx_everywhere(ViolaSfx.COLLISION_DAMAGE,target.global_position,-4.0,randf_range(0.96,1.04),900.0)
			target.apply_stun(maxf(camera_stun_duration,0.0))
	if photo_contact_count > 0:
		_add_public_opinion(camera_opinion_per_enemy * float(photo_contact_count))
	_spawn_photo_triangle_visual(a,b,c)

func _start_recording() -> void:
	if _recording or _fire_charging:
		return
	_recording = true
	_recording_left = maxf(recording_duration,0.1)
	_record_cooldown_left = maxf(recording_cooldown,0.1)
	_recording_damage_attacker_ref = null
	_apply_recording_damage_reduction()
	_set_recording_visual(true)
	_play_viola_sfx_everywhere(ViolaSfx.RECORDER,global_position,-3.0,1.0,850.0)
	_hide_phone()

func _finish_recording() -> void:
	if not _recording:
		return
	var recorded_target:ball = _recording_damage_attacker()
	_recording = false
	_recording_left = 0.0
	_restore_recording_damage_reduction()
	_set_recording_visual(false)
	_play_viola_sfx_everywhere(ViolaSfx.LIGHT_LAUGH,global_position,-1.0,1.0,900.0)
	# V411：录音期间只记录真正造成生命伤害的敌人；录音结束后才实例化键盘侠支援。
	if recorded_target != null:
		_spawn_recording_keyboard(recorded_target)
	_recording_damage_attacker_ref = null
	public_opinion = 0.0
	_update_opinion_ui()

func _apply_recording_damage_reduction() -> void:
	if _recording_damage_reduction_active:
		return
	_recording_saved_damage_reduction = float(default_properties.get("Damage_reduction",Damage_reduction))
	var reduced_value:float = clampf(recording_damage_reduction,0.0,0.95)
	Damage_reduction = reduced_value
	default_properties["Damage_reduction"] = reduced_value
	_recording_damage_reduction_active = true

func _restore_recording_damage_reduction() -> void:
	if not _recording_damage_reduction_active:
		return
	Damage_reduction = _recording_saved_damage_reduction
	default_properties["Damage_reduction"] = _recording_saved_damage_reduction
	_recording_damage_reduction_active = false

func _recording_damage_attacker() -> ball:
	if _recording_damage_attacker_ref == null:
		return null
	var raw:Variant = _recording_damage_attacker_ref.get_ref()
	if not is_instance_valid(raw) or not (raw is ball):
		return null
	var target:ball = raw as ball
	return target if _is_valid_enemy(target) else null

func _spawn_recording_keyboard(recorded_target:ball) -> void:
	if recorded_target == null or not _is_valid_enemy(recorded_target):
		return
	if not is_inside_tree() or KEYBOARD_SUPPORT_SCENE == null:
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var raw_support:Node = KEYBOARD_SUPPORT_SCENE.instantiate()
	if not (raw_support is ball):
		if raw_support != null:
			raw_support.queue_free()
		return
	var support:ball = raw_support as ball
	var map_rect:Rect2 = _get_current_map_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		support.queue_free()
		return

	# V410：完全照“寸头没事沙漠溜达猪”的地图外来客模式实例化真实键盘侠场景。
	# 它保留键盘侠场景自己的根scale/CharacterAutoFit，因此不再用自造70px Sprite放大显示。
	support.Team = Team
	support.Target_Enemy = recorded_target
	support.Nearest_Enemy = recorded_target
	support.Can_Attack = false
	support.Can_Skill = false
	support.Has_Collision_Damage = false
	support.set_meta(&"pig_outside_guest_exempt",true)
	support.set_meta(&"pig_outside_guest_hide_ui",true)
	support.set_meta(&"ignore_combat_targeting",true)
	support.set_meta(&"submission_allow_map_escape",true)
	support.set_meta(&"viola_recording_keyboard_support",true)
	support.set_meta(&"viola_recording_keyboard_owner_id",get_instance_id())
	support.set_process(false)
	support.set_physics_process(false)
	support.collision_layer = 0
	support.collision_mask = 0
	if "enemy_damage_gain_per_hit" in support:
		support.set("enemy_damage_gain_per_hit",0)
	if "attack_observer" in support:
		support.set("attack_observer",self)
	if "locked_attack_target" in support:
		support.set("locked_attack_target",recorded_target)
	if "text_speed" in support:
		support.set("text_speed",maxf(recording_keyboard_text_speed,10.0))
	if "damage_per_character_multiplier" in support:
		support.set("damage_per_character_multiplier",1.0)
	support.Damage = maxi(int(round(maxf(recording_keyboard_base_damage_per_character,0.0))),0)
	support.set_multiplayer_authority(get_multiplayer_authority(),true)

	scene_root.add_child(support,true)
	# _ready()/公共ball初始化完成后再锁一次处理开关，防止来客自己的AI抢位置。
	support.set_process(false)
	support.set_physics_process(false)
	if support.is_in_group("Ball"):
		support.remove_from_group("Ball")
	if support.state_machine != null:
		support.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if support.health_bar != null and is_instance_valid(support.health_bar):
		support.health_bar.visible = false
		support.health_bar.process_mode = Node.PROCESS_MODE_DISABLED
	# 比寸头猪来客再多一道保险：薇欧拉支援明确“不是单位”，所以连角色自身 Hitbox/Hurtbox Area 也关掉。
	if support.self_hitbox != null and is_instance_valid(support.self_hitbox):
		support.self_hitbox.collision_layer = 0
		support.self_hitbox.collision_mask = 0
		support.self_hitbox.monitoring = false
		support.self_hitbox.monitorable = false
	if support.self_hurtbox != null and is_instance_valid(support.self_hurtbox):
		support.self_hurtbox.collision_layer = 0
		support.self_hurtbox.collision_mask = 0
		support.self_hurtbox.monitoring = false
		support.self_hurtbox.monitorable = false
	support.z_as_relative = false
	support.z_index = 91

	_recording_keyboard_serial += 1
	_current_recording_keyboard_serial = -1
	var side:int = randi() % 4
	var route:Dictionary = _build_recording_keyboard_route(map_rect,_get_current_viewport_world_rect(),side,support)
	var spawn_position:Vector2 = route.get("start",global_position)
	var settle_position:Vector2 = route.get("stage",spawn_position)
	var exit_position:Vector2 = route.get("exit",spawn_position)
	var inward_dir:Vector2 = route.get("inward_dir",Vector2.RIGHT)
	if inward_dir.length_squared() <= 0.000001:
		inward_dir = Vector2.RIGHT
	inward_dir = inward_dir.normalized()
	support.global_position = spawn_position
	support.direction = inward_dir

	var enter_distance:float = spawn_position.distance_to(settle_position)
	_recording_keyboard_supports.append({
		"serial":_recording_keyboard_serial,
		"node":support,
		"target_ref":weakref(recorded_target),
		"phase":"enter",
		"settle_position":settle_position,
		"exit_position":exit_position,
		"side":side,
		"move_speed":maxf(recording_keyboard_walk_speed,70.0),
		"attack_left":0.0,
		"recording_open":false,
		"inward_dir":inward_dir,
		"enter_distance":enter_distance,
	})


func _recording_keyboard_visual_half_extent(support:ball,side:int) -> float:
	# 与寸头猪 _guest_visual_half_extent 一致：使用真实键盘侠场景最终 Image 的世界尺寸。
	var fallback:float = 24.0
	if support == null or not is_instance_valid(support) or not (support.image is Sprite2D):
		return fallback
	var sprite:Sprite2D = support.image as Sprite2D
	if sprite.texture == null:
		return fallback
	var tex_size:Vector2 = sprite.texture.get_size()
	var world_scale_x:float = sprite.global_transform.x.length()
	var world_scale_y:float = sprite.global_transform.y.length()
	var extent:float = tex_size.x * world_scale_x * 0.5 if side <= 1 else tex_size.y * world_scale_y * 0.5
	return clampf(extent,12.0,96.0)


func _build_recording_keyboard_route(map_rect:Rect2,viewport_rect:Rect2,side:int,support:ball) -> Dictionary:
	# 路线算法按寸头猪地图外来客：人物图片的“内缘”停在地图边界外，而不是把人物中心塞进地图。
	var visual_extent:float = _recording_keyboard_visual_half_extent(support,side)
	var edge_gap:float = maxf(recording_keyboard_edge_inset,2.0)
	var center_offset:float = visual_extent + edge_gap
	var spawn_margin:float = maxf(recording_keyboard_window_spawn_margin,18.0)
	var corner_pad:float = minf(32.0,minf(map_rect.size.x,map_rect.size.y) * 0.16)
	var min_x:float = map_rect.position.x + corner_pad
	var max_x:float = map_rect.end.x - corner_pad
	var min_y:float = map_rect.position.y + corner_pad
	var max_y:float = map_rect.end.y - corner_pad
	# 优先让来客出现在当前镜头能看到的地图边段；没有交集时退回地图全边段。
	var visible_min_x:float = maxf(min_x,viewport_rect.position.x + 18.0)
	var visible_max_x:float = minf(max_x,viewport_rect.end.x - 18.0)
	var visible_min_y:float = maxf(min_y,viewport_rect.position.y + 18.0)
	var visible_max_y:float = minf(max_y,viewport_rect.end.y - 18.0)
	if visible_min_x <= visible_max_x:
		min_x = visible_min_x
		max_x = visible_max_x
	if visible_min_y <= visible_max_y:
		min_y = visible_min_y
		max_y = visible_max_y
	if min_x > max_x:
		min_x = map_rect.get_center().x
		max_x = min_x
	if min_y > max_y:
		min_y = map_rect.get_center().y
		max_y = min_y

	var start:Vector2 = map_rect.get_center()
	var stage:Vector2 = map_rect.get_center()
	var outward:Vector2 = Vector2.RIGHT
	var inward:Vector2 = Vector2.LEFT
	match side:
		0:
			var y0:float = randf_range(min_y,max_y)
			outward = Vector2.LEFT
			inward = Vector2.RIGHT
			stage = Vector2(map_rect.position.x-center_offset,y0)
			start = stage + outward * spawn_margin
			start.x = minf(start.x,viewport_rect.position.x-visual_extent-12.0)
		1:
			var y1:float = randf_range(min_y,max_y)
			outward = Vector2.RIGHT
			inward = Vector2.LEFT
			stage = Vector2(map_rect.end.x+center_offset,y1)
			start = stage + outward * spawn_margin
			start.x = maxf(start.x,viewport_rect.end.x+visual_extent+12.0)
		2:
			var x2:float = randf_range(min_x,max_x)
			outward = Vector2.UP
			inward = Vector2.DOWN
			stage = Vector2(x2,map_rect.position.y-center_offset)
			start = stage + outward * spawn_margin
			start.y = minf(start.y,viewport_rect.position.y-visual_extent-12.0)
		_:
			var x3:float = randf_range(min_x,max_x)
			outward = Vector2.DOWN
			inward = Vector2.UP
			stage = Vector2(x3,map_rect.end.y+center_offset)
			start = stage + outward * spawn_margin
			start.y = maxf(start.y,viewport_rect.end.y+visual_extent+12.0)
	return {
		"start":start,
		"stage":stage,
		"exit":start + outward * maxf(recording_keyboard_exit_extra_distance,12.0),
		"inward_dir":inward,
	}


func _on_game_combat_damage_resolved(source:Node,target:Node,actual_health_damage:float,_target_health_before:float) -> void:
	if not is_multiplayer_authority() or not _recording or target != self or actual_health_damage <= 0.0:
		return
	if _recording_damage_attacker() != null:
		return
	var attacker:ball = _resolve_recording_damage_attacker(source)
	if attacker == null:
		return
	_recording_damage_attacker_ref = weakref(attacker)


func _resolve_recording_damage_attacker(source:Node) -> ball:
	if source == null or not is_instance_valid(source):
		return null
	if source is ball:
		var direct:ball = source as ball
		if _is_valid_enemy(direct):
			return direct
	var property_names:Array[String] = [
		"Master","master","source","Source","owner_ball","Owner","creator","shooter"
	]
	# V431 性能：按脚本缓存的属性名集合保持与 get_property_list() 相同的声明顺序，
	# 因此“第一个命中的持有者属性”结果不变。
	for property_name:String in PROPERTY_INDEX.names(source):
		if not property_name in property_names:
			continue
		var raw:Variant = source.get(property_name)
		if raw is WeakRef:
			raw = (raw as WeakRef).get_ref()
		if raw is ball and is_instance_valid(raw):
			var candidate:ball = raw as ball
			if _is_valid_enemy(candidate):
				return candidate
	var cursor:Node = source.get_parent()
	var depth:int = 0
	while cursor != null and depth < 5:
		if cursor is ball:
			var parent_ball:ball = cursor as ball
			if _is_valid_enemy(parent_ball):
				return parent_ball
		cursor = cursor.get_parent()
		depth += 1
	return null


func _finish_current_recording_keyboard_lock() -> void:
	var data:Dictionary = _find_recording_keyboard_support(_current_recording_keyboard_serial)
	_current_recording_keyboard_serial = -1
	if data.is_empty():
		return
	data["recording_open"] = false
	if _support_target(data) == null:
		_begin_recording_keyboard_exit(data)


func _find_recording_keyboard_support(serial:int) -> Dictionary:
	if serial < 0:
		return {}
	for data:Dictionary in _recording_keyboard_supports:
		if int(data.get("serial",-1)) == serial:
			return data
	return {}


func _support_target(data:Dictionary) -> ball:
	var ref_value:Variant = data.get("target_ref",null)
	if not (ref_value is WeakRef):
		return null
	var raw:Variant = (ref_value as WeakRef).get_ref()
	if not is_instance_valid(raw) or not (raw is ball):
		return null
	var target:ball = raw as ball
	if target == self or int(target.health) <= 0:
		return null
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return null
	if not Team.is_empty() and target.Team == Team:
		return null
	return target


func _update_recording_keyboard_supports(delta:float) -> void:
	if _recording_keyboard_supports.is_empty():
		return
	var runtime_active:bool = is_combat_runtime_active()
	for i:int in range(_recording_keyboard_supports.size()-1,-1,-1):
		var data:Dictionary = _recording_keyboard_supports[i]
		var node_value:Variant = data.get("node",null)
		if not is_instance_valid(node_value) or not (node_value is ball):
			_recording_keyboard_supports.remove_at(i)
			continue
		var support:ball = node_value as ball
		var phase:String = str(data.get("phase","active"))

		if phase == "exit":
			if not runtime_active:
				continue
			var exit_position:Vector2 = data.get("exit_position",support.global_position)
			var move_speed:float = maxf(float(data.get("move_speed",recording_keyboard_walk_speed)),70.0)
			support.direction = (exit_position-support.global_position).normalized() if support.global_position.distance_squared_to(exit_position) > 0.001 else support.direction
			support.global_position = support.global_position.move_toward(exit_position,move_speed*delta)
			if support.global_position.distance_to(exit_position) <= 1.0:
				support.queue_free()
				_recording_keyboard_supports.remove_at(i)
			continue

		if health <= 0 or _victory_pose:
			_begin_recording_keyboard_exit(data)
			continue

		if phase == "enter":
			if not runtime_active:
				continue
			var settle_position:Vector2 = data.get("settle_position",support.global_position)
			var move_speed:float = maxf(float(data.get("move_speed",recording_keyboard_walk_speed)),70.0)
			var inward:Vector2 = settle_position-support.global_position
			if inward.length_squared() > 0.001:
				support.direction = inward.normalized()
			support.global_position = support.global_position.move_toward(settle_position,move_speed*delta)
			if support.global_position.distance_to(settle_position) <= 1.0:
				support.global_position = settle_position
				data["phase"] = "active"
			continue

		var target:ball = _support_target(data)
		if target == null:
			if not bool(data.get("recording_open",false)) or data.get("target_ref",null) != null:
				_begin_recording_keyboard_exit(data)
			continue

		if not runtime_active:
			continue
		support.Target_Enemy = target
		support.Nearest_Enemy = target
		var aim:Vector2 = target.global_position-support.global_position
		if aim.length_squared() > 0.001:
			support.direction = aim.normalized()
		var attack_left:float = maxf(float(data.get("attack_left",0.0))-delta,0.0)
		data["attack_left"] = attack_left
		if attack_left <= 0.0:
			_fire_recording_keyboard_support(data,target)
			data["attack_left"] = maxf(recording_keyboard_attack_cooldown,0.05)


func _begin_recording_keyboard_exit(data:Dictionary) -> void:
	if data.is_empty() or str(data.get("phase","")) == "exit":
		return
	var node_value:Variant = data.get("node",null)
	data["phase"] = "exit"
	data["recording_open"] = false
	if not is_instance_valid(node_value) or not (node_value is ball):
		return
	var support:ball = node_value as ball
	support.Can_Attack = false
	support.Target_Enemy = null
	support.Nearest_Enemy = null
	if "locked_attack_target" in support:
		support.set("locked_attack_target",null)
	data["move_speed"] = maxf(recording_keyboard_walk_speed,70.0)


func _begin_all_recording_keyboard_exits() -> void:
	for data:Dictionary in _recording_keyboard_supports:
		_begin_recording_keyboard_exit(data)


func _detach_all_recording_keyboard_exits() -> void:
	# 薇欧拉离树后不再 tick；像寸头猪的来客一样，让完整键盘侠实例自行 Tween 到地图外再释放。
	for data:Dictionary in _recording_keyboard_supports:
		var node_value:Variant = data.get("node",null)
		if not is_instance_valid(node_value) or not (node_value is ball):
			continue
		var support:ball = node_value as ball
		var exit_position:Vector2 = data.get("exit_position",support.global_position)
		var distance:float = support.global_position.distance_to(exit_position)
		var duration:float = clampf(distance/maxf(recording_keyboard_walk_speed,70.0),0.18,1.75)
		var tween:Tween = support.create_tween()
		tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
		tween.tween_property(support,"global_position",exit_position,duration)
		tween.tween_callback(support.queue_free)
	_recording_keyboard_supports.clear()
	_current_recording_keyboard_serial = -1


func _fire_recording_keyboard_support(data:Dictionary,target:ball) -> void:
	var node_value:Variant = data.get("node",null)
	if not is_instance_valid(node_value) or not (node_value is ball):
		return
	var support:ball = node_value as ball
	if target == null or not _is_valid_enemy(target):
		return

	# V412：文字必须由真实键盘侠本体自己射出。
	# 不再在目标附近的地图墙内侧伪造 safe_entry；直接调用键盘侠脚本的原生文字生成入口，
	# 出生点使用键盘侠自己的 global_position + spawn_offset / jitter。
	if not support.has_method("fire_viola_support_text"):
		return
	var map_rect:Rect2 = _get_current_map_rect()
	support.Target_Enemy = target
	support.Nearest_Enemy = target
	if "locked_attack_target" in support:
		support.set("locked_attack_target",target)
	var aim:Vector2 = target.global_position-support.global_position
	if aim.length_squared() > 0.000001:
		support.direction = aim.normalized()
	support.call("fire_viola_support_text",target,self,map_rect)


func _get_current_viewport_world_rect() -> Rect2:
	var viewport:=get_viewport()
	if viewport == null:
		return _get_current_map_rect()
	var visible:Rect2 = viewport.get_visible_rect()
	var inv:Transform2D = get_canvas_transform().affine_inverse()
	var p0:Vector2 = inv * visible.position
	var p1:Vector2 = inv * visible.end
	return Rect2(Vector2(minf(p0.x,p1.x),minf(p0.y,p1.y)),Vector2(absf(p1.x-p0.x),absf(p1.y-p0.y)))


func _clear_recording_keyboard() -> void:
	# 兼容旧调用点：V410 后完整键盘侠来客也统一走地图外离场，不瞬删。
	_begin_all_recording_keyboard_exits()


func _spawn_text_barrage(count:int) -> void:
	var enemies:Array[ball] = _all_valid_enemies()
	if enemies.is_empty():
		return
	var delay_min:float = maxf(text_spawn_delay_min,0.0)
	var delay_max:float = maxf(text_spawn_delay_max,delay_min)
	var accumulated_delay:float = 0.0
	for i:int in range(count):
		var target:ball = enemies[i % enemies.size()]
		if target == null or not is_instance_valid(target):
			continue
		accumulated_delay += randf_range(delay_min,delay_max)
		var timer:SceneTreeTimer = get_tree().create_timer(accumulated_delay,false)
		timer.timeout.connect(_spawn_one_text_projectile.bind(weakref(target),i),CONNECT_ONE_SHOT)

func _spawn_one_text_projectile(target_ref_value:WeakRef,index:int) -> void:
	if not is_instance_valid(self) or health <= 0 or _victory_pose:
		return
	var target:ball = null
	if target_ref_value != null:
		var raw_target:Variant = target_ref_value.get_ref()
		if raw_target is ball and _is_valid_enemy(raw_target as ball):
			target = raw_target as ball
	if target == null:
		target = _find_nearest_enemy()
	if target == null:
		return
	var map_rect:Rect2 = _get_current_map_rect()
	var start_position:Vector2 = _random_outside_map_position(map_rect,index)
	var config:Dictionary = {
		"damage":attack_damage(text_damage_multiplier),
		"speed":text_projectile_speed,
		"word":_random_text_word(),
	}
	_network_effect_serial += 1
	var serial:int = _network_effect_serial
	_spawn_text_projectile_local(serial,target,start_position,config)
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_rpc_spawn_text_projectile.rpc(serial,target.get_path(),start_position,config)


@rpc("authority","call_remote","unreliable")
func _rpc_spawn_text_projectile(serial:int,target_path:NodePath,start_position:Vector2,config:Dictionary) -> void:
	var raw_target:Node = get_node_or_null(target_path)
	if raw_target is ball:
		_spawn_text_projectile_local(serial,raw_target as ball,start_position,config)


func _spawn_text_projectile_local(serial:int,target:ball,start_position:Vector2,config:Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var projectile:Node2D = TEXT_PROJECTILE_SCRIPT.new() as Node2D
	if projectile == null:
		return
	projectile.name = "薇欧拉_文字_%d" % serial
	get_tree().current_scene.add_child(projectile,true)
	projectile.call("setup",self,target,start_position,config)

func notify_viola_text_hit(target:Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_play_viola_sfx_everywhere(ViolaSfx.COLLISION_DAMAGE,target.global_position,-5.0,randf_range(0.96,1.04),900.0)
	var id:int = target.get_instance_id()
	_text_hit_counts[id] = int(_text_hit_counts.get(id,0)) + 1
	_cleanup_text_hit_counts()

func _select_fire_target() -> ball:
	_cleanup_text_hit_counts()
	var best:ball = null
	var best_hits:int = -1
	for key:Variant in _text_hit_counts.keys():
		var id:int = int(key)
		if not is_instance_id_valid(id):
			continue
		var raw:Variant = instance_from_id(id)
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _is_valid_enemy(target):
			continue
		if float(target.health) > float(target.Max_health) * clampf(fire_target_health_ratio,0.05,0.95):
			continue
		var hits:int = int(_text_hit_counts.get(id,0))
		if hits < maxi(text_hits_required_for_fire,1):
			continue
		if hits > best_hits:
			best_hits = hits
			best = target
	return best

func _launch_fire_at(target:ball) -> void:
	if target == null or not is_instance_valid(target) or _recording or _fire_charging:
		return
	_fire_charging = true
	_fire_charge_left = _fire_countdown_duration()
	_fire_target_ref = weakref(target)
	_show_fire_pose()
	_play_fire_countdown_local()
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_begin_fire_charge.rpc(_fire_charge_left)


func _fire_countdown_duration() -> float:
	if VIOLA_FIRE_COUNTDOWN_VOICE != null:
		var voice_length:float = VIOLA_FIRE_COUNTDOWN_VOICE.get_length()
		if voice_length > 0.05:
			return voice_length
	return 8.673


func _finish_fire_charge() -> void:
	if not _fire_charging:
		return
	_fire_charging = false
	_fire_charge_left = 0.0
	_stop_fire_countdown_local()

	var target:ball = _resolve_charged_fire_target()
	_fire_target_ref = null
	if target == null:
		_restore_after_fire_pose()
		if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
			_remote_cancel_fire_charge.rpc()
		return

	_fire_cooldown_left = maxf(fire_cooldown,0.1)
	_text_hit_counts[target.get_instance_id()] = 0
	_play_fire_open_local()
	_spawn_fire_projectile(target)
	_start_post_fire_pose_timer()
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_release_fire_attack.rpc()


func _resolve_charged_fire_target() -> ball:
	if _fire_target_ref != null:
		var raw_target:Variant = _fire_target_ref.get_ref()
		if raw_target is ball and _is_valid_enemy(raw_target as ball):
			return raw_target as ball
	return _select_fire_target()


func _spawn_fire_projectile(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var config:Dictionary = {
		"damage":attack_damage(fire_damage_multiplier),
		"speed":fire_projectile_speed,
		"explosion_radius":fire_field_radius,
		"burn_duration":fire_burn_duration,
		"burn_tick_interval":fire_burn_tick_interval,
		"burn_tick_damage":attack_damage(fire_burn_tick_damage_multiplier),
		"fire_field":{
			"radius":fire_field_radius,
			"duration":fire_field_duration,
			"tick_interval":fire_tick_interval,
			"tick_damage":attack_damage(fire_tick_damage_multiplier),
			"burn_duration":fire_burn_duration,
			"burn_tick_interval":fire_burn_tick_interval,
			"burn_tick_damage":attack_damage(fire_burn_tick_damage_multiplier),
		},
	}
	_network_effect_serial += 1
	var serial:int = _network_effect_serial
	var start_position:Vector2 = global_position
	_spawn_fire_projectile_local(serial,target,start_position,config)
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_rpc_spawn_fire_projectile.rpc(serial,target.get_path(),start_position,config)


@rpc("authority","call_remote","reliable")
func _rpc_spawn_fire_projectile(serial:int,target_path:NodePath,start_position:Vector2,config:Dictionary) -> void:
	var raw_target:Node = get_node_or_null(target_path)
	if raw_target is ball:
		_spawn_fire_projectile_local(serial,raw_target as ball,start_position,config)


func _spawn_fire_projectile_local(serial:int,target:ball,start_position:Vector2,config:Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var projectile:Node2D = FIRE_PROJECTILE_SCRIPT.new() as Node2D
	if projectile == null:
		return
	projectile.name = "薇欧拉_火焰_%d" % serial
	get_tree().current_scene.add_child(projectile,true)
	projectile.call("setup",self,target,start_position,config)


func _show_fire_pose() -> void:
	if _victory_pose:
		return
	_hide_phone()
	_set_recording_visual(false)
	if _fire_pose_timer != null:
		_fire_pose_timer.stop()
	if image != null and is_instance_valid(image):
		image.visible = true
		image.texture = FIRE_POSE_TEXTURE
	_refit_character_visual()


func _start_post_fire_pose_timer() -> void:
	if _victory_pose:
		return
	if _fire_pose_timer != null:
		_fire_pose_timer.wait_time = maxf(fire_pose_duration,0.1)
		_fire_pose_timer.start()


func _restore_after_fire_pose() -> void:
	if _victory_pose or _fire_charging:
		return
	if image != null and is_instance_valid(image):
		image.visible = true
		image.texture = NORMAL_TEXTURE
	_refit_character_visual()


func _play_fire_open_local() -> void:
	_rpc_play_viola_sfx(ViolaSfx.FIRE_OPEN,global_position,0.0,1.0,1000.0)


func _play_fire_countdown_local() -> void:
	if _fire_voice_player == null or not is_instance_valid(_fire_voice_player):
		return
	_fire_voice_player.stop()
	_fire_voice_player.stream = VIOLA_FIRE_COUNTDOWN_VOICE
	_fire_voice_player.play()


func _stop_fire_countdown_local() -> void:
	if _fire_voice_player != null and is_instance_valid(_fire_voice_player):
		_fire_voice_player.stop()


@rpc("authority","call_remote","reliable")
func _remote_begin_fire_charge(duration:float) -> void:
	if _victory_pose:
		return
	_fire_charging = true
	_fire_charge_left = maxf(duration,0.1)
	_show_fire_pose()
	_play_fire_countdown_local()


@rpc("authority","call_remote","reliable")
func _remote_release_fire_attack() -> void:
	_fire_charging = false
	_fire_charge_left = 0.0
	_fire_target_ref = null
	_stop_fire_countdown_local()
	_play_fire_open_local()
	_start_post_fire_pose_timer()


@rpc("authority","call_remote","reliable")
func _remote_cancel_fire_charge() -> void:
	_fire_charging = false
	_fire_charge_left = 0.0
	_fire_target_ref = null
	_stop_fire_countdown_local()
	_restore_after_fire_pose()


# 火焰倒计时期间仍为完整无敌。录音的75%减伤由 Damage_reduction + default_properties 同步实现，
# 避免公共 continue_attack() 在下一物理帧把录音减伤恢复掉。
func can_receive_hit_contact(_incoming_hit:hitbox,_contact_hurtbox:hurtbox) -> bool:
	return not _fire_charging


func can_receive_hit_from(_incoming_hit:hitbox) -> bool:
	return not _fire_charging


func receive_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block:bool = false,
	source:Node = null
) -> bool:
	if _fire_charging:
		return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)


func receive_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block:bool = false,
	raw_health:bool = false
) -> bool:
	if _fire_charging:
		return false
	var incoming_damage:float = damage
	# raw_health 会绕过 ball.take_damage()，因此录音期间需要在这里单独应用同样的75%减伤。
	if _recording and raw_health:
		incoming_damage *= 1.0 - clampf(recording_damage_reduction,0.0,0.95)
	return super.receive_spatial_damage(incoming_damage,damage_space,ignore_block,raw_health)


func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _fire_charging:
		return
	super.take_damage(damage,ignore_block)


func _add_public_opinion(amount:float) -> void:
	if amount <= 0.0:
		return
	public_opinion = clampf(public_opinion + amount,0.0,maxf(opinion_max,1.0))
	_update_opinion_ui()

func _update_opinion_ui() -> void:
	# V171：删除薇欧拉额外状态文字。舆论仍作为内部玩法数值保留，唯一保留文字为录音器下的 ● REC。
	pass

func _cleanup_text_hit_counts() -> void:
	var remove_keys:Array = []
	for key:Variant in _text_hit_counts.keys():
		var id:int = int(key)
		if not is_instance_id_valid(id):
			remove_keys.append(key)
			continue
		var raw:Variant = instance_from_id(id)
		if not raw is ball or not is_instance_valid(raw) or int((raw as ball).health) <= 0:
			remove_keys.append(key)
	for key:Variant in remove_keys:
		_text_hit_counts.erase(key)

func _point_in_triangle(p:Vector2,a:Vector2,b:Vector2,c:Vector2) -> bool:
	var d1:float = _triangle_sign(p,a,b)
	var d2:float = _triangle_sign(p,b,c)
	var d3:float = _triangle_sign(p,c,a)
	var has_neg:bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos:bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_neg and has_pos)

func _triangle_sign(p1:Vector2,p2:Vector2,p3:Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)

func _spawn_photo_triangle_visual(a:Vector2,b:Vector2,c:Vector2) -> void:
	var poly := Polygon2D.new()
	poly.name = "ViolaPhotoFlash"
	poly.polygon = PackedVector2Array([to_local(a),to_local(b),to_local(c)])
	poly.color = Color(1.0,0.92,1.0,0.20)
	poly.z_index = 38
	add_child(poly)
	var tween:Tween = poly.create_tween()
	tween.tween_property(poly,"modulate:a",0.0,0.16)
	tween.tween_callback(poly.queue_free)

func _get_current_map_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("return_map_world_rect"):
		var map_group_value:Variant = world.get("map_group")
		var now_map_value:Variant = world.get("now_choose_map")
		if map_group_value is Dictionary:
			var group:Dictionary = map_group_value as Dictionary
			var key:String = str(now_map_value)
			if group.has(key) and group[key] is TileMapLayer:
				var rect_value:Variant = world.call("return_map_world_rect",group[key])
				if rect_value is Rect2:
					return rect_value
	# 兜底只用于极端缺地图环境；正常 World 会走上面真实地图 Rect。
	return Rect2(global_position - Vector2(420.0,260.0),Vector2(840.0,520.0))

func _random_outside_map_position(map_rect:Rect2,index:int) -> Vector2:
	var margin:float = maxf(text_spawn_outside_margin,10.0)
	var edge:int = posmod(index + randi(),4)
	match edge:
		0:
			return Vector2(map_rect.position.x - margin,randf_range(map_rect.position.y,map_rect.end.y))
		1:
			return Vector2(map_rect.end.x + margin,randf_range(map_rect.position.y,map_rect.end.y))
		2:
			return Vector2(randf_range(map_rect.position.x,map_rect.end.x),map_rect.position.y - margin)
		_:
			return Vector2(randf_range(map_rect.position.x,map_rect.end.x),map_rect.end.y + margin)

func _random_text_word() -> String:
	var locale:String = TranslationServer.get_locale().to_lower()
	var words:Array[String]
	if locale.begins_with("zh"):
		words = ["质疑","争议","曝光","回应","热搜","真的吗","为什么","录音"]
	else:
		words = ["TRENDING","EXPOSED","WHY?","RESPONSE","HOT","REALLY?","AUDIO","RUMOR"]
	return words[randi() % words.size()]

func _play_viola_sfx_everywhere(kind:int,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_viola_sfx.rpc(kind,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_viola_sfx(kind,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_viola_sfx(kind:int,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	var stream:AudioStream = null
	match kind:
		ViolaSfx.PHOTO:
			stream = VIOLA_PHOTO_SFX
		ViolaSfx.RECORDER:
			stream = VIOLA_RECORDER_SFX
		ViolaSfx.COLLISION_DAMAGE:
			stream = COLLISION_DAMAGE_SFX
		ViolaSfx.LIGHT_LAUGH:
			stream = VIOLA_LIGHT_LAUGH_VOICE
		ViolaSfx.FIRE_OPEN:
			stream = VIOLA_FIRE_OPEN_VOICE
		ViolaSfx.BURN_TICK:
			stream = WAR_BURN_TICK_SFX
		_:
			return
	if stream == null or not is_inside_tree():
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "ViolaSFX"
	player.stream = stream
	player.volume_db = clampf(volume_db + maxf(viola_audio_gain_db,0.0),-40.0,12.0)
	player.pitch_scale = clampf(pitch,0.75,1.30)
	player.max_distance = maxf(max_distance,50.0)
	player.attenuation = 0.55
	player.max_polyphony = 8
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	scene_root.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


# V183：完全复用战争女神_灼烧.gd 的声音回调协议。
# 灼烧状态只认 source.play_war_burn_tick_sfx()，因此薇欧拉实现同名接口即可获得相同烫伤音效。
func play_war_burn_tick_sfx(position_value:Vector2) -> void:
	_play_viola_sfx_everywhere(ViolaSfx.BURN_TICK,position_value,1.0,randf_range(0.97,1.04),1100.0)


func _setup_voice_players() -> void:
	_fire_voice_player = _create_viola_voice_player("ViolaFireVoice")
	_victory_voice_player = _create_viola_voice_player("ViolaVictoryVoice")
	if _fire_voice_player != null and not _fire_voice_player.finished.is_connected(_on_fire_countdown_voice_finished):
		_fire_voice_player.finished.connect(_on_fire_countdown_voice_finished)
	if _victory_voice_player != null and not _victory_voice_player.finished.is_connected(_on_victory_voice_finished):
		_victory_voice_player.finished.connect(_on_victory_voice_finished)


func _create_viola_voice_player(node_name:String) -> AudioStreamPlayer2D:
	var player:=AudioStreamPlayer2D.new()
	player.name = node_name
	player.max_distance = 1100.0
	player.attenuation = 0.45
	player.volume_db = clampf(maxf(viola_audio_gain_db,0.0),-40.0,12.0)
	player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	return player


func _on_fire_countdown_voice_finished() -> void:
	if not is_multiplayer_authority() or not _fire_charging or _victory_pose:
		return
	_finish_fire_charge()


func _start_victory_voice_sequence() -> void:
	if _victory_voice_started or not _victory_pose:
		return
	if _victory_voice_player == null or not is_instance_valid(_victory_voice_player):
		return
	_victory_voice_started = true
	_victory_voice_player.stop()
	# V171：同一个薇欧拉实例一生只允许播放一次“笑开始”。即使胜利视觉/RPC 被重复设置，
	# 后续也只能直接进入“笑循环”，彻底避免胜利开场笑被再次触发。
	if not _victory_intro_played_once:
		_victory_intro_played_once = true
		_victory_voice_phase = 1
		var intro_stream:AudioStream = VIOLA_VICTORY_START_VOICE.duplicate() as AudioStream
		if intro_stream is AudioStreamMP3:
			(intro_stream as AudioStreamMP3).loop = false
		_victory_voice_player.stream = intro_stream
		_victory_voice_player.play()
	else:
		_start_victory_loop_local()


func _on_victory_voice_finished() -> void:
	if not _victory_pose or not _victory_voice_started or _victory_voice_phase != 1:
		return
	_start_victory_loop_local()


func _start_victory_loop_local() -> void:
	if _victory_voice_player == null or not is_instance_valid(_victory_voice_player):
		return
	_victory_voice_phase = 2
	var loop_stream:AudioStream = VIOLA_VICTORY_LOOP_VOICE.duplicate() as AudioStream
	if loop_stream is AudioStreamMP3:
		(loop_stream as AudioStreamMP3).loop = true
	_victory_voice_player.stream = loop_stream
	_victory_voice_player.play()


func _stop_victory_voice_sequence() -> void:
	_victory_voice_started = false
	_victory_voice_phase = 0
	# 不重置 _victory_intro_played_once：本实例后续若再次收到胜利视觉同步，只能继续循环段。
	if _victory_voice_player != null and is_instance_valid(_victory_voice_player):
		_victory_voice_player.stop()

func _all_valid_enemies() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and _is_valid_enemy(node as ball):
			result.append(node as ball)
	return result

func _has_any_enemy() -> bool:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and _is_valid_enemy(node as ball):
			return true
	return false

func _find_nearest_enemy() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for target:ball in _all_valid_enemies():
		var d:float = global_position.distance_squared_to(target.global_position)
		if d < nearest_distance_sq:
			nearest_distance_sq = d
			nearest = target
	return nearest

func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Team.is_empty() and target.Team == Team:
		return false
	return true

func _setup_character_visuals() -> void:
	if image != null and is_instance_valid(image):
		image.visible = true
		image.texture = NORMAL_TEXTURE
	if _phone_sprite != null:
		_phone_sprite.visible = false
	if _recorder_sprite != null:
		_recorder_sprite.visible = false
	if _fire_pose_timer != null:
		_fire_pose_timer.stop()
	_refit_character_visual()

func _refit_character_visual() -> void:
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")

func _setup_record_indicator() -> void:
	if _record_indicator != null and is_instance_valid(_record_indicator):
		return
	var graphics:Node = get_node_or_null("Graphics")
	if graphics == null or _recorder_sprite == null or not is_instance_valid(_recorder_sprite):
		return
	_record_indicator = Label.new()
	_record_indicator.name = "RECIndicator"
	_record_indicator.text = "● REC"
	_record_indicator.size = Vector2(180.0,64.0)
	_record_indicator.position = _recorder_sprite.position + Vector2(-90.0,38.0)
	_record_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_record_indicator.add_theme_font_size_override("font_size",54)
	_record_indicator.add_theme_color_override("font_color",Color(1.0,0.03,0.05,1.0))
	_record_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_record_indicator.z_index = 8
	_record_indicator.visible = false
	graphics.add_child(_record_indicator)


func _set_recording_visual(active:bool) -> void:
	if _recorder_sprite != null and is_instance_valid(_recorder_sprite):
		_recorder_sprite.visible = active
	if _record_indicator != null and is_instance_valid(_record_indicator):
		_record_indicator.position = _recorder_sprite.position + Vector2(-90.0,38.0) if _recorder_sprite != null else _record_indicator.position
		_record_indicator.visible = active


func _get_phone_photo_origin(fallback_direction:Vector2) -> Vector2:
	# V169：拍照三角形与快门音从“手机”Sprite 的实际世界位置发出，
	# 不再从薇欧拉角色根节点中心发出。
	if _phone_sprite != null and is_instance_valid(_phone_sprite) and _phone_sprite.visible:
		return _phone_sprite.global_position
	var dir:Vector2 = fallback_direction.normalized() if fallback_direction.length_squared() > 0.000001 else Vector2.RIGHT
	return global_position + dir * 6.0


func _show_phone_for_attack(aim_direction:Vector2) -> void:
	if _phone_sprite == null or not is_instance_valid(_phone_sprite):
		return
	var side:float = -1.0 if aim_direction.x < -0.05 else 1.0
	_phone_sprite.position = Vector2(88.0 * side,-10.0)
	_phone_sprite.flip_h = side < 0.0
	_phone_sprite.visible = true
	if _phone_display_timer != null:
		_phone_display_timer.start()

func _hide_phone() -> void:
	if _phone_sprite != null and is_instance_valid(_phone_sprite):
		_phone_sprite.visible = false

func _update_enemy_memory_and_victory() -> void:
	if not is_multiplayer_authority() or health <= 0 or _victory_pose:
		return
	if _has_any_enemy():
		_has_seen_enemy = true
		return
	if _has_seen_enemy:
		_enter_victory_pose()

func _enter_victory_pose() -> void:
	if _victory_pose:
		return
	_victory_pose = true
	_recording = false
	_recording_left = 0.0
	_recording_damage_attacker_ref = null
	_restore_recording_damage_reduction()
	_fire_charging = false
	_fire_charge_left = 0.0
	_fire_target_ref = null
	_stop_fire_countdown_local()
	Attacking = false
	Using_Skill = false
	velocity = Vector2.ZERO
	_hide_phone()
	_set_recording_visual(false)
	_begin_all_recording_keyboard_exits()
	if _fire_pose_timer != null:
		_fire_pose_timer.stop()
	_set_victory_visual(true)
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_set_victory_visual.rpc(true)

func _set_victory_visual(active:bool) -> void:
	_victory_pose = active
	if image != null and is_instance_valid(image):
		image.visible = true
		image.texture = VICTORY_TEXTURE if active else NORMAL_TEXTURE
	_refit_character_visual()
	if active:
		_start_victory_voice_sequence()
	else:
		_stop_victory_voice_sequence()

@rpc("authority","call_remote","reliable")
func _remote_set_victory_visual(active:bool) -> void:
	if active:
		_recording = false
		_recording_damage_attacker_ref = null
		_restore_recording_damage_reduction()
		_fire_charging = false
		_fire_charge_left = 0.0
		_fire_target_ref = null
		_stop_fire_countdown_local()
		_hide_phone()
		_set_recording_visual(false)
		_clear_recording_keyboard()
	_set_victory_visual(active)



func _exit_tree() -> void:
	_restore_recording_damage_reduction()
	_recording_damage_attacker_ref = null
	_detach_all_recording_keyboard_exits()
