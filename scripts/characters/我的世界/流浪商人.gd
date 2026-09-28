extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## 流浪商人 (Wandering Trader). Rules, numbers and sources: docs/WANDERING_TRADER.md.
## * Comes with two trader llamas (scenes/creatures/流浪商人_羊驼.tscn), each on a 缰绳.
##   Llamas are killable summons (Master = trader): no victory weight, leash removed when one
##   dies, and they despawn with the trader. A dead llama's slot has a return cooldown; once it is
##   ready, the next wall exit brings one llama back out of the wall with him, on its leash.
## * 牛奶: only while a negative effect is present; clears all negative effects exactly like the
##   copper sword (ball.cleanse_negative_effects / classes/status_cleansing.gd). Long cooldown.
## * 隐身药水: the Witch's own invisibility (女巫药水效果.apply_effect(self,"invisibility",self)).
## * 入墙: walks straight into the nearest map wall; the body is clipped on the wall surface, so it
##   vanishes only once it is completely inside (leashes snap). He then pushes straight out of the
##   safest wall slot (farthest from enemies, body-clear floor), again clipped, and the leashes
##   reconnect. No fading. Shortly before he comes out, the exit wall cracks (stone chips + sound)
##   so opponents can read where he will appear.
## * 物品: every wall exit rolls one item (items/catalog.gd), shown in the item frame under him
##   until it is used: 火药 / 蓝冰 / 河豚桶 / 滴水石锥 / 粘液球 / 干草块 / 马铃薯 / 仙人掌 / 热带鱼桶.
const AUDIO = preload("res://scripts/characters/我的世界/wandering_trader/audio.gd")
const VISUAL = preload("res://scripts/characters/我的世界/wandering_trader/visual.gd")
const LEASH = preload("res://scripts/characters/我的世界/wandering_trader/leash.gd")
const WALL = preload("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
const WALL_CLIP = preload("res://scripts/characters/我的世界/wandering_trader/wall_clip.gd")
const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const STATUS_EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const HIT_AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const LLAMA_SCENE_PATH:String = "res://scenes/creatures/流浪商人_羊驼.tscn"
const STATUS_CLEANSING_PATH:String = "res://classes/status_cleansing.gd"
const STONE_COLOR := Color(0.49,0.49,0.49)
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
const CRUMBS = preload("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd")
const FRAME_VIEW = preload("res://scripts/characters/我的世界/wandering_trader/items/frame_view.gd")
const THROWN = preload("res://scripts/characters/我的世界/wandering_trader/items/thrown.gd")
const HEARTS = preload("res://scripts/characters/我的世界/wandering_trader/items/hearts_fx.gd")
const PLACED_SCRIPTS:Dictionary = {
	&"gunpowder":preload("res://scripts/characters/我的世界/wandering_trader/items/gunpowder.gd"),
	&"blue_ice":preload("res://scripts/characters/我的世界/wandering_trader/items/blue_ice.gd"),
	&"pointed_dripstone":preload("res://scripts/characters/我的世界/wandering_trader/items/dripstone.gd"),
	&"cactus":preload("res://scripts/characters/我的世界/wandering_trader/items/cactus.gd"),
}
enum Phase { NONE, ENTERING, HIDDEN, EMERGING }

@export_category("流浪商人 / 羊驼与缰绳")
@export var llama_count:int = 2
@export var leash_slack:float = 42.0
@export var leash_pull_start:float = 60.0
@export var leash_pull_end:float = 28.0
@export_category("流浪商人 / 牛奶")
@export var milk_cooldown:float = 20.0
@export var milk_drink_time:float = 1.1
@export_category("流浪商人 / 隐身药水")
@export var invisibility_cooldown:float = 16.0
@export var invisibility_first_delay:float = 5.0
@export var invisibility_threat_radius:float = 70.0
@export var potion_drink_time:float = 0.78
@export_category("流浪商人 / 入墙")
@export var wall_cooldown:float = 11.0
@export var wall_first_delay:float = 7.0
@export var wall_threat_radius:float = 60.0
@export var wall_hidden_time:float = 2.6
@export var wall_arm_timeout:float = 4.0 # armed: goes into the next wall he runs into within this time
@export var wall_walk_time_max:float = 3.0 # safety cap for one walk in / out
@export var wall_max_angle_deg:float = 60.0 # steepest angle to the wall normal he walks in / out at
@export var wall_exit_warning:float = 0.45 # exit wall cracks this long before he comes out
@export var drink_move_ratio:float = 0.35
@export_category("流浪商人 / 羊驼补回")
@export var llama_return_cooldown:float = 20.0
@export_category("流浪商人 / 物品")
@export var item_delay_min:float = 0.6 # 火药 / 仙人掌: random delay after the wall exit
@export var item_delay_max:float = 2.4
@export var item_show_time:float = 0.3 # immediate items stay this long in the frame first
@export var slime_range:float = 150.0
@export var slime_hold_max:float = 10.0
@export var dripstone_hold_max:float = 12.0
@export var potato_heal:float = 40.0
@export var potato_eat_time:float = 0.96
@export var fish_max_each:int = 2
@export var items_enabled:bool = true # off = no item roll on wall exit (deterministic herd tests)

var wall_phase:int = Phase.NONE
var leashes:Array[Node2D] = []
var visual:Node
var milk_drinks:int = 0
var potion_drinks:int = 0
var wall_entries:int = 0
var last_cleansed:int = -1
var entry_slot:Dictionary = {}
var exit_slot:Dictionary = {}
var _llama_refs:Array = []
var _leash_active:bool = true
var _milk_wait:float = 0.0
var _invisibility_wait:float = 5.0
var _wall_wait:float = 7.0
var _drink_left:float = 0.0
var _drink_kind:StringName = &""
var _drink_visual_left:float = 0.0
var _since_hurt:float = 999.0
var _negative_check_wait:float = 0.0
var _phase_time:float = 0.0
var _phase_duration:float = 0.0
var _phase_from:Vector2
var _phase_to:Vector2
var _saved_layer:int = 2
var _saved_mask:int = 3
var _saved_while_invisible:bool = false
## Potion finished inside the wall: applied once collision is restored (the Witch effect saves
## the current collision layer, which is 0 inside the wall).
var _pending_invisibility:bool = false
var _wall_clip:Node
var _item_anchor:Node2D
var _item_sprite:Sprite2D
var _item_tween:Tween
var exit_warnings:int = 0
var wall_crumb_bursts:int = 0
## Wall skill triggered: he keeps his normal movement and goes in at the next wall he hits.
var wall_armed:bool = false
var _wall_armed_time:float = 0.0
var _wall_walk_speed:float = 48.0
var _wall_walk_angle:float = 0.0 # signed angle between the inward normal and his walk direction
var exit_direction:Vector2 = Vector2.ZERO
var llamas_returned:int = 0
var _exit_warned:bool = false
## Per llama slot: seconds until a dead llama may come back (<= 0 and empty slot = due).
var _llama_return_wait:Array[float] = []
## Slot of the llama walking out of the wall with him this exit (-1 = none).
var _returning_llama:int = -1
var held_item:StringName = &""
var items_rolled:int = 0
var items_used:Dictionary = {} # kind -> count
var item_frame:Node2D
var gunpowder_hits:int = 0
var ice_wall_hits:int = 0
var slime_hits:int = 0
var slime_wall_bounces:int = 0
var hay_healed:int = 0
var potato_healed:int = 0
var fish_released:int = 0
var _item_wait:float = 0.0
var _item_hold:float = 0.0
var _item_serial:int = 0
var _fish_serial:int = 0

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	mc_audio_role = "wandering_trader"
	super._ready()
	visual = VISUAL.attach(self,&"trader")
	_setup_item_visual()
	item_frame = FRAME_VIEW.new()
	item_frame.call(&"setup",self)
	add_child(item_frame)
	_invisibility_wait = invisibility_first_delay
	_wall_wait = wall_first_delay
	for i:int in range(llama_count):
		_llama_refs.append(null)
		_llama_return_wait.append(0.0)
		var view:Node2D = LEASH.new()
		view.name = "%s_Leash%d" % [str(name),i]
		view.slack_length = leash_slack
		leashes.append(view)
	call_deferred("_attach_leash_views")
	if is_multiplayer_authority(): call_deferred("_spawn_llamas")

func _attach_leash_views() -> void:
	# World-space children of the battle scene so they stay visible while the trader is hidden
	# (the snap animation plays at the wall) and so they never inherit the trader's scale.
	var parent:Node = get_parent() if get_parent() != null else get_tree().current_scene
	for view:Node2D in leashes:
		if is_instance_valid(view) and view.get_parent() == null: parent.add_child(view)

func _exit_tree() -> void:
	super._exit_tree()
	# Llamas retire themselves once their Master is gone; World resets free them with the Balls.
	for view:Node2D in leashes:
		if is_instance_valid(view): view.queue_free()

# ------------------------------------------------------------------ herd
func llama_name(index:int) -> String:
	return "%s_Llama%d" % [str(name),index]

func _spawn_llamas() -> void:
	if not is_inside_tree() or health <= 0 or not is_multiplayer_authority(): return
	for i:int in range(llama_count):
		if _llama(i) != null: continue
		var side:float = -16.0 if i % 2 == 0 else 16.0
		var wanted:Vector2 = global_position + Vector2(side,5.0)*absf(global_scale.x)/0.2
		var llama:ball = _spawn_llama(i)
		if llama == null: continue
		llama.global_position = wanted if llama.mc_body_position_clear(wanted) else TOOLS.safe_spawn_position(self,wanted,18.0)

## Deterministic name "<trader>_Llama<i>" (the slot/colour come from it on every peer); a returning
## llama reuses its dead predecessor's name, which is long freed by then.
func _spawn_llama(index:int) -> ball:
	var parent:Node = get_parent() if get_parent() != null else get_tree().current_scene
	if parent.get_node_or_null(NodePath(llama_name(index))) != null: return null
	var scene:PackedScene = load(LLAMA_SCENE_PATH) as PackedScene
	var llama:ball = scene.instantiate()
	llama.name = llama_name(index)
	llama.Master = self
	llama.Master_name = str(get_path())
	llama.Team = Team
	llama.set_multiplayer_authority(get_multiplayer_authority())
	parent.add_child(llama,true)
	_register_llama(index,llama)
	return llama

func _register_llama(index:int,llama:ball) -> void:
	_llama_refs[index] = weakref(llama)
	llama.set(&"leash_connected",true)
	add_collision_exception_with(llama)
	llama.add_collision_exception_with(self)
	for other_index:int in range(_llama_refs.size()):
		var other:Node = _llama(other_index)
		if other != null and other != llama:
			llama.add_collision_exception_with(other)
			(other as PhysicsBody2D).add_collision_exception_with(llama)

func _llama(index:int) -> Node:
	if index < 0 or index >= _llama_refs.size(): return null
	var ref:Variant = _llama_refs[index]
	var node:Variant = (ref as WeakRef).get_ref() if ref is WeakRef else null
	if not is_instance_valid(node) or (node as Node).is_queued_for_deletion():
		# Remote peers (and rejoin) find the replicated llama by its deterministic name.
		var parent:Node = get_parent()
		node = parent.get_node_or_null(NodePath(llama_name(index))) if parent != null else null
		if not is_instance_valid(node) or (node as Node).is_queued_for_deletion() or float(node.get(&"health")) <= 0.0: return null
		_llama_refs[index] = weakref(node)
	return node

func living_llamas() -> Array[Node]:
	var result:Array[Node] = []
	for i:int in range(_llama_refs.size()):
		var llama:Node = _llama(i)
		if llama != null and float(llama.get(&"health")) > 0.0: result.append(llama)
	return result

func wt_on_llama_lost(llama:Node) -> void:
	for i:int in range(_llama_refs.size()):
		var ref:Variant = _llama_refs[i]
		if ref is WeakRef and (ref as WeakRef).get_ref() == llama:
			_llama_refs[i] = null
			if i < _llama_return_wait.size(): _llama_return_wait[i] = llama_return_cooldown
			if i < leashes.size() and is_instance_valid(leashes[i]): leashes[i].snap()

func wt_leash_active() -> bool:
	return _leash_active and wall_phase == Phase.NONE and health > 0

func Die() -> void:
	super.Die()
	_finish_drink_visual()
	for view:Node2D in leashes:
		if is_instance_valid(view): view.snap()
	if is_multiplayer_authority():
		for llama:Node in living_llamas():
			if llama.has_method(&"owner_lost"): llama.call(&"owner_lost")

# ------------------------------------------------------------------ audio
func wt_sound(event:StringName,volume:float = 0.0,point:Variant = null) -> AudioStreamPlayer2D:
	var index:int = AUDIO.variant(event)
	var at:Vector2 = point if point is Vector2 else global_position
	var pitch:float = _mc_voice_rng.randf_range(0.92,1.08)
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_wt_sound_remote.rpc(event,index,at,volume,pitch)
	return AUDIO.play(self,event,at,volume,pitch,index)

@rpc("authority","call_remote","unreliable")
func _wt_sound_remote(event:StringName,index:int,point:Vector2,volume:float,pitch:float) -> void:
	AUDIO.play(self,event,point,volume,pitch,index)

func mc_play(event:String,_volume:float = -4.0) -> AudioStreamPlayer2D:
	var key:StringName = StringName("trader_" + event)
	if not AUDIO.EVENTS.has(key): return null
	return wt_sound(key)
func mc_ambient_event() -> String: return "ambient"
func mc_ambient_allowed() -> bool: return is_multiplayer_authority() and wall_phase == Phase.NONE and _drink_left <= 0.0
func mc_ambient_gap() -> Vector2: return Vector2(4.0,9.0)

# ------------------------------------------------------------------ frame
func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority() or health <= 0:
		super.tick_physics(state,delta)
		return
	if wall_phase != Phase.NONE:
		if not is_combat_runtime_active():
			finish_wall_phase_now()
			return
		_tick_wall(delta)
	else:
		super.tick_physics(state,delta)
	if health <= 0 or not is_combat_runtime_active(): return
	# Potion and wall are independent skills: both cooldowns and the drink keep running in the wall.
	_since_hurt += delta
	_milk_wait -= delta
	_invisibility_wait -= delta
	_wall_wait -= delta
	for i:int in range(_llama_return_wait.size()): _llama_return_wait[i] -= delta
	if wall_armed:
		_wall_armed_time += delta
		if _wall_armed_time > wall_arm_timeout or wall_phase != Phase.NONE:
			wall_armed = false
			if wall_phase == Phase.NONE: _wall_wait = 1.5 # never reached a wall: short retry
	if _drink_left > 0.0:
		_drink_left -= delta
		if _drink_left <= 0.0: _finish_drink()
	if dizziness or is_damage_output_disabled(): return
	if wall_phase == Phase.NONE: _tick_item(delta)
	if _drink_left <= 0.0 and wall_phase == Phase.NONE:
		_negative_check_wait -= delta
		if _milk_wait <= 0.0 and _negative_check_wait <= 0.0:
			_negative_check_wait = 0.2
			if has_negative_effect():
				start_drink(&"milk")
				return
	if is_player_controlled(): return
	var threat:float = nearest_threat_distance()
	if wall_phase == Phase.NONE and not wall_armed and _wall_wait <= 0.0 and (threat <= wall_threat_radius or (_since_hurt < 0.8 and health < Max_health*0.6)):
		start_wall_phase()
	if can_drink_invisibility() and (threat <= invisibility_threat_radius or _since_hurt < 1.0):
		start_drink(&"invisibility")

func can_drink_invisibility() -> bool:
	return _invisibility_wait <= 0.0 and _drink_left <= 0.0 and not _pending_invisibility and not is_invisible()

func move(speed:float,delta:float) -> void:
	super.move(speed*(drink_move_ratio if _drink_left > 0.0 else 1.0),delta)

func _process(delta:float) -> void:
	if _drink_visual_left > 0.0:
		_drink_visual_left -= delta
		if _drink_visual_left <= 0.0: _finish_drink_visual()
		elif _item_anchor != null: _item_anchor.visible = item_outside_wall()
	_update_item_facing()
	_update_leash_views()

func wt_visual_clip(observed_speed:float) -> StringName:
	if _drink_visual_left > 0.0: return &"drink"
	if wall_phase == Phase.ENTERING or wall_phase == Phase.EMERGING: return &"walk"
	return &"walk" if observed_speed > 6.0 else &"idle"

func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	super.on_actual_health_damage_received(actual_health_damage,health_before)
	if actual_health_damage > 0.0: _since_hurt = 0.0

func nearest_threat_distance() -> float:
	var best:float = INF
	for point:Vector2 in threat_points(): best = minf(best,global_position.distance_to(point))
	return best

func threat_points() -> Array[Vector2]:
	var points:Array[Vector2] = []
	for raw:Node in get_tree().get_nodes_in_group(&"Ball"):
		if raw == self or not (raw is ball): continue
		var unit:ball = raw as ball
		if unit.Type in [Ball_Type.Ball,Ball_Type.Creature] and wt_enemy(unit): points.append(unit.global_position)
	return points

func wt_enemy(target:Variant) -> bool:
	if not mc_enemy(target): return false
	if (target as Object).has_method(&"is_guarded_from_friendly_copy") and bool((target as Object).call(&"is_guarded_from_friendly_copy",self)): return false
	return true

func is_invisible() -> bool:
	return STATUS_EFFECTS.active(self,"invisibility") or bool(get_meta(&"mc_ignore_character_body_collision",false))

# ------------------------------------------------------------------ milk / potion
## Read-only mirror of classes/status_cleansing.gd candidates: a negative status node (children,
## recursive, or registered), or a legacy Buff that is_negative_for(self). Never mutates anything.
func has_negative_effect() -> bool:
	var cleansing:Script = load(STATUS_CLEANSING_PATH) as Script if ResourceLoader.exists(STATUS_CLEANSING_PATH) else null
	var candidates:Array[Node] = []
	_collect_effect_nodes(self,candidates)
	var registrations:Variant = get(&"_status_effect_registrations")
	if registrations is Dictionary:
		for ref:Variant in (registrations as Dictionary).values():
			var effect:Variant = (ref as WeakRef).get_ref() if ref is WeakRef else null
			if is_instance_valid(effect) and not candidates.has(effect): candidates.append(effect)
	for effect:Node in candidates:
		if not is_instance_valid(effect) or effect == self or effect.is_queued_for_deletion(): continue
		if "target" in effect and effect.get("target") != self: continue
		var polarity:int = 0
		if effect.has_method(&"get_status_effect_polarity"): polarity = int(effect.call(&"get_status_effect_polarity"))
		elif cleansing != null: polarity = int(cleansing.call(&"polarity",effect))
		if polarity < 0: return true
	for source_id:Variant in Buff_Dic.keys():
		var buffs:Variant = Buff_Dic[source_id]
		if not (buffs is Dictionary): continue
		for key:Variant in (buffs as Dictionary).keys():
			var buff:Variant = buffs[key]
			if buff is Object and (buff as Object).has_method(&"is_negative_for") and bool((buff as Object).call(&"is_negative_for",self)): return true
	return false

func _collect_effect_nodes(node:Node,result:Array[Node]) -> void:
	for child:Node in node.get_children():
		if child.has_method(&"cleanse_negative_effects"): continue
		result.append(child)
		_collect_effect_nodes(child,result)

## Same one-shot cleanse the copper sword uses. Returns removed count (or -1 if unavailable).
func cleanse_with_milk() -> int:
	if has_method(&"cleanse_negative_effects"): return int(call(&"cleanse_negative_effects"))
	if ResourceLoader.exists(STATUS_CLEANSING_PATH):
		var cleansing:Script = load(STATUS_CLEANSING_PATH) as Script
		if cleansing != null and get(&"_status_effect_registrations") is Dictionary: return int(cleansing.call(&"clear_local",self))
	return -1

func start_drink(kind:StringName) -> bool:
	# The potion also works inside the wall (independent skill); milk keeps its old rule.
	if _drink_left > 0.0 or health <= 0 or (kind != &"invisibility" and wall_phase != Phase.NONE): return false
	_drink_kind = kind
	if kind == CATALOG.POTATO:
		_drink_left = potato_eat_time
		_eat_effects(potato_eat_time)
	elif kind == &"milk":
		_milk_wait = milk_cooldown
		_drink_left = milk_drink_time
		milk_drinks += 1
		wt_sound(&"drink_milk")
	else:
		_invisibility_wait = invisibility_cooldown
		_drink_left = potion_drink_time
		potion_drinks += 1
		wt_sound(&"drink_potion")
	_show_drink_visual(kind,_drink_left)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _show_drink_visual.rpc(kind,_drink_left)
	return true

func _finish_drink() -> void:
	var kind:StringName = _drink_kind
	_drink_kind = &""
	_drink_left = 0.0
	if health <= 0: return
	if kind == CATALOG.POTATO:
		potato_healed += heal(potato_heal)
		wt_sound(&"item_burp",-2.0)
	elif kind == &"milk":
		last_cleansed = cleanse_with_milk()
		VISUAL.burst(self,global_position + Vector2(0.0,-4.0),Color(1.0,1.0,1.0),12,36.0,1.3,0.5)
	elif kind == &"invisibility":
		if wall_phase != Phase.NONE: _pending_invisibility = true
		else: POTION_EFFECTS.apply_effect(self,"invisibility",self)

@rpc("authority","call_remote","reliable")
func _show_drink_visual(kind:StringName,duration:float) -> void:
	_drink_visual_left = duration
	if _item_sprite == null: return
	_item_sprite.texture = CATALOG.icon(kind) if kind == CATALOG.POTATO else VISUAL.item_texture(kind)
	var size:float = maxf(_item_sprite.texture.get_width() if _item_sprite.texture != null else 16.0,1.0)
	_item_sprite.scale = Vector2.ONE*(30.0/size)
	_item_anchor.visible = true
	var hand := Vector2(12.0,-12.0)
	var mouth := Vector2(11.0,-38.0)
	_item_sprite.position = hand
	_item_sprite.rotation = 0.0
	if _item_tween != null and _item_tween.is_valid(): _item_tween.kill()
	# Witch drinking gesture: raise to the mouth, three small sips, lower.
	_item_tween = create_tween()
	_item_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var approach:float = duration*0.28
	var sip:float = duration*0.09
	_item_tween.tween_property(_item_sprite,"position",mouth,approach)
	_item_tween.parallel().tween_property(_item_sprite,"rotation",-0.5,approach)
	for i:int in range(3):
		_item_tween.tween_property(_item_sprite,"position",mouth + Vector2(0.0,-4.0),sip)
		_item_tween.tween_property(_item_sprite,"position",mouth + Vector2(0.0,1.5),sip)

func _finish_drink_visual() -> void:
	_drink_visual_left = 0.0
	if _item_tween != null and _item_tween.is_valid(): _item_tween.kill()
	if _item_anchor != null: _item_anchor.visible = false

## The held bottle is not covered by the body's wall clip shader: hide it while it is behind the wall.
func item_outside_wall() -> bool:
	if _wall_clip == null or not is_instance_valid(_wall_clip) or not bool(_wall_clip.get(&"active")): return true
	var at:Vector2 = _item_sprite.global_position if _item_sprite != null else global_position
	return float(_wall_clip.call(&"side_of",at)) > 0.0

func _setup_item_visual() -> void:
	var parent:Node2D = graphics if graphics != null and is_instance_valid(graphics) else self
	_item_anchor = Node2D.new()
	_item_anchor.name = "TraderHeldItem"
	_item_anchor.z_index = 120
	_item_anchor.visible = false
	parent.add_child(_item_anchor)
	_item_sprite = Sprite2D.new()
	_item_sprite.name = "Item"
	_item_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_item_anchor.add_child(_item_sprite)

func facing_sign() -> float:
	# dir_left=true: unflipped artwork faces left; the shader flip turns it right.
	var default_sign:float = -1.0 if dir_left else 1.0
	return -default_sign if is_character_visual_flipped_h() else default_sign

func _update_item_facing() -> void:
	if _item_anchor != null: _item_anchor.scale = Vector2(facing_sign(),1.0)

func hand_point() -> Vector2:
	return to_global(Vector2(facing_sign()*12.0,-12.0))

# ------------------------------------------------------------------ leash visuals
func _update_leash_views() -> void:
	for i:int in range(leashes.size()):
		var view:Node2D = leashes[i]
		if not is_instance_valid(view) or not view.is_inside_tree(): continue
		var llama:Node = _llama(i)
		if llama == null or health <= 0:
			if view.is_connected_visual(): view.snap()
			continue
		var from:Vector2 = hand_point()
		var to:Vector2 = llama.call(&"wt_neck_point") if llama.has_method(&"wt_neck_point") else (llama as Node2D).global_position
		if _leash_active and wall_phase == Phase.NONE:
			if not view.is_connected_visual(): view.connect_visual()
			view.set_points(from,to,leash_slack,from.distance_to(to) >= leash_slack)
		elif view.is_connected_visual():
			view.set_points(from,to,leash_slack,true)
			view.snap()

@rpc("authority","call_remote","reliable")
func _set_leash_active(active:bool) -> void:
	if _leash_active == active: return
	_leash_active = active
	if is_multiplayer_authority():
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _set_leash_active.rpc(active)
		for i:int in range(_llama_refs.size()):
			var llama:Node = _llama(i)
			if llama == null: continue
			var middle:Vector2 = hand_point().lerp((llama as Node2D).global_position,0.5)
			wt_sound(&"leash_place" if active else &"leash_break",0.0,middle)
	_update_leash_views()

# ------------------------------------------------------------------ wall phase
## Arms the wall skill. He does not steer or speed up: he keeps his normal movement and walks
## into the next wall he runs into (when_collide), at the speed and in the direction he had.
func start_wall_phase() -> bool:
	if wall_phase != Phase.NONE or wall_armed or health <= 0 or not is_multiplayer_authority(): return false
	wall_armed = true
	_wall_armed_time = 0.0
	_wall_wait = wall_cooldown + wall_arm_timeout + wall_hidden_time + wall_walk_time_max*2.0
	return true

func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	var collider:Object = collision.get_collider() if collision != null else null
	# His own cactus is an obstacle, not a wall: no wall entry, no dripstone on it.
	var map_wall:bool = collision != null and not (collider is ball) and not (collider is Node and (collider as Node).is_in_group(&"WTItemObstacle"))
	if map_wall and held_item == CATALOG.DRIPSTONE and wall_phase == Phase.NONE and is_multiplayer_authority() and health > 0:
		if _place_item(CATALOG.DRIPSTONE,collision.get_position(),{"normal": collision.get_normal(),"grace": get_instance_id()}) != null: _item_used(CATALOG.DRIPSTONE)
	if wall_armed and wall_phase == Phase.NONE and is_multiplayer_authority() and map_wall:
		if begin_wall_entry(collision.get_position(),collision.get_normal(),_last_requested_velocity): return
	super.when_collide(speed,collision)

## Walk direction at most wall_max_angle_deg from the inward normal (keeps its side).
func _clamp_walk_direction(dir:Vector2,inward:Vector2) -> Vector2:
	if dir.length_squared() < 0.000001: return inward
	var angle:float = inward.angle_to(dir.normalized())
	var limit:float = deg_to_rad(wall_max_angle_deg)
	return inward.rotated(clampf(angle,-limit,limit))

## face = the wall contact point, normal = wall normal (towards the floor), motion = the velocity he
## had. He walks on in that direction at that speed until his whole drawn body is behind the face.
func begin_wall_entry(face:Vector2,normal:Vector2,motion:Vector2) -> bool:
	if wall_phase != Phase.NONE or health <= 0 or not is_multiplayer_authority(): return false
	var n:Vector2 = normal.normalized() if normal.length_squared() > 0.000001 else Vector2.UP
	var speed:float = motion.length()
	if speed < 12.0: speed = maxf(Speed*CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,12.0)
	var raw:Vector2 = motion if motion.length_squared() > 0.01 else (direction if direction.length_squared() > 0.000001 else -n)
	var walk:Vector2 = _clamp_walk_direction(raw,-n)
	var depth:float = maxf((global_position - face).dot(n) + body_reach(n) + 1.0,0.0)
	var distance:float = depth/maxf(walk.dot(-n),0.05)
	wall_armed = false
	entry_slot = {"floor": global_position,"normal": n,"contact_face": face}
	_wall_walk_speed = speed
	_wall_walk_angle = (-n).angle_to(walk)
	wall_entries += 1
	exit_slot = {}
	_exit_warned = false
	_returning_llama = -1
	_wall_wait = wall_cooldown + wall_hidden_time + wall_walk_time_max*2.0
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	_saved_while_invisible = is_invisible()
	collision_layer = 0
	collision_mask = 0
	set_meta(&"ignore_combat_locking",true)
	# The body really goes past the map edge; World's squeeze rescue / out-of-bounds kill skip it.
	set_meta(&"submission_allow_map_escape",true)
	_begin_phase(Phase.ENTERING,global_position,global_position + walk*distance,minf(distance/speed,wall_walk_time_max))
	_wall_clip_state(true,face,n)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _wall_clip_state.rpc(true,face,n)
	_set_leash_active(false)
	wt_sound(&"trader_disappeared")
	return true

func _begin_phase(phase:int,from:Vector2,to:Vector2,duration:float) -> void:
	wall_phase = phase
	_phase_time = 0.0
	_phase_duration = maxf(duration,0.01)
	_phase_from = from
	_phase_to = to
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	if absf(to.x - from.x) > 0.01: set_character_visual_flip_h(to.x > from.x if dir_left else to.x < from.x)

func _tick_wall(delta:float) -> void:
	_phase_time += delta
	# Invisibility ending mid-phase restores its saved collision; inside the wall stay non-solid.
	if collision_layer != 0: collision_layer = 0
	if collision_mask != 0: collision_mask = 0
	var k:float = clampf(_phase_time/_phase_duration,0.0,1.0)
	# Straight walk at constant speed, fully opaque: the wall clip does the hiding.
	match wall_phase:
		Phase.ENTERING:
			global_position = _phase_from.lerp(_phase_to,k)
			if k >= 1.0: _enter_hidden()
		Phase.HIDDEN:
			if not _exit_warned and _phase_time >= wall_hidden_time - wall_exit_warning: _warn_exit()
			if _phase_time >= wall_hidden_time: _begin_emerge()
		Phase.EMERGING:
			global_position = _phase_from.lerp(_phase_to,k)
			if k >= 1.0: _finish_wall()

## The surface he visibly walks into: the physical wall (layer 1, World's bounce walls) found by
## a ray from the slot's floor tile against the normal. On maps whose border ring tiles are
## walkable (e.g. Map10x10) this is the arena edge, not the tile seam. Lateral position stays on
## the slot. Falls back to the tile seam when nothing is hit.
func wall_face_point(slot:Dictionary) -> Vector2:
	if slot.has("contact_face"): return slot.contact_face # walk-in contact (real wall surface)
	var normal:Vector2 = _slot_normal(slot)
	var seam:Vector2 = WALL.face_point(slot)
	if not is_inside_tree(): return seam
	var from:Vector2 = slot.get("floor",seam)
	var query := PhysicsRayQueryParameters2D.create(from,seam - normal*48.0,1,[get_rid()])
	query.collide_with_areas = false
	var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return seam
	return seam + normal*((hit.position as Vector2) - seam).dot(normal)

func _slot_normal(slot:Dictionary) -> Vector2:
	var normal:Vector2 = slot.get("normal",Vector2.UP)
	return normal.normalized() if normal.length_squared() > 0.000001 else Vector2.UP

## How far the drawn body reaches from global_position along +dir (sprite rect incl. transform,
## plus room for the shader's movement stretch).
func body_reach(dir:Vector2) -> float:
	if image == null or not is_instance_valid(image) or image.texture == null: return 24.0
	var rect:Rect2 = image.get_rect()
	var xf:Transform2D = image.get_global_transform()
	var reach:float = 0.0
	for corner:Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		reach = maxf(reach,(xf*corner - global_position).dot(dir))
	return reach*1.12 + 2.0

## Point on the wall side where the whole drawn body is behind the wall surface.
func inside_wall_point(face:Vector2,normal:Vector2) -> Vector2:
	return face - normal*body_reach(normal)

## True while any part of the drawn body is on the floor side of the active wall clip.
func wall_body_visible() -> bool:
	if _wall_clip == null or not is_instance_valid(_wall_clip) or not bool(_wall_clip.get(&"active")): return visible
	if not visible: return false
	var normal:Vector2 = _wall_clip.get(&"normal")
	return float(_wall_clip.call(&"side_of",global_position)) + body_reach(normal) > 0.5

@rpc("authority","call_remote","reliable")
func _wall_clip_state(active:bool,face:Vector2,normal:Vector2) -> void:
	if active:
		if image == null or not is_instance_valid(image): return
		if _wall_clip == null or not is_instance_valid(_wall_clip):
			_wall_clip = WALL_CLIP.new()
			_wall_clip.name = "WallClip"
			add_child(_wall_clip)
		_wall_clip.call(&"start",image,face,normal)
	elif _wall_clip != null and is_instance_valid(_wall_clip):
		_wall_clip.call(&"stop")

func _enter_hidden() -> void:
	_begin_phase(Phase.HIDDEN,global_position,global_position,wall_hidden_time)
	set_meta(&"ignore_combat_targeting",true)
	if self_hurtbox != null: self_hurtbox.set_deferred("monitorable",false)
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	var face:Vector2 = wall_face_point(entry_slot)
	_wall_visual(false,face,_slot_normal(entry_slot),global_position)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _wall_visual.rpc(false,face,_slot_normal(entry_slot),global_position)
	wt_sound(&"stone_break",0.0,face)

func choose_exit_slot() -> Dictionary:
	var slots:Array[Dictionary] = WALL.wall_slots(get_tree().current_scene,mc_arena_rect())
	return WALL.safest_slot(slots,threat_points(),Callable(self,&"resolve_exit_slot"),_mc_rng)

## Step out from the wall along its normal until the trader's whole body fits (tiles are 16 px,
## the body is taller), so he never emerges overlapping a wall or another character.
## The final point also keeps the whole drawn body out of the wall when that spot is clear, so the
## clip can be removed at the end without anything popping in.
func resolve_exit_slot(slot:Dictionary) -> Dictionary:
	var normal:Vector2 = _slot_normal(slot)
	var base:Vector2 = slot.get("floor",global_position)
	var face:Vector2 = wall_face_point(slot)
	var out_depth:float = body_reach(-normal)
	for step:float in [0.0,4.0,8.0,12.0,16.0,22.0]:
		var point:Vector2 = base + normal*step
		if mc_body_position_clear(point):
			var resolved:Dictionary = slot.duplicate()
			var short:float = out_depth - (point - face).dot(normal)
			if short > 0.0 and mc_body_position_clear(point + normal*short): point += normal*short
			resolved["floor"] = point
			return resolved
	return {}

## Where his walk-out line (same angle as the walk-in) crosses the exit wall surface.
func exit_cross_point(slot:Dictionary) -> Vector2:
	var normal:Vector2 = _slot_normal(slot)
	var face:Vector2 = wall_face_point(slot)
	var end:Vector2 = slot.get("floor",face)
	var dir:Vector2 = normal.rotated(_wall_walk_angle)
	return end - dir*((end - face).dot(normal)/maxf(dir.dot(normal),0.05))

## Exit tell: the exit is locked now, and its wall surface cracks (stone chips in pulses + a
## stone hit) for wall_exit_warning seconds before he walks out of it.
func _warn_exit() -> void:
	_exit_warned = true
	exit_slot = choose_exit_slot()
	if exit_slot.is_empty(): exit_slot = entry_slot
	if exit_slot.is_empty(): return
	exit_warnings += 1
	var face:Vector2 = exit_cross_point(exit_slot)
	var normal:Vector2 = _slot_normal(exit_slot)
	_exit_warning_visual(face,normal,wall_exit_warning)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _exit_warning_visual.rpc(face,normal,wall_exit_warning)
	wt_sound(&"stone_hit",-3.0,face)

@rpc("authority","call_remote","reliable")
func _exit_warning_visual(face:Vector2,normal:Vector2,duration:float) -> void:
	var dir:Vector2 = normal if normal != Vector2.ZERO else Vector2.UP
	var tangent:Vector2 = dir.orthogonal()
	var pulses:int = 3
	var source:Dictionary = CRUMBS.wall_source(self,face,dir)
	var tween:Tween = create_tween()
	for i:int in range(pulses):
		var spread:float = 8.0 + 5.0*i
		tween.tween_callback(func() -> void:
			for side:float in [-1.0,0.0,1.0]:
				CRUMBS.spawn(self,face + tangent*side*spread,source,6 + 3*i,dir,50.0 + 15.0*i,3.0,0.55,1.2,false,1.5))
		tween.tween_interval(duration/float(pulses))

func _begin_emerge() -> void:
	if exit_slot.is_empty() or not _exit_warned: exit_slot = choose_exit_slot()
	if exit_slot.is_empty(): exit_slot = entry_slot
	var face:Vector2 = wall_face_point(exit_slot)
	var normal:Vector2 = _slot_normal(exit_slot)
	# Out at the same angle he went in and at the same (normal) speed; he keeps moving that way.
	exit_direction = normal.rotated(_wall_walk_angle)
	var end:Vector2 = exit_slot.floor
	var depth:float = maxf((end - face).dot(normal) + body_reach(normal) + 1.0,0.0)
	var distance:float = depth/maxf(exit_direction.dot(normal),0.05)
	var start:Vector2 = end - exit_direction*distance
	global_position = start
	_begin_phase(Phase.EMERGING,start,end,minf(distance/maxf(_wall_walk_speed,1.0),wall_walk_time_max))
	# Clip first, then show: he appears fully inside the wall and walks out through its surface.
	_wall_clip_state(true,face,normal)
	var cross:Vector2 = exit_cross_point(exit_slot)
	_wall_visual(true,cross,normal,start)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_wall_clip_state.rpc(true,face,normal)
		_wall_visual.rpc(true,cross,normal,start)
	wt_sound(&"stone_hit",0.0,cross)
	wt_sound(&"trader_reappeared")
	_bring_back_llama(start,exit_slot.floor,_phase_duration,face,normal)

## First slot whose llama is dead and whose return cooldown is over.
func due_llama_slot() -> int:
	for i:int in range(mini(llama_count,_llama_return_wait.size())):
		if _llama(i) == null and _llama_return_wait[i] <= 0.0: return i
	return -1

## A due llama walks out of the wall beside him (same time, same clip), leashed once they are out.
func _bring_back_llama(from:Vector2,to:Vector2,duration:float,face:Vector2,normal:Vector2) -> void:
	_returning_llama = -1
	var index:int = due_llama_slot()
	if index < 0 or not is_multiplayer_authority(): return
	var tangent:Vector2 = normal.orthogonal()
	var side:float = -1.0 if index % 2 == 0 else 1.0
	var llama:ball = _spawn_llama(index)
	if llama == null: return
	var target:Vector2 = to
	for offset:float in [side*18.0,-side*18.0,side*30.0,-side*30.0]:
		if llama.mc_body_position_clear(to + tangent*offset):
			target = to + tangent*offset
			break
	var start:Vector2 = from + (target - to)
	llama.call(&"wt_begin_emerge",start,target,duration,face,normal)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _llama_clip_remote.rpc(index,true,face,normal)
	_returning_llama = index
	_llama_return_wait[index] = 0.0
	llamas_returned += 1

## Relayed through the trader: the replicated llama may arrive a few frames after this rpc.
@rpc("authority","call_remote","reliable")
func _llama_clip_remote(index:int,active:bool,face:Vector2,normal:Vector2) -> void:
	for attempt:int in range(20):
		var llama:Node = _llama(index)
		if llama != null and llama.has_method(&"emerge_clip"):
			llama.call(&"emerge_clip",active,face,normal)
			return
		await get_tree().process_frame
		if not is_instance_valid(self) or not is_inside_tree(): return

func _finish_wall() -> void:
	if not exit_slot.is_empty(): global_position = exit_slot.floor
	wall_phase = Phase.NONE
	var layer:int = _saved_layer
	var mask:int = _saved_mask
	if _saved_while_invisible and not is_invisible():
		layer |= 2
		mask |= 2
	collision_layer = layer
	collision_mask = mask
	remove_meta(&"ignore_combat_targeting") if has_meta(&"ignore_combat_targeting") else null
	remove_meta(&"ignore_combat_locking") if has_meta(&"ignore_combat_locking") else null
	remove_meta(&"submission_allow_map_escape") if has_meta(&"submission_allow_map_escape") else null
	_wall_clip_state(false,Vector2.ZERO,Vector2.UP)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _wall_clip_state.rpc(false,Vector2.ZERO,Vector2.UP)
	if self_hurtbox != null: self_hurtbox.set_deferred("monitorable",true)
	if self_hitbox != null and has_collision_damage(): self_hitbox.set_deferred("monitoring",true)
	_wall_fade(1.0)
	_wall_wait = wall_cooldown
	if exit_direction != Vector2.ZERO: direction = exit_direction
	if _returning_llama >= 0:
		var back:Node = _llama(_returning_llama)
		if back != null and back.has_method(&"wt_finish_emerge"): back.call(&"wt_finish_emerge")
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _llama_clip_remote.rpc(_returning_llama,false,Vector2.ZERO,Vector2.UP)
		_returning_llama = -1
	_set_leash_active(true)
	if items_enabled and health > 0 and is_combat_runtime_active(): roll_item()
	if _pending_invisibility:
		_pending_invisibility = false
		if health > 0 and is_combat_runtime_active(): POTION_EFFECTS.apply_effect(self,"invisibility",self)

## Battle ended / runtime paused mid-skill: pop out at once instead of staying hidden.
func finish_wall_phase_now() -> void:
	if wall_phase == Phase.NONE: return
	if wall_phase != Phase.EMERGING:
		exit_slot = choose_exit_slot()
		if exit_slot.is_empty(): exit_slot = entry_slot
		var face:Vector2 = wall_face_point(exit_slot) if not exit_slot.is_empty() else global_position
		var target:Vector2 = exit_slot.get("floor",global_position)
		_wall_visual(true,face,_slot_normal(exit_slot),target)
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _wall_visual.rpc(true,face,_slot_normal(exit_slot),target)
	_finish_wall()

func _wall_fade(alpha:float) -> void:
	if image != null and is_instance_valid(image):
		var c:Color = image.self_modulate
		c.a = clampf(alpha,0.0,1.0)
		image.self_modulate = c

## point = wall surface (chips), at = the trader's position at that moment (peers snap to it so
## the clipped body never shows at a stale synced position).
@rpc("authority","call_remote","reliable")
func _wall_visual(show_unit:bool,point:Vector2,normal:Vector2,at:Vector2) -> void:
	if not is_multiplayer_authority(): global_position = at
	visible = show_unit
	# The wall's own block particles: crumbs cut from the wall tile's texture (vanilla terrain particles).
	var n:Vector2 = normal if normal != Vector2.ZERO else Vector2.UP
	var source:Dictionary = CRUMBS.wall_source(self,point,n)
	CRUMBS.spawn(self,point,source,28,n,75.0,3.0,0.75,1.25,false,4.0) # dark wall tiles: unshaded so they read
	wall_crumb_bursts += 1

# Hidden inside the wall: no damage, knockback or hit contacts reach him.
func is_hidden_in_wall() -> bool: return wall_phase == Phase.HIDDEN

func can_receive_hit_contact(_incoming:hitbox,_contact:hurtbox) -> bool:
	return not is_hidden_in_wall()

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if is_hidden_in_wall(): return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)

