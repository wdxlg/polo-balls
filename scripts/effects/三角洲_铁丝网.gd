extends Node2D
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")

const WIRE_TEXTURE_PATH:String = "res://Images/characters/三角洲/盾狗/刺网.png"
const WIRE_SLOW_BUFF_NAME:String = "三角洲铁丝网减速"
const WIRE_BLEED_SCRIPT:Script = preload("res://scripts/status/剑客_流血.gd")
const WIRE_BLEED_NODE_NAME:StringName = &"DeltaWireBleedStatus"
const WIRE_BREAK_AUDIO_PATHS:Array[String] = [
	"res://audio/characters/三角洲/盾狗/刀片破坏1.MP3",
	"res://audio/characters/三角洲/盾狗/刀片破坏2.MP3",
	"res://audio/characters/三角洲/盾狗/刀片破坏3.MP3",
	"res://audio/characters/三角洲/盾狗/刀片破坏4.MP3",
]
const WIRE_DESTROY_AUDIO_PATH:String = "res://audio/characters/三角洲/盾狗/刀片破坏5.MP3"

@export var radius:float=58.0
@export var durability:float=12.0
@export var passive_decay_interval:float=2.2
@export var passive_decay:float=1.0
@export var attack_durability_damage:float=1.0
@export_range(0.05,1.0,0.05) var projectile_durability_multiplier:float=0.5
@export var durability_hit_cooldown:float=0.08

@export_category("铁丝网伤害与减速")
@export_range(0.05,1.0,0.01) var slow_ratio:float=0.52
@export var slow_refresh_duration:float=0.16
@export var enter_damage:float=7.0
@export var move_damage:float=5.0
@export var move_damage_distance:float=10.0
@export var wire_ignore_block:bool=true

@export_category("铁丝网流血")
@export_range(1,5,1) var bleed_stacks_per_move_hit:int=1
@export_range(1,5,1) var bleed_max_stacks:int=3
@export var bleed_duration:float=5.0
@export var bleed_action_damage_per_stack:float=1.0
@export var bleed_move_tick_interval:float=0.60
@export var bleed_move_damage_per_stack:float=1.0

@export_category("铁丝网视觉")
@export var visual_width:float=134.0
@export var durability_shake_distance:float=4.0
@export var durability_shake_time:float=0.12

@export_category("铁丝网耐久碎屑")
@export_range(1,12,1) var durability_debris_small_count:int=3
@export_range(4,28,1) var destroy_debris_small_count:int=13
@export_range(1,10,1) var destroy_debris_large_count:int=4
@export var debris_small_size_min:float=2.8
@export var debris_small_size_max:float=5.6
@export var debris_large_size_min:float=8.5
@export var debris_large_size_max:float=15.0
@export var debris_horizontal_speed_min:float=24.0
@export var debris_horizontal_speed_max:float=82.0
@export var debris_flight_time_min:float=0.72
@export var debris_flight_time_max:float=1.18
@export var debris_screen_bottom_margin:float=28.0

@export_category("铁丝网命中音效")
@export var hit_audio_repeat_delay:float=0.28

@export_category("铁丝网破坏音效")
@export var durability_break_audio_volume_db:float=0.0
@export var durability_break_audio_max_distance:float=760.0

var Team:String=""
var owner_ref:WeakRef
var _owner_assigned:bool=false
var _owner_break_queued:bool=false
var _final_break_started:bool=false

var _decay:float=0.0
var _damage_area:Area2D=null
var _attack_receiver:hurtbox=null
var _visual_sprite:Sprite2D=null
var _wire_texture:Texture2D=null
var _wire_texture_image:Image=null
var _shake_tween:Tween=null
var _durability_break_streams:Array[AudioStream]=[]
var _durability_destroy_stream:AudioStream=null

# id -> 上一物理帧世界坐标
var _inside:Dictionary={}
# id -> WeakRef(ball)
var _inside_targets:Dictionary={}
# id -> 自上次移动伤害后累计移动距离
var _move_distance_accum:Dictionary={}

var _projectile_seen:Dictionary={}
var _durability_hit_last_msec:Dictionary={}
var _hit_audio_last_msec:Dictionary={}


