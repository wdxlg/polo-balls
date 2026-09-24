extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const NATIVE_FEEDBACK = preload("res://scripts/effects/我的世界/mc16_native_feedback.gd")
var native_feedback:Node
const HAND_VISUAL = preload("res://scripts/effects/我的世界/trident_hand_visual.gd")
var hand_visual:Node2D
const TRIDENT = preload("res://scripts/effects/我的世界/三叉戟.gd")
const NETWORK = preload("res://scripts/effects/我的世界/trident_network.gd")
const ARC = preload("res://scripts/effects/我的世界/trident_arc.gd")
const LIGHTNING = preload("res://scripts/effects/我的世界/trident_lightning.gd")
const MC_ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const ENCHANTMENT = preload("res://scripts/effects/我的世界/trident_enchantment.gd")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
const IDLE_TEX = preload("res://Images/characters/我的世界/溺尸/溺尸.png")
@export_category("溺尸 / 忠诚三叉戟")
@export var trident_speed:float = 160.0
@export var trident_return_speed:float = 480.0
@export var trident_range:float = 600.0
@export var trident_damage_ratio:float = 0.5
@export var trident_refill_delay:float = 2.4
@export_category("溺尸 / 定时附魔")
@export_range(0.1,60.0,0.1) var held_enchant_delay:float = 5.0
@export_range(0.1,120.0,0.1) var stuck_enchant_delay:float = 12.0
@export_category("溺尸 / 引雷")
@export var lightning_first_delay:float = 0.6
@export var lightning_warning:float = 0.68
@export var lightning_interval:float = 4.0
@export var lightning_radius:float = 62.0
@export var lightning_damage_ratio:float = 1.4
@export var lightning_stun:float = 0.65
@export_category("溺尸 / 带电命中雷")
@export var impact_lightning_warning:float = 0.15
@export var impact_lightning_damage_ratio:float = 0.7
@export var impact_lightning_stun:float = 0.3
@export_category("溺尸 / 同队电网")
@export var network_interval:float = 2.0
@export var network_width:float = 3.0
@export var network_damage_ratio:float = 0.7
@export var network_stun:float = 0.28
@export var trident_throw_windup:float = 0.18
@export var trident_catch_duration:float = 0.36
var _catch_left:float = 0.0
var _throw_left:float = -1.0
var _throw_target:WeakRef
# 最近一次投掷实际瞄准的点（出手当帧敌人的当前坐标），供调试与回归测试读取。
var _throw_aim:Vector2 = Vector2.ZERO
var has_trident:bool = true
var _trident:Node2D
var _tridents:Dictionary = {}
var _serial:int = 0
var _refill_left:float = -1.0
var _sync_left:float = 0.0
var _refill_show_left:float = 0.0
func _ready() -> void:
	dir_left = true
	super._ready()
	native_feedback = NATIVE_FEEDBACK.attach(self,"drowned")
	hand_visual = HAND_VISUAL.new()
	hand_visual.name = "TridentHandVisual"
	hand_visual.unit = self
	add_child(hand_visual)
	register_hurt_shake_visual(hand_visual)
	add_to_group("MCDrowned")
	NETWORK.attach(get_tree().current_scene)
	if is_multiplayer_authority(): _new_trident()
func _get_hurt_shake_visual_parts() -> Array[Node2D]:
	var parts:Array[Node2D] = super._get_hurt_shake_visual_parts().duplicate()
	# The held enchantment mask/arcs are another top-level render layer.
	# Never shake flying/returning/lodged tridents or their electricity.
	if is_instance_valid(_trident) and _trident.flight_state==TRIDENT.Phase.HELD and is_instance_valid(_trident.charge_visual):
		parts.append(_trident.charge_visual)
	return parts

func get_preview_texture() -> Texture2D: return IDLE_TEX
func mc_ambient_event() -> String: return "ambient"
func mc_outgoing_impact_volume(actual:float) -> float:
	return preload("res://scripts/effects/我的世界/hit_audio_gain.gd").damage_gain(actual)
func trident_hit_damage() -> float: return attack_damage()*trident_damage_ratio
func trident_hand_position() -> Vector2:
	if is_instance_valid(mc_native_animation) and mc_native_animation.ready_visual and mc_native_animation.has_method("hand_world_position"):
		return mc_native_animation.hand_world_position()+HAND_VISUAL.HAND_LIFT
	return to_global(Vector2(18 if _visual_facing_flipped_h else -18,-8))+HAND_VISUAL.HAND_LIFT
func _create_trident(id:int) -> Node2D:
	var spear:Node2D = TRIDENT.new()
	spear.name = "LoyaltyTrident_"+str(id)
	spear.unit = self
	spear.serial = id
	add_child(spear)
	spear.global_position = trident_hand_position()
	_tridents[id] = spear
	return spear
