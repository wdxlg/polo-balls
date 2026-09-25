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
const BODY_PAIRS = preload("res://classes/body_collision_exclusions.gd")
const CRYSTAL_COUNT_MIN:int = 3
const CRYSTAL_COUNT_MAX:int = 8

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
const IRON_IMPACT_MULT:float = 1.61 # Previous 2.3 * 0.70
const IRON_CRUSH_MULT:float = 0.24 # Small sustained ticks, not repeated full slams.
const IRON_CRUSH_INTERVAL:float = 0.25
const AMETHYST_CONTACT_MULT:float = 1.4 # Previous 2.0 * 0.70
const CRYSTAL_RADIUS:float = 3.0
const CRYSTAL_VOLLEY_TIME:float = 2.4
const CRYSTAL_REGROW_TIME:float = 0.8

# This property, plus fuse_left, is replicated by the scene's synchronizer.
@export var block_mode:int = Block.EMPTY:
	set(value):
		block_mode = clampi(value,Block.EMPTY,Block.AMETHYST)
		if is_node_ready():
			if block_mode != Block.HONEY: _clear_honey_contacts()
			_crystal_hits.clear()
			_apply_visual()
			queue_redraw()
@export var fuse_left:float = 0.0
@export var crystals_out:bool = false:
	set(value):
		crystals_out = value
		if is_instance_valid(_native_model): _native_model.set_crystals_active(block_mode == Block.AMETHYST and not value)
# Explicit coordinates synchronize the model, contact tips and released projectiles.
@export var crystal_layout:PackedVector3Array = PackedVector3Array():
	set(value):
		if crystal_layout == value: return
		crystal_layout = value.duplicate()
		_crystal_hits.clear()
		if is_instance_valid(_native_model): _native_model.set_crystal_layout(crystal_layout)
@export var honey_target_paths:PackedStringArray = PackedStringArray():
	set(value):
		honey_target_paths = value
		if is_node_ready(): _sync_honey_collision_pairs()
@export var first_block_delay:float = 0.65
var _honey_contacts:Dictionary = {} # relative target path -> WeakRef
var _crystal_hits:Dictionary = {} # crystal index -> target ID -> WeakRef, once per growth


var _clock:float = 0.0
var _view_clock:float = 0.0
var _charge_circle:Node2D
var _ice_bounce_hold:float = 0.0
var _iron_previous_gravity_mode:bool = false
const MODEL_CAMERA_SIZE:float = 5.0 # Random clusters + maximum squish need more edge clearance.
const MODEL_IMAGE_SCALE:float = 0.8*MODEL_CAMERA_SIZE/3.3
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
	if is_multiplayer_authority() and block_mode == Block.AMETHYST and crystal_layout.is_empty(): _roll_crystal_layout()
	_apply_visual()
	_sync_honey_collision_pairs()
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
	camera.size = MODEL_CAMERA_SIZE
	camera.position = Vector3(1.55,0.85,6.0)
	_model_viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	(image as Sprite2D).texture = _model_viewport.get_texture()
	(image as Sprite2D).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _apply_visual() -> void:
	if block_mode != Block.TNT: _clear_charge_circle()
	if not image is Sprite2D: return
	var sprite:Sprite2D = image as Sprite2D
	if is_instance_valid(_native_model):
		_native_model.set_crystal_layout(crystal_layout)
		_native_model.set_block(block_mode)
		_native_model.set_crystals_active(block_mode == Block.AMETHYST and not crystals_out)
		sprite.texture = _model_viewport.get_texture()
	else:
		sprite.texture = SPRITES[block_mode]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta:float) -> void:
	_sync_honey_collision_pairs() # Retries late-spawned replicated targets; prunes dead/removed ones.
	if health <= 0:
		_clear_charge_circle()
		return
	if not image is Sprite2D: return
	if is_combat_runtime_active(): _view_clock += delta
	# The rendered six-sided shell squashes independently of the actual collision
	# circle and visible damage regions; the block switches inside it, not via
	# replacing the complete character image with another pre-baked sprite.
	image.scale = Vector2.ONE*(MODEL_IMAGE_SCALE if is_instance_valid(_native_model) else 1.0)
	if is_instance_valid(_native_model): _native_model.animate(_view_clock,delta,is_combat_runtime_active(),fuse_left)
	image.self_modulate = Color(1.0,0.62 if fmod(_view_clock*5.0,1.0) < 0.45 else 1.0,0.62 if fmod(_view_clock*5.0,1.0) < 0.45 else 1.0) if block_mode == Block.TNT and fuse_left > 0.0 else Color.WHITE
	_update_charge_circle()

