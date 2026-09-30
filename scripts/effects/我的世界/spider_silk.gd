extends Node2D
const COBWEB_TEXTURE = preload("res://Images/characters/我的世界/蜘蛛/cobweb_native.png")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
const MAP_THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
## Strand ends sink this far into the touched wall, so the 3D wall covers them.
const WALL_SINK:float = 4.0
## Absolute layer: above the ground tiles (-5, drawn earlier), below the 3D walls,
## wall shadows and 2D obstacles (-4 and up), so a sunk end is hidden by its wall.
const SILK_Z:int = -5
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
	z_as_relative = false
	z_index = SILK_Z
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
func wall_attachment(contact:Vector2,normal:Vector2,surface:Node2D,tail:Vector2) -> Dictionary:
	# A wall touch extends the live strand along its own direction from the
	# abdomen until that extension truly meets a wall shape; the meeting point is
	# the endpoint. Only when the strand does not head wallward or reaches no
	# wall shape nearby does the exact body contact serve as the endpoint.
	var n:Vector2 = normal.normalized()
	var direction:Vector2 = _strand_direction(tail)
	if n.length_squared()>=0.5 and not direction.is_zero_approx() and direction.dot(n)<=-0.2:
		var reach:float = maxf(2.0*tail.distance_to(contact)+WALL_SINK+16.0,96.0)
		var exclude:Array[RID] = []
		if is_instance_valid(unit): exclude = [unit.get_rid()]
		var hit:Dictionary = GEOMETRY.wall_ray(self,tail,tail+direction*reach,exclude)
		if not hit.is_empty():
			return {"point":_sunk_endpoint(hit.position,direction,hit.normal,hit.collider as Node2D),"surface":hit.collider as Node2D}
	return {"point":_contact_attachment(contact,n,surface,direction),"surface":surface}
func _strand_direction(tail:Vector2) -> Vector2:
	# The drawn strand runs from the previous anchor to the abdomen; continuing
	# that exact line keeps the fixed segment continuous with the visible silk.
	if not is_instance_valid(unit): return Vector2.ZERO
	var direction:Vector2 = Vector2.ZERO
	if _valid(anchor): direction = tail-_point(anchor)
	if direction.length_squared()<=unit.MOTION_EPSILON_SQ:
		var requested:Variant = unit.get("_last_requested_velocity")
		if requested is Vector2: direction = requested
	if direction.length_squared()<=unit.MOTION_EPSILON_SQ: return Vector2.ZERO
	return direction.normalized()
func _wall_sink(surface:Node2D) -> float:
	var world:Node = get_tree().current_scene if is_inside_tree() else null
	var map_wall:bool = surface!=null and surface.get_parent()!=null and surface.get_parent().has_meta(&"map_safety_frame")
	if map_wall and world!=null and world.has_method(&"map_background_style") and not MAP_THEMES.tiled(world.map_background_style()):
		# Flat themes draw the map wall as the black border line (above everything),
		# centred on the edge: end inside that line, not in the outside backdrop.
		# The line's centre uses World.return_map_display_rect's inset; stop in the
		# middle of its inner half so the pixel stroke's rounding stays under it.
		var width:float = float(world.get("map_border_width")) if "map_border_width" in world else 2.0
		return maxf(width*0.5-1.0,0.0)-maxf(width,0.0)*0.25
	return WALL_SINK
func _sunk_endpoint(hit_position:Vector2,direction:Vector2,hit_normal:Vector2,surface:Node2D) -> Vector2:
	# Default: the end dips into the touched wall so the wall itself covers it.
	var sink:float = _wall_sink(surface)
	if sink<=0.0: return hit_position+direction*sink # Flat-theme border: stay inside its drawn stroke line.
	var along:Vector2 = hit_position+direction*sink
	if _inside_surface(along,surface) and _on_wall_surface(along,hit_normal,surface): return along
	# Sinking along the strand would exit a thin obstacle or slide off an edge;
	# sink straight into the actual face instead, never through the far side.
	var inward:Vector2 = hit_position-hit_normal.normalized()*WALL_SINK
	if _inside_surface(inward,surface): return inward
	return hit_position
func _contact_attachment(contact:Vector2,n:Vector2,surface:Node2D,direction:Vector2) -> Vector2:
	# Fallback for degenerate geometry: the exact physics contact, dipped at
	# most WALL_SINK into the wall along the strand. Thin obstacles keep the end
	# exactly on their face instead of poking out the far side.
	var sink:float = _wall_sink(surface)
	if direction.is_zero_approx() or n.length_squared()<0.5 or direction.dot(n)>-0.05: return contact
	var point:Vector2 = contact+direction*sink
	if sink<=0.0: return point
	if not _on_wall_surface(point,n,surface) or not _inside_surface(point,surface): return contact
	return point
