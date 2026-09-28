extends Node2D
## Confirmed, bounded copy cast. Uses public pending-spawn lifecycle tickets;
## a dead source can finish this already-confirmed summon without a fake extra life.
signal copy_finished(success:bool,unit:Node)
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const SOUL = preload("res://scripts/effects/我的世界/灵魂粒子.gd")
const AUDIO = preload("res://scripts/characters/我的世界/haochen/audio.gd")
# All Haochen effects use the native Minecraft soul particle (user choice 2026-09-28).
const LINK_SOUL_WIDTH:float = 9.0
const LINK_INTERVAL:float = 0.05
const LINK_PER_TICK:int = 2
const FULL_BURST_COUNT:int = 16
const SPAWN_BURST_COUNT:int = 18
@export var template_snapshot:Dictionary = {}
@export var owner_name:String = ""
@export var owner_team:String = ""
@export var neutral_owner:String = ""
@export var stat_factor:float = 0.5
@export var cast_duration:float = 0.65
@export var remaining:float = 0.65
@export var visual_seed:int = 1
@export var completed:bool = false
# Source -> Haochen particle link. Authority refreshes both ends every physics
# frame; peers only draw from these replicated points (no client-side target pick).
@export var link_from:Vector2 = Vector2.ZERO
@export var link_to:Vector2 = Vector2.ZERO
@export var link_visible:bool = false
var owner_ref:WeakRef
var source_ref:WeakRef
var lifecycle_ticket:int = 0
var _visual_wait:float = 0.0
var _link_wait:float = 0.0
var _linger:float = 0.75
var _rng := RandomNumberGenerator.new()
var _reported:bool = false
var _finish_visual_played:bool = false

func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MCCharacterCopyRequest")
	_rng.seed = visual_seed
	z_as_relative = false
	z_index = 3
	# No particles/audio are allocated inside a locked parent's ready operation.
	_start_visual.call_deferred()

func _runtime_active() -> bool:
	if get_tree().paused or Game.now_stop_state or Engine.time_scale<=0.000001: return false
	var world:Node = get_tree().current_scene
	return world != null and (not world.has_method("is_combat_runtime_active") or world.is_combat_runtime_active())

func _start_visual() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or completed or not _runtime_active(): return
	# Full meter: souls burst out of Haochen once, then the source link starts.
	emit_ring(get_parent(),_rng,link_to if link_visible else global_position,FULL_BURST_COUNT,6.0,10.0,false,10.0,6.0,0.8,&"MCHaochenBurstParticle",&"haochen_copy_request",get_instance_id(),26.0)
	_emit_particles(6,false)
	_emit_link_particles(8,true)

func _physics_process(delta:float) -> void:
	if not _runtime_active(): return
	if is_multiplayer_authority() and not completed: _refresh_link_points()
	if not completed:
		_visual_wait -= delta
		if _visual_wait<=0.0:
			_visual_wait = 0.10
			_emit_particles(1,false)
		_link_wait -= delta
		if _link_wait<=0.0:
			_link_wait = LINK_INTERVAL
			_emit_link_particles(LINK_PER_TICK,false)
	if not is_multiplayer_authority(): return
	if completed:
		_linger -= delta
		if _linger<=0.0: queue_free()
		return
	remaining = maxf(remaining-maxf(delta,0.0),0.0)
	if remaining<=0.000001: _complete_copy()

func _complete_copy() -> void:
	if completed or not is_multiplayer_authority() or not _runtime_active(): return
	completed = true
	var owner:ball = owner_ref.get_ref() as ball if owner_ref != null else null
	if not is_instance_valid(owner) and not owner_name.is_empty(): owner = get_parent().get_node_or_null(NodePath(owner_name)) as ball
	var options:Dictionary = {"owner":owner,"parent":get_parent(),"master_name":owner_name,"team":owner_team,
		"neutral_owner":neutral_owner,"full_vitals":true,"cooldown_factor":1.0,"monochrome":true,
		"lifecycle_ticket":lifecycle_ticket,"metadata":{"haochen_copy":true,"haochen_owner_name":owner_name}}
	var copy:ball = TOOLS.spawn_character_copy(self,template_snapshot,global_position,stat_factor,options)
	var success:bool = is_instance_valid(copy)
	_release_ticket()
	if multiplayer.has_multiplayer_peer(): _finish_visual.rpc(success,AUDIO.variant(&"copy_complete"))
	else: _finish_visual(success,AUDIO.variant(&"copy_complete"))
	if not _reported:
		_reported = true
		copy_finished.emit(success,copy)

@rpc("authority","call_local","reliable")
func _finish_visual(success:bool,audio_variant:int) -> void:
	if not is_inside_tree() or not _runtime_active() or _finish_visual_played: return
	_finish_visual_played = true
	completed = true
	if success:
		_emit_particles(SPAWN_BURST_COUNT,true)
		AUDIO.play(self,&"copy_complete",global_position,audio_variant)

