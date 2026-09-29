extends ball
## Ordinary projectile protocol + public exact hurt-shape sweep. Z is not a summon.
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")
const UTILS = preload("res://scripts/characters/我的世界/new5/utils.gd")
@export var turn_degrees:float = 35.0
@export var lifetime:float = 3.5
@export var stun_duration:float = 0.1
var _spent:bool = false
var _resolving_hit:bool = false
var _z_label:Label
func _ready() -> void:
	inherit_master_attack_power=true
	master_attack_damage_multiplier=1.0
	Hit_Audio=""
	Dead_Audio=""
	Collide_Audio=""
	Collide_Audio_Node=""
	Block_Audio=""
	BlockBreak_Audio=""
	Projectile_Auto_Face_Motion=true # Reuse ball actual-motion facing, including homing/reflection.
	motion_blur_enabled=false
	motion_stretch_enabled=false
	AfterImage_Speed=-1.0
	super._ready()
	image.hide()
	health_bar.hide()
	health_bar.suppress_floating_text=true
	self_hurtbox.collision_layer=0
	self_hurtbox.collision_mask=0
	self_hurtbox.set_deferred("monitorable",false)
	self_hurtbox.set_deferred("monitoring",false)
	self_hitbox.collision_layer=0
	self_hitbox.collision_mask=0
	self_hitbox.set_deferred("monitoring",false)
	self_hitbox.set_deferred("monitorable",false)
	_z_label=Label.new()
	_z_label.text="Z"
	_z_label.position=Vector2(-5,-9)
	_z_label.add_theme_font_size_override("font_size",12)
	_z_label.add_theme_color_override("font_color",Color("b1e9ff"))
	_z_label.add_theme_color_override("font_outline_color",Color("304554"))
	_z_label.add_theme_constant_override("outline_size",2)
	add_child(_z_label)
	add_to_group("DingSleepZ")
	add_to_group("BattleTransient")
	var sync:MultiplayerSynchronizer=get_node("MultiplayerSynchronizer")
	var config:SceneReplicationConfig=sync.replication_config.duplicate()
	for key:String in ["direction","lifetime","turn_degrees","Speed"]:
		var path:=NodePath(".:"+key)
		if not config.has_property(path): config.add_property(path)
		config.property_set_spawn(path,true)
		config.property_set_replication_mode(path,SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	sync.replication_config=config
	_resolve_owner()
	_sync_projectile_facing_from_frame_motion(get_projectile_velocity(),1.0)
func _resolve_owner() -> void:
	if is_instance_valid(Master) or Master_name.is_empty() or get_parent()==null: return
	var candidate:Node=get_parent().get_node_or_null(NodePath(Master_name))
	if candidate is ball: Master=candidate
func _process(_delta:float) -> void: _resolve_owner()
func tick_physics(state:State,delta:float) -> void:
	if _spent: return
	if not is_multiplayer_authority():
		_update_projectile_facing_from_position_delta(delta)
		return
	if health<=0 or not is_instance_valid(Master) or Master.health<=0: expire(); return
	if not is_combat_runtime_active() or delta<=0.0: return
	lifetime-=delta
	if lifetime<=0.0: expire(); return
	var target:ball=TOOLS.nearest_enemy(self)
	if is_instance_valid(target) and target.is_combat_lockable():
		var heading:float=global_position.direction_to(target.global_position).angle()
		direction=Vector2.from_angle(rotate_toward(direction.angle(),heading,deg_to_rad(turn_degrees)*delta))
	super.tick_physics(state,delta)
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	return State.Move if state!=State.Move else -1
func get_projectile_velocity() -> Vector2: return direction*Speed+Repel
func set_projectile_velocity(motion:Vector2) -> void:
	direction=motion.normalized() if not motion.is_zero_approx() else Vector2.RIGHT
	Speed=motion.length()
	velocity=motion
func move(speed:float,delta:float) -> void:
	if _spent: return
	var start:Vector2=global_position
	velocity=direction*speed+Repel
	var finish:Vector2=start+velocity*delta
	var wall:Dictionary=UTILS.trace(self,start,finish)
	if not wall.is_empty(): finish=wall.position
	var contacts:Array[Dictionary]=SWEEP.contacts(self,start,finish,4.0,{},start)
	contacts.sort_custom(func(a:Dictionary,b:Dictionary): return start.distance_squared_to(a.point)<start.distance_squared_to(b.point))
	for contact:Dictionary in contacts:
		var target:ball=contact.target
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		global_position=contact.point
		self_hitbox.try_hit_hurtbox(target.self_hurtbox)
		if _spent or is_queued_for_deletion(): return
	global_position=finish
	if not wall.is_empty(): expire()
func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if _spent or _resolving_hit or not is_multiplayer_authority(): return
	var target:ball=_hurtbox_target_ball(hurt)
	if not TOOLS.is_enemy(self,target): return
	var before:float=target.health
	_resolving_hit=true
	super._on_hitbox_on_hit(hurt) # Common attributes, block/defense and exactly-once MC feedback.
	_resolving_hit=false
	if is_instance_valid(target) and target.health>0 and target.health<before:
		target.apply_stun(stun_duration,Master if is_instance_valid(Master) else self)
	expire()
func on_projectile_blocked_by(_target:ball,_point:Vector2) -> void:
	if not _resolving_hit: expire()
func can_receive_hit_contact(_incoming:hitbox,_contact:hurtbox) -> bool: return false
func can_receive_hit_from(_incoming:hitbox) -> bool: return false
func should_destroy_projectile_on_rejected_hit(_incoming:hitbox) -> bool: return false
func when_collide(_speed:float,_collision:KinematicCollision2D) -> void: expire()
func Die() -> void: expire()
func expire() -> void:
	if _spent: return
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _retire.rpc()
	else: _retire()
@rpc("authority","call_local","reliable")
func _retire() -> void:
	if _spent: return
	_spent=true
	hide()
	self_hitbox.set_deferred("monitoring",false)
	state_machine.set_physics_process(false)
	queue_free()
func get_ai_attack_threats(_receiver:ball) -> Array[Dictionary]:
	if _spent: return []
	return [{"shape":"circle","position":global_position,"radius":4.0,"velocity":get_projectile_velocity(),"damage":attack_damage(),"control_strength":0.1,"danger_in":0.0,"danger_duration":0.03,"kind":"ding_z","source":self}]
func get_debug_attack_regions() -> Array: return get_ai_attack_threats(null)
