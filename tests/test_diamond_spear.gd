extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
var spear:Node2D
var game:Node
var enemy:Node2D
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1
func victim(point:Vector2,team:String="Team1") -> Node2D:
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate()
	unit.Team = team
	unit.Max_health = 10000
	unit.Health_Restore = 0
	unit.Has_Collision_Damage = false
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(unit)
	unit.global_position = point
	for holder:Node in [unit,unit.self_hurtbox]:
		var child:CollisionShape2D = holder.get_node("CollisionShape2D")
		var shape := CircleShape2D.new()
		shape.radius = 15.0
		child.shape = shape
	return unit
func reset(point:Vector2=Vector2.ZERO,speed:float=100.0) -> void:
	spear._cancel_action()
	spear.global_position = point
	spear._facing = Vector2.RIGHT
	spear.direction = Vector2.RIGHT
	spear._momentum = speed
	spear.Speed = speed
	spear._attack_wait = 0.0
	spear._sweep_wait = 0.0
	spear._blink_wait = 0.0
	spear.dizziness = false
	spear._apply_pose()
func barrier(point:Vector2,size:Vector2,layer:int=1) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	wall.collision_layer = layer
	wall.collision_mask = 0
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	wall.add_child(col)
	arena.add_child(wall)
	wall.global_position = point
	return wall
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("DIAMOND_SPEAR_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var packed:PackedScene = load("res://scenes/characters/我的世界/钻石长矛.tscn")
	check(packed!=null,"production scene loads")
	if packed==null: quit(1); return
	spear = packed.instantiate()
	spear.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	spear.Team = "Team0"
	arena.add_child(spear)
	check(spear.health==500 and spear.Damage==26,"base health and damage")
	check(spear.image.texture==spear.TEXTURE and spear.get_preview_texture()==spear.INVENTORY_TEXTURE,"native inventory icon and native in-hand sprite")
	check(spear.is_in_group("MinecraftDiamondSpear"),"registered character group")
	check(FileAccess.get_sha256("res://Images/characters/我的世界/diamond_spear/diamond_spear_in_hand.png")=="b39edc6f9101da3a5a146d3827d50194cff0c41fb9723072f03274ce5aab3f7d","in-hand PNG matches official Mojang client bytes")
	check(FileAccess.get_sha256("res://Images/characters/我的世界/diamond_spear/diamond_spear.png")=="fa6c967027edcae3bc31a6d81c6d4e846833f21f641a34aef6f9f68895ea5cfb","inventory PNG matches official Mojang client bytes")
	check(spear.TEXTURE.get_size()==Vector2(32,32) and spear.INVENTORY_TEXTURE.get_size()==Vector2(16,16),"native texture dimensions preserved")
	check(absf(spear.image.rotation-spear.NATIVE_ROTATION_OFFSET)<0.001,"native upper-left spear tip rotated to face right")
	check(spear._base_speed==240.0 and spear.max_move_speed==960.0 and spear.acceleration==180.0,"same base and top speed with four-second acceleration buildup")
	check(not spear.Has_Collision_Damage and spear.self_hitbox.collision_mask==0,"no duplicate passive body damage")
	check(not spear.has_meta("submission_allow_map_escape"),"no map escape exemption")
	var wood_reference:Node = load("res://scenes/characters/我的世界/木矛.tscn").instantiate()
	check(spear.turn_degrees_per_second==wood_reference.thrust_tracking_turn_speed_degrees,"turn speed matches the actual wooden spear 900 deg/s setting")
	wood_reference.free()
	check(is_equal_approx(spear.sweep_duration,0.20),"180 degree sweep averages 900 deg/s over 0.20 seconds")
	reset(Vector2.ZERO,400.0)
	spear.steer_toward(Vector2.DOWN,0.1)
	check(absf(rad_to_deg(spear._facing.angle())-90.0)<0.01,"wood-matched turn covers 90 degrees in a tenth of a second")
	check(is_equal_approx(spear._momentum,400.0*exp(-deg_to_rad(90.0)*0.18)),"wood-matched turning preserves the existing angle-based speed loss")
	check(spear.direction==Vector2.RIGHT,"visual steering does not change ordinary movement heading")
	var slowed:float = spear._momentum
	spear._accelerate_motion(0.1)
	spear.steer_toward(spear._facing,0.1)
	check(spear._momentum>slowed,"straight movement regains speed")
	check(spear.speed_multiplier(420)>spear.speed_multiplier(100),"damage increases with speed")
	check(spear.echo_count(100)==0 and spear.echo_count(150)==1 and spear.echo_count(240)==2 and spear.echo_count(420)==3 and spear.echo_count(600)==4,"speed builds to four echoes at 600, before the separate upgrade threshold")
	check(spear.thrust_offset_at(0.03,0.38)>0.0,"stab quickly extends forward first")
	check(spear.thrust_offset_at(0.16,0.38)<0.0,"elastic withdrawal crosses rest position")
	check(is_zero_approx(spear.thrust_offset_at(0.38,0.38)),"spring settles exactly")
	check(is_equal_approx(spear.thrust_offset_at(0.38*0.22,0.38),spear.thrust_distance),"smooth full extension reached in about 84 milliseconds")
	check(is_equal_approx(spear.sweep_scale_at(0.0),1.0) and is_equal_approx(spear.sweep_scale_at(1.0),1.0),"sweep scale starts and ends at native size")
	check(is_equal_approx(spear.sweep_scale_at(0.5),2.0),"90 degree sweep reaches exactly double size")
	check(is_equal_approx(spear.sweep_scale_at(0.25),spear.sweep_scale_at(0.75)) and spear.sweep_scale_at(0.25)<2.0,"sweep scaling grows and shrinks symmetrically")
	check(spear.sweep_scale_at(0.001)-1.0<0.00002 and 2.0-spear.sweep_scale_at(0.501)<0.00002,"scale has smooth zero-slope endpoints and peak")
	reset(Vector2.ZERO,240.0)
	spear._accelerate_motion(0.1)
	check(is_equal_approx(spear._momentum,258.0),"ordinary travel gains only 18 speed in its first tenth of a second")
	spear._accelerate_motion(0.3)
	check(is_equal_approx(spear._momentum,312.0),"ordinary travel is still slowly building speed after 0.4 seconds")
	spear._accelerate_motion(3.6)
	check(is_equal_approx(spear._momentum,960.0),"ordinary travel reaches full speed after four seconds")
	spear._accelerate_motion(1.0)
	check(is_equal_approx(spear._momentum,960.0),"fast acceleration never exceeds its cap")
	reset(Vector2.ZERO,240.0)
	for i:int in range(240): spear._accelerate_motion(1.0/60.0)
	check(is_equal_approx(spear._momentum,960.0),"speed gain is independent of timestep subdivision")
	reset(Vector2.ZERO,240.0)
	spear._action = spear.Action.THRUST
	spear._accelerate_motion(0.1)
	check(is_equal_approx(spear._momentum,258.0),"stabbing does not interrupt acceleration")
	spear._action = spear.Action.SWEEP
	spear._accelerate_motion(0.1)
	check(is_equal_approx(spear._momentum,276.0),"sweeping also continues ordinary acceleration")
	spear._action = spear.Action.BLINK_WINDUP
	spear._accelerate_motion(0.1)
	check(is_equal_approx(spear._momentum,294.0),"moving blink windup continues gradual acceleration")
	spear._action = spear.Action.BLINK_RECOVER
	spear._accelerate_motion(0.1)
	check(is_equal_approx(spear._momentum,312.0),"moving blink recovery also continues gradual acceleration")
	spear._action = spear.Action.IDLE
	game.now_stop_state = true
	spear._accelerate_motion(0.2)
	check(is_equal_approx(spear._momentum,312.0),"pause freezes acceleration")
	game.now_stop_state = false
	spear.direction = Vector2.ZERO
	spear._accelerate_motion(0.2)
	check(is_equal_approx(spear._momentum,312.0),"no movement input means no free acceleration")
	reset()
	spear.global_position = Vector2(20,0)
	spear._facing = Vector2.DOWN
	spear._pose_scale = 2.0
	spear._apply_pose(false)
	spear._render_pose(0.5)
	check(spear.image.global_position.distance_to(Vector2(10,0))<0.001,"render frames interpolate the moving pivot, not just rotation")
	check(spear.image.scale.distance_to(spear._image_rest_scale*1.5)<0.001,"render frames produce intermediate scale between physics samples")
	var rendered_axis:Vector2 = Vector2(-1,-1).normalized().rotated(spear.image.global_rotation)
	check(rendered_axis.dot(Vector2(1,1).normalized())>0.999,"render frames interpolate intermediate weapon angles")
	check(spear.global_position==Vector2(20,0) and spear.self_hurtbox.scale==spear._hurtbox_rest_scale*2.0,"render interpolation cannot move physics or shrink actual hurt geometry")
	var physical_tip:Vector2 = spear._tip_position()
	spear._render_pose(0.9)
	check(spear._tip_position().distance_to(physical_tip)<0.001,"damage tip is independent of current render fraction")
	game.now_stop_state = true
	var frozen_pose:Transform2D = spear.image.global_transform
	spear._process(0.1)
	check(spear.image.global_transform==frozen_pose,"pause freezes subframe pose interpolation")
	game.now_stop_state = false
	spear._cancel_action()
	spear._render_pose(0.0)
	check(spear.image.scale.distance_to(spear._image_rest_scale)<0.001,"cancellation clears render history instead of replaying stale scale")
	spear.global_position = Vector2(300,0)
	spear._apply_pose(false)
	spear._render_pose(0.0)
	check(spear.image.global_position.distance_to(spear.global_position)<0.001,"teleports snap render history instead of sliding across the map")
	spear.global_position = Vector2(500,0)
	spear._process(0.005)
	check(spear.image.global_position.distance_to(spear.global_position)<0.001,"spawn reposition before the first physics tick cannot flash at the old origin")
	reset()
	spear._action = spear.Action.SWEEP
	spear._sweep_start = 0.0
	spear._facing = Vector2.RIGHT.rotated(deg_to_rad(75.0))
	spear._pose_scale = spear.sweep_scale_at(75.0/180.0)
	spear._apply_pose()
	spear._facing = Vector2.RIGHT.rotated(deg_to_rad(105.0))
	spear._pose_scale = spear.sweep_scale_at(105.0/180.0)
	spear._apply_pose(false)
	spear._render_pose(0.5)
	check(spear.image.scale.distance_to(spear._image_rest_scale*2.0)<0.001,"rendered 90-degree sweep still reaches exactly 2x between physics samples")
	reset()
	enemy = victim(Vector2(21,0))
	var friend:Node2D = victim(Vector2(21,0),"Team0")
	await physics_frame
	await physics_frame
	reset(Vector2.ZERO,600.0)
	check(spear._front_target()==enemy,"front tip target found")
	spear.Attack()
	check(spear._action==spear.Action.THRUST and spear._visual_nodes.size()==1 and spear._pending_echo_anchors.size()==3,"thrust starts one echo and queues the remaining three")
	for i:int in range(3): spear._tick_echo_queue(spear._echo_spawn_wait)
	check(spear._visual_nodes.size()==4,"thrust completes its four-echo volley over separate intervals")
	var echo:Node2D = spear._visual_nodes[0]
	var all_aimed:bool = true
	for ghost:Node2D in spear._visual_nodes:
		all_aimed = all_aimed and ghost.axis.dot((enemy.global_position-ghost.anchor).normalized())>0.999
	check(all_aimed,"every offset echo aims at the enemy from its own anchor")
	check(echo.axis.distance_to(spear._visual_nodes[1].axis)>0.1,"offset echoes converge rather than sharing parallel angles")
	check(echo.sprite.texture==spear.TEXTURE and absf(echo.sprite.rotation-spear.NATIVE_ROTATION_OFFSET)<0.001,"ghosts use the same native in-hand texture and forward direction")
	var fixed:Vector2 = echo.global_position
	spear.global_position += Vector2(50,35)
	check(echo.global_position.distance_to(fixed)<0.001,"echo stays at world anchor when caster moves")
	spear.global_position = Vector2.ZERO
	var ghost_hp:int = enemy.health
	echo._physics_process(0.05)
	check(echo.sprite.position.x>0.0 and echo.global_position.distance_to(fixed)<0.001,"echo independently thrusts forward without moving its world anchor")
	check(enemy.health<ghost_hp,"converging echo forward stroke actually hits its target")
	var ghost_once:int = enemy.health
	echo._render_at(0.025)
	check(is_equal_approx(echo.sprite.position.x,spear.thrust_offset_at(0.025,echo.stroke_duration,echo.stroke_distance)),"echo has continuous subframe stroke animation at its own longer reach")
	check(is_equal_approx(echo.elapsed,0.05) and enemy.health==ghost_once,"rendering an echo neither advances physics time nor applies extra hits")
	echo._physics_process(0.11)
	check(echo.sprite.position.x<0.0 and enemy.health==ghost_once,"echo elastically retracts without double damage")
	echo._physics_process(0.22)
	check(is_zero_approx(echo.sprite.position.x),"echo stroke returns to its own rest pose before fading")
	spear._tick_action(0.03)
	spear._apply_pose()
	check(spear.image.global_position.x>spear.global_position.x,"main sprite quickly pokes forward")
	spear._tick_action(0.13)
	spear._apply_pose()
	check(spear.image.global_position.x<spear.global_position.x,"main sprite withdraws elastically after its forward poke")
	var before:int = enemy.health
	var allied:int = friend.health
	var hits:Dictionary = {}
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,hits,0.0)
	check(enemy.health<before,"real spatial stab damage")
	check(friend.health==allied,"no friendly fire")
	var once:int = enemy.health
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,hits,0.0)
	check(enemy.health==once,"per attack target deduplication")
	friend.global_position = Vector2(-200,-200)
	reset(Vector2.ZERO,360.0)
	enemy.global_position = Vector2(0,29)
	await physics_frame
	await physics_frame
	check(spear._side_target()==enemy,"side target qualifies when tip empty")
	check(spear._begin_sweep(enemy),"side sweep starts")
	var rest_scale:Vector2 = spear.image.scale
	before = enemy.health
	spear._tick_action(spear.sweep_duration*0.5)
	spear._apply_pose()
	check(spear.image.scale.distance_to(rest_scale*2.0)<0.001,"actual native sprite doubles at 90 degrees")
	check(spear.self_hurtbox.scale.distance_to(spear._hurtbox_rest_scale*2.0)<0.001,"hurt geometry follows doubled weapon size")
	check(spear.image.global_position.distance_to(spear.global_position)<0.001,"sweep rotation and scaling keep one shared center pivot")
	spear.global_position += Vector2(5,-5)
	spear._apply_pose()
	check(spear.image.global_position.distance_to(spear.global_position)<0.001,"pivot follows moving body without scale-induced drift")
	spear.global_position -= Vector2(5,-5)
	check(spear._visual_nodes.back().visual_scale.distance_to(spear.image.global_scale)<0.001,"sweep afterimage snapshots the current enlarged size")
	check(spear.direction.dot(spear._facing)>0.999 and spear.direction.distance_to(Vector2.DOWN)<0.001,"halfway sweep turns actual travel with the spear")
	spear._tick_action(spear.sweep_duration*0.5)
	spear._apply_pose()
	check(spear.image.scale.distance_to(rest_scale)<0.001 and is_equal_approx(spear._pose_scale,1.0),"sweep completion restores native scale without accumulation")
	check(spear._facing.distance_to(Vector2.LEFT)<0.001,"sweep rotates exactly 180 degrees")
	check(spear.direction.distance_to(Vector2.LEFT)<0.001,"completed sweep reverses actual travel by 180 degrees")
	check(absf(spear._momentum-(360.0+spear.hit_speed_boost))<0.001,"sweep does not reduce movement speed")
	var after_sweep:float = spear._momentum
	spear._update_steering(0.05)
	check(spear._facing.distance_to(Vector2.LEFT)<0.001 and spear._momentum>=after_sweep,"sweep endpoint does not immediately turn back or pay hidden slowdown")
	var after_sweep_position:Vector2 = spear.global_position
	spear.move(spear.Speed,0.016)
	spear._apply_pose()
	check(spear.global_position.x<after_sweep_position.x,"real physics displacement follows the completed sweep")
	var sprite_forward:Vector2 = Vector2(-1,-1).normalized().rotated(spear.image.global_rotation)
	check(sprite_forward.dot(spear.velocity.normalized())>0.999,"native sprite tip points along actual post-sweep velocity")
	check(enemy.health<before,"enlarged sweep actually hits enemy beyond unscaled shaft reach")
	var knock:bool = false
	for child:Node in enemy.get_children():
		if child.get_script()!=null and child.get_script().resource_path.ends_with("knockback_effect.gd"): knock = true
	check(knock,"sweep applies shared knockback controller")
	reset()
	enemy.global_position = Vector2(80,0)
	await physics_frame
	await physics_frame
	var plan:Dictionary = spear.blink_plan(enemy)
	check(not plan.is_empty(),"front target with clear rear permits blink")
	enemy.global_position = Vector2.RIGHT.rotated(deg_to_rad(25))*80.0
	await physics_frame
	check(not spear.blink_plan(enemy).is_empty(),"25 degree boundary permitted")
	enemy.global_position = Vector2.RIGHT.rotated(deg_to_rad(25.2))*80.0
	await physics_frame
	check(spear.blink_plan(enemy).is_empty(),"outside plus 25 degrees rejected")
	enemy.global_position = Vector2.RIGHT.rotated(deg_to_rad(-25.2))*80.0
	await physics_frame
	check(spear.blink_plan(enemy).is_empty(),"outside minus 25 degrees rejected")
	enemy.global_position = Vector2(80,0)
	var wall:StaticBody2D = barrier(Vector2(40,0),Vector2(4,80))
	await physics_frame
	await physics_frame
	check(spear.blink_plan(enemy).is_empty(),"wall crossing rejected")
	wall.queue_free()
	await physics_frame
	await physics_frame
	plan = spear.blink_plan(enemy)
	check(not plan.is_empty(),"removing wall restores valid path")
	var end:Vector2 = plan.get("end",Vector2(120,0))
	var rear:StaticBody2D = barrier(end,Vector2(20,20))
	await physics_frame
	await physics_frame
	check(spear.blink_plan(enemy).is_empty(),"insufficient rear clearance rejected")
	rear.queue_free()
	await physics_frame
	await physics_frame
	var blocker:Node2D = victim(end,"Team0")
	await physics_frame
	await physics_frame
	check(not spear.blink_plan(enemy).is_empty(),"occupied rear by friendly body no longer prevents piercing")
	blocker.queue_free()
	await physics_frame
	await physics_frame
	reset(Vector2.ZERO,300.0)
	spear.direction = Vector2.DOWN
	var middle:Node2D = victim(Vector2(45,0))
	await physics_frame
	await physics_frame
	before = enemy.health
	var middle_before:int = middle.health
	check(spear._begin_blink(enemy),"blink starts with flash windup")
	check(spear._action==spear.Action.BLINK_WINDUP,"blink has windup state")
	check(is_equal_approx(spear.blink_windup,0.04),"flash windup is only forty milliseconds")
	var windup_position:Vector2 = spear.global_position
	spear.move(spear.Speed,0.01)
	check(spear.global_position.distance_to(windup_position)>0.1,"flash windup continues real movement instead of standing")
	spear._tick_action(spear.blink_windup)
	check(spear.global_position.x>enemy.global_position.x,"teleports beyond enemy")
	check(spear.direction.x>0.99 and spear.direction.dot(spear._facing)>0.999,"blink commits its current forward ray rather than retaining sideways travel")
	check(enemy.health<before and middle.health<middle_before,"damages all enemies on blink path")
	check(spear._blink_wait>0.0 and spear.total_blinks==1,"successful blink consumes cooldown once")
	var landing:Vector2 = spear.global_position
	var hp:int = enemy.health
	spear._tick_action(spear.blink_recover_duration*0.25)
	spear._apply_pose()
	check(spear.global_position.distance_to(landing)<0.001 and spear._visual_shift<0.0,"landing spring is local and no longer drags the physics body backward")
	spear.move(spear.Speed,0.016)
	check(spear.global_position.x>landing.x and spear.velocity.length()>0.1,"landing recovery immediately continues real forward movement")
	spear.direction = Vector2.UP
	var recover_facing:Vector2 = spear._facing
	spear._tick_action(0.01)
	check(spear._facing.distance_to(recover_facing)>0.01,"landing recovery does not lock out steering")
	spear._tick_action(spear.blink_recover_duration)
	spear._apply_pose()
	check(spear._action==spear.Action.IDLE and is_zero_approx(spear._visual_shift),"short elastic recovery settles without a post-teleport stand")
	check(enemy.health==hp,"pullback does not rehit blink victims")
	reset()
	enemy.global_position = Vector2(80,0)
	middle.global_position = Vector2(-100,100)
	await physics_frame
	await physics_frame
	check(spear._begin_blink(enemy),"second prepared blink begins")
	enemy.global_position = Vector2(0,80)
	await physics_frame
	spear._tick_action(0.1)
	check(spear.global_position.distance_to(Vector2.ZERO)<0.1,"target leaving cone during windup cancels teleport")
	check(spear._blink_wait<=0.21,"failed validation does not spend full cooldown")
	reset()
	var facing:Vector2 = spear._facing
	var wait:float = spear._attack_wait
	game.now_stop_state = true
	spear.tick_physics(spear.State.Move,0.2)
	check(spear._facing==facing and spear._attack_wait==wait,"paused combat freezes timers and steering")
	game.now_stop_state = false
	reset(Vector2.ZERO,350.0)
	spear.dizziness = true
	spear.tick_physics(spear.State.Stand,0.01)
	check(spear._momentum==spear._base_speed and spear._action==spear.Action.IDLE,"stun resets momentum and cancels action")
	check(not spear._on_floor(Vector2(30,0),Vector2.RIGHT,[Rect2(-40,-40,40,80),Rect2(60,-40,40,80)]),"empty island gap is not floor")
	check(not spear._on_floor(Vector2(95,0),Vector2.RIGHT,[Rect2(-100,-100,200,200)]),"whole spear must fit inside floor boundary")
	reset(Vector2.ZERO,420.0)
	enemy.global_position = Vector2(21,6)
	spear._emit_echo(Vector2(0,6),Vector2.RIGHT,0.44,true,0.32)
	var fixed_echo:Node2D = spear._visual_nodes.back()
	var echo_before:int = enemy.health
	spear.global_position = Vector2(100,100)
	fixed_echo._physics_process(0.10)
	check(enemy.health<echo_before,"fixed echo deals its own real damage after caster moves away")
	var echo_once:int = enemy.health
	fixed_echo._physics_process(0.05)
	check(enemy.health==echo_once,"same echo cannot repeatedly damage one victim")
	var echo_clock:float = fixed_echo.elapsed
	game.now_stop_state = true
	fixed_echo._physics_process(0.1)
	check(fixed_echo.elapsed==echo_clock,"fixed echo lifetime freezes with combat pause")
	game.now_stop_state = false
	fixed_echo._physics_process(0.5)
	check(fixed_echo.is_queued_for_deletion(),"fixed echo expires and cleans up")
	# Actual movement probes with offense suppressed: a nearby enemy must not steer travel.
	reset(Vector2(-300,0),180.0)
	enemy.global_position = spear.global_position+Vector2(0,70)
	spear._update_steering(0.1)
	check(spear.direction==Vector2.RIGHT and spear._facing.distance_to(Vector2.RIGHT)<0.001,"side enemy cannot cause pursuit steering")
	spear._action = spear.Action.THRUST
	var walking:Vector2 = spear.global_position
	spear.move(spear.Speed,0.016)
	check(spear.global_position.x>walking.x and absf(spear.global_position.y-walking.y)<0.001,"ordinary stab continues common straight movement")
	spear._finish_action()
	var wall_probe:StaticBody2D = barrier(Vector2(-240,0),Vector2(4,100))
	await physics_frame
	await physics_frame
	spear._last_requested_velocity = Vector2.RIGHT*180.0
	var hit:KinematicCollision2D = spear.move_and_collide(Vector2(90,0))
	check(hit!=null,"movement probe actually reaches a wall")
	if hit!=null:
		spear.when_collide(180.0,hit)
		check(spear.direction.x<0.0,"inherited common collision immediately bounces movement")
		var at_wall:Vector2 = spear.global_position
		spear.move(spear.Speed,0.016)
		check(spear.global_position.x<at_wall.x,"does not remain pinned waiting for visual turn")
	wall_probe.queue_free()
	arena.queue_free()
	await process_frame
	print("DIAMOND_SPEAR_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
