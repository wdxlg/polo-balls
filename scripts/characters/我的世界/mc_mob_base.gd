extends ball

const MC_NATIVE_ANIMATION = preload("res://scripts/effects/我的世界/mc_native_animation.gd")
var mc_native_animation:Node

const MC_AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
@export var mc_audio_role:String = ""
const MC_FX = preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
var _mc_portal_wait:float = 0.0
var _mc_death_visual_done:bool = false
@export_range(0.0,1.0,0.05) var hurt_voice_chance:float = 0.45
@export var ambient_gap_min:float = 3.0
@export var ambient_gap_max:float = 7.0
var _mc_voice_rng := RandomNumberGenerator.new()
var _mc_ambient_wait:float = 0.0
var _mc_ambient_key:String = ""
var _mc_ambient_player:AudioStreamPlayer2D

var _mc_rng := RandomNumberGenerator.new()
var _mc_target_ref:WeakRef
var _mc_target_wait:float = 0.0

func _ready() -> void:
	if mc_audio_role.is_empty():
		mc_audio_role = {"唤魔者":"evoker","潜影贝":"shulker","末影人":"enderman","潜影弹":"shulker_bullet","唤魔恼鬼":"vex","mc_short_lived_mob":"enderman"}.get(get_script().resource_path.get_file().get_basename(),"")
	_mc_rng.seed = Game.battle_rng_seed_or("mc_mob:" + str(name),int(get_instance_id()))
	super._ready()
	_mc_voice_rng.randomize()
	_mc_ambient_wait = _mc_voice_rng.randf_range(2.0,5.0)
	_mc_ambient_key = mc_ambient_event()
	mc_native_animation = MC_NATIVE_ANIMATION.attach(self,mc_audio_role)

func mc_cast_animation(duration:float = 0.65) -> void:
	if is_instance_valid(mc_native_animation): mc_native_animation.call("trigger_cast",duration)

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	mc_tick_ambient(delta)
	if mc_audio_role == "enderman" and health > 0 and is_combat_runtime_active():
		_mc_portal_wait -= delta
		if _mc_portal_wait <= 0.0:
			_mc_portal_wait = 0.14
			MC_FX.portal(self,global_position)
func mc_death_visual() -> void:
	if _mc_death_visual_done: return
	_mc_death_visual_done = true
	mc_stop_ambient()
	if image is Sprite2D: MC_FX.death_pose(self,image,direction.x >= 0.0)
func mc_live() -> bool:
	return is_multiplayer_authority() and health > 0 and is_combat_runtime_active() and not is_damage_output_disabled()

func mc_enemy(target:Variant) -> bool:
	# 必须先接收 Variant 再检查：已释放对象传入 ball 参数会在进入函数前报错。
	if not is_instance_valid(target): return false
	if not target is ball or target.is_queued_for_deletion(): return false
	if target == self or target.health <= 0 or not target.is_combat_targetable(): return false
	if target.Type not in [Ball_Type.Ball,Ball_Type.Creature]: return false
	if target == Master or target.Master == self: return false
	if is_instance_valid(Master) and target.Master == Master: return false
	return Game.Game_Settings.Have_Team_Damage or Team.is_empty() or target.Team != Team

func mc_nearest(delta:float = 0.0) -> ball:
	_mc_target_wait -= delta
	var cached:Variant = _mc_target_ref.get_ref() if _mc_target_ref != null else null
	if _mc_target_wait > 0.0 and mc_enemy(cached): return cached
	_mc_target_wait = 0.18
	_mc_target_ref = null
	var nearest:ball = null
	var best:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and mc_enemy(node):
			var distance:float = global_position.distance_squared_to(node.global_position)
			if distance < best:
				best = distance
				nearest = node
	if nearest != null: _mc_target_ref = weakref(nearest)
	return nearest