func receive_directional_damage(damage:float,source_position:Vector2,incoming_direction:Vector2 = Vector2.ZERO,ignore_block:bool = false) -> bool:
	if is_hidden_in_wall(): return false
	return super.receive_directional_damage(damage,source_position,incoming_direction,ignore_block)

func take_damage(damage:float,ignore_block:bool = false) -> void:
	if is_hidden_in_wall(): return
	super.take_damage(damage,ignore_block)

func apply_knockback(knockback_direction:Vector2,knockback_distance:float,knockback_speed:float = 700.0,wall_bounce_strength:float = 0.0,stun_duration:float = 0.0,options:Dictionary = {}) -> Node:
	if wall_phase != Phase.NONE: return null
	return super.apply_knockback(knockback_direction,knockback_distance,knockback_speed,wall_bounce_strength,stun_duration,options)

# ------------------------------------------------------------------ manual control
func controlled_attack_action() -> void:
	# Left click: invisibility potion (Witch's effect).
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active(): return
	if can_drink_invisibility(): start_drink(&"invisibility")

func controlled_skill_action() -> void:
	# Right click: enter the nearest wall.
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active(): return
	if _wall_wait <= 0.0: start_wall_phase()

func controlled_middle_action() -> void:
	# Middle click: milk, only while a negative effect is present (same rule as the AI).
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active(): return
	if _milk_wait <= 0.0 and has_negative_effect(): start_drink(&"milk")

