extends Node2D
## Original slimeball texture chips; purely visual, no damage/slow/collision.
const TEX=preload("res://Images/characters/我的世界/new5/slimeball.png")
const CONTAINER=preload("res://scripts/effects/我的世界/mc_explosion.gd")
var landing:bool=false
var size_factor:float=1.0
var reach:float=43.0
var visual_seed:int=1
var linger_after_death:bool=false
var particles:Array[Dictionary]=[]
var age:float=0.0
var ring:Line2D
var ring_radius:float=0.0
var owner_ref:WeakRef
var body_z:int=0
var _rng:=RandomNumberGenerator.new()
static func spawn(context:Node,point:Vector2,is_landing:bool,factor:float,range_value:float,random_seed:int,death_burst:bool=false) -> Node2D:
	var effect:Node2D=load("res://scripts/characters/我的世界/new5/slime_jump_fx.gd").new()
	effect.position=point
	effect.landing=is_landing
	effect.size_factor=factor
	effect.reach=range_value
	effect.visual_seed=random_seed
	effect.linger_after_death=death_burst
	if context.has_method("ground_point"):
		# Ordinary jump FX belongs to its live owner; the death burst is detached
		# so it survives the actor's removal and finishes its short animation.
		if not death_burst: effect.owner_ref=weakref(context)
		effect.body_z=effective_z(context.image)
	CONTAINER.runtime_container(context).add_child(effect)
	return effect
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	add_to_group("BattleTransient")
	add_to_group("MCSlimeJumpFX")
	_rng.seed=visual_seed
	if landing:
		ring=Line2D.new()
		ring.name="GroundRing"
		ring.z_as_relative=false
		ring.z_index=body_z-1 # ground plane, underneath the actual body layer
		ring.closed=true
		ring.antialiased=true
		ring.width=maxf(1.0,1.8*size_factor)
		ring.default_color=Color(0.32,0.95,0.18,0.72)
		add_child(ring)
	var count:int=maxi(3,roundi((16 if landing else 5)*size_factor))
	for i:int in range(count):
		var angle:float=(float(i)/count*TAU+_rng.randf_range(-0.12,0.12)) if landing else _rng.randf_range(0,TAU)
		var radial:Vector2=Vector2.RIGHT.rotated(angle)
		var offset:Vector2=radial*(9.0*size_factor if landing else _rng.randf_range(2,8)*size_factor)
		var chip:=AtlasTexture.new()
		chip.atlas=TEX
		chip.region=Rect2(_rng.randi_range(5,9),_rng.randi_range(5,9),2,2)
		chip.filter_clip=true
		var sprite:=Sprite2D.new()
		sprite.texture=chip
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_as_relative=false
		var diameter:float=_rng.randf_range(1.6,3.0)*size_factor
		sprite.scale=Vector2.ONE*(diameter/2.0)
		add_child(sprite)
		particles.append({"sprite":sprite,"plane":offset,"velocity":radial*(_rng.randf_range(38,68) if landing else _rng.randf_range(5,18))*size_factor,"height":0.5,"up":_rng.randf_range(24,43) if landing else _rng.randf_range(35,58),"life":_rng.randf_range(0.48,0.70),"spin":_rng.randf_range(-3,3),"grounded":false})
	update_visual(0.0)
func _process(delta:float) -> void:
	if not linger_after_death:
		# Cleanup precedes pause checks: the last death can stop the battle instantly.
		var owner:Node=owner_ref.get_ref() if owner_ref!=null else null
		if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.health<=0 or owner._death_visual_done or owner._split:
			hide()
			queue_free()
			return
		if Game.now_stop_state or get_tree().paused: return
		var world:Node=get_tree().current_scene
		if world!=null and world.has_method("is_combat_runtime_active") and not world.is_combat_runtime_active(): return
	# A fatal blow may stop/pause the match in this same frame. Only the detached
	# death burst continues to its own 0.7-second cleanup, even after victory.
	update_visual(delta)
func update_visual(delta:float) -> void:
	age+=maxf(delta,0)
	if is_instance_valid(ring):
		var t:float=clampf(age/0.5,0,1)
		ring_radius=lerpf(10.0*size_factor,reach,1-pow(1-t,2))
		var points:=PackedVector2Array()
		for i:int in range(72):
			var angle:float=float(i)*TAU/72
			points.append(Vector2(cos(angle)*ring_radius,sin(angle)*ring_radius*0.42))
		ring.points=points
		ring.default_color=Color(0.32,0.95,0.18,0.72*pow(1-t,1.4))
		ring.visible=t<1
	var alive:bool=landing and age<0.5
	for particle:Dictionary in particles:
		var sprite:Sprite2D=particle.sprite
		if age>=float(particle.life): sprite.visible=false; continue
		alive=true
		particle.plane+=particle.velocity*delta
		particle.velocity*=exp(-delta*2.1)
		if not particle.grounded:
			particle.height+=float(particle.up)*delta*size_factor
			particle.up-=210.0*delta
			if float(particle.height)<=0:
				particle.height=0.0
				particle.grounded=true
		sprite.position=Vector2(particle.plane.x,particle.plane.y*0.42-float(particle.height))
		var owner:Node=owner_ref.get_ref() if owner_ref!=null else null
		var foot:Vector2=owner.ground_point() if is_instance_valid(owner) else global_position
		var ground:Vector2=to_global(Vector2(particle.plane.x,particle.plane.y*0.42))
		sprite.z_index=body_z+1 if ground.y>=foot.y else body_z-1
		sprite.rotation+=float(particle.spin)*delta
		# Chips land; only a short final fade clears them. Ring has its own fade.
		sprite.modulate.a=clampf((float(particle.life)-age)/0.14,0,1)
	if not alive: queue_free()

static func effective_z(item:CanvasItem) -> int:
	var result:int=item.z_index
	while item.z_as_relative and item.get_parent() is CanvasItem:
		item=item.get_parent()
		result+=item.z_index
	return result