func setup(owner_node:Node,team:String)->void:
	owner_ref=weakref(owner_node)
	_owner_assigned=true
	Team=team

	# V80：刺网属于生成它的盾狗。盾狗被 queue_free/remove_child 时，
	# tree_exiting 只负责提出破坏请求；真正最终破坏 defer 到 owner 退树流程结束后执行。
	if owner_node!=null and is_instance_valid(owner_node):
		var exit_callable:=Callable(self,"_on_owner_tree_exiting")
		if not owner_node.tree_exiting.is_connected(exit_callable):
			owner_node.tree_exiting.connect(exit_callable,CONNECT_ONE_SHOT)


func _ready()->void:
	add_to_group("DeltaBarbedWire")
	add_to_group("BattleTransient")
	z_index=-1
	_load_durability_audio()
	_build_visual()
	_build_damage_area()
	_build_attack_receiver()


func _exit_tree()->void:
	for id in _inside_targets.keys():
		var target:=_target_from_ref(_inside_targets.get(id,null))
		if target!=null:
			_remove_wire_slow(target)

	_inside.clear()
	_inside_targets.clear()
	_move_distance_accum.clear()


func _physics_process(delta:float)->void:
	# V80：死亡不一定等到 owner 真正离树；普通 ball 会先进入 Die/0HP，随后才 queue_free。
	# 所以每个物理帧先检查 owner；死亡/删除统一请求“最终耐久破坏”，不允许静默 queue_free。
	if _owner_should_destroy_wire():
		_request_owner_break()
		return
	if _owner_break_queued:
		return

	_decay+=delta
	if _decay>=passive_decay_interval:
		_decay=0.0
		_damage_durability(passive_decay)
		if is_queued_for_deletion():
			return

	_process_character_range()
	_process_projectile_durability()


func _process_character_range()->void:
	var current_targets:Dictionary=_collect_targets_in_wire_range()
	var now_positions:Dictionary={}
	var now_refs:Dictionary={}

	for id_variant in current_targets.keys():
		var id:int=int(id_variant)
		var target:ball=current_targets[id] as ball
		if target==null or not is_instance_valid(target):
			continue

		var was_inside:bool=_inside.has(id)
		var previous_position:Vector2=(
			_inside.get(id,target.global_position) as Vector2
			if was_inside
			else target.global_position
		)

		now_positions[id]=target.global_position
		now_refs[id]=weakref(target)

		# 在范围内始终持续减速。
		_refresh_wire_slow(target)

		# 第一次真正进入危险范围：立即造成一次进入伤害。
		if not was_inside:
			_deal_wire_damage(target,enter_damage)
			_move_distance_accum[id]=0.0
			continue

		# V241：移动伤害只按“在网里实际移动了多少距离”结算，不再需要时间冷却。
		# 每累计 move_damage_distance，就造成一次完整伤害并叠流血。
		var moved:float=previous_position.distance_to(target.global_position)
		var accumulated:float=float(_move_distance_accum.get(id,0.0))+moved
		var step_distance:float=maxf(move_damage_distance,0.5)

		# 极端位移/拉扯一帧可能跨过多段距离；最多同帧结算3次，避免瞬移类机制一次爆死。
		var pulses:int=0
		while accumulated>=step_distance and pulses<3:
			var actually_hit:bool=_deal_wire_damage(target,move_damage)
			if actually_hit:
				_apply_wire_bleed(target)
			accumulated-=step_distance
			pulses+=1

		_move_distance_accum[id]=accumulated

	# 离开危险范围：立刻撤掉本刺网减速，并重置下一次进入判定。
	for old_id_variant in _inside_targets.keys():
		var old_id:int=int(old_id_variant)
		if now_refs.has(old_id):
			continue
		var old_target:=_target_from_ref(_inside_targets.get(old_id,null))
		if old_target!=null:
			_remove_wire_slow(old_target)
		_move_distance_accum.erase(old_id)
		_hit_audio_last_msec.erase(old_id)

	_inside=now_positions
	_inside_targets=now_refs


