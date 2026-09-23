extends "res://scripts/characters/我的世界/new5/base.gd"
## The heart falls vertically, then patrols the ground on X only; it remains targetable.
const BEACON_TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_front.png")
const BEAM_TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_beam.png")
const HEART_TEXTURE = preload("res://Images/characters/我的世界/wither/nether_star.png")
const VANILLA_SOUND = preload("res://scripts/characters/我的世界/wither/audio.gd")
const BEAM_VISUAL = preload("res://scripts/characters/我的世界/wither/beacon_beam.gd")
const GRAVITY:float = 1200.0
const TERMINAL_SPEED:float = 1100.0
const BEAM_RADIUS:float = 7.0
var _activated:bool = false
var _beam_visual:Node2D
var _body:CollisionShape2D
const BUFFS:Array[String] = ["speed","haste","strength","resistance","regeneration"]
var landed:bool = false
var fall_speed:float = 0.0
var beam_timer:float = 10.0
var warning_left:float = 0.0
var firing_left:float = 0.0
var tick_left:float = 0.0
var beam_end:Vector2
var beam_direction:Vector2 = Vector2.UP
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body = get_node("CollisionShape2D")
	# Ignore our summoner at spawn, not terrain or enemy body/hurtbox collisions.
	if is_instance_valid(Master) and Master is PhysicsBody2D: add_collision_exception_with(Master)
	_beam_visual = BEAM_VISUAL.new()
	_beam_visual.name = "VanillaBeaconBeam"
	_beam_visual.top_level = true # Beam dimensions/hazards are world units, not scaled character pixels.
	add_child(_beam_visual)
	add_to_group("AI_Hazard")
	add_to_group("WitherBeacon")
func get_preview_texture() -> Texture2D: return BEACON_TEXTURE
func voice_role() -> String: return ""
func move(_speed:float,_delta:float) -> void: pass
func stand(_delta:float): Repel = Vector2.ZERO
func step_mob(delta:float) -> void:
	var master:ball = Master as ball if is_instance_valid(Master) and Master is ball else null
	if master == null or master.health <= 0: queue_free(); return
	var target:ball = U.nearest(self)
	var horizontal:float = 0.0
	if _activated and target != null and warning_left <= 0 and firing_left <= 0 and not dizziness:
		horizontal = clampf((target.global_position.x-global_position.x)/maxf(delta,0.000001),-maxf(Speed,0.0),maxf(Speed,0.0))
	# Swept full-body collisions on every step, including after the first landing.
	# No Y seeking, map-edge teleport, or permanent "landed means floating" latch.
	var remaining:float = maxf(delta,0.0)
	while remaining > 0.000001:
		var dt:float = minf(remaining,1.0/120.0)
		remaining -= dt
		_gravity_step(dt,horizontal)
	beam_direction = Vector2.UP
	beam_end = _clipped_beam()
	if not _activated: return
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
					var nearest:Vector2 = Geometry2D.get_closest_point_to_segment(enemy.global_position,beam_origin(),beam_end)
					if nearest.distance_to(enemy.global_position) <= BEAM_RADIUS+enemy.get_crowd_separation_radius_world():
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
		beam_direction = Vector2.UP
		beam_end = _clipped_beam()
		warning_left = 0.6

func _gravity_step(dt:float,horizontal:float) -> void:
	var motion_x:float = horizontal+Repel.x
	velocity.x = motion_x
	if absf(motion_x)>0.00001:
		var side:KinematicCollision2D = move_and_collide(Vector2(motion_x*dt,0.0),false,0.001,false)
		if side != null: velocity.x = 0.0
	fall_speed = minf(fall_speed+GRAVITY*dt,TERMINAL_SPEED)
	velocity.y = fall_speed
	var down:KinematicCollision2D = move_and_collide(Vector2(0.0,fall_speed*dt),false,0.001,false)
	landed = down != null and down.get_normal().y < -0.5
	if down != null:
		fall_speed = 0.0
		velocity.y = 0.0
	if landed and not _activated:
		_activated = true
		if image is Sprite2D: (image as Sprite2D).visible = true
		_emit_sound("beacon_activate")

func beam_origin() -> Vector2:
	var half_height:float = _body.shape.get_rect().size.y*absf(_body.global_scale.y)*0.5 if is_instance_valid(_body) else 37.0
	return global_position+Vector2(0,-half_height)

func _clipped_beam() -> Vector2:
	var origin:Vector2 = beam_origin()
	var source:ball = Master as ball if is_instance_valid(Master) and Master is ball else null
	var top:float = origin.y-4096.0
	if source != null:
		var arena:Rect2 = source.call("mc_arena_rect")
		if arena.has_area(): top = minf(arena.position.y,origin.y-1.0)
	var end:Vector2 = Vector2(origin.x,top)
	var excludes:Array[RID] = [get_rid()]
	if source != null: excludes.append(source.get_rid())
	var query:=PhysicsRayQueryParameters2D.create(origin,end,1,excludes)
	var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	return Vector2(hit.position) if not hit.is_empty() else end

func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	if firing_left <= 0 and warning_left <= 0 or health <= 0: return {}
	var master:ball = Master as ball if is_instance_valid(Master) and Master is ball else null
	if master == null: return {}
	return {"shape":"segment","start":beam_origin(),"end":beam_end,"radius":BEAM_RADIUS,"damage":0.0 if warning_left>0 else 12.0,"danger_in":maxf(warning_left,0.0),"danger_duration":maxf(firing_left,0.1),"source":master,"kind":"wither_beacon_beam"}
func get_debug_detection_regions() -> Array[Dictionary]:
	if warning_left <= 0 or health <= 0: return []
	return [{"shape":"segment","start":beam_origin(),"end":beam_end,"radius":BEAM_RADIUS}]
func Die() -> void:
	warning_left = 0.0
	firing_left = 0.0
	if is_instance_valid(_beam_visual): _beam_visual.hide()
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
func visual_state() -> Dictionary:
	return {"time":clock,"activated":_activated,"landed":landed,"warning":warning_left,"firing":firing_left,"beam_end":beam_end}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_activated = bool(data.get("activated",_activated))
	landed = bool(data.get("landed",landed))
	warning_left = float(data.get("warning",0.0))
	firing_left = float(data.get("firing",0.0))
	beam_end = data.get("beam_end",beam_end)
	if image is Sprite2D: (image as Sprite2D).visible = _activated
func _draw() -> void:
	if not _activated: draw_texture_rect(HEART_TEXTURE,Rect2(-16,-16,32,32),false)
func _process(delta:float) -> void:
	super._process(delta)
	if is_instance_valid(_beam_visual):
		_beam_visual.global_transform = Transform2D(0.0,beam_origin())
		_beam_visual.call("update_beam",maxf(beam_origin().y-beam_end.y,0.0),_view_clock,warning_left>0 and health>0,firing_left>0 and health>0)
	queue_redraw()
