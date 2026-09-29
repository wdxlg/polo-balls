extends Node2D
signal impact_started(point:Vector2)

# Vanilla-inspired 2D adaptation: angular layered columns and two short strokes.
# Shared by Creeper, trident and fog-man: stronger network-blue lightning,
# compact shock ring at the exact attack radius, and short white impact streaks.
# This node emits one impact only; later visual flashes never repeat gameplay.
const HIT_BURST_EFFECT_SCRIPT = preload("res://scripts/effects/hit_burst_effect.gd")
const GLOW_SCRIPT = preload("res://scripts/effects/我的世界/lightning_glow.gd")
const PALETTE = preload("res://scripts/effects/我的世界/mc_electric_palette.gd")
const THUNDER_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/苦力怕/thunder1.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/thunder2.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/thunder3.ogg"),
]
const EXPLOSION_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/苦力怕/explode1.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode2.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode3.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/explode4.ogg"),
]
@export_category("雷电 / 时序")
@export_range(0.10,1.50,0.01) var warning_delay:float = 0.68
@export_range(0.08,0.80,0.01) var bolt_lifetime:float = 0.28
@export_range(0.12,1.00,0.01) var impact_lifetime:float = 0.46
@export_category("雷电 / 方折光柱")
@export_range(5,12,1) var segment_count:int = 8
@export_range(4.0,45.0,1.0) var bend_strength:float = 32.0
@export_range(0.5,12.0,0.1) var core_width:float = 7.0
@export_range(1.0,24.0,0.1) var inner_glow_width:float = 16.0
@export_range(3.0,40.0,0.1) var outer_glow_width:float = 28.0
@export_category("雷电 / 小范围冲击反馈")
# The first visible ring uses this SAME radius supplied by the damage caller.
@export_range(12.0,180.0,1.0) var impact_radius:float = 62.0
@export_range(1.0,1.25,0.01) var impact_ring_end_scale:float = 1.12
@export_range(0.1,1.2,0.01) var ring_lifetime:float = 0.54
@export_range(4,8,1) var impact_line_count:int = 7
@export_range(0.2,1.2,0.01) var streak_lifetime:float = 0.78
@export_category("雷电 / 音效")
@export_range(-30.0,12.0,0.5) var thunder_volume_db:float = -5.0
@export_range(-30.0,12.0,0.5) var explosion_volume_db:float = -2.5
@export_range(100.0,2400.0,25.0) var audio_max_distance:float = 1200.0
var _target_world:Vector2 = Vector2.ZERO
var _seed_value:int = 1
var _configured:bool = false
var _rng := RandomNumberGenerator.new()
var _start_local:Vector2 = Vector2.ZERO
var _end_local:Vector2 = Vector2.ZERO
var _points := PackedVector2Array()
var _branches:Array[PackedVector2Array] = []
var _elapsed:float = 0.0
var _impact_started:bool = false
var _impact_at:float = 0.0
var _impact_lines:Array[Dictionary] = []
var _white_lines_end:float = 0.0
var _white_lines:Node2D
var _glow:Node2D
var _flash_index:int = 0
func setup(target_world_position:Vector2,seed_value:int = 1,new_impact_radius:float = -1.0,new_warning_delay:float = -1.0) -> void:
	_target_world = target_world_position
	_seed_value = maxi(abs(seed_value),1)
	if new_impact_radius>0.0: impact_radius = new_impact_radius
	if new_warning_delay>0.0: warning_delay = new_warning_delay
	_configured = true
func _ready() -> void:
	add_to_group("BattleTransient")
	set_as_top_level(true)
	z_as_relative = false
	z_index = 180
	_rng.seed = _seed_value
	global_position = _target_world if _configured else global_position
	_end_local = Vector2.ZERO
	_start_local = _resolve_window_top_world(global_position)-global_position
	_rebuild_path()
	_glow = GLOW_SCRIPT.new()
	_glow.name = "LightningAdditiveGlow"
	_glow.source = self
	add_child(_glow)
	_play_random_spatial_sfx(THUNDER_SOUNDS,thunder_volume_db,"CreeperThunderWarning")
	queue_redraw()
func _process(delta:float) -> void:
	_elapsed += maxf(delta,0.0)
	if not _impact_started: _follow_parent_foot_until_impact()
	if not _impact_started and _elapsed>=warning_delay: _start_impact()
	if _impact_started:
		var flash:int = _flash_slot(_impact_elapsed())
		# Stable angular geometry during each stroke, not a continuously wriggling laser.
		if flash>=0 and flash!=_flash_index:
			_flash_index = flash
			_rebuild_path()
		# Reuse Creeper's real Line2D grow/travel/shrink animation with our paused clock.
		if is_instance_valid(_white_lines) and not _white_lines.is_queued_for_deletion():
			_white_lines._process(maxf(_impact_elapsed()-float(_white_lines._elapsed),0.0))
		_glow.queue_redraw()
		queue_redraw()
	if _impact_started and _impact_elapsed()>=presentation_lifetime(): queue_free()