func _collect_targets_in_wire_range()->Dictionary:
	var result:Dictionary={}

	# 第一层：Godot真实Area2D重叠。
	if _damage_area!=null and is_instance_valid(_damage_area):
		for body:Node2D in _damage_area.get_overlapping_bodies():
			if body is ball:
				var physical_target:=body as ball
				if _valid_wire_target(physical_target):
					result[physical_target.get_instance_id()]=physical_target

	# 第二层稳定兜底：
	# Area2D重叠列表只在物理迭代更新，而且用户项目存在大规模物理优化/碰撞层动态调整。
	# 因此再按角色真实碰撞半径判断“角色身体是否进入radius圆”。
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:=node as ball
		if not _valid_wire_target(target):
			continue
		if _is_target_body_in_wire_range(target):
			result[target.get_instance_id()]=target

	return result


func _valid_wire_target(target:ball)->bool:
	if target==null or not is_instance_valid(target):
		return false

	# V244：刺网永远不能伤到自己的投掷者。
	# 训练场常见 Team=""，因此不能只依赖 Team 过滤，否则 owner 与敌人都是空Team时
	# owner 也会被当成有效目标。这里直接按 owner_ref 的真实实例排除。
	var owner_ball:=_owner_ball()
	if owner_ball!=null and target==owner_ball:
		return false

	if target.health<=0:
		return false

	# V242：与项目 World 公共索敌规则一致。
	# Team="" 不是“同队”，只有双方 Team 都非空且相等才跳过。
	if (
		not Team.is_empty()
		and not target.Team.is_empty()
		and target.Team==Team
	):
		return false
	if target.has_method("is_combat_targetable") and not bool(target.call("is_combat_targetable")):
		return false
	return true


func _is_target_body_in_wire_range(target:ball)->bool:
	var body_center:Vector2=target.global_position
	if (
		target.collision_shape_2d!=null
		and is_instance_valid(target.collision_shape_2d)
	):
		body_center=target.collision_shape_2d.global_position

	var body_radius:float=12.0
	if target.has_method("get_crowd_separation_radius_world"):
		body_radius=clampf(
			float(target.call("get_crowd_separation_radius_world")),
			6.0,
			40.0
		)

	# “进入范围”按身体边缘进入刺网危险圆计算，而不是要求角色中心进入58px。
	return global_position.distance_to(body_center)<=maxf(radius,1.0)+body_radius


func _build_damage_area()->void:
	var area:=Area2D.new()
	area.name="DamageArea"
	area.collision_layer=0
	area.collision_mask=2
	area.monitoring=true
	area.monitorable=false
	add_child(area)

	var collision:=CollisionShape2D.new()
	collision.name="CollisionShape2D"
	var circle:=CircleShape2D.new()
	circle.radius=maxf(radius,1.0)
	collision.shape=circle
	area.add_child(collision)

	_damage_area=area


func contains_ball(target:ball)->bool:
	if target==null or not is_instance_valid(target):
		return false
	return _is_target_body_in_wire_range(target)


func _refresh_wire_slow(target:ball)->void:
	if target==null or not is_instance_valid(target):
		return

	var ratio:float=clampf(slow_ratio,0.05,1.0)
	target.velocity*=ratio

	var world:Node=get_tree().current_scene
	if world!=null and world.has_method("new_buff"):
		world.call(
			"new_buff",
			target,
			self,
			WIRE_SLOW_BUFF_NAME,
			Buff.new(
				3,
				maxf(slow_refresh_duration,0.08),
				Buff.Buff_types.Speed,
				ratio,
				Buff.Algorithms.mul
			),
            "cover"
		)


func _remove_wire_slow(target:ball)->void:
	if target==null or not is_instance_valid(target):
		return

	var world:Node=get_tree().current_scene
	if world!=null and world.has_method("new_buff"):
		world.call(
			"new_buff",
			target,
			self,
			WIRE_SLOW_BUFF_NAME,
			Buff.new(),
            "delete"
		)


func _deal_wire_damage(target:ball,amount:float)->bool:
	if target==null or not is_instance_valid(target) or amount<=0.0:
		return false

	var owner_node:=_owner_node()
	var before_health:float=float(target.health)
	var before_block:float=float(target.block)

	var damaged:bool=target.receive_spatial_damage(
		amount,
		{
			"shape":"circle",
			"center":global_position,
			"radius":radius,
			"point":target.global_position,
			"source":owner_node
		},
		wire_ignore_block,
		false
	)

	var actual_health_damage:bool=float(target.health)<before_health
	var actual_block_damage:bool=float(target.block)<before_block
	if damaged or actual_health_damage or actual_block_damage:
		_notify_owner_hit_audio(target,amount)
		return true
	return false