func _new_trident() -> void:
	if not is_multiplayer_authority() or health<=0 or is_instance_valid(_trident): return
	_serial += 1
	_trident = _create_trident(_serial)
	has_trident = true
	if is_instance_valid(mc_native_animation): mc_native_animation.refresh_trident_pose()
	_refill_left = -1.0
	if _serial>1:
		_refill_show_left = 0.2
		_trident.begin_refill_pop()
		native_feedback.request("entity.experience_orb.pickup",trident_hand_position(),-9.0,0.0)
	hand_visual.sync_pose()
	_sync_left = 0.0
func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not mc_live() or Game.now_stop_state or get_tree().paused: return
	_advance_trident_catch(delta)
	_refill_show_left = maxf(_refill_show_left-maxf(delta,0.0),0.0)
	if _refill_left>=0.0:
		_refill_left -= delta
		if _refill_left<=0.0: _new_trident()
	_advance_trident_throw(delta)
	if not dizziness and has_trident and _throw_left<0.0:
		var target:ball = mc_nearest(delta)
		if GEOMETRY.enemy(self,target): throw_trident(target)
	_sync_left -= delta
	if multiplayer.has_multiplayer_peer() and _sync_left<=0.0:
		_sync_left = 0.07
		var data:Array = []
		for spear:Node in _tridents.values():
			if is_instance_valid(spear) and not spear.is_queued_for_deletion(): data.append(spear.snapshot())
		_sync_tridents.rpc(data,_refill_left,_refill_show_left,_catch_left)
func throw_trident(target:Variant) -> bool:
	if not mc_live() or Game.now_stop_state or dizziness or not has_trident or not is_instance_valid(_trident) or _refill_show_left>0.0 or _throw_left>=0.0: return false
	if not GEOMETRY.enemy(self,target): return false
	# Catch is visual recovery only: a valid new attack interrupts it immediately.
	_catch_left=0.0
	_throw_target=weakref(target)
	_throw_left=maxf(trident_throw_windup,0.01)
	if is_instance_valid(mc_native_animation): mc_native_animation.trigger_action(&"throw",_throw_left+0.2)
	if is_instance_valid(hand_visual): hand_visual.sync_pose()
	return true
func trident_last_aim_point() -> Vector2: return _throw_aim
func _advance_trident_throw(delta:float) -> void:
	if _throw_left<0.0 or not mc_live() or Game.now_stop_state or get_tree().paused or dizziness: return
	var target:Variant=_throw_target.get_ref() if _throw_target!=null else null
	if not is_instance_valid(_trident) or not has_trident or not GEOMETRY.enemy(self,target):
		_throw_left=-1.0; _throw_target=null
		if is_instance_valid(mc_native_animation): mc_native_animation.refresh_trident_pose()
		return
	_throw_left-=maxf(delta,0.0)
	if _throw_left>0.0: return
	_throw_left=-1.0; _throw_target=null
	# 出手当帧才读取敌人“当前坐标”：不用蓄力开始时的旧位置，也不做提前量预判。
	var origin:Vector2 = trident_hand_position()
	var aim:Vector2 = target.global_position
	var axis:Vector2 = origin.direction_to(aim)
	if axis.length_squared()<0.0001: axis = Vector2.RIGHT
	_throw_aim = aim
	# 出手点与瞄准点一起交给三叉戟；若出手点被挡回身体，会从新起点重新校正方向。
	_trident.launch(axis,origin,aim)
	native_feedback.request("item.trident.throw",origin,-6.0,0.04)
	_sync_left = 0.0
func _advance_trident_catch(delta:float) -> void:
	if not mc_live() or Game.now_stop_state or get_tree().paused or dizziness: return
	_catch_left=maxf(_catch_left-maxf(delta,0.0),0.0)
func catch_trident(spear:Node2D) -> void:
	if spear!=_trident or spear.is_queued_for_deletion(): return
	has_trident = true
	_catch_left=trident_catch_duration
	if is_instance_valid(mc_native_animation): mc_native_animation.trigger_action(&"catch",trident_catch_duration)
	if is_instance_valid(hand_visual): hand_visual.sync_pose()
	_sync_left = 0.0
func trident_stuck(spear:Node2D) -> void:
	if spear==_trident:
		_trident = null
		has_trident = false
		_refill_left = maxf(trident_refill_delay,0.1)
	# Lodged tridents remain until their owner or supporting wall is removed.
	_sync_left = 0.0
func trident_retired(spear:Node2D) -> void:
	_tridents.erase(spear.serial)
	if spear==_trident:
		_trident = null
		has_trident = false
		_refill_left = maxf(trident_refill_delay,0.1)
func on_mc_lightning_struck() -> void:
	if not mc_live() or Game.now_stop_state: return
	# Creeper body-hit compatibility: only the weapon actually in this hand.
	# No remote flying-weapon enchant or credit for an item that does not exist.
	if is_instance_valid(_trident) and _trident.flight_state==TRIDENT.Phase.HELD: _trident.charge()
func summon_trident_lightning(spear:Node2D,contact_hit:bool = false) -> void:
	if not mc_live() or Game.now_stop_state or not spear.charged: return
	var seed_value:int = _mc_rng.randi_range(1,2147483646)
	_show_trident_lightning(spear.serial,spear.global_position,seed_value,contact_hit)
	if multiplayer.has_multiplayer_peer(): _show_trident_lightning.rpc(spear.serial,spear.global_position,seed_value,contact_hit)
