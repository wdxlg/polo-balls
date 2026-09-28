extends "res://tests/test_mc_moss_feedback.gd"
## Body/terrain contact and per-cell cooldown regression; no centre-point fallback.
func body_shape(unit:Node2D,shape:Shape2D) -> void:
	unit.scale = Vector2.ONE
	unit.rotation = 0.0
	var body:CollisionShape2D = unit.get_node("CollisionShape2D")
	body.transform = Transform2D.IDENTITY
	body.disabled = false
	body.shape = shape
func rectangle(size:Vector2) -> RectangleShape2D:
	var shape := RectangleShape2D.new()
	shape.size = size
	return shape
func field(unit:Node2D,point:Vector2,entries:Array) -> void:
	unit.cancel_burrow()
	unit.cancel_cultivation()
	unit.patches.clear()
	unit._damage_until.clear()
	unit.clock += 2.0
	unit.global_position = point
	for entry:Vector3 in entries:
		for layer:int in range(int(entry.z)):
			check(unit.plant(point+Vector2(entry.x,entry.y)*unit.CELL),"fixture plant")
func loss(unit:Node2D,victim:Node2D) -> int:
	var hp:int = victim.health
	unit.check_trampling()
	return hp-victim.health
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(70.0).timeout.connect(func(): finish(2))
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	var moss:Node2D = actor("苔藓",center)
	var point:Vector2 = moss.point_for_cell(moss.cell_at(center))
	var target:Node2D = dummy(point)
	var friend:Node2D = dummy(point,"Team0")
	var scheduler:Node = moss.FOOTSTEPS.ensure(moss)
	scheduler.set_physics_process(false)
	await physics_frame
	check(moss.Max_health==500 and moss.health==500 and moss.default_properties.Max_health==500,"spawn has 500 current and maximum HP")
	body_shape(target,rectangle(Vector2(4,4)))
	body_shape(moss,rectangle(Vector2(4,4)))
	field(moss,point,[Vector3(0,0,1)])
	target.global_position = point+Vector2(9.5,0)
	check(moss.cell_at(target.global_position)!=moss.cell_at(point),"edge fixture centre is outside moss cell")
	check(loss(moss,target)==10,"body edge overlapping tile triggers without centre entering")
	check(friend.health==10000,"friendly bodies are not damaged")
	check(loss(moss,target)==0,"same cell cannot tick twice immediately")
	moss.clock += 0.79
	check(loss(moss,target)==0,"same cell respects 0.8 second cooldown")
	moss.clock += 0.02
	check(loss(moss,target)==10,"same cell ticks again after cooldown")
	moss.clock += 1.0
	target.global_position = point+Vector2(10.2,0)
	check(loss(moss,target)==0,"body outside tile does not trigger")
	field(moss,point,[Vector3(0,0,1),Vector3(1,0,2)])
	target.global_position = point+Vector2(8,0)
	check(loss(moss,target)==30,"straddling two cells triggers both layer-weighted damages")
	check(loss(moss,target)==0,"both cells independently remain on cooldown")
	check(target.Buff_Dic[moss.get_instance_id()]["苔藓缠足"].amount==0.5,"strongest touched slow wins")
	moss.patches.reverse()
	moss.check_trampling()
	check(target.Buff_Dic[moss.get_instance_id()]["苔藓缠足"].amount==0.5,"reversing patch order cannot weaken slow")
	check(moss.patches.size()==2 and moss.patch_at(point).layers==1,"trampling does not consume terrain")
	field(moss,point,[Vector3(0,0,1),Vector3(1,0,1)])
	target.global_position = point
	check(loss(moss,target)==10,"first tile hits before crossing")
	moss.clock += 0.1
	target.global_position = point+Vector2(8,0)
	check(loss(moss,target)==10,"new tile hits while first tile is cooling down")
	moss.clock += 0.71
	check(loss(moss,target)==10,"first tile resumes without resetting second tile timer")
	moss.clock += 0.1
	check(loss(moss,target)==10,"second tile resumes on its own staggered timer")
	field(moss,point,[Vector3(0,0,1),Vector3(1,0,1),Vector3(0,1,1),Vector3(1,1,1)])
	target.global_position = point+Vector2(8,8)
	check(loss(moss,target)==40,"four-cell corner independently triggers all four cells")
	var duplicate := CollisionShape2D.new()
	duplicate.shape = rectangle(Vector2(4,4))
	target.add_child(duplicate)
	moss._damage_until.clear()
	check(loss(moss,target)==40,"multiple body shapes never duplicate a cell hit")
	duplicate.queue_free()
	await process_frame
	field(moss,point,[Vector3(0,0,1)])
	var circle := CircleShape2D.new()
	circle.radius = 2.0
	body_shape(target,circle)
	target.global_position = point+Vector2(9.6,9.6)
	check(loss(moss,target)==0,"circle AABB corner is not a real tile contact")
	target.global_position = point+Vector2(9.2,9.2)
	check(loss(moss,target)==10,"true circular corner contact triggers")
	body_shape(target,rectangle(Vector2(12,2)))
	target.rotation = PI*0.25
	target.global_position = point+Vector2(12,0)
	moss._damage_until.clear()
	check(loss(moss,target)==10,"rotated real body reaches tile beyond centre")
	target.get_node("CollisionShape2D").disabled = true
	moss._damage_until.clear()
	check(loss(moss,target)==0,"disabled body shape cannot trample")
	body_shape(target,rectangle(Vector2(4,4)))
	target.get_node("CollisionShape2D").position = Vector2(-8,0)
	target.global_position = point+Vector2(17,0)
	check(loss(moss,target)==10,"local body offset is included in contact")
	body_shape(target,rectangle(Vector2(4,4)))
	target.scale = Vector2(2,2)
	target.global_position = point+Vector2(11.5,0)
	moss._damage_until.clear()
	check(loss(moss,target)==10,"body world scaling is included in contact")
	body_shape(target,rectangle(Vector2(4,4)))
	field(moss,point,[Vector3(0,0,1)])
	target.global_position = point
	check(loss(moss,target)==10,"original patch hits")
	var old_serial:int = moss.patch_at(point).serial
	moss.destroy_moss_obstacle(point,old_serial)
	check(loss(moss,target)==0,"destroyed tile stops damage immediately")
	check(moss.plant(point),"replant destroyed tile")
	check(moss.patch_at(point).serial!=old_serial and loss(moss,target)==10,"new patch lifetime does not inherit destroyed patch cooldown")
	moss._damage_until.clear()
	moss.Damage = 32
	check(loss(moss,target)==20,"per-cell damage still uses current attack attribute")
	moss.Damage = 16
	moss.burrow_wait = 999.0
	moss.growth_left = 999.0
	moss.health = 300
	moss.global_position = point+Vector2(-9.5,0)
	moss._heal_left = 0.0
	moss.step_mob(0.01)
	check(moss.health==306,"owner body edge counts as on moss for healing")
	moss.health = 499
	moss._heal_left = 0.0
	moss.step_mob(0.01)
	check(moss.health==500,"contact healing clamps at new maximum")
	moss.burrow_wait = 0.0
	target.global_position = point+Vector2(9.5,0)
	check(moss.begin_burrow() and moss.burrow_destination==point,"both bodies touching same tile enable burrow without centres inside")
	moss.cancel_burrow()
	moss.burrow_wait = 999.0
	var hp:int = target.health
	var before_clock:float = moss.clock
	game.now_stop_state = true
	moss.tick_physics(0,2.0)
	check(target.health==hp and moss.clock==before_clock,"pause freezes contact damage and clocks")
	game.now_stop_state = false
	# The damage fixtures deliberately emit many simultaneous hit voices. Clear those
	# before testing steps so the unrelated global 24-voice cap does not hide them.
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		sound.stop()
		sound.remove_from_group("MCNativeSFX")
		sound.queue_free()
	await process_frame
	scheduler.states.clear()
	reset_sound(target,"block.moss.step")
	target.global_position = point+Vector2(9.5,0)
	scheduler.sample(0.1)
	target.global_position.y += 1.0
	scheduler.sample(0.1)
	check(sounds("block.moss.step").size()==1,"edge walking triggers real moss footstep")
	reset_sound(target,"block.moss.step")
	scheduler.states.clear()
	field(moss,point,[Vector3(0,0,1),Vector3(1,0,1)])
	target.global_position = point+Vector2(8,0)
	scheduler.sample(0.1)
	target.global_position.y += 1.0
	scheduler.sample(0.1)
	check(sounds("block.moss.step").size()==1,"two touched cells produce one non-overlapping walking sound")
	var regions:Array = moss.get_debug_attack_regions()
	check(regions.size()==2 and regions[0].shape=="rect" and regions[0].half_extents==Vector2(8,8),"threat regions match actual 16x16 square tiles")
	var other:Node2D = actor("苔藓",point+Vector2(32,0))
	field(moss,point,[Vector3(0,0,1)])
	check(other.plant(point+Vector2(16,0)),"second owner plants adjacent tile")
	target.global_position = point+Vector2(8,0)
	hp = target.health
	moss.check_trampling()
	other.check_trampling()
	check(target.health==hp-20,"different owners also independently trigger at shared boundary")
	print("MOSS CONTACT CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