func _apply_wire_bleed(target:ball)->void:
	if (
		target==null
		or not is_instance_valid(target)
		or target.health<=0
		or bleed_stacks_per_move_hit<=0
	):
		return

	var existing:Node=target.get_node_or_null(NodePath(str(WIRE_BLEED_NODE_NAME)))
	var source_ball:=_owner_ball()

	if (
		existing!=null
		and is_instance_valid(existing)
		and existing.has_method("add_stacks")
	):
		existing.call(
			"add_stacks",
			bleed_stacks_per_move_hit,
			source_ball
		)
		return

	var status:Node=WIRE_BLEED_SCRIPT.new()
	if status==null:
		return
	status.name=str(WIRE_BLEED_NODE_NAME)
	target.add_child(status)
	status.call(
		"setup",
		target,
		source_ball,
		bleed_stacks_per_move_hit,
		bleed_max_stacks,
		bleed_duration,
		bleed_action_damage_per_stack,
		bleed_move_tick_interval,
		bleed_move_damage_per_stack
	)


func _on_owner_tree_exiting()->void:
	# V80：owner 的 tree_exiting 发生在 owner 自己的退树流程中。
	# 不在这个信号回调里直接 queue_free 刺网，而是 defer 到当前退树流程结束后，
	# 再走与“真实耐久耗尽”完全相同的最终破坏函数，保证碎屑/最终破坏音不会被退树时序吞掉。
	_request_owner_break()


func _request_owner_break()->void:
	if _final_break_started or _owner_break_queued or is_queued_for_deletion():
		return
	_owner_break_queued=true
	call_deferred("_execute_owner_break")


func _execute_owner_break()->void:
	if _final_break_started or is_queued_for_deletion():
		return
	# 保持 queued 标记直到最终破坏完成，避免同一帧 physics + tree_exiting 重复触发。
	destroy_as_durability_depleted()


func _owner_should_destroy_wire()->bool:
	# setup() 之前不误杀；正常盾狗刺网 setup 后才开始强绑定 owner 生命周期。
	if not _owner_assigned:
		return false
	var owner_node:=_owner_node()
	if owner_node==null:
		return true
	if owner_node.is_queued_for_deletion() or not owner_node.is_inside_tree():
		return true
	if owner_node is ball and (owner_node as ball).health<=0:
		return true
	return false


func destroy_as_durability_depleted()->void:
	# V80：这里不再存在“durability 已经 <= 0 就直接 queue_free”的静默分支。
	# 无论是盾狗死亡/删除、remove_child，还是普通耐久真正归零，都统一进入 _finish_final_break()。
	if _final_break_started or is_queued_for_deletion():
		return
	durability=0.0
	_finish_final_break()


func _owner_node()->Node:
	if owner_ref==null:
		return null
	var value:Variant=owner_ref.get_ref()
	if not is_instance_valid(value) or not value is Node:
		return null
	return value as Node


func _owner_ball()->ball:
	var owner_node:=_owner_node()
	if owner_node is ball:
		return owner_node as ball
	return null


func _target_from_ref(value:Variant)->ball:
	if not value is WeakRef:
		return null
	var target_value:Variant=(value as WeakRef).get_ref()
	if not is_instance_valid(target_value) or not target_value is ball:
		return null
	return target_value as ball


func _process_projectile_durability()->void:
	var candidates:Dictionary={}
	for node:Node in PROJECTILE_API.candidates(get_tree()):
		candidates[node.get_instance_id()]=node

	for id_variant:Variant in candidates.keys():
		var id:int=int(id_variant)
		if _projectile_seen.has(id):
			continue
		var node:Node=candidates[id]
		if not node is Node2D or not is_instance_valid(node):
			continue
		var projectile:=node as Node2D
		if global_position.distance_to(projectile.global_position)<=maxf(radius,1.0)+8.0:
			_projectile_seen[id]=true
			_damage_durability(maxf(attack_durability_damage,0.0)*clampf(projectile_durability_multiplier,0.0,1.0),true)
			if is_queued_for_deletion():
				return


func _is_projectile_node(node:Node)->bool:
	return PROJECTILE_API.live(node)

