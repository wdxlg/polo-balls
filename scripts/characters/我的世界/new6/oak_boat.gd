extends "res://scripts/characters/我的世界/new5/base.gd"
const FRAMES8:SpriteFrames = preload("res://Images/characters/我的世界/new6/boat_frames8.tres")
const FRAMES8_FRONT:SpriteFrames = preload("res://Images/characters/我的世界/new6/boat_front_frames8.tres")
const FX = preload("res://scripts/characters/我的世界/new6/fx_burst.gd")
const RIDER:Script = preload("res://scripts/characters/我的世界/new6/boat_rider.gd")
# 八方向烘焙视图里长椅两座位相对船体中心的屏幕偏移（世界单位）。
# 由 scripts/training/mc_new6_assets/bake_boat8_views.py 生成，取代随朝向旋转的座位偏移。
const SEAT_ANCHORS:Array = [
	[Vector2(6.297,1.54),Vector2(-6.297,1.54)],
	[Vector2(3.989,5.538),Vector2(-3.989,-2.41)],
	[Vector2(0.0,6.964),Vector2(0.0,-3.875)],
	[Vector2(-3.989,5.538),Vector2(3.989,-2.41)],
	[Vector2(-6.297,1.54),Vector2(6.297,1.54)],
	[Vector2(-3.983,-2.403),Vector2(3.983,5.533)],
	[Vector2(0.0,-3.875),Vector2(0.0,6.964)],
	[Vector2(3.983,-2.403),Vector2(-3.983,5.533)],
]
# 操控手感：高转舵率 + 快起步/快刹车 + 更快的倒车，让船能急转、能迅速拉开再冲。
# 转弯半径 ≈ 转弯保底速度/转舵率 ≈ 95/1.7 ≈ 56px（旧 65/0.9 ≈ 72px，且 180° 掉头要 3.5s）。
@export var cruise_speed:float = 320.0
@export var acceleration:float = 170.0
@export var braking:float = 300.0
@export var reverse_speed:float = 80.0
@export var turn_rate:float = 1.7
@export var turn_acceleration:float = 5.0
@export var turn_speed_floor:float = 95.0
@export var board_range:float = 30.0
@export var board_cooldown:float = 4.0
@export var ram_cooldown:float = 0.55
@export var ram_min_speed:float = 90.0
@export var crash_speed:float = 90.0
# 船头正面撞上障碍物时播放 MC 木头破坏音效的最低法向撞速（低于 crash_speed 的轻撞也有声）。
@export var bump_speed:float = 30.0
var _bump_cd:float = 0.0
# 撞击后甩尾脱离（hit-and-run）：撞中敌人后不顶着对方磨蹭、也不倒车，而是满油门向空旷侧
# 甩头调转、驶离到助跑距离，再掉头全速再撞。每一撞都带满速度（伤害随撞速），
# 也不给贴身反击型目标连续输出的机会。
var _swing_left:float = 0.0
var _swing_side:float = 1.0
var _swing_out:bool = false
const RUNUP_DIST:float = 170.0
var _angular_speed:float = 0.0
var _paddle_hits:Dictionary = {}
var _reverse_left:float = 0.0
var _escape_steer:float = 1.0
var _wall_heading:Vector2 = Vector2.ZERO
var _wall_seek_left:float = 0.0
var _roam_target:Vector2 = Vector2.ZERO
var _roam_left:float = 0.0
var _sharing_damage:bool = false
var _share_frame:int = -1
var _shared_hits:Dictionary = {}
var facing:Vector2 = Vector2.RIGHT
var _forward_speed:float = 0.0
var _board_left:float = 0.8
var _crash_cd:float = 0.0
var _paddle_cd:float = 0.0
var _rowing:bool = false
var _ram_cd:Dictionary = {}
var _last_wall_normal:Vector2 = Vector2.ZERO
var _wall_contact_left:float = 0.0
var _stuck_time:float = 0.0
var _steer_boost:float = 0.0
var _follow_side:float = 0.0
var _flush_back:float = 0.0
var _slide_plan_left:float = 0.0
var _engage_time:float = 0.0
var _engage_target_id:int = 0
var _charge_grace:float = 0.0
var _back_off_left:float = 0.0
var _back_off_dist:float = 220.0
var _detour_left:float = 0.0
var _detour_point:Vector2 = Vector2.ZERO
var _dbg_desired:Vector2 = Vector2.ZERO
var _dbg_controls:Vector2 = Vector2.ZERO
var _dbg_branch:StringName = &"chase"
var _dbg_ram:String = "-"
var passengers:Array[ball] = []
var _riders:Dictionary = {}
var front:Sprite2D

func _ready() -> void:
	super._ready()
	Can_Skill = true
	Skill_Cooling = board_cooldown
	add_to_group("MinecraftBoardingBoat")
	if direction.length_squared() > 0.001: facing = direction.normalized()
	# 近侧船舷前景层：z 高于乘客，与船体后层把乘客夹在中间，形成"坐在舱内"。
	front = Sprite2D.new()
	front.name = "HullFront"
	front.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	front.z_index = 3
	graphics.add_child(front)
	front.scale = image.scale
	front.offset = image.offset

func _valid_board_target(target:ball) -> bool:
	if not is_instance_valid(target) or target == self or target.health <= 0: return false
	if target.Type not in [Ball_Type.Ball,Ball_Type.Creature] or not target.is_combat_targetable(): return false
	if target.is_in_group("MinecraftBoardingBoat") or target.is_transport_mounted(): return false
	if U.enemy(self,target) and not target.can_receive_negative_effects(): return false
	return true

func _boarding_candidates() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or not _valid_board_target(node as ball): continue
		var target:ball = node as ball
		if global_position.distance_to(ball.body_point(target,global_position)) <= board_range and U.line_clear(self,global_position,ball.body_point(target,global_position)):
			result.append(target)
	result.sort_custom(func(a:ball,b:ball): return global_position.distance_squared_to(ball.body_point(a,global_position)) < global_position.distance_squared_to(ball.body_point(b,global_position)))
	return result

func Skill() -> void:
	Using_Skill = false
	if not active() or dizziness or not Can_Skill or _board_left > 0.0 or passengers.size() >= 2: return
	if is_damage_output_disabled(): return
	var candidates:Array[ball] = _boarding_candidates()
	if candidates.is_empty(): return
	_board_left = board_cooldown
	if state_machine != null: state_machine.last_state_dis["Skill"] = 0.0
	for candidate:ball in candidates:
		if passengers.size() >= 2: break
		board_unit(candidate)
	play_sound("entity.boat.paddle_water",-2.0)
	FX.ring(get_tree().current_scene,"smoke",global_position,board_range,10,0.3,5.0)

