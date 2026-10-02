extends "res://scripts/characters/我的世界/torch/torch_spark.gd"
# Reuse the existing parabolic path, not the torch's particles or landing action.
const SLIME_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/zombie/slimeball.png")
const PARTICLE = preload("res://scripts/effects/我的世界/末影粒子.gd")
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const PROJECTILES = preload("res://classes/projectile_interactions.gd")
const ENCHANTS = preload("res://scripts/effects/我的世界/mc_enchantments.gd")
const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const UTILS = preload("res://scripts/characters/我的世界/new5/utils.gd")
const HIT_RADIUS:float = 4.0
const SLOW_SECONDS:float = 4.0
var _owner_name:String = ""
var _source_ref:WeakRef
var _spent:bool = false
var _redirected:bool = false
var _motion:Vector2 = Vector2.ZERO
var _life:float = 3.0
var _trail_distance:float = 0.0
var _visual_rng := RandomNumberGenerator.new()

func configure(caster:ball,start:Vector2,end:Vector2) -> void:
	_source_ref = weakref(caster)
	_owner_name = str(caster.name)
	_torch = weakref(caster)
	_from = start
	_to = end
	_ground_from = caster.global_position
	_flight = clampf(start.distance_to(end)/210.0,0.55,1.25)
	_arc = 28.0+start.distance_to(end)*0.18
	_age = 0.0
	set_meta("projectile_damage_kind","ordinary")
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 8
	add_to_group("BattleTransient")
	add_to_group("MCZombieSlimeBall")
	add_to_group("AI_Hazard")
	_visual_rng.randomize()
	set_process(false)
func get_projectile_source() -> Node:
	var node:Variant = _source_ref.get_ref() if _source_ref != null else null
	if is_instance_valid(node): return node
	return get_parent().get_node_or_null(NodePath(_owner_name)) if get_parent() != null and not _owner_name.is_empty() else null
func get_projectile_team() -> String:
	var source:Node = get_projectile_source()
	return str(source.Team) if source is ball else ""
func get_projectile_damage() -> float: return 0.0
func get_projectile_damage_kind() -> String: return "ordinary"
func get_projectile_radius() -> float: return HIT_RADIUS
func get_projectile_velocity() -> Vector2:
	if _redirected: return _motion
	var t:float = clampf(_age/_flight,0.0,1.0)
	return (_to-_from+Vector2.UP*_arc*4.0*(1.0-2.0*t))/_flight
func set_projectile_velocity(value:Vector2) -> void:
	_redirected = true
	_motion = value
func bind_projectile_owner(owner_unit:ball,_team:String,_previous:ball = null) -> void:
	_source_ref = weakref(owner_unit)
	var root_owner:ball = SubmissionCharacterTools.combat_root(owner_unit)
	_owner_name = str(root_owner.name if is_instance_valid(root_owner) else owner_unit.name)
func projectile_supports(capability:String) -> bool:
	return capability in ["block","reflect","redirect","capture","predict","wool"]
func relaunch_projectile(point:Vector2,target:Vector2) -> void:
	global_position = point
	_spent = false
	_life = 3.0
	_age = 0.0
	_from = point
	_to = target
	_flight = clampf(point.distance_to(target)/210.0,0.55,1.25)
	_redirected = false
func _physics_process(delta:float) -> void:
	if _spent or get_tree().paused or Game.now_stop_state: return
	var source:ball = get_projectile_source() as ball
	if source == null:
		retire()
		return
	if not source.is_combat_runtime_active(): return
	_life -= delta
	if _life <= 0.0:
		retire()
		return
	var start:Vector2 = global_position
	_age += delta
	var t:float = clampf(_age/_flight,0.0,1.0)
	var end:Vector2 = point_at(t)
	if _redirected:
		var gravity:Vector2 = Vector2.DOWN*(8.0*_arc/(_flight*_flight))
		end = start+_motion*delta+gravity*(0.5*delta*delta)
		_motion += gravity*delta
	if is_multiplayer_authority():
		var wall:Dictionary = UTILS.trace(self,start,end)
		if not wall.is_empty(): end = wall.position
		var contacts:Array[Dictionary] = SWEEP.contacts(source,start,end,HIT_RADIUS,{})
		contacts.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return start.distance_squared_to(a.point) < start.distance_squared_to(b.point))
		for contact:Dictionary in contacts:
			var victim:ball = contact.target
			if victim.get_world_2d() != get_world_2d() or not SubmissionCharacterTools.is_enemy(source,victim) or not victim.can_receive_control_from(source): continue
			if victim.get_instance_id() in get_meta("mc_pierce_ignore",[]): continue
			var decision:String = PROJECTILES.defense(self,victim,contact.point)
			if decision == "dodge": continue
			if decision in ["reflect","block"] or _spent or is_queued_for_deletion(): return
			if not victim.can_receive_negative_effects(): continue
			if not ENCHANTS.allow_projectile_hit(self,victim):
				if _spent: return
				continue
			if EFFECTS.apply_effect(victim,"slowness",2,SLOW_SECONDS,source):
				ENCHANTS.note_projectile_hit(self,victim)
			global_position = contact.point
			retire()
			return
		if not wall.is_empty():
			global_position = end
			retire()
			return
	global_position = end
	_emit_slime_trail(start,end)
	queue_redraw()
	if t >= 1.0: retire()
func _emit_slime_trail(start:Vector2,end:Vector2) -> void:
	var distance:float = start.distance_to(end)
	var along:float = 4.0-_trail_distance
	while along <= distance:
		if get_tree().get_nodes_in_group("MCZombieSlimeParticle").size() >= 192: break
		var fx:Sprite2D = PARTICLE.new()
		get_parent().add_child(fx)
		var texture := AtlasTexture.new()
		texture.atlas = SLIME_TEXTURE
		texture.region = Rect2(5,5,4,4)
		fx.frames = [texture]
		fx.setup(start.lerp(end,along/maxf(distance,0.001)),Vector2(_visual_rng.randf_range(-5,5),_visual_rng.randf_range(4,12)),0.38,1.0)
		fx.self_modulate = Color.WHITE
		fx.remove_from_group("MCEnderParticle")
		fx._pixel_width = 2.5
		fx.scale = Vector2.ONE*0.625
		fx.z_index = 7
		fx.add_to_group("MCZombieSlimeParticle")
		along += 4.0
	_trail_distance = fposmod(_trail_distance+distance,4.0)
func _draw() -> void:
	draw_texture_rect(SLIME_TEXTURE,Rect2(Vector2(-5,-5),Vector2(10,10)),false)
func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	if _spent: return {}
	return {"shape":"circle","position":global_position,"radius":HIT_RADIUS,"velocity":get_projectile_velocity(),"damage":0.0,"source":get_projectile_source(),"kind":"zombie_slime","control":true,"danger_duration":0.1}
func retire() -> void:
	if _spent: return
	_spent = true
	if is_multiplayer_authority(): queue_free()
	else: hide()
