extends "res://scripts/characters/我的世界/new5/base.gd"
const FIELD = preload("res://scripts/characters/我的世界/snow_golem/snow_field.gd")
const RULES = preload("res://scripts/characters/我的世界/snow_golem/rules.gd")
const SNOW_AUDIO = preload("res://scripts/characters/我的世界/snow_golem/audio.gd")
const SHOT:PackedScene = preload("res://scenes/shooter/我的世界/雪球.tscn")
const PUMPKIN:Array[Texture2D] = [preload("res://Images/characters/我的世界/snow_golem/pumpkin_left.png"),preload("res://Images/characters/我的世界/snow_golem/pumpkin_center.png"),preload("res://Images/characters/我的世界/snow_golem/pumpkin_right.png")]
const BARE:Array[Texture2D] = [preload("res://Images/characters/我的世界/snow_golem/bare_left.png"),preload("res://Images/characters/我的世界/snow_golem/bare_center.png"),preload("res://Images/characters/我的世界/snow_golem/bare_right.png")]
@export var miniature:bool = false
@export var attack_range:float = 260.0
@export var snowball_speed:float = 260.0
@export var shot_cold:float = 22.0
@export var snow_cold:float = 8.0
@export var freeze_duration:float = 1.4
@export var snow_tick_interval:float = 0.5
@export var snow_damage_multiplier:float = 0.33333334
@export var snowball_knockback:float = 8.0
@export_range(0.0,1.0,0.05) var aim_hold_duration:float = 0.25
var family:String = ""
var has_pumpkin:bool = true
var head_drop_count:int = 0
var shots_fired:int = 0
var _field:Node2D
var _shot_left:float = 0.0
var _last_cell:Vector2i
var _last_point:Vector2
var _trail_started:bool = false
var _aim:Vector2 = Vector2.LEFT
var _aim_hold_left:float = 0.0
var _visual_heading:Vector2 = Vector2.LEFT
var _aim_pose:int = 1
var _shot_serial:int = 0

func _ready() -> void:
	# The baked Minecraft front points left; agree with the common mover.
	dir_left = true
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Dead_Audio = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	motion_blur_enabled = false
	motion_stretch_enabled = false
	AfterImage_Speed = 0.0
	super._ready()
	image.z_as_relative = true
	image.z_index = 0
	add_to_group("MCSnowGolem")
	if family.is_empty(): family = str(name)
	set_meta("mc_snow_family",family)
	_field = FIELD.ensure(self)
	_shot_left = maxf(Attack_Cooling,0.1)
	_last_point = global_position
	call_deferred("_initialize_identity")
	visual_mob()

func _initialize_identity() -> void:
	if not is_multiplayer_authority(): return
	if has_meta("battle_continuation_victory_side_key"): return
	var world:Node = get_tree().current_scene
	var victory:String = "team:"+Team if not Team.is_empty() else "solo_instance:"+str(get_instance_id())
	var presentation:String = "team:"+Team if not Team.is_empty() else "solo:"+str(get_instance_id())
	if world.has_method("_victory_side_key_for_character"):
		victory = world.call("_victory_side_key_for_character",self)
		presentation = world.call("return_ball_side_key",self)
	set_meta("battle_continuation_victory_side_key",victory)
	set_meta("battle_continuation_presentation_side_key",presentation)
	set_meta("victory_side_key",victory)

func step_mob(delta:float) -> void:
	_shot_left = maxf(0.0,_shot_left-delta)
	_aim_hold_left = maxf(0.0,_aim_hold_left-delta)
	if dizziness or is_damage_output_disabled():
		_last_point = global_position
		_last_cell = FIELD.cell_at(global_position)
		return
	lay_trail()
	if not Can_Attack or _shot_left > 0.0: return
	var target:ball = nearest_snow_enemy()
	if is_instance_valid(target): fire_at(target.global_position)

func nearest_snow_enemy() -> ball:
	var result:ball
	var best:float = attack_range*attack_range
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not RULES.enemy(self,node) or not node.is_combat_lockable(): continue
		var distance:float = global_position.distance_squared_to(node.global_position)
		if distance <= best and U.line_clear(self,global_position,node.global_position):
			best = distance
			result = node as ball
	return result

