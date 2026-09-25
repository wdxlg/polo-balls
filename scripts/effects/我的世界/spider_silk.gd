extends Node2D
const COBWEB_TEXTURE = preload("res://Images/characters/我的世界/蜘蛛/cobweb_native.png")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
var unit:ball
var segments:Array[Dictionary] = []
var anchor:Dictionary = {}
var live_id:int = 1
var webs:Dictionary = {}
var _sample_left:float = 0.0
var _clock:float = 0.0
var _contact_left:float = 0.0
var _previous:Dictionary = {}
var _previous_lines:Dictionary = {}
var _remote_lines:Array = []
var _remote_webs:Array = []
var _sync_left:float = 0.0
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_as_top_level(true)
	global_transform = Transform2D.IDENTITY
	z_index = -1
	add_to_group("BattleTransient")
	add_to_group("MCSpiderSilk")
func _make_anchor(point:Vector2,surface:Node2D) -> Dictionary:
	return {"point":point,"ref":weakref(surface) if surface!=null else null,"local":surface.to_local(point) if surface!=null else point}
func _valid(a:Dictionary) -> bool:
	return not a.is_empty() and (a.ref==null or is_instance_valid(a.ref.get_ref()))
func _point(a:Dictionary) -> Vector2:
	var wall:Variant = a.ref.get_ref() if a.ref!=null else null
	return wall.to_global(a.local) if is_instance_valid(wall) else a.point
func development_prepare_merge() -> void:
	# Resolve attached wall coordinates before any wall or owner is relocated.
	var anchors:Array[Dictionary] = []
	for segment:Dictionary in segments:
		anchors.append(segment.start)
		anchors.append(segment.end)
	if not anchor.is_empty(): anchors.append(anchor)
	var resolved:Array[Dictionary] = []
	for a:Dictionary in anchors:
		var seen:bool = false
		for prior:Dictionary in resolved:
			if is_same(a,prior): seen = true; break
		if seen: continue
		var point:Vector2 = _point(a)
		a.point = point
		a.local = point
		a.ref = null
		resolved.append(a)
func development_rebase(change:Vector2) -> void:
	if change.is_zero_approx(): return
	# A completed segment shares its endpoint Dictionary with the next one.
	# Resolve wall attachments before the source map moves; the old wall is not
	# the wall on the merged map. Move each anchor only once and detach it.
	var shifted:Array[Dictionary] = []
	for segment:Dictionary in segments:
		for endpoint:String in ["start","end"]:
			var a:Dictionary = segment[endpoint]
			var seen:bool = false
			for previous:Dictionary in shifted:
				if is_same(a,previous): seen = true; break
			if seen: continue
			var point:Vector2 = _point(a)+change
			a.point = point
			a.local = point
			a.ref = null
			shifted.append(a)
	if not anchor.is_empty():
		var seen_anchor:bool = false
		for previous:Dictionary in shifted:
			if is_same(anchor,previous): seen_anchor = true; break
		if not seen_anchor:
			var point:Vector2 = _point(anchor)+change
			anchor.point = point
			anchor.local = point
			anchor.ref = null
	for web:Dictionary in webs.values(): web.point += change
	# Sweep history describes an old arena. Never damage a target over the
	# distance between two maps on the first combat tick after merging.
	_previous.clear()
	_previous_lines.clear()
	for line:Array in _remote_lines:
		line[0] += change
		line[1] += change
	for i:int in range(_remote_webs.size()): _remote_webs[i] += change
	queue_redraw()
func wall_attachment_point(contact:Vector2,normal:Vector2,surface:Node2D,tail:Vector2) -> Vector2:
	# A body/head contact is not the silk endpoint. Extend the current abdomen
	# strand onto the touched wall plane, preserving its direction when fixing it.
	var n:Vector2 = normal.normalized()
	var plane:Vector2 = contact+n*1.5
	if n.length_squared()<0.5: return plane
	if _valid(anchor):
		var start:Vector2 = _point(anchor)
		var axis:Vector2 = (tail-start).normalized()
		var denominator:float = axis.dot(n)
		if denominator < -0.05:
			var distance:float = (plane-start).dot(n)/denominator
			var candidate:Vector2 = start+axis*distance
			# Near-parallel contacts must not create an anchor far along/beyond a wall.
			var reach:float = maxf(GEOMETRY.radius(unit)*4.0,96.0)
			if distance>0.0 and candidate.distance_to(tail)<=reach and candidate.distance_to(plane)<=reach:
				if _on_wall_surface(candidate,n,surface): return candidate
	# First anchor, grazing contact or a short obstacle: project the abdomen
	# onto the real surface rather than reusing an unrelated collision point.
	var projected:Vector2 = tail-n*(tail-plane).dot(n)
	if _on_wall_surface(projected,n,surface): return projected
	return plane
