extends "res://scripts/characters/我的世界/new5/base.gd"
## 附魔台：书本按固定周期开合。合上时获得 25% 免伤（Damage_reduction Buff）；翻开时失去免伤，
## 每次攻击冷却在书周围一定范围内生成一枚原版附魔符文，飞向最近的敌人或友军（含召唤物）。
## 符文命中敌人造成低伤害（走公共 hitbox / 投射物附魔），命中友军回复等量生命。
## 每个目标对每张附魔台各有一个计数，显示在目标左上角（罗马数字 I–X）；到 X 时清零并按
## mc_enchant_support.gd::pool_for(目标) 随机一个对该目标真实生效的附魔：友军 +1 级、敌人 -1 级，
## 用 mc_enchantments.gd::add 叠加（正负相互抵消，到 0 移除），本场战斗内永久。
const RUNE_SCENE:PackedScene = preload("res://scenes/shooter/我的世界/附魔符文.tscn")
const TABLE_AUDIO = preload("res://scripts/characters/我的世界/enchanting_table/enchanting_table_audio.gd")
const STONE_AUDIO = preload("res://scripts/characters/我的世界/useless_stones/useless_stones_audio.gd")
const COUNTER_OVERLAY = preload("res://scripts/characters/我的世界/enchanting_table/enchant_counter_overlay.gd")
const SUPPORT = preload("res://scripts/effects/我的世界/mc_enchant_support.gd")
const ENCHANTS = preload("res://scripts/effects/我的世界/mc_enchantments.gd")
const BLOCK_FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
const SCENE_PATH:String = "res://scenes/characters/我的世界/附魔台.tscn"
const TABLE_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/enchanting_table/table_block.png")
const BOOK_OPEN:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/enchanting_table/book_open_0.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_open_1.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_open_2.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_open_3.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_open_4.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_open_5.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_open_6.png"),
]
const BOOK_FLIP:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_0.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_1.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_2.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_3.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_4.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_5.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_6.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_flip_7.png"),
]
const BOOK_SPIN:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_0.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_1.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_2.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_3.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_4.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_5.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_6.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_7.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_8.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_9.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_10.png"),
	preload("res://Images/characters/我的世界/enchanting_table/book_spin_11.png"),
]
const GUARD_BUFF_KEY:String = "附魔台_合书免伤"
## 书在 table_block.png 里的位置（贴图像素，相对贴图中心）：桌面中心上方 0.85 格，
## 同一 yaw 30 / pitch 25 正交投影（4.25 px/方块像素）。
const BOOK_ANCHOR:Vector2 = Vector2(0.0,-17.4)

@export_category("附魔台 / 书本周期")
@export var closed_time:float = 4.0
@export var open_time:float = 6.0
@export_range(0.0,0.95,0.01) var closed_damage_reduction:float = 0.25
## 开合动画时长（包含在周期内，只影响画面）。
@export var book_turn_time:float = 0.35
@export_category("附魔台 / 符文")
@export var attack_range:float = 520.0
## 符文出生在书周围这个半径内（角色单位 1 时的世界像素，随根缩放）。
@export var rune_spawn_radius:float = 34.0
@export var rune_speed:float = 120.0
## 略微追踪：每秒最多转向的弧度。
@export var rune_turn_rate:float = 1.4
## 自动射出的符文初始方向在朝向目标的基础上随机偏转（弧度），配合略微追踪画出弧线。
@export var rune_spread:float = 0.6
@export var rune_life:float = 5.5
@export var rune_hover_time:float = 0.25
## 命中友军的回复量 = 当前攻击力 × 该倍率。
@export var rune_heal_ratio:float = 1.0
@export var hits_per_enchant:int = 10
@export_category("附魔台 / 声音")
@export var footstep_base_interval:float = 0.42
@export var footstep_volume_db:float = -8.0

var book_open:bool = false
var phase_left:float = 4.0
var runes_fired:int = 0
var enchants_granted:int = 0
## instance id -> {"ref":WeakRef,"count":int}（权威端）；客户端只存显示用的计数。
var counters:Dictionary = {}
var _shot_left:float = 0.0
var _rune_serial:int = 0
var _manual_request:bool = false
var _book:Sprite2D
var _book_amount:float = 0.0
var _book_clock:float = 0.0
var _overlay:Node2D
var _break_done:bool = false
var _landed_sound_done:bool = false
var _hit_sound_gap:float = 0.0
var _footstep_cadence = FOOTSTEP.new()

