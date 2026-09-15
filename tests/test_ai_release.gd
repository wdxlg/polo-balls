extends SceneTree
var checks:int = 0
var failures:int = 0
var world:Node
var game:Node
var saved:Dictionary
var locale:String
var old_stop:bool
var old_scale:float
func check(condition:bool,message:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("AI_FAIL ",message)
func _initialize() -> void:
	call_deferred("run")
func spawn(path:String,team:String,point:Vector2) -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.position = point
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(unit,true)
	return unit
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	locale = game.current_locale
	old_stop = game.now_stop_state
	old_scale = Engine.time_scale
	create_timer(35.0).timeout.connect(func(): finish(2))
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	Engine.time_scale = 1.0
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world._ensure_character_path_index()
	check(world._character_paths_by_folder.has("AI"),"AI category registered")
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var center:Vector2 = rect.get_center()
	var tank:Node2D = spawn("res://scenes/characters/AI/磐灯守卫.tscn","Team0",center)
	var ranger:Node2D = spawn("res://scenes/characters/AI/霆针游侠.tscn","Team0",center+Vector2(0,200))
	var priest:Node2D = spawn("res://scenes/characters/AI/时砂司祭.tscn","Team0",center+Vector2(0,-200))
	for actor:Node2D in [tank,ranger,priest]:
		check(actor.get_script().can_instantiate(),"script loaded")
		check(actor.image.texture != null,"original portrait")
		check(not actor.Has_Collision_Damage,"no unintended body damage")
		check(actor.is_combat_runtime_active(),"combat active")
	check(world._character_paths_by_folder.AI.size() == 3,"three registered originals")
	var dummy:Node2D = spawn("res://scenes/ball.tscn","Team1",center+Vector2(65,0))
	var hp:int = dummy.health
	await tank.Attack()
	check(dummy.health == hp-24,"tank attack damage")
	check(not tank.Attacking,"attack completes")
	tank.Skill()
	var shield:int = tank.block
	tank.take_damage(100)
	check(tank.block == shield-55,"guard mitigation")
	check(is_equal_approx(tank._stored,45.0),"guard stores mitigated damage")
	hp = dummy.health
	tank._tick_trait(1.0)
	check(dummy.health < hp-24,"guard counter includes stored damage")
	check(not tank.Using_Skill,"guard ends")
	tank._quiet_time = 4.0
	shield = tank.block
	tank._tick_trait(1.0)
	check(tank.block == mini(shield+18,140),"out of combat block regen")
	# Two aligned opponents: only the third shot pierces.
	dummy.position = ranger.position+Vector2(90,0)
	var back:Node2D = spawn("res://scenes/ball.tscn","Team1",ranger.position+Vector2(170,0))
	hp = back.health
	await ranger.Attack()
	await ranger.Attack()
	check(back.health == hp,"ordinary shots stop at first victim")
	await ranger.Attack()
	check(back.health == hp-27,"third shot pierces at 1.5x")
	check(ranger._shot_count == 3,"shot cadence")
	# Piercing cannot travel through a physical map wall.
	var wall_body:StaticBody2D = StaticBody2D.new()
	wall_body.process_mode = Node.PROCESS_MODE_ALWAYS
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	var shape:CollisionShape2D = CollisionShape2D.new()
	var rectangle:RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(12,120)
	shape.shape = rectangle
	wall_body.add_child(shape)
	world.add_child(wall_body)
	wall_body.global_position = ranger.global_position+Vector2(140,0)
	ranger._shot_count = 2
	var front_hp:int = dummy.health
	hp = back.health
	await ranger.Attack()
	check(dummy.health == front_hp-27,"piercing hits before wall")
	check(back.health == hp,"wall blocks piercing damage")
	wall_body.queue_free()
	await physics_frame
	# An available but unnecessary close-range skill cannot starve ranged fire.
	var base_script:Script = load("res://classes/ball.gd")
	ranger.state_machine.last_state_dis["Skill"] = 999.0
	ranger.state_machine.last_state_dis["Attack"] = 999.0
	check(ranger.get_next_state(base_script.State.Move) == base_script.State.Attack,"ready unused skill does not block ordinary attacks")
	check(ranger.Can_Skill and ranger.state_machine.last_state_dis["Skill"] == 999.0,"skill readiness preserved")
	# A stun cancels a telegraphed shot without damage or consuming the cadence.
	hp = dummy.health
	ranger.Attack()
	ranger.dizziness = true
	await create_timer(0.25).timeout
	check(dummy.health == hp and ranger._shot_count == 3,"stun interrupts telegraph")
	ranger.dizziness = false
	check(not ranger.Attacking,"interrupted action releases state")
	# Pause holds a telegraph instead of allowing a delayed hit during time stop.
	hp = dummy.health
	ranger.Attack()
	game.now_stop_state = true
	await create_timer(0.3).timeout
	check(dummy.health == hp,"telegraph waits during stop")
	game.now_stop_state = false
	await create_timer(0.3).timeout
	check(dummy.health < hp and not ranger.Attacking,"telegraph resumes once")
	check(not ranger.enemy_valid(tank),"friendly-fire setting respected")
	# Mark -> heal/detonate. Healing must never affect an enemy.
	dummy.position = priest.position+Vector2(80,0)
	back.position = center+Vector2(400,400)
	await priest.Attack()
	check(priest._marks.has(dummy.get_instance_id()),"mark attached")
	var friend:Node2D = spawn("res://scenes/ball.tscn","Team0",priest.position+Vector2(-40,0))
	friend.health_bar.suppress_floating_text = true
	friend.health -= 100
	friend.health_bar.suppress_floating_text = false
	var friend_hp:int = friend.health
	hp = dummy.health
	await priest.Skill()
	check(friend.health == friend_hp+40,"ally healed")
	check(dummy.health == hp-12,"one mark detonates")
	check(priest._marks.is_empty(),"marks consumed")
	await priest.Attack()
	priest._combat_clock += 4.1
	priest._tick_trait(0.0)
	check(priest._marks.is_empty(),"marks expire")
	# A stopped battle cannot deal direct AI damage.
	hp = dummy.health
	game.now_stop_state = true
	check(not priest.deal(dummy) and dummy.health == hp,"time stop damage gate")
	game.now_stop_state = false
	var cue:Node2D = load("res://scripts/effects/AI/原创战斗反馈.gd").new()
	world.add_child(cue)
	cue.configure(0,center,center,Color.WHITE,50.0,1.0)
	game.now_stop_state = true
	cue._process(0.5)
	check(cue.elapsed == 0.0,"telegraph visual pauses with action")
	game.now_stop_state = false
	cue._process(0.1)
	check(is_equal_approx(cue.elapsed,0.1),"telegraph visual resumes")
	cue.queue_free()
	# Actual GPU renders for all four blade kinds / both variants.
	var viewport:SubViewport = SubViewport.new()
	viewport.size = Vector2i(1000,620)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background:ColorRect = ColorRect.new()
	background.size = Vector2(1000,620)
	background.color = Color("111922")
	viewport.add_child(background)
	caption(viewport,"AI  /  ORIGINAL ROSTER",Vector2(26,18),24)
	for i:int in range(3):
		var portrait:Sprite2D = Sprite2D.new()
		portrait.texture = [tank,ranger,priest][i].image.texture
		portrait.position = Vector2(185+315*i,140)
		portrait.scale = Vector2.ONE*0.85
		viewport.add_child(portrait)
		caption(viewport,["磐灯守卫 · WARDEN","霆针游侠 · LANCER","时砂司祭 · ORACLE"][i],Vector2(85+315*i,258),20)
	caption(viewport,"THE RED MIST  /  NORMAL",Vector2(26,308),18)
	caption(viewport,"E.G.O  /  MIMICRY",Vector2(26,453),18)
	for i:int in range(8):
		var effect:Node2D = load("res://scripts/effects/殷红迷雾_刀光.gd").new()
		viewport.add_child(effect)
		effect.position = Vector2(95+240*(i%4),365+145*(i/4))
		effect.configure(i%4,Vector2(210,100),65,Color(0.94,0.03,0.05),0.72,1.0,Vector2(-60,0),i>=4)
		effect.set_process(false)
		effect._elapsed = 0.10
		effect._update_material(0.14)
		check(effect.get_child_count() == 1,"single sprite blade budget")
		check(effect.z_index < 99,"blade below health UI")
	for i:int in range(4):
		caption(viewport,["THRUST","SLASH","HORIZONTAL","EXECUTION"][i],Vector2(66+i*240,592),15)
	await RenderingServer.frame_post_draw
	var image:Image = viewport.get_texture().get_image()
	check(not image.is_empty(),"GPU preview readable")
	image.save_png("res://scripts/training/ai_mist_preview.png")
	print("AI_RELEASE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	viewport.queue_free()
	finish(0 if failures == 0 else 1)
func finish(code:int) -> void:
	if game != null:
		game.Game_Settings = saved
		game.current_locale = locale
		game.now_stop_state = old_stop
	Engine.time_scale = old_scale
	if is_instance_valid(world):
		world.queue_free()
	current_scene = null
	quit(code)

func caption(parent:Node,text:String,point:Vector2,size:int) -> void:
	var label:Label = Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("c7d3db"))
	parent.add_child(label)
