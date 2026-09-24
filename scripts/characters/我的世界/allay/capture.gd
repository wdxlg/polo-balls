extends RefCounted
## Explicit contact adapters; confirmed captures retain their complete native state.
const NATIVE_RETURN = preload("res://scripts/characters/我的世界/allay/native_return.gd")
const EXTENDED = preload("res://scripts/characters/我的世界/allay/extended_capture.gd")
const ARROW = "res://scripts/effects/我的世界/骷髅箭.gd"
const BLAZE = "res://scripts/effects/我的世界/烈焰弹.gd"
const SIMPLE = ["res://scripts/shooter/子弹.gd", "res://scripts/shooter/knife.gd", "res://scripts/shooter/潜影弹.gd", "res://scripts/characters/我的世界/allay/note.gd", "res://scripts/characters/我的世界/snow_golem/snowball.gd"]

static func describe(shot:Node) -> Dictionary:
	if not is_instance_valid(shot) or shot.is_queued_for_deletion() or shot.get_script() == null: return {}
	var path:String = shot.get_script().resource_path
	if path in SIMPLE and shot is ball and shot.Type in [ball.Ball_Type.Shooter,ball.Ball_Type.Shooter_with_Health] and shot.health > 0:
		if shot.scene_file_path.is_empty(): return {}
		return {"kind":"simple", "scene":shot.scene_file_path, "damage":float(shot.Damage), "speed":float(shot.Speed), "scale":shot.scale}
	if path == ARROW and shot.get("_mode") == 0 and shot.get("_configured"):
		return {"kind":"arrow","damage":shot.get("_direct_damage"),"speed":shot.get("_speed"),"plain":shot.get("_plain_arrow_mode"),"pickup":shot.get("_pickup_damage"),"knockback":shot.get("_knockback_distance"),"knock_speed":shot.get("_knockback_speed"),"life":shot.get("_terrain_lifetime")}
	if path == BLAZE and shot.get("_configured"):
		var source:Variant = shot.call("_source_ball")
		if not is_instance_valid(source): return {}
		return {"kind":"blaze","damage":source.attack_damage(shot.get("_damage_multiplier")),"speed":shot.get("_speed"),"burn_duration":shot.get("_burn_duration"),"burn":shot.get("_burn_tick_damage_multiplier"),"fire_radius":shot.get("_fire_radius"),"fire_duration":shot.get("_fire_duration"),"fire":shot.get("_fire_tick_damage_multiplier"),"fire_burn":shot.get("_fire_burn_tick_damage_multiplier")}
	return EXTENDED.describe(shot)

static func hostile(collector:ball,shot:Node) -> bool:
	var source:Node = null
	var team:String = ""
	var extra:Dictionary = EXTENDED.config(shot)
	if not extra.is_empty():
		source = EXTENDED.source(shot,extra)
		team = EXTENDED.team(shot,extra)
	elif shot is ball:
		source = shot.Master if is_instance_valid(shot.Master) else null
		team = str(shot.Team)
		if shot.has_meta("forced_combat_team"): team = str(shot.get_meta("forced_combat_team"))
		if source != null and (team.is_empty() or team == "Ball"): team = str(source.Team)
	elif shot.has_method("_source_ball"):
		source = shot.call("_source_ball")
		team = str(shot.get("_source_team"))
	if source == collector or shot == collector: return false
	if source != null and source is ball and (source.Master == collector or collector.Master == source): return false
	# Collection never steals allied shots, even when friendly damage is enabled.
	return collector.Team.is_empty() or team.is_empty() or team != collector.Team

const NOTE_RADIUS:float = 13.0

static func contact_t(from:Vector2,to:Vector2,center:Vector2,radius:float) -> float:
	var relative:Vector2 = from-center
	if relative.length_squared()<=radius*radius: return 0.0
	var segment:Vector2 = to-from
	var a:float = segment.length_squared()
	if a<0.000001: return -1.0
	var b:float = relative.dot(segment)
	var discriminant:float = b*b-a*(relative.length_squared()-radius*radius)
	if discriminant<0.0: return -1.0
	var t:float = (-b-sqrt(discriminant))/a
	return t if t>=0.0 and t<=1.0 else -1.0

static func shot_radius(shot:Node2D) -> float:
	var extra:Dictionary = EXTENDED.config(shot)
	if not extra.is_empty(): return float(extra.get("radius",4.0))
	var collider:CollisionShape2D = shot.get_node_or_null("CollisionShape2D")
	if collider != null and collider.shape is CircleShape2D:
		return collider.shape.radius*maxf(absf(shot.global_scale.x),absf(shot.global_scale.y))
	return 4.0

static func path_clear(shot:Node2D,from:Vector2,to:Vector2) -> bool:
	if shot.is_in_group("AllayFlyingNote") or bool(EXTENDED.config(shot).get("through_walls",false)) or from.distance_squared_to(to)<0.01: return true
	var query := PhysicsRayQueryParameters2D.create(from,to,1)
	if shot is CollisionObject2D: query.exclude = [shot.get_rid()]
	return shot.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

