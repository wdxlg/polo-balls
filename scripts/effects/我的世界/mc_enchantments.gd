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
const ATTACK_BUFF:String = "MC附魔攻速"
const WATER_MOVE_BUFF:String = "MC附魔水中移速"
@export var enchantments:Dictionary = {} # minecraft ID -> 1..32767 (no vanilla item restrictions)
var _slots:Dictionary = {} # visual instance id -> weak source / overlay
var _clock:float = 0.0
var _rescan_left:float = 0.0
var _buff_refresh_left:float = 0.0
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

static func _combat_levels(actor:Node,source:Node = null) -> Dictionary:
	# Items nested below an actor register weak references there. A projectile
	# can also carry its own enchantments: use the highest level, not two procs.
	var values:Dictionary = {}
	for node:Node in [actor,source]:
		if not is_instance_valid(node): continue
		var direct:Dictionary = levels_of(node)
		for id:String in direct:
			values[id] = maxi(int(values.get(id,0)),int(direct[id]))
		for weak:Variant in node.get_meta("mc_enchant_components",[]):
			var component:Node = weak.get_ref() if weak is WeakRef else null
			if not is_instance_valid(component) or component.is_queued_for_deletion(): continue
			for id:String in component.enchantments:
				values[id] = maxi(int(values.get(id,0)),int(component.enchantments[id]))
	return values

## For systems that already own an event (mining, fishing, shooting, equipment,
## XP, mobility, elemental damage). Returned values are deterministic and
## side-effect-free; the authoritative caller applies them exactly once.
static func resolve_event(target:Node,event:String,context:Dictionary = {}) -> Dictionary:
	return EFFECTS.resolve(_combat_levels(target),event,context)

static func resolve_combat_event(actor:Node,source:Node,event:String,context:Dictionary = {}) -> Dictionary:
	return EFFECTS.resolve(_combat_levels(actor,source),event,context)

static func in_water(actor:Node) -> bool:
	# A real water system may supply either an is_in_water() method or this
	# explicit runtime flag. Blue/water-themed backgrounds are NOT water.
	if not is_instance_valid(actor): return false
	if actor.has_method("is_in_water"): return bool(actor.call("is_in_water"))
	return bool(actor.get_meta("in_water",false))

static func target_tags_for(target:Node) -> Array:
	var tags:Array = []
	if not is_instance_valid(target): return tags
	var family:String = str(target.get_meta("mc_creature_family",""))
	if not family.is_empty(): tags.append(family)
	# Existing spiders and silverfish have no family metadata yet. Classify by
	# their exact Minecraft character scripts, never by a user-renamable node name.
	var script:Script = target.get_script() as Script
	if script != null and script.resource_path.begins_with("res://scripts/characters/我的世界/"):
		if script.resource_path.get_file().get_basename() in ["蜘蛛","蠹虫"] and not tags.has("arthropod"):
			tags.append("arthropod")
	if target is ball and (target as ball).Type_Tags.has("节肢") and not tags.has("arthropod"):
		tags.append("arthropod")
	return tags

static func apply_hit_effects(actor:ball,source:ball,target:ball,mode:String,tags:Array) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(target) or target == actor or target.health <= 0: return
	if not actor.is_multiplayer_authority() or not actor.is_combat_runtime_active(): return
	var proc:Dictionary = resolve_combat_event(actor,source,"on_hit",{"mode":mode,"target_tags":tags})
	var dist:float = float(proc.get("knockback_distance",0.0))
	if dist > 0.0:
		var origin:Vector2 = source.global_position if is_instance_valid(source) else actor.global_position
		var direction:Vector2 = (ball.body_point(target,origin)-origin).normalized()
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

static func apply_retaliation(defender:ball,attacker:ball,taken_damage:float) -> void:
	if not is_instance_valid(defender) or not is_instance_valid(attacker) or defender == attacker: return
	if taken_damage <= 0.0 or not defender.is_multiplayer_authority() or not defender.is_combat_runtime_active(): return
	var amount:float = float(resolve_event(defender,"on_hurt",{"taken_damage":taken_damage}).get("retaliation_damage",0.0))
	if amount > 0.0 and attacker.health > 0: attacker.receive_positional_damage(amount,defender.global_position,false,defender)

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
	_register_combat_actor()
	_reconcile()
	set_process(not enchantments.is_empty())