func _update_charge_circle() -> void:
	if block_mode != Block.TNT or fuse_left <= 0.0 or health <= 0:
		_clear_charge_circle()
		return
	if not is_instance_valid(_charge_circle):
		_charge_circle = ABILITIES.charge_circle(self,TNT_RADIUS)
	_charge_circle.set_charge(global_position,TNT_RADIUS,1.0-fuse_left/TNT_FUSE_SECONDS)

func _clear_charge_circle() -> void:
	if is_instance_valid(_charge_circle):
		_charge_circle.hide()
		_charge_circle.queue_free()
	_charge_circle = null

func Attack() -> void:
	Attacking = false
	if not mc_live() or dizziness or block_mode in [Block.EMPTY,Block.TNT]: return
	if block_mode == Block.IRON:
		_start_single_slam()
	else:
		_surge_left = 0.34

func player_control_extra_actions() -> Array[StringName]:
	# Preserve the existing surge (left) and block change (right). Volley is
	# the real third ability, only exposed while carrying amethyst.
	return [&"controlled_crystal_volley"] if block_mode == Block.AMETHYST else []

func controlled_crystal_volley() -> void:
	if not mc_live() or not is_player_controlled() or dizziness or not Can_Attack: return
	if block_mode == Block.AMETHYST and not crystals_out and _crystal_timer <= 0.0:
		_release_crystals()

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
	if block_mode == Block.IRON:
		configure_external_directional_gravity_locomotion(_iron_previous_gravity_mode)
		clear_external_directional_gravity_velocity()
	if next == Block.IRON:
		_iron_previous_gravity_mode = is_external_directional_gravity_locomotion_enabled()
		configure_external_directional_gravity_locomotion(true)
		clear_external_directional_gravity_velocity()
	honey_target_paths = PackedStringArray()
	if next == Block.AMETHYST: _roll_crystal_layout()
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
	_ice_bounce_hold = 0.0
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
					_roll_crystal_layout()
					crystals_out = false
					_crystal_timer = CRYSTAL_VOLLEY_TIME
				elif not is_player_controlled():
					_release_crystals()
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
	if block_mode == Block.IRON:
		if can_tick: _iron_bottom_contacts()
		return
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
		_ice_bounce_hold = maxf(_ice_bounce_hold-delta,0.0)
		var steering:Vector2 = _slide_velocity.normalized() if _ice_bounce_hold > 0.0 else intended.normalized()
		_slide_velocity = _slide_velocity.move_toward(steering*speed*(1.42 if _surge_left > 0.0 else 1.0),210.0*delta)
		var heading:Vector2 = _slide_velocity.normalized() if _slide_velocity.length_squared() > 0.01 else Vector2.ZERO
		if player: player_control_direction = heading
		else: direction = heading
		super.move(_slide_velocity.length(),delta)
		# The base class reflects direction, not our persistent ice momentum.
		# Reflect EVERY inward contact normal (corners too), then retain the
		# outgoing momentum instead of restoring the old into-wall heading.
		var bounced:bool = false
		for i:int in range(get_slide_collision_count()):
			var normal:Vector2 = get_slide_collision(i).get_normal().normalized()
			if _slide_velocity.dot(normal) < -0.01:
				_slide_velocity = _slide_velocity.bounce(normal)
				bounced = true
		if bounced: _ice_bounce_hold = 0.18
		if player: player_control_direction = intended
		else: direction = _slide_velocity.normalized() if bounced else intended
		return
	if block_mode == Block.IRON:
		var player:bool = is_player_controlled()
		var intended:Vector2 = player_control_direction if player else direction
		var horizontal:float = clampf(intended.x,-1.0,1.0) if player else signf(intended.x)
		if not player and is_zero_approx(horizontal): horizontal = 1.0
		if player: player_control_direction = Vector2(horizontal,0.0)
		else: direction = Vector2(horizontal,0.0)
		# Shared ball gravity owns v += g*dt, support and side-wall contacts.
		# W/S cannot generate an upward drive or a phantom horizontal input.
		super.move(speed*0.58*absf(horizontal),delta)
		if player: player_control_direction = intended
		return
	var multiplier:float = 0.86 if block_mode == Block.MAGMA else 0.90 if block_mode == Block.HONEY else 0.58 if block_mode == Block.IRON else 1.0
	if _surge_left > 0.0: multiplier *= 1.42
	super.move(speed*multiplier,delta)