func lay_trail() -> void:
	if not active() or dizziness or is_damage_output_disabled(): return
	if not is_instance_valid(_field): _field = FIELD.ensure(self)
	var point:Vector2 = global_position
	if not _trail_started:
		_trail_started = true
		_last_cell = FIELD.cell_at(point)
		_last_point = point
		_field.deposit(self,_last_cell,miniature)
		return
	var distance:float = _last_point.distance_to(point)
	# Never paint a teleport line, and never increment the same occupied cell
	# once per physics frame. A mini must actually leave and re-enter its cell.
	if distance > FIELD.CELL*8.0: _last_point = point
	var steps:int = clampi(int(ceil(_last_point.distance_to(point)/(FIELD.CELL*0.3))),1,32)
	for index:int in range(1,steps+1):
		var cell:Vector2i = FIELD.cell_at(_last_point.lerp(point,float(index)/float(steps)))
		if cell == _last_cell: continue
		_last_cell = cell
		_field.deposit(self,cell,miniature)
	_last_point = point

func fire_at(point:Vector2) -> bool:
	if not can_act() or _shot_left > 0.0 or global_position.distance_to(point) > attack_range: return false
	if not U.line_clear(self,global_position,point): return false
	var heading:Vector2 = global_position.direction_to(point)
	if heading == Vector2.ZERO: heading = direction.normalized()
	if heading == Vector2.ZERO: heading = Vector2.RIGHT
	_aim = heading
	_aim_hold_left = maxf(aim_hold_duration,0.0)
	visual_mob()
	_shot_left = maxf(Attack_Cooling,0.1)
	_shot_serial += 1
	shots_fired += 1
	var shot_name:String = str(name)+"_Snowball_"+str(_shot_serial)
	var point_from:Vector2 = global_position
	_spawn_snowball(shot_name,point_from,heading,attack_damage())
	if multiplayer.has_multiplayer_peer(): _spawn_snowball.rpc(shot_name,point_from,heading,attack_damage())
	play_sound("entity.snow_golem.shoot",-5.0)
	return true

@rpc("authority","call_remote","reliable")
func _spawn_snowball(shot_name:String,point:Vector2,heading:Vector2,damage:float) -> void:
	var world:Node = get_tree().current_scene
	if world.has_node(NodePath(shot_name)): return
	var shot:ball = SHOT.instantiate()
	shot.name = shot_name
	shot.Master = self
	shot.Master_name = str(name)
	shot.Team = Team
	shot.set_meta("mc_snow_family",family)
	shot.Damage = int(round(damage))
	shot.Speed = snowball_speed
	shot.cold_gain = shot_cold
	shot.freeze_duration = freeze_duration
	shot.snow_knockback = snowball_knockback
	shot.direction = heading
	shot.position = world.to_local(point) if world is Node2D else point
	shot.set_multiplayer_authority(get_multiplayer_authority())
	world.add_child(shot,true)

func Attack() -> void:
	Attacking = false
	var target:ball = nearest_snow_enemy()
	if has_player_control_aim(): fire_at(player_control_aim_world_position())
	elif is_instance_valid(target): fire_at(target.global_position)
func player_control_action(action_index:int) -> void:
	if action_index == 0: Attack()

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if not is_multiplayer_authority() or not has_pumpkin or amount <= 0.0 or health <= 0: return
	if float(health) <= float(Max_health)*0.5:
		has_pumpkin = false
		head_drop_count += 1
		if not is_instance_valid(_field): _field = FIELD.ensure(self)
		_field.drop_head(self)
		visual_mob()
		if multiplayer.has_multiplayer_peer(): _new5_visual.rpc(network_visual_state())

func mini_spawn_settings() -> Dictionary:
	_initialize_identity()
	var data:Dictionary = {"family":family,"team":Team,"direction":direction,
		"victory":get_meta("battle_continuation_victory_side_key","team:"+Team),
		"presentation":get_meta("battle_continuation_presentation_side_key","team:"+Team)}
	if has_meta("battle_setup_id"): data["setup"] = get_meta("battle_setup_id")
	# Match configured combat stats, not a temporary buff/debuff at birth.
	# Max_health deliberately stays the fixed mini health from its scene.
	var base_combat:Dictionary = {}
	for key:String in ["Damage","Speed","max_block","max_energy","Attack_Cooling","Skill_Cooling","Health_Restore","Damage_reduction"]:
		base_combat[key] = default_properties.get(key,get(key))
	data["base_combat"] = base_combat
	for key:String in ["snowball_speed","shot_cold","snow_cold","freeze_duration","snow_tick_interval","snow_damage_multiplier","snowball_knockback","attack_range","aim_hold_duration"]: data[key] = get(key)
	return data