func get_preview_texture() -> Texture2D: return TABLE_TEXTURE

func _ready() -> void:
	Hit_Audio = ""
	Unique_Death_Audio = null
	motion_blur_enabled = false
	motion_blur_effect_strength = 0.0
	motion_stretch_enabled = false
	AfterImage_Speed = 0.0
	super._ready()
	add_to_group(&"MCEnchantingTable")
	phase_left = closed_time
	_ensure_book()
	if is_multiplayer_authority(): call_deferred("_apply_guard",true)

func _ensure_book() -> void:
	if is_instance_valid(_book) or image == null: return
	_book = Sprite2D.new()
	_book.name = "附魔书"
	_book.texture = BOOK_SPIN[0]
	_book.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_book.position = BOOK_ANCHOR
	image.add_child(_book)

func overlay() -> Node2D:
	if is_instance_valid(_overlay) and _overlay.is_inside_tree(): return _overlay
	var parent:Node = get_parent()
	if not is_instance_valid(parent): return null
	_overlay = COUNTER_OVERLAY.new()
	_overlay.name = str(name)+"_附魔计数"
	_overlay.set("table_ref",weakref(self))
	parent.add_child(_overlay,true)
	return _overlay

# ---------------------------------------------------------------- 书本周期

func step_mob(delta:float) -> void:
	if not _landed_sound_done:
		_landed_sound_done = true
		_play_stone_sound(STONE_AUDIO.PLACE_SOUND,_voice_rng.randi_range(0,STONE_AUDIO.variant_count(STONE_AUDIO.PLACE_SOUND)-1),_voice_rng.randf_range(0.9,1.1))
	phase_left -= delta
	if phase_left <= 0.0: set_book_open(not book_open)
	_shot_left = maxf(_shot_left-delta,0.0)
	if not book_open or dizziness or is_damage_output_disabled() or not Can_Attack:
		_manual_request = false
		return
	if is_player_controlled():
		if _manual_request and _shot_left <= 0.0 and has_player_control_aim():
			_manual_request = false
			fire_rune(null,player_control_aim_world_position())
		return
	if _shot_left > 0.0: return
	var target:ball = nearest_rune_target()
	if target != null: fire_rune(target,ball.body_point(target,global_position))

func set_book_open(value:bool) -> void:
	if not is_multiplayer_authority(): return
	book_open = value
	phase_left = maxf(open_time if value else closed_time,0.05)
	_apply_guard(not value)
	if value: _shot_left = maxf(book_turn_time,0.0)
	_play_table_sound(TABLE_AUDIO.PAGE_TURN if value else TABLE_AUDIO.BOOK_PUT,_voice_rng.randi_range(0,8),global_position)

## 合书免伤用 Damage_reduction 加法 Buff（与药水抗性等叠加，正面效果不被净化）。
func _apply_guard(enabled:bool) -> void:
	var world:Node = get_tree().current_scene if is_inside_tree() else null
	if world == null or not world.has_method("new_buff"): return
	if enabled and health > 0:
		world.call("new_buff",self,self,GUARD_BUFF_KEY,Buff.new(0,INF,Buff.Buff_types.Damage_reduction,closed_damage_reduction,Buff.Algorithms.add))
	else:
		world.call("new_buff",self,self,GUARD_BUFF_KEY,Buff.new(),"delete")
	if world.has_method("refresh_runtime_buffs"): world.call("refresh_runtime_buffs",self)

func has_closed_guard() -> bool:
	return (Buff_Dic.get(get_instance_id(),{}) as Dictionary).has(GUARD_BUFF_KEY)

# ---------------------------------------------------------------- 选目标与符文

func is_rune_ally(target:Variant) -> bool:
	if not is_instance_valid(target) or not (target is ball) or target == self: return false
	var unit:ball = target as ball
	if unit.is_queued_for_deletion() or unit.health <= 0 or not unit.is_combat_targetable(): return false
	if unit.Type not in [Ball_Type.Ball,Ball_Type.Creature]: return false
	return SubmissionCharacterTools.same_side(self,unit)

