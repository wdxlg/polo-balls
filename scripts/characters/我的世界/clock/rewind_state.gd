extends RefCounted
## 时钟倒流快照：血量、护盾、朝向速度、身上的状态（原版药水与通用状态节点）和 Buff。
const MC = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const CLEANSE = preload("res://classes/status_cleansing.gd")
const CLASSIFICATION = preload("res://classes/combat_classification.gd")
const TIMER_PROPS:Array[String] = ["remaining","time_left","duration_left","elapsed","age","left","timer","tick_left","stacks","stack","layers","absorption_remaining"]


static func capture(target:Node,t:float) -> Dictionary:
	var statuses:Array[Dictionary] = []
	for node:Node in status_nodes(target):
		var mc:bool = _is_mc(node)
		var props:Dictionary = {}
		for key:String in TIMER_PROPS:
			if key in node:
				var v:Variant = node.get(key)
				if v is float or v is int: props[key] = v
		var src:Variant = node.get("source") if "source" in node else null
		var apps:Variant = node.get("applications") if "applications" in node else null
		statuses.append({
			"node":weakref(node),
			"id":node.get_instance_id(),
			"mc":mc,
			"kind":str(node.get("effect_type")) if mc and "effect_type" in node else "",
			"level":int(node.get("level")) if "level" in node else 1,
			"source":weakref(src) if src is Object and is_instance_valid(src) else null,
			"apps":(apps as Dictionary).duplicate(true) if apps is Dictionary else null,
			"props":props,
		})
	return {
		"t":t,
		"hp":int(target.health),
		"block":target.get("block"),
		"direction":target.direction,
		"velocity":target.velocity,
		"statuses":statuses,
		"buffs":copy_buffs(target.Buff_Dic),
	}


static func restore(target:Node,snap:Dictionary) -> void:
	var wanted:Dictionary = {}
	for e:Dictionary in snap.statuses: wanted[int(e.id)] = e
	# 1) 这一秒里新得到的状态全部撤销。
	for node:Node in status_nodes(target):
		if not wanted.has(node.get_instance_id()): _drop(target,node)
	# 2) 当时就有的状态：还在的回拨计时，已结束的重新挂上。
	for e:Dictionary in snap.statuses:
		var node:Node = (e.node as WeakRef).get_ref() as Node
		var alive:bool = is_instance_valid(node) and not node.is_queued_for_deletion() and node.is_inside_tree()
		if bool(e.mc) and not alive:
			if str(e.kind) == "" or str(e.kind) == "levitation": continue
			var src:Object = (e.source as WeakRef).get_ref() if e.source != null else null
			var remaining:float = float(e.props.get("remaining",1.0))
			if is_inf(remaining): remaining = 3600.0
			MC.apply_effect(target,str(e.kind),maxi(int(e.level),1),maxf(remaining,0.05),src as Node)
			node = MC.current(target,str(e.kind))
			alive = is_instance_valid(node)
		if not alive: continue
		if "level" in node: node.set("level",int(e.level))
		if e.apps is Dictionary and "applications" in node: node.set("applications",(e.apps as Dictionary).duplicate(true))
		for key:Variant in e.props: node.set(key,e.props[key])
	target.Buff_Dic = copy_buffs(snap.buffs)
	if snap.block != null and "block" in target: target.set("block",snap.block)
	target.direction = snap.direction
	target.velocity = snap.velocity
	var world:Node = target.get_tree().current_scene if target.is_inside_tree() else null
	if is_instance_valid(world) and world.has_method("refresh_runtime_buffs"): world.call("refresh_runtime_buffs",target)
	var tooltip:Node = target.get_node_or_null("Minecraft药水状态框")
	if tooltip != null and tooltip.has_method("refresh_display"): tooltip.call("refresh_display")


static func status_nodes(target:Node) -> Array[Node]:
	var out:Array[Node] = []
	for child:Node in target.get_children():
		if child.is_queued_for_deletion() or child.has_method("cleanse_negative_effects"): continue
		if _is_mc(child) or CLEANSE.polarity(child) != 0: out.append(child)
	for ref:WeakRef in target._status_effect_registrations.values():
		var effect:Node = ref.get_ref() as Node
		if not is_instance_valid(effect) or effect.is_queued_for_deletion() or out.has(effect): continue
		if "target" in effect and effect.get("target") != target: continue
		if CLEANSE.polarity(effect) != 0: out.append(effect)
	return out


static func copy_buffs(source:Dictionary) -> Dictionary:
	var out:Dictionary = {}
	for from:Variant in source:
		var group:Dictionary = {}
		for key:Variant in source[from]:
			var b:Buff = source[from][key] as Buff
			if b == null: continue
			var amount:Variant = b.amount
			if amount is Array or amount is Dictionary: amount = amount.duplicate(true)
			var c := Buff.new(b.index,b.duration,b.buff_type,amount,b.algorithm)
			c.effect_polarity = b.effect_polarity
			group[key] = c
		out[from] = group
	return out


static func _is_mc(node:Node) -> bool:
	return node.name == &"WitherStatus" or String(node.name).begins_with("MinecraftStatus_")


static func _drop(target:Node,node:Node) -> void:
	if _is_mc(node) and "effect_type" in node:
		MC.clear(target,str(node.get("effect_type")))
		if not is_instance_valid(node) or node.is_queued_for_deletion(): return
	var profile:Dictionary = CLASSIFICATION.declared(node)
	var cleanup:String = str(profile.get("status_cleanup","detach"))
	if node.has_method("cleanse_status_effect"): cleanup = "cleanse_status_effect"
	node.set_process(false)
	node.set_physics_process(false)
	if cleanup != "detach" and node.has_method(cleanup): node.call(cleanup)
	if not is_instance_valid(node): return
	if node.get_parent() != null: node.get_parent().remove_child(node)
	if not node.is_queued_for_deletion(): node.queue_free()
