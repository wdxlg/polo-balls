extends "res://scripts/characters/我的世界/new5/base.gd"
## The heart falls vertically, then patrols the ground on X only; it remains targetable.
const BEACON_TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_front.png")
const BEAM_TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_beam.png")
const HEART_TEXTURE = preload("res://Images/characters/我的世界/wither/nether_star.png")
const VANILLA_SOUND = preload("res://scripts/characters/我的世界/wither/audio.gd")
const BUFFS:Array[String] = ["speed","haste","strength","resistance","regeneration"]
var landed:bool = false
var fall_speed:float = 0.0
var beam_timer:float = 10.0
var warning_left:float = 0.0
var firing_left:float = 0.0
var tick_left:float = 0.0
var beam_end:Vector2
var beam_direction:Vector2 = Vector2.RIGHT
var beams_fired:int = 0
var last_buff:String = ""
func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	if image is Sprite2D:
		(image as Sprite2D).texture = BEACON_TEXTURE
		(image as Sprite2D).visible = false # Falling Nether Star, not yet a beacon.
	add_to_group("AI_Hazard")
	add_to_group("WitherBeacon")
func get_preview_texture() -> Texture2D: return BEACON_TEXTURE
func voice_role() -> String: return ""
func move(_speed:float,_delta:float) -> void: pass
func stand(_delta:float): Repel = Vector2.ZERO
func step_mob(delta:float) -> void:
	var master:ball = Master as ball if is_instance_valid(Master) and Master is ball else null
	if master == null or master.health <= 0: queue_free(); return
	if not landed:
		fall_speed = minf(fall_speed+1200.0*delta,1100.0)
		var bottom:float = global_position.y+fall_speed*delta
		var query:=PhysicsRayQueryParameters2D.create(global_position,Vector2(global_position.x,bottom+20.0),1,[get_rid(),master.get_rid()])
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position.y = float(hit.position.y)-20.0
			landed = true
			if image is Sprite2D: (image as Sprite2D).visible = true
			_emit_sound("beacon_activate")
			fall_speed = 0.0
		else:
			var arena:Rect2 = master.call("mc_arena_rect")
			var limit:float = arena.end.y-24.0
			global_position.y = minf(bottom,limit)
			if global_position.y >= limit:
				landed = true
				if image is Sprite2D: (image as Sprite2D).visible = true
				_emit_sound("beacon_activate")
		return
	var target:ball = U.nearest(self)
	if target != null and warning_left <= 0 and firing_left <= 0:
		var dx:float = clampf(target.global_position.x-global_position.x,-60.0*delta,60.0*delta)
		var candidate:Vector2 = global_position+Vector2(dx,0)
		var arena:Rect2 = master.call("mc_arena_rect")
		var rect:Rect2 = arena.grow(-20.0)
		if rect.has_point(candidate) and _can_slide_to(candidate): global_position = candidate
	if warning_left > 0:
		warning_left -= delta
		beam_end = _clipped_beam()
		if warning_left <= 0:
			_emit_sound("beacon_power")
			firing_left = 1.5
			tick_left = 0.5
		return
	if firing_left > 0:
		firing_left -= delta
		beam_end = _clipped_beam()
		tick_left -= delta
		if tick_left <= 0:
			tick_left += 0.5
			for node:Node in SubmissionCharacterTools.targeting_candidates(master):
				if node is ball and master.call("mc_enemy",node):
					var enemy:ball = node as ball
					var nearest:Vector2 = Geometry2D.get_closest_point_to_segment(enemy.global_position,global_position,beam_end)
					if nearest.distance_to(enemy.global_position) <= 7.0+enemy.get_crowd_separation_radius_world():
						master.call("impact",enemy,12.0,nearest)
		if firing_left <= 0:
			_emit_sound("beacon_deactivate")
			beams_fired += 1
			last_buff = BUFFS[rng.randi_range(0,BUFFS.size()-1)]
			master.call("apply_beacon_buff",last_buff)
			beam_timer = 10.0
		return
	beam_timer -= delta
	if beam_timer <= 0 and target != null:
		beam_direction = (target.global_position-global_position).normalized()
		if beam_direction.length_squared() < 0.001: beam_direction = Vector2.RIGHT
		beam_end = _clipped_beam()
		warning_left = 0.6

func _can_slide_to(point:Vector2) -> bool:
	var shape:=CircleShape2D.new()
	shape.radius = 20.0
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
func _clipped_beam() -> Vector2:
	var end:Vector2 = global_position+beam_direction*320.0
	var source:ball = Master as ball if is_instance_valid(Master) and Master is ball else null
	var excludes:Array[RID] = [get_rid()]
	if source != null: excludes.append(source.get_rid())
	var query:=PhysicsRayQueryParameters2D.create(global_position,end,1,excludes)
	var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	return Vector2(hit.position) if not hit.is_empty() else end
func get_ai_hazard_info() -> Dictionary:
	if firing_left <= 0 and warning_left <= 0 or health <= 0: return {}
	var master:ball = Master as ball if is_instance_valid(Master) and Master is ball else null
	if master == null: return {}
	return {"shape":"segment","start":global_position,"end":beam_end,"radius":7.0,"damage":12.0,"danger_in":maxf(warning_left,0.0),"danger_duration":maxf(firing_left,0.1),"source":master,"kind":"wither_beacon_beam"}
func Die() -> void:
	if is_instance_valid(Master) and Master.has_method("apply_beacon_buff"):
		Master.call("apply_beacon_buff","")
	super.Die()
func visual_mob() -> void:
	if image is Sprite2D:
		image.rotation = 0.0
		image.position = Vector2.ZERO
func _emit_sound(event:String) -> void:
	VANILLA_SOUND.play(self,event,global_position)
	if multiplayer.has_multiplayer_peer(): _remote_sound.rpc(event,global_position)
@rpc("authority","call_remote","reliable")
func _remote_sound(event:String,point:Vector2) -> void: VANILLA_SOUND.play(self,event,point)
func _draw() -> void:
	if not landed: draw_texture_rect(HEART_TEXTURE,Rect2(-16,-16,32,32),false)
	if warning_left <= 0 and firing_left <= 0: return
	var ray:Vector2 = to_local(beam_end)
	draw_set_transform(Vector2.ZERO,ray.angle(),Vector2.ONE)
	for x:int in range(0,int(ray.length()),16):
		draw_texture_rect(BEAM_TEXTURE,Rect2(float(x),-7.0,minf(16.0,ray.length()-float(x)),14.0),false,Color(1,1,1,0.45 if warning_left > 0 else 0.9))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
func _process(delta:float) -> void:
	super._process(delta)
	queue_redraw()