static func sweep(shot:Node2D,from:Vector2,to:Vector2) -> bool:
	if not is_instance_valid(shot) or not shot.is_inside_tree(): return false
	if bool(shot.get_meta("allay_captured",false)): return true
	if shot.is_queued_for_deletion() or not shot.is_multiplayer_authority(): return false
	var options:Array[Dictionary] = []
	var radius:float = NOTE_RADIUS+shot_radius(shot)
	for unit:Node in shot.get_tree().get_nodes_in_group("MinecraftAllay"):
		if not unit.active() or not hostile(unit,shot): continue
		for i:int in mini(unit.notes,unit._note_cloud.positions.size()):
			var t:float = contact_t(from,to,unit._note_cloud.positions[i],radius)
			if t>=0.0: options.append({"unit":unit,"index":i,"note":null,"t":t})
	for note:Node in shot.get_tree().get_nodes_in_group("AllayFlyingNote"):
		if note==shot or note._spent or note.is_queued_for_deletion(): continue
		var unit:Node = note.Master if is_instance_valid(note.Master) else null
		if unit==null or not unit.is_in_group("MinecraftAllay") or not unit.active() or not hostile(unit,shot): continue
		var t:float = contact_t(from,to,note.global_position,radius)
		if t>=0.0: options.append({"unit":unit,"index":-1,"note":note,"t":t})
	if options.is_empty() or describe(shot).is_empty(): return false
	options.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return a.t<b.t)
	for entry:Dictionary in options:
		var point:Vector2 = from.lerp(to,entry.t)
		if path_clear(shot,from,point) and entry.unit.collect_projectile(shot,point,entry.index,entry.note): return true
	return false

static func candidates(tree:SceneTree) -> Array[Node]:
	var result:Array[Node] = tree.get_nodes_in_group("Ball")
	result.append_array(tree.get_nodes_in_group("MinecraftSkeletonArrow"))
	result.append_array(tree.get_nodes_in_group("AllayCapturableBlaze"))
	result.append_array(tree.get_nodes_in_group("AllayExtendedProjectile"))
	return result

static func scan_orbit(unit:ball) -> void:
	if unit.notes<=0: return
	# This also handles stationary attacks touched by moving orbit notes.
	for shot:Node in candidates(unit.get_tree()):
		if shot is Node2D and hostile(unit,shot) and not describe(shot).is_empty():
			sweep(shot,shot.global_position,shot.global_position)

static func sweep_note(note:ball,from:Vector2,to:Vector2) -> bool:
	var unit:Node = note.Master if is_instance_valid(note.Master) else null
	if unit==null or not unit.is_in_group("MinecraftAllay") or not unit.active(): return false
	var options:Array[Dictionary] = []
	for shot:Node in candidates(note.get_tree()):
		if shot==note or not shot is Node2D or not hostile(unit,shot) or describe(shot).is_empty(): continue
		var t:float = contact_t(from,to,shot.global_position,NOTE_RADIUS+shot_radius(shot))
		if t>=0.0: options.append({"shot":shot,"t":t})
	options.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return a.t<b.t)
	for entry:Dictionary in options:
		if unit.collect_projectile(entry.shot,from.lerp(to,entry.t),-1,note): return true
	return false

static func discard(shot:Node) -> void:
	shot.set_meta("allay_captured",true)
	shot.set_physics_process(false)
	shot.process_mode = Node.PROCESS_MODE_DISABLED
	if shot is CanvasItem: shot.hide()
	# Do not call Die/explode/on_hit: those can spawn damage or status effects.
	if shot.get_script().resource_path=="res://scripts/effects/我的世界/三叉戟.gd":
		shot.retire() # Release owner bookkeeping without spawning damage.
	elif shot.get_script().resource_path == "res://scripts/characters/我的世界/snow_golem/snowball.gd":
		shot.expire() # Retire replicas too; capture must not leave a stationary snowball.
	else: shot.queue_free()

static func launch(owner_ball:ball,data:Dictionary,target:ball,point:Vector2) -> Node2D:
	if data.has("native_script"): return NATIVE_RETURN.launch(owner_ball,data,target,point)
	var aim:Vector2 = point.direction_to(target.global_position)
	var damage:float = float(data.get("damage",0))
	var shot:Node2D
	match str(data.get("kind","")):
		"simple":
			var scene:PackedScene = load(str(data.scene)) as PackedScene
			if scene == null: return null
			shot = scene.instantiate()
			shot.Master = owner_ball
			shot.Master_name = str(owner_ball.name)
			shot.Team = owner_ball.Team
			shot.Ignore_Team_Damage_Setting = true
			shot.Target_Enemy = target
			shot.Damage = int(damage)
			shot.Speed = maxf(float(data.speed),1.0)
			shot.scale = data.get("scale",Vector2.ONE)
			shot.direction = aim
			if shot.get_script().resource_path == "res://scripts/shooter/潜影弹.gd": shot.target_ref = weakref(target)
		"arrow":
			shot = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
		"blaze":
			shot = load("res://scenes/shooter/我的世界/烈焰弹.tscn").instantiate()
		_: return null
	shot.position = point
	shot.set_meta("allay_returned",true)
	shot.set_meta("forced_combat_team",owner_ball.Team)
	shot.name = Game.return_random_name(shot)
	owner_ball.get_tree().current_scene.add_child(shot,true)
	shot.add_to_group("BattleTransient")
	match str(data.kind):
		"arrow":
			shot.configure(owner_ball,owner_ball.Team,aim,data.speed,damage,float(data.pickup),data.knockback,data.knock_speed,data.life)
			shot.set("_plain_arrow_mode",bool(data.plain))
			shot.set("_force_no_friendly_fire",true)
		"blaze":
			shot.configure(owner_ball,owner_ball.Team,aim,data.speed,damage/maxf(owner_ball.attack_damage(),1.0),data.burn_duration,float(data.burn),data.fire_radius,data.fire_duration,float(data.fire),float(data.fire_burn))
	return shot
