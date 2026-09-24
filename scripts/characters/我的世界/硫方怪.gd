extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## Minecraft 26.2 Sulfur Cube. The official block archetypes are adapted to
## auto-cycling PvP: the block is visible INSIDE the original translucent shell.
const AUDIO = preload("res://scripts/characters/我的世界/sulfur_cube_audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const BLAST_FX = preload("res://scripts/effects/我的世界/sulfur_cube_blast.gd")
const MODEL = preload("res://scripts/characters/我的世界/sulfur_cube_model.gd")

enum Block { EMPTY, WOOD, ICE, MAGMA, HONEY, IRON, TNT }
const SPRITES:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/sulfur_cube/empty.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/wood.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/ice.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/magma.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/honey.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/iron.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/tnt.png"),
]
const MODE_HITS:Array[StringName] = [
	&"", &"wood_hit", &"ice_hit", &"magma_hit", &"honey_hit", &"iron_hit", &"tnt_hit"
]
const CONTACT_RADIUS:float = 43.0 # Local CircleShape2D radius; root scale is 0.2.
const HOT_RADIUS:float = 26.0 # World-space aura radius.
const TNT_RADIUS:float = 72.0 # World-space explosion radius.
const TNT_FUSE_SECONDS:float = 2.4
const TNT_DAMAGE:float = 90.0
const CONTACT_INTERVAL:float = 0.68
const HOT_INTERVAL:float = 0.82

# This property, plus fuse_left, is replicated by the scene's synchronizer.
@export var block_mode:int = Block.EMPTY:
	set(value):
		block_mode = clampi(value,Block.EMPTY,Block.TNT)
		if is_node_ready():
			_apply_visual()
			queue_redraw()
@export var fuse_left:float = 0.0
@export var first_block_delay:float = 0.65

var _clock:float = 0.0
var _view_clock:float = 0.0
var _ring_refresh:float = 0.0
var _opening:float = 0.0
var _scan_left:float = 0.0
var _next_hit_at:Dictionary = {} # instance ID -> next time; cleared at each change
var _slide_velocity:Vector2 = Vector2.ZERO
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
	super._ready()
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	_create_live_model()
	_apply_visual()
	_previous_motion_position = global_position
	_motion_sample_valid = true

func get_preview_texture() -> Texture2D:
	# Off-tree selection portraits cannot render a SubViewport. This native-UV
	# thumbnail is only a menu fallback; live battles always use the 3D model.
	return SPRITES[Block.WOOD]

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
	if mc_live() and not dizziness and block_mode != Block.EMPTY and block_mode != Block.TNT:
		_surge_left = 0.42

func Skill() -> void:
	Using_Skill = false
	if not mc_live() or dizziness or (block_mode == Block.TNT and fuse_left > 0.0): return
	set_block(next_block())

func next_block() -> int:
	return Block.WOOD if block_mode == Block.EMPTY or block_mode == Block.TNT else block_mode+1

func set_block(next:int) -> void:
	if not is_multiplayer_authority() or health <= 0: return
	next = clampi(next,Block.EMPTY,Block.TNT)
	if next == block_mode: return
	if block_mode != Block.EMPTY: _emit_sound(&"eject")
	block_mode = next
	fuse_left = TNT_FUSE_SECONDS if next == Block.TNT else 0.0
	_next_hit_at.clear()
	_slide_velocity = Vector2.ZERO
	_scan_left = 0.0
	if next != Block.EMPTY: _emit_sound(&"absorb")
	if next == Block.TNT: _emit_sound(&"fuse")

func tick_physics(state:State,delta:float) -> void:
	var can_tick:bool = mc_live()
	# Check the ACTUAL previous-tick displacement, not the desired velocity.
	# Discard an initial spawn/teleport jump so a stationary cube never steps.
	var displacement:float = global_position.distance_to(_previous_motion_position)
	_previous_motion_position = global_position
	var moved:bool = _motion_sample_valid and displacement > 0.20 and displacement < maxf(36.0,Speed*delta*3.0)
	_motion_sample_valid = true
	if can_tick:
		_clock += delta
		_surge_left = maxf(_surge_left-delta,0.0)
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
			if _opening >= first_block_delay: set_block(Block.WOOD)
		elif block_mode == Block.TNT and fuse_left > 0.0:
			fuse_left = maxf(fuse_left-delta,0.0)
			if fuse_left <= 0.0: _detonate()
		super.tick_physics(state,delta)
	if not can_tick or health <= 0 or block_mode in [Block.EMPTY,Block.TNT] or dizziness or not Can_Attack: return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = 0.08
		_pulse_contact()

func move(speed:float,delta:float) -> void:
	if block_mode == Block.ICE:
		# Preserve momentum when the target turns; the normal shared move() still
		# handles terrain, portals, knockback, team collisions and large-battle mode.
		var player:bool = is_player_controlled()
		var intended:Vector2 = player_control_direction if player else direction
		var target_velocity:Vector2 = intended.normalized() * speed * 1.72
		_slide_velocity = _slide_velocity.move_toward(target_velocity,155.0*delta)
		var original:Vector2 = intended
		var heading:Vector2 = _slide_velocity.normalized() if _slide_velocity.length_squared() > 0.01 else Vector2.ZERO
		if player: player_control_direction = heading
		else: direction = heading
		super.move(_slide_velocity.length(),delta)
		if player: player_control_direction = original
		else: direction = original
		return
	var multiplier:float = 1.12 if block_mode == Block.WOOD else 0.98 if block_mode == Block.MAGMA else 0.62 if block_mode == Block.HONEY else 0.55 if block_mode == Block.IRON else 0.86
	if _surge_left > 0.0: multiplier *= 1.42
	super.move(speed*multiplier,delta)

