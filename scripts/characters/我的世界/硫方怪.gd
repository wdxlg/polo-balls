extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## Minecraft 26.2 Sulfur Cube. The official block archetypes are adapted to
## auto-cycling PvP: the block is visible INSIDE the original translucent shell.
const AUDIO = preload("res://scripts/characters/我的世界/sulfur_cube_audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const MODEL = preload("res://scripts/characters/我的世界/sulfur_cube_model.gd")
const ICE_TRAIL = preload("res://scripts/effects/我的世界/sulfur_ice_trail.gd")
const BURN = preload("res://scripts/effects/我的世界/mc_shared_burn.gd")
const SHARD = preload("res://scripts/effects/我的世界/sulfur_amethyst_shard.gd")
const FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const CRYSTAL_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/amethyst_cluster.png")
const CRYSTAL_DIRECTIONS:Array[Vector2] = [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]

enum Block { EMPTY, ICE, MAGMA, HONEY, IRON, TNT, AMETHYST }
const SPRITES:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/sulfur_cube/empty.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/ice.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/magma.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/honey.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/iron.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/tnt.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/empty.png"),
]
const MODE_HITS:Array[StringName] = [
	&"", &"ice_hit", &"magma_hit", &"honey_hit", &"iron_hit", &"tnt_hit", &"amethyst_hit"
]
const TNT_RADIUS:float = 80.0
const TNT_FUSE_SECONDS:float = 2.4
const TNT_DAMAGE:float = 150.0
const TNT_SELF_DAMAGE:float = 60.0
const CONTACT_INTERVAL:float = 0.62
const HOT_INTERVAL:float = 0.16
const CRYSTAL_RADIUS:float = 3.0
const CRYSTAL_VOLLEY_TIME:float = 2.4
const CRYSTAL_REGROW_TIME:float = 0.8

# This property, plus fuse_left, is replicated by the scene's synchronizer.
@export var block_mode:int = Block.EMPTY:
	set(value):
		block_mode = clampi(value,Block.EMPTY,Block.AMETHYST)
		if is_node_ready():
			_apply_visual()
			queue_redraw()
@export var fuse_left:float = 0.0
@export var crystals_out:bool = false:
	set(value):
		crystals_out = value
		if is_instance_valid(_native_model): _native_model.set_crystals_active(block_mode == Block.AMETHYST and not value)
@export var first_block_delay:float = 0.65

var _clock:float = 0.0
var _view_clock:float = 0.0
var _ring_refresh:float = 0.0
var _opening:float = 0.0
var _scan_left:float = 0.0
var _next_hit_at:Dictionary = {} # instance ID -> next time; cleared at each change
var _slide_velocity:Vector2 = Vector2.ZERO
var _actual_speed:float = 0.0
var _ice_reference_speed:float = 78.0
var _last_move_direction:Vector2 = Vector2.ZERO
var _recoil_velocity:Vector2 = Vector2.ZERO
var _ice_cells:Dictionary = {}
var _top_hit_at:Dictionary = {}
@export var _slam_time:float = -1.0 # Replicated so the guest threat overlay follows the real descent.
var _slam_start:Vector2
var _slam_end:Vector2
var _slam_target_ref:WeakRef
var _slam_saved_mask:int = 0
var _slam_hits:Dictionary = {}
var _crystal_timer:float = CRYSTAL_VOLLEY_TIME
var _random := RandomNumberGenerator.new()
var _surge_left:float = 0.0
var _hop_timer:float = 0.18
var _landing_wait:float = -1.0
var _sound_time:Dictionary = {}
var _sound_duration_ms:Dictionary = {}
var _motion_audio_until_ms:int = 0
var _motion_audio_player:AudioStreamPlayer2D
var _previous_motion_position:Vector2
var _motion_sample_valid:bool = false
var _sulfur_died:bool = false
var _model_viewport:SubViewport
var _native_model:Node3D

