extends "res://scripts/characters/我的世界/new5/base.gd"
## 三废石（Useless Stones）：一名选手由花岗岩、闪长岩、安山岩三块原版方块组成。
## 放置的是花岗岩（领头），开战前延迟生成另外两块；三块共享一个三人组（同一存续键，
## 任意一块活着这一方就没输），各自独立、走公共正常移动，射程内锁最近的可见敌人投掷石块。
## 三块之间无身体碰撞、互不选为目标；石块投射物见 stone_shard.gd。
## - 花岗岩：伤害最高、攻速中等；命中小幅击退并施加缓慢 II，不叠加，再次命中重置时间。
## - 闪长岩：伤害较低；每次命中永久提高自身攻速（每次 +闪长岩每击攻速，没有上限）。
## - 安山岩：攻速最慢、伤害低；命中时治疗三块中生命比例最低的一块，目标越残血治疗越多；
##   每隔一段时间给三块都施加几秒急迫 III。治疗与急迫都以地面石头波纹（andesite_ripple.gd）
##   从安山岩脚下射向队友，抵达时才生效。
## 受击播原版石头敲击声、碎裂播原版石头破坏声并迸出方块像素碎屑。
const SHARD_SCENE:PackedScene = preload("res://scenes/shooter/我的世界/废石碎块.tscn")
const STONE_AUDIO = preload("res://scripts/characters/我的世界/useless_stones/useless_stones_audio.gd")
const RIPPLE = preload("res://scripts/characters/我的世界/useless_stones/andesite_ripple.gd")
const STATUS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const BLOCK_FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const SCENE_PATH:String = "res://scenes/characters/我的世界/三废石.tscn"
const GRANITE:int = 0
const DIORITE:int = 1
const ANDESITE:int = 2
const KIND_NAMES:Array[String] = ["granite","diorite","andesite"]
const BLOCKS:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/useless_stones/granite_block.png"),
	preload("res://Images/characters/我的世界/useless_stones/diorite_block.png"),
	preload("res://Images/characters/我的世界/useless_stones/andesite_block.png"),
]
const DIORITE_BUFF_KEY:String = "三废石_闪长岩攻速"
const SHARED_EXPORTS:Array[String] = ["attack_range","shard_speed","granite_damage","granite_attack_cooling","granite_knockback","granite_knockback_speed","granite_slowness_level","granite_slowness_duration","diorite_damage","diorite_attack_cooling","diorite_rate_per_hit","andesite_damage","andesite_attack_cooling","andesite_heal_missing_scale","andesite_haste_first","andesite_haste_interval","andesite_haste_level","andesite_haste_duration","ripple_speed","member_spawn_distance"]

## 0 花岗岩（放置的领头）、1 闪长岩、2 安山岩。
@export_range(0,2) var stone_kind:int = GRANITE
@export var attack_range:float = 280.0
@export var shard_speed:float = 330.0
@export var member_spawn_distance:float = 26.0
@export_category("三废石 / 花岗岩")
@export var granite_damage:int = 16
@export var granite_attack_cooling:float = 1.5
@export var granite_knockback:float = 20.0
@export var granite_knockback_speed:float = 170.0
@export var granite_slowness_level:int = 2
@export var granite_slowness_duration:float = 3.0
@export_category("三废石 / 闪长岩")
@export var diorite_damage:int = 8
@export var diorite_attack_cooling:float = 1.2
## 每次命中叠加的攻速比例：攻速倍率 = 1 + 层数 × 该值，冷却 = 基础冷却 / 攻速倍率。
@export var diorite_rate_per_hit:float = 0.10
@export_category("三废石 / 安山岩")
@export var andesite_damage:int = 5
@export var andesite_attack_cooling:float = 2.4
## 治疗量 = 安山岩当次伤害 × (1 + 该值 × 目标缺血比例)。
@export var andesite_heal_missing_scale:float = 6.0
@export var andesite_haste_first:float = 6.0
@export var andesite_haste_interval:float = 10.0
@export var andesite_haste_level:int = 3
@export var andesite_haste_duration:float = 5.0
@export var ripple_speed:float = 300.0

