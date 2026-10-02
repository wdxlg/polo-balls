extends Node
## Opt-in enchantment component. Effects are resolved by mc_enchantment_effects.gd.
## Add this as a child of an object and edit `enchantments` in the Inspector, or call apply().
## Sprite2D, AnimatedSprite2D, Polygon2D, TextureRect, and ColorRect are masked individually.
const CATALOG = preload("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")
const EFFECTS = preload("res://scripts/effects/我的世界/mc_enchantment_effects.gd")
const CLASSIFY = preload("res://classes/combat_classification.gd")
const PROJECTILES = preload("res://classes/projectile_interactions.gd")
const SHADER = preload("res://scripts/effects/我的世界/mc_enchantment_glint.gdshader")
const NATIVE_GLINT = preload("res://Images/characters/我的世界/native_frames/trident_masks/enchanted_item_glint.png")
const NODE_NAME:String = "MinecraftEnchantments"
const GLINT_NAME:String = "MCEnchantGlint"
## Shaders that include shaders/mc_enchant_glint.gdshaderinc draw the glint themselves
## (same flip / soft-body warp / crop as the body); other visuals get a child overlay.
const GLINT_PARAM:StringName = &"enchant_glint"
const GLINT_TEXTURE_PARAM:StringName = &"enchant_glint_texture"
static var _glint_shader_cache:Dictionary = {} # shader instance id -> bool
const MAX_LEVEL:int = 32767
const ATTACK_BUFF:String = "MC附魔攻速"
const WATER_MOVE_BUFF:String = "MC附魔水中移速"
const SOUL_MOVE_BUFF:String = "MC附魔灵魂疾行"
const SOUL_SAND_FIELD_PATH:String = "res://scripts/characters/我的世界/torch/soul_sand_field.gd"
const PROJECTILES_PATH:String = "res://scripts/effects/我的世界/mc_enchant_projectiles.gd"
const LIVE_TOOLTIP_PATH:String = "res://scripts/ui/mc_active_enchantment_tooltip.gd"
const BODY_EXCLUSIONS = preload("res://classes/body_collision_exclusions.gd")
## Engine meta counting live components: ball damage hooks skip all enchant work while it is 0.
const LIVE_META:StringName = &"mc_enchant_live_components"
const HIT_EFFECT_INTERVAL_MS:int = 250
## Non-ordinary damage (fire, cold, magic...) is an ATTACK only when its classified context
## names one of these carriers; untagged elemental damage and status_tick carriers are ticks.
const DIRECT_CARRIERS:Array[String] = ["body_contact","weapon_sweep","projectile","ray_beam","area"]
## Smite / Bane of Arthropods targets by character scene (Minecraft undead and skeleton characters).
const CREATURE_FAMILIES:Dictionary = {
	"res://scenes/characters/我的世界/僵尸.tscn": "undead",
	"res://scenes/characters/我的世界/僵尸王.tscn": "undead",
	"res://scenes/characters/我的世界/凋灵.tscn": "undead",
	"res://scenes/characters/我的世界/凋灵骷髅.tscn": "undead",
	"res://scenes/characters/我的世界/溺尸.tscn": "undead",
	"res://scenes/characters/我的世界/骷髅.tscn": "undead",
	"res://scenes/characters/传说之下/Sans.tscn": "undead",
	"res://scenes/characters/我的世界/蜘蛛.tscn": "arthropod",
	"res://scenes/characters/我的世界/蠹虫.tscn": "arthropod",
}
@export var enchantments:Dictionary = {} # minecraft ID -> -32767..-1 / 1..32767 (negative = inverse)
## Runtime-granted enchantments (Enchanting Table) show a live tooltip on the character.
@export var show_live_tooltip:bool = false
var _slots:Dictionary = {} # visual instance id -> {source, overlay (weak or null), shader:bool}
var _clock:float = 0.0
var _rescan_left:float = 0.0
var _buff_refresh_left:float = 0.0
var _combat_actor:Node = null
var _impaling_peers:Dictionary = {} # instance id -> weakref(other body) with a collision lease
var _counted_live:bool = false
static var _retaliation_depth:int = 0
## Support audits (tests/audit_mc_enchant_support.gd) collect every hook call here; null in play.
static var audit_sink:Variant = null

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
	if not CATALOG.has_id(kind) or level == 0 or absi(level) > MAX_LEVEL: return false
	var component:Node = ensure(target)
	return component != null and bool(component.call("set_level",kind,level))

