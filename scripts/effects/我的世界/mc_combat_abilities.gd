extends RefCounted
## 共享战斗表现入口。只生成本地视觉；施放者仍须用已有 RPC 在各 peer 调用。
## 玩法结算只在权威端连接 impact_started；不要复制雷电/方块粒子的实现。
const LIGHTNING=preload("res://scripts/effects/我的世界/雷电.gd")
const GROUND_IMPACT=preload("res://scripts/effects/我的世界/重锤落地冲击.gd")
const EXPLOSION=preload("res://scripts/effects/我的世界/mc_explosion.gd")
const OBSTACLES=preload("res://scripts/effects/我的世界/ghast_obstacle_damage.gd")

static func lightning(parent:Node,point:Vector2,seed:int,radius:float,warning:float,options:Dictionary = {}) -> Node2D:
	var packed:PackedScene = options.get("scene",null)
	var effect:Node2D
	if packed != null:
		effect = packed.instantiate() as Node2D
	else:
		var script:Script = options.get("script",LIGHTNING)
		if script == null: return null
		effect = script.new() as Node2D
	if effect == null: return null
	effect.name = str(options.get("name","MCLightning"))
	# Variant-specific fields (e.g. trident caster/fixed impact) belong to the effect subclass.
	var fields:Dictionary = options.get("fields",{})
	for key:Variant in fields: effect.set(str(key),fields[key])
	var tuning:Dictionary = options.get("tuning",{})
	for key:Variant in tuning: effect.set(str(key),tuning[key])
	effect.call("setup",point,seed,radius,warning)
	var on_impact:Callable = options.get("on_impact",Callable())
	if on_impact.is_valid(): effect.connect("impact_started",on_impact,CONNECT_ONE_SHOT)
	parent.add_child(effect,true)
	return effect

static func ground_impact(parent:Node,point:Vector2,radius:float,options:Dictionary = {}) -> Node2D:
	var effect:Node2D = GROUND_IMPACT.new()
	effect.name = str(options.get("name","MCGroundImpact"))
	for key:Variant in options:
		if key != "name": effect.set(str(key),options[key])
	parent.add_child(effect,true)
	effect.call("setup",point,radius) # floor sampling is asynchronous; ring appears immediately.
	return effect

static func explosion(context:Node,point:Vector2,radius:float,options:Dictionary = {}) -> Node2D:
	return EXPLOSION.spawn(context,point,radius,options)

static func obstacle_blast(context:Node2D,point:Vector2,radius:float) -> Array[Dictionary]:
	# Authority collects once, caller sends updates by RPC then each peer applies them.
	var manager:Node = OBSTACLES.ensure(context)
	var updates:Array[Dictionary] = []
	updates.assign(manager.call("collect_blast",context,point,radius))
	return updates

static func apply_obstacle_updates(context:Node,updates:Array) -> void:
	OBSTACLES.ensure(context).call("apply_updates",updates)
