extends Node2D
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
var source_ref:WeakRef
var sequence:int = 0
var channel_index:int = -1
var kick_strength:float = 0.0
var snare_strength:float = 0.0
var hat_strength:float = 0.0
var musical_pitch:float = 0.5
var pitch_confidence:float = 0.0
var sustain_seconds:float = 0.0
var beat_strength:float = 0.0
var has_music_profile:bool = false
var age:float = 0.0
var music_knockbacks:int = 0
var song_index:int = 0
const SONG_COLORS:Array[Color] = [Color(1.0,0.34,0.07),Color(0.18,0.78,1.0),Color(0.40,1.0,0.35),Color(0.94,0.55,0.32),Color(0.76,0.60,1.0),Color(0.12,0.86,0.72)]
const ACCENT_COLORS:Array[Color] = [Color(1.0,0.82,0.22),Color(0.86,0.44,1.0),Color(0.78,1.0,0.60),Color(0.94,0.75,1.0),Color(0.72,1.0,1.0),Color(1.0,0.76,0.38)]
func theme_color() -> Color: return SONG_COLORS[song_index]
var heading:Vector2 = Vector2.RIGHT
var amplitude:float = 0.5
var radius:float = 4.0
var speed:float = 180.0
var max_radius:float = 180.0
var half_angle:float = deg_to_rad(7.5)
var line_width:float = 2.0
var trail_width:float = 20.0
var damage:float = 10.0
var hit_ids:Dictionary = {}
var any_hit:bool = false
var finished:bool = false
var _shape := RectangleShape2D.new()
func configure(source:Node2D,id:int,point:Vector2,direction:Vector2,peak:float,amount:float,song:int = -1,arc_degrees:float = -1.0) -> void:
	source_ref = weakref(source)
	sequence = id
	song_index = posmod(int(source.track_index) if song < 0 else song,SONG_COLORS.size())
	global_position = point
	heading = direction.normalized()
	amplitude = clampf(peak,0,1)
	speed = lerpf(110,240,amplitude)
	max_radius = lerpf(50,225,amplitude)
	var coverage:float = float(source.wave_angle_degrees) if arc_degrees<0 else arc_degrees
	# Immutable emission snapshot: only radius grows during flight.
	var upper:float = clampf(coverage,15,180)
	var progress:float = (upper-15.0)/165.0
	var lower:float = lerpf(3.0,90.0,progress)
	half_angle = deg_to_rad(lerpf(lower,upper,amplitude)*0.5)
	line_width = lerpf(0.20,0.55,amplitude)
	trail_width = lerpf(1.5,7,amplitude)
	damage = amount
func _ready() -> void:
	z_as_relative = false
	z_index = 6
	add_to_group("MCNoteWave")
	add_to_group("BattleTransient")
func _physics_process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	advance(delta)
func advance(delta:float) -> void:
	if finished: return
	var source:Node2D = source_ref.get_ref() if source_ref != null else null
	if not is_instance_valid(source) or source.health <= 0:
		finished = true
		queue_free()
		return
	age += delta
	var previous:float = radius
	radius = minf(max_radius,radius+speed*delta)
	if is_multiplayer_authority(): scan_arc(previous,radius,source)
	queue_redraw()
	if radius >= max_radius: complete()
func scan_arc(previous:float,current:float,source:Node2D) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.collision_mask = 2
	query.collide_with_bodies = false
	query.collide_with_areas = true
	# Swept radial bands along the visible arc; real hurtbox queries, no full-disk hit.
	var slices:int = maxi(1,int(ceil((current-previous)/5.0)))
	for slice:int in range(slices):
		var inner:float = lerpf(previous,current,float(slice)/slices)
		var outer:float = lerpf(previous,current,float(slice+1)/slices)
		var middle:float = (inner+outer)*0.5
		var segments:int = arc_segments(middle)
		for segment:int in range(segments):
			var a:Vector2 = Vector2.RIGHT.rotated(heading.angle()+lerpf(-half_angle,half_angle,float(segment)/segments))*middle
			var b:Vector2 = Vector2.RIGHT.rotated(heading.angle()+lerpf(-half_angle,half_angle,float(segment+1)/segments))*middle
			_shape.size = Vector2(a.distance_to(b)+0.4,outer-inner+line_width)
			query.transform = Transform2D((b-a).angle(),global_position+(a+b)*0.5)
			for contact:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,64):
				var area:Node = contact.collider
				var target:Node = area
				while is_instance_valid(target) and not target is ball: target = target.get_parent()
				if not target is ball or area != target.self_hurtbox or not U.enemy(source,target): continue
				var id:int = target.get_instance_id()
				if hit_ids.has(id) or not U.line_clear(self,global_position,target.global_position): continue
				hit_ids[id] = true
				var health_before:float = float(target.health)
				var hit_point:Vector2 = area.global_position
				if U.damage(source,target,damage,hit_point):
					var actual:float = maxf(0,health_before-float(target.health)) if is_instance_valid(target) else health_before
					apply_music_impact(target,source)
					source.register_music_hit(sequence)
					source.play_wave_impact(hit_point,actual)
					if not any_hit: report_result(source,true)
					any_hit = true