func get_external_directional_gravity() -> Vector2:
	if block_mode == Block.IRON:
		return Vector2.DOWN*1200.0 if _slam_time < 0.0 else Vector2.ZERO
	return super.get_external_directional_gravity()

func stand(delta:float) -> void:
	if block_mode == Block.IRON and _slam_time >= 0.0:
		if dizziness:
			_slam_time = -1.0
			_restore_slam_collision()
		else:
			_step_single_slam(delta)
			return
	super.stand(delta) # Gravity still falls while idle/stunned; never hover.
	if block_mode == Block.IRON: Repel = Vector2.ZERO

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
	if not mc_live() or dizziness or not Can_Attack: return
	if block_mode == Block.IRON:
		_iron_bottom_contacts()
		return
	if block_mode not in [Block.ICE,Block.MAGMA,Block.AMETHYST]: return
	# While inserting, the spikes are still buried; the plain shell is harmless.
	if block_mode == Block.AMETHYST and is_instance_valid(_native_model) and not _native_model.crystals_ready(): return
	var radius:float = get_crowd_separation_radius_world()
	var crystal_points:Array[Vector2] = []
	if block_mode == Block.AMETHYST and not crystals_out: crystal_points = _crystal_tip_points()
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw): continue
		var target:ball = raw as ball
		var id:int = target.get_instance_id()
		var reach:float = radius+_target_radius(target)
		var distance:float = global_position.distance_to(target.global_position)
		if block_mode == Block.AMETHYST:
			if crystals_out: continue
			for i:int in range(crystal_points.size()):
				if not mc_enemy(target): break
				if _crystal_has_hit(i,target): continue
				var center:Vector2 = crystal_points[i]
				if center.distance_to(target.global_position) <= CRYSTAL_RADIUS+_target_radius(target):
					# Mark this crystal before callbacks. Other crystals remain independent;
					# lingering/re-entering cannot re-hit until a NEW growth is generated.
					if not _crystal_hits.has(i): _crystal_hits[i] = {}
					_crystal_hits[i][id] = weakref(target)
					_damage_with_impact(target,attack_damage(AMETHYST_CONTACT_MULT),center)
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

func _pull_touching_enemies(_delta:float) -> void:
	if not mc_live() or block_mode != Block.HONEY: return
	var touching:PackedStringArray = PackedStringArray()
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw): continue
		var target:ball = raw as ball
		# Include the physics safe margin so touching bodies can enter adhesion.
		var reach:float = get_crowd_separation_radius_world()+_target_radius(target)+0.5
		if global_position.distance_to(target.global_position) > reach: continue
		touching.append(str(get_path_to(target)))
		var toward:Vector2 = target.global_position.direction_to(global_position)
		# Bounded pull, not a forced lock: a fast outward target can still escape.
		target.Repel += toward*170.0
	touching.sort()
	if honey_target_paths != touching: honey_target_paths = touching
	else: _sync_honey_collision_pairs()

func _sync_honey_collision_pairs() -> void:
	if not is_inside_tree(): return
	if _honey_contacts.is_empty() and (honey_target_paths.is_empty() or block_mode != Block.HONEY): return
	var wanted:Dictionary = {}
	if block_mode == Block.HONEY and health > 0 and not _sulfur_died:
		for path:String in honey_target_paths:
			var target:Node = get_node_or_null(NodePath(path))
			if mc_enemy(target): wanted[path] = target
	for path:String in _honey_contacts.keys():
		var previous:Variant = (_honey_contacts[path] as WeakRef).get_ref()
		if not wanted.has(path) or previous != wanted[path]:
			if is_instance_valid(previous): BODY_PAIRS.release(self,previous,self)
			_honey_contacts.erase(path)
	for path:String in wanted:
		if not _honey_contacts.has(path) or not BODY_PAIRS.are_excluded(self,wanted[path]):
			var target:ball = wanted[path] as ball
			BODY_PAIRS.acquire(self,target,self)
			_honey_contacts[path] = weakref(target)

func _clear_honey_contacts() -> void:
	for ref:WeakRef in _honey_contacts.values():
		var target:Variant = ref.get_ref()
		if is_instance_valid(target): BODY_PAIRS.release(self,target,self)
	_honey_contacts.clear()

