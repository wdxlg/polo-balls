extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## 流浪商人 (Wandering Trader). Rules, numbers and sources: docs/WANDERING_TRADER.md.
## * Comes with two trader llamas (scenes/creatures/流浪商人_羊驼.tscn), each on a 缰绳.
##   Llamas are killable summons (Master = trader): no respawn, no victory weight, leash removed
##   when one dies, and they despawn with the trader.
## * 牛奶: only while a negative effect is present; clears all negative effects exactly like the
##   copper sword (ball.cleanse_negative_effects / classes/status_cleansing.gd). Long cooldown.
## * 隐身药水: the Witch's own invisibility (女巫药水效果.apply_effect(self,"invisibility",self)).
## * 入墙: walks straight into the nearest map wall; the body is clipped on the wall surface, so it
##   vanishes only once it is completely inside (leashes snap). He then pushes straight out of the
##   safest wall slot (farthest from enemies, body-clear floor), again clipped, and the leashes
##   reconnect. No fading.
const AUDIO = preload("res://scripts/characters/我的世界/wandering_trader/audio.gd")
const VISUAL = preload("res://scripts/characters/我的世界/wandering_trader/visual.gd")
const LEASH = preload("res://scripts/characters/我的世界/wandering_trader/leash.gd")
const WALL = preload("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
const WALL_CLIP = preload("res://scripts/characters/我的世界/wandering_trader/wall_clip.gd")
const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const STATUS_EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const LLAMA_SCENE_PATH:String = "res://scenes/creatures/流浪商人_羊驼.tscn"
const STATUS_CLEANSING_PATH:String = "res://classes/status_cleansing.gd"
const STONE_COLOR := Color(0.49,0.49,0.49)
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
@export var wall_entry_speed:float = 150.0
@export var wall_entry_time_max:float = 1.4
@export var wall_emerge_time:float = 0.3 # minimum; the real time follows the walk-out distance
@export var drink_move_ratio:float = 0.35

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
var _wall_clip:Node
var _item_anchor:Node2D
var _item_sprite:Sprite2D
var _item_tween:Tween

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	mc_audio_role = "wandering_trader"
	super._ready()
	visual = VISUAL.attach(self,&"trader")
	_setup_item_visual()
	_invisibility_wait = invisibility_first_delay
	_wall_wait = wall_first_delay
	for i:int in range(llama_count):
		_llama_refs.append(null)
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
	var scene:PackedScene = load(LLAMA_SCENE_PATH) as PackedScene
	var parent:Node = get_parent() if get_parent() != null else get_tree().current_scene
	for i:int in range(llama_count):
		if _llama(i) != null: continue
		var llama:ball = scene.instantiate()
		llama.name = llama_name(i)
		llama.Master = self
		llama.Master_name = str(get_path())
		llama.Team = Team
		llama.set_multiplayer_authority(get_multiplayer_authority())
		parent.add_child(llama,true)
		var side:float = -16.0 if i % 2 == 0 else 16.0
		var wanted:Vector2 = global_position + Vector2(side,5.0)*absf(global_scale.x)/0.2
		llama.global_position = wanted if llama.mc_body_position_clear(wanted) else TOOLS.safe_spawn_position(self,wanted,18.0)
		_register_llama(i,llama)

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
		return
	super.tick_physics(state,delta)
	if health <= 0 or not is_combat_runtime_active(): return
	_since_hurt += delta
	_milk_wait -= delta
	_invisibility_wait -= delta
	_wall_wait -= delta
	if _drink_left > 0.0:
		_drink_left -= delta
		if _drink_left <= 0.0: _finish_drink()
		return
	if dizziness or is_damage_output_disabled(): return
	_negative_check_wait -= delta
	if _milk_wait <= 0.0 and _negative_check_wait <= 0.0:
		_negative_check_wait = 0.2
		if has_negative_effect():
			start_drink(&"milk")
			return
	if is_player_controlled(): return
	var threat:float = nearest_threat_distance()
	if _wall_wait <= 0.0 and (threat <= wall_threat_radius or (_since_hurt < 0.8 and health < Max_health*0.6)):
		if start_wall_phase(): return
	if _invisibility_wait <= 0.0 and not is_invisible() and (threat <= invisibility_threat_radius or _since_hurt < 1.0):
		start_drink(&"invisibility")

func move(speed:float,delta:float) -> void:
	super.move(speed*(drink_move_ratio if _drink_left > 0.0 else 1.0),delta)

func _process(delta:float) -> void:
	if _drink_visual_left > 0.0:
		_drink_visual_left -= delta
		if _drink_visual_left <= 0.0: _finish_drink_visual()
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
	if _drink_left > 0.0 or wall_phase != Phase.NONE or health <= 0: return false
	_drink_kind = kind
	if kind == &"milk":
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
	if kind == &"milk":
		last_cleansed = cleanse_with_milk()
		VISUAL.burst(self,global_position + Vector2(0.0,-4.0),Color(1.0,1.0,1.0),12,36.0,1.3,0.5)
	elif kind == &"invisibility":
		POTION_EFFECTS.apply_effect(self,"invisibility",self)

@rpc("authority","call_remote","reliable")
func _show_drink_visual(kind:StringName,duration:float) -> void:
	_drink_visual_left = duration
	if _item_sprite == null: return
	_item_sprite.texture = VISUAL.item_texture(kind)
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
func start_wall_phase() -> bool:
	if wall_phase != Phase.NONE or _drink_left > 0.0 or health <= 0 or not is_multiplayer_authority(): return false
	var slots:Array[Dictionary] = WALL.wall_slots(get_tree().current_scene,mc_arena_rect())
	if slots.is_empty(): return false
	entry_slot = WALL.nearest_slot(slots,global_position)
	if entry_slot.is_empty(): return false
	wall_entries += 1
	_wall_wait = wall_cooldown + wall_hidden_time + wall_entry_time_max + wall_emerge_time
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	_saved_while_invisible = is_invisible()
	collision_layer = 0
	collision_mask = 0
	set_meta(&"ignore_combat_locking",true)
	# The body really goes past the map edge; World's squeeze rescue / out-of-bounds kill skip it.
	set_meta(&"submission_allow_map_escape",true)
	var face:Vector2 = wall_face_point(entry_slot)
	var normal:Vector2 = _slot_normal(entry_slot)
	var target:Vector2 = inside_wall_point(face,normal)
	var travel:float = global_position.distance_to(target)
	_begin_phase(Phase.ENTERING,global_position,target,clampf(travel/maxf(wall_entry_speed,1.0),0.25,wall_entry_time_max))
	_wall_clip_state(true,face,normal)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _wall_clip_state.rpc(true,face,normal)
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
			if _phase_time >= wall_hidden_time: _begin_emerge()
		Phase.EMERGING:
			global_position = _phase_from.lerp(_phase_to,k)
			if k >= 1.0: _finish_wall()

## The surface he visibly walks into: the physical wall (layer 1, World's bounce walls) found by
## a ray from the slot's floor tile against the normal. On maps whose border ring tiles are
## walkable (e.g. Map10x10) this is the arena edge, not the tile seam. Lateral position stays on
## the slot. Falls back to the tile seam when nothing is hit.
func wall_face_point(slot:Dictionary) -> Vector2:
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

## Start of the walk-out: straight behind the exit point, body completely inside the wall.
func exit_start_point(slot:Dictionary) -> Vector2:
	var normal:Vector2 = _slot_normal(slot)
	var face:Vector2 = wall_face_point(slot)
	var end:Vector2 = slot.get("floor",face)
	var on_face:Vector2 = end - normal*(end - face).dot(normal)
	return inside_wall_point(on_face,normal)

func _begin_emerge() -> void:
	exit_slot = choose_exit_slot()
	if exit_slot.is_empty(): exit_slot = entry_slot
	var face:Vector2 = wall_face_point(exit_slot)
	var normal:Vector2 = _slot_normal(exit_slot)
	var start:Vector2 = exit_start_point(exit_slot)
	global_position = start
	var travel:float = start.distance_to(exit_slot.floor)
	_begin_phase(Phase.EMERGING,start,exit_slot.floor,clampf(travel/maxf(wall_entry_speed,1.0),wall_emerge_time,wall_entry_time_max))
	# Clip first, then show: he appears fully inside the wall and walks out through its surface.
	_wall_clip_state(true,face,normal)
	_wall_visual(true,face,normal,start)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_wall_clip_state.rpc(true,face,normal)
		_wall_visual.rpc(true,face,normal,start)
	wt_sound(&"stone_hit",0.0,face)
	wt_sound(&"trader_reappeared")

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
	_set_leash_active(true)

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
	if not show_unit: _finish_drink_visual()
	VISUAL.burst(self,point,STONE_COLOR,18,70.0,1.6,0.6,normal if normal != Vector2.ZERO else Vector2.UP)
	VISUAL.burst(self,point,Color(0.62,0.62,0.62),8,40.0,1.0,0.45,normal if normal != Vector2.ZERO else Vector2.UP)

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
	if _invisibility_wait <= 0.0 and not is_invisible(): start_drink(&"invisibility")

func controlled_skill_action() -> void:
	# Right click: enter the nearest wall.
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active(): return
	if _wall_wait <= 0.0: start_wall_phase()

func controlled_middle_action() -> void:
	# Middle click: milk, only while a negative effect is present (same rule as the AI).
	if not is_player_controlled() or not is_multiplayer_authority() or not is_combat_runtime_active(): return
	if _milk_wait <= 0.0 and has_negative_effect(): start_drink(&"milk")