func board_unit(target:ball) -> bool:
	if not is_multiplayer_authority() or passengers.size() >= 2 or not _valid_board_target(target): return false
	if global_position.distance_to(ball.body_point(target,global_position)) > board_range or not U.line_clear(self,global_position,ball.body_point(target,global_position)): return false
	_attach_passenger(target,passengers.size())
	_broadcast_passengers()
	return true

func _attach_passenger(target:ball,index:int) -> void:
	if passengers.has(target): return
	var rider:Node = RIDER.new()
	rider.name = "BoatSeatConstraint"
	target.add_child(rider)
	passengers.append(target)
	_riders[target.get_instance_id()] = rider
	rider.setup(target,self,index)

func seat_position(index:int) -> Vector2:
	# 座位跟随当前方向烘焙视图中的长椅位置，乘客视觉上坐在船舱内而不是船外。
	var dir_index:int = posmod(roundi(facing.angle()/TAU*8),8)
	var anchors:Array = SEAT_ANCHORS[dir_index]
	return global_position+anchors[clampi(index,0,1)]

func disembark_position(target:ball,index:int) -> Vector2:
	if not is_inside_tree() or get_world_2d() == null: return ball.body_point(target,global_position)
	var space:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var circle:CircleShape2D = CircleShape2D.new()
	circle.radius = _body_radius(target)+2.0
	for step:int in range(12):
		var dir:Vector2 = facing.rotated(PI*0.5*(1 if index == 0 else -1)+step*TAU/12.0)
		var candidate:Vector2 = global_position+dir*(22.0+circle.radius)
		var query:PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
		query.shape = circle
		query.transform = Transform2D(0.0,candidate)
		query.collision_mask = 1
		query.exclude = [get_rid(),target.get_rid()]
		if space.intersect_shape(query,1).is_empty(): return candidate
	return global_position

func _prune_passengers() -> void:
	var changed:bool = false
	for i:int in range(passengers.size()-1,-1,-1):
		var passenger = passengers[i]
		if not is_instance_valid(passenger) or passenger.health <= 0 or not passenger.is_transport_mounted():
			if is_instance_valid(passenger):
				var rider = _riders.get(passenger.get_instance_id())
				if is_instance_valid(rider): rider.release()
				_riders.erase(passenger.get_instance_id())
			passengers.remove_at(i)
			changed = true
	for key in _riders.keys():
		if not is_instance_valid(_riders[key]): _riders.erase(key)
	for i:int in range(passengers.size()):
		var rider = _riders.get(passengers[i].get_instance_id())
		if is_instance_valid(rider): rider.slot = i
	if changed: _broadcast_passengers()

func release_all() -> void:
	for rider in _riders.values():
		if is_instance_valid(rider): rider.release()
	_riders.clear()
	passengers.clear()
	_broadcast_passengers()

func _passenger_paths() -> Array[String]:
	var paths:Array[String] = []
	for passenger in passengers:
		if is_instance_valid(passenger): paths.append(str(passenger.get_path()))
	return paths
func _broadcast_passengers() -> void:
	if is_inside_tree() and is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_sync_passenger_paths.rpc(_passenger_paths())
@rpc("authority","call_remote","reliable")
func _sync_passenger_paths(paths:Array[String]) -> void:
	for passenger in passengers.duplicate():
		if not is_instance_valid(passenger):
			passengers.erase(passenger)
			continue
		if str(passenger.get_path()) not in paths:
			var rider = _riders.get(passenger.get_instance_id())
			if is_instance_valid(rider): rider.release()
			_riders.erase(passenger.get_instance_id())
			passengers.erase(passenger)
	for key in _riders.keys():
		if not is_instance_valid(_riders[key]): _riders.erase(key)
	for i:int in range(mini(paths.size(),2)):
		var target:ball = get_node_or_null(NodePath(paths[i])) as ball
		if target == null: continue
		if not passengers.has(target): _attach_passenger(target,i)
		var rider = _riders.get(target.get_instance_id())
		if is_instance_valid(rider):
			rider.slot = i
			rider.apply_pose()

func step_mob(delta:float) -> void:
	_prune_passengers()
	_wall_contact_left = maxf(_wall_contact_left-delta,0.0)
	if _wall_contact_left <= 0.0: _follow_side = 0.0
	_flush_back = maxf(_flush_back-delta,0.0)
	_slide_plan_left = maxf(_slide_plan_left-delta,0.0)
	_board_left = maxf(_board_left-delta,0.0)
	_crash_cd = maxf(_crash_cd-delta,0.0)
	_bump_cd = maxf(_bump_cd-delta,0.0)
	_swing_left = maxf(_swing_left-delta,0.0)
	_paddle_cd -= delta
	_reverse_left = maxf(_reverse_left-delta,0.0)
	_wall_seek_left = maxf(_wall_seek_left-delta,0.0)
	_roam_left = maxf(_roam_left-delta,0.0)
	var prev_back_off:float = _back_off_left
	_back_off_left = maxf(_back_off_left-delta,0.0)
	# 拉距计时自然到期（未退满 260px）也给冲锋宽限，避免刚转向前就再判缠斗。
	if prev_back_off > 0.0 and _back_off_left <= 0.0 and _charge_grace <= 0.0: _charge_grace = 2.5
	_charge_grace = maxf(_charge_grace-delta,0.0)
	_detour_left = maxf(_detour_left-delta,0.0)
	for key in _paddle_hits.keys():
		_paddle_hits[key] -= delta
		if _paddle_hits[key] <= 0: _paddle_hits.erase(key)
	for key:Variant in _ram_cd.keys():
		_ram_cd[key] -= delta
		if _ram_cd[key] <= 0.0: _ram_cd.erase(key)
	if not is_player_controlled() and Can_Skill and _board_left <= 0.0 and passengers.size() < 2 and not dizziness: Skill()
	_rowing = velocity.length_squared() > 900.0
	if _rowing and _paddle_cd <= 0.0:
		_paddle_cd = 0.5
		play_sound("entity.boat.paddle_water",-8.0)

func _body_radius(actor:ball) -> float:
	var shape:CollisionShape2D = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or shape.shape == null: return 10.0
	var size:Vector2 = shape.shape.get_rect().size*shape.global_scale.abs()
	return maxf(size.x,size.y)*0.5