var trio:Dictionary = {}
## 领头的伤害相对花岗岩基础伤害的倍率；成员按同一倍率换算各自基础伤害（训练强化等）。
var stat_ratio:float = 1.0
var diorite_stacks:int = 0
var shots_fired:int = 0
var heals_sent:int = 0
var haste_casts:int = 0
var _shot_left:float = 0.4
var _shot_serial:int = 0
var _ripple_serial:int = 0
var _haste_wait:float = 6.0
var _manual_request:bool = false
var _throw_sound_gap:float = 0.0
var _hit_sound_gap:float = 0.0
var _pulse:float = 0.0
var _rest_image_scale:Vector2 = Vector2.ONE
var _break_done:bool = false
var _stone_collision_peers:Array[WeakRef] = []

func get_preview_texture() -> Texture2D: return BLOCKS[GRANITE]

func _ready() -> void:
	Hit_Audio = ""
	Dead_Audio = ""
	Unique_Death_Audio = null
	motion_blur_enabled = false
	motion_blur_effect_strength = 0.0
	motion_stretch_enabled = false
	AfterImage_Speed = 0.0
	_apply_kind_stats()
	super._ready()
	add_to_group(&"MCUselessStone")
	if image != null: _rest_image_scale = image.scale
	_apply_kind_visual()
	_haste_wait = andesite_haste_first
	_shot_left = 0.3 + 0.15*float(stone_kind)
	if trio.is_empty(): call_deferred("initialize_trio")

func _apply_kind_stats() -> void:
	stone_kind = clampi(stone_kind,GRANITE,ANDESITE)
	if stone_kind == GRANITE:
		stat_ratio = float(Damage)/float(maxi(granite_damage,1))
		return
	var base:int = diorite_damage if stone_kind == DIORITE else andesite_damage
	Damage = maxi(int(round(float(base)*stat_ratio)),1)
	Attack_Cooling = diorite_attack_cooling if stone_kind == DIORITE else andesite_attack_cooling
	default_properties["Damage"] = Damage
	default_properties["Attack_Cooling"] = Attack_Cooling

func _apply_kind_visual() -> void:
	if image is Sprite2D: image.texture = BLOCKS[clampi(stone_kind,GRANITE,ANDESITE)]

# ---------------------------------------------------------------- 三人组

func initialize_trio() -> void:
	if not trio.is_empty() or health <= 0 or not is_multiplayer_authority(): return
	# 编队预览（以及正在释放的预览）不能留下真正的三人组。
	if is_queued_for_deletion() or has_meta("rotation_prestart_preview") or not is_inside_tree(): return
	var world:Node = get_tree().current_scene
	var victory_key:String = "team:"+Team if not Team.is_empty() else "solo_instance:"+str(get_instance_id())
	var presentation_key:String = "team:"+Team if not Team.is_empty() else "solo:"+str(get_instance_id())
	if world != null and world.has_method("_victory_side_key_for_character"):
		victory_key = world.call("_victory_side_key_for_character",self)
		presentation_key = world.call("return_ball_side_key",self)
	trio = {"members":[weakref(self)],"key":victory_key,"presentation":presentation_key,"id":get_instance_id()}
	_mark_identity(self)
	if stone_kind != GRANITE: return
	_spawn_member(DIORITE,1)
	_spawn_member(ANDESITE,2)

func _mark_identity(unit:ball) -> void:
	unit.set_meta("mc_stone_trio",trio.id)
	unit.set_meta("battle_continuation_victory_side_key",trio.key)
	unit.set_meta("battle_continuation_presentation_side_key",trio.presentation)
	unit.set_meta("victory_side_key",trio.key)
	if has_meta("battle_setup_id"): unit.set_meta("battle_setup_id",get_meta("battle_setup_id"))

func living_members() -> Array:
	var result:Array = []
	for ref:WeakRef in trio.get("members",[]):
		var unit:Variant = ref.get_ref()
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.health > 0: result.append(unit)
	return result

func member_of_kind(kind:int) -> ball:
	for unit:Variant in living_members():
		if int(unit.stone_kind) == kind: return unit
	return null

