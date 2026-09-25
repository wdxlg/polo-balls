extends Node2D
## Minecraft's actual totem item + glitter_7..0 totem particle atlas. Visual only.
const ITEM:Texture2D = preload("res://Images/characters/我的世界/唤魔者/totem_of_undying.png")
const MC_FX = preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
const PARTICLE_COUNT:int = 88
const LIFETIME:float = 1.55
const ICON_WIDTH:float = 20.0 # Near the native 16px item size; the old 72px icon obscured the Evoker.
const INTRO_SECONDS:float = 0.19 # Pop out of the Evoker before the fast front/back spin.
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
			"origin":Vector2(_rng.randf_range(-13.0,13.0),_rng.randf_range(-22.0,10.0)),
			"velocity":Vector2(_rng.randf_range(-105.0,105.0),_rng.randf_range(-170.0,-52.0)),
			"delay":_rng.randf_range(0.0,0.17),
			"life":_rng.randf_range(0.65,1.12),
			"diameter":_rng.randf_range(2.8,5.0),
			"color":PARTICLE_COLORS[_rng.randi_range(0,PARTICLE_COLORS.size()-1)],
		})
	advance_visual(0.025) # The totem appears in the very same frame as the save.

func _process(delta:float) -> void:
	if get_tree().paused: return
	advance_visual(delta)

func yaw_turns(time:float) -> float:
	# Integrate a rapidly decaying angular velocity plus a nonzero cruising
	# speed: the card keeps rotating right up to its last visible frame.
	var t:float = maxf(time-INTRO_SECONDS,0.0)
	return 0.95*(1.0-exp(-3.1*t))+0.42*t

func advance_visual(delta:float) -> void:
	# Keep the detached effect at the living Evoker's position. Once its owner
	# leaves the tree, hold the last location so the brief burst can finish.
	if _follow != null:
		var owner:Node2D = _follow.get_ref() as Node2D
		if is_instance_valid(owner) and owner.is_inside_tree(): global_position = owner.global_position
	age += maxf(delta,0.0)
	if age >= LIFETIME:
		queue_free()
		return
	var progress:float = clampf(age/LIFETIME,0.0,1.0)
	var pop:float = 1.0-pow(1.0-clampf(age/INTRO_SECONDS,0.0,1.0),3.0)
	var spin_time:float = maxf(age-INTRO_SECONDS,0.0)
	# Launch from the body, then hover by its head and visibly sway in place.
	totem_sprite.position = Vector2(sin(spin_time*16.0)*2.5,lerpf(-5.0,-53.0,pop)+sin(spin_time*10.0)*1.3)
	# A front-to-back yaw about the item's VERTICAL axis, projected into 2D:
	# cosine foreshortens the face at the edge; the negative half shows its
	# mirrored back. Do not rotate the flat icon in the screen plane.
	var yaw:float = TAU*yaw_turns(age)
	var facing:float = cos(yaw)
	if absf(facing) < 0.06: facing = 0.06 if facing >= 0.0 else -0.06
	var size:float = (ICON_WIDTH/float(ITEM.get_width())) * (0.12+0.88*pop)
	totem_sprite.scale = Vector2(size*facing,size)
	totem_sprite.rotation = sin(spin_time*18.0)*0.075*(1.0-0.35*progress) # small wobble, not the front/back spin
	totem_sprite.modulate.a = 1.0-smoothstep(0.73,1.0,progress)
	for particle:Dictionary in particles:
		var sprite:Sprite2D = particle.sprite
		var elapsed:float = age-float(particle.delay)
		if elapsed < 0.0 or elapsed >= float(particle.life):
			sprite.visible = false
			continue
		sprite.visible = true
		var phase:float = clampf(elapsed/float(particle.life),0.0,0.9999)
		sprite.texture = MC_FX.END_ROD[mini(int(phase*MC_FX.END_ROD.size()),MC_FX.END_ROD.size()-1)]
		sprite.position = (particle.origin as Vector2) + (particle.velocity as Vector2)*elapsed + Vector2.DOWN*82.0*elapsed*elapsed
		sprite.scale = Vector2.ONE * float(particle.diameter)/float(sprite.texture.get_width()) * (1.0-0.25*phase)
		var color:Color = particle.color
		color.a = 0.96*(1.0-smoothstep(0.66,1.0,phase))
		sprite.modulate = color