func player_control_extra_actions() -> Array:
	return [&"controlled_item_action"]

func controlled_item_action() -> void:
	# Key 1: use the item in the frame now (slime ball toward the mouse aim).
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active(): return
	if wall_phase == Phase.NONE and not held_item.is_empty(): use_held_item(true)

# ------------------------------------------------------------------ items
## One random item per wall exit. 干草块 only while a llama is hurt, 马铃薯 only while he is hurt.
func roll_item() -> StringName:
	if not is_multiplayer_authority(): return &""
	var pool:Array[StringName] = []
	for kind:StringName in CATALOG.ALL:
		if kind == CATALOG.HAY and hay_target() == null: continue
		if kind == CATALOG.POTATO and health >= Max_health: continue
		pool.append(kind)
	if pool.is_empty(): return &""
	give_item(pool[_mc_rng.randi_range(0,pool.size() - 1)])
	items_rolled += 1
	return held_item

## Puts kind into the frame (replacing an unused one) and starts its trigger timer.
func give_item(kind:StringName) -> void:
	held_item = kind
	_item_hold = 0.0
	if kind == CATALOG.GUNPOWDER or kind == CATALOG.CACTUS: _item_wait = _mc_rng.randf_range(item_delay_min,item_delay_max)
	else: _item_wait = item_show_time
	_show_frame_item(kind)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _show_frame_item.rpc(kind)
	if not kind.is_empty(): wt_sound(&"item_frame_add",0.0,item_frame.global_position if item_frame != null else global_position)