@rpc("authority","call_remote","reliable")
func _show_trident_lightning(id:int,point:Vector2,seed_value:int,contact_hit:bool = false) -> void:
	var anchor:Variant = _tridents.get(id)
	var parent_node:Node = anchor if is_instance_valid(anchor) else self
	var effect:Node2D = MC_ABILITIES.lightning(parent_node,point,seed_value,lightning_radius,impact_lightning_warning if contact_hit else lightning_warning,{
		"script":LIGHTNING,"name":"TridentLightning","fields":{"caster":self,"fixed_impact":contact_hit},
		"on_impact":_charge_drowned_in_bolt
	})
	if effect != null and is_multiplayer_authority(): effect.impact_started.connect(_strike_area.bind(contact_hit))
	# Direct hit is immediate; contact lightning warns for 0.15s at a frozen contact point.
func _charge_drowned_in_bolt(point:Vector2) -> void:
	# Query actual allied item positions, including held, flying and lodged tridents.
	ENCHANTMENT.in_radius(self,point,lightning_radius)
func _strike_area(point:Vector2,contact_hit:bool = false) -> void:
	if not mc_live() or Game.now_stop_state: return
	_charge_drowned_in_bolt(point)
	var ratio:float = impact_lightning_damage_ratio if contact_hit else lightning_damage_ratio
	var stun:float = impact_lightning_stun if contact_hit else lightning_stun
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not GEOMETRY.enemy(self,raw): continue
		if raw.global_position.distance_to(point)>lightning_radius+GEOMETRY.radius(raw): continue
		if mc_damage_with_impact(raw,attack_damage()*ratio,point) and is_instance_valid(raw) and raw.health>0:
			raw.apply_stun(stun)
func emit_trident_arc(a:Node,b:Node) -> void:
	if not mc_live() or Game.now_stop_state: return
	# Electrical links use a short native redstone fizz, NOT the impact thunder.
	# Merge edges per caster; decoded source length + silence prevents overlap.
	var wire_gap:float = native_feedback.BANK.EVENTS["block.redstone_torch.burnout"][0].get_length()+0.08
	native_feedback.request("block.redstone_torch.burnout",(a.global_position+b.global_position)*0.5,-10.0,wire_gap)
	var seed_value:int = _mc_rng.randi_range(1,2147483646)
	_show_trident_arc(a.unit.get_path(),a.serial,b.unit.get_path(),b.serial,a.global_position,b.global_position,seed_value)
	if multiplayer.has_multiplayer_peer(): _show_trident_arc.rpc(a.unit.get_path(),a.serial,b.unit.get_path(),b.serial,a.global_position,b.global_position,seed_value)
@rpc("authority","call_remote","reliable")
func _show_trident_arc(a_path:NodePath,a_id:int,b_path:NodePath,b_id:int,a:Vector2,b:Vector2,seed_value:int) -> void:
	var effect:Node2D = ARC.new()
	effect.name = "TridentArc"
	effect.caster = self
	effect.start = a
	effect.end = b
	effect.seed_value = seed_value
	var first_unit:Node = get_node_or_null(a_path)
	var second_unit:Node = get_node_or_null(b_path)
	var first:Variant = first_unit._tridents.get(a_id) if first_unit!=null else null
	var second:Variant = second_unit._tridents.get(b_id) if second_unit!=null else null
	if is_instance_valid(first): effect.first = weakref(first)
	if is_instance_valid(second): effect.second = weakref(second)
	add_child(effect,true)
@rpc("authority","call_remote","unreliable_ordered")
func _sync_tridents(data:Array,refill_left:float = -1.0,show_left:float = 0.0,catch_left:float = 0.0) -> void:
	_catch_left=clampf(catch_left,0.0,trident_catch_duration)
	var keep:Dictionary = {}
	var previous_held:bool = has_trident
	has_trident = false
	_trident = null
	_refill_left = maxf(refill_left,-1.0)
	_refill_show_left = clampf(show_left,0.0,0.2)
	for record:Dictionary in data:
		var id:int = int(record.id)
		keep[id] = true
		var spear:Variant = _tridents.get(id)
		if not is_instance_valid(spear): spear = _create_trident(id)
		spear.receive(record)
		if spear.flight_state!=TRIDENT.Phase.STUCK: _trident = spear
		if spear.flight_state==TRIDENT.Phase.HELD: has_trident = true
	for id:Variant in _tridents.keys():
		if not keep.has(id):
			var spear:Node = _tridents[id]
			_tridents.erase(id)
			spear.queue_free()
	if previous_held!=has_trident and is_instance_valid(mc_native_animation):
		if has_trident and _catch_left>0.0: mc_native_animation.trigger_action(&"catch",_catch_left)
		else: mc_native_animation.refresh_trident_pose()
	if is_instance_valid(hand_visual): hand_visual.sync_pose()