func _start_impact() -> void:
	if _impact_started: return
	_follow_parent_foot_until_impact()
	_impact_started = true
	_impact_at = _elapsed # No frame overshoot: first visible ring is exactly the hit radius.
	_build_impact_lines()
	_flash_index = 0
	_start_local = _resolve_window_top_world(global_position)-global_position
	_rebuild_path()
	_play_random_spatial_sfx(EXPLOSION_SOUNDS,explosion_volume_db,"CreeperLightningImpact")
	impact_started.emit(global_position)
	queue_redraw()
func presentation_lifetime() -> float:
	# Independent visual envelopes. Keep the owner until the LAST actual streak ends,
	# including its random start delay and HitBurst's own cleanup grace period.
	return maxf(maxf(bolt_lifetime+GLOW_SCRIPT.AFTERGLOW_DURATION,impact_lifetime),maxf(ring_lifetime,_white_lines_end))
func impact_ring_alpha() -> float:
	return pow(clampf(1.0-_impact_elapsed()/maxf(ring_lifetime,0.001),0.0,1.0),1.25)
func _impact_elapsed() -> float: return maxf(_elapsed-_impact_at,0.0)
func _flash_slot(time:float) -> int:
	var p:float = time/maxf(bolt_lifetime,0.001)
	if p<0.0 or p>=1.0: return -1
	if p<0.34: return 0
	if p<0.54: return -1
	return 1
func _follow_parent_foot_until_impact() -> void:
	if _impact_started: return
	var owner_node:Node = get_parent()
	if not is_instance_valid(owner_node) or not owner_node.has_method("_self_foot_world_position"): return
	var resolved:Variant = owner_node.call("_self_foot_world_position")
	if resolved is Vector2: global_position = resolved
func _resolve_window_top_world(target_world:Vector2) -> Vector2:
	var viewport:Viewport = get_viewport()
	if viewport==null: return target_world+Vector2(0.0,-900.0)
	var canvas:Transform2D = viewport.get_canvas_transform()
	var target_screen:Vector2 = canvas*target_world
	return canvas.affine_inverse()*Vector2(target_screen.x,viewport.get_visible_rect().position.y-12.0)
func _rebuild_path() -> void:
	# Geometry RNG is independent of sound choice, so equal seeds stay equal on peers.
	var random := RandomNumberGenerator.new()
	random.seed = _seed_value+_flash_index*104729
	var count:int = maxi(segment_count,3)
	var height:float = maxf(-_start_local.y,96.0)
	var walk:float = 0.0
	var step_span:float = clampf(height/float(count)*0.5,bend_strength*0.75,bend_strength*2.5)
	var path := PackedVector2Array([_end_local])
	for i:int in range(1,count+1):
		walk = clampf(walk+float(random.randi_range(-8,8))*step_span/8.0,-bend_strength*2.2,bend_strength*2.2)
		path.append(Vector2(roundf(walk),-height*float(i)/float(count)))
	path.reverse()
	_points = path
	_branches.clear()
	# Two short forks high on the column; neither creates another ground impact.
	for fork:int in range(2):
		var start:int = 2+fork*2
		if start>=count-1: continue
		var branch := PackedVector2Array([path[start]])
		var side:float = -1.0 if random.randf()<0.5 else 1.0
		for step:int in range(2):
			branch.append(branch[-1]+Vector2(side*random.randf_range(0.65,1.35)*step_span,height/float(count)*0.75))
		_branches.append(branch)
func _draw() -> void:
	if not _impact_started: return
	_draw_impact_ring()
	if _flash_slot(_impact_elapsed())<0: return
	var strength:float = 1.0 if _flash_index==0 else 0.85
	_draw_column(_points,1.0,strength)
	for branch:PackedVector2Array in _branches: _draw_column(branch,0.60,strength*0.85)
func _draw_column(path:PackedVector2Array,width_scale:float,alpha:float) -> void:
	var widths:Array[float] = [outer_glow_width,inner_glow_width,inner_glow_width*0.65,core_width]
	var colors:Array[Color] = [Color(PALETTE.OUTER,0.32),Color(PALETTE.MIDDLE,0.55),Color(PALETTE.CORE,0.82),Color(PALETTE.CORE,1.0)]
	for layer:int in range(widths.size()):
		var color:Color = colors[layer]
		color.a *= alpha
		for i:int in range(path.size()-1):
			var a:Vector2 = path[i]
			var b:Vector2 = path[i+1]
			var top:float = widths[layer]*width_scale*0.5
			var bottom:float = top
			if width_scale<1.0:
				top *= lerpf(1.0,0.4,float(i)/float(path.size()-1))
				bottom *= lerpf(1.0,0.4,float(i+1)/float(path.size()-1))
			# Horizontal cross-sections form hard square-sided segments, the separate additive layer supplies the soft halo.
			draw_colored_polygon(PackedVector2Array([a+Vector2(-top,0),a+Vector2(top,0),b+Vector2(bottom,0),b+Vector2(-bottom,0)]),color)