## Stacks a signed level: opposite signs cancel and reaching 0 removes the enchantment.
## Returns the resulting level (0 = removed).
static func add(target:Node,kind:String,delta:int,live_tooltip:bool = true) -> int:
	if not CATALOG.has_id(kind) or delta == 0: return int(levels_of(target).get(CATALOG.canonical(kind),0))
	var component:Node = ensure(target)
	if component == null: return 0
	if live_tooltip: component.set("show_live_tooltip",true)
	return int(component.call("add_level",kind,delta))

static func is_live() -> bool:
	return int(Engine.get_meta(LIVE_META,0)) > 0

static func has_enchantments(node:Node) -> bool:
	return is_instance_valid(node) and (node.has_meta("mc_enchant_components") or _component(node) != null)

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
			values[id] = maxi(int(values[id]),int(direct[id])) if values.has(id) else int(direct[id])
		for weak:Variant in node.get_meta("mc_enchant_components",[]):
			var component:Node = weak.get_ref() if weak is WeakRef else null
			if not is_instance_valid(component) or component.is_queued_for_deletion(): continue
			for id:String in component.enchantments:
				values[id] = maxi(int(values[id]),int(component.enchantments[id])) if values.has(id) else int(component.enchantments[id])
	return values

## Signed level of one enchantment on an actor (and its carried items).
static func level_on(actor:Node,kind:String) -> int:
	if not is_live() or not is_instance_valid(actor): return 0
	return int(_combat_levels(actor).get(CATALOG.canonical(kind),0))

## Quick Charge adapter for every charging character: multiply charge progress by this
## (or divide a charge DURATION by it). 1.0 when the character has no Quick Charge.
static func charge_speed(actor:Node) -> float:
	if not is_live() or not is_instance_valid(actor): return 1.0
	var n:int = level_on(_caster_of(actor),"quick_charge")
	return 1.0 if n == 0 else EFFECTS.charge_speed(n)

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
	var scene_family:Variant = CREATURE_FAMILIES.get(target.scene_file_path)
	if scene_family != null and not tags.has(scene_family): tags.append(scene_family)
	if target is ball and (target as ball).Type_Tags.has("节肢") and not tags.has("arthropod"):
		tags.append("arthropod")
	return tags

static func apply_hit_effects(actor:ball,source:Node,target:ball,mode:String,tags:Array) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(target) or target == actor or target.health <= 0: return
	if not actor.is_multiplayer_authority() or not actor.is_combat_runtime_active(): return
	# One proc per carrier/target pair per 250 ms: continuous areas must not stack knockback/burn every tick.
	var carrier:Node = source if is_instance_valid(source) else actor
	var key:String = "%d" % carrier.get_instance_id()
	var stamps:Dictionary = target.get_meta("_mc_enchant_hit_stamps",{})
	var now:int = Time.get_ticks_msec()
	if now-int(stamps.get(key,-100000)) < HIT_EFFECT_INTERVAL_MS: return
	if stamps.size() > 32: stamps.clear()
	stamps[key] = now
	target.set_meta("_mc_enchant_hit_stamps",stamps)
	var proc:Dictionary = resolve_combat_event(actor,source,"on_hit",{"mode":mode,"target_tags":tags})
	var dist:float = float(proc.get("knockback_distance",0.0))
	if not is_zero_approx(dist):
		var origin:Vector2 = (source as Node2D).global_position if source is Node2D else actor.global_position
		var direction:Vector2 = (ball.body_point(target,origin)-origin).normalized()
		if direction == Vector2.ZERO: direction = (target.global_position-actor.global_position).normalized()
		# Negative Knockback/Punch pulls toward the attacker.
		if direction != Vector2.ZERO: target.apply_knockback(direction*signf(dist),absf(dist),420.0,0.0,0.0,{"source":actor})
	_ignite(target,actor,float(proc.get("burn_seconds",0.0)),float(proc.get("burn_damage",0.0)))
	_ignite(actor,actor,float(proc.get("self_burn_seconds",0.0)),float(proc.get("self_burn_damage",0.0)))

