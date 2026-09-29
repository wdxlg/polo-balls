extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
var game:Node
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures += 1
func keep_physics(node:Node2D) -> void:
	node.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in node.find_children("*","CollisionObject2D",true,false): child.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
func wall_at(point:Vector2,width:float = 2.0) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width,200)
	collision.shape = shape
	wall.add_child(collision)
	wall.position = point
	arena.add_child(wall)
	return wall
func golem(point:Vector2,team:String="Team0") -> Node2D:
	var node:Node2D = load("res://scenes/characters/我的世界/铁傀儡.tscn").instantiate()
	node.Team = team
	node.position = point
	arena.add_child(node)
	node.ensure_companion()
	keep_physics(node)
	if is_instance_valid(node.companion): keep_physics(node.companion)
	return node
func enemy(point:Vector2,team:String="Team1") -> Node2D:
	var node:Node2D = load("res://scenes/ball.tscn").instantiate()
	node.Team = team
	node.Max_health = 10000
	node.Health_Restore = 0
	node.Has_Collision_Damage = false
	node.position = point
	arena.add_child(node)
	keep_physics(node)
	return node
func clear_control(node:Node2D) -> void:
	for child:Node in node.get_children():
		if str(child.name).begins_with("KnockbackEffect"): child.free()
	node.Repel = Vector2.ZERO
	node.dizziness = false