func source_is_onboard(source:Node) -> bool:
	var node = source
	for i:int in range(8):
		if not is_instance_valid(node): return false
		if node == self or (node is ball and passengers.has(node)): return true
		if node is ball and is_instance_valid(node.Master): node = node.Master
		elif node.has_meta("combat_source") and node.get_meta("combat_source") is Node: node = node.get_meta("combat_source")
		else: node = node.get_parent()
	return false

func share_external_damage(receiver:ball,damage:float,point:Vector2,ignore_block:bool,source:Node,raw_health:bool = false,damage_kind:String = "") -> bool:
	if _sharing_damage or source_is_onboard(source) or damage <= 0: return false
	_prune_passengers()
	if passengers.is_empty(): return false
	var frame_id:int = Engine.get_physics_frames()
	if frame_id != _share_frame: _shared_hits.clear(); _share_frame = frame_id
	# 一次外部范围命中覆盖船与多个座位时，只分摊一份，不乘以乘员数。
	if is_instance_valid(source):
		var key:String = "%d:%s" % [source.get_instance_id(),damage_kind]
		var seen:Dictionary = _shared_hits.get(key,{})
		if not seen.is_empty() and not seen.has(receiver.get_instance_id()):
			seen[receiver.get_instance_id()] = true
			_shared_hits[key] = seen
			return true
		_shared_hits[key] = {receiver.get_instance_id():true}
	var members:Array[ball] = [self]
	members.append_array(passengers)
	_sharing_damage = true
	# 生命值为整数；将舍入余数分给前几个座位，保证总量不膨胀。
	var total:int = maxi(roundi(damage),0)
	var each:int = total/members.size()
	var remainder:int = total%members.size()
	for i:int in range(members.size()):
		var member = members[i]
		if not is_instance_valid(member): continue
		var part:int = each+(1 if i<remainder else 0)
		if part <= 0: continue
		member.set_meta("boat_damage_share_guard",true)
		if not damage_kind.is_empty():
			if raw_health: member.receive_classified_spatial_damage(part,{"point":point,"source":source},StringName(damage_kind),true,true)
			else: member.receive_classified_positional_damage(part,point,StringName(damage_kind),ignore_block,source)
		elif raw_health: member.receive_spatial_damage(part,{"point":point,"source":source},true,true)
		else: member.receive_positional_damage(part,point,ignore_block,source)
		if is_instance_valid(member): member.remove_meta("boat_damage_share_guard")
	_sharing_damage = false
	return true

func ram_profile(speed_value:float) -> Dictionary:
	var ratio:float = clampf(speed_value/cruise_speed,0,1)
	return {"damage":attack_damage(0.35+2.1*ratio),"distance":2.0+10.0*ratio,"speed":70.0+90.0*ratio}

func _ram_path(start:Vector2,finish:Vector2,impact_speed:float) -> void:
	if impact_speed < ram_min_speed or not can_act():
		_dbg_ram = ("spd" if impact_speed < ram_min_speed else "act")+"|"+str(int(impact_speed))+"|"+str(can_act())
		return
	_dbg_ram = "nofoe"
	# 撞角弓距按"视觉全局坐标"校准：全体角色全局缩放 0.2，船体视觉半长
	# 仅 ~10-13px，运行时碰撞半径(~12px)与视觉一致。旧常数 60 是局部设计
	# 值，全局坐标下等于 3~4 个船长——导致"隔着很远就撞伤敌人"。
	# 14px 恰好盖过船首视觉突出部；末段结算靠冲锋免晕豁免保护。
	var bow_offset:Vector2 = facing*maxf(_body_radius(self),14.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		# 登上其他载具的单位算"在船体内"，不可被外部撞击结算（与目标选择一致）。
		if not U.enemy(self,node) or passengers.has(node) or node.is_transport_mounted(): continue
		var victim:ball = node as ball
		if _ram_cd.has(victim.get_instance_id()): _dbg_ram = "cd"; continue
		var offset:Vector2 = ball.body_point(victim,start)-start
		if offset.normalized().dot(facing) < 0.65: _dbg_ram = "cone"; continue
		if U.segment_distance(ball.body_point_seg(victim,start+bow_offset,finish+bow_offset),start+bow_offset,finish+bow_offset) > _body_radius(victim)+6.0:
			_dbg_ram = "seg|"+str(int(U.segment_distance(ball.body_point_seg(victim,start+bow_offset,finish+bow_offset),start+bow_offset,finish+bow_offset)))+"|"+str(int(_body_radius(victim)))
			continue
		# 视线终点允许就是受害者本体。命中窗口(≈14+R_vic+6，视觉贴合)比
		# 羊头槌射程(~55px)更近：靠 committed 冲锋的免晕免推豁免，
		# 保证反击型目标不能在结算前把船晕住。
		var sight:Dictionary = U.trace(self,start,victim.global_position)
		if not sight.is_empty() and sight.collider != victim:
			_dbg_ram = "sight|"+str(sight.collider)
			continue
		var profile:Dictionary = ram_profile(impact_speed)
		_dbg_ram = "dmg?|"+str(int(profile.damage))
		if U.damage(self,victim,profile.damage,finish):
			_dbg_ram = "HIT"
			_ram_cd[victim.get_instance_id()] = ram_cooldown
			victim.apply_knockback(facing,profile.distance,profile.speed,0,0,{"source":self,"lock_control":false})
			_forward_speed *= 0.92
			FX.hit_sfx(self,victim.global_position,profile.damage)
			if not is_player_controlled():
				# 甩向净空更大的一侧；回环期间不计"无效纠缠"，也不倒车。
				var swing_probe:float = _body_radius(self)+160.0
				var clear_cw:float = _wall_clear_distance(facing.rotated(1.0),swing_probe)
				var clear_ccw:float = _wall_clear_distance(facing.rotated(-1.0),swing_probe)
				_swing_side = 1.0 if clear_cw >= clear_ccw else -1.0
				_swing_left = 3.0
				_swing_out = false
				_engage_time = 0.0

func _paddle_attack(start:Vector2,old_facing:Vector2,angular:float) -> void:
	if absf(angular)<0.12 or not can_act(): return
	var reach:float = _body_radius(self)+9.0
	var ratio:float = clampf(absf(angular)/turn_rate,0,1)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,node) or passengers.has(node) or node.is_transport_mounted(): continue
		var victim:ball = node as ball
		if _paddle_hits.has(victim.get_instance_id()): continue
		var offset:Vector2 = ball.body_point(victim,global_position)-global_position
		if absf(offset.normalized().dot(facing))>0.65: continue
		for side:float in [-1.0,1.0]:
			var a:Vector2 = start+old_facing.orthogonal()*reach*side
			var b:Vector2 = global_position+facing.orthogonal()*reach*side
			if U.segment_distance(ball.body_point_seg(victim,a,b),a,b)>_body_radius(victim)+4.0: continue
			if not U.line_clear(self,global_position,ball.body_point(victim,global_position)): continue
			var amount:float = attack_damage(0.25+0.85*ratio)
			if U.damage(self,victim,amount,b):
				_paddle_hits[victim.get_instance_id()] = 0.45
				victim.apply_knockback(offset.normalized(),2.0+6.0*ratio,60.0+70.0*ratio,0,0,{"source":self,"lock_control":false})
				FX.hit_sfx(self,victim.global_position,amount)
			break

