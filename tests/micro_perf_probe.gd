extends SceneTree
var world:Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game:Node = root.get_node("Game")
	game.Game_Settings["Training_Mode"] = false
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.visible = false
	await create_timer(0.5).timeout
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	for i in range(120):
		world.create_char("Team0" if i % 2 == 0 else "Team1","小刀猎",rect.position + rect.size * Vector2(0.1 + 0.8 * float(i % 12) / 11.0,0.1 + 0.8 * float(i / 12) / 9.0))
	await create_timer(0.5).timeout
	var units:Array = world.get_battle_units_fast()
	var u = units[0]
	print("unit=",u.name," image=",u.image.get_class()," frames=",u.image.sprite_frames.get_animation_names())
	# (a) image.animation 切换
	var t0:int = Time.get_ticks_usec()
	for i in range(2000):
		u.image.animation = "Attack" if i % 2 == 0 else "Idle"
	print("animation set x2000: ",(Time.get_ticks_usec()-t0)/2000.0," us each")
	# (a2) 带信号连接数
	print("animation_changed connections: ",u.image.animation_changed.get_connections().size()," frame_changed: ",u.image.frame_changed.get_connections().size(), " item_rect_changed: ",u.image.item_rect_changed.get_connections().size())
	# (b) transition_state Stand<->Attack (直接调用，不含 Attack() 本体？会调用 Attack)
	t0 = Time.get_ticks_usec()
	for i in range(200):
		u.transition_state(u.State.Stand,u.State.Hurt)
		u.transition_state(u.State.Hurt,u.State.Stand)
	print("transition_state Stand<->Hurt x400: ",(Time.get_ticks_usec()-t0)/400.0," us each")
	t0 = Time.get_ticks_usec()
	for i in range(200):
		u.hurting_timer.start(0.5)
	print("hurting_timer.start x200: ",(Time.get_ticks_usec()-t0)/200.0," us each")
	# (c) knife spawn
	var knife_scene:PackedScene = load("res://scenes/shooter/knife.tscn")
	var RK = load("res://classes/runtime_knife_scene.gd")
	var spawned:Array = []
	t0 = Time.get_ticks_usec()
	for i in range(100):
		var k = RK.instantiate(world,knife_scene)
		spawned.append(k)
	var t_inst:int = Time.get_ticks_usec()-t0
	t0 = Time.get_ticks_usec()
	for k in spawned:
		k.Master = u
		k.Team = u.Team
		k.global_position = u.global_position
		world.add_child(k,true)
	var t_add:int = Time.get_ticks_usec()-t0
	print("knife instantiate: ",t_inst/100.0," us; add_child: ",t_add/100.0," us; nodes per knife=",_count(spawned[0]))
	var names:Array = []
	for c in spawned[0].get_children(): names.append(c.name + "(" + c.get_class() + ")")
	print("knife children: ",names)
	t0 = Time.get_ticks_usec()
	for k in spawned: k.free()
	print("knife free: ",(Time.get_ticks_usec()-t0)/100.0," us")
	# (d) Die transition on a fresh unit
	var v = units[1]
	t0 = Time.get_ticks_usec()
	v.health = 0
	v.state_machine.current_state = v.State.Die
	print("die transition: ",(Time.get_ticks_usec()-t0)," us")
	quit()
func _count(n:Node) -> int:
	var c:int = 1
	for ch in n.get_children(true): c += _count(ch)
	return c
