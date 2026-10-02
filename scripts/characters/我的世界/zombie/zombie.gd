extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/zombie/zombie.tres")
const VOICE = preload("res://scripts/effects/我的世界/mc_creature_voice.gd")
const SOUNDS = preload("res://scripts/characters/我的世界/zombie/sounds.gd")
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const BITE = preload("res://scripts/characters/我的世界/zombie/bite.gd")
const COPY_SIZE = preload("res://scripts/characters/我的世界/haochen/copy_body_scale.gd")
const CHASE_RANGE:float = 180.0
const BITE_REACH:float = 28.0
const BITE_RADIUS:float = 10.0
const BITE_WINDUP:float = 0.14
var bite_cooldown:float = 0.0
var bite_left:float = -1.0
var bite_point:Vector2 = Vector2.ZERO
var bite_victim:WeakRef
var voice:Node
var _death_done:bool = false
var _serial:int = 0
var _received_bite:int = 0
var _gait:float = 0.0
var _idle_clock:float = 0.0
var _previous:Vector2
var _walking:bool = false
var _damage_regions:Array[Dictionary] = []
var _bite_fx:Node2D

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	_previous = global_position
	voice = VOICE.new()
	voice.name = "NativeVoice"
	voice.unit = self
	voice.events = SOUNDS.EVENTS
	add_child(voice)
	add_to_group("MinecraftZombie")
	set_process(true)

func body_frames() -> SpriteFrames: return FRAMES
func can_act() -> bool:
	return mc_live() and Can_Attack and not dizziness and not is_hard_controlled()
func mc_enemy(target:Variant) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false
	if not super.mc_enemy(target): return false
	if not Master_name.is_empty() and Master_name == target.Master_name: return false
	return true
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:int = State.Move
	if health <= 0: next = State.Die
	elif not is_combat_runtime_active() or dizziness: next = State.Stand
	return -1 if state == next else next
func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health > 0 and is_combat_runtime_active(): step_zombie(delta)
	super.tick_physics(state,delta)
func step_zombie(delta:float) -> void:
	_damage_regions.clear()
	bite_cooldown = maxf(0.0,bite_cooldown-delta)
	if not can_act():
		cancel_bite()
		return
	if bite_left >= 0.0:
		bite_left -= delta
		if bite_left <= 0.0:
			bite_left = -1.0
			resolve_bite()
	if is_player_controlled(): return
	var target:ball = mc_nearest(delta)
	if target == null: return
	var point:Vector2 = ball.body_point(target,global_position)
	if global_position.distance_to(point) <= CHASE_RANGE:
		direction = global_position.direction_to(point)
	if bite_cooldown <= 0.0: begin_bite(target)
func player_control_action_ids() -> Array[StringName]: return [&"controlled_attack_action"]
func controlled_attack_action() -> void:
	if not is_player_controlled(): return
	var aim:Vector2 = player_control_aim_world_position()
	var chosen:ball
	var best:float = INF
	for raw:Variant in SubmissionCharacterTools.targeting_candidates(self):
		if not mc_enemy(raw): continue
		var point:Vector2 = ball.body_point(raw,global_position)
		if global_position.distance_to(point) > bite_reach(): continue
		var distance:float = point.distance_squared_to(aim)
		if distance < best:
			best = distance
			chosen = raw
	begin_bite(chosen)
func Attack() -> void:
	if is_player_controlled(): controlled_attack_action()
func bite_reach() -> float: return BITE_REACH*COPY_SIZE.of(self)
func bite_radius() -> float: return BITE_RADIUS*COPY_SIZE.of(self)
func begin_bite(target:Variant) -> bool:
	if not can_act() or bite_left >= 0.0 or bite_cooldown > 0.0 or not mc_enemy(target): return false
	var point:Vector2 = ball.body_point(target,global_position)
	if global_position.distance_to(point) > bite_reach() or not mc_line_clear(global_position,point): return false
	bite_point = point
	bite_victim = weakref(target)
	bite_left = BITE_WINDUP
	bite_cooldown = maxf(Attack_Cooling,BITE_WINDUP+0.1)
	_serial += 1
	_receive_bite(_serial,point,bite_radius())
	if multiplayer.has_multiplayer_peer(): _receive_bite.rpc(_serial,point,bite_radius())
	return true
func resolve_bite() -> void:
	if not can_act(): return
	var victim:Variant = bite_victim.get_ref() if bite_victim != null else null
	if not mc_enemy(victim): return
	if global_position.distance_to(bite_point) > bite_reach()+bite_radius(): return
	_damage_regions.append({"shape":"circle","position":bite_point,"radius":bite_radius(),"damage":attack_damage(),"source":self,"kind":"zombie_bite"})
	for contact:Dictionary in SWEEP.contacts(self,bite_point,bite_point,bite_radius(),{},global_position):
		if contact.target != victim: continue
		victim.receive_classified_positional_damage(attack_damage(),contact.point,&"ordinary",false,self,{"carrier":"body_contact"})
		break
func cancel_bite() -> void:
	if bite_left < 0.0: return
	bite_left = -1.0
	bite_victim = null
	if multiplayer.has_multiplayer_peer(): _cancel_bite_visual.rpc(_serial)
	_cancel_bite_visual(_serial)
@rpc("authority","call_remote","reliable")
func _cancel_bite_visual(serial:int) -> void:
	if serial != _received_bite: return
	if is_instance_valid(_bite_fx): _bite_fx.queue_free()
@rpc("authority","call_remote","reliable")
func _receive_bite(serial:int,point:Vector2,radius:float) -> void:
	if serial <= _received_bite: return
	_received_bite = serial
	var fx:Node2D = BITE.new()
	get_parent().add_child(fx)
	fx.global_position = point
	fx.setup(self,BITE_WINDUP,0.0,{})
	fx.remove_from_group("MCEvokerFang")
	fx.add_to_group("MCZombieBite")
	fx.scale = Vector2.ONE*(radius/BITE_RADIUS)
	_bite_fx = fx
func get_ai_attack_threats() -> Array[Dictionary]:
	if bite_left < 0.0 or not can_act(): return []
	return [{"shape":"circle","position":bite_point,"radius":bite_radius(),"damage":attack_damage(),"source":self,"danger_delay":bite_left,"danger_duration":0.02,"kind":"zombie_bite"}]
func get_debug_attack_regions() -> Array[Dictionary]: return _damage_regions
func _process(delta:float) -> void:
	var moved:float = global_position.distance_to(_previous)
	_previous = global_position
	if health <= 0 or not is_combat_runtime_active() or get_tree().paused: return
	_idle_clock += delta
	_walking = not dizziness and moved > 0.02 and moved < 50.0
	if _walking: _gait += moved/30.0
	var frames:SpriteFrames = body_frames()
	var clip:StringName = &"walk" if _walking else &"idle"
	var index:int = int(_gait*frames.get_frame_count(clip)) if _walking else int(_idle_clock*frames.get_animation_speed(clip))
	image.texture = frames.get_frame_texture(clip,posmod(index,frames.get_frame_count(clip)))
	image.rotation = 0.0
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if amount > 0.0 and health > 0 and is_multiplayer_authority() and _mc_voice_rng.randf() < hurt_voice_chance:
		voice.request("hurt",global_position,-4.0)
func Die() -> void:
	if _death_done: return
	_death_done = true
	cancel_bite()
	if is_instance_valid(voice): voice.request("death",global_position,-4.0)
	mc_death_visual()
	super.Die()
func get_armor_test_effect_summary() -> String: return Game.t("MC_ARMOR_INTRO_ZOMBIE")
