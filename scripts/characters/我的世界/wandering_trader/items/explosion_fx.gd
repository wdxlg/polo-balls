extends Node2D
## Vanilla explosion look: the explosion emitter spawns "explosion" particles (16-frame
## textures/particle/explosion_N sheet played once over 6-9 ticks, grey tint 0.4-1.0, random
## size) scattered over the blast for a few ticks. Scaled so the cloud covers the damage radius.
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
var frames:Array[Texture2D] = []
var puffs:Array[Dictionary] = []
var _age:float = 0.0
var _end:float = 0.6

static func spawn(context:Node,point:Vector2,radius:float) -> Node2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree:SceneTree = context.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var fx:Node2D = (load("res://scripts/characters/我的世界/wandering_trader/items/explosion_fx.gd") as Script).new()
	fx.name = "WTExplosion"
	fx.frames = CATALOG.explosion_frames()
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_as_relative = false
	fx.z_index = 45
	fx.add_to_group(&"MCWanderingTraderFx")
	fx.add_to_group(&"BattleTransient")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count:int = 14
	for i:int in range(count):
		var delay:float = 0.05*floorf(float(i)/3.0)
		var life:float = rng.randf_range(6.0,9.0)/20.0
		var tint:float = rng.randf_range(0.4,1.0)
		var at:Vector2 = Vector2.ZERO if i == 0 else Vector2(rng.randf() - rng.randf(),rng.randf() - rng.randf())*radius
		fx.puffs.append({"pos": at,"delay": delay,"life": life,"size": radius*rng.randf_range(0.7,1.2),"tint": Color(tint,tint,tint)})
		fx._end = maxf(fx._end,delay + life)
	parent.add_child(fx)
	fx.global_position = point
	return fx

func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	_age += delta
	queue_redraw()
	if _age >= _end: queue_free()

func _draw() -> void:
	if frames.is_empty(): return
	for p:Dictionary in puffs:
		var t:float = _age - float(p.delay)
		if t < 0.0 or t >= float(p.life): continue
		var index:int = clampi(int(t/float(p.life)*16.0),0,15)
		var s:float = float(p.size)
		draw_texture_rect(frames[index],Rect2((p.pos as Vector2) - Vector2(s,s)*0.5,Vector2(s,s)),false,p.tint)
