extends Node2D
## 火药冒烟 (user rule 2026-09-29): a placed gunpowder pile gives off a light trickle of smoke
## puffs (vanilla generic_7 -> generic_0 poof frames) going from white to off-white grey; once it
## is triggered the smoke pours out and each puff goes from white to black. Pure visual, run on
## every peer. The emitter sits at the world origin in the battle scene, so puffs already out keep
## drifting and fading after the pile explodes (release()).
const FRAMES = [
	preload("res://Images/effects/我的世界/通用粒子/generic_7.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_6.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_5.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_4.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_3.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_2.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_1.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_0.png"),
]
const IDLE_RATE:float = 3.5 # puffs per second while it lies there
const IDLE_END:float = 0.72 # white -> off-white grey
const LIT_RATE:float = 110.0 # puffs per second once triggered
const LIT_END:float = 0.08 # white -> black
var puffs:Array[Dictionary] = []
var source:Vector2 = Vector2.ZERO # world point of the pile
var lit:bool = false
var emitting:bool = true
var emitted:int = 0
var _acc:float = 0.0
var _rng := RandomNumberGenerator.new()

static func attach(context:Node,point:Vector2) -> Node2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tree:SceneTree = context.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var fx:Node2D = (load("res://scripts/characters/我的世界/wandering_trader/items/gunpowder_smoke.gd") as Script).new()
	fx.name = "WTGunpowderSmoke"
	fx.source = point
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_as_relative = false
	fx.z_index = 3 # just above the pile (placed items are absolute 2)
	fx.add_to_group(&"MCWanderingTraderFx")
	fx.add_to_group(&"BattleTransient")
	fx._rng.randomize()
	parent.add_child(fx)
	fx.global_position = Vector2.ZERO
	return fx

func ignite() -> void:
	if lit: return
	lit = true
	_acc = 8.0 # an immediate gush

## The pile is gone: stop emitting, let the last puffs finish.
func release() -> void:
	emitting = false

func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	if emitting:
		_acc += (LIT_RATE if lit else IDLE_RATE)*delta
		while _acc >= 1.0:
			_acc -= 1.0
			_emit()
	for i:int in range(puffs.size() - 1,-1,-1):
		var p:Dictionary = puffs[i]
		p.age = float(p.age) + delta
		if float(p.age) >= float(p.life):
			puffs.remove_at(i)
			continue
		p.pos = (p.pos as Vector2) + (p.vel as Vector2)*delta
		p.vel = (p.vel as Vector2)*pow(0.25,delta) + Vector2(0.0,-p.rise*delta) # slows down, keeps rising
	queue_redraw()
	if not emitting and puffs.is_empty(): queue_free()

func _emit() -> void:
	var angle:float = _rng.randf_range(-PI,PI)
	var spread:float = 30.0 if lit else 6.0
	puffs.append({
		"pos": source + Vector2(_rng.randf_range(-3.0,3.0),_rng.randf_range(-2.0,1.0)),
		"vel": Vector2.from_angle(angle)*_rng.randf_range(0.3,1.0)*spread + Vector2(0.0,-_rng.randf_range(8.0,16.0) if not lit else -_rng.randf_range(20.0,45.0)),
		"rise": _rng.randf_range(4.0,10.0) if not lit else _rng.randf_range(10.0,24.0),
		"age": 0.0,
		"life": _rng.randf_range(0.9,1.5) if not lit else _rng.randf_range(0.5,0.9),
		"size": _rng.randf_range(3.2,4.4) if not lit else _rng.randf_range(4.5,6.5), # small random range
		"rot": _rng.randf_range(-PI,PI), # random angle
		"alpha": 0.55 if not lit else 0.85,
		"end": _rng.randf_range(IDLE_END - 0.06,IDLE_END + 0.06) if not lit else _rng.randf_range(LIT_END - 0.05,LIT_END + 0.08),
	})
	emitted += 1

func _draw() -> void:
	for p:Dictionary in puffs:
		var k:float = clampf(float(p.age)/float(p.life),0.0,1.0)
		var tex:Texture2D = FRAMES[mini(int(k*FRAMES.size()),FRAMES.size() - 1)]
		var shade:float = lerpf(1.0,float(p.end),smoothstep(0.0,0.8,k))
		var alpha:float = float(p.alpha)*(1.0 - smoothstep(0.7,1.0,k))
		var s:float = float(p.size)*(1.0 + 0.35*k)
		draw_set_transform(p.pos,float(p.rot),Vector2.ONE)
		draw_texture_rect(tex,Rect2(-s*0.5,-s*0.5,s,s),false,Color(shade,shade,shade,alpha))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