static func _ignite(target:ball,actor:ball,seconds:float,damage:float) -> void:
	if seconds <= 0.0 or not is_instance_valid(target) or not target.can_receive_fire_status(): return
	var status:Node = target.get_node_or_null("MinecraftBlazeBurn")
	if status != null and status.has_method("refresh"): status.call("refresh",actor,seconds,damage)
	else:
		status = load("res://scripts/status/战争女神_灼烧.gd").new()
		status.name = "MinecraftBlazeBurn"
		target.add_child(status,true)
		status.call("setup",target,actor,seconds,0.55,damage)

static func apply_retaliation(defender:ball,attacker:ball,taken_damage:float) -> void:
	if not is_instance_valid(defender) or not is_instance_valid(attacker) or defender == attacker: return
	if _retaliation_depth > 0: return # Thorns damage itself never triggers thorns or attack enchantments.
	if taken_damage <= 0.0 or not defender.is_multiplayer_authority() or not defender.is_combat_runtime_active(): return
	var proc:Dictionary = resolve_event(defender,"on_hurt",{"taken_damage":taken_damage})
	var amount:float = float(proc.get("retaliation_damage",0.0))
	_retaliation_depth += 1
	if amount > 0.0 and attacker.health > 0: attacker.receive_positional_damage(amount,defender.global_position,false,defender)
	_retaliation_depth -= 1
	var heal:float = float(proc.get("attacker_heal",0.0))
	if heal > 0.0 and attacker.health > 0: attacker.heal(heal)

static func in_retaliation() -> bool:
	return _retaliation_depth > 0

## Outgoing hook shared by every positional/spatial/hitbox damage path in ball.gd.
## Returns {"damage", "caster", "mode", "tags", "armor_penetration", "shield_bypass"} or {} when
## enchantments do not apply. Only ordinary damage, or any damage carried by a projectile, counts:
## elemental ticks (burn, cold, poison, wither, bleed, drowning, magic) are not attacks.
static func outgoing(source:Node,target:ball,damage:float,kind:String = "ordinary") -> Dictionary:
	if not is_live() or _retaliation_depth > 0 or damage <= 0.0 or not is_instance_valid(source) or not is_instance_valid(target): return {}
	var caster:Node = _caster_of(source)
	if not (caster is ball) or caster == target: return {}
	var ranged:bool = CLASSIFY.is_projectile(source) or carrier_tag(target) == "projectile"
	if not has_enchantments(caster) and not has_enchantments(source): return {}
	if audit_sink != null: audit_sink.append({"caster":caster.get_instance_id(),"source":source.get_instance_id(),"ranged":ranged,"kind":kind,"damage":damage,"element":str(target.get_meta("_mc_enchant_element",target.get_meta("_blood_damage_element","physical")))})
	if not ranged and not (kind.is_empty() or kind == "ordinary") and not is_direct_elemental_hit(target): return {}
	var mode:String = "ranged" if ranged else "melee"
	var tags:Array = target_tags_for(target)
	var info:Dictionary = resolve_combat_event(caster,source if source != caster else null,"damage_out",{"damage":damage,"mode":mode,"target_tags":tags,"base_damage":damage,"current_speed":float(caster.get("Speed"))})
	info["caster"] = caster
	info["mode"] = mode
	info["tags"] = tags
	return info

## True when the classified hit being applied to target tags a direct carrier (see DIRECT_CARRIERS).
static func is_direct_elemental_hit(target:Node) -> bool:
	return DIRECT_CARRIERS.has(carrier_tag(target))

## Carrier named by the classified hit currently being applied to target ("" when untagged).
static func carrier_tag(target:Node) -> String:
	if not is_instance_valid(target) or not target.has_meta("_classified_damage_space"): return ""
	var space:Variant = target.get_meta("_classified_damage_space")
	return str((space as Dictionary).get("carrier","")) if space is Dictionary else ""

## Adapter for scripts that write target.health directly (frame damage etc.): returns the
## health to remove after the source's offensive and the target's defensive enchantments.
## Fractions carry over per source/target pair, so 1 HP frame damage scales smoothly.
static func direct_health_loss(source:Node,target:ball,amount:float) -> int:
	if amount <= 0.0 or not is_instance_valid(target): return 0
	var scaled:float = amount
	if is_live():
		var info:Dictionary = outgoing(source,target,amount,"ordinary")
		if not info.is_empty(): scaled = float(info.get("damage",amount))
		if has_enchantments(target):
			scaled = float(resolve_event(target,"damage_in",{"damage":scaled,"element":"physical","roll":randf()}).get("damage",scaled))
	if is_equal_approx(scaled,amount) and is_equal_approx(amount,roundf(amount)): return int(amount)
	var carries:Dictionary = target.get_meta("_mc_enchant_direct_carry",{})
	var key:int = source.get_instance_id() if is_instance_valid(source) else 0
	var total:float = scaled+float(carries.get(key,0.0))
	var whole:int = int(floor(total))
	if carries.size() > 16: carries.clear()
	carries[key] = total-float(whole)
	target.set_meta("_mc_enchant_direct_carry",carries)
	return maxi(whole,0)

