extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## 河豚 / 热带鱼 released from the trader's bucket (docs/WANDERING_TRADER.md "物品").
## * Killable summon (Type Creature, Master = trader, his team): no victory weight.
## * Out of water it flops: gravity pulls it to the floor (bottom of the arena, as for the anvil),
##   every landing throws it up again with a random medium jump. Horizontal speed like the anvil:
##   constant left/right drive that bounces off characters, obstacles and the arena walls.
## * The body tumbles freely: each landing / bounce kicks its spin and gravity swings it.
## * 河豚 (puffer = true, 50 HP): puffs up when an enemy is near; touching an enemy stings it
##   (damage + Poison). 热带鱼 (puffer = false, 75 HP): on the trader's team; ramming an enemy deals
##   collision damage that scales with the fish's own speed (user rule 2026-09-29).
## * Never dries out (user rule 2026-09-29: nothing of his disappears on its own). dry_time > 0
##   would restore the vanilla suffocation.
const AUDIO = preload("res://scripts/characters/我的世界/wandering_trader/audio.gd")
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
const CRUMBS = preload("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd")
const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")
@export var puffer:bool = true
@export_category("鱼 / 弹跳")
@export var gravity_acceleration:float = 900.0
@export var terminal_speed:float = 700.0
@export var hop_speed_min:float = 210.0
@export var hop_speed_max:float = 320.0
@export var drift_speed_min:float = 40.0
@export var drift_speed_max:float = 70.0
@export_category("鱼 / 河豚")
@export var sting_damage:float = 10.0
@export var puffed_sting_damage:float = 14.0
@export var sting_cooldown:float = 0.7
@export var poison_time:float = 4.0
@export var puff_radius:float = 34.0
@export var dry_time:float = 0.0 # 0 = never dries out
@export_category("鱼 / 热带鱼撞击")
@export var ram_min_speed:float = 60.0 # own speed below this: no damage (a slow drift is harmless)
@export var ram_damage_per_speed:float = 0.05 # 300 px/s hop = 15
@export var ram_damage_max:float = 22.0
@export var ram_cooldown:float = 0.5
@export var ram_knockback:float = 0.04 # knockback px per px/s of own speed

var fall_velocity:Vector2 = Vector2.ZERO
var spin:float = 0.0
var puffed:bool = false
var puff_visual:float = 0.0
var hops:int = 0
var bounces:int = 0
var stings:int = 0
var rams:int = 0
var last_ram_damage:float = 0.0
var alive_time:float = 0.0
var _puff_hold:float = 0.0
var _sting_wait:Dictionary = {}
var _flop_wait:float = 0.0
var _retired:bool = false
var _rest_scale:Vector2 = Vector2.ONE

func _ready() -> void:
	Type = Ball_Type.Creature
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	Has_Collision_Damage = false
	side_status_ui_enabled = false
	hurt_voice_chance = 0.9
	mc_audio_role = "wt_pufferfish" if puffer else "wt_tropical_fish"
	super._ready()
	collision_layer = 2
	collision_mask = 3
	if image != null: _rest_scale = image.scale
	add_to_group(&"MCTraderFish")
	# Contact damage is the sting below (with Poison); the inherited body hitbox must not add a second hit.
	var contact:Area2D = get_node_or_null(^"hitbox") as Area2D
	if contact != null: contact.set_deferred(&"monitoring",false)
	var sign_x:float = -1.0 if _mc_rng.randf() < 0.5 else 1.0
	if direction.x != 0.0: sign_x = signf(direction.x)
	fall_velocity = Vector2(sign_x*_mc_rng.randf_range(drift_speed_min,drift_speed_max),-_mc_rng.randf_range(hop_speed_min,hop_speed_max)*0.6)
	spin = _mc_rng.randf_range(-6.0,6.0)

func has_collision_damage() -> bool: return false
func trader() -> Node:
	return Master if is_instance_valid(Master) and not Master.is_queued_for_deletion() else null

