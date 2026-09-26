extends ball
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const RULES = preload("res://scripts/characters/我的世界/snow_golem/rules.gd")
const COLD = preload("res://scripts/characters/我的世界/snow_golem/cold.gd")
const AUDIO = preload("res://scripts/characters/我的世界/snow_golem/audio.gd")
@export var cold_gain:float = 22.0
@export var freeze_duration:float = 1.4
@export var snow_knockback:float = 8.0
@export var life:float = 3.2
var _spent:bool = false
var _resolving_hit:bool = false
var _impact_played:bool = false

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
	# ball._ready() adds an incoming damage layer to every Hurtbox. Undo it:
	# this disposable projectile has no HP/defense surface for other bullets.
	collision_layer = 0
	self_hurtbox.collision_layer = 0
	self_hurtbox.collision_mask = 0
	self_hurtbox.set_deferred("monitorable",false)
	self_hurtbox.set_deferred("monitoring",false)
	# Contacts are already swept in move(); an automatic Area overlap would
	# run projectile-vs-projectile defense hooks before our target filter.
	self_hitbox.collision_layer = 0
	self_hitbox.collision_mask = 0
	self_hitbox.set_deferred("monitorable",false)
	self_hitbox.set_deferred("monitoring",false)
	add_to_group("MCSnowball")
	add_to_group("BattleTransient")
	image.rotation = 0.0

func tick_physics(state:State,delta:float) -> void:
	if _spent or not is_multiplayer_authority(): return
	# Death/rejected contacts must retire even if the battle stops this frame.
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
	var offset:Vector2 = from-center
	if offset.length_squared() <= radius*radius: return 0.0
	var segment:Vector2 = to-from
	var a:float = segment.length_squared()
	if a <= 0.000001: return -1.0
	var b:float = offset.dot(segment)
	var discriminant:float = b*b-a*(offset.length_squared()-radius*radius)
	if discriminant < 0.0: return -1.0
	var t:float = (-b-sqrt(discriminant))/a
	return t if t >= 0.0 and t <= 1.0 else -1.0

func move(speed:float,delta:float) -> void:
	if _spent or delta <= 0.0: return
	var from:Vector2 = global_position
	velocity = direction*maxf(speed,0.0)+Repel
	var to:Vector2 = from+velocity*delta
	var wall:Dictionary = U.trace(self,from,to)
	if not wall.is_empty(): to = wall.position
	if get_tree().has_group("MinecraftAllay"):
		var capture:Script = load("res://scripts/characters/我的世界/allay/capture.gd")
		if capture.sweep(self,from,to): return
	var owner_unit:ball = Master if is_instance_valid(Master) else self
	var hits:Array[Dictionary] = []
	for candidate:Node in get_tree().get_nodes_in_group("Ball"):
		if not RULES.enemy(owner_unit,candidate) or candidate == self: continue
		var target:ball = candidate as ball
		var t:float = contact_t(from,to,target.global_position,U.radius(target)+3.0)
		if t >= 0.0: hits.append({"target":target,"t":t})
	hits.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return float(a.t) < float(b.t))
	for hit:Dictionary in hits:
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
	var owner_unit:ball = Master if is_instance_valid(Master) else self
	if not RULES.enemy(owner_unit,target): return
	var before:float = maxf(float(target.health),0.0)
	var point:Vector2 = target.global_position
	var impact_heading:Vector2 = direction
	_resolving_hit = true
	super._on_hitbox_on_hit(hurt)
	_resolving_hit = false
	var remaining:float = maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0
	var actual:float = maxf(before-remaining,0.0)
	if is_instance_valid(target) and target.health > 0 and actual > 0.0 and target.can_receive_negative_effects():
		if target.can_receive_cold_status(): COLD.ensure(target).add_cold(cold_gain,freeze_duration,owner_unit)
		target.apply_knockback(impact_heading,snow_knockback*target.get_negative_effect_ratio(),100.0,0.0,0.0,{"source":owner_unit,"lock_control":false})
	# The common hit callback already reports direct Allay-owned hits once.
	var allay_reported:bool = is_instance_valid(Master) and Master.is_in_group("MinecraftAllay")
	impact_sound(0.0 if allay_reported else actual,point)
	expire()

func impact_sound(actual:float,point:Vector2) -> void:
	if _impact_played: return
	_impact_played = true
	var field:Node = get_tree().current_scene.get_node_or_null("MCSnowField")
	if is_instance_valid(field) and not field.is_queued_for_deletion(): field.emit_impact(actual,point,true)
	else: AUDIO.play_impact(self,actual,point,true)

# Snowballs are NOT defensive entities. Even an explicit legacy hitbox call
# must pass through, without killing/reflecting the incoming bullet.
func can_receive_hit_contact(_incoming:hitbox,_contact:hurtbox) -> bool: return false
func can_receive_hit_from(_incoming:hitbox) -> bool: return false
func on_incoming_hit_rejected(_incoming:hitbox) -> void: pass
func should_destroy_projectile_on_rejected_hit(_incoming:hitbox) -> bool: return false

func on_projectile_blocked_by(target:ball,point:Vector2) -> void:
	if _spent or not is_multiplayer_authority(): return
	var owner_unit:ball = Master if is_instance_valid(Master) else self
	if is_instance_valid(target) and not RULES.enemy(owner_unit,target): return
	# Partial shield absorption re-enters here inside super's hit callback;
	# let that callback finish computing real HP loss before selecting audio.
	if not _resolving_hit: impact_sound(0.0,point)
	expire()

func Die() -> void: expire()
func when_collide(_speed:float,_collision:KinematicCollision2D) -> void: expire()
func expire() -> void:
	if _spent: return
	if is_multiplayer_authority() and multiplayer.get_peers().size() > 0: _retire.rpc()
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
