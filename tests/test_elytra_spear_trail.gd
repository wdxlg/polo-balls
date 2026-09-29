extends "res://tests/test_elytra_spear.gd"
func snapshots() -> Array[Node]:
	var result:Array[Node] = []
	for child:Node in arena.get_children():
		if child is Sprite2D and child.texture != null and child.texture.resource_path.ends_with("elytra_spear/netherite_spear.png"):
			result.append(child)
	return result
func run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var spear:Node2D = load("res://scenes/characters/我的世界/鞘翅长矛.tscn").instantiate()
	arena.add_child(spear)
	check(spear.allows_character_motion_effects(),"new spear explicitly opts into motion snapshots")
	check(spear.AfterImage_Speed==342.0,"high-speed threshold matches piercing threshold")
	prepare(spear,Vector2.ZERO,Vector2.RIGHT*280.0)
	spear._reset_after_image_sampling()
	spear._process_auto_after_image(0.2)
	spear.global_position += Vector2(56,0)
	spear._process_auto_after_image(0.2)
	check(snapshots().is_empty(),"normal 280-speed flight creates no snapshots")
	spear.global_position += Vector2(30,0)
	spear._process_auto_after_image(0.05)
	check(snapshots().size()==4,"600-speed flight emits bounded snapshots without an enemy or attack")
	var ghost:Sprite2D = snapshots()[0] as Sprite2D
	check(ghost.z_index>=100 and ghost.z_index<spear.image.z_index,"snapshots render above the map mask and behind the spear")
	check(ghost.texture==spear.image.texture,"snapshots use the actual netherite spear")
	check(ghost.global_position.x<spear.image.global_position.x,"snapshots remain behind the moving spear")
	check(ghost.get_children().is_empty(),"snapshots do not copy combat or collision nodes")
	var count:int = snapshots().size()
	spear.global_position += Vector2(5,0)
	spear._process_auto_after_image(0.05)
	check(snapshots().size()==count,"slowing stops new snapshots")
	game.now_stop_state = true
	spear.global_position += Vector2(30,0)
	spear._process_auto_after_image(0.05)
	check(snapshots().size()==count,"paused combat emits no snapshots")
	game.now_stop_state = false
	spear._process_auto_after_image(0.05)
	spear.global_position += Vector2(500,0)
	spear._process_auto_after_image(0.05)
	check(snapshots().size()==count,"teleports do not leave map-wide trails")

	# Real authority tick path calls the base automatic sampler once, not twice.
	prepare(spear,Vector2.ZERO,Vector2.RIGHT*600)
	spear._reset_after_image_sampling()
	spear.tick_physics(spear.State.Move,0.05)
	count = snapshots().size()
	spear.tick_physics(spear.State.Move,0.05)
	check(snapshots().size()>count and snapshots().size()<=count+4,"real flight tick generates one bounded trail batch")
	# Remote replicas use synchronized position changes, not unsynchronized flight speed.
	spear.set_multiplayer_authority(2)
	spear._reset_after_image_sampling()
	spear.tick_physics(spear.State.Move,0.05)
	count = snapshots().size()
	spear.global_position += Vector2(30,0)
	spear.tick_physics(spear.State.Move,0.05)
	check(snapshots().size()>count,"remote replica also emits trails from received movement")
	count = snapshots().size()
	spear.health = 0
	spear.global_position += Vector2(30,0)
	spear._process_auto_after_image(0.05)
	check(snapshots().size()==count,"death stops new snapshots")
	spear.process_mode = Node.PROCESS_MODE_DISABLED
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	await create_timer(0.4).timeout
	check(snapshots().is_empty(),"snapshots fade and free themselves")
	print("ELYTRA_SPEAR_TRAIL_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
