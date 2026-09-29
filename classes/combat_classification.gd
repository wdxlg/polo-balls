extends RefCounted
## Shared runtime vocabulary. Entity identity NEVER decides the element of every
## attack a character owns. Each damage event declares its own kind.
const CATALOG = preload("res://classes/combat_classification_catalog.gd")
const ENTITY_KINDS:Array[String] = ["character","combat_entity","subentity","projectile","obstacle","terrain","hazard","status","effect","visual","system","component"]
const DAMAGE_KINDS:Array[String] = ["ordinary","fire","cold","poison","wither","bleed","drowning","magic"]
const ATTACK_MODES:Array[String] = ["melee","ranged","environment","retaliation","self","none"]
const CARRIERS:Array[String] = ["body_contact","weapon_sweep","projectile","ray_beam","area","status_tick","none"]

static func canonical_damage_kind(value:Variant) -> String:
	var kind:String = str(value).strip_edges().to_lower()
	if kind == "physical": return "ordinary"
	return kind if DAMAGE_KINDS.has(kind) else ""

static func declared(node:Node) -> Dictionary:
	if not is_instance_valid(node): return {}
	if node.has_meta("combat_classification"):
		var explicit:Variant = node.get_meta("combat_classification")
		if explicit is Dictionary and ENTITY_KINDS.has(str(explicit.get("entity_kind",""))):
			return _stage_profile(node,explicit)
	var scene_path:String = node.scene_file_path
	var script:Script = node.get_script() as Script
	if CATALOG.SCENES.has(scene_path):
		var scene:Dictionary = CATALOG.SCENES[scene_path]
		# A base scene may be instantiated and assigned a different gameplay script.
		if script == null or str(scene.get("root_script","")) == script.resource_path: return _stage_profile(node,scene)
	while script != null:
		if CATALOG.SCRIPTS.has(script.resource_path): return _stage_profile(node,CATALOG.SCRIPTS[script.resource_path])
		script = script.get_base_script()
	# Engine-created map collision/visual children have no resource script.
	# Unknown scripted gameplay objects deliberately remain unregistered.
	if node.get_script() == null:
		if node is StaticBody2D or node is TileMapLayer: return {"entity_kind":"obstacle","review":"engine_collision"}
		if node is Sprite2D or node is GPUParticles2D or node is CPUParticles2D: return {"entity_kind":"visual","review":"engine_visual"}
		if node is CollisionShape2D or node is CollisionPolygon2D or node is Area2D: return {"entity_kind":"component","review":"engine_collision_component"}
	return {}

static func _stage_profile(node:Node,info:Dictionary) -> Dictionary:
	var field:String = str(info.get("stage_field",""))
	if field.is_empty() or not field in node: return info
	var stages:Dictionary = info.get("stages",{})
	var stage:String = str(node.get(field))
	if not stages.has(stage): return info
	var result:Dictionary = info.duplicate()
	result.merge(stages[stage],true)
	return result

static func is_projectile(node:Node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return false
	var info:Dictionary = declared(node)
	var kind:String = str(info.get("entity_kind",""))
	# Phase declarations outrank old groups, Type values and return-shot tags.
	if info.has("stage_field") and kind != "projectile": return false
	if node.is_in_group("AllayExtendedProjectile"): return true
	if kind == "projectile": return true
	# Ground webs, walls, statuses and pure visuals are not flying objects.
	if kind in ["obstacle","terrain","hazard","status","visual","system","component"]: return false
	if node.is_in_group("Shooter"): return true
	# Base ball is also instantiated dynamically and then given a legacy Type.
	if "Type" in node and int(node.get("Type")) in [1,2]: return true
	# Compatibility for unregistered external descendants; no path/name guesses.
	return kind.is_empty() and "flight_velocity" in node

static func profile_of(node:Node) -> Dictionary:
	if not is_instance_valid(node): return {"entity_kind":"unregistered","registered":false}
	var result:Dictionary = declared(node).duplicate(true)
	result["registered"] = not result.is_empty()
	var kind:String = str(result.get("entity_kind","unregistered"))
	if is_projectile(node):
		kind = "projectile"
	elif kind == "combat_entity" and "Type" in node:
		kind = "subentity" if int(node.get("Type")) == 3 else "character"
	result["entity_kind"] = kind
	result["is_projectile"] = kind == "projectile"
	result["is_obstacle"] = kind == "obstacle" or node is StaticBody2D or node is TileMapLayer
	result["attack_modes"] = result.get("attack_modes",[])
	result["carriers"] = result.get("carriers",[])
	result["damage_kinds"] = result.get("damage_kinds",[])
	# Runtime methods remain authoritative; classification does not silently
	# enable control, targetability, friendly fire or destructibility.
	return result

static func context_kind(space:Variant) -> String:
	if not space is Dictionary: return ""
	if space.has("damage_kind"):
		var kind:String = canonical_damage_kind(space["damage_kind"])
		var element:String = canonical_damage_kind(space.get("element",""))
		if not element.is_empty() and kind != element: return ""
		return kind
	return canonical_damage_kind(space.get("element",""))

static func legacy_element(kind:String) -> String:
	return "physical" if kind == "ordinary" else kind
