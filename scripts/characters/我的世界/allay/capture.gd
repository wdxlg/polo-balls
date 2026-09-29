extends RefCounted
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")
## Explicit contact adapters; confirmed captures retain their complete native state.
const NATIVE_RETURN = preload("res://scripts/characters/我的世界/allay/native_return.gd")
const EXTENDED = preload("res://scripts/characters/我的世界/allay/extended_capture.gd")
static func describe(shot:Node) -> Dictionary:
	return PROJECTILE_API.capture_descriptor(shot)

static func hostile(collector:ball,shot:Node) -> bool:
	return PROJECTILE_API.hostile(collector,shot)

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
	return PROJECTILE_API.radius_of(shot)

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
		var t:float = contact_t(from,to,ball.body_point_seg(note,from,to),radius)
		if t>=0.0: options.append({"unit":unit,"index":-1,"note":note,"t":t})
	if options.is_empty() or describe(shot).is_empty(): return false
	options.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return a.t<b.t)
	for entry:Dictionary in options:
		var point:Vector2 = from.lerp(to,entry.t)
		if path_clear(shot,from,point) and entry.unit.collect_projectile(shot,point,entry.index,entry.note): return true
	return false

static func candidates(tree:SceneTree) -> Array[Node]:
	return PROJECTILE_API.candidates(tree)

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
		var t:float = contact_t(from,to,ball.body_point_seg(shot,from,to),NOTE_RADIUS+shot_radius(shot))
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
	var aim:Vector2 = point.direction_to(ball.body_point(target,point))
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