func _ready() -> void:
	mc_audio_role = "sulfur_cube" # No borrowed Slime voices or animation frames.
	Has_Collision_Damage = false
	Hit_Audio = ""
	# The native creature death voice supplements, never replaces, the game's
	# standard death bell. mc_mob_base.Die() plays only the creature sound.
	if Dead_Audio.is_empty(): Dead_Audio = "DeadBell"
	Collide_Audio = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	Unique_Hurt_Audio = null
	Unique_Collide_Audio = null
	motion_blur_enabled = false
	AfterImage_Speed = 0.0
	_random.seed = Game.battle_rng_seed_or("sulfur_cube:"+str(name),int(get_instance_id()))
	super._ready()
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	_create_live_model()
	_apply_visual()
	_previous_motion_position = global_position
	_motion_sample_valid = true

func get_preview_texture() -> Texture2D:
	# Off-tree selection portraits cannot render a SubViewport. This native-UV
	# thumbnail is only a menu fallback; live battles always use the 3D model.
	return SPRITES[Block.EMPTY]

func _get_hit_effect_visual_texture() -> Texture2D:
	# CPU-only hit particles and ground-shadow sampling cannot read the live
	# ViewportTexture in a headless renderer. This native-UV sprite is sampled
	# only by the effects system; it is never the in-battle character image.
	return SPRITES[block_mode]

func _create_live_model() -> void:
	if not image is Sprite2D: return
	_model_viewport = SubViewport.new()
	_model_viewport.name = "SulfurCube3DViewport"
	_model_viewport.size = Vector2i(160,160)
	_model_viewport.transparent_bg = true
	_model_viewport.own_world_3d = true
	# Render the opening empty shell too: WHEN_VISIBLE can skip its first frame
	# before the Sprite2D starts sampling this new ViewportTexture.
	_model_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_model_viewport)
	_native_model = MODEL.new() as Node3D
	_native_model.name = "SulfurCubeModel"
	_model_viewport.add_child(_native_model)
	var camera := Camera3D.new()
	camera.name = "ModelCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.3
	camera.position = Vector3(1.55,0.85,6.0)
	_model_viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	(image as Sprite2D).texture = _model_viewport.get_texture()
	(image as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _apply_visual() -> void:
	if not image is Sprite2D: return
	var sprite:Sprite2D = image as Sprite2D
	if is_instance_valid(_native_model):
		_native_model.set_block(block_mode)
		_native_model.set_crystals_active(block_mode == Block.AMETHYST and not crystals_out)
		sprite.texture = _model_viewport.get_texture()
	else:
		sprite.texture = SPRITES[block_mode]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta:float) -> void:
	if not image is Sprite2D or health <= 0: return
	if is_combat_runtime_active(): _view_clock += delta
	# The rendered six-sided shell squashes independently of the actual collision
	# circle and visible damage regions; the block switches inside it, not via
	# replacing the complete character image with another pre-baked sprite.
	image.scale = Vector2.ONE*(0.8 if is_instance_valid(_native_model) else 1.0)
	if is_instance_valid(_native_model): _native_model.animate(_view_clock,delta,is_combat_runtime_active(),fuse_left)
	image.self_modulate = Color(1.0,0.62 if fmod(_view_clock*5.0,1.0) < 0.45 else 1.0,0.62 if fmod(_view_clock*5.0,1.0) < 0.45 else 1.0) if block_mode == Block.TNT and fuse_left > 0.0 else Color.WHITE
	if block_mode == Block.TNT and fuse_left > 0.0:
		_ring_refresh -= delta
		if _ring_refresh <= 0.0:
			_ring_refresh = 0.08 # Warning geometry at ~12.5 Hz, not a per-frame overlay.
			queue_redraw()