@rpc("authority","call_remote","reliable")
func _show_frame_item(kind:StringName) -> void:
	held_item = kind
	if item_frame != null and is_instance_valid(item_frame): item_frame.call(&"show_item",kind)

## The frame hides with his body while he is behind a wall surface.
func frame_outside_wall(point:Vector2) -> bool:
	if wall_phase == Phase.HIDDEN or not visible: return false
	if _wall_clip == null or not is_instance_valid(_wall_clip) or not bool(_wall_clip.get(&"active")): return true
	return float(_wall_clip.call(&"side_of",point)) > 0.0

func _tick_item(delta:float) -> void:
	if held_item.is_empty() or health <= 0: return
	_item_hold += delta
	_item_wait -= delta
	match held_item:
		CATALOG.DRIPSTONE:
			# Placed by when_collide on the next wall he touches; floor spike if none in time.
			if _item_hold >= dripstone_hold_max: use_held_item()
		CATALOG.SLIME_BALL:
			if is_player_controlled() or _item_wait > 0.0: return
			if slime_target(true) != null or (_item_hold >= slime_hold_max and slime_target(false) != null): use_held_item()
		_:
			if _item_wait <= 0.0 and not use_held_item(): _item_wait = 0.3

## Uses the held item now. Returns false when it cannot be used yet (it stays in the frame).
func use_held_item(manual:bool = false) -> bool:
	var kind:StringName = held_item
	if kind.is_empty() or wall_phase != Phase.NONE or health <= 0: return false
	var used:bool = false
	match kind:
		CATALOG.GUNPOWDER:
			used = _place_item(kind,global_position,{}) != null
		CATALOG.BLUE_ICE:
			used = _place_item(kind,_inside_arena(global_position + _exit_inward()*14.0,16.0),{}) != null
		CATALOG.CACTUS:
			var spot:Variant = cactus_spot()
			used = spot is Vector2 and _place_item(kind,spot,{}) != null
		CATALOG.DRIPSTONE:
			var back:Vector2 = _behind(14.0)
			used = _place_item(kind,back,{"normal": Vector2.UP,"grace": get_instance_id()}) != null
		CATALOG.SLIME_BALL:
			used = throw_slime(manual)
		CATALOG.HAY:
			var llama:Node2D = hay_target()
			if llama == null:
				_item_used(kind) # nobody to feed any more: drop it
				return false
			used = _throw(kind,llama,llama.global_position,0.7)
		CATALOG.POTATO:
			used = start_drink(CATALOG.POTATO)
		CATALOG.PUFFERFISH,CATALOG.TROPICAL_FISH:
			used = release_fish(kind == CATALOG.PUFFERFISH) != null
	if used: _item_used(kind)
	return used