func _hostile_passenger(passenger:ball) -> bool:
	return is_instance_valid(passenger) and passenger.health>0 and (Team.is_empty() or passenger.Team!=Team)

func _has_enemy_passenger() -> bool:
	for passenger in passengers:
		if _hostile_passenger(passenger): return true
	return false

func _nearest_outside_enemy() -> ball:
	var nearest:ball
	var best:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,node) or passengers.has(node) or node.is_transport_mounted() or U.wall_node(node): continue
		var dist:float = global_position.distance_squared_to(ball.body_point(node,global_position))
		if dist<best: best = dist; nearest = node as ball
	return nearest

func _pick_wall_heading() -> Vector2:
	var best:float = INF
	var heading:Vector2 = facing
	for i:int in range(24):
		var dir:Vector2 = Vector2.from_angle(i*TAU/24.0)
		var hit:Dictionary = U.trace(self,global_position,global_position+dir*2400)
		if hit.is_empty(): continue
		var length:float = global_position.distance_to(hit.position)
		if length<_body_radius(self)+60: continue
		var score:float = length+absf(facing.angle_to(dir))*100
		if score<best: best = score; heading = dir
	return heading

func _pick_roam_target() -> Vector2:
	# 没有敌人时也绕场地巡航，保持车辆一直有动势。
	# 在多个候选里取"够长且少掉头"的方向：巡航是连贯的弧线，而不是原地掉头来回折返。
	var best_point:Vector2 = global_position+facing*300
	var best_score:float = -INF
	for i:int in range(8):
		var dir:Vector2 = Vector2.from_angle(randf()*TAU)
		var hit:Dictionary = U.trace(self,global_position,global_position+dir*1200)
		var length:float = 1200.0 if hit.is_empty() else global_position.distance_to(hit.position)
		if length<=160: continue
		var score:float = minf(length,700.0)-absf(facing.angle_to(dir))*160.0+randf()*80.0
		if score>best_score:
			best_score = score
			best_point = global_position+dir*randf_range(0.5,0.85)*length
	return best_point

