extends ball
## 三废石投出的石块。投射物契约与雪球、羊驼口水一致：逐帧扫掠接触，走公共 hitbox 伤害
## （护盾、格挡、船载都照常生效），撞墙或飞完射程即碎，名字确定、权威端 RPC 生成。
## 外观是投掷者那种石头的小方块（自旋飞行），碎裂时迸出该石头的原版像素碎屑并播石质敲击声。
## 花岗岩石块命中后小幅击退并施加缓慢；闪长岩/安山岩的命中效果交给投掷者 on_stone_shard_hit 结算。
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const STATUS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const BLOCK_FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const STONE_AUDIO = preload("res://scripts/characters/我的世界/useless_stones/useless_stones_audio.gd")
const BLOCKS:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/useless_stones/granite_block.png"),
	preload("res://Images/characters/我的世界/useless_stones/diorite_block.png"),
	preload("res://Images/characters/我的世界/useless_stones/andesite_block.png"),
]
const FACES:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/useless_stones/granite.png"),
	preload("res://Images/characters/我的世界/useless_stones/diorite.png"),
	preload("res://Images/characters/我的世界/useless_stones/andesite.png"),
]
const GRANITE:int = 0
@export var stone_kind:int = 0
@export var life:float = 0.85
@export var knockback:float = 0.0
@export var knockback_speed:float = 170.0
@export var slowness_level:int = 0
@export var slowness_duration:float = 0.0
@export var spin_speed:float = 11.0
## 碎裂表现的像素尺度：原版 16px 贴图每像素在世界里的大小。
@export var fragment_pixel_scale:float = 0.32
var trio_id:int = -1
var hits:int = 0
var _spent:bool = false
var _resolving_hit:bool = false

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
	add_to_group(&"MCUselessStoneShard")
	add_to_group(&"BattleTransient")
	if image is Sprite2D: image.texture = BLOCKS[clampi(stone_kind,0,BLOCKS.size()-1)]

func _process(delta:float) -> void:
	if image != null and not _spent and is_combat_runtime_active(): image.rotation += spin_speed*delta*(1.0 if direction.x >= 0.0 else -1.0)

func owner_unit() -> ball:
	return Master if is_instance_valid(Master) else self

func enemy(target:Variant) -> bool:
	if not is_instance_valid(target) or not target is ball or target == self: return false
	var source:ball = owner_unit()
	if target == source: return false
	if source != self and source.has_method(&"stone_enemy"): return bool(source.call(&"stone_enemy",target))
	if target.is_queued_for_deletion() or target.health <= 0: return false
	if trio_id >= 0 and int(target.get_meta("mc_stone_trio",-1)) == trio_id: return false
	if target.Type not in [Ball_Type.Ball,Ball_Type.Creature]: return false
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
	var heading:Vector2 = direction.normalized()
	_resolving_hit = true
	super._on_hitbox_on_hit(hurt)
	_resolving_hit = false
	hits += 1
	var alive:bool = is_instance_valid(target) and not target.is_queued_for_deletion()
	var actual:float = maxf(before - (maxf(float(target.health),0.0) if alive else 0.0),0.0)
	if alive and target.health > 0 and actual > 0.0 and stone_kind == GRANITE:
		if knockback > 0.0:
			target.apply_knockback(heading,knockback*target.get_negative_effect_ratio(),knockback_speed,0.0,0.0,{"source":owner_unit(),"lock_control":false})
		if slowness_level > 0 and slowness_duration > 0.0:
			# 同一花岗岩只有一层缓慢：等级固定、不叠加，每次命中把剩余时间重置为满时长。
			STATUS.apply_effect(target,"slowness",slowness_level,slowness_duration,owner_unit())
	var shooter:ball = owner_unit()
	if shooter != self and shooter.has_method(&"on_stone_shard_hit"): shooter.call(&"on_stone_shard_hit",target if alive else null,actual)
	expire()

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
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0: _retire.rpc(global_position)
	_retire(global_position)

@rpc("authority","call_remote","reliable")
func _retire(point:Vector2) -> void:
	if _spent: return
	_spent = true
	_crumble(point)
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

## 石块碎成原版石头像素并伴随一声石质敲击；各端本地播放，序号取自确定的节点名。
func _crumble(point:Vector2) -> void:
	if not is_inside_tree(): return
	var kind:int = clampi(stone_kind,0,FACES.size()-1)
	var seed_value:int = absi(hash(str(name)))
	BLOCK_FRAGMENTS.spawn_texture(self,FACES[kind],point,fragment_pixel_scale,{"max_pieces":6,"scatter_radius":6.0,"arc_height_min":3.0,"arc_height_max":8.0,"flight_min":0.22,"flight_max":0.36,"ground_hold":0.12,"fade_time":0.22,"spin_speed":6.0,"seed":seed_value})
	STONE_AUDIO.play(self,STONE_AUDIO.HIT_SOUND,seed_value,point,1.0,{"keep_after_source":true,"volume_db":-7.0})