func receive_attack_hitbox(attacker:ball,incoming_hit:hitbox)->void:
	if attacker==null or not is_instance_valid(attacker):
		return
	var is_projectile:bool=_is_projectile_node(attacker)
	if is_projectile and _projectile_seen.has(attacker.get_instance_id()):
		return
	# 纯身体接触/冲撞伤害不伤刺网。Has_Collision_Damage 角色的本体 self_hitbox
	# 即使某一帧同时处于 Attacking，也仍按“直接碰撞伤害”排除。
	if (
		not is_projectile
		and attacker.Has_Collision_Damage
		and incoming_hit!=null
		and is_instance_valid(incoming_hit)
		and attacker.self_hitbox==incoming_hit
	):
		return
	var key:int=incoming_hit.get_instance_id() if incoming_hit!=null and is_instance_valid(incoming_hit) else attacker.get_instance_id()
	var now_msec:int=Time.get_ticks_msec()
	var cooldown_msec:int=int(round(maxf(durability_hit_cooldown,0.0)*1000.0))
	if now_msec-int(_durability_hit_last_msec.get(key,-1000000))<cooldown_msec:
		return
	_durability_hit_last_msec[key]=now_msec
	if is_projectile:
		_projectile_seen[attacker.get_instance_id()]=true
	var multiplier:float=clampf(projectile_durability_multiplier,0.0,1.0) if is_projectile else 1.0
	_damage_durability(maxf(attack_durability_damage,0.0)*multiplier,true)


func notify_non_collision_attack(is_projectile:bool=false)->void:
	var multiplier:float=clampf(projectile_durability_multiplier,0.0,1.0) if is_projectile else 1.0
	_damage_durability(maxf(attack_durability_damage,0.0)*multiplier,true)


func _damage_durability(value:float,with_shake:bool=true)->void:
	var actual:float=maxf(value,0.0)
	if _final_break_started or actual<=0.0 or durability<=0.0:
		return

	durability=maxf(durability-actual,0.0)

	# V80：致命耐久损失和 owner 消失共用唯一最终破坏入口。
	# 这样不会再出现某条生命周期分支只 queue_free、没有最终碎屑/刀片破坏5 的情况。
	if durability<=0.0:
		_finish_final_break()
		return

	# 非致命耐久损失仍只喷普通小碎屑，并播放刀片破坏1~4。
	_spawn_durability_debris(false)
	_play_random_durability_break_audio()
	if with_shake:
		_play_durability_shake()


func _finish_final_break()->void:
	if _final_break_started or is_queued_for_deletion():
		return
	_final_break_started=true
	_owner_break_queued=true
	durability=0.0

	# 与耐久耗尽完全相同的最终表现：大/小真实刺网纹理碎屑 + 刀片破坏5。
	_spawn_durability_debris(true)
	_play_durability_audio(_durability_destroy_stream)
	queue_free()


func _spawn_durability_debris(destroyed:bool)->void:
	var small_count:int=(
		maxi(destroy_debris_small_count,1)
		if destroyed
		else maxi(durability_debris_small_count,1)
	)
	for _i:int in range(small_count):
		_spawn_one_debris(false)

	if destroyed:
		for _i:int in range(maxi(destroy_debris_large_count,1)):
			_spawn_one_debris(true)


