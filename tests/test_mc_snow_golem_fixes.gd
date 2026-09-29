extends "res://tests/test_mc_snow_golem.gd"
## Regression for melting, actor/projectile occlusion and competing facing writers.
func effective_z(item:CanvasItem) -> int:
	var result:int = item.z_index
	var node:CanvasItem = item
	while node.z_as_relative:
		var parent:Node = node.get_parent()
		if not parent is CanvasItem: break
		node = parent as CanvasItem
		result += node.z_index
	return result

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(50.0).timeout.connect(func(): finish(2))
	var golem:Node2D = load(GOLEM_PATH).instantiate()
	golem.direction = Vector2.RIGHT
	golem.position = center
	golem.Team = "Team0"
	world.add_child(golem,true)
	golem.state_machine.set_physics_process(false)
	var enemy:Node2D = dummy(center+Vector2(120,0))
	var field:Node2D = golem._field
	field.set_physics_process(false)
	check(golem._aim_hold_left==0.0 and golem._aim_pose==2 and not golem.is_character_visual_flipped_h(),"fresh right-moving golem selects a native diagonal view with no extra mirror")
	check(field.full_snow_lifetime == 8.0 and field.snow_fade_duration == 0.3,"snow exposes eight melt-seconds plus a short fixed-footprint fade")
	field.full_snow_lifetime = 2.0
	field.snow_fade_duration = 1.0
	var cell:Vector2i = field.snow_cell_at(center)
	check(field.deposit(golem,cell,false),"new full tile receives an expiring lifetime")
	check(is_equal_approx(field.patches[cell].expires_at-field._melt_clock,2.0),"full tile is stamped with its own deadline")
	park_contact(field,enemy,center)
	field.advance(0.01)
	check(enemy.health == 9997 and enemy.get_node("MCSnowCold").amount == 8.0,"fresh full snow still deals damage and cold")
	field.advance(1.98)
	check(field.patches[cell].level == 2,"snow stays full before the full-stage deadline")
	var hp:int = enemy.health
	var amount:float = enemy.get_node("MCSnowCold").amount
	field.advance(0.02)
	check(field.patches[cell].level == 2 and field.snow_alpha(field.patches[cell])<1.0,"full tile begins an opacity fade without a half-size stage")
	check(is_equal_approx(field.patches[cell].expires_at,2.0),"fade retains its original solid deadline without extending a late tick")
	field.advance(0.6)
	check(enemy.health == hp and enemy.get_node("MCSnowCold").amount == amount,"fading snow is immediately harmless: no damage and no added cold")
	field.advance(0.38)
	check(field.patches.has(cell) and field.snow_alpha(field.patches[cell])>0.0,"fading snow remains visible until its opacity reaches zero")
	field.advance(0.02)
	check(not field.patches.has(cell),"full-footprint snow disappears after its short fade")
	clear_cold(enemy)
	park_contact(field,enemy,center+Vector2(192,144))

	# The retired half-size deposit flag now produces the same full block.
	var partial_cell:Vector2i = cell+Vector2i(-4,0)
	field.deposit(golem,partial_cell,true)
	var deadline:float = field.patches[partial_cell].expires_at
	game.now_stop_state = true
	field.advance(100.0)
	check(field.patches.has(partial_cell) and field.patches[partial_cell].expires_at==deadline,"gameplay pause consumes no partial-snow lifetime")
	game.now_stop_state = false
	paused = true
	var before_clock:float = field._clock
	field.advance(100.0)
	check(field._clock==before_clock,"SceneTree pause also stops melting")
	paused = false
	field.advance(3.01)
	check(not field.patches.has(partial_cell),"whole snow expires without a half stage or construction consumer")
	field.deposit(golem,partial_cell,true)
	check(field.deposit(golem,partial_cell,false) and field.patches[partial_cell].level==2,"a fresh ordinary deposit restores full snow")
	field.advance(0.7)
	check(field.deposit(golem,partial_cell,false) and is_equal_approx(field.patches[partial_cell].expires_at-field._melt_clock,2.0),"real revisit refreshes a still-full tile")
	field.advance(10.0)
	check(field.patches.is_empty(),"large delta removes elapsed solid and fade periods")
	check(not field.has_method("_land_head") and not field.has_method("_spawn_mini"),"melting no longer interleaves retired pumpkin landing or birth")

	# Host and visual replica can have different clocks; transfer remaining life.
	field.full_snow_lifetime = 2.0
	field.snow_fade_duration = 1.0
	field.deposit(golem,cell,false)
	field.advance(0.4)
	var snapshot:Array = field._cell_snapshot([cell])
	check(is_equal_approx(snapshot[0].remaining,1.6) and snapshot[0].fade_duration == 1.0,"terrain snapshot includes relative melt time and fade duration")
	var replica:Node2D = load("res://scenes/effects/我的世界/雪傀儡雪地.tscn").instantiate()
	replica.name = "SnowLifetimeReplica"
	world.add_child(replica,true)
	# Offline mirror fixture: change authority after _ready(), so it does not
	# send a deferred initial-state RPC to a nonexistent real peer.
	replica.set_multiplayer_authority(2)
	replica.set_physics_process(false)
	replica._clock = 100.0
	replica._melt_clock = 100.0
	replica._field_state(snapshot,[],true)
	check(is_equal_approx(replica.patches[cell].expires_at,101.6),"visual replica does not mistake a different host clock for instant expiry")
	replica._physics_process(1.61)
	check(replica.patches[cell].level == 2 and replica.snow_alpha(replica.patches[cell])<1.0,"replica shows the same fixed-size fading stage between updates")
	replica._physics_process(1.0)
	check(not replica.patches.has(cell),"replica also removes expired fading snow")
	replica._field_state(snapshot,[],true)
	replica._field_state([{"cell":cell,"level":0}],[],false)
	check(not replica.patches.has(cell),"authoritative removal cannot leave a ghost client tile")
	replica.queue_free()

	# Ordinary actors/projectiles, not only our specially drawn snow golem.
	var bullet:Node2D = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(96,-48))
	var snowball:Node2D = spawn("res://scenes/shooter/我的世界/雪球.tscn",center+Vector2(144,-48))
	check(effective_z(field) < effective_z(enemy.image),"snow floor is below an ordinary unmodified character")
	check(effective_z(field) < effective_z(bullet.image) and effective_z(field) < effective_z(snowball.image),"snow is below both stock projectiles and native snowballs")
	check(not field.has_method("drop_head"),"no construction prop can conceal pass-through actors or bullets")
	var old_z:int = world.z_index
	world.z_index = 17
	check(effective_z(field) < effective_z(enemy.image) and effective_z(field) < effective_z(bullet.image),"relative floor ordering also survives a changed World layer")
	world.z_index = old_z
	check(effective_z(golem.image) == effective_z(enemy.image),"snow golem no longer needs a special raised-body workaround")
	bullet.queue_free()
	snowball.queue_free()

	# Walking uses the two front diagonals; all sixteen attack views are covered by the burst suite.
	golem.global_position = center+Vector2(-216,-144)
	golem.burst_probability = 0.0
	var mirror:Node2D = spawn(GOLEM_PATH,center+Vector2(-144,-144))
	mirror.burst_probability = 0.0
	for unit:Node2D in [golem,mirror]:
		for pumpkin:bool in [true,false]:
			unit.has_pumpkin = pumpkin
			var expected_walk:int = 2
			for heading:Vector2 in [Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2(-1,-1).normalized(),Vector2(1,1).normalized()]:
				unit._aim_hold_left = 0.0
				unit.direction = heading
				if absf(heading.x)>0.01: expected_walk = 2 if heading.x>0 else 6
				unit.move(0.0,0.016)
				var physics_pose:int = unit._aim_pose
				unit.visual_mob()
				check(physics_pose==expected_walk and unit._aim_pose==physics_pose and not unit.is_character_visual_flipped_h() and unit.image.rotation==0.0,"physics/render use the same native view pumpkin=%s heading=%s" % [pumpkin,heading])
	golem.has_pumpkin = true
	golem.set_player_control_peer(1)
	golem.direction = Vector2.LEFT
	golem.set_player_control_direction(Vector2.RIGHT)
	golem.move(0.0,0.016)
	check(golem._aim_pose==2 and not golem.is_character_visual_flipped_h(),"manual right input wins without mirroring a diagonal view")
	golem.set_player_control_direction(Vector2.LEFT)
	golem.move(0.0,0.016)
	check(golem._aim_pose==6 and not golem.is_character_visual_flipped_h(),"manual left selects its own native diagonal")
	golem.set_player_control_peer(0)
	golem.direction = Vector2.LEFT
	golem._shot_left = 0.0
	check(golem.fire_at(golem.global_position+Vector2(100,0)),"real shot starts a short aim hold")
	golem.move(0.0,0.016)
	check(golem._aim_pose==0 and golem._aim_hold_left>0.0,"shot aim wins temporarily over opposite movement")
	game.now_stop_state = true
	var hold:float = golem._aim_hold_left
	golem.tick_physics(0,1.0)
	check(golem._aim_hold_left==hold,"pause preserves aim hold")
	game.now_stop_state = false
	golem.step_mob(golem.aim_hold_duration+0.01)
	golem.visual_mob()
	check(golem._aim_pose==6 and golem._aim_hold_left==0.0,"expired hold returns to actual movement")
	golem.direction = Vector2.UP
	golem.visual_mob()
	check(golem._aim_pose==6,"up walking preserves the previous left diagonal")
	golem.direction = Vector2.DOWN
	golem.visual_mob()
	check(golem._aim_pose==6,"down walking also preserves the previous left diagonal")
	var view_state:Dictionary = golem.network_visual_state()
	mirror.set_multiplayer_authority(2)
	mirror.direction = Vector2.LEFT
	mirror.accept_visual(view_state)
	mirror.visual_mob()
	check(mirror._visual_heading==golem._visual_heading and mirror._aim_pose==golem._aim_pose and not mirror.is_character_visual_flipped_h(),"replica uses authoritative full heading, not stale local movement")
	print("SNOW_FIXES_ASSERTIONS checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
