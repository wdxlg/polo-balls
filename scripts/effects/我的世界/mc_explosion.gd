extends Node2D
## Reusable visuals + optional original sound. Does not deal damage or change teams.
const FRAMES=preload("res://scenes/effects/我的世界/MC爆炸粒子帧.tres")
const SMOKE=preload("res://scenes/effects/我的世界/MC通用粒子帧.tres")
const AUDIO=preload("res://scripts/characters/我的世界/new5/audio.gd")
@export var radius:float=55.0
@export var play_audio:bool=true
@export var volume_db:float=-2.0
@export var allow_outside:bool=false
@export var visual_seed:int=0
@export var explosion_count:int=0
@export var smoke_count:int=0
var particles:Array[Dictionary]=[]
var _age:float=0.0
var _rng:=RandomNumberGenerator.new()
static func runtime_container(context:Node) -> Node2D:
	var world:Node=context.get_tree().current_scene
	var container:Node2D=world.get_node_or_null("MCLocalEffects") as Node2D
	if container==null:
		container=Node2D.new()
		container.name="MCLocalEffects"
		world.add_child(container)
	return container
static func spawn(context:Node,point:Vector2,reach:float=55.0,options:Dictionary={}) -> Node2D:
	var effect:Node2D=load("res://scenes/effects/我的世界/MC爆炸.tscn").instantiate()
	effect.radius=reach
	effect.play_audio=bool(options.get("sound",true))
	effect.volume_db=float(options.get("volume_db",-2.0))
	effect.allow_outside=bool(options.get("allow_outside",false))
	effect.visual_seed=int(options.get("seed",0))
	effect.explosion_count=maxi(int(options.get("explosion_count",0)),0)
	effect.smoke_count=maxi(int(options.get("smoke_count",0)),0)
	effect.position=point
	runtime_container(context).add_child(effect)
	return effect
func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MCExplosion")
	z_as_relative=false
	z_index=102 if allow_outside else 85
	if visual_seed==0: _rng.randomize()
	else: _rng.seed=visual_seed
	radius=clampf(radius,4.0,500.0)
	var bursts:int=explosion_count if explosion_count>0 else clampi(int(8+radius*0.12),8,40)
	var smokes:int=smoke_count if smoke_count>0 else clampi(int(18+radius*0.5),20,110)
	for i:int in range(bursts): _make_particle(false,i==0)
	for i:int in range(smokes): _make_particle(true,false)
	if play_audio: AUDIO.play(self,"entity.generic.explode",global_position,volume_db)
func _make_particle(smoke:bool,central:bool) -> void:
	var angle:float=_rng.randf_range(0,TAU)
	var disk:Vector2=Vector2.RIGHT.rotated(angle)*sqrt(_rng.randf())*radius*(0.15 if smoke else 0.78)
	if central: disk=Vector2.ZERO
	var shade:float=_rng.randf_range(0.0,1.0) if smoke else _rng.randf_range(0.16,1.0)
	var diameter:float=radius*_rng.randf_range(0.07,0.17) if smoke else radius*_rng.randf_range(0.60,1.02)
	var speed:float=_rng.randf_range(75,190)*sqrt(radius/55.0)
	var sprite:=Sprite2D.new()
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture=SMOKE.get_frame_texture(&"smoke",0) if smoke else FRAMES.get_frame_texture(&"explode",0)
	sprite.modulate=Color(shade,shade,shade,1.0)
	sprite.visible=false
	add_child(sprite)
	particles.append({"sprite":sprite,"smoke":smoke,"position3":Vector3(disk.x,_rng.randf_range(0,1.5) if smoke else 0.0,disk.y),"velocity3":Vector3(cos(angle)*speed,_rng.randf_range(30,68),sin(angle)*speed) if smoke else Vector3.ZERO,"diameter":diameter,"delay":_rng.randf_range(0.0,0.045 if smoke else 0.16),"life":_rng.randf_range(0.80,1.25) if smoke else _rng.randf_range(0.48,0.72),"end_shade":_rng.randf_range(0,0.45),"start_shade":shade})
func _process(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	var world:Node=get_tree().current_scene
	if world!=null and world.has_method("is_combat_runtime_active") and not world.is_combat_runtime_active(): return
	advance_visual(delta)
func advance_visual(delta:float) -> void:
	_age+=maxf(delta,0)
	var alive:bool=false
	for particle:Dictionary in particles:
		var sprite:Sprite2D=particle.sprite
		var age:float=_age-float(particle.delay)
		if age<0: alive=true; continue
		if age>=float(particle.life): sprite.visible=false; continue
		alive=true
		sprite.visible=true
		var progress:float=clampf(age/float(particle.life),0,0.99999)
		var smoke:bool=particle.smoke
		var position3:Vector3=particle.position3
		if smoke:
			var velocity3:Vector3=particle.velocity3
			position3+=velocity3*delta
			velocity3.x*=exp(-delta*1.6)
			velocity3.z*=exp(-delta*1.6)
			velocity3.y-=300.0*delta
			if position3.y<0:
				position3.y=0
				velocity3.y=absf(velocity3.y)*0.22
			particle.position3=position3
			particle.velocity3=velocity3
		# X/Z ground plane + independent height. Front/back depth changes size
		# and sorting; gravity gives each ejected puff a visible 3D arc.
		sprite.position=Vector2(position3.x,position3.z*(0.56 if smoke else 1.0)-position3.y)
		var frames:SpriteFrames=SMOKE if smoke else FRAMES
		var clip:StringName=&"smoke" if smoke else &"explode"
		var index:int=mini(int(progress*frames.get_frame_count(clip)),frames.get_frame_count(clip)-1)
		sprite.texture=frames.get_frame_texture(clip,index)
		var depth:float=clampf(1.0+position3.z/350.0,0.65,1.35) if smoke else 1.0
		sprite.scale=Vector2.ONE*float(particle.diameter)/sprite.texture.get_width()*depth
		# Remain opaque. The supplied frame animations shrink/disintegrate naturally.
		var shade:float=lerpf(float(particle.start_shade),float(particle.end_shade),progress*0.45) if smoke else float(particle.start_shade)
		sprite.modulate=Color(shade,shade,shade,1.0)
		sprite.z_index=clampi(int(position3.z*0.05),-4,4)
	if not alive: queue_free()
