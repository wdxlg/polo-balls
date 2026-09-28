extends Node2D
## Confirmed, bounded copy cast. Uses public pending-spawn lifecycle tickets;
## a dead source can finish this already-confirmed summon without a fake extra life.
signal copy_finished(success:bool,unit:Node)
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const PARTICLE = preload("res://scripts/effects/我的世界/末影粒子.gd")
const AUDIO = preload("res://scripts/characters/我的世界/haochen/audio.gd")
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
	_emit_particles(10,false)
	_emit_link_particles(10,true)

func _physics_process(delta:float) -> void:
	if not _runtime_active(): return
	if is_multiplayer_authority() and not completed: _refresh_link_points()
	if not completed:
		_visual_wait -= delta
		if _visual_wait<=0.0:
			_visual_wait = 0.10
			_emit_particles(2,false)
		_link_wait -= delta
		if _link_wait<=0.0:
			_link_wait = 0.04
			_emit_link_particles(4,false)
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
		_emit_particles(22,true)
		AUDIO.play(self,&"copy_complete",global_position,audio_variant)

func _emit_particles(count:int,outward:bool) -> void:
	if get_parent()==null or get_parent().is_queued_for_deletion(): return
	for i:int in range(count):
		if get_tree().get_nodes_in_group("MCEnderParticle").size()>=320: break
		var heading:Vector2 = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
		var offset:Vector2 = heading*_rng.randf_range(10.0,23.0)
		var particle:Node2D = PARTICLE.new()
		get_parent().add_child(particle)
		var point:Vector2 = global_position if outward else global_position+offset
		particle.setup(point,offset*1.8 if outward else -offset,0.65,2.2 if outward else 1.8)
		particle.self_modulate = Color(0.82,0.72,1.0,0.9) if not outward else Color(0.93,0.93,0.98,0.9)
		particle.add_to_group("MCHaochenCopyParticle")
		particle.set_meta("haochen_copy_request",get_instance_id())

func _refresh_link_points() -> void:
	var owner:Node2D = owner_ref.get_ref() as Node2D if owner_ref != null else null
	link_to = owner.global_position if is_instance_valid(owner) and owner.is_inside_tree() else global_position
	var source:Node2D = source_ref.get_ref() as Node2D if source_ref != null else null
	# A copied character that dies mid-cast keeps its last known point.
	if is_instance_valid(source) and source.is_inside_tree() and not source.is_queued_for_deletion(): link_from = source.global_position

## Same public native portal particle, spawned along the segment and flowing
## from the copied character into Haochen. Visual only; each peer draws its own.
func _emit_link_particles(count:int,source_burst:bool) -> void:
	if not link_visible or get_parent()==null or get_parent().is_queued_for_deletion(): return
	var span:Vector2 = link_to-link_from
	if span.length()<4.0: return
	var side:Vector2 = span.normalized().orthogonal()
	for i:int in range(count):
		if get_tree().get_nodes_in_group("MCEnderParticle").size()>=320: break
		var t:float = _rng.randf_range(0.0,0.12) if source_burst else _rng.randf_range(0.0,0.9)
		var point:Vector2 = link_from.lerp(link_to,t)+side*_rng.randf_range(-5.0,5.0)
		var motion:Vector2 = link_to-point+side*_rng.randf_range(-3.0,3.0)
		var particle:Node2D = PARTICLE.new()
		get_parent().add_child(particle)
		particle.setup(point,motion,clampf(motion.length()/300.0,0.28,0.7),2.4)
		particle.self_modulate = Color(0.78,0.52,1.0,0.92)
		particle.add_to_group("MCHaochenLinkParticle")
		particle.set_meta("haochen_copy_request",get_instance_id())

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