## The node that actually CARRIED a hit. Many shots report their shooter as the damage
## source; when the source is a character, a live projectile it owns that is touching the
## impact point or the target is taken as the carrier, so the hit counts as ranged.
static func hit_carrier(source:Node,target:Node2D,point:Vector2) -> Node:
	if not is_live() or not is_instance_valid(source) or not (source is ball) or CLASSIFY.is_projectile(source) or not source.is_inside_tree(): return source
	if not has_enchantments(source) and not has_enchantments(_caster_of(source)): return source
	var best:Node = source
	var best_distance:float = INF
	for node:Node in PROJECTILES.candidates(source.get_tree()):
		if not (node is Node2D) or node == source: continue
		var shot:Node2D = node as Node2D
		var near_point:float = shot.global_position.distance_to(point)
		var near_body:float = shot.global_position.distance_to(ball.body_point(target,shot.global_position)) if is_instance_valid(target) else INF
		var distance:float = minf(near_point,near_body)
		if distance > 56.0 or distance >= best_distance: continue
		var owner:Node = PROJECTILES.owner_of(shot)
		if not is_instance_valid(owner) or (owner != source and _caster_of(owner) != source): continue
		best = shot
		best_distance = distance
	return best

static func _caster_of(source:Node) -> Node:
	var current:Node = source
	for _i:int in range(8):
		var next:Variant = null
		if "Master" in current: next = current.get("Master")
		if not is_instance_valid(next) and CLASSIFY.is_projectile(current): next = PROJECTILES.owner_of(current)
		if not is_instance_valid(next) or not (next is Node) or next == current: break
		current = next
	return current

## Hit gate for projectile shots shaped by Multishot / Piercing (see mc_enchant_projectiles.gd).
static func allow_projectile_hit(source:Node,target:Node) -> bool:
	if not is_instance_valid(source) or not (source.has_meta("mc_pierce_ignore") or source.has_meta("mc_fizzle_chance") or source.has_meta("mc_enchant_fizzled")): return true
	return bool(load(PROJECTILES_PATH).allow_hit(source,target))

static func note_projectile_hit(source:Node,target:Node) -> void:
	if not is_instance_valid(source) or not source.has_meta("mc_enchant_inspected") or not (target is ball) or not source.is_inside_tree(): return
	var runtime:Node = load(PROJECTILES_PATH).find(source.get_tree())
	if runtime != null: runtime.note_hit(source,target)

static func target_has_retaliation(target:Node) -> bool:
	return is_live() and has_enchantments(target)

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
		row.hide_level = CATALOG.is_levelless(id)
		if row.level > 3999 or row.level < 0: row.level_text_override = CATALOG.display_level(row.level)
		row.text_color = CATALOG.level_color(row.level)
		result.append(row)
	return result

func _ready() -> void:
	# Sync glints after characters update their visuals this frame (no one-frame lag).
	process_priority = 100
	var valid:Dictionary = {}
	for raw:Variant in enchantments:
		var id:String = CATALOG.canonical(str(raw))
		if CATALOG.has_id(id) and enchantments[raw] is int and absi(int(enchantments[raw])) <= MAX_LEVEL and CATALOG.clamp_level(id,int(enchantments[raw])) != 0: valid[id] = CATALOG.clamp_level(id,int(enchantments[raw]))
	enchantments = valid
	_register_combat_actor()
	_reconcile()
	_on_levels_changed()