func _drive_input(delta:float) -> Vector2:
	# 冲锋宽限航段：重载荷具的 committed charge，小型单位头槌的
	# 眩晕/顶推不得取消它（窗口仅 2.5s，只在 AI 倒开拉距后进入）。
	# 豁免仅在"仍在高速冲锋"时成立——用前向速度门控：停泊/被减速的船
	# 不得被宽限期解除外部施加的 dizziness（控制类技能、测试停泊）。
	if _charge_grace > 0.0 and _forward_speed > 90.0 and not is_player_controlled():
		if dizziness: dizziness = false
		Repel = Vector2.ZERO
	if dizziness:
		_steer_boost = 0.0
		return Vector2.ZERO
	if is_player_controlled():
		_steer_boost = 0.0
		var player_dir:Vector2 = player_control_direction
		if player_dir.length_squared()<0.001: return Vector2.ZERO
		var angle:float = facing.angle_to(player_dir.normalized())
		if absf(angle)>2.35:
			return Vector2(-1,clampf(facing.angle_to(-player_dir.normalized())/0.7,-1,1))
		return Vector2(1,clampf(angle/0.7,-1,1))
	if _reverse_left>0:
		# 脱困倒车时也加快转舵，尽快把船头甩向空旷一侧。
		_steer_boost = 0.6
		_dbg_branch = &"reverse"
		return Vector2(-1,_escape_steer)
	var target:ball = _nearest_outside_enemy()
	var desired:Vector2 = facing
	# 缠斗计时：贴身距离内迟迟没有成功冲撞（无 ram 冷却记录）= 无效纠缠——
	# 低速磨蹭、切向环绕、被目标击退力悬停在触体外都算数；1.2s 即倒开拉距。
	if target != null:
		var tid:int = target.get_instance_id()
		if tid != _engage_target_id:
			_engage_target_id = tid
			_engage_time = 0.0
		var to_eng:Vector2 = ball.body_point(target,global_position)-global_position
		var dist_eng:float = to_eng.length()
		var closing:float = (velocity.dot(to_eng/dist_eng)) if dist_eng > 1.0 else 0.0
		# committed 冲锋：末段接近（速度快 + 船头大致对准）给短暂免晕免推，
		# 保证对反击型目标（羊头槌会眩晕取消冲撞）的冲锋能打到结算。
		if _charge_grace <= 0.0 and _forward_speed > 90.0 and dist_eng < 250.0 and absf(facing.angle_to(to_eng/dist_eng)) < 0.6:
			_charge_grace = 0.8
		# 无效纠缠 = 贴近但"不再接近"（悬停/环绕/被顶开）。正在追近的船
		# 绝不触发倒开——追击会移动的目标时倒开只会越倒越远、永远撞不上。
		if _charge_grace > 0.0 or _detour_left > 0.0 or _swing_left > 0.0:
			_engage_time = 0.0
		elif dist_eng < maxf(_body_radius(self)+_body_radius(target),60.0)+140.0 and not _ram_cd.has(tid) and closing < 40.0 and absf(facing.angle_to(to_eng/dist_eng)) < 0.7:
			# 只有"船头已对准目标却仍不接近"才算纠缠；正在掉头重新瞄准不算。
			_engage_time += delta
		else:
			_engage_time = maxf(_engage_time-delta*2.0,0.0)
		if _engage_time > 0.9 and _back_off_left <= 0.0:
			_engage_time = 0.0
			_back_off_left = 3.5
	else:
		_engage_target_id = 0
		_engage_time = 0.0
	# 倒开拉距：低速顶上敌人时撞击无效（ram 需要 ≥ ram_min_speed 撞速，
	# 贴身相持只会平衡在 ~83px/s），立即倒退拉开冲锋距离，船头始终指向目标，
	# 退够后转全速直线冲撞。背后是墙退无可退时，改为向空旷侧脱离一段再绕冲。
	if _back_off_left > 0.0 and _swing_left > 0.0:
		# 甩尾脱离本身就是拉距动作，不再叠加倒车。
		_back_off_left = 0.0
	if _back_off_left > 0.0:
		if target == null:
			_back_off_left = 0.0
		elif global_position.distance_to(ball.body_point(target,global_position)) >= _back_off_dist:
			_back_off_left = 0.0
			_charge_grace = 2.5
			_engage_time = 0.0
		elif _wall_clear_distance(-facing,_body_radius(self)+80.0) < _body_radius(self)+35.0:
			_back_off_left = 0.0
			_detour_left = 1.4
			var to_t:Vector2 = global_position.direction_to(ball.body_point(target,global_position))
			var perp:Vector2 = to_t.orthogonal()
			if _wall_clear_distance(perp,300.0) < _wall_clear_distance(-perp,300.0): perp = -perp
			_detour_point = global_position+perp*300.0
		else:
			# 倒开时无视小型单位的击退顶推：船是重载具，被羊头顶住倒不动
			# 就会永远悬在触体外，攒不出冲锋距离。
			Repel = Vector2.ZERO
			_steer_boost = 0.6
			_dbg_branch = &"backoff"
			_dbg_desired = global_position.direction_to(ball.body_point(target,global_position))
			return Vector2(-1,clampf(facing.angle_to(_dbg_desired)/0.55,-1,1))
	if target != null and _swing_left > 0.0:
		# 撞击后甩尾脱离：先向空旷侧满舵甩头（回转半径≈45px）直到船尾对着目标，
		# 再全速驶离到 RUNUP_DIST 助跑距离，随即掉头冲锋。全程保持油门，不倒车；
		# 驶离路线仍走扫掠避墙，被墙困住时 3s 超时兜底回到追击。
		# 不清 Repel：对方的击退正好把船带离贴身区，顺势脱离。
		var to_sw:Vector2 = global_position.direction_to(ball.body_point(target,global_position))
		var dist_sw:float = global_position.distance_to(ball.body_point(target,global_position))
		if dist_sw >= RUNUP_DIST:
			_swing_left = 0.0
			desired = to_sw
		else:
			if not _swing_out and facing.dot(to_sw) < -0.2: _swing_out = true
			if _swing_out: desired = (-to_sw+facing*0.35).normalized()
			else: desired = facing.rotated(_swing_side*1.1)
	elif target != null:
		if _detour_left > 0.0 and global_position.distance_to(_detour_point) > 80.0:
			# 侧向脱离航段：仍走 resolver 避墙，绕开后直线冲锋攒速度。
			Repel = Vector2.ZERO
			desired = global_position.direction_to(_detour_point)
		else:
			_detour_left = 0.0
			# 拦截解算：瞄"会在哪"而不是"现在在哪"。对横向逃逸目标切弦拦截；
			# 纯追尾会陷入平行飞行(closing≈0)→被误判无效纠缠→反复倒开永远撞不上。
			var to_int:Vector2 = ball.body_point(target,global_position)-global_position
			var rv:Vector2 = target.velocity
			var s_int:float = maxf(absf(_forward_speed),120.0)
			var qa:float = rv.dot(rv)-s_int*s_int
			var qb:float = 2.0*rv.dot(to_int)
			var qc:float = to_int.dot(to_int)
			var t_hit:float = 0.0
			if absf(qa) < 1.0:
				if absf(qb) > 0.001: t_hit = -qc/qb
			else:
				var disc:float = qb*qb-4.0*qa*qc
				if disc >= 0.0:
					var sq:float = sqrt(disc)
					var r1:float = (-qb-sq)/(2.0*qa)
					var r2:float = (-qb+sq)/(2.0*qa)
					t_hit = minf(r1,r2) if minf(r1,r2) > 0.0 else maxf(r1,r2)
			t_hit = clampf(t_hit,0.0,1.4)
			# 末段归航：拦截解假设目标匀速直线；对弧线机动/变向的目标，
			# 长提前量的瞄点会系统性偏差（目标已弯离弦线终点），在贴身
			# 窗口(~31px)上擦边落空。~60px 内退化为纯追尾（每帧重瞄当前
			# 位置）——只要比目标快，追尾螺旋自然收敛进撞角窗口；
			# 60~260px 线性混合提前量，兼顾远程切弦拦截与末段命中精度。
			t_hit *= clampf((to_int.length()-60.0)/200.0,0.0,1.0)
			desired = global_position.direction_to(target.global_position+rv*t_hit)
	elif _has_enemy_passenger():
		if _wall_seek_left<=0 or _wall_heading==Vector2.ZERO:
			_wall_heading = _pick_wall_heading()
			_wall_seek_left = 1.0
		desired = _wall_heading
	else:
		if _roam_left<=0 or global_position.distance_to(_roam_target)<60:
			_roam_target = _pick_roam_target()
			_roam_left = randf_range(3,6)
		desired = global_position.direction_to(_roam_target)
	# 押送处决冲锋：载着敌方俘虏且无外部目标时，直奔选定墙面——
	# 不偏转、不阻尼、不倒车；撞墙速度必须达到 _wall_crash 的伤害门槛(90)，
	# 这是"撞墙让俘虏掉血"的核心机制。撞击后 crash 分支自动倒车拉开 3s，
	# 形成"退开—冲锋"循环，不会贴墙空转（卡死监控仍然兜底）。
	if target == null and _has_enemy_passenger():
		var rerr:float = facing.angle_to(desired)
		_steer_boost = clampf((absf(rerr)-0.2)*1.8,0.0,0.9)
		_dbg_branch = &"ram"
		_dbg_desired = desired
		return Vector2(1,clampf(rerr/0.55,-1,1))
	_refresh_avoid_exclusions()
	# 触墙滑行规划：碰墙后 1.2s 内以"切向 + 离墙分量"作为规划输入。
	# 扫掠规划器会把距墙面 <95px 的沿墙路线全部拒掉、把船剥离去绕大圈；
	# 滑行规划接管这段时间，切向侧用 300px 前瞻视野（离墙 30px 视点）决定：
	# 哪边先看到目标就往哪边滑；离墙点直线通视成立即解除，直奔目标穿口。
	if _slide_plan_left > 0.0 and _last_wall_normal.length_squared() > 0.001:
		var stand_off:Vector2 = global_position+_last_wall_normal*30.0
		var has_target:bool = target != null and is_instance_valid(target)
		var direct:bool = has_target and _route_visible(stand_off,target)
		if not direct:
			var tangent:Vector2 = _last_wall_normal.orthogonal().normalized()
			if has_target:
				var vis_a:bool = _route_visible(stand_off+tangent*300.0,target)
				var vis_b:bool = _route_visible(stand_off-tangent*300.0,target)
				if vis_a != vis_b:
					if vis_b: tangent = -tangent
				elif tangent.dot(desired) < 0.0:
					tangent = -tangent
			elif tangent.dot(desired) < 0.0:
				tangent = -tangent
			desired = (tangent+_last_wall_normal*0.5).normalized()
	# 预测式绕行：撞墙前须状扫描，直行被挡就取最近的通畅偏角提前绕开；
	# 经过墙口时直行恢复通畅，立刻穿过去直奔目标，不再贴墙空转。
	desired = _avoid_direction(desired,target)
	# 带符号转角用于转向指令；绝对值只用于敏捷加成与调试。
	var signed_err:float = facing.angle_to(desired)
	var err:float = absf(signed_err)
	# 三段式近墙处理（撞击豁免：正抵近攻击前方敌人时全部让路，由卡死监控兜底）：
	# 远——正常巡航；近（<半径+50）——阻尼逼近，保推力舵效、把船头甩向空旷侧；
	# 贴（<半径+20）——短促倒车让位。计时只在真正贴墙时刷新，防止进退极限环。
	var ahead:float = _wall_clear_distance(facing,_body_radius(self)+120.0)
	var hunting:bool = false
	if target != null:
		var to_target:Vector2 = global_position.direction_to(ball.body_point(target,global_position))
		var target_dist:float = global_position.distance_to(ball.body_point(target,global_position))
		var aim_err:float = absf(facing.angle_to(to_target))
		hunting = target_dist < _body_radius(self)+_body_radius(target)+34.0 and aim_err < 1.0
		# 目标就在船头前方、而且比前方的墙更近（墙在目标身后）：这是正常冲撞航线，
		# 不能因为目标背后有墙就提前减速——否则撞到目标时速度已掉到冲撞门槛以下，
		# 只会顶着目标磨蹭、再倒开、再磨蹭，看起来又蠢又慢。
		if not hunting and aim_err < 0.6 and target_dist-_body_radius(target) <= ahead+8.0:
			hunting = true
	if not hunting:
		# 只有"选定路线也被近距挡死"（真被角落顶住）才倒车让位；
		# 路线通畅时交给阻尼+舵效完成转向，避免在墙口拐角前进退摇摆。
		var route_clear:float = _wall_clear_distance(desired,_body_radius(self)+60.0)
		if ahead < _body_radius(self)+20.0 and route_clear < _body_radius(self)+26.0 and _forward_speed > -20.0:
			_flush_back = 0.25
		if _flush_back > 0.0:
			if _forward_speed > 50.0: _forward_speed = 50.0
			if _follow_side == 0.0: _follow_side = signf(facing.angle_to(desired)) if err > 0.1 else 1.0
			_steer_boost = 0.9
			_dbg_branch = &"flush"
			return Vector2(-1,clampf(facing.angle_to(desired)/0.55,-1,1))
		if ahead < _body_radius(self)+50.0 and _forward_speed > 70.0:
			# 近墙阻尼分两档：选定路线已经通畅（正在转离墙面）只轻收油门、保留转弯保底速度，
			# 让船"贴着墙拐过去"而不是每次靠近墙都刹到爬行；路线也被挡才重刹到 50，
			# 保留舵效并把刮蹭法向速度压在撞墙判定(30)附近以下。
			if route_clear >= _body_radius(self)+60.0:
				_forward_speed = maxf(_forward_speed*0.96,turn_speed_floor)
			else:
				_forward_speed = maxf(_forward_speed*0.92,50.0)
			_steer_boost = 0.9
			_dbg_branch = &"damp"
			_dbg_desired = desired
			return Vector2(1,clampf(facing.angle_to(desired)/0.55,-1,1))
	# AI 敏捷加成：转向偏差越大，转舵越紧、角速度与转弯保底下速越高。
	_steer_boost = clampf((err-0.2)*1.8,0.0,0.9)
	if _swing_left > 0.0: _dbg_branch = &"swing"
	else: _dbg_branch = &"chase" if _slide_plan_left <= 0.0 else &"slide"
	_dbg_desired = desired
	return Vector2(1,clampf(signed_err/0.55,-1,1))