func run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("IRON_GOLEM_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var g:Node2D = golem(Vector2.ZERO)
	var v:Node2D = g.companion
	check(g.Max_health==800 and v.Max_health==180,"golem and companion initial health")
	check(v.Master==g and v.Team==g.Team,"companion inherits master and team")
	check(v.Type==g.Ball_Type.Ball and v.is_combat_targetable(),"villager is a targetable continuation fighter")
	check(not v.Can_Attack and not v.has_collision_damage(),"helper cannot attack or deal contact damage")
	g.ensure_companion()
	check(get_nodes_in_group("MinecraftGolemVillager").size()==1,"exactly one initial villager")
	check(v.get_meta("battle_continuation_victory_side_key")=="team:Team0","companion carries stable victory identity")
	check(g.get_node("PairSync").replication_config.get_properties().size()==7 and g.get_node("PairSync").replication_config.has_property(NodePath(".:attack_facing_flipped_h")),"pair pose, locked facing and continuation fields are replicated")
	check(g.get_preview_texture()!=v.get_preview_texture(),"native selector portraits are distinct")
	for frames:SpriteFrames in g.GOLEM_FRAMES:
		check(frames.get_frame_count("walk")==16 and frames.get_frame_count("charge")==8 and frames.get_frame_count("swing")==24,"each crack variant has full bone-animation clips")
	check(v.pair_frames.has_animation("carry_walk") and v.pair_frames.get_frame_count("throw")==10,"villager carrying and throwing animations exist")
	g.set_pair_clip("charge")
	g.visual_clock = 0.0
	g.update_pair_visual()
	var first:Texture2D = g.image.texture
	g.visual_clock = 0.3
	g.update_pair_visual()
	check(g.image.texture!=first,"windup animates bones through different actual textures")
	g.set_pair_clip("idle")
	var target:Node2D = enemy(Vector2(30,0))
	var ally:Node2D = enemy(Vector2(30,3),"Team0")
	var behind:Node2D = enemy(Vector2(-30,0))
	await physics_frame
	await process_frame
	g._attack_wait = 0.0
	var before:int = target.health
	g.direction = Vector2.UP
	g.set_character_visual_flip_h(true)
	check(g.begin_swing(target),"nearby enemy starts windup")
	check(g.direction==Vector2.UP and g.current_attack_heading()==Vector2.RIGHT,"attack aim is independent from normal movement")
	check(g.visual_clip=="charge" and g._phase==1 and target.health==before,"charging lowers arms without early damage")
	g.move(g.Speed,1.0/60.0)
	check(g.velocity.length()<=g.Speed*0.31,"windup slows movement")
	g.global_position = Vector2.ZERO
	g.set_character_visual_flip_h(true)
	g.step_attack(g.minimum_charge)
	g.release_swing()
	check(g.visual_clip=="swing" and target.health==before,"upswing begins before its impact frame")
	g.step_attack(0.13)
	check(before-target.health==48,"upward impact deals configured damage")
	check(ally.health==10000 and behind.health==10000,"swing excludes allies and enemies behind")
	check(target.dizziness and target.get_node("KnockbackEffect_GolemAirborne")._vertical_speed<0.0,"upswing launches upward and applies control lock")
	var control:Node = null
	for child:Node in target.get_children():
		if str(child.name)=="KnockbackEffect_GolemAirborne": control = child
	check(control!=null and is_equal_approx(control.stun_duration,0.65),"launch controller schedules actual stun duration")
	g.step_attack(0.1)
	check(before-target.health==48,"a single upswing cannot hit repeatedly")
	clear_control(target)
	g._phase = 0
	g._attack_wait = 0.0
	g.dizziness = true
	check(not g.begin_swing(target),"stun prevents starting an attack")
	g.dizziness = false
	g.begin_swing(target)
	game.now_stop_state = true
	var phase_time:float = g._phase_time
	g.tick_physics(g.State.Move,0.2)
	check(is_equal_approx(g._phase_time,phase_time),"pause freezes windup timer")
	game.now_stop_state = false
	g.dizziness = true
	g.tick_physics(g.State.Move,0.02)
	check(g._phase==0,"stun interrupts the charged attack")
	g.dizziness = false
	g.global_position = Vector2.ZERO
	for value:int in [800,600,599,400,399,200,199]:
		g.health = value
		var expected:int = 3 if value<200 else 2 if value<400 else 1 if value<600 else 0
		check(g.crack_stage()==expected,"native crack threshold at "+str(value))
	g.health = 100
	v.global_position = Vector2(17,0)
	var barrier:StaticBody2D = wall_at(Vector2(10.3,0),0.4)
	await physics_frame
	await process_frame
	g._phase = 0
	g._attack_wait = 0
	check(not g.begin_swing(target),"golem does not wind up through a wall")
	g.set_character_visual_flip_h(true)
	var wall_health:int = target.health
	g.resolve_upswing()
	check(target.health==wall_health,"upswing damage cannot cross a wall")
	check(v.touching_golem() and v.try_repair()==0 and g.health==100,"wall prevents repair even with body-contact tolerance")
	barrier.free()
	await physics_frame
	await process_frame
	v.global_position = Vector2(150,0)
	v.direction = Vector2.UP
	v.step_helper(target)
	check(v.carrying_iron and v.visual_clip=="carry_walk","injured golem makes normally moving villager carry iron")
	check(v.direction==Vector2.UP,"repair need never steers toward the golem")
	check(v.try_repair()==0 and g.health==100,"repair cannot work remotely")
	v.global_position = Vector2(17,0)
	check(v.touching_golem(),"repair uses real body contact with small tolerance")
	check(v.try_repair()==100 and g.health==200 and g.crack_stage()==2,"one contact repairs exactly one heavy crack tier")
	check(v.try_repair()==0 and g.health==200,"repair cooldown prevents instant full restoration")
	v.repair_wait = 0.0
	check(v.try_repair()==200 and g.health==400 and g.crack_stage()==1,"next repair restores medium crack tier")
	v.repair_wait = 0.0
	check(v.try_repair()==200 and g.health==600 and g.crack_stage()==0,"next repair clears light cracks without healing to full")
	v.repair_wait = 0.0
	check(v.try_repair()==0 and g.health==600,"no-crack golem consumes no extra repair")
	g.health = 550
	v.dizziness = true
	check(v.try_repair()==0,"stunned villager cannot repair")
	v.dizziness = false
	v.set_multiplayer_authority(2)
	check(v.try_repair()==0,"remote replica cannot heal")
	v.set_multiplayer_authority(1)
	game.now_stop_state = true
	check(v.try_repair()==0,"paused combat cannot heal")
	game.now_stop_state = false
	g.health = 800
	v.global_position = Vector2(35,0)
	target.global_position = Vector2(42,0)
	v.direction = Vector2.UP
	v.Repel = Vector2.ZERO
	v._evade_wait = 0.0
	v.step_helper(target,0.016)
	check(v.direction==Vector2.UP and v.Repel.x<0 and v.Repel.length()<=v.Speed*0.121,"small evasive offset leaves normal heading unchanged")
	var evade_heading:Vector2 = v.direction
	v.Repel = Vector2.ZERO
	v.step_small_evade(target,0.2)
	check(v.Repel.is_zero_approx() and v.direction==evade_heading,"tiny evade ends without changing normal direction")
	v._evade_wait = 0.0
	game.Game_Settings.Ball_Can_Move = false
	v.step_small_evade(target,0.016)
	check(v.Repel.is_zero_approx(),"movement-disabled setting suppresses villager evasion")
	game.Game_Settings.Ball_Can_Move = true
	var shots:int = get_nodes_in_group("GolemIronProjectile").size()
	v.launch_iron(Vector2.RIGHT)
	check(get_nodes_in_group("GolemIronProjectile").size()==shots,"living golem prevents villager projectiles")
	v.receive_positional_damage(1000,v.global_position,false,target)
	check(g.enraged and g.visual_rage and g.image.self_modulate.g<0.5,"villager death immediately reddens and enrages golem")
	check(g.attack_damage(g.rage_damage_multiplier)==72.0 and g.rage_speed_multiplier>1.0,"rage raises damage and movement")
	g.on_companion_killed()
	g._phase = 0
	g._attack_wait = 0
	check(g.begin_swing(target) and is_equal_approx(g._attack_wait,1.105),"rage speeds up attacks once without stacking")
	g.ensure_companion()
	check(g.companion==v,"dead villager is never replaced")

	var g2:Node2D = golem(Vector2(400,0),"")
	var v2:Node2D = g2.companion
	var key:String = str(v2.get_meta("battle_continuation_victory_side_key"))
	check(key.begins_with("solo_instance:"),"teamless pair has stable shared solo identity")
	g2.receive_positional_damage(2000,g2.global_position,false,target)
	check(v2.orphaned and v2.Can_Attack and v2.health==180,"golem death leaves living armed villager")
	check(v2.try_repair()==0,"orphan cannot resurrect dead golem")
	var world:Node = load("res://scripts/world.gd").new()
	world._battle_units_cache = [g2,v2,target]
	var sides:Dictionary = world._collect_alive_victory_sides()
	check(sides.has(key) and sides.size()==2,"real world victory logic keeps orphan side alive")
	check(world._is_primary_battle_character(v2),"orphan keeps combat runtime active as continuation")
	check(world.return_battle_sides().members.has(v2.get_meta("battle_continuation_presentation_side_key")),"orphan retains original VS presentation side")
	check(world.return_all_character_names().has("铁傀儡"),"golem registered in actual selector roster")
	check(world._get_character_scene_any("铁傀儡")!=null,"roster resolves golem scene")
	v2.global_position = Vector2(400,0)
	target.global_position = Vector2(470,0)
	ally.global_position = Vector2(900,0)
	behind.global_position = Vector2(900,200)
	v2.direction = Vector2.UP
	v2._throw_wait = 0.0
	v2.step_orphan(target,0.01)
	check(v2.visual_clip=="throw" and is_equal_approx(v2._throw_wait,2.4),"orphan uses slow native throwing windup")
	v2.step_orphan(target,0.23)
	check(v2.direction==Vector2.UP,"throw windup does not stop or steer normal movement")
	var projectile:Node2D = get_nodes_in_group("GolemIronProjectile").back()
	before = target.health
	projectile.advance(0.4)
	check(before-target.health==70,"flying iron ingot deals high damage on real hit")
	check(target.Repel.x>0.0,"iron ingot applies small knockback")
	check(projectile._spent,"iron ingot is consumed by first hit")
	projectile.advance(0.4)
	check(before-target.health==70,"spent ingot cannot damage twice")
	clear_control(target)
	v2._throw_left = 0
	v2.step_orphan(target,0.1)
	check(v2.visual_clip!="throw","orphan cannot throw every frame")
	v2.launch_iron(Vector2.UP)
	projectile = get_nodes_in_group("GolemIronProjectile").back()
	var start:Vector2 = projectile.global_position
	game.now_stop_state = true
	projectile.advance(1.0)
	check(projectile.global_position==start,"pause freezes projectile travel")
	game.now_stop_state = false
	projectile.set_multiplayer_authority(2)
	projectile.heading = Vector2.RIGHT
	projectile.global_position = Vector2(400,0)
	before = target.health
	projectile.advance(0.4)
	check(target.health==before,"remote iron visual never deals damage")
	projectile.set_multiplayer_authority(1)
	projectile.heading = Vector2.UP
	projectile.advance(2.0)
	check(projectile._spent,"missed ingot expires at maximum range")
	barrier = wall_at(Vector2(435,0))
	await physics_frame
	await process_frame
	v2.launch_iron(Vector2.RIGHT)
	projectile = get_nodes_in_group("GolemIronProjectile").back()
	before = target.health
	projectile.advance(0.5)
	check(projectile._spent and target.health==before,"iron ingot hits the obstacle instead of an enemy behind it")
	barrier.free()
	world._battle_units_cache = [v2,target] # A real World unregisters freed g2; mirror that here.
	v2.health = 0
	check(not world._collect_alive_victory_sides().has(key),"only both deaths remove original side from victory logic")
	world.free()
	for event:String in ["attack","hurt","death","damage","repair","step"]:
		check(g.PAIR_SOUNDS.EVENTS.has("entity.iron_golem."+event),"native golem sound event: "+event)
	check(g.PAIR_SOUNDS.EVENTS.has("entity.villager.hurt") and g.PAIR_SOUNDS.EVENTS.has("entity.villager.death"),"native villager voices installed")
	print("IRON_GOLEM_PAIR_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