func complete() -> void:
	if finished: return
	finished = true
	var source:Node = source_ref.get_ref() if source_ref != null else null
	if is_multiplayer_authority() and is_instance_valid(source) and not any_hit: report_result(source,false)
	queue_free()
func _draw() -> void:
	var fade:float = clampf((max_radius-radius)/18.0,0,1)
	if has_music_profile: fade *= lerpf(0.72,1.0,beat_strength)
	draw_music_details(fade)
	# Three weighted tail bands replace twelve almost coincident pixel layers.
	# Preserve the old integrated tail opacity without changing any hit geometry.
	for band:int in range(3,0,-1):
		var weight:float=0.0
		var weighted_fraction:float=0.0
		for i:int in range((band-1)*4+1,band*4+1):
			var fraction:float=float(i)/12.0
			var alpha:float=pow(1.0-fraction,2.0)*0.12
			weight+=alpha
			weighted_fraction+=fraction*alpha
		if weight<=0.0: continue
		var r:float=radius-trail_width*weighted_fraction/weight
		if r>0.0:
			preload("res://scripts/effects/我的世界/pixel_arc.gd").draw(self,Vector2.ZERO,r,heading.angle()-half_angle,heading.angle()+half_angle,0,Color(theme_color(),weight*fade),line_width)
	preload("res://scripts/effects/我的世界/pixel_arc.gd").draw(self,Vector2.ZERO,radius,heading.angle()-half_angle,heading.angle()+half_angle,0,Color(theme_color(),0.95*fade),line_width)

	var accent:Color = ACCENT_COLORS[song_index]
	var time:float = radius/maxf(speed,1.0)
	match song_index:
		0: # Pigstep: orange/gold ember streaks riding behind the front.
			for i:int in range(8):
				var angle:float = heading.angle()+lerpf(-half_angle,half_angle,(float(i)+0.5)/8.0)
				var trail:float = fposmod(time*30.0+float(i)*3.7+sequence,trail_width)
				var point:Vector2 = Vector2.RIGHT.rotated(angle)*maxf(1,radius-trail)
				draw_line(point,point-Vector2.RIGHT.rotated(angle)*(2.0+amplitude*3.0),Color(accent,fade*(1.0-trail/trail_width)),0.5,true)
		1: # Otherside: cyan front, violet weaving ribbons and glints.
			for ribbon:int in range(2):
				var points:PackedVector2Array = []
				for j:int in range(arc_segments(radius)+1):
					var f:float = float(j)/arc_segments(radius)
					var r:float = maxf(1,radius-1.2-float(ribbon)*2.0+sin(f*TAU*2.0+time*7.0+ribbon*PI)*0.7)
					points.append(Vector2.RIGHT.rotated(heading.angle()+lerpf(-half_angle,half_angle,f))*r)
				draw_polyline(points,Color(accent,fade*0.6),0.35,true)
		2: # Cat: lime/mint front with small drifting musical-note glyphs.
			for i:int in range(5):
				var f:float = (float(i)+0.5)/5.0
				var point:Vector2 = Vector2.RIGHT.rotated(heading.angle()+lerpf(-half_angle,half_angle,f))*maxf(1,radius-trail_width*0.55)
				point.y += sin(time*8.0+i)*1.5
				var color:Color = Color(accent,fade*0.65)
				draw_circle(point,1.2,color)
				draw_line(point+Vector2(1,0),point+Vector2(1,-4),color,0.5,true)
				draw_line(point+Vector2(1,-4),point+Vector2(3,-3),color,0.5,true)

		3: # Creator: copper/lilac mechanical teeth, rendered without new hitboxes.
			for i:int in range(9):
				var a:float = heading.angle()+lerpf(-half_angle,half_angle,(i+0.5)/9.0)
				var axis:Vector2 = Vector2.RIGHT.rotated(a)
				var tip:Vector2 = axis*maxf(1,radius-2)
				draw_line(tip-axis*3,tip,Color(accent,fade*0.65),0.45,true)
				draw_line(tip,tip+axis.orthogonal()*1.7,Color(accent,fade*0.65),0.45,true)
		4: # Precipice: lavender/ice climbing chevrons.
			for i:int in range(7):
				var a:float = heading.angle()+lerpf(-half_angle,half_angle,(i+0.5)/7.0)
				var axis:Vector2 = Vector2.RIGHT.rotated(a)
				var tip:Vector2 = axis*maxf(1,radius-2.0-fposmod(time*9+i*1.7,5))
				var tangent:Vector2 = axis.orthogonal()
				draw_line(tip-axis*2-tangent*1.5,tip,Color(accent,fade*0.6),0.4,true)
				draw_line(tip,tip-axis*2+tangent*1.5,Color(accent,fade*0.6),0.4,true)
		5: # Relic: teal/sand pixel pulse trail.
			for i:int in range(8):
				var a:float = heading.angle()+lerpf(-half_angle,half_angle,(i+0.5)/8.0)
				var p:Vector2 = Vector2.RIGHT.rotated(a)*maxf(1,radius-2-fposmod(time*12+i*2,6))
				draw_rect(Rect2(p-Vector2.ONE,Vector2(2,2)),Color(accent,fade*0.65),false,0.4)