## Gathering souls converge on the spawn point during the cast; on success they
## burst out of it as the copy appears.
func _emit_particles(count:int,outward:bool) -> void:
	if outward: emit_ring(get_parent(),_rng,global_position,count,4.0,8.0,false,10.0,10.0,0.9,&"MCHaochenCopyParticle",&"haochen_copy_request",get_instance_id(),26.0)
	else: emit_ring(get_parent(),_rng,global_position,count,14.0,24.0,true,7.0,0.0,0.6,&"MCHaochenCopyParticle",&"haochen_copy_request",get_instance_id())

func _refresh_link_points() -> void:
	var owner:Node2D = owner_ref.get_ref() as Node2D if owner_ref != null else null
	link_to = owner.global_position if is_instance_valid(owner) and owner.is_inside_tree() else global_position
	var source:Node2D = source_ref.get_ref() as Node2D if source_ref != null else null
	# A copied character that dies mid-cast keeps its last known point.
	if is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion(): link_from = source.global_position

## Native soul particles spawned along the segment, flowing from the copied
## character into Haochen. Visual only; each peer draws its own.
func _emit_link_particles(count:int,source_burst:bool) -> void:
	if not link_visible: return
	emit_stream(get_parent(),_rng,link_from,link_to,count,LINK_SOUL_WIDTH,&"MCHaochenLinkParticle",&"haochen_copy_request",get_instance_id(),0.12 if source_burst else 0.9,_owner_node())

## Haochen on this peer (authority weakref, or by replicated name on clients).
func _owner_node() -> Node2D:
	var owner:Node2D = owner_ref.get_ref() as Node2D if owner_ref != null else null
	if not is_instance_valid(owner) and not owner_name.is_empty() and get_parent()!=null: owner = get_parent().get_node_or_null(NodePath(owner_name)) as Node2D
	return owner if is_instance_valid(owner) and owner.is_inside_tree() else null

## Shared by the copy link and Haochen's charging drain: native soul particles
## spawned on the from->to segment (up to t_max along it) that all flow into `to`.
static func emit_stream(parent:Node,rng:RandomNumberGenerator,from:Vector2,to:Vector2,count:int,width:float,group:StringName,meta_key:StringName,meta_id:int,t_max:float = 0.9,target:Node2D = null) -> int:
	if parent==null or not parent.is_inside_tree() or parent.is_queued_for_deletion(): return 0
	var span:Vector2 = to-from
	if span.length()<4.0: return 0
	var side:Vector2 = span.normalized().orthogonal()
	var room:int = mini(count,SOUL.room(parent.get_tree()))
	for i:int in range(room):
		var point:Vector2 = from.lerp(to,rng.randf_range(0.0,t_max))+side*rng.randf_range(-5.0,5.0)
		var end_offset:Vector2 = side*rng.randf_range(-3.0,3.0)
		var motion:Vector2 = to-point+end_offset
		var particle:Node2D = SOUL.new()
		parent.add_child(particle)
		particle.setup(point,motion,clampf(motion.length()/110.0,0.45,0.85),width)
		if target != null: particle.follow(target,to-target.global_position+end_offset)
		particle.add_to_group(group)
		particle.set_meta(meta_key,meta_id)
	return room

## Shared ring of native souls around `center`: inward gathers from r_min..r_max
## into the center; outward bursts from the center out to `travel`, drifting up.
static func emit_ring(parent:Node,rng:RandomNumberGenerator,center:Vector2,count:int,r_min:float,r_max:float,inward:bool,width:float,rise:float,lifetime:float,group:StringName,meta_key:StringName,meta_id:int,travel:float = 0.0) -> int:
	if parent==null or not parent.is_inside_tree() or parent.is_queued_for_deletion(): return 0
	var room:int = mini(count,SOUL.room(parent.get_tree()))
	for i:int in range(room):
		var heading:Vector2 = Vector2.RIGHT.rotated(TAU*(float(i)+rng.randf_range(-0.35,0.35))/float(maxi(room,1)))
		var offset:Vector2 = heading*rng.randf_range(r_min,r_max)
		var particle:Node2D = SOUL.new()
		parent.add_child(particle)
		if inward: particle.setup(center+offset,-offset,lifetime,width,rise)
		else: particle.setup(center+offset,heading*maxf(travel-offset.length(),0.0),lifetime,width,rise)
		particle.add_to_group(group)
		particle.set_meta(meta_key,meta_id)
	return room

func _release_ticket() -> void:
	if lifecycle_ticket<=0 or not is_inside_tree(): return
	var world:Node = get_tree().current_scene
	if is_instance_valid(world) and not world.is_queued_for_deletion() and world.has_method("finish_battle_spawn"): world.finish_battle_spawn(lifecycle_ticket)
	lifecycle_ticket = 0

func _exit_tree() -> void:
	_release_ticket()
	if not _reported and is_multiplayer_authority():
		_reported = true
		copy_finished.emit(false,null)