func _draw() -> void:
	if block_mode != Block.TNT or fuse_left <= 0.0 or health <= 0: return
	# A simple UI telegraph, not an extra non-Minecraft character texture.
	# Radius is exactly the subsequent explosion's source-centered damage radius.
	var urgency:float = 1.0 - fuse_left/TNT_FUSE_SECONDS
	var alpha:float = 0.40 + 0.25*urgency + 0.18*absf(sin(_view_clock*TAU*2.5))
	# CanvasItem drawing is local to the 0.2-scaled fighter. Counter-scale the
	# visual ONLY: the ring must mark the same world-space 72 units as damage.
	var world_scale:Vector2 = global_transform.get_scale().abs()
	draw_set_transform(Vector2.ZERO,0.0,Vector2(1.0/maxf(world_scale.x,0.001),1.0/maxf(world_scale.y,0.001)))
	draw_arc(Vector2.ZERO,TNT_RADIUS,0.0,TAU,48,Color(1.0,0.26,0.10,alpha),2.0,false)
	draw_set_transform(Vector2.ZERO)

func Attack() -> void:
	Attacking = false
	if not mc_live() or dizziness or block_mode in [Block.EMPTY,Block.TNT]: return
	if block_mode == Block.IRON:
		_start_single_slam()
	else:
		_surge_left = 0.34

func Skill() -> void:
	Using_Skill = false
	if not mc_live() or dizziness or (block_mode == Block.TNT and fuse_left > 0.0): return
	set_block(next_block())

func next_block() -> int:
	# Equal chance among the OTHER modes; never a fixed sequence or repeat.
	var options:Array[int] = []
	for candidate:int in range(Block.ICE,Block.AMETHYST+1):
		if candidate != block_mode: options.append(candidate)
	return options[_random.randi_range(0,options.size()-1)]

func set_block(next:int) -> void:
	if not is_multiplayer_authority() or health <= 0: return
	next = clampi(next,Block.EMPTY,Block.AMETHYST)
	if next == block_mode: return
	if block_mode == Block.TNT and fuse_left > 0.0: return # Cannot skip self-damage.
	if block_mode == Block.AMETHYST and not crystals_out:
		if multiplayer.has_multiplayer_peer(): _break_body_crystals.rpc(global_position)
		_break_body_crystals(global_position)
		_emit_sound(&"amethyst_break")
	if block_mode != Block.EMPTY: _emit_sound(&"eject")
	block_mode = next
	if next == Block.ICE:
		_ice_reference_speed = maxf(Speed*CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,1.0)
	fuse_left = TNT_FUSE_SECONDS if next == Block.TNT else 0.0
	crystals_out = false
	_crystal_timer = CRYSTAL_VOLLEY_TIME
	_restore_slam_collision()
	_slam_time = -1.0
	_slam_hits.clear()
	_next_hit_at.clear()
	_top_hit_at.clear()
	_slide_velocity = Vector2.ZERO
	_scan_left = 0.0
	if next != Block.EMPTY: _emit_sound(&"absorb")
	if next == Block.TNT: _emit_sound(&"fuse")

func get_fire_effect_ratio() -> float:
	# Uses the common ball fire protocol; status nodes also remove themselves
	# as soon as they see immunity, including an already active Blaze burn.
	return 0.0 if block_mode == Block.MAGMA else super.get_fire_effect_ratio()