func _item_used(kind:StringName) -> void:
	items_used[kind] = int(items_used.get(kind,0)) + 1
	if held_item == kind:
		held_item = &""
		_show_frame_item(&"")
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _show_frame_item.rpc(&"")
		wt_sound(&"item_frame_remove",0.0,item_frame.global_position if item_frame != null else global_position)

func item_count(kind:StringName) -> int: return int(items_used.get(kind,0))

## Floor direction away from the exit wall (his walk-out direction as fallback).
func _exit_inward() -> Vector2:
	if not exit_slot.is_empty(): return _slot_normal(exit_slot)
	if direction.length_squared() > 0.000001: return direction.normalized()
	return Vector2.DOWN

func _behind(distance:float) -> Vector2:
	var heading:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	return _inside_arena(global_position - heading*distance,8.0)

func _inside_arena(point:Vector2,margin:float) -> Vector2:
	var rect:Rect2 = mc_arena_rect().grow(-margin)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0: return point
	return point.clamp(rect.position,rect.end)

## A free 14 px square behind / beside him for the cactus (never on a unit or wall).
func cactus_spot() -> Variant:
	var heading:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var box := RectangleShape2D.new()
	box.size = Vector2(15.0,15.0)
	for offset:Vector2 in [-heading*18.0,-heading*26.0,heading.orthogonal()*18.0,-heading.orthogonal()*18.0,-heading*34.0]:
		var point:Vector2 = _inside_arena(global_position + offset,9.0)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = box
		query.transform = Transform2D(0.0,point)
		query.collision_mask = 3
		query.collide_with_areas = false
		if get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return point
	return null