func _register_combat_actor() -> void:
	if not _counted_live:
		_counted_live = true
		Engine.set_meta(LIVE_META,int(Engine.get_meta(LIVE_META,0))+1)
	var node:Node = get_parent()
	while node != null and not (node is ball): node = node.get_parent()
	if node == null: return
	_combat_actor = node
	var refs:Array = node.get_meta("mc_enchant_components",[])
	refs.append(weakref(self))
	node.set_meta("mc_enchant_components",refs)
	var game:Node = get_node_or_null("/root/Game")
	if game != null and game.has_signal("combatant_died") and not game.combatant_died.is_connected(_on_combatant_died):
		game.combatant_died.connect(_on_combatant_died)
	# Standard hits, burn, knockback and post-shield retaliation are now resolved
	# ONCE at ball._on_hitbox_on_hit, where actual damage and shot mode are known.

func set_level(kind:String,level:int) -> bool:
	var id:String = CATALOG.canonical(kind)
	if not CATALOG.has_id(id) or absi(level) > MAX_LEVEL: return false
	level = CATALOG.clamp_level(id,level)
	if level == 0: enchantments.erase(id)
	else: enchantments[id] = level # No item class or mutual-exclusion restrictions.
	_reconcile()
	_on_levels_changed()
	return true

## Signed stacking; returns the new level (0 = removed).
func add_level(kind:String,delta:int) -> int:
	var id:String = CATALOG.canonical(kind)
	if not CATALOG.has_id(id): return 0
	var next:int = CATALOG.clamp_level(id,clampi(int(enchantments.get(id,0))+delta,-MAX_LEVEL,MAX_LEVEL))
	set_level(id,next)
	return next

func remove_level(kind:String) -> void:
	enchantments.erase(CATALOG.canonical(kind))
	_reconcile()
	_on_levels_changed()

func _on_levels_changed() -> void:
	_refresh_combat_buffs()
	_refresh_body_rules()
	set_process(not enchantments.is_empty())
	if int(enchantments.get("multishot",0)) != 0 or int(enchantments.get("piercing",0)) != 0:
		var tree:SceneTree = get_tree() if is_inside_tree() else null
		if tree != null: load(PROJECTILES_PATH).ensure(tree)
	if show_live_tooltip and _combat_actor is ball and is_inside_tree():
		load(LIVE_TOOLTIP_PATH).ensure(_combat_actor)

func replace_all(values:Dictionary) -> void:
	var valid:Dictionary = {}
	for raw:Variant in values:
		var id:String = CATALOG.canonical(str(raw))
		if CATALOG.has_id(id) and values[raw] is int and int(values[raw]) != 0 and absi(int(values[raw])) <= MAX_LEVEL: valid[id] = values[raw]
	enchantments = valid
	_reconcile()
	_on_levels_changed()

func _process(delta:float) -> void:
	if get_tree().paused: return
	var game:Node = get_node_or_null("/root/Game")
	if game != null and bool(game.get("now_stop_state")): return
	_buff_refresh_left -= maxf(delta,0.0)
	if _buff_refresh_left <= 0.0:
		_buff_refresh_left = 0.10
		_refresh_combat_buffs()
		_refresh_body_rules()
	_clock += maxf(delta,0.0)
	_rescan_left -= maxf(delta,0.0)
	if _rescan_left <= 0.0:
		_rescan_left = 0.20
		_reconcile() # Covers visuals dynamically created or removed after the enchantment.
	for id:int in _slots.keys():
		var slot:Dictionary = _slots[id]
		var source:CanvasItem = slot.source.get_ref() as CanvasItem
		if not is_instance_valid(source): continue
		# A character may swap its material at runtime (effects, forms): switch drawing mode.
		if shader_draws_glint(source) != bool(slot.shader):
			_drop_slot(slot)
			slot = _make_slot(source)
			if slot.is_empty():
				_slots.erase(id)
				continue
			_slots[id] = slot
		if bool(slot.shader):
			_apply_shader_glint(source)
			continue
		var overlay:CanvasItem = (slot.overlay as WeakRef).get_ref() as CanvasItem
		if is_instance_valid(overlay):
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
	# Soul Speed above level 1 speeds up on fully grown soul sand; the slowdown itself is the field's motion lease.
	var on_soul:bool = int(_combat_levels(actor).get("soul_speed",0)) > 1 and bool(load(SOUL_SAND_FIELD_PATH).full_sand_under(actor))
	_set_combat_buff(world,actor,SOUL_MOVE_BUFF,float(resolve_event(actor,"move",{"on_soul":true}).get("speed_multiplier",1.0)) if on_soul else 1.0,Buff.Buff_types.Speed,false)

