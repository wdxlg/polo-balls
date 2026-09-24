extends Node
## Opt-in enchantment component. Effects are resolved by mc_enchantment_effects.gd.
## Add this as a child of an object and edit `enchantments` in the Inspector, or call apply().
## Sprite2D, AnimatedSprite2D, Polygon2D, TextureRect, and ColorRect are masked individually.
const CATALOG = preload("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")
const EFFECTS = preload("res://scripts/effects/我的世界/mc_enchantment_effects.gd")
const SHADER = preload("res://scripts/effects/我的世界/mc_enchantment_glint.gdshader")
const NATIVE_GLINT = preload("res://Images/characters/我的世界/native_frames/trident_masks/enchanted_item_glint.png")
const NODE_NAME:String = "MinecraftEnchantments"
const GLINT_NAME:String = "MCEnchantGlint"
const MAX_LEVEL:int = 32767
@export var enchantments:Dictionary = {} # minecraft ID -> 1..32767 (no vanilla item restrictions)
var _slots:Dictionary = {} # visual instance id -> weak source / overlay
var _clock:float = 0.0
var _rescan_left:float = 0.0
var _combat_actor:Node = null

static func ensure(target:Node) -> Node:
	if not is_instance_valid(target) or target.is_queued_for_deletion(): return null
	var existing:Node = _component(target)
	if existing != null: return existing
	var component:Node = load("res://scripts/effects/我的世界/mc_enchantments.gd").new()
	component.name = NODE_NAME if not target.has_node(NODE_NAME) else NODE_NAME+"2"
	target.add_child(component)
	return component

static func _component(target:Node) -> Node:
	if not is_instance_valid(target): return null
	var script:Script = load("res://scripts/effects/我的世界/mc_enchantments.gd")
	for child:Node in target.get_children():
		if child.get_script() == script and not child.is_queued_for_deletion(): return child
	return null

static func apply(target:Node,kind:String,level:int = 1) -> bool:
	if not CATALOG.has_id(kind) or level <= 0 or level > MAX_LEVEL: return false
	var component:Node = ensure(target)
	return component != null and bool(component.call("set_level",kind,level))

static func remove(target:Node,kind:String) -> void:
	var component:Node = _component(target)
	if component != null and component.has_method("remove_level"): component.call("remove_level",kind)

static func levels_of(target:Node) -> Dictionary:
	var component:Node = _component(target)
	return component.enchantments.duplicate() if component != null else {}

## For systems that already own an event (mining, fishing, shooting, equipment,
## XP, mobility, elemental damage). Returned values are deterministic and
## side-effect-free; the authoritative caller applies them exactly once.
static func resolve_event(target:Node,event:String,context:Dictionary = {}) -> Dictionary:
	var values:Dictionary = levels_of(target)
	if is_instance_valid(target) and target.has_meta("mc_enchant_components"):
		for weak:Variant in target.get_meta("mc_enchant_components",[]):
			var component:Node = weak.get_ref() if weak is WeakRef else null
			if not is_instance_valid(component) or component.is_queued_for_deletion(): continue
			for id:String in component.enchantments:
				values[id] = maxi(int(values.get(id,0)),int(component.enchantments[id]))
	return EFFECTS.resolve(values,event,context)

static func preview_entries(target:Node) -> Array[MCPreviewEnchantment]:
	## May be given to an existing mc_effect_tooltip, without changing test-armour-stand UI.
	var result:Array[MCPreviewEnchantment] = []
	var values:Dictionary = levels_of(target)
	for id:String in CATALOG.all_ids():
		if not values.has(id): continue
		var row := MCPreviewEnchantment.new()
		row.enchantment_name = CATALOG.display_name(id)
		row.english_name = CATALOG.display_name(id,true)
		row.level = int(values[id])
		if row.level > 3999: row.level_text_override = str(row.level)
		result.append(row)
	return result

func _ready() -> void:
	var valid:Dictionary = {}
	for raw:Variant in enchantments:
		var id:String = CATALOG.canonical(str(raw))
		if CATALOG.has_id(id) and enchantments[raw] is int and int(enchantments[raw]) > 0 and int(enchantments[raw]) <= MAX_LEVEL: valid[id] = enchantments[raw]
	enchantments = valid
	_bind_combat_signals()
	_reconcile()
	set_process(not enchantments.is_empty())