func _item_name(prefix:String) -> String:
	_item_serial += 1
	return "%s_%s%d" % [str(name),prefix,_item_serial]

func _place_item(kind:StringName,point:Vector2,extra:Dictionary) -> Node2D:
	if not PLACED_SCRIPTS.has(kind) or not is_inside_tree(): return null
	var node_name:String = _item_name("Item")
	var node:Node2D = _spawn_placed(kind,node_name,point,extra,true)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _spawn_placed_remote.rpc(kind,node_name,point,extra)
	return node

func _spawn_placed(kind:StringName,node_name:String,point:Vector2,extra:Dictionary,authority:bool) -> Node2D:
	var parent:Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	var node:Node2D = (PLACED_SCRIPTS[kind] as Script).new()
	node.name = node_name
	node.set(&"kind",kind)
	parent.add_child(node)
	node.call(&"setup",self,point,extra,authority)
	return node

@rpc("authority","call_remote","reliable")
func _spawn_placed_remote(kind:StringName,node_name:String,point:Vector2,extra:Dictionary) -> void:
	if PLACED_SCRIPTS.has(kind): _spawn_placed(kind,node_name,point,extra,false)

## Relays a gameplay moment of an item node (gunpowder trigger, slime hit) to remote copies.
func wt_item_event(node_name:String,event:StringName,point:Vector2 = Vector2.ZERO) -> void:
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _item_event_remote.rpc(node_name,event,point)

