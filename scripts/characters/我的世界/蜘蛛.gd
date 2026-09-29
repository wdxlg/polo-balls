extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const VISUAL = preload("res://Images/characters/我的世界/蜘蛛/蜘蛛.png")
const NATIVE_FEEDBACK = preload("res://scripts/effects/我的世界/mc16_native_feedback.gd")
var native_feedback:Node
const WEB_DEBRIS = preload("res://scripts/effects/我的世界/cobweb_debris.gd")
const WEB_STEPS = preload("res://scripts/effects/我的世界/cobweb_footsteps.gd")
const SILK = preload("res://scripts/effects/我的世界/spider_silk.gd")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
@export_category("蜘蛛 / 连墙织丝")
@export var silk_tick:float = 0.12
@export var silk_damage:float = 1.0
@export var silk_slow_multiplier:float = 0.85
@export var silk_width:float = 1.2
@export var silk_anchor_spacing:float = 24.0
@export var silk_max_webs:int = 32
@export_category("蜘蛛 / 交叉蛛网捕猎")
@export var web_radius:float = 8.0 # Native 16x16 web at 1:1 size; trap radius matches.
@export var web_slow_multiplier:float = 0.2
@export var web_damage:float = 1.0
@export var web_retrigger:float = 2.2
@export var lunge_speed:float = 520.0
@export var lunge_interval:float = 1.2
@export var lunge_damage_ratio:float = 2.4
var silk_network:Node2D
var _lunge_left:float = 0.0
var _lunge_elapsed:float = 0.0
var _lunge_wait:float = 0.0
var _lunge_direction:Vector2 = Vector2.ZERO
var _lunge_target:WeakRef
var _lunge_hit:bool = false
var _last_lunge_position:Vector2
func _ready() -> void:
	dir_left = true
	super._ready()
	native_feedback = NATIVE_FEEDBACK.attach(self,"spider")
	silk_network = SILK.new()
	silk_network.name = "SpiderSilk"
	silk_network.unit = self
	add_child(silk_network)
	WEB_STEPS.ensure(self)
func get_preview_texture() -> Texture2D: return VISUAL
func mc_ambient_event() -> String: return "ambient"
func silk_tail_position() -> Vector2:
	# Abdomen is behind the head, not at the center or on the health bar.
	var local:Vector2 = Vector2(-25.0 if _visual_facing_flipped_h else 25.0,2.0)
	return graphics.to_global(local) if is_instance_valid(graphics) else to_global(local)
func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not mc_live() or Game.now_stop_state or dizziness: return
	_lunge_wait = maxf(_lunge_wait-delta,0.0)
	if _lunge_left>0.0:
		_lunge_elapsed += maxf(delta,0.0)
		_lunge_left = maxf(_lunge_left-delta,0.0)
		var target:Variant = _lunge_target.get_ref() if _lunge_target!=null else null
		if not GEOMETRY.enemy(self,target):
			_end_lunge()
			return
		_lunge_direction = global_position.direction_to(ball.body_point(target,global_position))
		_try_lunge_hit(target)
		if _lunge_left<=0.0 and not _lunge_hit: _end_lunge()
func hunt_web_target(target:Variant,manual:bool=false) -> bool:
	# A web contact can still slow/damage passively, but cannot start an AI
	# lunge while this spider is selected. The left-click uses this same lunge.
	if is_player_controlled() and not manual: return false
	if not mc_live() or Game.now_stop_state or dizziness or _lunge_wait>0.0 or _lunge_left>0.0: return false
	if not GEOMETRY.enemy(self,target): return false
	_lunge_target = weakref(target)
	_lunge_wait = maxf(lunge_interval,0.1)
	_lunge_direction = global_position.direction_to(ball.body_point(target,global_position))
	_lunge_left = clampf(global_position.distance_to(ball.body_point(target,global_position))/maxf(lunge_speed*0.6,1.0)+0.3,0.15,3.0)
	_lunge_hit = false
	_lunge_elapsed = 0.0
	_last_lunge_position = global_position
	return true
func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not has_player_control_aim(): return
	var point:Vector2=player_control_aim_world_position()
	var chosen:ball=null
	var nearest:float=INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not GEOMETRY.enemy(self,raw) or not raw.is_combat_lockable(): continue
		var distance:float=ball.body_point(raw,point).distance_to(point)
		if distance<=GEOMETRY.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	if chosen!=null: hunt_web_target(chosen,true)
func _try_lunge_hit(target:ball) -> void:
	if _lunge_hit: return
	var reach:float = GEOMETRY.radius(self)+GEOMETRY.radius(target)+5.0
	if GEOMETRY.segment_distance(_last_lunge_position,global_position,target.global_position)>reach:
		_last_lunge_position = global_position
		return
	# Walls between the spider and its prey still block the attack.
	if not mc_line_clear(global_position,ball.body_point(target,global_position)): return
	_lunge_hit = true
	_lunge_left = 0.0
	var hit_point:Vector2 = ball.body_point(target,global_position) # Damage may immediately remove the victim.
	var dealt:bool = mc_damage_with_impact(target,attack_damage()*lunge_damage_ratio,hit_point)
	if dealt and is_instance_valid(mc_native_animation):
		mc_native_animation.trigger_spider_impact(hit_point)
	else: _end_lunge()
func _end_lunge() -> void:
	_lunge_left = 0.0
	if is_instance_valid(mc_native_animation): mc_native_animation.trigger_action(&"land",0.18)
func move(speed:float,delta:float) -> void:
	if _lunge_left>0.0: direction = _lunge_direction
	var override_input:bool=is_player_controlled() and _lunge_left>0.0
	var saved_input:Vector2=player_control_direction
	if override_input: player_control_direction=_lunge_direction
	super.move(lunge_speed if _lunge_left>0.0 else speed,delta)
	if override_input: player_control_direction=saved_input
	# The primary collision may be another actor; inspect every slide for walls.
	if mc_live() and not dizziness:
		for i:int in range(get_slide_collision_count()):
			var collision:KinematicCollision2D = get_slide_collision(i)
			if _is_wall_like_collision(collision): _attach_silk(collision)
func _attach_silk(collision:KinematicCollision2D) -> void:
	if not is_instance_valid(silk_network): return
	var surface:Node2D = collision.get_collider() as Node2D
	# Called before the common collision bounce changes direction/facing.
	var point:Vector2 = silk_network.wall_attachment_point(collision.get_position(),collision.get_normal(),surface,silk_tail_position())
	silk_network.touch_wall(point,surface)
func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	if mc_live() and _is_wall_like_collision(collision):
		_attach_silk(collision)
		if _lunge_left>0.0: _end_lunge()
	super.when_collide(speed,collision)
@rpc("authority","call_remote","unreliable_ordered")
func _sync_silk(lines:Array,webs:Array) -> void:
	if is_instance_valid(silk_network): silk_network.receive_snapshot(lines,webs)

func emit_web_birth(point:Vector2) -> void:
	if not mc_live() or Game.now_stop_state: return
	_show_web_birth(point)
	if multiplayer.has_multiplayer_peer(): _show_web_birth.rpc(point)
	native_feedback.request("block.cobweb.place",point,-9.0,0.04)
@rpc("authority","call_remote","reliable")
func _show_web_birth(point:Vector2) -> void:
	if health<=0 or Game.now_stop_state or not is_combat_runtime_active(): return
	if get_tree().get_nodes_in_group("MCSpiderWebDebris").size()>=64: return
	var debris:Node2D = WEB_DEBRIS.new()
	silk_network.add_child(debris)
	debris.setup_web(self,point,web_radius*2.0)
