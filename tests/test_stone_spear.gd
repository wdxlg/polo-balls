extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
var spear:Variant
var game:Node
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
		shape.radius = 7.0
		child.shape = shape
	return unit
func reset_pose(form:int=0) -> void:
	spear.formation = form
	spear._facing = 0.0
	spear._formation_heading = 0.0
	spear._formation_center = Vector2.ZERO
	spear._orbit = 0.0
	spear._stab_time = -1.0
	spear._transition_left = 0.0
	spear._switch_wait = 100.0
	spear._stab_wait = 100.0
	spear.global_position = Vector2.ZERO
	spear._last_body_position = Vector2.ZERO
	spear._main_shift = 0.0
	spear.direction = Vector2.RIGHT
	spear.permanent_speed_bonus = 0.0
	spear.dizziness = false
	spear.Can_Attack = true
	spear.Can_Skill = true
	spear._tip_speeds.fill(0.0)
	for item:Dictionary in spear._hits: item.clear()
	for item:Dictionary in spear._stroke_hits: item.clear()
	for i:int in range(4):
		var pose:Dictionary = spear.formation_pose(i,0.0)
		spear._centers[i] = pose.offset
		spear._angles[i] = pose.angle
	spear._apply_pose()
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("STONE_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var packed:PackedScene = load("res://scenes/characters/我的世界/石矛.tscn")
	check(packed!=null,"production scene loads")
	if packed==null: quit(1); return
	spear = packed.instantiate()
	spear.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	spear.Team = "Team0"
	arena.add_child(spear)
	await process_frame
	check(spear.Max_health==600 and spear.Damage==20 and spear.Speed==170.0,"base parameters")
	check(spear._copies.size()==4,"exactly four persistent copies")
	check(spear.TEXTURE.get_size()==Vector2(32,32) and spear.ICON.get_size()==Vector2(16,16),"native hand and inventory assets")
	for sprite:Sprite2D in spear._copies:
		check(is_equal_approx(sprite.modulate.a,0.78) and sprite.texture==spear.TEXTURE,"native translucent copy")
	check(not spear.Has_Collision_Damage and spear.self_hitbox.collision_mask==0,"shaft/body cannot do contact damage")
	check(spear.get_preview_texture()==spear.ICON,"selection icon is original stone spear")
	check(spear.player_control_action_ids().size()==2,"only two active manual actions")
	check(not spear.player_control_action_hold_repeat_allowed(1),"holding switch does not auto spam")
	reset_pose()
	var last_damage:float = -1.0
	for speed_value:float in [0.0,10.0,50.0,102.0,200.0,400.0,1000.0,10000.0]:
		var amount:float = spear.damage_at_speed(speed_value)
		check(amount>last_damage,"strictly increasing speed damage %s" % speed_value)
		last_damage = amount
	check(is_equal_approx(spear.damage_at_speed(102.0),5.0),"reference real speed gives quarter base attack")
	spear.Damage = 40
	check(is_equal_approx(spear.damage_at_speed(102.0),10.0),"current attack property scales reduced damage")
	spear.Damage = 20
	for i:int in range(4):
		var slow:Dictionary = spear.formation_pose(i,30.0)
		var fast:Dictionary = spear.formation_pose(i,1000.0)
		check(absf(slow.offset.x)<0.001,"follow formation perpendicular to spear")
		check(fast.offset.length()<slow.offset.length(),"faster follow formation closer to body")
		check(spear.follow_response(i,1000)>spear.follow_response(i,30),"faster follow formation catches up sooner")
	check(spear.follow_response(1,100)<spear.follow_response(0,100),"outer copies have more lag")
	check(spear._centers[1].length()>spear._centers[0].length(),"two distinct ranks on each side")
	reset_pose(1)
	for i:int in range(4):
		var pose:Dictionary = spear.formation_pose(i,100)
		check(is_equal_approx(pose.offset.length(),16.0),"orbit stays one grid away")
		check(absf(pose.offset.normalized().dot(Vector2.from_angle(pose.angle)))<0.001,"orbit spear points tangent")
	check(spear.orbit_rate(300)>spear.orbit_rate(30),"movement speed increases rotation")
	check(spear.damage_at_speed(spear.orbit_rate(300)*22)>spear.damage_at_speed(spear.orbit_rate(30)*22),"rotation speed increases contact damage")
	reset_pose(2)
	check(spear.stab_reach(500)>spear.stab_reach(20),"speed extends stab reach")
	check(spear.get_ai_attack_threats(null).is_empty(),"idle stab has no threat")
	spear._stab_wait=0.0
	spear._real_speed=102.0
	check(spear.begin_stab(),"stroke can start")
	check(not spear.begin_stab(),"stroke cannot overlap")
	check(is_equal_approx(spear.stroke_offset(0),0.0),"stroke begins at rest")
	check(is_equal_approx(spear.stroke_offset(spear.stab_out_time),spear._stab_distance),"stroke reaches actual peak")
	check(is_equal_approx(spear.stroke_offset(spear.stab_out_time+spear.stab_return_time),0.0),"elastic return ends at rest")
	spear._stab_time=spear.stab_out_time+0.1
	spear._tip_speeds.fill(100.0)
	check(spear.get_ai_attack_threats(null).is_empty(),"return has no damaging threat")
	reset_pose()
	spear.permanent_speed_bonus=37.0
	spear._switch_wait=0.0
	var old:int = spear.formation
	check(spear.choose_formation() and spear.formation!=old,"random change selects a different stance")
	check(spear.permanent_speed_bonus==37.0,"formation does not consume permanent growth")
	check(not spear.choose_formation(),"switch obeys cooldown")
	var seen:Dictionary = {}
	for n:int in range(30):
		spear._switch_wait=0.0
		old=spear.formation
		spear.choose_formation()
		check(spear.formation!=old,"no immediate random repeat")
		seen[spear.formation]=true
	check(seen.size()==3,"all three formations reachable")
	reset_pose()
	var enemy:Node2D = victim(Vector2(25,0))
	var ally:Node2D = victim(Vector2(25,0),"Team0")
	await physics_frame
	var hp:int = enemy.health
	spear._sweep_tip(0,Vector2.ZERO,Vector2(20,0),0.0,0.0,0.2,Vector2.ZERO)
	check(enemy.health<hp,"real spearhead sweep damages enemy")
	check(ally.health==10000,"same-team excluded")
	hp=enemy.health
	spear._sweep_tip(0,Vector2.ZERO,Vector2(20,0),0.0,0.0,0.2,Vector2.ZERO)
	check(enemy.health==hp,"same head contact deduplicated")
	spear._sweep_tip(1,Vector2.ZERO,Vector2(20,0),0.0,0.0,0.2,Vector2.ZERO)
	check(enemy.health<hp,"different heads have independent contacts")
	enemy.global_position=Vector2(-8,0)
	await physics_frame
	hp=enemy.health
	spear._hits[0].clear()
	spear._sweep_tip(0,Vector2.ZERO,Vector2(1,0),0.0,0.0,0.1,Vector2.ZERO)
	check(enemy.health==hp,"shaft overlap is not a head hit")
	enemy.global_position=Vector2(100,0)
	await physics_frame
	hp=enemy.health
	spear._hits[0].clear()
	spear._sweep_tip(0,Vector2.ZERO,Vector2(200,0),0.0,0.0,0.1,Vector2.ZERO)
	check(enemy.health<hp,"fast sweep does not tunnel through enemy")
	var wall := StaticBody2D.new()
	wall.collision_layer=1
	wall.collision_mask=0
	wall.disable_mode=CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size=Vector2(4,100)
	col.shape=rect
	wall.add_child(col)
	arena.add_child(wall)
	wall.position=Vector2(60,0)
	await physics_frame
	hp=enemy.health
	spear._hits[0].clear()
	spear._sweep_tip(0,Vector2.ZERO,Vector2(200,0),0.0,0.0,0.1,Vector2.ZERO)
	check(enemy.health==hp,"wall rejects through-wall spear damage")
	wall.free()
	reset_pose()
	spear.dizziness=true
	hp=enemy.health
	spear._sweep_tip(0,Vector2.ZERO,Vector2(200,0),0.0,0.0,0.1,Vector2.ZERO)
	check(enemy.health==hp,"stun prevents all spear damage")
	spear.permanent_speed_bonus=75.0
	spear.tick_physics(spear.State.Stand,0.1)
	check(spear.permanent_speed_bonus==75.0,"stun preserves growth")
	spear.dizziness=false
	game.now_stop_state=true
	var old_wait:float=spear._switch_wait
	spear.tick_physics(spear.State.Move,1.0)
	check(spear.permanent_speed_bonus==75.0 and spear._switch_wait==old_wait,"pause freezes growth and formation clocks")
	game.now_stop_state=false
	spear.direction=Vector2.ZERO
	spear.tick_physics(spear.State.Move,0.1)
	check(spear.permanent_speed_bonus==75.0,"stationary does not grow")
	spear.global_position=Vector2(1000,1000)
	spear.tick_physics(spear.State.Move,0.1)
	check(spear.permanent_speed_bonus==75.0,"external relocation is not movement growth")
	spear.direction=Vector2.RIGHT
	for n:int in range(12):
		await physics_frame
		spear.tick_physics(spear.State.Move,1.0/60.0)
	check(spear.permanent_speed_bonus>75.0,"real physics locomotion grows speed")
	check(spear.Speed==170.0,"growth does not overwrite buff-managed Speed")
	var config:SceneReplicationConfig=spear.get_node("MultiplayerSynchronizer").replication_config
	for key:String in ["permanent_speed_bonus","formation","_pose_state","_stab_axes","_stab_time","direction"]:
		check(config.has_property(NodePath(".:"+key)) and config.property_get_spawn(NodePath(".:"+key)),"spawn replication includes "+key)
	check(spear._pose_state.size()==17,"complete four-copy pose snapshot")
	var bonus:float=spear.permanent_speed_bonus
	spear.set_multiplayer_authority(2)
	spear.tick_physics(spear.State.Move,1.0)
	check(spear.permanent_speed_bonus==bonus,"non-authority cannot grow or simulate attacks")
	spear.set_multiplayer_authority(1)
	check(spear.HIT_GAIN.damage_event(50)=="entity.player.hurt" and spear.HIT_GAIN.damage_event(51)=="entity.player.attack.crit","strict actual damage audio threshold")
	check(spear.HIT_GAIN.damage_gain(100)>spear.HIT_GAIN.damage_gain(20),"damage audio gain grows above zero dB baseline")
	game.current_locale="en"
	check("Four" in spear.get_armor_test_effect_summary(),"English character explanation")
	game.current_locale="zh_CN"
	check("四个" in spear.get_armor_test_effect_summary(),"Chinese character explanation")
	check(spear.get_combat_classification().get("entity_kind","")=="character","runtime classification identifies character")

	var roster:Node=load("res://scripts/world.gd").new()
	check(roster.character_scene_path("石矛")=="res://scenes/characters/我的世界/石矛.tscn","production roster discovers stone spear in Minecraft category")
	roster.free()
	# Whole-tick outward/return gating, not just pure formula checks.
	reset_pose(2)
	enemy.global_position=Vector2(0,-40)
	ally.global_position=Vector2(900,900)
	spear.direction=Vector2.ZERO
	spear._stab_wait=0.0
	spear._real_speed=102.0
	check(spear.begin_stab(),"real radial stroke starts")
	await physics_frame
	hp=enemy.health
	spear.tick_physics(spear.State.Stand,0.10)
	check(enemy.health<hp,"outward clone head deals real damage")
	check(spear._main_shift>0.0,"center spear also visibly thrusts")
	check(spear.self_hurtbox.global_position.distance_to(spear.image.global_position)<0.01,"center hurt geometry follows visible thrust")
	spear._stab_time=spear.stab_out_time
	spear._main_shift=spear._stab_distance
	for i:int in range(4):
		var pose:Dictionary=spear.formation_pose(i,0)
		spear._centers[i]=pose.offset
		spear._angles[i]=pose.angle
	for item:Dictionary in spear._hits: item.clear()
	for item:Dictionary in spear._stroke_hits: item.clear()
	hp=enemy.health
	spear.tick_physics(spear.State.Stand,0.10)
	check(enemy.health==hp,"elastic return cannot damage even with fresh contact cache")
	reset_pose(2)
	enemy.global_position=Vector2(0,-31)
	await physics_frame
	hp=enemy.health
	spear.tick_physics(spear.State.Stand,0.10)
	check(enemy.health==hp,"idle radial head touching enemy is harmless")
	reset_pose(0)
	spear.permanent_speed_bonus=125.0
	spear._transition_left=0.35
	enemy.global_position=Vector2(20,0)
	await physics_frame
	hp=enemy.health
	spear.tick_physics(spear.State.Stand,0.10)
	check(enemy.health==hp,"formation transition never creates damage")
	check(spear.permanent_speed_bonus==125.0,"no growth loss through transition")
	spear.Can_Attack=false
	check(spear.get_ai_attack_threats(null).is_empty(),"attack-disabled threats disappear")
	check(not spear.begin_stab(),"attack-disabled cannot begin stroke")
	spear.Can_Attack=true
	spear.Can_Skill=false
	spear._switch_wait=0.0
	check(not spear.choose_formation(),"skill-disabled cannot change formation")
	spear.Can_Skill=true
	spear.player_control_peer_id=1
	spear._switch_wait=0.01
	var controlled_form:int=spear.formation
	spear.tick_physics(spear.State.Stand,0.10)
	check(spear.formation==controlled_form,"manual control suppresses AI formation changes")
	spear.controlled_formation()
	check(spear.formation!=controlled_form,"manual right action changes to another formation")
	reset_pose(2)
	spear._stab_wait=0.0
	spear.tick_physics(spear.State.Stand,0.10)
	check(spear._stab_time<0.0,"manual control suppresses automatic stabbing")
	spear.controlled_stab()
	check(spear._stab_time==0.0,"manual left action starts one stroke")
	check(spear.direction==Vector2.RIGHT,"manual stroke does not steal movement heading")
	spear.player_control_peer_id=0
	print("STONE_SPEAR_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