func is_rune_enemy(target:Variant) -> bool:
	if not is_instance_valid(target) or not (target is ball) or target == self: return false
	var unit:ball = target as ball
	if unit.is_queued_for_deletion() or unit.Type not in [Ball_Type.Ball,Ball_Type.Creature]: return false
	return SubmissionCharacterTools.is_enemy(self,unit)

## 最近的敌人或友军（自己除外），按身体最近点量距离。
func nearest_rune_target() -> ball:
	var result:ball = null
	var best:float = attack_range*attack_range
	for raw:Variant in SubmissionCharacterTools.targeting_candidates(self):
		if not is_rune_enemy(raw) and not is_rune_ally(raw): continue
		var node:ball = raw as ball
		if not node.is_combat_lockable(): continue
		var distance:float = global_position.distance_squared_to(ball.body_point(node,global_position))
		if distance <= best:
			best = distance
			result = node
	return result

func book_world_position() -> Vector2:
	if is_instance_valid(_book): return _book.global_position
	return image.to_global(BOOK_ANCHOR) if image != null else global_position

func fire_rune(target:ball,point:Vector2) -> bool:
	if not can_act() or not book_open or not point.is_finite(): return false
	var parent:Node = get_parent()
	if not is_instance_valid(parent): return false
	var center:Vector2 = book_world_position()
	var radius:float = rune_spawn_radius*_unit_scale()*sqrt(rng.randf())
	var start:Vector2 = center + Vector2.RIGHT.rotated(rng.randf()*TAU)*radius
	var aim:Vector2 = start.direction_to(point)
	if aim.is_zero_approx(): aim = Vector2.RIGHT
	# 近处目标偏转收窄，否则慢速小转向的符文会绕着目标打转。
	var spread:float = rune_spread*clampf((start.distance_to(point) - 30.0*_unit_scale())/(150.0*_unit_scale()),0.0,1.0)
	if target != null and spread > 0.0: aim = aim.rotated(rng.randf_range(-spread,spread))
	_rune_serial += 1
	runes_fired += 1
	var rune_name:String = str(name)+"_Rune_"+str(_rune_serial)
	var polarity:int = 0
	if target != null: polarity = 1 if is_rune_enemy(target) else -1
	var glyph:int = rng.randi_range(0,25)
	var shade:float = rng.randf()*0.35+0.65
	var target_path:NodePath = target.get_path() if target != null else NodePath()
	var damage:float = attack_damage()
	_spawn_rune(rune_name,start,aim,damage,polarity,target_path,glyph,shade)
	if multiplayer.has_multiplayer_peer(): _spawn_rune.rpc(rune_name,start,aim,damage,polarity,target_path,glyph,shade)
	_shot_left = maxf(Attack_Cooling,0.0)
	return true

@rpc("authority","call_remote","reliable")
func _spawn_rune(rune_name:String,start:Vector2,heading:Vector2,damage:float,polarity:int,target_path:NodePath,glyph:int,shade:float) -> void:
	var parent:Node = get_parent()
	if not is_instance_valid(parent) or parent.has_node(NodePath(rune_name)): return
	var rune:ball = RUNE_SCENE.instantiate()
	rune.name = rune_name
	rune.Master = self
	rune.Master_name = str(name)
	rune.Team = Team
	rune.Damage = maxi(int(round(damage)),1)
	rune.Speed = rune_speed
	rune.direction = heading
	rune.set("polarity",polarity)
	rune.set("heal_amount",maxf(damage*rune_heal_ratio,0.0))
	rune.set("life",rune_life)
	rune.set("hover_time",rune_hover_time)
	rune.set("turn_rate",rune_turn_rate)
	rune.set("glyph",glyph)
	rune.set("shade",shade)
	var target:Node = get_node_or_null(target_path) if not target_path.is_empty() else null
	if target is ball: rune.set("target_ref",weakref(target))
	rune.position = parent.to_local(start) if parent is Node2D else start
	rune.set_multiplayer_authority(get_multiplayer_authority())
	parent.add_child(rune,true)

func controlled_attack_action() -> void:
	if is_player_controlled() and is_multiplayer_authority(): _manual_request = true

func player_control_action_cancelled(index:int) -> void:
	if index == 0: _manual_request = false

func set_player_control_peer(peer_id:int) -> void:
	if peer_id != player_control_peer_id: _manual_request = false
	super.set_player_control_peer(peer_id)

