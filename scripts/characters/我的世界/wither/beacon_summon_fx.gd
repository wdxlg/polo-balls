extends Node2D
## Purely visual Nether Star arrival. The beacon body still falls and collides normally.
const STAR:Texture2D = preload("res://Images/characters/我的世界/wither/nether_star.png")
const SPARK:Texture2D = preload("res://Images/characters/我的世界/wither/effect_0.png")
const WHITE:Shader = preload("res://shaders/mc_beacon_summon_white.gdshader")
const SHAKE_DURATION:float = 0.24
const FLASH_DURATION:float = 0.16
const BOUNCE_DURATION:float = 0.43
var star:Sprite2D
var trail:CPUParticles2D
var white_flash:Sprite2D
var _block:Sprite2D
var _normal_scale:Vector2 = Vector2.ONE

static func flight_duration(distance:float) -> float:
	return clampf(0.68 + maxf(distance,0.0)*0.0012,0.68,1.12)

static func flight_position(start:Vector2,finish:Vector2,fraction:float) -> Vector2:
	var t:float = clampf(fraction,0.0,1.0)
	var eased:float = t*t*(3.0-2.0*t)
	var axis:Vector2 = finish-start
	var side:Vector2 = axis.orthogonal().normalized()
	return start.lerp(finish,eased) + side*clampf(axis.length()*0.11,4.0,16.0)*sin(PI*t)

static func bounce_scale(age:float) -> float:
	if age >= BOUNCE_DURATION: return 1.0
	return 1.0 + 0.22*exp(-10.0*maxf(age,0.0))*cos(23.0*maxf(age,0.0))

func setup(block:Sprite2D,body_diameter:float) -> void:
	_block = block
	_normal_scale = block.scale
	white_flash = Sprite2D.new()
	white_flash.name = "BeaconWhiteFlash"
	white_flash.texture = block.texture
	white_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	white_flash.z_index = 1
	white_flash.material = ShaderMaterial.new()
	(white_flash.material as ShaderMaterial).shader = WHITE
	white_flash.hide()
	block.add_child(white_flash)

	trail = CPUParticles2D.new()
	trail.name = "NetherStarTrail"
	trail.top_level = true
	trail.z_index = 3
	trail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	trail.texture = SPARK
	trail.amount = 36
	trail.lifetime = 0.48
	trail.local_coords = false
	trail.direction = Vector2.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 4.0
	trail.initial_velocity_max = 17.0
	trail.gravity = Vector2(0.0,12.0)
	trail.scale_amount_min = 0.55
	trail.scale_amount_max = 1.3
	var ramp:=Gradient.new()
	ramp.set_color(0,Color(1.0,0.96,0.72,1.0))
	ramp.set_color(1,Color(0.42,0.80,1.0,0.0))
	trail.color_ramp = ramp
	trail.emitting = false
	add_child(trail)

	star = Sprite2D.new()
	star.name = "FlyingNetherStar"
	star.top_level = true
	star.z_index = 4
	star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	star.texture = STAR
	star.scale = Vector2.ONE * (body_diameter*0.92 / float(STAR.get_width()))
	add_child(star)

func render(age:float,start:Vector2,finish:Vector2,flight:float,morph_age:float,alive:bool) -> void:
	if not alive:
		star.hide()
		trail.emitting = false
		white_flash.hide()
		return
	if morph_age >= 0.0:
		star.hide()
		trail.emitting = false
		_block.show()
		_block.scale = _normal_scale * bounce_scale(morph_age)
		var white_amount:float = 1.0-pow(clampf(morph_age/FLASH_DURATION,0.0,1.0),2.0)
		white_flash.self_modulate.a = white_amount
		white_flash.visible = white_amount > 0.001
		return
	_block.hide()
	white_flash.hide()
	star.show()
	var t:float = clampf(age/maxf(flight,0.01),0.0,1.0)
	star.global_position = flight_position(start,finish,t)
	if age >= flight:
		# Once it reaches the supporting wall, only the star trembles; the hitbox
		# and the eventual vertical beam are never shaken or rotated.
		star.global_position += Vector2(sin((age-flight)*109.0),cos((age-flight)*127.0))*0.85
		star.global_rotation = flight*TAU*2.4+sin((age-flight)*93.0)*0.13
	else:
		star.global_rotation = age*TAU*2.4
	trail.global_position = star.global_position
	trail.emitting = age < flight