var _avoid_exclusions:Array[RID] = []
var _avoid_shape:CircleShape2D

func _refresh_avoid_exclusions() -> void:
	# 扫掠排除全部生物（船要主动撞击敌人），只把墙/静态障碍当阻挡。
	_avoid_exclusions = [get_rid()]
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is CollisionObject2D and node != self:
			_avoid_exclusions.append((node as CollisionObject2D).get_rid())
	if _avoid_shape == null:
		_avoid_shape = CircleShape2D.new()
	# 略小于真实船体：贴墙滑行时保留几像素裕度，扫掠不会因初始贴面而全部归零；
	# 漏检带宽 <5px，最多轻蹭拐角，由接触滑行兜住。
	_avoid_shape.radius = _body_radius(self)*0.92

func _wall_clear_distance(dir:Vector2,distance:float) -> float:
	# 船体整圆扫掠（cast_motion）：平行射线会从射线缝隙里漏掉拐角，
	# 导致船身侧舷啃在墙口上；整圆扫掠对船体半径内的一切障碍都算数。
	if get_world_2d() == null: return distance
	if _avoid_shape == null: _refresh_avoid_exclusions()
	var space:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query:PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = _avoid_shape
	query.transform = Transform2D(0.0,global_position)
	query.motion = dir*distance
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _avoid_exclusions
	var result:PackedFloat32Array = space.cast_motion(query)
	if result.size() < 1: return distance
	return clampf(result[0],0.0,1.0)*distance

func _route_visible(from:Vector2,target:ball) -> bool:
	# 一步前瞻：from 处能否直视目标（射线终点是目标本体不算遮挡）。
	var hit:Dictionary = U.trace(self,from,target.global_position)
	return hit.is_empty() or hit.collider == target