func tick_physics(state:State,delta:float) -> void:
	var can_tick:bool = mc_live()
	# Check the ACTUAL previous-tick displacement, not the desired velocity.
	# Discard an initial spawn/teleport jump so a stationary cube never steps.
	var displacement:float = global_position.distance_to(_previous_motion_position)
	var previous_position:Vector2 = _previous_motion_position
	_previous_motion_position = global_position
	var moved:bool = _motion_sample_valid and displacement > 0.20 and displacement < maxf(36.0,Speed*delta*4.5)
	_actual_speed = displacement/maxf(delta,0.001) if moved else 0.0
	if moved:
		_last_move_direction = (global_position-previous_position).normalized()
	_motion_sample_valid = true
	if can_tick:
		_clock += delta
		_surge_left = maxf(_surge_left-delta,0.0)
		if block_mode == Block.ICE and moved: _leave_ice(previous_position,global_position)
		if block_mode == Block.AMETHYST:
			_crystal_timer -= delta
			if _crystal_timer <= 0.0:
				if crystals_out:
					crystals_out = false
					_crystal_timer = CRYSTAL_VOLLEY_TIME
				else:
					_fire_all_crystals()
					crystals_out = true
					_crystal_timer = CRYSTAL_REGROW_TIME
		if block_mode != Block.EMPTY:
			if _landing_wait > 0.0:
				_landing_wait -= delta
				if _landing_wait <= 0.0:
					if moved and not is_instance_valid(_emit_sound(&"squish")):
						# A jump variant can last 0.8–0.9 s, longer than the
						# visual 0.43 s landing. Wait until it actually ends.
						_landing_wait = 0.05
					else:
						_landing_wait = -1.0
			if moved:
				_hop_timer -= delta
				if _hop_timer <= 0.0 and _landing_wait < 0.0:
					if is_instance_valid(_emit_sound(&"jump")):
						_hop_timer = 1.9 if is_large_battle_performance_mode() else 0.9
						_landing_wait = 0.43
					else:
						_hop_timer = 0.05
			else:
				_landing_wait = -1.0
		if block_mode == Block.EMPTY:
			_opening += delta
			if _opening >= first_block_delay: set_block(next_block())
		elif block_mode == Block.TNT and fuse_left > 0.0:
			fuse_left = maxf(fuse_left-delta,0.0)
			if fuse_left <= 0.0: _detonate()
		if block_mode == Block.HONEY: _pull_touching_enemies(delta)
		if _recoil_velocity.length_squared() > 1.0:
			Repel += _recoil_velocity
			_recoil_velocity = _recoil_velocity.move_toward(Vector2.ZERO,780.0*delta)
		super.tick_physics(state,delta)
	if not can_tick or health <= 0 or block_mode in [Block.EMPTY,Block.TNT,Block.HONEY] or dizziness or not Can_Attack: return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.08
		_pulse_contact()

func move(speed:float,delta:float) -> void:
	if block_mode == Block.IRON and _slam_time >= 0.0:
		if is_multiplayer_authority(): _step_single_slam(delta)
		return
	if block_mode == Block.ICE:
		var player:bool = is_player_controlled()
		var intended:Vector2 = player_control_direction if player else direction
		_slide_velocity = _slide_velocity.move_toward(intended.normalized()*speed*(1.42 if _surge_left > 0.0 else 1.0),210.0*delta)
		var heading:Vector2 = _slide_velocity.normalized() if _slide_velocity.length_squared() > 0.01 else Vector2.ZERO
		if player: player_control_direction = heading
		else: direction = heading
		super.move(_slide_velocity.length(),delta)
		if player: player_control_direction = intended
		else: direction = intended
		return
	var multiplier:float = 0.86 if block_mode == Block.MAGMA else 0.90 if block_mode == Block.HONEY else 0.58 if block_mode == Block.IRON else 1.0
	if _surge_left > 0.0: multiplier *= 1.42
	super.move(speed*multiplier,delta)

func take_damage(damage:float,ignore_block:bool = false) -> void:
	# Iron's resistance does not overwrite external buffs/debuffs on the shared
	# Damage_reduction property, and is removed automatically upon a block swap.
	super.take_damage(damage*0.5 if block_mode == Block.IRON else damage,ignore_block)

func _on_hitbox_on_hit(_hurt:hurtbox) -> void:
	# Do not double-hit via the inherited generic body hitbox.
	pass

func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	super.when_collide(speed,collision)
	if block_mode == Block.ICE and is_multiplayer_authority() and is_combat_runtime_active() and speed >= 40.0:
		_emit_sound(&"bounce",global_position)