func get_preview_texture() -> Texture2D: return PUMPKIN[1]
func voice_role() -> String: return "snow_golem"
@rpc("authority","call_remote","reliable")
func _receive_sound(event:String,point:Vector2,volume_db:float) -> AudioStreamPlayer2D:
	return SNOW_AUDIO.play(self,event,point,volume_db)

func _movement_facing_hint() -> Vector2:
	# The shared mover uses player_control_direction, not the stored AI direction.
	return player_control_direction if is_player_controlled() else direction

func move(speed:float,delta:float) -> void:
	super.move(speed,delta)
	# ball.move() also writes horizontal flip. Finish the physics step with the
	# same facing used by _process(), including shot aim and pure vertical motion.
	visual_mob()

func visual_mob() -> void:
	if not is_instance_valid(image): return
	if is_multiplayer_authority() and not dizziness:
		var hint:Vector2 = _aim if _aim_hold_left > 0.0 else _movement_facing_hint()
		if hint.length_squared() > 0.000001:
			_visual_heading = hint.normalized()
			# Native -28 yaw turns toward the camera (down); +28 turns away (up).
			# Horizontal mirroring changes X only, so both sides use this same mapping.
			_aim_pose = 2 if _visual_heading.y < -0.4 else 0 if _visual_heading.y > 0.4 else 1
	image.texture = PUMPKIN[clampi(_aim_pose,0,2)] if has_pumpkin else BARE[clampi(_aim_pose,0,2)]
	face_horizontal(_visual_heading,true)

func visual_state() -> Dictionary:
	return {"time":clock,"pumpkin":has_pumpkin,"miniature":miniature,"family":family,"aim":_aim,"pose":_aim_pose,"shot_left":_shot_left,"aim_hold":_aim_hold_left,"facing":_visual_heading}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	has_pumpkin = bool(data.get("pumpkin",has_pumpkin))
	family = str(data.get("family",family))
	set_meta("mc_snow_family",family)
	_aim = data.get("aim",_aim)
	_aim_pose = int(data.get("pose",1))
	_shot_left = float(data.get("shot_left",0.0))
	_aim_hold_left = float(data.get("aim_hold",0.0))
	_visual_heading = data.get("facing",_visual_heading)

func get_debug_detection_regions() -> Array:
	return [{"shape":"circle","position":global_position,"radius":attack_range,"kind":"snowball_targeting"}]
func get_armor_test_effect_summary() -> String:
	if str(Game.current_locale).begins_with("en"):
		return "Slow snowballs cause slight knockback and accumulate cold. Full snow tiles deal periodic damage and add cold to enemies, then melt into harmless mini snow and finally disappear. More cold means stronger slowing, slower attacks, a whiter body and more native snow particles; a full meter resets and briefly freezes the victim, who keeps losing health inside the ice and takes double damage until it breaks.\nAt half health the pumpkin drops once. It absorbs snow beneath it as the first block; further snow laid at its cell builds a second block and creates a smaller autonomous snow golem with lower health but matching combat stats. Mini trails start half-sized and harmless; a later pass completes the tile. Minis keep the same attacks, cold and pumpkin-building mechanics."
	return "慢速发射雪球，造成轻微击退并累计寒冷值；沿途留下整格雪径，敌人踩上持续受伤并积寒；雪径会先融成无害小雪，再消失。寒冷越高减速越强、攻速越慢，身体逐渐雪白、雪花增多；满值清空并短暂冻结，冻住期间持续掉血且受到的伤害加倍。\n半血时南瓜头仅掉落一次；落地吸收该格已有雪成为一层雪块，在其位置继续造雪，叠满两层后生成体型较小、血量较低，但其余战斗数值相同的小雪人。小雪人的初次雪径仅半格大小且无伤害/寒冷，再次经过补成完整雪；攻击、寒冷和掉头造雪人的机制相同。"

@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	DEATH_FX.death_pose(self,image,_face_right)