func _register_combat_actor() -> void:
	var node:Node = get_parent()
	while node != null and not (node is ball): node = node.get_parent()
	if node == null: return
	_combat_actor = node
	var refs:Array = node.get_meta("mc_enchant_components",[])
	refs.append(weakref(self))
	node.set_meta("mc_enchant_components",refs)
	# Standard hits, burn, knockback and post-shield retaliation are now resolved
	# ONCE at ball._on_hitbox_on_hit, where actual damage and shot mode are known.

func set_level(kind:String,level:int) -> bool:
	var id:String = CATALOG.canonical(kind)
	if not CATALOG.has_id(id) or level <= 0 or level > MAX_LEVEL: return false
	enchantments[id] = level # No item class or mutual-exclusion restrictions.
	_reconcile()
	_refresh_combat_buffs()
	set_process(true)
	return true

func remove_level(kind:String) -> void:
	enchantments.erase(CATALOG.canonical(kind))
	_reconcile()
	_refresh_combat_buffs()
	set_process(not enchantments.is_empty())

func replace_all(values:Dictionary) -> void:
	var valid:Dictionary = {}
	for raw:Variant in values:
		var id:String = CATALOG.canonical(str(raw))
		if CATALOG.has_id(id) and values[raw] is int and int(values[raw]) > 0 and int(values[raw]) <= MAX_LEVEL: valid[id] = values[raw]
	enchantments = valid
	_reconcile()
	_refresh_combat_buffs()
	set_process(not enchantments.is_empty())

func _process(delta:float) -> void:
	if get_tree().paused: return
	var game:Node = get_node_or_null("/root/Game")
	if game != null and bool(game.get("now_stop_state")): return
	_buff_refresh_left -= maxf(delta,0.0)
	if _buff_refresh_left <= 0.0:
		_buff_refresh_left = 0.10
		_refresh_combat_buffs()
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

func _refresh_combat_buffs() -> void:
	var actor:ball = _combat_actor as ball
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.is_multiplayer_authority(): return
	var tree:SceneTree = actor.get_tree()
	var world:Node = tree.current_scene if tree != null else null
	if world == null or not world.has_method("new_buff"): return
	var water:bool = in_water(actor)
	var attack:Dictionary = resolve_event(actor,"attack_rate",{"in_water":water})
	var move:Dictionary = resolve_event(actor,"move",{"in_water":water})
	_set_combat_buff(world,actor,ATTACK_BUFF,float(attack.get("attack_rate_multiplier",1.0)),Buff.Buff_types.Attack_Cooling,true)
	var depth_level:int = int(_combat_levels(actor).get("depth_strider",0))
	_set_combat_buff(world,actor,WATER_MOVE_BUFF,float(move.get("speed_multiplier",1.0)) if water and depth_level > 0 else 1.0,Buff.Buff_types.Speed,false)

static func _set_combat_buff(world:Node,actor:ball,key:String,factor:float,buff_type:int,invert:bool) -> void:
	if factor > 1.0:
		world.call("new_buff",actor,actor,key,Buff.new(2,0.25,buff_type,1.0/factor if invert else factor,Buff.Algorithms.mul))
	else:
		var actor_buffs:Dictionary = actor.Buff_Dic.get(actor.get_instance_id(),{})
		if actor_buffs.has(key): world.call("new_buff",actor,actor,key,Buff.new(),"delete")

func _exit_tree() -> void:
	var actor:ball = _combat_actor as ball
	if not is_instance_valid(actor): return
	var tree:SceneTree = actor.get_tree()
	var world:Node = tree.current_scene if tree != null else null
	if world != null and world.has_method("new_buff"):
		_set_combat_buff(world,actor,ATTACK_BUFF,1.0,Buff.Buff_types.Attack_Cooling,true)
		_set_combat_buff(world,actor,WATER_MOVE_BUFF,1.0,Buff.Buff_types.Speed,false)

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