func _pulse_contact() -> void:
	if block_mode == Block.IRON:
		if _slam_time >= 0.0 and _slam_time >= 0.38: _iron_bottom_contacts()
		return
	if block_mode not in [Block.ICE,Block.MAGMA,Block.AMETHYST]: return
	var radius:float = get_crowd_separation_radius_world()
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw): continue
		var target:ball = raw as ball
		var id:int = target.get_instance_id()
		var reach:float = radius+_target_radius(target)
		var distance:float = global_position.distance_to(target.global_position)
		if block_mode == Block.AMETHYST:
			if crystals_out or _clock < float(_next_hit_at.get(id,0.0)): continue
			for axis:Vector2 in CRYSTAL_DIRECTIONS:
				var center:Vector2 = global_position+axis*radius
				if center.distance_to(target.global_position) <= CRYSTAL_RADIUS+_target_radius(target):
					_next_hit_at[id] = _clock+CONTACT_INTERVAL
					_damage_with_impact(target,attack_damage(2.0),center)
					break
			continue
		if distance > reach: continue
		if block_mode == Block.MAGMA:
			# The TOP contact is a real strip, not an all-direction fire aura.
			var top_strip := Rect2(global_position+Vector2(-radius,-radius-2.5),Vector2(radius*2.0,5.0))
			var upper:bool = top_strip.grow(_target_radius(target)).has_point(target.global_position)
			if upper and _clock >= float(_top_hit_at.get(id,0.0)):
				_top_hit_at[id] = _clock+HOT_INTERVAL
				_damage_with_impact(target,attack_damage(0.17),global_position+Vector2.UP*radius,true)
		if _clock >= float(_next_hit_at.get(id,0.0)):
			_next_hit_at[id] = _clock+CONTACT_INTERVAL
			if block_mode == Block.MAGMA:
				if _damage_with_impact(target,attack_damage(0.80),global_position,true):
					BURN.apply(self,target,2.4,0.21)
					_emit_sound(&"magma_hit",target.global_position)
			else:
				var amount:float = attack_damage(0.34+1.52*clampf((_actual_speed-_ice_reference_speed)/maxf(_ice_reference_speed*0.9,1.0),0.0,1.0))
				if _damage_with_impact(target,amount,global_position): _emit_sound(&"ice_hit",target.global_position)

func _target_radius(target:ball) -> float:
	return maxf(target.get_crowd_separation_radius_world(),3.0)

func _pull_touching_enemies(delta:float) -> void:
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw): continue
		var target:ball = raw as ball
		var reach:float = get_crowd_separation_radius_world()+_target_radius(target)
		if global_position.distance_to(target.global_position) > reach: continue
		var toward:Vector2 = target.global_position.direction_to(global_position)
		if toward.is_zero_approx(): continue
		# A bounded opposing force, not a forced lock/teleport: outward velocity
		# exceeding it still carries the target out of contact.
		target.Repel += toward*170.0

func _start_single_slam() -> void:
	if _slam_time >= 0.0: return
	var target:ball = mc_nearest()
	_slam_target_ref = weakref(target) if is_instance_valid(target) else null
	_slam_start = global_position
	_slam_end = target.global_position if is_instance_valid(target) else global_position+_last_move_direction*30.0
	_slam_end = _slam_end.clamp(mc_arena_rect().position+Vector2.ONE*12.0,mc_arena_rect().end-Vector2.ONE*12.0)
	_slam_time = 0.0
	_slam_hits.clear()
	# Like the anvil's arc, fly past character bodies while still colliding
	# with map terrain; the downward strip alone resolves character damage.
	_slam_saved_mask = collision_mask
	collision_mask = collision_mask & ~2

func _restore_slam_collision() -> void:
	if _slam_saved_mask != 0:
		collision_mask = _slam_saved_mask
		_slam_saved_mask = 0

func _step_single_slam(delta:float) -> void:
	var last:float = _slam_time
	_slam_time += delta
	var t:float = clampf(_slam_time/0.82,0.0,1.0)
	var target:Variant = _slam_target_ref.get_ref() if _slam_target_ref != null else null
	if t >= 0.36 and mc_enemy(target):
		_slam_end.x = move_toward(_slam_end.x,target.global_position.x,40.0*delta)
	var desired:Vector2 = _slam_start.lerp(_slam_end,t)-Vector2.UP*0.0-Vector2(0.0,1.0)*56.0*4.0*t*(1.0-t)
	var bounds:Rect2 = mc_arena_rect().grow(-get_crowd_separation_radius_world())
	if bounds.has_area(): desired = desired.clamp(bounds.position,bounds.end)
	# Physical sweep uses the body collision shape; cannot pass walls or void.
	var motion:Vector2 = desired-global_position
	if motion.length_squared() > 0.0001: move_and_collide(motion)
	if t >= 0.46 and _slam_time > last: _iron_bottom_contacts()
	if t >= 1.0:
		_slam_time = -1.0 # Never queue a hit-confirmed follow-up.
		_restore_slam_collision()