@rpc("authority","call_remote","reliable")
func _item_event_remote(node_name:String,event:StringName,point:Vector2) -> void:
	var parent:Node = get_tree().current_scene
	var node:Node = parent.get_node_or_null(NodePath(node_name)) if parent != null else null
	if node == null: return
	if node.has_method(&"remote_event"): node.call(&"remote_event",event,point)
	elif event == &"trigger" and node.has_method(&"trigger"): node.call(&"trigger")

## Nearest enemy for the slime ball (in range with a clear line when strict).
func slime_target(strict:bool) -> ball:
	var best:ball
	var distance:float = INF
	for raw:Node in get_tree().get_nodes_in_group(&"Ball"):
		if raw == self or not (raw is ball) or not wt_enemy(raw) or not (raw as ball).is_combat_lockable(): continue
		var unit:ball = raw as ball
		if unit.Type not in [Ball_Type.Ball,Ball_Type.Creature]: continue
		var d:float = global_position.distance_to(unit.global_position)
		if strict and (d > slime_range or not mc_line_clear(global_position,unit.global_position)): continue
		if d < distance:
			distance = d
			best = unit
	return best

func throw_slime(manual:bool) -> bool:
	var target:ball = slime_target(false)
	var aim:Vector2
	if manual and has_player_control_aim():
		aim = global_position + player_control_aim_direction(direction)*minf(slime_range,120.0)
		target = null
	elif target != null:
		var flight_guess:float = clampf(global_position.distance_to(target.global_position)/220.0,0.35,0.75)
		aim = target.global_position + target.velocity*flight_guess*0.8
	else:
		return false
	var flight:float = clampf(global_position.distance_to(aim)/220.0,0.35,0.75)
	return _throw(CATALOG.SLIME_BALL,target,aim,flight)