# ------------------------------------------------------------------ audio
func wt_sound(event:StringName,volume:float = 0.0,pitch:float = -1.0) -> AudioStreamPlayer2D:
	var index:int = AUDIO.variant(event)
	var p:float = pitch if pitch > 0.0 else _mc_voice_rng.randf_range(0.9,1.1)
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_wt_sound_remote.rpc(event,index,global_position,volume,p)
	return AUDIO.play(self,event,global_position,volume,p,index)

@rpc("authority","call_remote","unreliable")
func _wt_sound_remote(event:StringName,index:int,point:Vector2,volume:float,pitch:float) -> void:
	AUDIO.play(self,event,point,volume,pitch,index)

func mc_play(event:String,_volume:float = -4.0) -> AudioStreamPlayer2D:
	match event:
		"hurt": return wt_sound(&"puffer_hurt" if puffer else &"fish_hurt")
		"death": return wt_sound(&"puffer_death" if puffer else &"fish_hurt",0.0,-1.0 if puffer else 0.8)
	return null
func mc_ambient_event() -> String: return ""

# ------------------------------------------------------------------ physics
func move(_speed:float,delta:float) -> void: _fish_step(delta)
func stand(delta:float) -> void: _fish_step(delta)

func arena_bounds() -> Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method(&"_current_map_node"): return Rect2()
	var map:Node = world.call(&"_current_map_node")
	if map == null: return Rect2()
	if map.has_method(&"island_entries"):
		var best:Rect2
		var distance:float = INF
		for entry:Dictionary in map.call(&"island_entries"):
			var rect:Rect2 = entry.rect
			if rect.has_point(global_position): return rect
			var d:float = global_position.distance_squared_to(global_position.clamp(rect.position,rect.end))
			if d < distance:
				distance = d
				best = rect
		return best
	return world.call(&"return_map_world_rect",map) if world.has_method(&"return_map_world_rect") else Rect2()

func body_half_size() -> Vector2:
	var body:CollisionShape2D = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if body == null or body.shape == null: return Vector2(6,6)
	return body.shape.get_rect().size*body.global_scale.abs()*0.5

func _fish_step(delta:float) -> void:
	if _retired or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active(): return
	var remaining:float = maxf(delta,0.0)
	for _guard:int in range(64):
		if remaining <= 0.000001: break
		var dt:float = minf(remaining,1.0/120.0)
		remaining -= dt
		_substep(dt)
	velocity = fall_velocity
	Repel = Repel.move_toward(Vector2.ZERO,600.0*delta)