# ---------------------------------------------------------------- 计数与附魔

## 符文对 target 生效（敌人：被接受的命中；友军：送达回复）后由符文回调。
func on_rune_landed(target:Variant) -> void:
	if not is_multiplayer_authority() or health <= 0 or is_queued_for_deletion(): return
	if not is_instance_valid(target) or not (target is ball) or (target as ball).health <= 0: return
	var unit:ball = target as ball
	var key:int = unit.get_instance_id()
	var entry:Dictionary = counters.get(key,{"ref":weakref(unit),"count":0})
	entry.count = int(entry.count) + 1
	if int(entry.count) >= maxi(hits_per_enchant,1):
		counters.erase(key)
		_sync_counter_everywhere(unit,0)
		grant_random_enchant(unit)
		return
	counters[key] = entry
	_sync_counter_everywhere(unit,int(entry.count))

func counter_of(target:Node) -> int:
	if not is_instance_valid(target): return 0
	return int((counters.get(target.get_instance_id(),{}) as Dictionary).get("count",0))

## 友军 +1、敌人 -1；池子只含对该目标真实生效的附魔，为空时本次不附魔。
func grant_random_enchant(target:ball) -> String:
	var pool:Array[String] = SUPPORT.pool_for(target)
	if pool.is_empty(): return ""
	var kind:String = pool[rng.randi_range(0,pool.size()-1)]
	var delta:int = -1 if is_rune_enemy(target) else 1
	var level:int = ENCHANTS.add(target,kind,delta)
	enchants_granted += 1
	_receive_enchant(target.get_path(),kind,delta,level)
	if multiplayer.has_multiplayer_peer(): _receive_enchant.rpc(target.get_path(),kind,delta,level)
	_play_table_sound(TABLE_AUDIO.ENCHANT,_voice_rng.randi_range(0,8),target.global_position)
	return kind

@rpc("authority","call_remote","reliable")
func _receive_enchant(target_path:NodePath,kind:String,delta:int,level:int) -> void:
	var target:Node = get_node_or_null(target_path)
	if not (target is ball): return
	if not is_multiplayer_authority():
		if level == 0: ENCHANTS.remove(target,kind)
		else:
			ENCHANTS.ensure(target)
			ENCHANTS.apply(target,kind,level)
			var component:Node = ENCHANTS._component(target)
			if component != null: component.set("show_live_tooltip",true)
	var layer:Node2D = overlay()
	if layer != null: layer.call("popup",target,kind,delta)

func _sync_counter_everywhere(target:ball,count:int) -> void:
	_receive_counter(target.get_path(),count)
	if multiplayer.has_multiplayer_peer(): _receive_counter.rpc(target.get_path(),count)

@rpc("authority","call_remote","reliable")
func _receive_counter(target_path:NodePath,count:int) -> void:
	var target:Node = get_node_or_null(target_path)
	if not (target is ball): return
	if not is_multiplayer_authority():
		if count <= 0: counters.erase(target.get_instance_id())
		else: counters[target.get_instance_id()] = {"ref":weakref(target),"count":count}
	var layer:Node2D = overlay()
	if layer != null: layer.queue_redraw()

# ---------------------------------------------------------------- 声音与表现

func _unit_scale() -> float:
	return absf(global_scale.x)/0.2 if global_scale.x != 0.0 else 1.0

func _play_table_sound(kind:int,index:int,point:Vector2) -> void:
	if not is_multiplayer_authority(): return
	var pitch:float = _voice_rng.randf_range(0.9,1.1) if kind == TABLE_AUDIO.ENCHANT else 1.0
	if multiplayer.has_multiplayer_peer(): _receive_table_sound.rpc(kind,index,point,pitch)
	_receive_table_sound(kind,index,point,pitch)

@rpc("authority","call_remote","reliable")
func _receive_table_sound(kind:int,index:int,point:Vector2,pitch:float) -> void:
	TABLE_AUDIO.play(self,kind,index,point,pitch)

func _play_stone_sound(kind:int,index:int,pitch_scale:float = 1.0,volume_db:float = NAN) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.has_multiplayer_peer(): _receive_stone_sound.rpc(kind,index,global_position,pitch_scale,volume_db)
	_receive_stone_sound(kind,index,global_position,pitch_scale,volume_db)

