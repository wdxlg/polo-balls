extends Node2D
## Minecraft's actual totem item + glitter_7..0 totem particle atlas. Visual only.
const ITEM:Texture2D = preload("res://Images/characters/我的世界/唤魔者/totem_of_undying.png")
const MC_FX = preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
const PARTICLE_COUNT:int = 88
const LIFETIME:float = 1.55
const GRAVITY:float = 240.0
const GROUND_FADE:float = 0.18
const PARTICLE_TAIL:float = 1.1
const ICON_WIDTH:float = 20.0 # Near the native 16px item size; the old 72px icon obscured the Evoker.
const INTRO_SECONDS:float = 0.19 # Pop out of the Evoker before the fast front/back spin.
const SPIN_RAMP_SECONDS:float = 0.045
const WOBBLE_RAMP_SECONDS:float = 0.18
const PARTICLE_COLORS = [Color(1.0,0.97,0.36),Color(0.34,0.90,0.28),Color(0.72,0.98,0.32),Color(1.0,0.80,0.25)]

var totem_sprite:Sprite2D
var particles:Array[Dictionary] = []
var age:float = 0.0
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()
var _follow:WeakRef

func setup(point:Vector2, follow_target:Node2D = null) -> void:
	global_position = point
	if follow_target != null: _follow = weakref(follow_target)
	z_as_relative = false
	z_index = 300 # Above the battlefield's map/feedback layers; UI CanvasLayers remain on top.
	add_to_group("BattleTransient")
	add_to_group("MCEvokerTotemFX")
	_rng.randomize()
	totem_sprite = Sprite2D.new()
	totem_sprite.name = "TotemItem"
	totem_sprite.texture = ITEM
	totem_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(totem_sprite)
	for i:int in range(PARTICLE_COUNT):
		var sprite:Sprite2D = Sprite2D.new()
		sprite.texture = MC_FX.END_ROD[0]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		particles.append({
			"sprite":sprite,
			"offset":Vector2(_rng.randf_range(-13.0,13.0),_rng.randf_range(-9.0,9.0)),
			"velocity":Vector2(_rng.randf_range(-18.0,18.0),_rng.randf_range(-12.0,5.0)),
			"delay":float(i)*LIFETIME/float(PARTICLE_COUNT),
			"started":false,
			"diameter":_rng.randf_range(2.8,5.0),
			"color":PARTICLE_COLORS[_rng.randi_range(0,PARTICLE_COLORS.size()-1)],
		})
	advance_visual(0.025) # The totem appears in the very same frame as the save.

func _process(delta:float) -> void:
	if get_tree().paused: return
	advance_visual(delta)

func yaw_turns(time:float) -> float:
	# Integrate a fast, decaying angular velocity plus a nonzero cruising speed.
	# Subtract the initial exponential impulse so speed starts at ZERO at the
	# end of the launch: no one-frame jerk where the two phases meet.
	var t:float = maxf(time-INTRO_SECONDS,0.0)
	return 1.08*(1.0-exp(-3.1*t))+0.48*t - (1.08*3.1+0.48)*SPIN_RAMP_SECONDS*(1.0-exp(-t/SPIN_RAMP_SECONDS))

func advance_visual(delta:float) -> void:
	# Keep the detached effect at the living Evoker's position. Once its owner
	# leaves the tree, hold the last location so the item and falling sparks can finish.
	if _follow != null:
		var owner:Node2D = _follow.get_ref() as Node2D
		if is_instance_valid(owner) and owner.is_inside_tree(): global_position = owner.global_position
	age += maxf(delta,0.0)
	if age >= LIFETIME + PARTICLE_TAIL:
		queue_free()
		return
	var progress:float = clampf(age/LIFETIME,0.0,1.0)
	var pop:float = 1.0-pow(1.0-clampf(age/INTRO_SECONDS,0.0,1.0),3.0)
	var spin_time:float = maxf(age-INTRO_SECONDS,0.0)
	var wobble_ramp:float = smoothstep(0.0,WOBBLE_RAMP_SECONDS,spin_time)
	# Ease into a slow continuous sway rather than snapping from launch to shake.
	totem_sprite.position = item_position(age)
	totem_sprite.visible = age < LIFETIME
	# A front-to-back yaw about the item's VERTICAL axis, projected into 2D:
	# cosine foreshortens the face at the edge; the negative half shows its
	# mirrored back. Do not rotate the flat icon in the screen plane.
	var yaw:float = TAU*yaw_turns(age)
	var facing:float = cos(yaw)
	if absf(facing) < 0.06: facing = 0.06 if facing >= 0.0 else -0.06
	var size:float = (ICON_WIDTH/float(ITEM.get_width())) * (0.12+0.88*pop)
	totem_sprite.scale = Vector2(size*facing,size)
	totem_sprite.rotation = sin(spin_time*9.0)*0.09*wobble_ramp*(1.0-0.25*progress) # gentle tilt, not the front/back spin
	totem_sprite.modulate.a = 1.0-smoothstep(0.73,1.0,progress)
	for particle:Dictionary in particles:
		var sprite:Sprite2D = particle.sprite
		var elapsed:float = age-float(particle.delay)
		if elapsed < 0.0:
			sprite.visible = false
			continue
		if not particle.started:
			# Capture world space at birth: old sparks must not follow a moving owner.
			particle.started = true
			particle.origin = global_position + item_position(float(particle.delay)) + (particle.offset as Vector2)
			particle.ground_y = global_position.y + 10.0
			var height:float = maxf(float(particle.ground_y)-(particle.origin as Vector2).y,0.0)
			var vy:float = (particle.velocity as Vector2).y
			particle.flight = (-vy+sqrt(vy*vy+2.0*GRAVITY*height))/GRAVITY
			particle.life = float(particle.flight)+GROUND_FADE
		if elapsed >= float(particle.life):
			sprite.visible = false
			continue
		sprite.visible = true
		var phase:float = clampf(elapsed/float(particle.life),0.0,0.9999)
		sprite.texture = MC_FX.END_ROD[mini(int(phase*MC_FX.END_ROD.size()),MC_FX.END_ROD.size()-1)]
		var fall_time:float = minf(elapsed,float(particle.flight))
		sprite.global_position = (particle.origin as Vector2) + (particle.velocity as Vector2)*fall_time + Vector2.DOWN*(0.5*GRAVITY*fall_time*fall_time)
		sprite.global_position.y = minf(sprite.global_position.y,float(particle.ground_y))
		sprite.scale = Vector2.ONE * float(particle.diameter)/float(sprite.texture.get_width()) * (1.0-0.25*phase)
		var color:Color = particle.color
		color.a = 0.96*(1.0-smoothstep(float(particle.flight),float(particle.life),elapsed))
		sprite.modulate = color

func item_position(time:float) -> Vector2:
	var pop:float = 1.0-pow(1.0-clampf(time/INTRO_SECONDS,0.0,1.0),3.0)
	var spin_time:float = maxf(time-INTRO_SECONDS,0.0)
	var ramp:float = smoothstep(0.0,WOBBLE_RAMP_SECONDS,spin_time)
	return Vector2(sin(spin_time*8.0)*3.0*ramp,lerpf(-5.0,-53.0,pop)+sin(spin_time*6.0)*1.4*ramp)