func _throw(kind:StringName,target:Node2D,aim:Vector2,flight:float) -> bool:
	var node_name:String = _item_name("Throw")
	var start:Vector2 = hand_point()
	THROWN.launch(self,kind,start,target,aim,true,flight,node_name)
	var path:String = str(target.get_path()) if target != null else ""
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _throw_remote.rpc(kind,start,path,aim,flight,node_name)
	wt_sound(&"item_throw",0.0,start)
	return true

@rpc("authority","call_remote","reliable")
func _throw_remote(kind:StringName,start:Vector2,target_path:String,aim:Vector2,flight:float,node_name:String) -> void:
	var target:Node2D = get_node_or_null(NodePath(target_path)) as Node2D if not target_path.is_empty() else null
	THROWN.launch(self,kind,start,target,aim,false,flight,node_name)

## The hurt llama with the lowest health share (null when none is hurt).
func hay_target() -> Node2D:
	var best:Node2D
	var share:float = 1.0
	for llama:Node in living_llamas():
		var ratio:float = float(llama.get(&"health"))/maxf(float(llama.get(&"Max_health")),1.0)
		if ratio < share:
			share = ratio
			best = llama as Node2D
	return best

func wt_hearts(point:Vector2) -> void:
	HEARTS.spawn(self,point,4)

## Eating: three bites with the vanilla eat sound and baked potato crumbs at the mouth.
func _eat_effects(duration:float) -> void:
	var tween:Tween = create_tween()
	for i:int in range(3):
		tween.tween_interval(duration*0.28)
		tween.tween_callback(func() -> void:
			if health <= 0: return
			wt_sound(&"item_eat",0.0)
			_eat_crumbs(to_global(Vector2(facing_sign()*11.0,-38.0))))
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _eat_crumbs_remote.rpc(duration)

func _eat_crumbs(point:Vector2) -> void:
	CRUMBS.spawn(self,point,CRUMBS.texture_source(CATALOG.icon(CATALOG.POTATO)),6,Vector2.DOWN,30.0,1.6,0.45,1.1,false,1.0)

@rpc("authority","call_remote","reliable")
func _eat_crumbs_remote(duration:float) -> void:
	var tween:Tween = create_tween()
	for i:int in range(3):
		tween.tween_interval(duration*0.28)
		tween.tween_callback(func() -> void: _eat_crumbs(to_global(Vector2(facing_sign()*11.0,-38.0))))

## 河豚 / 热带鱼 out of the bucket beside him; at most fish_max_each of each kind (oldest dries out).
func release_fish(puffer:bool) -> ball:
	if not is_multiplayer_authority() or not is_inside_tree(): return null
	var mine:Array[Node] = []
	for fish:Node in get_tree().get_nodes_in_group(&"MCTraderFish"):
		if fish.get(&"Master") == self and bool(fish.get(&"puffer")) == puffer and float(fish.get(&"health")) > 0.0: mine.append(fish)
	while mine.size() >= maxi(fish_max_each,1):
		var oldest:Node = mine.pop_front()
		if oldest.has_method(&"owner_lost"): oldest.call(&"owner_lost")
	var scene:PackedScene = load(CATALOG.PUFFERFISH_SCENE_PATH if puffer else CATALOG.TROPICAL_FISH_SCENE_PATH) as PackedScene
	if scene == null: return null
	var fish:ball = scene.instantiate()
	_fish_serial += 1
	fish.name = "%s_Fish%d" % [str(name),_fish_serial]
	fish.Master = self
	fish.Master_name = str(get_path())
	fish.Team = Team
	var side:float = facing_sign()
	fish.direction = Vector2(side,0.0)
	fish.set_multiplayer_authority(get_multiplayer_authority())
	var parent:Node = get_parent() if get_parent() != null else get_tree().current_scene
	parent.add_child(fish,true)
	var wanted:Vector2 = global_position + Vector2(side*14.0,-4.0)
	fish.global_position = wanted if fish.call(&"mc_body_position_clear",wanted) else TOOLS.safe_spawn_position(self,wanted,14.0)
	fish.add_to_group(&"BattleTransient")
	fish_released += 1
	wt_sound(&"item_empty_fish",0.0)
	return fish

func wt_on_fish_lost(_fish:Node) -> void: pass

## §1 hit feedback for item damage (played at the victim, synced to peers).
func wt_hit_sound(actual:float,point:Vector2) -> AudioStreamPlayer2D:
	if not is_finite(actual) or actual <= 0.0: return null
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _wt_hit_sound_remote.rpc(actual,point)
	return _wt_hit_sound_local(actual,point)

@rpc("authority","call_remote","reliable")
func _wt_hit_sound_remote(actual:float,point:Vector2) -> void:
	_wt_hit_sound_local(actual,point)

func _wt_hit_sound_local(actual:float,point:Vector2) -> AudioStreamPlayer2D:
	var player:AudioStreamPlayer2D = HIT_AUDIO.play(self,HIT_GAIN.damage_event(actual),point,HIT_GAIN.damage_gain(actual),false,true,true,true)
	if is_instance_valid(player):
		player.set_meta(&"mc_damage_source",get_instance_id())
		player.set_meta(&"mc_actual_damage",actual)
	return player