@rpc("authority","call_remote","reliable")
func _receive_stone_sound(kind:int,index:int,point:Vector2,pitch_scale:float,volume_db:float) -> void:
	STONE_AUDIO.play(self,kind,index,point,pitch_scale,{} if is_nan(volume_db) else {"volume_db":volume_db})

func move(speed:float,delta:float) -> void:
	var start:Vector2 = global_position
	super.move(speed,delta)
	_step_movement_audio(start,delta)

func stand(delta:float) -> void:
	var start:Vector2 = global_position
	super.stand(delta)
	_step_movement_audio(start,delta)

func _step_movement_audio(start:Vector2,delta:float) -> void:
	if not active() or dizziness or delta <= 0.0: return
	var moved:float = start.distance_to(global_position)
	if moved < 0.01: moved = 0.0
	if not _footstep_cadence.tick(moved,delta,FOOTSTEP.base_speed(self),footstep_base_interval): return
	_play_stone_sound(STONE_AUDIO.STEP_SOUND,_voice_rng.randi_range(0,STONE_AUDIO.variant_count(STONE_AUDIO.STEP_SOUND)-1),_voice_rng.randf_range(0.9,1.1),footstep_volume_db)

func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if amount <= 0.0 or health <= 0 or not is_multiplayer_authority(): return
	if Time.get_ticks_msec()*0.001 < _hit_sound_gap: return
	_hit_sound_gap = Time.get_ticks_msec()*0.001 + 0.1
	_play_stone_sound(STONE_AUDIO.HIT_SOUND,_voice_rng.randi_range(0,STONE_AUDIO.variant_count(STONE_AUDIO.HIT_SOUND)-1))

func Die() -> void:
	if is_multiplayer_authority() and not _break_done:
		_apply_guard(false)
		_play_stone_sound(STONE_AUDIO.BREAK_SOUND,_voice_rng.randi_range(0,STONE_AUDIO.variant_count(STONE_AUDIO.BREAK_SOUND)-1))
		if multiplayer.has_multiplayer_peer(): _shatter.rpc(absi(hash(str(name))))
		_shatter(absi(hash(str(name))))
	super.Die()

@rpc("authority","call_remote","reliable")
func _shatter(seed_value:int) -> void:
	if _break_done or image == null or not is_inside_tree(): return
	_break_done = true
	BLOCK_FRAGMENTS.spawn_obstacle(image,{},{"max_pieces":16,"scatter_radius":14.0*_unit_scale(),"arc_height_min":5.0*_unit_scale(),"arc_height_max":13.0*_unit_scale(),"seed":seed_value})
	image.visible = false
	counters.clear()
	if is_instance_valid(_overlay): _overlay.queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(_overlay): _overlay.queue_free()
	_overlay = null
	super._exit_tree()

## 合书：原版闭合书缓慢自转；翻开：开书动画后循环翻页；合上时倒放开书。悬浮按原版正弦微浮。
func visual_mob() -> void:
	_ensure_book()
	if not is_instance_valid(_book): return
	var running:bool = is_combat_runtime_active() and health > 0
	var dt:float = get_process_delta_time() if running else 0.0
	_book_clock += dt
	var step:float = dt/maxf(book_turn_time,0.01)
	_book_amount = clampf(_book_amount + (step if book_open else -step),0.0,1.0)
	if _book_amount >= 1.0:
		_book.texture = BOOK_FLIP[int(_book_clock*10.0) % BOOK_FLIP.size()]
	elif _book_amount > 0.0:
		_book.texture = BOOK_OPEN[clampi(int(round(_book_amount*float(BOOK_OPEN.size()-1))),0,BOOK_OPEN.size()-1)]
	else:
		_book.texture = BOOK_SPIN[int(_book_clock*4.0) % BOOK_SPIN.size()]
	_book.position = BOOK_ANCHOR + Vector2(0.0,sin(_book_clock*2.0)*1.2)
	_book.visible = image.visible

func visual_state() -> Dictionary: return {"time":clock,"open":book_open}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	book_open = bool(data.get("open",book_open))

func get_debug_detection_regions() -> Array:
	if health <= 0 or not book_open or not Can_Attack or dizziness or is_damage_output_disabled(): return []
	return [{"shape":"circle","position":global_position,"radius":attack_range,"kind":"enchanting_rune_targeting"}]

func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_ENCHANTING_TABLE")
