extends "res://scripts/characters/我的世界/zombie/zombie.gd"
const KING_FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/zombie/king.tres")
const ZOMBIE_SCENE:String = "res://scenes/characters/我的世界/僵尸.tscn"
const SLIME_SCENE:String = "res://scenes/creatures/僵尸粘液球.tscn"
const WALL = preload("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
const MAX_SUMMONS:int = 6
const SUMMON_COUNT:int = 2
const SUMMON_INTERVAL:float = 8.0
const THROW_RANGE:float = 260.0
var summon_cooldown:float = 2.0
var throw_cooldown:float = 1.0
var _summons:Array[WeakRef] = []
var _shot_serial:int = 0
var _received_shot:int = 0

func _ready() -> void:
	super._ready()
	add_to_group("MinecraftZombieKing")
func body_frames() -> SpriteFrames: return KING_FRAMES
func begin_bite(_target:Variant) -> bool: return false
func player_control_action_ids() -> Array[StringName]: return [&"controlled_attack_action",&"controlled_skill_action"]
func step_zombie(delta:float) -> void:
	summon_cooldown = maxf(0.0,summon_cooldown-delta)
	throw_cooldown = maxf(0.0,throw_cooldown-delta)
	if not can_act() or is_player_controlled(): return
	var target:ball = mc_nearest(delta)
	if target == null: return
	if summon_cooldown <= 0.0: summon_zombies()
	if throw_cooldown <= 0.0 and global_position.distance_to(ball.body_point(target,global_position)) <= THROW_RANGE:
		throw_slime(ball.body_point(target,global_position))
func controlled_attack_action() -> void:
	if is_player_controlled(): summon_zombies()
func controlled_skill_action() -> void:
	if is_player_controlled(): throw_slime(player_control_aim_world_position())
func living_summons() -> Array[ball]:
	var result:Array[ball] = []
	for i:int in range(_summons.size()-1,-1,-1):
		var unit:Variant = _summons[i].get_ref()
		if not is_instance_valid(unit) or unit.health <= 0 or unit.is_queued_for_deletion(): _summons.remove_at(i)
		else: result.append(unit)
	return result
func summon_zombies() -> int:
	if not can_act() or summon_cooldown > 0.0: return 0
	var count:int = mini(SUMMON_COUNT,MAX_SUMMONS-living_summons().size())
	var spawned:int = 0
	var world:Node = get_parent()
	for i:int in range(count):
		var unit:ball = load(ZOMBIE_SCENE).instantiate()
		unit.Master = self
		unit.Master_name = str(get_path())
		unit.Team = Team
		# Summons have their own attack attributes; the king deliberately has zero Damage.
		unit.inherit_master_attack_power = false
		unit.set_multiplayer_authority(get_multiplayer_authority())
		unit.name = Game.return_random_name(unit)
		var slot:Dictionary = summon_wall_slot(unit)
		if slot.is_empty():
			unit.free()
			continue
		unit.entry_face = slot.face
		unit.entry_normal = slot.normal
		unit.entry_target = slot.floor
		unit.entry_left = 0.9
		unit.position = world.to_local(slot.face-slot.normal*40.0)
		world.add_child(unit,true)
		unit.add_to_group("BattleTransient")
		_summons.append(weakref(unit))
		spawned += 1
	if spawned > 0:
		summon_cooldown = SUMMON_INTERVAL
		voice.request("ambient",global_position,-3.0)
	return spawned
func summon_wall_slot(unit:ball) -> Dictionary:
	var world:Node = get_parent()
	var rects:Array[Rect2] = []
	if world.has_method("map_islands"):
		for island:Dictionary in world.map_islands(world._current_map_node()): rects.append(island.rect)
	if rects.is_empty(): rects.append(mc_arena_rect())
	var slots:Array[Dictionary] = []
	for rect:Rect2 in rects: slots.append_array(WALL.wall_slots(null,rect))
	unit.collision_shape_2d = unit.get_node("CollisionShape2D")
	while not slots.is_empty():
		var index:int = _mc_rng.randi_range(0,slots.size()-1)
		var slot:Dictionary = slots[index]
		slots.remove_at(index)
		var point:Vector2 = slot.face+slot.normal*40.0
		if world.has_method("map_free_spawn_position"): point = world.map_free_spawn_position(unit,point)
		if not mc_position_clear(point,16.0): continue
		var occupied:bool = false
		for other:ball in living_summons():
			var planned:Vector2 = other.entry_target if other.entry_left > 0.0 else other.global_position
			if planned.distance_to(point) < 36.0: occupied = true
		if occupied: continue
		slot.floor = point
		# Keep the ingress perpendicular even when the common resolver shifts sideways.
		slot.face += (point-slot.face).slide(slot.normal)
		return slot
	return {}
func throw_slime(point:Vector2) -> bool:
	if not can_act() or throw_cooldown > 0.0 or not point.is_finite(): return false
	var start:Vector2 = global_position+Vector2(0,-8)
	var offset:Vector2 = (point-start).limit_length(THROW_RANGE)
	if offset.length() < 12.0: offset = player_control_aim_direction(direction)*12.0
	point = start+offset
	throw_cooldown = maxf(Attack_Cooling,0.15)
	_shot_serial += 1
	_spawn_slime(_shot_serial,start,point)
	return true
func _spawn_slime(serial:int,start:Vector2,end:Vector2) -> void:
	if serial <= _received_shot: return
	_received_shot = serial
	var shot:Node2D = load(SLIME_SCENE).instantiate()
	shot.name = str(name)+"_Slime_"+str(serial)
	shot.configure(self,start,end)
	shot.set_multiplayer_authority(get_multiplayer_authority())
	shot.position = get_parent().to_local(start)
	get_parent().add_child(shot,true)
func get_ai_attack_threats() -> Array[Dictionary]: return []
func get_armor_test_effect_summary() -> String: return Game.t("MC_ARMOR_INTRO_ZOMBIE_KING")
