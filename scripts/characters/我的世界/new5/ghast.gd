extends "res://scripts/characters/我的世界/new5/base.gd"
const FRAMES=preload("res://Images/characters/我的世界/new5/ghast.tres")
@export var shot_interval:float=2.2
@export var shot_range:float=430.0
@export var float_speed:float=55.0
@export var outside_margin:float=110.0
var _waypoint:Vector2
var _turn_left:float=0.0
var _shot_left:float=1.0
var _shoot_pose:float=0.0
var _warned:bool=false
var drift:Vector2=Vector2.ZERO
func _ready() -> void:
	set_meta("submission_allow_map_escape",true)
	super._ready()
	collision_mask=0
	image.z_as_relative=false
	image.z_index=101
	health_bar.z_as_relative=false
	health_bar.z_index=110
	_waypoint=global_position
func _is_character_ground_shadow_owner() -> bool: return false
func step_mob(delta:float) -> void:
	_turn_left-=delta
	_shot_left-=delta
	_shoot_pose=maxf(0,_shoot_pose-delta)
	var target:ball=U.nearest(self)
	if _turn_left<=0 or global_position.distance_to(_waypoint)<12:
		_turn_left=rng.randf_range(1.4,2.8)
		var center:Vector2=target.global_position if target!=null else global_position
		_waypoint=center+Vector2.RIGHT.rotated(rng.randf_range(0,TAU))*rng.randf_range(90.0,200.0)
		var world:Node=get_tree().current_scene
		if world.has_method("_current_map_node"):
			var map:Node=world._current_map_node()
			if map!=null:
				var rect:Rect2=world.return_map_world_rect(map).grow(outside_margin)
				_waypoint=_waypoint.clamp(rect.position,rect.end)
	var desired:Vector2=(_waypoint-global_position).normalized()*float_speed
	if is_player_controlled(): desired=player_control_direction*float_speed
	drift=drift.lerp(desired,1.0-exp(-delta*1.8))
	direction=drift.normalized()
	if not is_player_controlled() and can_act() and target!=null and global_position.distance_to(ball.body_point(target,global_position))<=shot_range and _shot_left>0 and _shot_left<=0.55 and not _warned:
		_warned=true
		_shoot_pose=0.55
		play_sound("entity.ghast.warn",-9.0)
	if not is_player_controlled() and can_act() and _shot_left<=0 and target!=null and global_position.distance_to(ball.body_point(target,global_position))<=shot_range:
		fire_at(ball.body_point(target,global_position))
		_shot_left=shot_interval
		_warned=false

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not can_act() or _shot_left>0: return
	fire_at(player_control_aim_world_position(global_position+direction*shot_range))
	_shot_left=shot_interval
	_warned=false

@export var fireball_damage_multiplier:float=2.0
func fire_at(point:Vector2) -> Node2D:
	play_sound("entity.ghast.shoot",-5.0)
	var scene:PackedScene=load("res://scenes/shooter/我的世界/恶魂火焰弹.tscn")
	var projectile:Node2D=scene.instantiate()
	projectile.Team=""
	projectile.Damage=attack_damage(fireball_damage_multiplier)
	projectile.initial_team=""
	projectile.launch_owner_id=get_instance_id()
	projectile.flight_velocity=(point-global_position).normalized()*185.0
	projectile.configure_launch(global_position)
	projectile.position=global_position+projectile.flight_velocity.normalized()*maxf(30.0,U.radius(self)+6.0)
	projectile.name=Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)
	projectile.add_to_group("BattleTransient")
	_shoot_pose=0.4
	return projectile
func move(_speed:float,_delta:float) -> void:
	velocity=drift*(Speed/maxf(float(default_properties.get("Speed",Speed)),0.001))+Repel
	global_position+=velocity*_delta
	Repel=Vector2.ZERO
func visual_mob() -> void:
	face_horizontal(drift if drift.length_squared()>0.01 else direction)
	frame(FRAMES,&"shoot" if _shoot_pose>0 else &"idle")
	image.position.y=sin(_view_clock*1.8)*10.0
func visual_state() -> Dictionary: return {"time":clock,"shoot":_shoot_pose}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_shoot_pose=float(data.get("shoot",0))

func voice_role() -> String: return "ghast"