func _avoid_direction(desired:Vector2,target:ball = null) -> Vector2:
	# 探测长度必须覆盖到相关障碍：短探测会在射线尽头前"看不见"墙，
	# 把冲向墙的路线误判为零罚分全通畅。按速度 1.2 秒前瞻、下限 150。
	var probe:float = _body_radius(self)+10.0+clampf(absf(_forward_speed)*1.2,150.0,420.0)
	# 目标比探测距离更近时，探测截到目标处：目标身后的墙不是障碍，
	# 不该为它绕路（旧逻辑会为 400px 外、目标背后的墙放弃直冲，绕一大圈）。
	if target != null and is_instance_valid(target) and global_position.direction_to(ball.body_point(target,global_position)).dot(desired) > 0.7:
		var to_target:float = global_position.distance_to(ball.body_point(target,global_position))
		probe = clampf(to_target-_body_radius(target)*0.5,_body_radius(self)+40.0,probe)
	if _wall_clear_distance(desired,probe) >= probe: return desired
	var best_dir:Vector2 = desired
	var best_score:float = INF
	var best_offset:float = 0.0
	var fallback_dir:Vector2 = desired
	var fallback_clear:float = -1.0
	# 细分 0.26rad（≈15°）步进、最大 ±120°：候选更密，选出的绕行角更贴合实际缺口，
	# 航线更平滑、少走冤枉路；转舵率提高后每一步都能及时跟上。
	for step:int in range(1,9):
		for side:float in [1.0,-1.0]:
			var offset:float = side*step*0.26
			var dir:Vector2 = desired.rotated(offset)
			var clear:float = _wall_clear_distance(dir,probe)
			# 门槛 = 船体半径 + 35：转弯弧线会向路线外侧漂移半个船身，
			# 只留几像素净空的"擦角路线"必然啃角，直接拒掉。
			if clear < _body_radius(self)+35.0:
				# 次门槛候选不丢弃：全部被拒时作为兜底方向（最大净空），
				# 避免兜底直冲 desired 反而撞进墙角。
				if clear > fallback_clear: fallback_clear = clear; fallback_dir = dir
				continue
			# 角度偏差罚分 + 净空不足罚分：优先"少绕"，其次"绕得远"。
			var score:float = absf(offset)+(1.0-clear/probe)*1.6
			# 一步前瞻：沿该方向前行一段后若能直视目标，说明此路通向墙口/绕后，
			# 大幅加分——否则贪心角度罚分会让船永远选"贴墙缓绕"而错过穿口路线。
			if target != null and is_instance_valid(target):
				var pivot:Vector2 = global_position+dir*minf(clear*0.9,200.0)
				if _route_visible(pivot,target): score -= 1.5
			# 已贴墙/已选过绕行侧：给锁定侧明显加成，杜绝沿墙左右横跳。
			if _follow_side != 0.0 and signf(offset) == _follow_side: score -= 0.3
			if score < best_score: best_score = score; best_dir = dir; best_offset = offset
	# 全部候选低于门槛：朝净空最大的方向走（配合阻尼/卡死监控脱困），绝不直冲墙角。
	if best_score >= INF: return fallback_dir
	# 首次偏转即锁定该侧，直到离墙一段时间后才重置（step_mob）。
	if _follow_side == 0.0: _follow_side = signf(best_offset)
	return best_dir

func _integrate_drive(throttle:float,steering:float,delta:float) -> Vector2:
	var old_speed:float = _forward_speed
	var old_angle:float = facing.angle()
	var agility:float = 1.0+_steer_boost
	_angular_speed = move_toward(_angular_speed,steering*turn_rate*agility,turn_acceleration*agility*delta)
	facing = facing.rotated(_angular_speed*delta).normalized()
	var cap:float = cruise_speed*maxf(Speed,0)/220.0
	var turn_fraction:float = clampf(absf(_angular_speed)/(turn_rate*agility),0,1)
	# AI 规避转弯时保底速度更高，转完即走，不再一打舵就掉到爬行速度。
	var floor_speed:float = turn_speed_floor*(1.0+0.55*_steer_boost)*maxf(Speed,0)/220.0
	# 转弯减速按转舵量的平方取：小幅修正航向几乎不掉速（追击时不断微调也能保持冲撞速度），
	# 满舵急转才降到转弯保底速度。
	var goal:float = lerpf(cap,minf(floor_speed,cap),turn_fraction*turn_fraction)
	if throttle<0: goal = -reverse_speed*maxf(Speed,0)/220.0
	elif is_zero_approx(throttle): goal = 0
	var rate:float = braking if old_speed*goal<0 or absf(goal)<absf(old_speed) else acceleration
	_forward_speed = move_toward(old_speed,goal,rate*delta)
	# 有符号速度连续经过零；倒车不会瞬间翻转惯性。
	return Vector2.from_angle(lerp_angle(old_angle,facing.angle(),0.5))*(old_speed+_forward_speed)*0.5*delta

func _wall_crash(normal_speed:float) -> void:
	if normal_speed<crash_speed or _crash_cd>0: return
	_crash_cd = 0.8
	var ratio:float = clampf(normal_speed/cruise_speed,0,1)
	for passenger in passengers.duplicate():
		if _hostile_passenger(passenger):
			U.damage(self,passenger,attack_damage(0.4+2.6*ratio),passenger.global_position)
	play_sound("block.wood.break",-3.0)

func _bow_bump(normal:Vector2,normal_speed:float) -> void:
	# 船头撞上障碍物（墙/静态物）：达到伤害门槛走 _wall_crash（自带木头破坏音效并伤俘虏）；
	# 未达门槛、或伤害冷却中，只要是船头正面撞上（法向撞速 > bump_speed），
	# 也播放 MC 木头破坏音效（block.wood.break，原版 wood dig 四段随机），音量随撞速；
	# 侧舷/船尾刮蹭不算船头撞击，不出声。
	var crash_ready:bool = normal_speed >= crash_speed and _crash_cd <= 0.0
	_wall_crash(normal_speed)
	if crash_ready:
		_bump_cd = 0.3
		return
	if _bump_cd > 0.0 or facing.dot(-normal) < 0.35: return
	_bump_cd = 0.3
	var ratio:float = clampf((normal_speed-bump_speed)/maxf(crash_speed-bump_speed,1.0),0.0,1.0)
	play_sound("block.wood.break",lerpf(-13.0,-4.0,ratio))

