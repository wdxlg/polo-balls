extends Label

# Absolute displayed amount: 1 is the softest colour, 500+ reaches the strongest.
const COLOR_FULL_AMOUNT:float = 500.0
const INFINITE_AMOUNT:float = 10_000_000_000.0
static var _visual_random:RandomNumberGenerator
var base_position:Vector2
var if_shake:bool = false # Legacy callers; motion no longer jitters every frame.
var shake_amount:float = 1.0
var target_scale:float = 1.0
var _infinite_damage_visual:bool = false
var _kind:StringName = &"damage"
var _flight_origin:Vector2
var _flight_velocity:Vector2
var _gravity:float
var _lifetime:float
var _flight:Tween

static func visual_random() -> RandomNumberGenerator:
	if _visual_random == null:
		_visual_random = RandomNumberGenerator.new()
		_visual_random.randomize()
	return _visual_random

static func amount_color(amount:float,kind:StringName = &"damage") -> Color:
	var strength:float = 1.0 if is_inf(amount) else sqrt(clampf((absf(amount)-1.0)/(COLOR_FULL_AMOUNT-1.0),0.0,1.0))
	match kind:
		&"block": return Color("e0e0e0").lerp(Color("787878"),strength)
		&"heal": return Color("208c44").lerp(Color("a2ffad"),strength)
		_: return Color("ffe34c").lerp(Color("ff3830"),strength)

func configure_amount(amount:float,kind:StringName = &"damage") -> void:
	_kind = kind
	_infinite_damage_visual = is_inf(amount) or absf(amount) >= INFINITE_AMOUNT
	text = "INF" if _infinite_damage_visual else ("+" if kind == &"heal" else "-")+str(int(round(absf(amount))))
	set_properties(INFINITE_AMOUNT if _infinite_damage_visual else amount)
	add_theme_color_override("font_color",amount_color(amount,kind))
	add_theme_color_override("font_outline_color",Color("17202a"))
	add_theme_color_override("font_shadow_color",Color(0,0,0,0.45))

func set_infinite_damage_visual() -> void:
	# Keep the INF notation, but obey the category's high-value colour now.
	configure_amount(INFINITE_AMOUNT,_kind)

func set_properties(hp:float) -> void:
	var magnitude:float = INFINITE_AMOUNT if is_inf(hp) else absf(hp)
	shake_amount = clampf(magnitude/10.0,1.0,5.0)
	add_theme_font_size_override("font_size",int(clampf(magnitude/5.0,10.0,25.0)))

func _ready() -> void:
	set_process(false)
	z_as_relative = false
	z_index = 98
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_multiplayer_authority(): call_deferred("_start_flight")

func _start_flight() -> void:
	if is_queued_for_deletion(): return
	var rng:RandomNumberGenerator = visual_random()
	_lifetime = rng.randf_range(0.95,1.12)*clampf(target_scale,0.75,1.5)
	var apex_time:float = _lifetime*rng.randf_range(0.40,0.46)
	var height:float = rng.randf_range(20.0,32.0)
	_gravity = 2.0*height/(apex_time*apex_time)
	var side:float = -1.0 if rng.randf()<0.5 else 1.0
	_flight_velocity = Vector2(side*rng.randf_range(18.0,38.0)/_lifetime,-_gravity*apex_time)
	# The spawn point marks the centre of the number, not its upper-left corner.
	_flight_origin = global_position-size*0.5
	base_position = _flight_origin
	if _flight != null and _flight.is_valid(): _flight.kill()
	_flight = create_tween()
	_flight.tween_method(_sample_flight,0.0,_lifetime,_lifetime)
	_flight.finished.connect(Game.free_node.bind(self))
	_sample_flight(0.0)

func _sample_flight(elapsed:float) -> void:
	var t:float = clampf(elapsed,0.0,_lifetime)
	global_position = _flight_origin+_flight_velocity*t+Vector2(0,0.5*_gravity*t*t)
	var progress:float = t/maxf(_lifetime,0.001)
	modulate.a = 1.0-smoothstep(0.48,1.0,progress)
	scale = Vector2.ONE*minf(t/0.085,1.0)

func move(poi:Vector2) -> void:
	global_position = poi # Compatibility only; new flight uses a continuous parabola.