func _iron_bottom_contacts() -> void:
	var radius:float = get_crowd_separation_radius_world()
	var bottom := Rect2(global_position+Vector2(-radius,radius-3.0),Vector2(radius*2.0,5.0))
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw): continue
		var target:ball = raw as ball
		if _slam_hits.has(target.get_instance_id()): continue
		if target.global_position.y < global_position.y or not bottom.grow(_target_radius(target)).has_point(target.global_position): continue
		_slam_hits[target.get_instance_id()] = true
		if _damage_with_impact(target,attack_damage(2.3),bottom.get_center()):
			_emit_sound(&"iron_hit",target.global_position)
			var away:Vector2 = (target.global_position-global_position).normalized()
			target.apply_knockback(away,30.0,230.0,0.0,0.0,{"source":self})

func _leave_ice(from:Vector2,to:Vector2) -> void:
	var steps:int = clampi(ceili(from.distance_to(to)/8.0),1,20)
	for step:int in range(steps+1):
		var rect:Rect2 = ICE_TRAIL.cell_at(self,from.lerp(to,float(step)/float(steps)))
		var key:String = str(rect.position)+":"+str(rect.size)
		var existing:Variant = _ice_cells.get(key)
		if is_instance_valid(existing) and not existing.is_queued_for_deletion(): continue
		if not mc_arena_rect().has_point(rect.get_center()): continue
		if multiplayer.has_multiplayer_peer(): _spawn_ice_tile.rpc(rect)
		_spawn_ice_tile(rect)
	if _ice_cells.size() > 80:
		for key:Variant in _ice_cells.keys():
			if not is_instance_valid(_ice_cells[key]): _ice_cells.erase(key)

@rpc("authority","call_remote","reliable")
func _spawn_ice_tile(rect:Rect2) -> void:
	if get_tree().current_scene == null: return
	var key:String = str(rect.position)+":"+str(rect.size)
	var existing:Variant = _ice_cells.get(key)
	if is_instance_valid(existing) and not existing.is_queued_for_deletion(): return
	var tile:Node2D = ICE_TRAIL.new()
	get_tree().current_scene.add_child(tile,true)
	tile.setup(self,rect)
	_ice_cells[key] = tile

func _fire_all_crystals() -> void:
	var radius:float = get_crowd_separation_radius_world()
	for axis:Vector2 in CRYSTAL_DIRECTIONS:
		var point:Vector2 = global_position+axis*radius
		if multiplayer.has_multiplayer_peer(): _spawn_crystal_shard.rpc(point,axis)
		_spawn_crystal_shard(point,axis)
	_emit_sound(&"amethyst_break")

@rpc("authority","call_remote","reliable")
func _spawn_crystal_shard(point:Vector2,axis:Vector2) -> void:
	if get_tree().current_scene == null: return
	var shard:Node2D = SHARD.new()
	get_tree().current_scene.add_child(shard,true)
	shard.setup(self,point,axis)

@rpc("authority","call_remote","reliable")
func _break_body_crystals(point:Vector2) -> void:
	for axis:Vector2 in CRYSTAL_DIRECTIONS:
		FRAGMENTS.spawn_texture(self,CRYSTAL_TEXTURE,point+axis*get_crowd_separation_radius_world(),0.45,{"max_pieces":5,"scatter_radius":12.0})

static func sulfur_impact_event(actual:float) -> StringName:
	return StringName(HIT_GAIN.damage_event(actual))

static func sulfur_impact_gain(actual:float) -> float:
	# The shared Minecraft policy starts at the source's 0 dB (1x) and rises
	# with effective HP damage, up to its capped +6 dB; no -2 dB hit baseline.
	return HIT_GAIN.damage_gain(actual)