func move(_speed:float,delta:float) -> void:
	if apply_transport_pose() or not active(): return
	var controls:Vector2 = _drive_input(delta)
	_dbg_controls = controls
	var old_facing:Vector2 = facing
	var start:Vector2 = global_position
	var motion:Vector2 = _integrate_drive(controls.x,controls.y,delta)
	velocity = facing*_forward_speed+Repel
	var impact_speed:float = _forward_speed
	var collision:KinematicCollision2D = move_and_collide(motion+Repel*delta)
	_ram_path(start,global_position,impact_speed)
	_paddle_attack(start,old_facing,_angular_speed)
	if collision != null:
		var collider = collision.get_collider()
		var normal:Vector2 = collision.get_normal().normalized()
		var full_motion:Vector2 = motion+Repel*delta
		if not collider is ball or U.wall_node(collider):
			_last_wall_normal = normal
			_wall_contact_left = 0.35
			_slide_plan_left = 1.2
			var normal_speed:float = absf((facing*impact_speed).dot(normal))
			if normal_speed>bump_speed:
				_bow_bump(normal,normal_speed)
				_forward_speed *= 0.2
				_reverse_left = 0.35
				_escape_steer = 1.0 if facing.cross(normal)>=0 else -1.0
				# 撞墙后先朝离墙方向行驶一段时间，再重新选墙，避免贴墙卡死。
				_wall_heading = normal.rotated(randf_range(-0.7,0.7))
				_wall_seek_left = 3.0
			else:
				_forward_speed *= 0.98
				_wall_seek_left = 0.0
		else:
			# 顶着生物/另一条船：轻减速，靠下面的切向互滑错开，绝不顶牛死锁。
			_forward_speed *= 0.98
			# 顶上敌方单位且最近一次冲撞没有落地（无 ram 冷却记录）：立即倒开拉距。
			# 贴身低速磨蹭（平衡速度 83 < 门槛 90）和切向环绕滑行（撞锥 dot>0.65
			# 永不满足）都打不出 ram 伤害；退到 260px 直线冲锋才能命中。
			# 成功撞中后 _ram_cd 已写入（_ram_path 先于本分支执行），追击不被打断。
			if controls.x > 0.0 and collider is ball and not passengers.has(collider) and U.enemy(self,collider) and not _ram_cd.has((collider as ball).get_instance_id()):
				_back_off_left = 3.5
		# 切向滑行：move_and_collide 会丢掉整帧位移，这里补回切向分量——
		# 擦墙时顺墙走，船船对顶时互相侧滑错开。绕行侧锁定由 _avoid_direction 统一管理。
		var tangent_motion:Vector2 = full_motion-normal*full_motion.dot(normal)
		if tangent_motion.length_squared() > 1e-6:
			move_and_collide(tangent_motion*0.92)
	direction = facing
	_rowing = absf(_forward_speed)>5 or absf(_angular_speed)>0.1
	# 卡死监控：油门向前却几乎没有位移时，强制倒车脱困。
	# 阈值 35：慢速蹭墙也算卡；贴墙倒车反射（_flush_back）是主动脱困动作，不计入卡死，
	# 否则两套逃逸机制会朝相反方向打舵互相抵消。
	var frame_speed:float = (global_position-start).length()/maxf(delta,1e-4)
	# 卡死特征 = 油门要求高速（_forward_speed>60）但实际几乎零位移（<15px/s）。
	# 阈值必须远低于阻尼保底速度，刮蹭转向的减速段不会被误判成卡死。
	# 倒车后的正常加速段速度低，不满足该特征，不会被误判成卡死而形成倒车循环。
	# 卡死特征：(a)油门要求高速却零位移（顶墙/啃角）——快速累积；
	# (b)持续低速顶着不动（船船对顶、顶着生物）——慢速累积约 1.4s 触发，
	# 倒车后的加速段只有 ~1s 低速，不会误触发。
	if controls.x > 0.0 and frame_speed < 15.0 and (_forward_speed > 60.0 or _wall_contact_left > 0.0):
		_stuck_time += delta
	elif controls.x > 0.0 and frame_speed < 20.0:
		_stuck_time += delta*0.35
	else:
		_stuck_time = maxf(_stuck_time-delta,0.0)
	if _stuck_time > 0.4:
		_stuck_time = 0.0
		_reverse_left = 0.4
		var away:Vector2 = _last_wall_normal if _wall_contact_left > 0.0 else -facing
		# 逃逸转向沿用已锁定的绕行侧，与须状扫描保持一致，不再随机反向。
		if _follow_side != 0.0:
			_escape_steer = _follow_side
		else:
			_escape_steer = 1.0 if facing.cross(away) >= 0 else -1.0
		_follow_side = 0.0
		_wall_heading = away.rotated(randf_range(-0.5,0.5))
		_wall_seek_left = 2.0
		_roam_left = 0.0
	for rider in _riders.values():
		if is_instance_valid(rider): rider.apply_pose()

func stand(delta:float) -> void:
	move(Speed,delta)
func visual_mob() -> void:
	# 守卫者式八方向：图集按方向烘焙，运行时只选帧，不做任何旋转。
	var dir_index:int = posmod(roundi(facing.angle()/TAU*8),8)
	var clip:StringName = StringName("d%d_%s"%[dir_index,"row" if _rowing else "idle"])
	frame(FRAMES8,clip)
	if is_instance_valid(front):
		# 前景船舷与船体同帧同步，乘客夹在两层之间。
		front.texture = FRAMES8_FRONT.get_frame_texture(clip,int(_view_clock*FRAMES8_FRONT.get_animation_speed(clip))%FRAMES8_FRONT.get_frame_count(clip))
		front.rotation = 0.0
	image.rotation = 0.0
	set_character_visual_flip_h(false)
	graphics.rotation = 0.0
func visual_state() -> Dictionary:
	return {"time":clock,"facing":facing,"rowing":_rowing,"seats":_passenger_paths()}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	facing = data.get("facing",facing)
	_rowing = bool(data.get("rowing",_rowing))
	var paths:Array[String] = []
	for path:Variant in data.get("seats",[]): paths.append(str(path))
	_sync_passenger_paths(paths)
func Die() -> void:
	release_all()
	AUDIO.play(self,"block.wood.break",global_position,0.0,true,true)
	super.Die()
func _exit_tree() -> void:
	release_all()
	super._exit_tree()
