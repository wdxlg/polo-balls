extends Node2D
## Forward slimeball chips; visual only, no collision or damage.
const TEX=preload("res://Images/characters/我的世界/new5/slimeball.png")
const CONTAINER=preload("res://scripts/effects/我的世界/mc_explosion.gd")
var source_ref:WeakRef
var facing:Vector2=Vector2.RIGHT
var visual_seed:int=1
var age:float=0.0
var particles:Array[Dictionary]=[]
static func spawn(context:Node,point:Vector2,heading:Vector2,random_seed:int) -> Node2D:
	var effect:Node2D=load("res://scripts/characters/我的世界/new5/piston_slime_fx.gd").new()
	effect.source_ref=weakref(context)
	effect.facing=heading.normalized() if heading.length_squared()>0.001 else Vector2.RIGHT
	effect.visual_seed=random_seed
	CONTAINER.runtime_container(context).add_child(effect)
	effect.global_position=point
	return effect
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	add_to_group("BattleTransient")
	add_to_group("MCPistonSlimeFX")
	z_as_relative=false
	z_index=7
	var rng:=RandomNumberGenerator.new()
	rng.seed=visual_seed
	for i:int in range(10):
		var chip:=AtlasTexture.new()
		chip.atlas=TEX
		chip.region=Rect2(rng.randi_range(5,9),rng.randi_range(5,9),2,2)
		chip.filter_clip=true
		var sprite:=Sprite2D.new()
		sprite.texture=chip
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position=facing.orthogonal()*rng.randf_range(-5.0,5.0)
		sprite.scale=Vector2.ONE*rng.randf_range(1.4,2.5)
		add_child(sprite)
		particles.append({"sprite":sprite,"velocity":facing.rotated(rng.randf_range(-0.32,0.32))*rng.randf_range(90.0,155.0),"life":rng.randf_range(0.32,0.48),"spin":rng.randf_range(-4.0,4.0)})
func _process(delta:float) -> void:
	var source:Node=source_ref.get_ref() if source_ref!=null else null
	if not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion() or source.health<=0:
		hide()
		queue_free()
		return
	if Game.now_stop_state or get_tree().paused or not source.is_combat_runtime_active(): return
	update_visual(delta)
func update_visual(delta:float) -> void:
	age+=maxf(delta,0.0)
	var alive:bool=false
	for particle:Dictionary in particles:
		var sprite:Sprite2D=particle.sprite
		var progress:float=clampf(age/float(particle.life),0.0,1.0)
		sprite.visible=progress<1.0
		if not sprite.visible: continue
		alive=true
		sprite.position+=particle.velocity*delta
		particle.velocity*=exp(-delta*2.3)
		sprite.rotation+=float(particle.spin)*delta
		sprite.modulate.a=pow(1.0-progress,1.3)
	if not alive: queue_free()