func arc_segments(at_radius:float) -> int:
	return clampi(int(ceil(2.0*half_angle*maxf(at_radius,1.0)/8.0)),12,192)

func report_result(source:Node,hit:bool) -> void:
	if channel_index>=0: source.resolve_channel(sequence,channel_index,hit)
	else: source.resolve_wave(sequence,hit)

func apply_music_profile(profile:Array) -> void:
	if profile.size()<8: return
	has_music_profile = true
	kick_strength = clampf(float(profile[0]),0,1)
	snare_strength = clampf(float(profile[1]),0,1)
	hat_strength = clampf(float(profile[2]),0,1)
	musical_pitch = clampf(float(profile[3]),0,1)
	pitch_confidence = clampf(float(profile[4]),0,1)
	sustain_seconds = clampf(float(profile[5]),0.04,1.0)
	beat_strength = clampf(float(profile[6]),0,1)
	if sustain_seconds>=0.22:
		trail_width = maxf(trail_width,minf(24.0,speed*sustain_seconds*0.13))
	elif sustain_seconds<=0.14:
		trail_width *= 0.55
func apply_music_impact(target:Node2D,source:Node2D) -> void:
	if kick_strength<0.55 or beat_strength<0.45 or not is_instance_valid(target): return
	# Light radial kick, no stun; same per-wave/per-target hit dedup as damage.
	var outward:Vector2 = global_position.direction_to(target.global_position)
	if outward.length_squared()<0.001: outward = heading
	target.apply_knockback(outward,lerpf(4,10,kick_strength)*beat_strength,90.0,0.0,0.0,{"source":source,"stop_on_character":true,"lock_control":false,"control_recovery_time":0.0})
	music_knockbacks += 1
func draw_music_details(fade:float) -> void:
	if not has_music_profile: return
	var accent:Color = ACCENT_COLORS[song_index]
	var attack_fade:float = exp(-age*6.0)*fade
	if kick_strength>=0.55:
		var r:float = maxf(1,radius-2.0-3.0*kick_strength)
		preload("res://scripts/effects/我的世界/pixel_arc.gd").draw(self,Vector2.ZERO,r,heading.angle()-half_angle,heading.angle()+half_angle,arc_segments(r)+1,Color(accent,attack_fade*kick_strength*0.7),0.45,true)
	# Short high-frequency ticks and crossed mid-frequency taps; no extra projectiles.
	var ticks:int = 3+int(hat_strength*8.0)
	if hat_strength>=0.4 or snare_strength>=0.5:
		for i:int in range(ticks):
			var f:float = (i+0.5)/ticks
			var a:float = heading.angle()+lerpf(-half_angle,half_angle,f)
			var axis:Vector2 = Vector2.RIGHT.rotated(a)
			var tangent:Vector2 = axis.orthogonal()
			var p:Vector2 = axis*maxf(1,radius-1.5)
			var length:float = 1.0+2.0*hat_strength
			draw_line(p-tangent*length,p+tangent*length,Color(accent,attack_fade*maxf(hat_strength,snare_strength)),0.4,true)
			if snare_strength>=0.5: draw_line(p-axis*1.5,p+axis*1.5,Color(accent,attack_fade*snare_strength),0.4,true)
	if pitch_confidence>=0.45:
		var count:int = 3+int(musical_pitch*9.0)
		for i:int in range(count):
			var f:float = (i+0.5)/count
			var a:float = heading.angle()+lerpf(-half_angle,half_angle,f)
			var p:Vector2 = Vector2.RIGHT.rotated(a)*maxf(1,radius-trail_width*0.6)
			p.y += lerpf(2,-3,musical_pitch)
			var tint:Color = Color(accent,fade*pitch_confidence*0.5)
			draw_circle(p,0.65,tint)
			draw_line(p,p+Vector2(0,-lerpf(1.5,3.5,musical_pitch)),tint,0.35,true)