func _spawn_member(kind:int,index:int) -> ball:
	var parent:Node = get_parent()
	if not is_instance_valid(parent): return null
	var unit:ball = (load(SCENE_PATH) as PackedScene).instantiate() as ball
	unit.manual_controllable_subentity = true # 每块石头都可单独选控。
	unit.set("stone_kind",kind)
	unit.set("trio",trio)
	unit.set("stat_ratio",stat_ratio)
	for key:String in SHARED_EXPORTS: unit.set(key,get(key))
	unit.Max_health = Max_health
	unit.Speed = float(default_properties.get("Speed",Speed))
	unit.Team = Team
	unit.name = Game.return_random_name(unit)
	unit.set_multiplayer_authority(get_multiplayer_authority())
	_mark_identity(unit)
	var point:Vector2 = _spawn_point(index)
	unit.position = parent.to_local(point) if parent is Node2D else point
	parent.add_child(unit,true)
	unit.add_to_group("BattleTransient")
	for member:ball in living_members():
		if member == unit: continue
		unit.add_collision_exception_with(member)
		member.add_collision_exception_with(unit)
		unit._stone_collision_peers.append(weakref(member))
		member._stone_collision_peers.append(weakref(unit))
	trio.members.append(weakref(unit))
	return unit

func _spawn_point(index:int) -> Vector2:
	var distance:float = member_spawn_distance
	for attempt:int in range(18):
		var angle:float = PI*0.5 + TAU*float(index)/3.0 + float(attempt)*0.53
		var point:Vector2 = global_position + Vector2.RIGHT.rotated(angle)*(distance + float(attempt/6)*12.0)
		if _position_clear(point,9.0) and U.line_clear(self,global_position,point): return point
	return global_position

func _position_clear(point:Vector2,radius:float) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func _forget_stone_collision_peer(peer:Node) -> void:
	for i:int in range(_stone_collision_peers.size()-1,-1,-1):
		var other:Variant = _stone_collision_peers[i].get_ref()
		if not is_instance_valid(other) or other == peer: _stone_collision_peers.remove_at(i)

func _clear_stone_collision_exceptions() -> void:
	for ref:WeakRef in _stone_collision_peers:
		var peer:Variant = ref.get_ref()
		if is_instance_valid(peer):
			remove_collision_exception_with(peer)
			peer.remove_collision_exception_with(self)
			peer._forget_stone_collision_peer(self)
	_stone_collision_peers.clear()

# ---------------------------------------------------------------- 选敌与投掷

func stone_enemy(target:Variant) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false
	if not is_instance_valid(target) or not target is ball or target.is_queued_for_deletion(): return false
	if target == self or target.health <= 0 or not target.is_combat_targetable(): return false
	if target.Type not in [Ball_Type.Ball,Ball_Type.Creature]: return false
	if not trio.is_empty() and int(target.get_meta("mc_stone_trio",-1)) == int(trio.id): return false
	if target == Master or target.Master == self: return false
	return U.enemy(self,target)

func nearest_stone_enemy() -> ball:
	var result:ball = null
	var best:float = attack_range*attack_range
	for raw:Variant in SubmissionCharacterTools.targeting_candidates(self):
		if not is_instance_valid(raw) or not (raw is ball): continue
		var node:ball = raw as ball
		if not stone_enemy(node) or not node.is_combat_lockable(): continue
		var point:Vector2 = ball.body_point(node,global_position)
		var distance:float = global_position.distance_squared_to(point)
		if distance <= best and U.line_clear(self,global_position,point):
			best = distance
			result = node
	return result

func step_mob(delta:float) -> void:
	_shot_left = maxf(_shot_left-delta,0.0)
	_throw_sound_gap = maxf(_throw_sound_gap-delta,0.0)
	if stone_kind == ANDESITE: _tick_haste(delta)
	if dizziness or is_damage_output_disabled() or not Can_Attack:
		_manual_request = false
		return
	if is_player_controlled():
		if _manual_request and _shot_left <= 0.0 and has_player_control_aim():
			_manual_request = false
			throw_at(player_control_aim_world_position())
		return
	if _shot_left > 0.0: return
	var target:ball = nearest_stone_enemy()
	if target != null: throw_at(ball.body_point(target,global_position))

func controlled_attack_action() -> void:
	if is_player_controlled() and is_multiplayer_authority(): _manual_request = true

func player_control_action_cancelled(index:int) -> void:
	if index == 0: _manual_request = false

func set_player_control_peer(peer_id:int) -> void:
	if peer_id != player_control_peer_id: _manual_request = false
	super.set_player_control_peer(peer_id)