func impact_ring_radius() -> float:
	var p:float = clampf(_impact_elapsed()/maxf(ring_lifetime,0.001),0.0,1.0)
	return impact_radius*lerpf(1.0,clampf(impact_ring_end_scale,1.0,1.25),1.0-pow(1.0-p,2.0))
func _draw_impact_ring() -> void:
	var p:float = _impact_elapsed()/maxf(ring_lifetime,0.001)
	if p>=1.0: return
	var fade:float = impact_ring_alpha()
	var radius:float = impact_ring_radius()
	preload("res://scripts/effects/我的世界/pixel_arc.gd").draw(self,Vector2.ZERO,radius,0.0,TAU,64,Color(PALETTE.OUTER,0.3*fade),5.5,true)
	preload("res://scripts/effects/我的世界/pixel_arc.gd").draw(self,Vector2.ZERO,radius,0.0,TAU,64,Color(PALETTE.MIDDLE,0.75*fade),3.0,true)
	preload("res://scripts/effects/我的世界/pixel_arc.gd").draw(self,Vector2.ZERO,radius,0.0,TAU,64,Color(PALETTE.CORE,fade),1.6,true)
	# A compact contact flash, never a full-screen flash or radius-sized filled disk.
	draw_circle(Vector2.ZERO,minf(impact_radius*0.16,10.0),Color(PALETTE.CORE,0.4*pow(1.0-p,4.0)))
func _build_impact_lines() -> void:
	_impact_lines.clear()
	var random := RandomNumberGenerator.new()
	random.seed = _seed_value^408152
	# Restore the ORIGINAL Creeper lightning HitBurst profile (golden-angle scatter,
	# staggered onset, grow/shrink, cool-white tint), scaled down in space, not time.
	var scale_value:float = 0.4
	for i:int in range(clampi(impact_line_count,4,8)):
		var angle:float = float(i)*2.39996323+random.randf_range(-0.54,0.54)
		var direction:Vector2 = Vector2.RIGHT.rotated(angle)
		var tangent:Vector2 = Vector2(-direction.y,direction.x)
		var offset:Vector2 = (direction*random.randf_range(impact_radius*0.08,impact_radius*0.36)+tangent*random.randf_range(-impact_radius*0.16,impact_radius*0.16))*scale_value
		var cool_mix:float = random.randf_range(0.0,1.0)
		var duration:float = streak_lifetime if i==0 else random.randf_range(streak_lifetime*0.72,streak_lifetime)
		_impact_lines.append({
			"spawn_offset":offset,"direction":direction,
			"distance":impact_radius*random.randf_range(1.25,2.35)*scale_value,
			"length":impact_radius*random.randf_range(0.34,0.78)*scale_value,
			"width":random.randf_range(0.85,1.6),
			"duration":duration,
			"delay":random.randf_range(0.0,0.045),
			"grow_end":clampf(random.randf_range(0.055,0.095)/maxf(duration,0.001),0.08,0.55),
			"fade_in_end":random.randf_range(0.06,0.12),
			"fade_out_start":random.randf_range(0.46,0.62),
			"color":Color(lerpf(1.0,0.82,cool_mix),lerpf(1.0,0.94,cool_mix),1.0,0.98),
		})
	_white_lines = HIT_BURST_EFFECT_SCRIPT.new()
	_white_lines.name = "CreeperLightningWhiteLines"
	_white_lines.setup(global_position,_impact_lines)
	add_child(_white_lines)
	# Owned child = battle/owner cleanup; manual clock = no drift during trident pause.
	_white_lines.set_process(false)
	_white_lines_end = float(_white_lines._end_time)+0.02
func _play_random_spatial_sfx(streams:Array[AudioStream],volume_db:float,node_name:String) -> void:
	if streams.is_empty(): return
	var stream:AudioStream = streams[_rng.randi_range(0,streams.size()-1)]
	if stream==null: return
	var parent:Node = get_parent()
	if not is_instance_valid(parent): return
	var player := AudioStreamPlayer2D.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _rng.randf_range(0.97,1.03)
	player.max_distance = maxf(audio_max_distance,100.0)
	player.attenuation = 0.72
	player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
	parent.add_child(player,true)
	player.global_position = global_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
