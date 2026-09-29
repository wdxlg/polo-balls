extends ball
## 羊驼口水 (llama spit). Same projectile contract as the snow golem's snowball: swept contact
## test each frame, common hitbox damage (shields/blocks/boats respected), wall = expire,
## deterministic name + authority RPC spawn. Owner = the llama (Master), whose Master is the trader.
## Art: geometry.llamaspit + textures/entity/llama/spit.png baked by bake_wandering_trader.py.
## Vanilla look: the model turns to its flight direction (animation.llama_spit.setup) and the
## launch releases 7 spit smoke puffs along the shot (spit_smoke.gd). Impacts spawn nothing
## extra, as in vanilla (LlamaSpit.onHit only discards the entity).
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const SMOKE = preload("res://scripts/characters/我的世界/wandering_trader/spit_smoke.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const HIT_AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
@export var knockback:float = 6.0
@export var life:float = 2.2
var _spent:bool = false
var _resolving_hit:bool = false
var _impact_played:bool = false
var hits:int = 0

func _ready() -> void:
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
	health_bar.hide()
	collision_layer = 0
	self_hurtbox.collision_layer = 0
	self_hurtbox.collision_mask = 0
	self_hurtbox.set_deferred("monitorable",false)
	self_hurtbox.set_deferred("monitoring",false)
	self_hitbox.collision_layer = 0
	self_hitbox.collision_mask = 0
	self_hitbox.set_deferred("monitorable",false)
	self_hitbox.set_deferred("monitoring",false)
	add_to_group(&"MCLlamaSpit")
	add_to_group(&"BattleTransient")
	_face_flight()
	if direction.is_finite() and direction.length_squared() > 0.000001:
		SMOKE.emit_for_shot(self,global_position,direction.normalized()*maxf(Speed,0.0))

## Baked frame faces LEFT; turn it so the model points along the flight direction.
func _face_flight() -> void:
	if image == null or not direction.is_finite() or direction.length_squared() <= 0.000001: return
	image.rotation = direction.angle() - PI

func owner_unit() -> ball:
	return Master if is_instance_valid(Master) else self

func enemy(target:Variant) -> bool:
	var source:ball = owner_unit()
	if target == source or target == self: return false
	if source.has_method(&"wt_enemy"): return bool(source.call(&"wt_enemy",target))
	return U.enemy(source,target)

func tick_physics(state:State,delta:float) -> void:
	if _spent or not is_multiplayer_authority(): return
	if health <= 0 or state == State.Die:
		expire()
		return
	if not is_combat_runtime_active(): return
	if Speed <= 0.0 or not direction.is_finite() or direction.length_squared() <= 0.000001 or dizziness:
		expire()
		return
	life -= delta
	if life <= 0.0:
		expire()
		return
	super.tick_physics(state,delta)

static func contact_t(from:Vector2,to:Vector2,center:Vector2,radius:float) -> float:
	var offset:Vector2 = from - center
	if offset.length_squared() <= radius*radius: return 0.0
	var segment:Vector2 = to - from
	var a:float = segment.length_squared()
	if a <= 0.000001: return -1.0
	var b:float = offset.dot(segment)
	var discriminant:float = b*b - a*(offset.length_squared() - radius*radius)
	if discriminant < 0.0: return -1.0
	var t:float = (-b - sqrt(discriminant))/a
	return t if t >= 0.0 and t <= 1.0 else -1.0

func move(speed:float,delta:float) -> void:
	if _spent or delta <= 0.0: return
	var from:Vector2 = global_position
	velocity = direction*maxf(speed,0.0) + Repel
	_face_flight()
	var to:Vector2 = from + velocity*delta
	var wall:Dictionary = U.trace(self,from,to)
	if not wall.is_empty(): to = wall.position
	if get_tree().has_group("MinecraftAllay"):
		var capture:Script = load("res://scripts/characters/我的世界/allay/capture.gd")
		if capture.sweep(self,from,to): return
	var candidates:Array[Dictionary] = []
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not enemy(candidate): continue
		var target:ball = candidate as ball
		var t:float = contact_t(from,to,ball.body_point_seg(target,from,to),U.radius(target) + 2.0)
		if t >= 0.0: candidates.append({"target":target,"t":t})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return float(a.t) < float(b.t))
	for hit:Dictionary in candidates:
		var target:Variant = hit.target
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		global_position = from.lerp(to,float(hit.t))
		self_hitbox.try_hit_hurtbox(target.self_hurtbox)
		if _spent or is_queued_for_deletion(): return
	global_position = to
	if not wall.is_empty(): expire()

func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if _spent or _resolving_hit or not is_multiplayer_authority(): return
	var target:ball = _hurtbox_target_ball(hurt)
	if not enemy(target): return
	var before:float = maxf(float(target.health),0.0)
	var point:Vector2 = ball.body_point(target,global_position)
	var heading:Vector2 = direction
	_resolving_hit = true
	super._on_hitbox_on_hit(hurt)
	_resolving_hit = false
	hits += 1
	var remaining:float = maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0
	var actual:float = maxf(before - remaining,0.0)
	if is_instance_valid(target) and target.health > 0 and actual > 0.0:
		target.apply_knockback(heading,knockback*target.get_negative_effect_ratio(),120.0,0.0,0.0,{"source":owner_unit(),"lock_control":false})
	impact_sound(actual,point)
	expire()

func impact_sound(actual:float,point:Vector2) -> void:
	if _impact_played or actual <= 0.0: return
	_impact_played = true
	# Through the llama (it outlives the spit and syncs the sound to peers); new5 table as fallback.
	var shooter:Node = owner_unit()
	if is_instance_valid(shooter) and shooter.has_method(&"wt_hit_sound"): shooter.call(&"wt_hit_sound",actual,point)
	else: HIT_AUDIO.play(self,HIT_GAIN.damage_event(actual),point,HIT_GAIN.damage_gain(actual),false,true,true,true)

func can_receive_hit_contact(_incoming:hitbox,_contact:hurtbox) -> bool: return false
func can_receive_hit_from(_incoming:hitbox) -> bool: return false
func on_incoming_hit_rejected(_incoming:hitbox) -> void: pass
func should_destroy_projectile_on_rejected_hit(_incoming:hitbox) -> bool: return false

func on_projectile_blocked_by(target:ball,_point:Vector2) -> void:
	if _spent or not is_multiplayer_authority(): return
	if is_instance_valid(target) and not enemy(target): return
	expire()

func Die() -> void: expire()
func when_collide(_speed:float,_collision:KinematicCollision2D) -> void: expire()
func expire() -> void:
	if _spent: return
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0: _retire.rpc()
	_retire()

@rpc("authority","call_remote","reliable")
func _retire() -> void:
	if _spent: return
	_spent = true
	hide()
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	self_hitbox.set_deferred("monitoring",false)
	self_hitbox.set_deferred("monitorable",false)
	self_hurtbox.set_deferred("monitoring",false)
	self_hurtbox.set_deferred("monitorable",false)
	state_machine.set_physics_process(false)
	queue_free()