func _bind_combat_signals() -> void:
	var node:Node = get_parent()
	while node != null and not (node is ball): node = node.get_parent()
	if node == null: return
	_combat_actor = node
	var refs:Array = node.get_meta("mc_enchant_components",[])
	refs.append(weakref(self))
	node.set_meta("mc_enchant_components",refs)
	var hit:Node = node.get_node_or_null("hitbox")
	var hurt:Node = node.get_node_or_null("hurtbox")
	if hit is hitbox and not hit.on_hit.is_connected(_on_combat_hit): hit.on_hit.connect(_on_combat_hit)
	if hurt is hurtbox and not hurt.on_hurt.is_connected(_on_combat_hurt): hurt.on_hurt.connect(_on_combat_hurt)

func _on_combat_hit(hurt:hurtbox) -> void:
	var actor:ball = _combat_actor as ball
	var target:ball = hurt.get_parent() as ball if is_instance_valid(hurt) else null
	if actor == null or target == null or target == actor or target.health <= 0 or not actor.is_multiplayer_authority(): return
	if not actor.is_combat_runtime_active(): return
	# Hitbox has already performed normal friendly-fire/avoidance validation.
	var base:float = actor.attack_damage()
	if base <= 0.0: return
	var mode:String = "ranged" if actor._is_ranged_hit_source(actor) else "melee"
	var tags:Array = []
	var family:String = str(target.get_meta("mc_creature_family",""))
	if not family.is_empty(): tags.append(family)
	var proc:Dictionary = EFFECTS.resolve(enchantments,"on_hit",{"mode":mode,"target_tags":tags})
	var dist:float = float(proc.get("knockback_distance",0.0))
	if dist > 0.0:
		var direction:Vector2 = (target.global_position-actor.global_position).normalized()
		if direction != Vector2.ZERO: target.apply_knockback(direction,dist,420.0,0.0,0.0,{"source":actor})
	var burn:float = float(proc.get("burn_seconds",0.0))
	if burn > 0.0 and target.can_receive_fire_status():
		var status:Node = target.get_node_or_null("MinecraftBlazeBurn")
		if status != null and status.has_method("refresh"): status.call("refresh",actor,burn,float(proc.get("burn_damage",0.0)))
		else:
			status = load("res://scripts/status/战争女神_灼烧.gd").new()
			status.name = "MinecraftBlazeBurn"
			target.add_child(status,true)
			status.call("setup",target,actor,burn,0.55,float(proc.get("burn_damage",0.0)))
	var stun:float = float(proc.get("stun_seconds",0.0))
	if stun > 0.0: target.apply_stun(stun,actor)

func _on_combat_hurt(hit:hitbox) -> void:
	var owner_ball:ball = _combat_actor as ball
	var attacker:ball = hit.get_parent() as ball if is_instance_valid(hit) else null
	if owner_ball == null or attacker == null or owner_ball.health <= 0 or attacker.health <= 0: return
	if not owner_ball.is_multiplayer_authority() or not owner_ball.is_combat_runtime_active(): return
	if attacker.attack_damage() <= 0.0: return
	var retaliation:float = float(EFFECTS.resolve(enchantments,"on_hurt").get("retaliation_damage",0.0))
	if retaliation > 0.0: attacker.receive_positional_damage(retaliation,owner_ball.global_position,false,owner_ball)

func set_level(kind:String,level:int) -> bool:
	var id:String = CATALOG.canonical(kind)
	if not CATALOG.has_id(id) or level <= 0 or level > MAX_LEVEL: return false
	enchantments[id] = level # No item class or mutual-exclusion restrictions.
	_reconcile()
	set_process(true)
	return true

func remove_level(kind:String) -> void:
	enchantments.erase(CATALOG.canonical(kind))
	_reconcile()
	set_process(not enchantments.is_empty())

func replace_all(values:Dictionary) -> void:
	var valid:Dictionary = {}
	for raw:Variant in values:
		var id:String = CATALOG.canonical(str(raw))
		if CATALOG.has_id(id) and values[raw] is int and int(values[raw]) > 0 and int(values[raw]) <= MAX_LEVEL: valid[id] = values[raw]
	enchantments = valid
	_reconcile()
	set_process(not enchantments.is_empty())

func _process(delta:float) -> void:
	if get_tree().paused: return
	var game:Node = get_node_or_null("/root/Game")
	if game != null and bool(game.get("now_stop_state")): return
	_clock += maxf(delta,0.0)
	_rescan_left -= maxf(delta,0.0)
	if _rescan_left <= 0.0:
		_rescan_left = 0.20
		_reconcile() # Covers visuals dynamically created or removed after the enchantment.
	for slot:Dictionary in _slots.values():
		var overlay:CanvasItem = slot.overlay.get_ref() as CanvasItem
		var source:CanvasItem = slot.source.get_ref() as CanvasItem
		if is_instance_valid(overlay) and is_instance_valid(source):
			_sync_overlay(source,overlay)
			(overlay.material as ShaderMaterial).set_shader_parameter("glint_time",_clock)