func _on_wall_surface(point:Vector2,normal:Vector2,surface:Node2D) -> bool:
	if surface==null: return true # Explicit geometric fixtures have no PhysicsBody.
	var hit:Dictionary = GEOMETRY.wall_ray(self,point+normal*4.0,point-normal*4.0,[unit.get_rid()])
	return not hit.is_empty() and hit.collider==surface
func touch_wall(point:Vector2,surface:Node2D = null) -> bool:
	if not unit.mc_live() or Game.now_stop_state or _contact_left>0.0: return false
	if _valid(anchor) and _point(anchor).distance_to(point)<unit.silk_anchor_spacing: return false
	_contact_left = 0.18
	var next:Dictionary = _make_anchor(point,surface)
	if _valid(anchor):
		segments.append({"id":live_id,"start":anchor,"end":next})
		live_id += 1
	anchor = next
	unit.mc_cast_animation(0.25)
	_sync_left = 0.0
	queue_redraw()
	return true
func lines(include_live:bool = true) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	for segment:Dictionary in segments:
		if _valid(segment.start) and _valid(segment.end):
			result.append(_line(segment.id,_point(segment.start),_point(segment.end)))
	if include_live and _valid(anchor): result.append(_line(live_id,_point(anchor),unit.silk_tail_position()))
	return result
func _line(id:int,a:Vector2,b:Vector2) -> Dictionary:
	return {"id":id,"key":str(unit.get_path())+":"+str(id),"a":a,"b":b,"caster":unit}
func _physics_process(delta:float) -> void: advance(delta)
func advance(delta:float) -> void:
	if not is_instance_valid(unit) or unit.health<=0:
		hide()
		return
	if Game.now_stop_state or get_tree().paused or not unit.is_combat_runtime_active(): return
	if not unit.is_multiplayer_authority():
		queue_redraw()
		return
	if not unit.mc_live(): return
	_clock += delta
	_contact_left = maxf(_contact_left-delta,0.0)
	for i:int in range(segments.size()-1,-1,-1):
		if not _valid(segments[i].start) or not _valid(segments[i].end): segments.remove_at(i)
	if not _valid(anchor): anchor.clear()
	_sample_left -= delta
	if _sample_left<=0.0:
		_sample_left = maxf(unit.silk_tick,0.04)
		_update_crossings()
		_tick_contacts()
	_sync_left -= delta
	if multiplayer.has_multiplayer_peer() and _sync_left<=0.0:
		_sync_left = 0.1
		var packed:Array = []
		for line:Dictionary in lines(): packed.append([line.a,line.b,line.id==live_id])
		var points:Array = []
		for web:Dictionary in webs.values(): points.append(web.point)
		unit._sync_silk.rpc(packed,points)
	queue_redraw()
func _update_crossings() -> void:
	var own:Array[Dictionary] = lines(false) # Only completed wall-to-wall strands create webs.
	var all:Array[Dictionary] = own.duplicate()
	for other:Node in get_tree().get_nodes_in_group("MCSpiderSilk"):
		if other==self or not is_instance_valid(other.unit) or other.unit.health<=0: continue
		if GEOMETRY.same_team(unit,other.unit): all.append_array(other.lines(false))
	var next:Dictionary = {}
	var births:Array[Vector2] = []
	for a:Dictionary in own:
		for b:Dictionary in all:
			if str(a.key)>=str(b.key): continue # One owner per unordered pair, including friendly spiders.
			var point:Variant = GEOMETRY.crossing(a.a,a.b,b.a,b.b)
			if point==null: continue
			var key:String = a.key+"|"+b.key
			if not webs.has(key):
				var unique:bool = true
				for born:Vector2 in births:
					if born.distance_to(point)<1.0: unique = false
				if unique: births.append(point)
			var web:Dictionary = webs.get(key,{"cooldowns":{}})
			web.point = point
			web.hunters = [weakref(a.caster),weakref(b.caster)]
			next[key] = web
			if next.size()>=unit.silk_max_webs: break
		if next.size()>=unit.silk_max_webs: break
	webs = next
	for point:Vector2 in births: unit.emit_web_birth(point)