static func _set_combat_buff(world:Node,actor:ball,key:String,factor:float,buff_type:int,invert:bool) -> void:
	if not is_equal_approx(factor,1.0) and factor > 0.0:
		world.call("new_buff",actor,actor,key,Buff.new(2,0.25,buff_type,1.0/factor if invert else factor,Buff.Algorithms.mul))
	else:
		var actor_buffs:Dictionary = actor.Buff_Dic.get(actor.get_instance_id(),{})
		if actor_buffs.has(key): world.call("new_buff",actor,actor,key,Buff.new(),"delete")

func _exit_tree() -> void:
	_clear_slots()
	if _counted_live:
		_counted_live = false
		Engine.set_meta(LIVE_META,maxi(int(Engine.get_meta(LIVE_META,0))-1,0))
	_release_impaling()
	var game:Node = get_node_or_null("/root/Game")
	if game != null and game.has_signal("combatant_died") and game.combatant_died.is_connected(_on_combatant_died):
		game.combatant_died.disconnect(_on_combatant_died)
	var actor:ball = _combat_actor as ball
	if not is_instance_valid(actor): return
	var tree:SceneTree = actor.get_tree()
	var world:Node = tree.current_scene if tree != null else null
	if world != null and world.has_method("new_buff"):
		_set_combat_buff(world,actor,ATTACK_BUFF,1.0,Buff.Buff_types.Attack_Cooling,true)
		_set_combat_buff(world,actor,WATER_MOVE_BUFF,1.0,Buff.Buff_types.Speed,false)
		_set_combat_buff(world,actor,SOUL_MOVE_BUFF,1.0,Buff.Buff_types.Speed,false)

## The first live component registered on an actor owns actor-wide hooks (mending, impaling).
static func _primary_component(actor:Node) -> Node:
	if not is_instance_valid(actor): return null
	for weak:Variant in actor.get_meta("mc_enchant_components",[]):
		var component:Node = weak.get_ref() if weak is WeakRef else null
		if is_instance_valid(component) and not component.is_queued_for_deletion() and component.is_inside_tree(): return component
	return null

## Mending: the killer heals 5% of the victim's max health per level (inverse: loses it).
func _on_combatant_died(victim:Node,killer:Node,_health_before:float) -> void:
	var actor:ball = _combat_actor as ball
	if not is_instance_valid(actor) or killer != actor or victim == actor or not (victim is ball): return
	if _primary_component(actor) != self or not actor.is_multiplayer_authority() or actor.health <= 0: return
	var amount:float = float(resolve_event(actor,"on_kill",{"victim_max_health":float((victim as ball).Max_health)}).get("mending_health",0.0))
	if amount > 0.0: actor.heal(amount)
	elif amount < 0.0: actor.health -= int(round(-amount))

## Impaling: positive levels lease body-pair exclusions with every other character.
func _refresh_body_rules() -> void:
	var actor:ball = _combat_actor as ball
	if not is_instance_valid(actor) or not actor.is_inside_tree() or _primary_component(actor) != self:
		_release_impaling()
		return
	if int(_combat_levels(actor).get("impaling",0)) <= 0:
		_release_impaling()
		return
	var seen:Dictionary = {}
	for node:Node in actor.get_tree().get_nodes_in_group("Ball"):
		if node == actor or not (node is PhysicsBody2D) or node.is_queued_for_deletion(): continue
		var id:int = node.get_instance_id()
		seen[id] = true
		if not _impaling_peers.has(id):
			BODY_EXCLUSIONS.acquire(actor,node as PhysicsBody2D,self)
			_impaling_peers[id] = weakref(node)
	for id:int in _impaling_peers.keys():
		if seen.has(id): continue
		var other:Node = _impaling_peers[id].get_ref()
		if is_instance_valid(other): BODY_EXCLUSIONS.release(actor,other as PhysicsBody2D,self)
		_impaling_peers.erase(id)

func _release_impaling() -> void:
	var actor:ball = _combat_actor as ball
	for id:int in _impaling_peers.keys():
		var other:Node = _impaling_peers[id].get_ref()
		if is_instance_valid(actor) and is_instance_valid(other): BODY_EXCLUSIONS.release(actor,other as PhysicsBody2D,self)
	_impaling_peers.clear()