func throw_at(point:Vector2) -> bool:
	if not can_act() or not point.is_finite(): return false
	var parent:Node = get_parent()
	if not is_instance_valid(parent): return false
	var aim:Vector2 = global_position.direction_to(point)
	if aim.is_zero_approx(): aim = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_shot_serial += 1
	shots_fired += 1
	var shot_name:String = str(name)+"_Stone_"+str(_shot_serial)
	var damage:float = attack_damage() # 每块石头取投掷瞬间的攻击力。
	_spawn_shard(shot_name,global_position,aim,damage)
	if multiplayer.has_multiplayer_peer(): _spawn_shard.rpc(shot_name,global_position,aim,damage)
	# 冷却直接取实时 Attack_Cooling（含急迫、闪长岩叠层）；闪长岩不设下限，最多每物理帧一投。
	_shot_left = maxf(Attack_Cooling,0.0)
	_pulse = 1.0
	if _throw_sound_gap <= 0.0:
		_throw_sound_gap = 0.09
		_play_stone_sound(STONE_AUDIO.THROW_SOUND,_shot_serial,rng.randf_range(0.8,1.2))
	return true

@rpc("authority","call_remote","reliable")
func _spawn_shard(shot_name:String,point:Vector2,heading:Vector2,damage:float) -> void:
	var parent:Node = get_parent()
	if not is_instance_valid(parent) or parent.has_node(NodePath(shot_name)): return
	_pulse = 1.0
	var shot:ball = SHARD_SCENE.instantiate()
	shot.name = shot_name
	shot.Master = self
	shot.Master_name = str(name)
	shot.Team = Team
	shot.Damage = maxi(int(round(damage)),1)
	shot.Speed = shard_speed
	shot.direction = heading
	shot.set("stone_kind",stone_kind)
	shot.set("trio_id",int(trio.get("id",-1)))
	shot.set("life",attack_range/maxf(shard_speed,1.0))
	if stone_kind == GRANITE:
		shot.set("knockback",granite_knockback)
		shot.set("knockback_speed",granite_knockback_speed)
		shot.set("slowness_level",granite_slowness_level)
		shot.set("slowness_duration",granite_slowness_duration)
	shot.position = parent.to_local(point) if parent is Node2D else point
	shot.set_multiplayer_authority(get_multiplayer_authority())
	parent.add_child(shot,true)

## 石块命中敌人（被接受的命中，护盾吸收也算）后由石块回调。
func on_stone_shard_hit(_target:Variant,_actual:float) -> void:
	if not is_multiplayer_authority() or health <= 0 or is_queued_for_deletion(): return
	match stone_kind:
		DIORITE: add_diorite_stack()
		ANDESITE: heal_lowest_member()

func add_diorite_stack() -> void:
	diorite_stacks += 1
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("new_buff"): return
	var rate:float = 1.0 + maxf(diorite_rate_per_hit,0.0)*float(diorite_stacks)
	world.call("new_buff",self,self,DIORITE_BUFF_KEY,Buff.new(2,INF,Buff.Buff_types.Attack_Cooling,1.0/rate,Buff.Algorithms.mul))
	if world.has_method("refresh_runtime_buffs"): world.call("refresh_runtime_buffs",self)

func diorite_attack_rate() -> float:
	return 1.0 + maxf(diorite_rate_per_hit,0.0)*float(diorite_stacks)

func heal_lowest_member() -> void:
	var chosen:ball = null
	var lowest:float = INF
	for unit:Variant in living_members():
		var ratio:float = float(unit.health)/maxf(float(unit.Max_health),1.0)
		if ratio < lowest:
			lowest = ratio
			chosen = unit
	if chosen == null or lowest >= 1.0: return
	heals_sent += 1
	_launch_ripple(chosen,RIPPLE.HEAL,attack_damage())

func _tick_haste(delta:float) -> void:
	_haste_wait -= delta
	if _haste_wait > 0.0: return
	_haste_wait = maxf(andesite_haste_interval,0.5)
	haste_casts += 1
	for unit:Variant in living_members(): _launch_ripple(unit,RIPPLE.HASTE,0.0)