func _tick_contacts() -> void:
	var current:Array[Dictionary] = lines()
	var next_positions:Dictionary = {}
	var next_lines:Dictionary = {}
	for line:Dictionary in current: next_lines[line.id] = [line.a,line.b]
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not GEOMETRY.enemy(unit,raw): continue
		var target:ball = raw
		var id:int = target.get_instance_id()
		var p:Vector2 = target.global_position
		var old:Vector2 = _previous.get(id,p)
		next_positions[id] = p
		var r:float = GEOMETRY.radius(target)
		for line:Dictionary in current:
			var hit:bool = GEOMETRY.touching(line.a,line.b,p,old,r+unit.silk_width)
			if not hit and _previous_lines.has(line.id):
				var before:Array = _previous_lines[line.id]
				# The wall-to-body thread can sweep over a stationary enemy.
				var quad := PackedVector2Array([before[0],before[1],line.b,line.a])
				hit = Geometry2D.is_point_in_polygon(p,quad) or GEOMETRY.touching(before[1],line.b,p,old,r+unit.silk_width)
			if not hit: continue
			var world:Node = get_tree().current_scene
			if world!=null and world.has_method("new_buff"):
				# Unique key per strand: same strand refreshes, DIFFERENT strands multiply.
				world.new_buff(target,unit,"蜘蛛丝_"+str(line.id),Buff.new(2,maxf(unit.silk_tick*2.2,0.2),Buff.Buff_types.Speed,unit.silk_slow_multiplier,Buff.Algorithms.mul),"cover")
			unit.mc_damage_with_impact(target,unit.silk_damage,p)
			if not is_instance_valid(target) or target.health<=0: break
		if not is_instance_valid(target) or target.health<=0: continue
		for web:Dictionary in webs.values():
			if GEOMETRY.segment_distance(old,p,web.point)>unit.web_radius+r: continue
			var world:Node = get_tree().current_scene
			if world!=null and world.has_method("new_buff"):
				# Refresh one strong slow per owner, not another stack every tick.
				world.new_buff(target,unit,"蜘蛛网",Buff.new(2,maxf(unit.silk_tick*2.2,0.2),Buff.Buff_types.Speed,unit.web_slow_multiplier,Buff.Algorithms.mul),"cover")
			unit.mc_damage_with_impact(target,unit.web_damage,p)
			if not is_instance_valid(target) or target.health<=0: break
			if float(web.cooldowns.get(id,0.0))>_clock: continue
			web.cooldowns[id] = _clock+maxf(unit.web_retrigger,0.1)
			for hunter_ref:WeakRef in web.hunters:
				var hunter:Variant = hunter_ref.get_ref()
				if is_instance_valid(hunter): hunter.hunt_web_target(target)
	_previous = next_positions
	_previous_lines = next_lines
	# Bound per-web cooldown dictionaries to live combat targets.
	for web:Dictionary in webs.values():
		for id:Variant in web.cooldowns.keys():
			if not next_positions.has(id): web.cooldowns.erase(id)
func web_points() -> Array[Vector2]:
	var result:Array[Vector2] = []
	if unit.is_multiplayer_authority():
		for web:Dictionary in webs.values(): result.append(web.point)
	else:
		for point:Vector2 in _remote_webs: result.append(point)
	return result
func receive_snapshot(packed:Array,points:Array) -> void:
	_remote_lines = packed
	_remote_webs = points
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(unit) or unit.health<=0: return
	var draw_lines:Array = []
	var draw_webs:Array = []
	if unit.is_multiplayer_authority():
		for line:Dictionary in lines(): draw_lines.append([line.a,line.b,line.id==live_id])
		for web:Dictionary in webs.values(): draw_webs.append(web.point)
	else:
		draw_lines = _remote_lines
		draw_webs = _remote_webs
	for line:Array in draw_lines:
		var endpoint:Vector2 = unit.silk_tail_position() if line[2] else line[1]
		# One hard-edged pixel stroke: no smooth shadow/outline or round wall dots.
		draw_line(Vector2(line[0]).round()+Vector2(0.5,0.5),endpoint.round()+Vector2(0.5,0.5),Color(0.91,0.94,0.96),1.0,false)
	for point:Vector2 in draw_webs:
		# Untouched vanilla 16x16 cobweb; no generated radial spokes/rings.
		var diameter:float = unit.web_radius*2.0
		draw_texture_rect(COBWEB_TEXTURE,Rect2(point-Vector2.ONE*unit.web_radius,Vector2.ONE*diameter),false)