func _reconcile() -> void:
	if not is_inside_tree() or get_parent() == null: return
	if enchantments.is_empty():
		for slot:Dictionary in _slots.values():
			var old:Node = slot.overlay.get_ref()
			if is_instance_valid(old): old.queue_free()
		_slots.clear()
		return
	var found:Dictionary = {}
	_collect(get_parent(),found)
	for id:int in _slots.keys():
		var slot:Dictionary = _slots[id]
		var overlay:Node = slot.overlay.get_ref()
		if not found.has(id) or not is_instance_valid(overlay) or overlay.is_queued_for_deletion():
			if is_instance_valid(overlay): overlay.queue_free()
			_slots.erase(id)
	for id:int in found:
		if _slots.has(id): continue
		var source:CanvasItem = found[id]
		var overlay:CanvasItem = _create_overlay(source)
		if overlay != null: _slots[id] = {"source":weakref(source),"overlay":weakref(overlay)}

func _collect(node:Node,found:Dictionary) -> void:
	if node == self or node.has_meta("mc_enchant_skip"): return
	if node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D or node is TextureRect or node is ColorRect:
		found[node.get_instance_id()] = node
	for child:Node in node.get_children(): _collect(child,found)

func _create_overlay(source:CanvasItem) -> CanvasItem:
	var overlay:CanvasItem
	if source is Sprite2D or source is AnimatedSprite2D: overlay = Sprite2D.new()
	elif source is Polygon2D: overlay = Polygon2D.new()
	elif source is TextureRect: overlay = TextureRect.new()
	elif source is ColorRect: overlay = ColorRect.new()
	else: return null
	overlay.name = GLINT_NAME
	overlay.set_meta("mc_enchant_skip",true) # Never scan our own child even if Godot renames it on a name conflict.
	overlay.z_as_relative = true
	overlay.z_index = 1
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("native_glint",NATIVE_GLINT)
	material.set_shader_parameter("glint_time",_clock)
	overlay.material = material
	if overlay is Control: (overlay as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	source.add_child(overlay)
	_sync_overlay(source,overlay)
	return overlay

func _sync_overlay(source:CanvasItem,overlay:CanvasItem) -> void:
	if source is Sprite2D and overlay is Sprite2D:
		var s:Sprite2D = source as Sprite2D
		var view:Sprite2D = overlay as Sprite2D
		view.texture = s.texture
		view.centered = s.centered
		view.offset = s.offset
		view.flip_h = s.flip_h
		view.flip_v = s.flip_v
		view.region_enabled = s.region_enabled
		view.region_rect = s.region_rect
		view.hframes = s.hframes
		view.vframes = s.vframes
		view.frame = s.frame
		view.visible = s.texture != null
	elif source is AnimatedSprite2D and overlay is Sprite2D:
		var a:AnimatedSprite2D = source as AnimatedSprite2D
		var frame:Texture2D
		if a.sprite_frames != null and a.sprite_frames.has_animation(a.animation) and a.sprite_frames.get_frame_count(a.animation) > a.frame:
			frame = a.sprite_frames.get_frame_texture(a.animation,a.frame)
		var view:Sprite2D = overlay as Sprite2D
		view.texture = frame
		view.centered = a.centered
		view.offset = a.offset
		view.flip_h = a.flip_h
		view.flip_v = a.flip_v
		view.visible = frame != null
	elif source is Polygon2D and overlay is Polygon2D:
		var p:Polygon2D = source as Polygon2D
		var view:Polygon2D = overlay as Polygon2D
		view.polygon = p.polygon
		view.uv = p.uv
		view.texture = p.texture
		view.texture_offset = p.texture_offset
		view.texture_rotation = p.texture_rotation
		view.texture_scale = p.texture_scale
		view.color = Color(1,1,1,p.color.a)
	elif source is TextureRect and overlay is TextureRect:
		var r:TextureRect = source as TextureRect
		var view:TextureRect = overlay as TextureRect
		view.texture = r.texture
		view.size = r.size
		view.expand_mode = r.expand_mode
		view.stretch_mode = r.stretch_mode
		view.visible = r.texture != null
	elif source is ColorRect and overlay is ColorRect:
		var c:ColorRect = source as ColorRect
		var view:ColorRect = overlay as ColorRect
		view.size = c.size
		view.color = Color(1,1,1,c.color.a)
	var scale_factor:float = maxf(source.get_global_transform().x.length(),0.01)
	(overlay.material as ShaderMaterial).set_shader_parameter("world_texel",scale_factor)