func _on_wall_surface(point:Vector2,normal:Vector2,surface:Node2D) -> bool:
	if surface==null: return true # Explicit geometric fixtures have no PhysicsBody.
	# Start outside even when the point is already sunk into the wall.
	var hit:Dictionary = GEOMETRY.wall_ray(self,point+normal*(WALL_SINK+4.0),point-normal*4.0,[unit.get_rid()])
	return not hit.is_empty() and hit.collider==surface
func _inside_surface(point:Vector2,surface:Node2D) -> bool:
	# Thin obstacles keep the end on their face instead of poking out the far side.
	if surface==null: return true
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = [unit.get_rid()]
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_point(query,8):
		if hit.collider==surface: return true
	return false
func _can_weave() -> bool:
	if unit.has_method(&"can_weave_silk"): return unit.can_weave_silk()
	return unit.mc_live() and not Game.now_stop_state
func touch_wall(point:Vector2,surface:Node2D = null) -> bool:
	if not _can_weave() or _contact_left>0.0: return false
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
	# Weaving bookkeeping (debounce, anchors, crossings) runs under any control;
	# only the damaging/slowing contact pass needs mc_live() (not damage-disabled).
	if not _can_weave(): return
	_clock += delta
	_contact_left = maxf(_contact_left-delta,0.0)
	for i:int in range(segments.size()-1,-1,-1):
		if not _valid(segments[i].start) or not _valid(segments[i].end): segments.remove_at(i)
	if not _valid(anchor): anchor.clear()
	_sample_left -= delta
	if _sample_left<=0.0:
		_sample_left = maxf(unit.silk_tick,0.04)
		_update_crossings()
		if unit.mc_live(): _tick_contacts()
		else:
			# Damage output disabled: webs still form, but no slow/damage/pounce.
			# Drop sweep history so re-enabling cannot sweep the whole gap at once.
			_previous.clear()
			_previous_lines.clear()
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
			# Unique key per strand: same strand refreshes, DIFFERENT strands multiply.
			target.set_motion_speed_factor("蜘蛛丝_"+str(unit.get_instance_id())+"_"+str(line.id),unit,unit.silk_slow_multiplier,maxf(unit.silk_tick*2.2,0.2))
			unit.mc_damage_with_impact(target,unit.silk_damage,p)
			if not is_instance_valid(target) or target.health<=0: break
		if not is_instance_valid(target) or target.health<=0: continue
		for web:Dictionary in webs.values():
			if GEOMETRY.segment_distance(old,p,web.point)>unit.web_radius+r: continue
			# Refresh one strong slow per owner, not another stack every tick.
			target.set_motion_speed_factor("蜘蛛网_"+str(unit.get_instance_id()),unit,unit.web_slow_multiplier,maxf(unit.silk_tick*2.2,0.2))
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
	# The silk layer must be an identity top-level item. A stale inherited map
	# transform would increasingly scale/offset long strands on larger maps.
	if not global_transform.is_equal_approx(Transform2D.IDENTITY):
		global_transform = Transform2D.IDENTITY
		queue_redraw()
		return
	var draw_lines:Array = []
	var draw_webs:Array = []
	if unit.is_multiplayer_authority():
		for line:Dictionary in lines(): draw_lines.append([line.a,line.b,line.id==live_id])
		for web:Dictionary in webs.values(): draw_webs.append(web.point)
	else:
		draw_lines = _remote_lines
		draw_webs = _remote_webs
	# Endpoints are world coordinates even if a caller re-parented this item; draw
	# them in this item's local space so a map transform cannot scale the silk away.
	var local_transform:Transform2D = global_transform.affine_inverse()
	for line:Array in draw_lines:
		var endpoint:Vector2 = unit.silk_tail_position() if line[2] else line[1]
		# One hard-edged pixel stroke: no smooth shadow/outline or round wall dots.
		# Snap to the centre of the pixel that holds each end (floor, not round):
		# unbiased on every side, so wall-sunk ends stay under the wall.
		draw_line(local_transform*(Vector2(line[0]).floor()+Vector2(0.5,0.5)),local_transform*(endpoint.floor()+Vector2(0.5,0.5)),Color(0.91,0.94,0.96),1.0,false)
	for point:Vector2 in draw_webs:
		# Untouched vanilla 16x16 cobweb; no generated radial spokes/rings.
		var diameter:float = unit.web_radius*2.0
		draw_texture_rect(COBWEB_TEXTURE,Rect2(local_transform*point-Vector2.ONE*unit.web_radius,Vector2.ONE*diameter),false)
