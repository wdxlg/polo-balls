extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var checks:int=0
var failures:int=0
var finishing:bool=false
var center:Vector2
var u:Script
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("NEW5_FAIL "+label)
func spawn(role:String,offset:Vector2,team:String="Team0",folder:String="characters") -> Node2D:
	var path:String="res://scenes/"+folder+"/我的世界/"+role+".tscn" if role!="" else "res://scenes/ball.tscn"
	var packed:PackedScene=load(path)
	var actor:Node2D=packed.instantiate()
	actor.Team=team
	actor.position=center+offset
	world.add_child(actor,true)
	actor.state_machine.set_physics_process(false)
	actor.Has_Collision_Damage=false
	return actor
func obstacle(offset:Vector2,wall:bool=false,boundary:bool=false) -> StaticBody2D:
	var body:=StaticBody2D.new()
	body.name="InternalWall" if wall else "CrateObstacle"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("mc_wall",wall)
	body.set_meta("mc_map_boundary",boundary)
	var shape:=CollisionShape2D.new()
	var rect:=RectangleShape2D.new()
	rect.size=Vector2(8,70)
	shape.shape=rect
	body.add_child(shape)
	world.add_child(body)
	body.global_position=center+offset
	return body
func clear_units() -> void:
	for actor:Node in get_nodes_in_group("Ball"):
		if actor.get_parent()==world: actor.queue_free()
	await process_frame
	await physics_frame
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	for role:String in ["史莱姆","守卫者","恶魂","粘性活塞","钓鱼竿"]:
		var actor:Node2D=spawn(role,Vector2.ZERO)
		check(actor.get_script().can_instantiate(),role+" script compiled")
		check(actor.health>0 and actor.active(),role+" ready and active")
		check(not actor.Has_Collision_Damage,role+" no touch damage")
		actor.visual_mob()
		check(actor.image.texture!=null,role+" official image")
		check(world._mc_prewarmer.handles(role),role+" prewarm registration")
		check(world.spawner.get_spawnable_scene_count()>0,role+" scene registration")
		actor.queue_free()
		await process_frame
	# Four world axes, inclusive +-15 degrees, strict outside.
	var guardian:Node2D=spawn("守卫者",Vector2.ZERO)
	var target:Node2D=spawn("",Vector2(150,0),"Team1")
	target.health=10000
	for axis:float in [0.0,PI/2,PI,PI*1.5]:
		for degrees:float in [-15.0,-14.9,0,14.9,15.0]: check(guardian.in_sector(Vector2.RIGHT.rotated(axis+deg_to_rad(degrees))*150),"guardian inside "+str(axis)+"/"+str(degrees))
		for degrees:float in [-16.0,16.0,44.0]: check(not guardian.in_sector(Vector2.RIGHT.rotated(axis+deg_to_rad(degrees))*150),"guardian outside")
	guardian.step_mob(0.01)
	check(guardian.locked==target and guardian.beam_active,"guardian locks cardinal target")
	var hp:float=target.health
	guardian.step_mob(guardian.laser_tick+0.01)
	check(target.health<hp,"guardian periodic laser damage")
	target.global_position=center+Vector2(150,60)
	guardian.step_mob(0.01)
	check(not guardian.beam_active,"guardian immediate angle disconnect")
	target.global_position=center+Vector2(150,0)
	var wall:StaticBody2D=obstacle(Vector2(75,0),true)
	await physics_frame
	guardian.step_mob(0.01)
	check(not guardian.beam_active,"guardian occlusion disconnect")
	wall.queue_free()
	await physics_frame
	guardian.step_mob(0.01)
	guardian.dizziness=true
	guardian.step_mob(0.01)
	check(not guardian.beam_active,"guardian stun disconnect")
	await clear_units()
	# Directional jumping, no ground walking, two exact split generations.
	var slime:Node2D=spawn("史莱姆",Vector2.ZERO)
	var before:Vector2=slime.global_position
	slime.airborne=false
	slime.move(slime.Speed,0.016)
	check(slime.global_position.is_equal_approx(before),"slime no walking on ground")
	slime.direction=Vector2.RIGHT
	slime.rest_left=0
	slime.step_mob(0.01)
	check(slime.airborne and slime.jump_direction==Vector2.RIGHT,"slime directional takeoff")
	slime.step_mob(0.016)
	slime.move(slime.Speed,0.016)
	check(slime.global_position.x>before.x,"slime moves only while airborne")
	slime.step_mob(1.0)
	slime.move(slime.Speed,0.016)
	check(not slime.airborne,"slime lands")
	slime.Die()
	slime.Die()
	var mediums:Array=[]
	for node:Node in get_nodes_in_group("Ball"):
		if node.get_script()==slime.get_script() and node.slime_stage==1: mediums.append(node); node.state_machine.set_physics_process(false)
	check(mediums.size()==2,"one large -> exactly two medium, death idempotent")
	for medium:Node in mediums:
		check(medium.jump_duration<slime.jump_duration and medium.jump_distance<slime.jump_distance,"medium faster shorter")
		medium.Die()
	var smalls:Array=[]
	for node:Node in get_nodes_in_group("Ball"):
		if node.get_script()==slime.get_script() and node.slime_stage==2: smalls.append(node); node.state_machine.set_physics_process(false)
	check(smalls.size()==4,"two medium -> exactly four small")
	var count:int=get_nodes_in_group("Ball").size()
	for small:Node in smalls: small.Die()
	check(get_nodes_in_group("Ball").size()==count,"small never splits")
	await clear_units()
	# Fireball damage braking and attack-direction neutral momentum.
	var ghast:Node2D=spawn("恶魂",Vector2(-180,0))
	var projectile:Node2D=ghast.fire_at(center+Vector2(150,0))
	projectile.state_machine.set_physics_process(false)
	projectile.global_position=center
	check(projectile.is_combat_targetable() and projectile.is_combat_lockable(),"fireball public lock and hit contract")
	check(ghast.collision_mask==0 and ghast.get_meta("submission_allow_map_escape"),"ghast ignores boundaries")
	var speed:float=projectile.flight_velocity.length()
	projectile.receive_positional_damage(10,center+Vector2(20,0),false,ghast)
	check(is_equal_approx(projectile.flight_velocity.length(),speed-50),"damage reduces speed")
	check(not projectile.neutral,"not neutral before speed exhausted")
	projectile.receive_positional_damage(40,center+Vector2(20,0))
	check(projectile.neutral and projectile.flight_velocity.x<0,"neutral reflection follows incoming force")
	check(projectile.Team=="" and projectile.Master==null,"neutral removes friendly/master exemption")
	var vx:float=projectile.flight_velocity.x
	projectile.receive_positional_damage(10,center+Vector2(20,0))
	check(projectile.flight_velocity.x<vx,"subsequent attacks add neutral force")
	wall=obstacle(Vector2(45,0),true)
	var crate:StaticBody2D=obstacle(Vector2(90,0))
	await physics_frame
	var hit:Dictionary=u.trace(projectile,center,center+Vector2(150,0),true,false)
	check(hit.get("collider")==wall,"original fireball blocked by internal wall")
	hit=u.trace(projectile,center,center+Vector2(150,0),true,true)
	check(hit.get("collider")==crate,"neutral passes wall but hits nonwall obstacle")
	wall.set_meta("mc_map_boundary",true)
	hit=u.trace(projectile,center,center+Vector2(150,0),true,false)
	check(hit.get("collider")==crate,"original crosses map boundary, still hits obstacle")
	wall.queue_free()
	crate.queue_free()
	ghast.global_position=center+Vector2(20,0)
	hp=ghast.health
	projectile.explode()
	check(ghast.health<hp,"neutral explosion damages original shooter")
	await clear_units()
	# Piston ramp, end rod damage, dedicated sticky control and kinetic wall hit.
	var piston:Node2D=spawn("粘性活塞",Vector2.ZERO)
	target=spawn("",Vector2(65,0),"Team1")
	target.health=10000
	piston.direction=Vector2.RIGHT
	hp=target.health
	for i:int in range(30): piston.step_mob(0.016)
	check(piston.extending and piston.charge>0,"piston attack ramps speed")
	check(target.health<hp,"end rod inflicts damage")
	check(piston.rod is Sprite2D and not piston.rod is CollisionObject2D,"end rod has no solid collision")
	target.global_position=center+Vector2(0,300)
	for i:int in range(60): piston.step_mob(0.016)
	check(is_zero_approx(piston.charge) and not piston.extending,"piston charge decays rapidly")
	for effect:Node in target.get_children():
		if effect.has_method("replace_with_hit"): effect.call("_finish",false)
	await process_frame
	target.global_position=center+Vector2(31,0)
	piston.phase=0
	piston.extension=12
	for i:int in range(20): piston.step_mob(0.016)
	check(target.has_meta("mc_sticky_hold") and target.dizziness,"head sticks and fully stuns")
	var hold:Node=instance_from_id(int(target.get_meta("mc_sticky_hold",0)))
	if hold!=null:
		piston.extension=40
		hold._physics_process(0.01)
		check(target.global_position.distance_to(piston.sticky_anchor(target))<5,"victim follows moving piston head")
		hold.queue_free()
		await process_frame
		check(not target.has_meta("mc_sticky_hold"),"sticky metadata released")
		check(not target.dizziness,"sticky releases own control lock")
	var push:Node=load("res://scripts/characters/我的世界/new5/piston_push.gd").new()
	push.target=target
	push.source=piston
	push.distance=80
	push.speed=300
	target.add_child(push)
	push.set_physics_process(false)
	push._current_speed=200
	hp=target.health
	push._handle_wall_collision(Vector2.LEFT,target.global_position+Vector2(10,0))
	check(is_equal_approx(hp-target.health,11),"wall damage uses remaining speed")
	check(is_equal_approx(push.stun_duration,0.4),"wall stun scales with remaining speed")
	await clear_units()
	# Fishing cast, hit slow, distance break, strong pull and sword.
	var fisher:Node2D=spawn("钓鱼竿",Vector2.ZERO)
	target=spawn("",Vector2(150,0),"Team1")
	target.health=10000
	fisher.cast_at(target.global_position)
	hp=target.health
	for i:int in range(50):
		fisher.step_mob(0.016)
		if fisher.hook_mode==2: break
	check(fisher.hook_mode==2 and fisher.hooked==target,"fishing hook attaches")
	check(target.health<hp and not target.Buff_Dic.is_empty(),"hook deals damage and slow")
	hp=target.health
	fisher._attached_time=0.7
	fisher.step_mob(0.01)
	check(fisher.hook_mode==4 and target.health<hp,"far hooked victim pulled with damage and visible retrieval")
	check(target.Repel.x<0,"pull force toward fisher")
	fisher.hook_mode=2
	fisher.hooked=target
	target.global_position=center+Vector2(300,0)
	fisher.step_mob(0.01)
	check(fisher.hook_mode==4,"overlong line begins retrieval")
	target.global_position=center+Vector2(35,0)
	hp=target.health
	fisher._sword_left=0
	fisher.step_mob(0.01)
	check(target.health<hp and fisher.sword_pose>0,"close target gets sword damage")
	fisher.hook_mode=2
	fisher.hooked=target
	fisher.dizziness=true
	fisher.step_mob(0.01)
	check(fisher.hook_mode==0,"fishing control cleanup on stun")
	await clear_units()
	finish(0 if failures==0 else 1)
func finish(code:int) -> void:
	if finishing: return
	finishing=true
	# Drain outstanding background resource requests before destroying World.
	# Quitting early can abort preloads and emit spurious missing-resource errors.
	if is_instance_valid(world) and is_instance_valid(world._mc_prewarmer):
		for path:Variant in world._mc_prewarmer._paths.values():
			var status:int=ResourceLoader.load_threaded_get_status(str(path))
			if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(path))
	print("NEW5_RESULT checks=",checks," failures=",failures)
	if game!=null:
		game.Game_Settings=saved
		game.now_stop_state=true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	quit(code)