func _launch_ripple(target:ball,kind:int,amount:float) -> void:
	_ripple_serial += 1
	var serial:int = int(get_instance_id() % 100000)*1000 + _ripple_serial
	var scale_value:float = _unit_scale()
	RIPPLE.launch(get_parent(),self,target,kind,{"start":global_position,"serial":serial,"amount_base":amount,"heal_missing_scale":andesite_heal_missing_scale,"haste_level":andesite_haste_level,"haste_duration":andesite_haste_duration,"speed":ripple_speed,"unit_scale":scale_value,"authoritative":true})
	if multiplayer.has_multiplayer_peer(): _show_ripple.rpc(serial,global_position,target.get_path(),kind,scale_value)

@rpc("authority","call_remote","reliable")
func _show_ripple(serial:int,start:Vector2,target_path:NodePath,kind:int,scale_value:float) -> void:
	var target:Node2D = get_node_or_null(target_path) as Node2D
	if target == null: return
	RIPPLE.launch(get_parent(),self,target,kind,{"start":start,"serial":serial,"speed":ripple_speed,"unit_scale":scale_value,"authoritative":false})

## 角色根缩放 0.2 是“单位 1”；地图换算后的实际根缩放按比例放大或缩小波纹。
func _unit_scale() -> float:
	return absf(global_scale.x)/0.2 if global_scale.x != 0.0 else 1.0

# ---------------------------------------------------------------- 声音与表现

func _play_stone_sound(kind:int,index:int,pitch_scale:float = 1.0) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.has_multiplayer_peer(): _receive_stone_sound.rpc(kind,index,global_position,pitch_scale)
	_receive_stone_sound(kind,index,global_position,pitch_scale)

@rpc("authority","call_remote","reliable")
func _receive_stone_sound(kind:int,index:int,point:Vector2,pitch_scale:float) -> void:
	STONE_AUDIO.play(self,kind,index,point,pitch_scale)

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if amount <= 0.0 or health <= 0 or not is_multiplayer_authority(): return
	if Time.get_ticks_msec()*0.001 < _hit_sound_gap: return
	_hit_sound_gap = Time.get_ticks_msec()*0.001 + 0.1
	_play_stone_sound(STONE_AUDIO.HIT_SOUND,rng.randi_range(0,STONE_AUDIO.variant_count(STONE_AUDIO.HIT_SOUND)-1))

func Die() -> void:
	if is_multiplayer_authority() and not _break_done:
		_play_stone_sound(STONE_AUDIO.BREAK_SOUND,rng.randi_range(0,STONE_AUDIO.variant_count(STONE_AUDIO.BREAK_SOUND)-1))
		if multiplayer.has_multiplayer_peer(): _shatter.rpc(absi(hash(str(name))))
		_shatter(absi(hash(str(name))))
	_clear_stone_collision_exceptions()
	super.Die()

@rpc("authority","call_remote","reliable")
func _shatter(seed_value:int) -> void:
	if _break_done or image == null or not is_inside_tree(): return
	_break_done = true
	BLOCK_FRAGMENTS.spawn_obstacle(image,{},{"max_pieces":16,"scatter_radius":14.0*_unit_scale(),"arc_height_min":5.0*_unit_scale(),"arc_height_max":13.0*_unit_scale(),"seed":seed_value})
	image.visible = false

func _exit_tree() -> void:
	_clear_stone_collision_exceptions()
	super._exit_tree()

func visual_mob() -> void:
	if image == null: return
	_apply_kind_visual()
	if _pulse > 0.0 and is_combat_runtime_active(): _pulse = maxf(_pulse-get_process_delta_time()/0.16,0.0)
	var squash:float = sin(_pulse*PI)*0.1
	image.scale = Vector2(_rest_image_scale.x*(1.0+squash),_rest_image_scale.y*(1.0-squash*0.6))

func visual_state() -> Dictionary: return {"time":clock,"kind":stone_kind,"stacks":diorite_stacks}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	stone_kind = clampi(int(data.get("kind",stone_kind)),GRANITE,ANDESITE)
	diorite_stacks = int(data.get("stacks",diorite_stacks))

func get_debug_detection_regions() -> Array:
	if health <= 0 or not Can_Attack or dizziness or is_damage_output_disabled(): return []
	return [{"shape":"circle","position":global_position,"radius":attack_range,"kind":"stone_throw_targeting"}]

func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_USELESS_STONES")
