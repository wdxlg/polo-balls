extends "res://scripts/effects/physical_airborne_effect.gd"
## Iron Golem specialization: the shared physical airborne controller owns flight;
## only landing damage, MC audio, particles and team policy live here.
const MCB:Script = preload("res://scripts/characters/我的世界/mc_mob_base.gd")
const LANDING_AUDIO:Script = preload("res://scripts/characters/我的世界/iron_golem/landing_audio.gd")
const IMPACT:Script = preload("res://scripts/characters/我的世界/iron_golem/landing_impact.gd")
var owner_team:String = ""
var owner_id:int = 0
var excluded_ids:Array[int] = []
var damage_power:float = 1.0
var _visual_landed:bool = false
var _damage_settled:bool = false

func _ready() -> void:
	height_meta_key = &"golem_air_height"
	add_to_group("GolemAirborne")
	super._ready()

func relaunch(apex:float,up_speed:float,stun:float) -> void:
	_visual_landed = false
	_damage_settled = false
	super.relaunch(apex,up_speed,stun)

func landing_radius() -> float: return 24.0+minf(peak_height,240.0)*0.12
func landing_damage() -> float: return peak_height*0.25*damage_power
func landing_push() -> float: return minf(3.0+peak_height*0.06,14.0)

func _on_landing(point:Vector2) -> void:
	var sound_index:int = LANDING_AUDIO.variant(peak_height)
	if multiplayer.has_multiplayer_peer(): _land_visual.rpc(point,landing_radius(),peak_height,sound_index)
	_land_visual(point,landing_radius(),peak_height,sound_index)
	landing_hits = damage_landing(point)

func is_landing_enemy(candidate:Variant,include_victim:bool=false) -> bool:
	if not is_instance_valid(candidate) or not candidate is ball: return false
	if candidate==target and not include_victim: return false
	if candidate.is_queued_for_deletion() or candidate.health<=0 or not candidate.is_combat_targetable(): return false
	if candidate.Type not in [ball.Ball_Type.Ball,ball.Ball_Type.Creature]: return false
	if excluded_ids.has(candidate.get_instance_id()): return false
	if is_instance_valid(source): return source.mc_enemy(candidate)
	return Game.Game_Settings.Have_Team_Damage or owner_team.is_empty() or candidate.Team!=owner_team

func overlaps_ground_circle(candidate:ball,center:Vector2,radius:float) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = radius
	for node:Node in candidate.self_hurtbox.find_children("*","CollisionShape2D",true,false):
		var shape:CollisionShape2D = node as CollisionShape2D
		if not shape.disabled and shape.shape!=null and circle.collide(Transform2D(0,center),shape.shape,shape.global_transform): return true
	return false

func damage_landing(center:Vector2) -> int:
	if not landed or _finished or _damage_settled or not is_multiplayer_authority() or not _target_is_usable() or not target.is_combat_runtime_active(): return 0
	_damage_settled = true
	if is_instance_valid(source) and source.is_damage_output_disabled(): return 0
	var hits:int = 0
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not is_landing_enemy(node): continue
		var candidate:ball = node as ball
		if not overlaps_ground_circle(candidate,center,landing_radius()): continue
		var ray := PhysicsRayQueryParameters2D.create(center,candidate.global_position,1,[target.get_rid()])
		if not target.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var applied:bool = _apply_landing_damage(candidate,center)
		if applied:
			hits += 1
			if is_instance_valid(candidate) and candidate.health>0:
				var push:Vector2 = center.direction_to(ball.body_point(candidate,center))
				if push.is_zero_approx(): push = Vector2.RIGHT
				candidate.apply_knockback(push,landing_push(),120.0,0.0,0.0,{"source":source if is_instance_valid(source) else null,"stop_on_character":true})
	# The launched victim takes one direct fall hit, separately from the AOE.
	# No overlap/LOS test or outward knockback on itself. Settle it last so a
	# lethal fall does not cancel the shock already produced by this landing.
	if is_landing_enemy(target,true) and _apply_landing_damage(target,center): hits += 1
	return hits

func _apply_landing_damage(candidate:ball,center:Vector2) -> bool:
	var applied:bool = false
	if is_instance_valid(source):
		applied = source.mc_damage_with_impact(candidate,landing_damage(),center)
	else:
		# A launched enemy still lands after the golem is removed. Reuse shared
		# event/gain functions; only kill attribution is unavailable without owner.
		var before:float = maxf(candidate.health,0.0)
		var point:Vector2 = candidate.global_position
		applied = candidate.receive_positional_damage(landing_damage(),center,false,null)
		var after:float = maxf(candidate.health,0.0) if is_instance_valid(candidate) else 0.0
		var actual:float = maxf(before-after,0.0)
		if actual>0.0:
			if multiplayer.has_multiplayer_peer(): _hit_audio.rpc(MCB.mc_impact_event(actual),point,MCB.mc_impact_volume(actual))
			_hit_audio(MCB.mc_impact_event(actual),point,MCB.mc_impact_volume(actual))
	return applied

@rpc("authority","call_remote","reliable")
func _hit_audio(event:String,point:Vector2,gain:float) -> void:
	var player:AudioStreamPlayer2D = preload("res://scripts/characters/我的世界/new5/audio.gd").play(self,event,point,gain,false,true,true,true)
	if is_instance_valid(player): player.set_meta("mc_damage_source",owner_id)

@rpc("authority","call_remote","reliable")
func _land_visual(point:Vector2,radius:float,actual_height:float = -1.0,sound_index:int = -1) -> void:
	if _visual_landed: return
	_visual_landed = true
	LANDING_AUDIO.play(self,point,peak_height if actual_height<0.0 else actual_height,sound_index)
	landed = true
	height = 0.0
	_apply_height()
	var world:Node = get_tree().current_scene
	if world==null: return
	var effect:Node2D = IMPACT.new()
	world.add_child(effect)
	effect.add_to_group("BattleTransient")
	effect.add_to_group("GolemLandingImpact")
	effect.setup(point,radius)