func _spawn_one_debris(large_piece:bool)->void:
	var host:Node=get_tree().current_scene
	if host==null:
		host=get_tree().root
	if host==null:
		return

	# V250：碎屑必须真的是“刺网.png 的一部分”，不能再用单色 Polygon2D 冒充。
	# 这里直接复用刺网原纹理，并通过 Sprite2D.region_rect 裁出随机局部区域。
	var tex:Texture2D=_wire_texture
	if tex==null or not is_instance_valid(tex):
		_shared_wire_assets()
		tex=_shared_wire_texture
	if tex==null:
		return

	var size_min:float=(debris_large_size_min if large_piece else debris_small_size_min)
	var size_max:float=(debris_large_size_max if large_piece else debris_small_size_max)
	size_min=maxf(size_min,0.8)
	size_max=maxf(size_max,size_min)
	var desired_world_size:float=randf_range(size_min,size_max)

	var region_rect:Rect2=_pick_wire_debris_region(tex,desired_world_size)
	if region_rect.size.x<=0.0 or region_rect.size.y<=0.0:
		return

	var piece:=Sprite2D.new()
	piece.name=("刀片刺网大块碎屑_%d" if large_piece else "刀片刺网碎屑_%d") % Time.get_ticks_usec()
	piece.texture=tex
	piece.centered=true
	piece.region_enabled=true
	piece.region_filter_clip_enabled=true
	piece.region_rect=region_rect
	piece.z_index=4
	host.add_child(piece)
	piece.add_to_group("BattleTransient")

	var tex_size:Vector2=tex.get_size()
	var original_fit_scale:float=1.0
	if tex_size.x>0.001:
		original_fit_scale=maxf(visual_width,radius*2.0)/tex_size.x
	var start_scale_value:float=original_fit_scale*randf_range(0.92,1.12)
	if large_piece:
		start_scale_value=original_fit_scale*randf_range(0.96,1.16)

	var start_pos:Vector2=global_position+Vector2(
		randf_range(-maxf(radius,1.0)*0.55,maxf(radius,1.0)*0.55),
		randf_range(-maxf(radius,1.0)*0.28,maxf(radius,1.0)*0.18)
	)
	piece.global_position=start_pos
	piece.rotation=randf_range(-0.20,0.20)
	piece.scale=Vector2.ONE*start_scale_value

	var visible_rect:Rect2=_get_visible_world_rect()
	var bottom_y:float=start_pos.y+90.0
	if visible_rect.size.y>1.0:
		bottom_y=maxf(
			visible_rect.end.y+maxf(debris_screen_bottom_margin,4.0),
			start_pos.y+visible_rect.size.y*0.62
		)

	var duration:float=randf_range(
		maxf(debris_flight_time_min,0.20),
		maxf(debris_flight_time_max,maxf(debris_flight_time_min,0.20))
	)
	if large_piece:
		duration*=randf_range(1.02,1.18)

	var horizontal_speed:float=randf_range(
		maxf(debris_horizontal_speed_min,0.0),
		maxf(debris_horizontal_speed_max,maxf(debris_horizontal_speed_min,0.0))
	)
	var side:float=-1.0 if randf()<0.5 else 1.0
	var end_pos:=Vector2(
		start_pos.x+side*horizontal_speed*duration*randf_range(0.70,1.25),
		bottom_y
	)

	var fall_distance:float=maxf(end_pos.y-start_pos.y,1.0)
	var arc_height:float=maxf(
		randf_range(26.0,52.0) if not large_piece else randf_range(34.0,68.0),
		fall_distance*0.45
	)
	var apex_fraction:float=randf_range(0.34,0.46)
	var apex_pos:=Vector2(
		lerpf(start_pos.x,end_pos.x,apex_fraction),
		start_pos.y-arc_height
	)
	var up_time:float=maxf(duration*apex_fraction,0.08)
	var down_time:float=maxf(duration-up_time,0.10)
	var end_rotation:float=piece.rotation+randf_range(-1.15,1.15)

	# 碎屑自身持有Tween，铁丝网完全销毁也不影响已飞出的真实纹理碎片。
	var movement:=piece.create_tween()
	movement.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	movement.tween_property(piece,"global_position",apex_pos,up_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	movement.tween_property(piece,"global_position",end_pos,down_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	movement.tween_callback(piece.queue_free)

	var appearance:=piece.create_tween()
	appearance.set_parallel(true)
	appearance.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	appearance.tween_property(piece,"scale",Vector2.ONE*start_scale_value*0.08,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	appearance.tween_property(piece,"rotation",end_rotation,duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _pick_wire_debris_region(tex:Texture2D,desired_world_size:float)->Rect2:
	var tex_size:Vector2=tex.get_size()
	var tex_width:int=maxi(int(floor(tex_size.x)),1)
	var tex_height:int=maxi(int(floor(tex_size.y)),1)

	var fit_scale:float=1.0
	if tex_size.x>0.001:
		fit_scale=maxf(visual_width,radius*2.0)/tex_size.x
	fit_scale=maxf(fit_scale,0.001)

	# 把希望看到的世界尺寸换算成原图裁切尺寸。大块会自然裁出更大一片真实铁丝网。
	var region_side:int=maxi(int(round(maxf(desired_world_size,1.0)/fit_scale)),2)
	region_side=mini(region_side,mini(tex_width,tex_height))

	# get_image() 只在 _build_visual() 时缓存一次。这里优先找真正有不透明刺网像素的位置，
	# 避免随机裁到 PNG 的透明空白区域，看起来像“没有碎屑”。
	var image:Image=_wire_texture_image
	if image!=null and not image.is_empty():
		for _attempt:int in range(72):
			var px:int=randi_range(0,tex_width-1)
			var py:int=randi_range(0,tex_height-1)
			if image.get_pixel(px,py).a<0.12:
				continue
			var max_x:int=maxi(tex_width-region_side,0)
			var max_y:int=maxi(tex_height-region_side,0)
			var region_x:int=clampi(px-int(region_side*0.5),0,max_x)
			var region_y:int=clampi(py-int(region_side*0.5),0,max_y)
			return Rect2(
				Vector2(float(region_x),float(region_y)),
				Vector2(float(region_side),float(region_side))
			)

	# 极端情况下纹理像素不可读，仍裁同一张刺网图，而不是回退成单色方块。
	var fallback_max_x:int=maxi(tex_width-region_side,0)
	var fallback_max_y:int=maxi(tex_height-region_side,0)
	return Rect2(
		Vector2(
			float(randi_range(0,fallback_max_x)) if fallback_max_x>0 else 0.0,
			float(randi_range(0,fallback_max_y)) if fallback_max_y>0 else 0.0
		),
		Vector2(float(region_side),float(region_side))
	)


func _get_visible_world_rect()->Rect2:
	if not is_inside_tree():
		return Rect2()
	var viewport_rect:Rect2=get_viewport_rect()
	if viewport_rect.size.x<=1.0 or viewport_rect.size.y<=1.0:
		return Rect2()

	# 当前 CanvasItem 的 canvas_transform 已包含 Camera2D；取逆把屏幕四角转换为世界坐标。
	var viewport_to_world:Transform2D=get_canvas_transform().affine_inverse()
	var corners:Array[Vector2]=[
		viewport_to_world*viewport_rect.position,
		viewport_to_world*Vector2(viewport_rect.end.x,viewport_rect.position.y),
		viewport_to_world*viewport_rect.end,
		viewport_to_world*Vector2(viewport_rect.position.x,viewport_rect.end.y),
	]
	var min_x:float=corners[0].x
	var max_x:float=corners[0].x
	var min_y:float=corners[0].y
	var max_y:float=corners[0].y
	for point:Vector2 in corners:
		min_x=minf(min_x,point.x)
		max_x=maxf(max_x,point.x)
		min_y=minf(min_y,point.y)
		max_y=maxf(max_y,point.y)
	return Rect2(Vector2(min_x,min_y),Vector2(max_x-min_x,max_y-min_y))


func _load_durability_audio()->void:
	_durability_break_streams.clear()
	for path:String in WIRE_BREAK_AUDIO_PATHS:
		var stream:=_load_wire_audio(path)
		if stream!=null:
			_durability_break_streams.append(stream)
	_durability_destroy_stream=_load_wire_audio(WIRE_DESTROY_AUDIO_PATH)


func _load_wire_audio(path:String)->AudioStream:
	# V433 性能：音效按路径跨刺网实例缓存，不再每张刺网重新 ResourceLoader.load()。
	var cached:Variant=_wire_audio_cache.get(path)
	if cached is AudioStream:
		return cached as AudioStream
	if not ResourceLoader.exists(path):
		push_warning("盾狗刀片刺网破坏音效缺失: %s" % path)
		return null
	var resource:=ResourceLoader.load(path)
	if resource is AudioStream:
		_wire_audio_cache[path]=resource
		return resource as AudioStream
	push_warning("盾狗刀片刺网破坏音效资源类型错误: %s" % path)
	return null


static var _wire_audio_cache:Dictionary={}
# V433 性能：刺网.png 约 2.8 MB，未压缩导入；此前每张刺网都 load() + get_image()（100 人场上单帧 39 ms）。
# 纹理与可读 Image 只解一次，跨实例共享；碎屑采样只读不写。
static var _shared_wire_texture:Texture2D=null
static var _shared_wire_image:Image=null
static var _shared_wire_loaded:bool=false

static func _shared_wire_assets()->void:
	if _shared_wire_loaded and _shared_wire_texture!=null and is_instance_valid(_shared_wire_texture):
		return
	_shared_wire_loaded=true
	_shared_wire_texture=load(WIRE_TEXTURE_PATH) as Texture2D
	_shared_wire_image=null
	if _shared_wire_texture==null:
		return
	var image:Image=_shared_wire_texture.get_image()
	if image!=null and image.is_compressed():
		var readable_image:Image=image.duplicate() as Image
		if readable_image!=null and readable_image.decompress()==OK:
			image=readable_image
		else:
			image=null
	_shared_wire_image=image


func _play_random_durability_break_audio()->void:
	if _durability_break_streams.is_empty():
		return
	var index:int=randi_range(0,_durability_break_streams.size()-1)
	_play_durability_audio(_durability_break_streams[index])


func _play_durability_audio(stream:AudioStream)->void:
	if stream==null:
		return

	var host:Node=get_tree().current_scene
	if host==null:
		host=get_tree().root
	if host==null:
		return

	var player:=AudioStreamPlayer2D.new()
	player.name="刀片刺网破坏音效_%d" % Time.get_ticks_usec()
	player.stream=stream
	player.volume_db=durability_break_audio_volume_db
	player.max_distance=maxf(durability_break_audio_max_distance,1.0)
	host.add_child(player)
	player.global_position=global_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _play_durability_shake()->void:
	if _visual_sprite==null or not is_instance_valid(_visual_sprite):
		return
	if _shake_tween!=null and _shake_tween.is_valid():
		_shake_tween.kill()
	_visual_sprite.position=Vector2.ZERO
	var distance:float=maxf(durability_shake_distance,0.0)
	var total_time:float=maxf(durability_shake_time,0.03)
	_shake_tween=create_tween()
	_shake_tween.tween_property(_visual_sprite,"position",Vector2(distance,0.0),total_time*0.25)
	_shake_tween.tween_property(_visual_sprite,"position",Vector2(-distance,0.0),total_time*0.50)
	_shake_tween.tween_property(_visual_sprite,"position",Vector2.ZERO,total_time*0.25)


func _build_attack_receiver()->void:
	var receiver:=hurtbox.new()
	receiver.name="耐久受击区"
	receiver.collision_layer=2
	receiver.collision_mask=0
	receiver.monitoring=false
	receiver.monitorable=true
	add_child(receiver)

	var collision:=CollisionShape2D.new()
	collision.name="CollisionShape2D"
	var circle:=CircleShape2D.new()
	circle.radius=maxf(radius,1.0)
	collision.shape=circle
	receiver.add_child(collision)
	_attack_receiver=receiver


func _build_visual()->void:
	_shared_wire_assets()
	var tex:Texture2D=_shared_wire_texture
	if tex==null:
		push_warning("盾狗刺网图片加载失败: %s" % WIRE_TEXTURE_PATH)
		return

	_wire_texture=tex
	# V250：碎屑只做像素采样，不反复从 GPU 抓纹理；V433 起这份 Image 跨所有刺网共享。
	_wire_texture_image=_shared_wire_image

	var sprite:=Sprite2D.new()
	sprite.name="刺网图片"
	sprite.texture=tex
	sprite.centered=true
	sprite.z_index=0
	add_child(sprite)
	_visual_sprite=sprite

	var tex_size:=tex.get_size()
	if tex_size.x>0.001:
		var fit_scale:float=maxf(visual_width,radius*2.0)/tex_size.x
		sprite.scale=Vector2.ONE*fit_scale


func _notify_owner_hit_audio(target:ball,damage_amount:float)->void:
	if target==null or not is_instance_valid(target):
		return

	var now_msec:int=Time.get_ticks_msec()
	var id:int=target.get_instance_id()
	var last_msec:int=int(_hit_audio_last_msec.get(id,-1000000))
	if now_msec-last_msec<int(round(maxf(hit_audio_repeat_delay,0.0)*1000.0)):
		return
	_hit_audio_last_msec[id]=now_msec

	var owner_node:=_owner_node()
	if owner_node!=null and owner_node.has_method("play_wire_damage_impact_audio"):
		owner_node.call(
			"play_wire_damage_impact_audio",
			target.global_position,
			maxf(damage_amount,0.0)
		)