func _damage_with_impact(target:ball,amount:float,point:Vector2,fire:bool = false) -> bool:
	if not is_multiplayer_authority() or not is_combat_runtime_active() or is_damage_output_disabled() or not mc_enemy(target) or amount <= 0.0: return false
	var before:float = maxf(target.health,0.0)
	var hit_point:Vector2 = target.global_position
	var applied:bool = target.receive_fire_positional_damage(amount,point,false,self) if fire else target.receive_positional_damage(amount,point,false,self)
	var remaining:float = maxf(target.health,0.0) if is_instance_valid(target) else 0.0
	var actual:float = maxf(before-remaining,0.0)
	if actual > 0.0:
		var event:StringName = sulfur_impact_event(actual)
		var gain:float = sulfur_impact_gain(actual)
		if multiplayer.has_multiplayer_peer(): _sulfur_impact.rpc(event,hit_point,gain)
		_sulfur_impact(event,hit_point,gain)
	return applied

@rpc("authority","call_remote","reliable")
func _sulfur_impact(event:StringName,point:Vector2,volume:float) -> void:
	var player:AudioStreamPlayer2D = AUDIO.play(self,event,point,volume)
	if is_instance_valid(player):
		player.set_meta("mc_sound_event",event)
		player.set_meta("mc_damage_source",get_instance_id())

func _mode_damage() -> float:
	match block_mode:
		Block.ICE: return 18.0+72.0*clampf((_actual_speed-_ice_reference_speed)/maxf(_ice_reference_speed*0.9,1.0),0.0,1.0)
		Block.MAGMA: return 38.0
		Block.AMETHYST: return 96.0 if not crystals_out else 0.0
	return 0.0

func _detonate() -> void:
	if not mc_live() or block_mode != Block.TNT: return
	var point:Vector2 = global_position
	# Minecraft 26.2 explosion textures/sounds; the PvP adaptation leaves the
	# cube alive so it can continue cycling its inner block after its finisher.
	if multiplayer.has_multiplayer_peer(): _spawn_blast_visual.rpc(point)
	_spawn_blast_visual(point)
	_emit_sound(&"explosion",point)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		var target:ball = node as ball
		if not mc_enemy(target): continue
		var reach:float = TNT_RADIUS + _target_radius(target)
		if point.distance_squared_to(target.global_position) > reach*reach: continue
		if _damage_with_impact(target,attack_damage(TNT_DAMAGE/maxf(float(Damage),1.0)),point):
			var away:Vector2 = (target.global_position-point).normalized()
			if away.is_zero_approx(): away = Vector2.RIGHT
			target.apply_knockback(away,32.0,235.0,0.0,0.0,{"source":self})
	# Explosion recoil keeps the pre-blast travel direction and decays quickly.
	_recoil_velocity = _last_move_direction.normalized()*480.0
	# Self-damage uses the same live outgoing/incoming attribute settlement.
	take_damage(attack_damage(TNT_SELF_DAMAGE/maxf(float(Damage),1.0)))
	if health > 0: set_block(next_block())

@rpc("authority","call_remote","reliable")
func _spawn_blast_visual(point:Vector2) -> void:
	if get_tree().current_scene == null: return
	# One shared Minecraft explosion per peer. Sulfur's native explode sound
	# is emitted separately, so the shared effect must not play it twice.
	ABILITIES.explosion(self,point,TNT_RADIUS,{"sound":false})

func _emit_sound(event:StringName,point:Vector2 = Vector2.INF) -> AudioStreamPlayer2D:
	if not is_multiplayer_authority(): return null
	var location:Vector2 = global_position if point == Vector2.INF else point
	var player:AudioStreamPlayer2D = _sulfur_sound(event,location,-2.0)
	if is_instance_valid(player) and multiplayer.has_multiplayer_peer(): _sulfur_sound.rpc(event,location,-2.0)
	return player