func mc_line_clear(from:Vector2,to:Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from,to,1,[get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func mc_position_clear(point:Vector2,radius:float = 16.0) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func mc_body_position_clear(point:Vector2) -> bool:
	if collision_shape_2d == null or collision_shape_2d.shape == null: return mc_position_clear(point,18.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape_2d.shape
	query.transform = collision_shape_2d.global_transform
	query.transform.origin += point-global_position
	query.collision_mask = 3
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func mc_arena_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("return_map_world_rect"):
		var maps:Variant = world.get("map_group")
		var key:Variant = world.get("now_choose_map")
		if maps is Dictionary and maps.has(key): return world.call("return_map_world_rect",maps[key])
	return Rect2(global_position - Vector2(240,180),Vector2(480,360))

func mc_safe_random_position() -> Vector2:
	var rect:Rect2 = mc_arena_rect().grow(-22.0)
	for attempt:int in range(24):
		var point := Vector2(_mc_rng.randf_range(rect.position.x,rect.end.x),_mc_rng.randf_range(rect.position.y,rect.end.y))
		if mc_body_position_clear(point): return point
	return global_position

func mc_spawn_creature(path:String,point:Vector2,multiplier:float = 0.5) -> ball:
	var scene:PackedScene = load(path) as PackedScene
	if scene == null or not mc_position_clear(point,12.0): return null
	var unit:ball = scene.instantiate() as ball
	unit.Master = self
	unit.Master_name = str(get_path())
	unit.Team = Team
	unit.inherit_master_attack_power = true
	unit.master_attack_damage_multiplier = multiplier
	unit.name = Game.return_random_name(unit)
	get_tree().current_scene.add_child(unit,true)
	unit.global_position = point
	unit.add_to_group("BattleTransient")
	return unit

func mc_play(event:String,volume:float = -4.0) -> AudioStreamPlayer2D:
	if mc_audio_role.is_empty(): return null
	return MC_AUDIO.play(self,"entity."+mc_audio_role+"."+event,global_position,volume)
func mc_hurt_event() -> String: return "hurt"
func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	super.on_actual_health_damage_received(actual_health_damage,health_before)
	if is_multiplayer_authority() and health > 0 and _mc_voice_rng.randf() < hurt_voice_chance:
		mc_play(mc_hurt_event(),-5.0)
func Die() -> void:
	if mc_audio_role.is_empty(): super.Die()
	else:
		mc_play("death",-5.0)
		mc_death_visual()

func mc_ambient_event() -> String:
	return "ambient" if mc_audio_role in ["evoker","vex","enderman","shulker"] else ""
func mc_ambient_allowed() -> bool: return true
func mc_ambient_gap() -> Vector2: return Vector2(ambient_gap_min,ambient_gap_max)
func mc_tick_ambient(delta:float) -> void:
	var allowed:bool = health > 0 and is_combat_runtime_active() and mc_ambient_allowed() and not Game.now_stop_state
	if is_instance_valid(_mc_ambient_player):
		_mc_ambient_player.global_position = global_position
		_mc_ambient_player.stream_paused = not allowed
	if not allowed: return
	var event:String = mc_ambient_event()
	if event.is_empty(): return
	if event != _mc_ambient_key:
		var previous_left:float = 0.0
		if is_instance_valid(_mc_ambient_player):
			previous_left = maxf((_mc_ambient_player.stream.get_length()-_mc_ambient_player.get_playback_position())/maxf(_mc_ambient_player.pitch_scale,0.01),0.0)
		mc_stop_ambient()
		_mc_ambient_key = event
		_mc_ambient_wait = maxf(previous_left,_mc_voice_rng.randf_range(0.6,1.2))
	_mc_ambient_wait = maxf(_mc_ambient_wait-delta,0.0)
	if _mc_ambient_wait > 0.0: return
	if is_instance_valid(_mc_ambient_player) and _mc_ambient_player.playing: return
	_mc_ambient_player = mc_play(event,-8.0)
	if not is_instance_valid(_mc_ambient_player):
		_mc_ambient_wait = 0.15
		return
	var duration:float = _mc_ambient_player.stream.get_length()/maxf(_mc_ambient_player.pitch_scale,0.01)
	var gap:Vector2 = mc_ambient_gap()
	# 从播放开始计时：至少完整音频时长，再加随机空白；闭壳时播放进度和计时一起暂停。
	_mc_ambient_wait = duration+_mc_voice_rng.randf_range(maxf(gap.x,0.0),maxf(gap.y,gap.x))
func mc_stop_ambient() -> void:
	if is_instance_valid(_mc_ambient_player):
		_mc_ambient_player.stop()
		_mc_ambient_player.queue_free()
	_mc_ambient_player = null
func _exit_tree() -> void: mc_stop_ambient()
