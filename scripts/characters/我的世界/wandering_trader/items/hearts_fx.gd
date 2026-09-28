extends Node2D
## Vanilla HEART particles (animal breeding / healing look): a few hearts rise slowly and fade.
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
var hearts:Array[Dictionary] = []
var _age:float = 0.0

static func spawn(context:Node,point:Vector2,count:int = 4) -> Node2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree:SceneTree = context.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var fx:Node2D = (load("res://scripts/characters/我的世界/wandering_trader/items/hearts_fx.gd") as Script).new()
	fx.name = "WTHearts"
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_as_relative = false
	fx.z_index = 55
	fx.add_to_group(&"MCWanderingTraderFx")
	fx.add_to_group(&"BattleTransient")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i:int in range(count):
		fx.hearts.append({"pos": Vector2(rng.randf_range(-7,7),rng.randf_range(-3,3)),"delay": i*0.08,"rise": rng.randf_range(10.0,16.0)})
	parent.add_child(fx)
	fx.global_position = point
	return fx

func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	_age += delta
	queue_redraw()
	if _age > 1.2: queue_free()

func _draw() -> void:
	for h:Dictionary in hearts:
		var t:float = (_age - float(h.delay))/0.8
		if t < 0.0 or t > 1.0: continue
		var c := Color(1,1,1,1.0 if t < 0.6 else 1.0 - (t - 0.6)/0.4)
		var at:Vector2 = (h.pos as Vector2) + Vector2(0,-float(h.rise)*t)
		draw_texture_rect(CATALOG.TEX_HEART,Rect2(at - Vector2(3.5,3.5),Vector2(7,7)),false,c)