func _exit_tree() -> void:
	_clear_honey_contacts()
	_clear_charge_circle()
	super._exit_tree()

func _roll_crystal_layout() -> void:
	if not is_multiplayer_authority(): return
	var layout:PackedVector3Array = PackedVector3Array()
	for i:int in range(_random.randi_range(CRYSTAL_COUNT_MIN,CRYSTAL_COUNT_MAX)):
		# Independent angles, offsets and lengths: NO cardinal slots or angular
		# exclusion, so several clusters can grow along the same side/direction.
		var axis:Vector2 = Vector2.RIGHT.rotated(_random.randf_range(0.0,TAU))
		var root_xy:Vector2 = axis*_random.randf_range(0.30,0.56)+axis.orthogonal()*_random.randf_range(-0.24,0.24)
		var tip_xy:Vector2 = axis*_random.randf_range(1.60,1.83)+axis.orthogonal()*_random.randf_range(-0.12,0.12)
		layout.append(Vector3(root_xy.x,root_xy.y,_random.randf_range(0.30,0.56)))
		layout.append(Vector3(tip_xy.x,tip_xy.y,_random.randf_range(1.05,1.22)))
	crystal_layout = layout

func _crystal_has_hit(index:int,target:ball) -> bool:
	if not is_instance_valid(target) or not _crystal_hits.has(index): return false
	var ref:WeakRef = _crystal_hits[index].get(target.get_instance_id()) as WeakRef
	return ref != null and ref.get_ref() == target

func _start_single_slam() -> void:
	if _slam_time >= 0.0: return
	var target:ball = null if is_player_controlled() else mc_nearest()
	_slam_target_ref = weakref(target) if is_instance_valid(target) else null
	_slam_start = global_position
	_slam_end = player_control_aim_position if is_player_controlled() and has_player_control_aim() else target.global_position if is_instance_valid(target) else global_position+_last_move_direction*30.0
	_slam_end = _slam_end.clamp(mc_arena_rect().position+Vector2.ONE*12.0,mc_arena_rect().end-Vector2.ONE*12.0)
	_slam_time = 0.0
	clear_external_directional_gravity_velocity()
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

func _iron_bottom_active() -> bool:
	# Gravity contact keeps pressing even without an active jump. Rising is harmless.
	return block_mode == Block.IRON and health > 0 and is_combat_runtime_active() and not is_damage_output_disabled() and not dizziness and Can_Attack and (_slam_time < 0.0 or _slam_time >= 0.38)

func _iron_bottom_rect() -> Rect2:
	var radius:float = get_crowd_separation_radius_world()
	return Rect2(global_position+Vector2(-radius,radius-3.0),Vector2(radius*2.0,5.0))

func _iron_damage_multiplier(target:ball = null) -> float:
	return IRON_CRUSH_MULT if is_instance_valid(target) and _slam_hits.has(target.get_instance_id()) else IRON_IMPACT_MULT

func _iron_bottom_contacts() -> void:
	if not is_multiplayer_authority() or not _iron_bottom_active(): return
	var bottom:Rect2 = _iron_bottom_rect()
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw): continue
		var target:ball = raw as ball
		var id:int = target.get_instance_id()
		# Only the underside presses: never the top, rear or a fully engulfed body.
		if target.global_position.y < bottom.position.y or not bottom.grow(_target_radius(target)).has_point(target.global_position): continue
		if not mc_line_clear(global_position,target.global_position): continue
		var first:bool = not _slam_hits.has(id)
		var press:Dictionary = _slam_hits.get(id,{"next":0.0,"remainder":0.0})
		if _clock+0.000001 < float(press.next): continue
		var amount:float = attack_damage(IRON_IMPACT_MULT if first else IRON_CRUSH_MULT)
		# Carry fractional HP rather than rounding every tiny contact update up.
		press.remainder = float(press.remainder)+amount
		var settled:float = floorf(float(press.remainder))
		press.remainder -= settled
		press.next = _clock+IRON_CRUSH_INTERVAL
		_slam_hits[id] = press # Same-frame sweep/contact calls cannot double-settle.
		if not _damage_with_impact(target,settled,bottom.get_center()): continue
		_emit_sound(&"iron_hit",target.global_position)
		var heading:Vector2 = Vector2.DOWN
		if not mc_position_clear(target.global_position+Vector2.DOWN*6.0,_target_radius(target)):
			heading = Vector2.LEFT if target.global_position.x < global_position.x else Vector2.RIGHT
		target.apply_knockback(heading,24.0 if first else 6.0,230.0 if first else 120.0,0.0,0.0,
			{"source":self,"lock_control":false,"stop_on_character":true,"max_wall_bounces":0,"collision_damage":0.0,"control_recovery_time":0.0})

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