func _substep(dt:float) -> void:
	fall_velocity.y = minf(fall_velocity.y + gravity_acceleration*dt,terminal_speed)
	var motion:Vector2 = (fall_velocity + Repel)*dt
	var bounds:Rect2 = arena_bounds()
	var half:Vector2 = body_half_size()
	var floor_hit:bool = false
	var side:float = 0.0
	if bounds.size.x > half.x*2.0 and bounds.size.y > half.y*2.0:
		var wanted:Vector2 = global_position + motion
		if wanted.y >= bounds.end.y - half.y:
			motion.y = maxf(bounds.end.y - half.y - global_position.y,0.0)
			floor_hit = true
		elif wanted.y <= bounds.position.y + half.y and fall_velocity.y < 0.0:
			motion.y = minf(bounds.position.y + half.y - global_position.y,0.0)
			fall_velocity.y = absf(fall_velocity.y)*0.3
		if wanted.x <= bounds.position.x + half.x and motion.x < 0.0:
			motion.x = minf(bounds.position.x + half.x - global_position.x,0.0)
			side = 1.0
		elif wanted.x >= bounds.end.x - half.x and motion.x > 0.0:
			motion.x = maxf(bounds.end.x - half.x - global_position.x,0.0)
			side = -1.0
	var collision:KinematicCollision2D = move_and_collide(motion,false,0.001,false)
	if collision != null:
		var normal:Vector2 = collision.get_normal()
		var other:Object = collision.get_collider()
		if absf(normal.x) > 0.5 and fall_velocity.x*normal.x < 0.0: side = signf(normal.x)
		if normal.y < -0.5: floor_hit = true
		elif normal.y > 0.5 and fall_velocity.y < 0.0: fall_velocity.y = absf(fall_velocity.y)*0.3
		if other is ball: _touch(other as ball)
		if side != 0.0:
			_last_requested_velocity = fall_velocity
			when_collide(absf(fall_velocity.x),collision)
	if side != 0.0:
		fall_velocity.x = side*absf(fall_velocity.x)
		direction = Vector2(side,0.0)
		spin += side*_mc_rng.randf_range(2.0,5.0)
		bounces += 1
		if collision == null: notify_bounce_feedback(Vector2(-side,0.0),absf(fall_velocity.x))
	if floor_hit and fall_velocity.y > 0.0: _land()
	# Free tumble: spin decays, gravity swings the nose toward the fall direction.
	spin = move_toward(spin,0.0,1.2*dt)
	if image != null:
		var fall_angle:float = atan2(fall_velocity.y,absf(fall_velocity.x) + 1.0)*signf(fall_velocity.x if fall_velocity.x != 0.0 else 1.0)
		spin += angle_difference(image.rotation,fall_angle)*2.5*dt
		image.rotation = wrapf(image.rotation + spin*dt,-PI,PI)

func _land() -> void:
	hops += 1
	fall_velocity.y = -_mc_rng.randf_range(hop_speed_min,hop_speed_max)
	var sign_x:float = signf(fall_velocity.x) if fall_velocity.x != 0.0 else (-1.0 if _mc_rng.randf() < 0.5 else 1.0)
	fall_velocity.x = sign_x*_mc_rng.randf_range(drift_speed_min,drift_speed_max)
	spin += _mc_rng.randf_range(-7.0,7.0)
	if _flop_wait <= 0.0:
		_flop_wait = 0.35
		wt_sound(&"puffer_flop" if puffer else &"fish_flop",-4.0)

# ------------------------------------------------------------------ puffer
func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if _retired or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active(): return
	alive_time += delta
	_flop_wait -= delta
	for id:Variant in _sting_wait.keys():
		_sting_wait[id] = float(_sting_wait[id]) - delta
		if float(_sting_wait[id]) <= 0.0: _sting_wait.erase(id)
	if dry_time > 0.0 and alive_time >= dry_time:
		health = 0
		retire()
		return
	if puffer: _tick_puffer(delta)
	else: _tick_ram()

func fish_enemy(target:Variant) -> bool:
	var boss:Node = trader()
	if boss != null and boss.has_method(&"wt_enemy"): return bool(boss.call(&"wt_enemy",target))
	return mc_enemy(target)

func _tick_puffer(delta:float) -> void:
	var near:bool = false
	var mine:Rect2 = CATALOG.body_rect(self).grow(1.5)
	for unit:ball in CATALOG.units(self):
		if unit == self or not fish_enemy(unit): continue
		var rect:Rect2 = CATALOG.body_rect(unit)
		if rect.intersects(mine): _touch(unit)
		if ball.body_point(unit,global_position).distance_to(global_position) <= puff_radius: near = true
	if near:
		_puff_hold = 1.5
		if not puffed: _set_puffed(true)
	else:
		_puff_hold -= delta
		if puffed and _puff_hold <= 0.0: _set_puffed(false)

func _set_puffed(on:bool) -> void:
	puffed = on
	wt_sound(&"puffer_blow_up" if on else &"puffer_blow_out",-3.0)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _puff_remote.rpc(on)

@rpc("authority","call_remote","reliable")
func _puff_remote(on:bool) -> void: puffed = on