func take_damage(damage:float,ignore_block:bool = false) -> void:
	# Iron's resistance does not overwrite external buffs/debuffs on the shared
	# Damage_reduction property, and is removed automatically upon a block swap.
	super.take_damage(damage*0.53 if block_mode == Block.IRON else damage,ignore_block)

func _on_hitbox_on_hit(_hurt:hurtbox) -> void:
	# Do not double-hit via the inherited generic body hitbox.
	pass

func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	super.when_collide(speed,collision)
	if block_mode in [Block.WOOD,Block.ICE] and is_multiplayer_authority() and is_combat_runtime_active() and speed >= 40.0:
		_emit_sound(&"bounce",global_position)

func _pulse_contact() -> void:
	var radius:float = HOT_RADIUS if block_mode == Block.MAGMA else get_crowd_separation_radius_world()
	var damage:float = _mode_damage()
	if damage <= 0.0: return
	var gap:float = HOT_INTERVAL if block_mode == Block.MAGMA else CONTACT_INTERVAL
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		var target:ball = node as ball
		if not mc_enemy(target): continue
		var reach:float = radius + _target_radius(target)
		if global_position.distance_squared_to(target.global_position) > reach*reach: continue
		var target_id:int = target.get_instance_id()
		if _clock < float(_next_hit_at.get(target_id,0.0)): continue
		_next_hit_at[target_id] = _clock + gap
		if not _damage_with_impact(target,attack_damage(damage/maxf(float(Damage),1.0)),global_position): continue
		_emit_sound(MODE_HITS[block_mode],target.global_position)
		var away:Vector2 = (target.global_position-global_position).normalized()
		if away.is_zero_approx(): away = Vector2.RIGHT
		if block_mode == Block.WOOD:
			target.apply_knockback(away,21.0,175.0,0.0,0.0,{"source":self})
		elif block_mode == Block.ICE:
			target.apply_knockback(away,13.0,150.0,0.0,0.0,{"source":self})
		elif block_mode == Block.HONEY:
			_slow_target(target)

func _target_radius(target:ball) -> float:
	return maxf(target.get_crowd_separation_radius_world(),3.0)

func _slow_target(target:ball) -> void:
	if not is_instance_valid(target) or not target.can_receive_negative_effects() or not target.can_receive_control_from(self): return
	var debuff := Buff.new(2,1.1,Buff.Buff_types.Speed,0.55,Buff.Algorithms.mul)
	var scene:Node = get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("new_buff"):
		scene.new_buff(target,self,"硫方怪蜂蜜黏滞",debuff)
	else:
		var id:int = get_instance_id()
		if not target.Buff_Dic.has(id): target.Buff_Dic[id] = {}
		target.Buff_Dic[id]["硫方怪蜂蜜黏滞"] = debuff

static func sulfur_impact_event(actual:float) -> StringName:
	return StringName(HIT_GAIN.damage_event(actual))

static func sulfur_impact_gain(actual:float) -> float:
	# The shared Minecraft policy starts at the source's 0 dB (1x) and rises
	# with effective HP damage, up to its capped +6 dB; no -2 dB hit baseline.
	return HIT_GAIN.damage_gain(actual)

func _damage_with_impact(target:ball,amount:float,point:Vector2) -> bool:
	if not is_multiplayer_authority() or not is_combat_runtime_active() or is_damage_output_disabled() or not mc_enemy(target) or amount <= 0.0: return false
	var before:float = maxf(target.health,0.0)
	var hit_point:Vector2 = target.global_position
	var applied:bool = target.receive_positional_damage(amount,point,false,self)
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
		Block.WOOD: return 28.0
		Block.ICE: return 20.0
		Block.MAGMA: return 12.0
		Block.HONEY: return 8.0
		Block.IRON: return 10.0
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
	set_block(Block.WOOD)

@rpc("authority","call_remote","reliable")
func _spawn_blast_visual(point:Vector2) -> void:
	if get_tree().current_scene == null: return
	var fx:Sprite2D = BLAST_FX.new() as Sprite2D
	fx.set("blast_radius",TNT_RADIUS)
	get_tree().current_scene.add_child(fx)
	fx.global_position = point

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
	var damage:float = _mode_damage()
	if damage <= 0.0: return []
	return [{"shape":"circle","position":global_position,
		"radius":HOT_RADIUS if block_mode == Block.MAGMA else get_crowd_separation_radius_world(),
		"damage":attack_damage(damage/maxf(float(Damage),1.0)),"danger_in":0.0,
		"danger_duration":HOT_INTERVAL if block_mode == Block.MAGMA else CONTACT_INTERVAL,
		"kind":"sulfur_cube_hot" if block_mode == Block.MAGMA else "sulfur_cube_contact","source":self}]

func get_debug_attack_regions() -> Array:
	return get_ai_attack_threats(null)

func Die() -> void:
	if _sulfur_died: return
	_sulfur_died = true
	super.Die()
	# mc_mob_base.Die() intentionally supplies the vanilla creature death,
	# but does not call ball.Die(); keep the normal project death bell as well.
	if not Dead_Audio.is_empty(): Audios.play_sfx(Dead_Audio,{},true)
