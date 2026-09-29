extends "res://tests/test_drowned_surface_probe.gd"
## Current gameplay contract: aiming chooses direction; only real obstacle contact lodges.
var next_id:int = 2000
func owned_spear() -> Node2D:
	if is_instance_valid(caster._trident): caster._trident.retire()
	next_id += 1
	var spear:Node2D = new_spear(next_id)
	caster._trident = spear
	caster.has_trident = true
	caster._throw_left = -1.0
	caster._throw_target = null
	caster._refill_show_left = 0.0
	caster._catch_left = 0.0
	caster._refill_left = -1.0
	return spear
func fly(spear:Node2D,seconds:float,dt:float = 1.0/120.0) -> void:
	var elapsed:float = 0.0
	while elapsed < seconds and spear.flight_state == 1:
		spear.advance(dt)
		elapsed += dt
func run() -> void:
	await setup_probe()
	create_timer(50.0).timeout.connect(func(): finish(2))
	var start:Vector2 = center+Vector2(-160,-100)
	caster.global_position = start
	caster.trident_range = 260.0
	caster.trident_speed = 160.0
	var target:Node2D = dummy(start+Vector2(65,0),"Team1")
	var spear:Node2D = owned_spear()
	check(caster.throw_trident(target),"real throw still uses its normal windup")
	target.global_position = start+Vector2(90,-12)
	caster._advance_trident_throw(caster.trident_throw_windup+0.01)
	check(spear.flight_state == 1 and spear.axis.dot(spear.global_position.direction_to(target.global_position)) > 0.999,"release still aims at the enemy's current position, without homing")
	var release:Vector2 = spear.global_position
	var old_target:Vector2 = target.global_position
	var heading:Vector2 = spear.axis
	check(is_equal_approx(spear.flight_length,caster.trident_range),"enemy distance no longer truncates the outgoing flight")
	target.global_position = center+Vector2(-240,220)
	var debris_before:int = get_nodes_in_group("MCTridentGroundDebris").size()
	fly(spear,1.0)
	check(spear.flight_state == 1 and not spear.planted,"missing the enemy continues outbound instead of planting at its old position")
	check(spear.traveled > release.distance_to(old_target)+20.0 and spear.axis == heading,"spear passes the old aim coordinate and preserves its original direction")
	check(not spear.ground_seek and get_nodes_in_group("MCTridentGroundDebris").size() == debris_before,"passing the aim creates neither ground seek nor ground impact effects")
	fly(spear,2.0)
	check(spear.flight_state == 2 and not spear.planted and spear.wall_ref == null,"a full-range miss starts ordinary loyalty return")
	check(spear.global_position.distance_to(release+heading*260.0) < 0.05,"miss returns from the actual range endpoint, without overshoot or ground adjustment")
	check(not spear.stuck_mound.visible and float(spear.material.get_shader_parameter("plant_clip")) < 0.5,"range return has no dirt mound or buried-weapon crop")
	var caught:bool = catch_back(caster,spear)
	check(caught and caster._trident == spear and spear.flight_state == 0,"missed spear comes back into the original hand/inventory")

	# A later actor on the same ray can still be hit beyond the former aim point.
	caster.global_position = center+Vector2(-160,20)
	var hit:Node2D = owned_spear()
	var origin:Vector2 = caster.global_position
	target.global_position = origin+Vector2(175,0)
	var hp:float = target.health
	hit.launch(Vector2.RIGHT,origin,origin+Vector2(55,0))
	fly(hit,2.0)
	check(target.health < hp and hit.flight_state == 2 and hit.traveled > 55.0,"actor farther along the original ray is hit after the old target coordinate was passed")
	var after_hit:float = target.health
	catch_back(caster,hit)
	check(target.health == after_hit,"return flight still cannot apply another direct hit")
	target.global_position = center+Vector2(-280,240)

	# The nearest real wall/obstacle owns lodging, even well beyond the aimed point.
	for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		caster.global_position = center
		var wall_size := Vector2(12,170) if direction.x != 0.0 else Vector2(170,12)
		var obstacle:StaticBody2D = make_wall(center+direction*165.0,wall_size)
		await physics_frame
		var lodged:Node2D = owned_spear()
		lodged.launch(direction,center,center+direction*45.0)
		fly(lodged,3.0)
		check(lodged.flight_state == 3 and not lodged.planted and lodged.wall_ref != null and lodged.wall_ref.get_ref() == obstacle,"actual four-direction obstacle contact lodges the spear: "+str(direction))
		check(lodged.traveled >= 158.0 and lodged.traveled <= 160.0 and not lodged.ground_seek,"wall lodging results from real flight/contact, not near-destination attraction")
		check(not lodged.stuck_mound.visible and float(lodged.material.get_shader_parameter("plant_clip")) < 0.5,"wall/obstacle lodging keeps the complete airborne item appearance")
		var point:Vector2 = lodged.global_position
		obstacle.global_position += Vector2(5,3)
		lodged.advance(0.01)
		check(lodged.global_position.is_equal_approx(point+Vector2(5,3)),"existing wall-local anchoring survives the behavior restoration")
		obstacle.queue_free()
		await process_frame
		lodged.advance(0.01)
		check(lodged.is_queued_for_deletion(),"removed supporting obstacle retires its lodged spear")
		await physics_frame

	caster.global_position = center
	caster.trident_range = 80.0
	var beyond:StaticBody2D = make_wall(center+Vector2(100,0),Vector2(12,140))
	await physics_frame
	var no_snap:Node2D = owned_spear()
	no_snap.launch(Vector2.RIGHT,center,center+Vector2(55,0))
	fly(no_snap,2.0)
	check(no_snap.flight_state == 2 and no_snap.wall_ref == null and not no_snap.ground_seek,"wall beyond maximum flight range is not attracted/snapped to, even when nearby")
	beyond.queue_free()
	no_snap.retire()
	await physics_frame
	for dt:float in [1.0/30.0,1.0/120.0,0.75]:
		var sample:Node2D = owned_spear()
		sample.launch(Vector2.RIGHT,center,center+Vector2(10,0))
		fly(sample,2.0,dt)
		check(sample.flight_state == 2 and not sample.planted and is_equal_approx(sample.traveled,80.0),"range miss returns consistently at different frame sizes: "+str(dt))
		sample.retire()

	# Charged misses do not create phantom impact lightning or permanent ground poles.
	caster.trident_range = 120.0
	var charged:Node2D = owned_spear()
	charged.charged = true
	charged.launch(Vector2.RIGHT,center,center+Vector2(20,0))
	var flashes:int = bolts(charged).size()
	fly(charged,2.0)
	check(charged.flight_state == 2 and bolts(charged).size() == flashes and not charged._impact_emitted,"charged empty flight keeps enchantment but does not fabricate a ground impact/lightning trigger")
	charged.charge_visual.advance(0.0)
	check(float(charged.charge_visual.glint_material.get_shader_parameter("plant_clip")) < 0.5 and float(charged.charge_visual.arc_material.get_shader_parameter("plant_clip")) < 0.5,"returning enchantment is fully visible, without old ground masks")
	charged.retire()

	# Compatibility cannot bring the removed gameplay rule back.
	var compat:Node2D = owned_spear()
	compat.launch(Vector2.RIGHT,center,center+Vector2(20,0))
	compat.stick_ground(center+Vector2(20,0))
	check(compat.flight_state == 2 and not compat.planted,"old explicit ground-lodgement caller now takes the return path")
	compat.flight_state = 3
	compat.planted = true
	compat._apply_plant_visual()
	compat.advance(0.01)
	check(compat.flight_state == 2 and not compat.planted and not compat.stuck_mound.visible,"already-present old ground pole is converted to return on its next live tick")
	var legacy:Dictionary = compat.snapshot()
	legacy.phase = 3
	legacy.planted = true
	legacy.ground_impact_id = 999
	legacy.ground_impact_age = 0.0
	var replica:Node2D = new_spear(2900)
	replica.receive(legacy)
	check(replica.flight_state == 2 and not replica.planted and not replica.stuck_mound.visible,"old ground snapshots do not recreate planted replicas")
	check(get_nodes_in_group("MCTridentGroundDebris").size() == debris_before,"the restored rule never emits ground particle bursts")
	var pause_spear:Node2D = owned_spear()
	pause_spear.launch(Vector2.RIGHT,center,center+Vector2(15,0))
	var paused_position:Vector2 = pause_spear.global_position
	game.now_stop_state = true
	pause_spear.advance(1.0)
	check(pause_spear.global_position == paused_position and pause_spear.flight_state == 1,"pause still freezes outgoing flight rather than prematurely returning/lodging")
	game.now_stop_state = false
	var replacement:Node2D = caster._trident
	var old_pole:Node2D = new_spear(2901)
	old_pole.flight_state = 3
	old_pole.planted = true
	old_pole.global_position = caster.trident_hand_position()
	old_pole.advance(0.01)
	check(old_pole.is_queued_for_deletion() and caster._trident == replacement,"legacy pole return cannot duplicate or replace another active weapon")
	var no_surface:Node2D = new_spear(2902)
	no_surface.launch(Vector2.RIGHT,center,center+Vector2(20,0))
	no_surface.stick(center+Vector2(20,0))
	check(no_surface.flight_state == 2 and not no_surface.planted and no_surface.wall_ref == null,"a lodging call without a real supporting obstacle cannot create a new pole")
	print("DROWNED_WALL_ONLY_RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
