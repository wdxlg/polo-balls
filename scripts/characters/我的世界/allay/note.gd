extends ball
const NOTE_TRAIL = preload("res://scripts/characters/我的世界/allay/note_trail.gd")
var _trail:Node2D
var target_ref:WeakRef
var life:float = 3.0
var turn_rate:float = 0.45
var _path_ready:bool = false
var _spine:Vector2
var _path_axis:Vector2
var _path_length:float = 1.0
var _travel:float = 0.0
var _curve_side:float = 1.0
var _spent:bool = false
var _recall_ref:WeakRef
var _recall_token:int = -1
var _recall_state:int = 0 # 0 ordinary / 1 returning (full hit damage) / 2 spinning
var _recall_damage:float = 0.0
var _recall_angle:float = 0.0
func begin_recall(unit:ball,token:int) -> void:
	_recall_damage=attack_damage()
	_recall_ref=weakref(unit)
	_recall_token=token
	_recall_state=1
func cancel_recall() -> void:
	_recall_state=0; _recall_ref=null; _recall_token=-1
	_path_ready=false
func join_recall() -> void:
	var unit:Variant=_recall_ref.get_ref() if _recall_ref!=null else null
	if not is_instance_valid(unit) or not unit._recall.accepts(_recall_token):
		cancel_recall()
		return
	_recall_state=2
	var offset:Vector2=global_position-unit.global_position
	_recall_angle=offset.angle() if offset.length_squared()>0.01 else fmod(float(get_instance_id())*2.399963,TAU)
	velocity=Vector2.ZERO
	# The controller supplies the small, cooldown-limited spin contact damage.
	self_hitbox.set_deferred("monitoring",false)
	self_hitbox.set_deferred("collision_layer",0)
	self_hitbox.set_deferred("collision_mask",0)
func attack_damage(multiplier:float=1.0) -> float:
	return 0.0 if _recall_state==2 else super.attack_damage(multiplier)
func _return_move(delta:float) -> void:
	var unit:Variant=_recall_ref.get_ref() if _recall_ref!=null else null
	if not is_instance_valid(unit) or not unit._recall.accepts(_recall_token):
		cancel_recall()
		return
	var from:Vector2=global_position
	var outward:Vector2=(from-unit.global_position).normalized()
	if outward==Vector2.ZERO: outward=Vector2.RIGHT
	var goal:Vector2=unit.global_position+outward*30.0
	var to:Vector2=from.move_toward(goal,420.0*delta)
	var capture:Script=load("res://scripts/characters/我的世界/allay/capture.gd")
	if capture.sweep_note(self,from,to) or capture.sweep(self,from,to): return
	# Preserve real hitbox/block/dodge semantics, including fast return-path contacts.
	var hits:Array[Dictionary]=[]
	var geometry:Script=load("res://scripts/characters/我的世界/new5/utils.gd")
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not geometry.enemy(unit,target) or target.is_queued_for_deletion(): continue
		if not unit.Team.is_empty() and target.Team==unit.Team: continue
		var t:float=capture.contact_t(from,to,ball.body_point_seg(target,from,to),geometry.radius(target)+4.0)
		if t>=0.0: hits.append({"target":target,"t":t})
	hits.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return a.t<b.t)
	for hit:Dictionary in hits:
		var target:Variant=hit.target
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		global_position=from.lerp(to,float(hit.t))
		self_hitbox.try_hit_hurtbox(target.self_hurtbox)
		if _spent or is_queued_for_deletion(): return
	global_position=to
	velocity=(to-from)/maxf(delta,0.000001)
	if global_position.distance_to(goal)<=6.0: join_recall()
func _ready() -> void:
	set_meta("submission_allow_map_escape",true)
	z_as_relative=false
	z_index=102
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Dead_Audio = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	super._ready()
	if target_ref == null and is_instance_valid(Target_Enemy): target_ref = weakref(Target_Enemy)
	add_to_group("AllayFlyingNote")
	health_bar.hide()
	_create_trail.call_deferred()
func _create_trail() -> void:
	if is_instance_valid(_trail) or _spent or is_queued_for_deletion(): return
	if get_tree().current_scene == null: return
	_trail = NOTE_TRAIL.new()
	get_tree().current_scene.add_child(_trail)
	_trail.setup(self)
func tick_physics(state:State,delta:float) -> void:
	if _spent or not is_multiplayer_authority() or not is_combat_runtime_active(): return
	if _recall_state>0:
		var unit:Variant=_recall_ref.get_ref() if _recall_ref!=null else null
		if not is_instance_valid(unit) or unit.health<=0:
			_spent=true; queue_free(); return
		if unit.dizziness or unit.is_damage_output_disabled(): return
	if _recall_state==2: return
	life -= delta
	if life<=0:
		_spent = true
		queue_free()
		return
	if _recall_state==1:
		super.tick_physics(state,delta)
		return
	_ensure_path()
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if is_instance_valid(target) and target.health>0 and target.is_combat_lockable():
		var aim:Vector2 = _spine.direction_to(ball.body_point(target,_spine))
		direction = Vector2.RIGHT.rotated(rotate_toward(direction.angle(),aim.angle(),maxf(turn_rate,0)*delta))
	super.tick_physics(state,delta)
func _ensure_path() -> void:
	if _path_ready: return
	_path_ready = true
	_spine = global_position
	_path_axis = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	_curve_side = -1.0 if get_instance_id()%2==0 else 1.0
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	_path_length = maxf(global_position.distance_to(ball.body_point(target,global_position)),16.0) if is_instance_valid(target) else maxf(Speed,16.0)

func curve_offset(progress:float) -> Vector2:
	var u:float = clampf(progress,0.0,1.0)
	# A parabolic arch carrying one loop, closing back onto the aim spine.
	var envelope:float = 4.0*u*(1.0-u)
	var radius:float = minf(_path_length*0.25,28.0)
	var height:float = minf(_path_length*0.22,26.0)
	# Close targets get a shallow path instead of a full-sized loop around them.
	var close_scale:float=smoothstep(0.0,90.0,_path_length)
	radius*=close_scale
	height*=close_scale
	var along:float = sin(TAU*u)*radius*envelope
	var across:float = (height+(1.0-cos(TAU*u))*radius*0.65)*envelope*_curve_side
	return _path_axis*along+_path_axis.orthogonal()*across

func move(speed:float,delta:float) -> void:
	if _spent or delta<=0.0 or _recall_state==2: return
	if _recall_state==1:
		_return_move(delta)
		return
	_ensure_path()
	var distance:float = maxf(speed,0.0)*delta
	if distance<=0.0: return
	_travel += distance
	_spine += direction*distance
	var next:Vector2 = _spine+curve_offset(_travel/_path_length)
	velocity = (next-global_position)/delta
	# Keep capture interception and normal Area2D damage, but bypass solid bodies.
	if get_tree().has_group("MinecraftAllay"):
		var capture:Script = load("res://scripts/characters/我的世界/allay/capture.gd")
		if capture.sweep_note(self,global_position,next): return
		if capture.sweep(self,global_position,next): return
	global_position = next

func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if _spent or _recall_state==2: return
	super._on_hitbox_on_hit(hurt)
	_spent = true
	queue_free()
func when_collide(_speed:float,_collision:KinematicCollision2D) -> void:
	pass # Notes ignore world obstacles; hits and lifetime still consume them.
