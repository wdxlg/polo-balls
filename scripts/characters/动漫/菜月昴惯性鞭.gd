extends Node2D
## Fixed-step spring chain. Damage follows the visible curved whip, once per swing.
var fighter:ball
var points:PackedVector2Array = PackedVector2Array()
var velocities:PackedVector2Array = PackedVector2Array()
var phase:float = -1.0
var cooldown:float = 0.3
var aim:float = 0.0
var hit_ids:Dictionary = {}
var line:Line2D
var shine:Line2D
const SEGMENTS:int = 12
func _ready() -> void:
	fighter = get_parent() as ball
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_index = 33
	line = Line2D.new()
	line.width = 2.2
	line.default_color = Color("49301f")
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(line)
	shine = Line2D.new()
	shine.width = 0.7
	shine.default_color = Color("b49b6a")
	line.add_child(shine)
func advance(delta:float) -> void:
	if not is_instance_valid(fighter) or fighter.health <= 0 or fighter.get("_returning") or not fighter.is_combat_runtime_active(): return
	if fighter.is_damage_output_disabled():
		phase = -1.0
		visible = false
		return
	visible = true
	var dt:float = clampf(delta,0.0,0.1)
	cooldown = maxf(0.0,cooldown-dt)
	if phase < 0.0 and cooldown <= 0.0 and not fighter.is_player_controlled():
		var target:ball = fighter.call("_find_fist_target")
		if target != null and fighter.global_position.distance_to(target.global_position) <= float(fighter.get("whip_reach"))+18.0:
			aim = fighter.global_position.angle_to_point(target.global_position)
			phase = 0.0
			hit_ids.clear()
			cooldown = float(fighter.get("whip_interval"))
	if phase >= 0.0:
		phase += dt
		if phase >= float(fighter.get("whip_swing_duration")): phase = -1.0
	var origin:Vector2 = fighter.global_position
	if points.size() != SEGMENTS:
		for i:int in range(SEGMENTS):
			points.append(origin+Vector2.RIGHT*float(i))
			velocities.append(Vector2.ZERO)
	if points[0].distance_to(origin) > 250.0:
		var shift:Vector2 = origin-points[0]
		for i:int in range(SEGMENTS):
			points[i] += shift
			velocities[i] = Vector2.ZERO
	var steps:int = maxi(1,int(ceil(dt*120.0)))
	for step:int in range(steps):
		var h:float = dt/float(steps)
		points[0] = origin
		for i:int in range(1,SEGMENTS):
			var ratio:float = float(i)/float(SEGMENTS-1)
			var angle:float = fighter.direction.angle()+0.8+ratio*1.3
			var reach:float = 18.0
			if phase >= 0.0:
				var swing:float = clampf((phase-ratio*0.10)/float(fighter.get("whip_swing_duration")),0.0,1.0)
				angle = aim+lerpf(-1.15,1.15,smoothstep(0.0,0.85,swing))
				reach = float(fighter.get("whip_reach"))
			var desired:Vector2 = origin+Vector2.RIGHT.rotated(angle)*reach*ratio
			var stiffness:float = lerpf(650.0,260.0,ratio)
			velocities[i] += (desired-points[i])*stiffness*h
			velocities[i] *= exp(-lerpf(34.0,21.0,ratio)*h)
			points[i] += velocities[i]*h
	_render_and_hit()

func request_manual_swing(world_point:Vector2) -> bool:
	if fighter == null or not is_instance_valid(fighter) or not fighter.is_player_controlled() or not fighter.is_multiplayer_authority():
		return false
	if fighter.health <= 0 or fighter.is_damage_output_disabled() or not fighter.is_combat_runtime_active():
		return false
	if phase >= 0.0 or cooldown > 0.0:
		return false
	aim = fighter.global_position.angle_to_point(world_point)
	phase = 0.0
	hit_ids.clear()
	cooldown = maxf(float(fighter.get("whip_interval")),0.05)
	return true

func _render_and_hit() -> void:
	var displayed:PackedVector2Array = PackedVector2Array([points[0]])
	for i:int in range(1,points.size()):
		var ray := PhysicsRayQueryParameters2D.create(displayed[-1],points[i],1,[fighter.get_rid()])
		var wall:Dictionary = get_world_2d().direct_space_state.intersect_ray(ray)
		var end:Vector2 = wall.get("position",points[i])
		if phase >= 0.10: _hit_segment(displayed[-1],end)
		displayed.append(end)
		if not wall.is_empty(): break
	line.points = displayed
	shine.points = displayed
func _hit_segment(start:Vector2,end:Vector2) -> void:
	var capsule := CapsuleShape2D.new()
	capsule.radius = 2.0
	capsule.height = start.distance_to(end)+4.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = capsule
	query.transform = Transform2D((end-start).angle()-PI*0.5,(start+end)*0.5)
	query.collision_mask = 2
	query.exclude = [fighter.get_rid()]
	for result:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,32):
		var enemy:Variant = result.collider
		if not enemy is ball or enemy == fighter or not enemy.is_combat_targetable() or enemy.health <= 0: continue
		if fighter.Team != "" and fighter.Team == enemy.Team: continue
		var id:int = enemy.get_instance_id()
		if hit_ids.has(id): continue
		hit_ids[id] = true
		var hp:float = enemy.health
		var shield:float = enemy.block
		enemy.receive_positional_damage(fighter.effective_outgoing_damage(float(fighter.get("whip_damage"))),end,false,fighter)
		if is_instance_valid(enemy) and (enemy.health < hp or enemy.block < shield):
			enemy.Repel += fighter.global_position.direction_to(enemy.global_position)*float(fighter.get("whip_knockback"))