@rpc("authority","call_remote","reliable")
func _sulfur_sound(event:StringName,point:Vector2,volume:float) -> AudioStreamPlayer2D:
	# Sound starts are separated by the LAST actually selected Ogg variant's
	# length / pitch, never just by a fixed interval. Jump and landing squish
	# share one non-overlapping movement channel on each network peer.
	var now:int = Time.get_ticks_msec()
	var movement_sound:bool = event in [&"jump",&"squish"]
	if movement_sound and (now < _motion_audio_until_ms or (is_instance_valid(_motion_audio_player) and _motion_audio_player.playing)): return null
	if now - int(_sound_time.get(event,-100000)) < maxi(90,int(_sound_duration_ms.get(event,0))): return null
	var player:AudioStreamPlayer2D = AUDIO.play(self,event,point,volume)
	if not is_instance_valid(player): return null
	_sound_time[event] = now
	if movement_sound:
		var playback_rate:float = maxf(player.pitch_scale*AudioServer.playback_speed_scale,0.01)
		var length_ms:int = maxi(1,ceili(player.stream.get_length()*1000.0/playback_rate))
		_sound_duration_ms[event] = length_ms
		_motion_audio_until_ms = now+length_ms
		_motion_audio_player = player
	return player

func mc_play(event:String,volume:float = -4.0) -> AudioStreamPlayer2D:
	# Inherited hurt/death callbacks route through THIS cube's original voices,
	# rather than a Slime or a generic creature sample.
	if not is_multiplayer_authority(): return null
	var name_key:StringName = StringName(event)
	if multiplayer.has_multiplayer_peer(): _sulfur_sound.rpc(name_key,global_position,volume)
	return _sulfur_sound(name_key,global_position,volume)

func get_ai_attack_threats(_receiver:ball) -> Array:
	if health <= 0 or not is_combat_runtime_active() or is_damage_output_disabled(): return []
	if block_mode == Block.TNT:
		if fuse_left <= 0.0: return []
		return [{"shape":"circle","position":global_position,"radius":TNT_RADIUS,
			"damage":attack_damage(TNT_DAMAGE/maxf(float(Damage),1.0)),"danger_in":fuse_left,
			"danger_duration":0.12,"kind":"sulfur_cube_tnt","source":self}]
	if dizziness or not Can_Attack: return []
	var radius:float = get_crowd_separation_radius_world()
	if block_mode == Block.IRON and _slam_time >= 0.38:
		return [{"shape":"rect","position":global_position+Vector2(0,radius-0.5),
			"half_extents":Vector2(radius,2.5),"damage":attack_damage(2.3),
			"danger_duration":0.1,"kind":"sulfur_iron_bottom","source":self}]
	if block_mode == Block.AMETHYST and not crystals_out:
		var threats:Array = []
		for axis:Vector2 in CRYSTAL_DIRECTIONS:
			threats.append({"shape":"circle","position":global_position+axis*radius,
				"radius":CRYSTAL_RADIUS,"damage":attack_damage(2.0),
				"danger_duration":CONTACT_INTERVAL,"kind":"sulfur_amethyst_crystal","source":self})
		return threats
	if block_mode == Block.MAGMA:
		return [{"shape":"circle","position":global_position,"radius":radius,
			"damage":attack_damage(0.8),"danger_duration":CONTACT_INTERVAL,"kind":"sulfur_magma_touch","source":self},
			{"shape":"rect","position":global_position+Vector2.UP*radius,
			"half_extents":Vector2(radius,2.5),"damage":attack_damage(0.17),
			"danger_duration":HOT_INTERVAL,"kind":"sulfur_magma_top","source":self}]
	if block_mode == Block.ICE:
		return [{"shape":"circle","position":global_position,"radius":radius,
			"damage":attack_damage(_mode_damage()/maxf(float(Damage),1.0)),
			"danger_duration":CONTACT_INTERVAL,"kind":"sulfur_ice_speed_contact","source":self}]
	return []

func get_debug_attack_regions() -> Array:
	return get_ai_attack_threats(null)

func Die() -> void:
	if _sulfur_died: return
	_sulfur_died = true
	_restore_slam_collision()
	super.Die()
	# mc_mob_base.Die() intentionally supplies the vanilla creature death,
	# but does not call ball.Die(); keep the normal project death bell as well.
	if not Dead_Audio.is_empty(): Audios.play_sfx(Dead_Audio,{},true)