func _release_crystals() -> void:
	_fire_all_crystals()
	crystals_out = true
	_crystal_timer = CRYSTAL_REGROW_TIME

func _fire_all_crystals() -> void:
	var tips:Array[Vector2] = _crystal_tip_points()
	for i:int in range(tips.size()):
		var point:Vector2 = tips[i]
		# Each shard follows the individual spike's projected tip direction.
		# Nothing here aims at an opponent or invents a cardinal volley.
		var axis:Vector2 = (point-global_position).normalized()
		var appearance:Dictionary = _native_model.crystal_render_state(i)
		var camera:Camera3D = _model_viewport.get_node("ModelCamera") as Camera3D
		appearance["camera_transform"] = camera.global_transform
		appearance["camera_size"] = camera.size
		appearance["viewport_size"] = _model_viewport.size
		appearance["canvas_transform"] = image.global_transform
		if multiplayer.has_multiplayer_peer(): _spawn_crystal_shard.rpc(point,axis,appearance)
		_spawn_crystal_shard(point,axis,appearance)
	_emit_sound(&"amethyst_break")

@rpc("authority","call_remote","reliable")
func _spawn_crystal_shard(point:Vector2,axis:Vector2,appearance:Dictionary = {}) -> void:
	if get_tree().current_scene == null: return
	var shard:Node2D = SHARD.new()
	get_tree().current_scene.add_child(shard,true)
	shard.setup(self,point,axis,appearance)

@rpc("authority","call_remote","reliable")
func _break_body_crystals(point:Vector2) -> void:
	for tip:Vector2 in _crystal_tip_points():
		FRAGMENTS.spawn_texture(self,CRYSTAL_TEXTURE,point+(tip-global_position),0.45,{"max_pieces":5,"scatter_radius":12.0})

func _crystal_tip_points() -> Array[Vector2]:
	var points:Array[Vector2] = []
	var camera:Camera3D = _model_viewport.get_node_or_null("ModelCamera") as Camera3D if is_instance_valid(_model_viewport) else null
	if is_instance_valid(camera) and is_instance_valid(_native_model) and image is Sprite2D:
		var screen_origin:Vector2 = camera.unproject_position(_native_model.global_position)
		for i:int in range(_native_model.crystal_count()):
			var screen_tip:Vector2 = camera.unproject_position(_native_model.crystal_tip_world(i))
			points.append((image as Sprite2D).to_global(screen_tip-screen_origin))
		return points
	return points

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
		Block.AMETHYST: return attack_damage(AMETHYST_CONTACT_MULT) if not crystals_out else 0.0
	return 0.0

func _detonate() -> void:
	if not mc_live() or block_mode != Block.TNT: return
	_clear_charge_circle()
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
	if _iron_bottom_active():
		var bottom:Rect2 = _iron_bottom_rect()
		return [{"shape":"rect","position":bottom.get_center(),
			"half_extents":bottom.size*0.5,"damage":attack_damage(_iron_damage_multiplier(_receiver)),
			"danger_duration":IRON_CRUSH_INTERVAL,"kind":"sulfur_iron_bottom","source":self}]
	if block_mode == Block.AMETHYST and not crystals_out and (not is_instance_valid(_native_model) or _native_model.crystals_ready()):
		var threats:Array = []
		var tips:Array[Vector2] = _crystal_tip_points()
		for i:int in range(tips.size()):
			if _crystal_has_hit(i,_receiver): continue
			var tip:Vector2 = tips[i]
			threats.append({"shape":"circle","position":tip,
				"radius":CRYSTAL_RADIUS,"damage":attack_damage(AMETHYST_CONTACT_MULT),
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
	honey_target_paths = PackedStringArray()
	_clear_honey_contacts()
	_clear_charge_circle()
	_restore_slam_collision()
	super.Die()
	# mc_mob_base.Die() intentionally supplies the vanilla creature death,
	# but does not call ball.Die(); keep the normal project death bell as well.
	if not Dead_Audio.is_empty(): Audios.play_sfx(Dead_Audio,{},true)