func _reconcile() -> void:
	if not is_inside_tree() or get_parent() == null: return
	if enchantments.is_empty():
		_clear_slots()
		return
	var found:Dictionary = {}
	_collect(get_parent(),found)
	for id:int in _slots.keys():
		var slot:Dictionary = _slots[id]
		if not found.has(id) or not _slot_alive(slot):
			_drop_slot(slot)
			_slots.erase(id)
	for id:int in found:
		if _slots.has(id): continue
		var slot:Dictionary = _make_slot(found[id])
		if not slot.is_empty(): _slots[id] = slot

func _make_slot(source:CanvasItem) -> Dictionary:
	if shader_draws_glint(source):
		_apply_shader_glint(source)
		return {"source":weakref(source),"overlay":null,"shader":true}
	var overlay:CanvasItem = _create_overlay(source)
	if overlay == null: return {}
	return {"source":weakref(source),"overlay":weakref(overlay),"shader":false}

func _slot_alive(slot:Dictionary) -> bool:
	var source:Object = slot.source.get_ref()
	if not is_instance_valid(source) or (source as Node).is_queued_for_deletion(): return false
	if bool(slot.shader): return true
	var overlay:Object = (slot.overlay as WeakRef).get_ref()
	return is_instance_valid(overlay) and not (overlay as Node).is_queued_for_deletion()

func _drop_slot(slot:Dictionary) -> void:
	var source:Object = slot.source.get_ref()
	if bool(slot.shader):
		if is_instance_valid(source) and shader_draws_glint(source as CanvasItem): (source as CanvasItem).set_instance_shader_parameter(GLINT_PARAM,Vector4.ZERO)
		return
	var overlay:Object = (slot.overlay as WeakRef).get_ref()
	if is_instance_valid(overlay): (overlay as Node).queue_free()

func _clear_slots() -> void:
	for slot:Dictionary in _slots.values(): _drop_slot(slot)
	_slots.clear()

## True when the visual's own shader includes mc_enchant_glint.gdshaderinc.
static func shader_draws_glint(source:CanvasItem) -> bool:
	if not is_instance_valid(source): return false
	var material:ShaderMaterial = source.material as ShaderMaterial
	if material == null or material.shader == null: return false
	var id:int = material.shader.get_instance_id()
	if not _glint_shader_cache.has(id): _glint_shader_cache[id] = material.shader.code.contains("enchant_glint")
	return bool(_glint_shader_cache[id])

func _apply_shader_glint(source:CanvasItem) -> void:
	var material:ShaderMaterial = source.material as ShaderMaterial
	if material.get_shader_parameter(GLINT_TEXTURE_PARAM) == null: material.set_shader_parameter(GLINT_TEXTURE_PARAM,NATIVE_GLINT)
	source.set_instance_shader_parameter(GLINT_PARAM,Vector4(1.0,_clock,maxf(source.get_global_transform().x.length(),0.01),0.0))

func _collect(node:Node,found:Dictionary) -> void:
	# Characters glint only on their body art: the Graphics subtree plus nodes opted in with
	# meta mc_enchant_body. Health bar, status icon, ground shadow and other UI stay plain.
	if node == get_parent() and node is ball:
		# Without its Graphics node a character has no body art yet: never fall back to the whole tree.
		if not is_instance_valid((node as ball).graphics): return
		_collect_visuals((node as ball).graphics,found)
		for extra:Node in node.find_children("*","CanvasItem",true,false):
			if extra.has_meta("mc_enchant_body") and not (node as ball).graphics.is_ancestor_of(extra): _collect_visuals(extra,found)
		return
	_collect_visuals(node,found)

func _collect_visuals(node:Node,found:Dictionary) -> void:
	if node == self or node.has_meta("mc_enchant_skip") or node is CanvasLayer: return
	if node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D or node is TextureRect or node is ColorRect:
		found[node.get_instance_id()] = node
	for child:Node in node.get_children(): _collect_visuals(child,found)

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
	# The glint is a child, so it inherits modulate/visibility but not self_modulate:
	# a source faded out through self_modulate must not leave a glowing silhouette behind.
	overlay.self_modulate.a = source.self_modulate.a
	if source.self_modulate.a <= 0.01: overlay.visible = false
	elif overlay is Polygon2D or overlay is ColorRect: overlay.visible = true
	var scale_factor:float = maxf(source.get_global_transform().x.length(),0.01)
	(overlay.material as ShaderMaterial).set_shader_parameter("world_texel",scale_factor)
