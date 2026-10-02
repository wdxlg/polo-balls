extends SceneTree
class GravityArena extends Node2D:
	func get_directional_gravity_for(_actor:Node) -> Vector2:return Vector2.DOWN*900.0
const PATHS:Array[String]=[
 "res://classes/ball.gd","res://classes/character_motion.gd","res://classes/portal_map.gd",
 "res://scripts/effects/knockback_effect.gd","res://scripts/effects/physical_airborne_effect.gd",
 "res://scripts/shooter/clown/clown_motion_effect.gd","res://scripts/effects/传说之下/Sans终幕.gd",
 "res://scripts/characters/科学家_传送门.gd","res://scripts/characters/动漫/菜月昴.gd","res://scripts/characters/动漫/菜月昴惯性鞭.gd",
 "res://scripts/characters/剑客.gd","res://scripts/characters/meme/凑企鹅.gd","res://scripts/characters/面包车.gd",
 "res://scripts/characters/月计/伞夫.gd","res://scripts/characters/月计/堇紫泪滴.gd","res://scripts/characters/月计/殷红迷雾.gd",
 "res://scripts/characters/我的世界/fog_man/actor.gd","res://scripts/characters/我的世界/minecart/minecart.gd",
 "res://scripts/characters/我的世界/new5/slime.gd","res://scripts/characters/我的世界/new5/piston_push.gd","res://scripts/characters/我的世界/new5/sticky_hold.gd",
 "res://scripts/characters/我的世界/new6/sheep.gd","res://scripts/characters/我的世界/new6/oak_boat.gd","res://scripts/characters/我的世界/new6/boat_rider.gd",
 "res://scripts/characters/我的世界/vindicator/vindicator.gd","res://scripts/characters/我的世界/zombie/zombie.gd","res://scripts/characters/我的世界/wither/wither.gd"
]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var errors:int=0
	for path:String in PATHS:
		var script:Script=load(path)
		if script==null or not script.can_instantiate():errors+=1;push_error("MOTION_ADAPTER_LOAD "+path)
	var game:Node=root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("motion_adapter_settings.json")
	game.now_stop_state=false
	game.Game_Settings.Ball_Can_Move=true
	var arena:=GravityArena.new();root.add_child(arena);current_scene=arena
	var actor:Node2D=load("res://scenes/ball.tscn").instantiate()
	arena.add_child(actor);actor.state_machine.set_physics_process(false)
	actor.get_body_motion().set_physics_process(false)
	actor.configure_external_directional_gravity_locomotion(true)
	actor.Speed=100.0;actor.direction=Vector2.RIGHT
	var floor_body:=StaticBody2D.new();floor_body.collision_layer=1
	var shape:=CollisionShape2D.new();var box:=RectangleShape2D.new();box.size=Vector2(400,8)
	shape.shape=box;floor_body.add_child(shape);arena.add_child(floor_body);floor_body.position=Vector2(0,50)
	for frame:int in range(45):
		await physics_frame
		actor.tick_physics(actor.State.Move,1.0/60.0)
	var half_y:float=actor.collision_shape_2d.shape.get_rect().size.y*actor.collision_shape_2d.global_scale.y*0.5
	var physics_checks:Array[bool]=[
		actor.global_position.y+half_y<=46.15,
		actor._external_directional_gravity_grounded,
		absf(actor.get_body_motion().impulse_velocity().y)<0.1,
		actor.global_position.x>30.0
	]
	var motion:Node=actor.get_body_motion()
	motion.reset_motion();motion.add_impulse(11,Vector2.RIGHT*100.0)
	motion.transform_motion(func(value:Vector2)->Vector2:return value.rotated(PI/2))
	physics_checks.append(motion.impulse_velocity().distance_to(Vector2.DOWN*100)<0.001)
	motion.reset_motion();physics_checks.append(motion.impulse_velocity().is_zero_approx())
	var force:Script=load("res://scripts/effects/knockback_effect.gd")
	force.set_pull(actor,arena,Vector2.LEFT*60.0)
	var total:Vector2=motion.compose(Vector2.RIGHT*60,force.pull_velocity(actor),1.0/60.0)
	physics_checks.append(total.is_zero_approx() and not actor.dizziness)
	force.release_pull(actor,arena)
	physics_checks.append(force.pull_velocity(actor).is_zero_approx())
	for ok:bool in physics_checks:
		if not ok:errors+=1
	print("ADAPTER_PHYSICS ",physics_checks)
	arena.queue_free();await process_frame
	print("MOTION_ADAPTER_LOAD checks=",PATHS.size()+physics_checks.size()," failures=",errors)
	quit(0 if errors==0 else 1)