## 热带鱼: overlap check each tick (move_and_collide only reports the bodies it runs into).
func _tick_ram() -> void:
	var mine:Rect2 = CATALOG.body_rect(self).grow(1.5)
	for unit:ball in CATALOG.units(self):
		if unit == self or not fish_enemy(unit): continue
		if CATALOG.body_rect(unit).intersects(mine): _ram(unit)

func ram_damage(speed:float) -> float:
	if speed < ram_min_speed: return 0.0
	return minf(speed*ram_damage_per_speed,ram_damage_max)

func _ram(unit:ball) -> void:
	if not fish_enemy(unit) or is_damage_output_disabled(): return
	var id:int = unit.get_instance_id()
	if _sting_wait.has(id): return
	var speed:float = fall_velocity.length()
	var amount:float = ram_damage(speed)
	if amount <= 0.0: return
	_sting_wait[id] = ram_cooldown
	var boss:Node = trader()
	var before:float = maxf(float(unit.health),0.0)
	unit.receive_positional_damage(amount,unit.global_position,false,self)
	var actual:float = before - (maxf(float(unit.health),0.0) if is_instance_valid(unit) else 0.0)
	last_ram_damage = actual
	rams += 1
	if actual > 0.0 and boss != null and boss.has_method(&"wt_hit_sound"): boss.call(&"wt_hit_sound",actual,unit.global_position)
	if is_instance_valid(unit) and unit.health > 0 and unit.can_receive_negative_effects():
		var push:Vector2 = fall_velocity.normalized() if speed > 0.01 else global_position.direction_to(ball.body_point(unit,global_position))
		unit.apply_knockback(push,speed*ram_knockback*unit.get_negative_effect_ratio(),260.0,0.0,0.0,{"source":self,"lock_control":false})

func _touch(unit:ball) -> void:
	if not puffer:
		_ram(unit)
		return
	if not fish_enemy(unit) or is_damage_output_disabled(): return
	var id:int = unit.get_instance_id()
	if _sting_wait.has(id): return
	_sting_wait[id] = sting_cooldown
	var boss:Node = trader()
	var amount:float = puffed_sting_damage if puffed else sting_damage
	var before:float = maxf(float(unit.health),0.0)
	unit.receive_positional_damage(amount,unit.global_position,false,self)
	var actual:float = before - (maxf(float(unit.health),0.0) if is_instance_valid(unit) else 0.0)
	if actual > 0.0 and boss != null and boss.has_method(&"wt_hit_sound"): boss.call(&"wt_hit_sound",actual,unit.global_position)
	if is_instance_valid(unit) and unit.health > 0: POTION_EFFECTS.apply_effect(unit,"poison",self,1,poison_time)
	stings += 1
	wt_sound(&"puffer_sting",-2.0)

func _process(delta:float) -> void:
	puff_visual = move_toward(puff_visual,1.0 if puffed else 0.0,delta*6.0)
	if image != null: image.scale = _rest_scale*(1.0 + 0.4*puff_visual)

# ------------------------------------------------------------------ death
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _retired: return
	super.take_damage(damage,ignore_block)
	if health <= 0: retire()

func retire() -> void:
	if _retired: return
	_retired = true
	if is_multiplayer_authority(): mc_play("death")
	mc_death_visual()
	var boss:Node = trader()
	if boss != null and boss.has_method(&"wt_on_fish_lost"): boss.call(&"wt_on_fish_lost",self)
	hide()
	collision_layer = 0
	collision_mask = 0
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	if self_hurtbox != null: self_hurtbox.set_deferred("monitorable",false)
	for group:StringName in [&"Ball",&"MCTraderFish"]:
		if is_in_group(group): remove_from_group(group)
	queue_free()

func owner_lost() -> void:
	if _retired: return
	health = 0
	retire()

func Die() -> void: retire()

func is_combat_targetable() -> bool:
	if _retired or health <= 0 or is_queued_for_deletion(): return false
	return state_machine == null or state_machine.current_state != State.Die
