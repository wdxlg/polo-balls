extends Node2D
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
const TEXTURE = preload("res://Images/characters/我的世界/溺尸/三叉戟.png")
const CHARGE_VISUAL = preload("res://scripts/effects/我的世界/trident_charge_visual.gd")
const GROUND_DEBRIS = preload("res://scripts/effects/我的世界/trident_ground_debris.gd")
const DRAW_SIZE:float = 16.0 # Compact airborne weapon; original swept collision/damage remain unchanged.
const REFILL_FLASH = preload("res://scripts/effects/我的世界/trident_refill_flash.gdshader")
var _refill_pop_time:float = 1.0
var _refill_material:ShaderMaterial
enum Phase {HELD, OUTBOUND, RETURNING, STUCK}
# 旧插地视觉兼容数据（不再由正常玩法触发）：沿用原版 64×64 三叉戟贴图（默认斜朝右上），旋转 +135° 后戟头竖直朝下扎进地面，
# 再按投掷方向轻微侧倾。地表正好落在戟叉根部：整个戟叉（含三根白刃）都埋在土里，
# 由材质在土表线上裁掉，所以土面上只会看到戟杆插进地里，落点是一小堆被顶起来的干土。
const PLANT_ANGLE:float = PI*0.75
const PLANT_LEAN:float = 0.10
# 绘制框（16 单位）内：节点中心 → 戟叉尖端的方向与长度（贴图戟头在右上角）。
const PLANT_HEAD:Vector2 = Vector2(7.875,-7.875)
const PLANT_REACH:float = 9.72
# 绘制框内：节点中心 → 戟杆穿过土表的位置（= 轴向 PLANT_REACH-PLANT_SINK，土堆画在这里）。
const PLANT_GROUND:Vector2 = Vector2(1.570,-1.570)
# 戟叉沿戟轴没入土里的深度（戟尖到土表的距离）；地表因此落在戟叉根部之上。
const PLANT_SINK:float = 7.5
# 土表裁切线在落点【上方】的高度：正好切在戟叉顶端，戟叉整段（含白刃）都不会画出来，
# 断面落在土堆顶部内部，所以戟身上看不到悬空的杆头，附魔流光也不会透出土面。
const PLANT_CUT_ABOVE:float = 2.3
class StuckMound extends Node2D:
	# 基准点在戟杆穿过土表的位置；父节点倾角由 rotation 抵消，土堆按世界坐标水平摆放。
	# 只是一小堆被戟杆顶起来的干土，正好盖住埋在土里的戟叉。
	func _draw() -> void:
		# 接地阴影 + 阶梯状土堆：底宽顶窄，右侧受光、左侧和底部压暗。
		draw_rect(Rect2(-4.0,2.4,8.0,1.2),Color(0.0,0.0,0.0,0.20),true)
		draw_rect(Rect2(-3.4,1.0,6.8,1.5),Color("4a3820"),true)
		draw_rect(Rect2(-2.9,0.1,5.8,0.9),Color("5a4526"),true)
		draw_rect(Rect2(-2.4,-0.8,4.8,0.9),Color("6a5133"),true)
		draw_rect(Rect2(-1.9,-1.6,3.8,0.8),Color("7e5c36"),true)
		# 顶层要盖住裁切断面（落点上方 2.3 单位），戟杆从这里插进土里。
		draw_rect(Rect2(-1.5,-2.4,3.0,0.8),Color("8f6a40"),true)
		# 被戟杆顶出来的湿土和旁边的土块。
		draw_rect(Rect2(-0.7,2.0,1.4,1.2),Color("7a5a37"),true)
		draw_rect(Rect2(1.6,1.5,1.3,0.8),Color("2b1d0d"),true)
		draw_rect(Rect2(-3.9,0.2,1.0,0.7),Color("2b1d0d"),true)
var planted:bool = false
var stuck_mound:Node2D
# 出手当帧敌人的坐标只用于决定方向；本次飞行长度锁定完整射程。
# -1 表示旧调用点未走 launch()，沿用当前射程。
var aim_point:Vector2 = Vector2.ZERO
var flight_length:float = -1.0
# Retained for old snapshots/debug callers; wall-only flight never seeks/snaps.
var ground_seek:bool = false
var unit:ball
var serial:int = 0
var flight_state:int = Phase.HELD
var charged:bool = false:
	set(value):
		charged = value
		_sync_enchantment_candidate()
var _impact_emitted:bool = false
var return_trail:Node2D
const RETURN_SPIN_SPEED:float=60.0
const RETURN_ACCEL_TIME:float=0.75
const RETURN_SPIN_ACCEL_TIME:float=0.18
var _return_elapsed:float=0.0
var charge_visual:Node2D
var axis:Vector2 = Vector2.RIGHT
var traveled:float = 0.0
var lightning_left:float = 0.0
var wall_ref:WeakRef
var wall_local:Vector2
var _clock:float = 0.0
var _enchant_elapsed:float = 0.0
var _enchant_phase:int = Phase.HELD
func _ready() -> void:
	add_to_group("AllayExtendedProjectile")
	set_as_top_level(true)
	scale = Vector2.ONE
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refill_material = ShaderMaterial.new()
	_refill_material.shader = REFILL_FLASH
	material = _refill_material
	add_to_group("MCTrident")
	_sync_enchantment_candidate()
	add_to_group("BattleTransient")
	charge_visual = CHARGE_VISUAL.new()
	charge_visual.name = "ChargedTridentVisual"
	charge_visual.spear = self
	add_child(charge_visual)
	return_trail=preload("res://scripts/effects/我的世界/trident_return_trail.gd").new()
	return_trail.name="ReturnAfterimages"
	add_child(return_trail)
	# Added after the enchantment overlay so the cut cross-section stays covered.
	stuck_mound = StuckMound.new()
	stuck_mound.name = "StuckGroundMound"
	stuck_mound.visible = false
	add_child(stuck_mound)
	_apply_plant_clip(false)
func _ready_clip_default() -> void:
	_apply_plant_clip(false)
func begin_refill_pop() -> void:
	_refill_pop_time = 0.0
	_apply_refill_visual()
func refill_scale() -> float:
	if _refill_pop_time>=0.34: return 1.0
	var p:float = clampf(_refill_pop_time/0.34,0.0,1.0)
	return 1.0+0.45*exp(-7.0*p)*cos(3.0*PI*p)
func refill_flash() -> float:
	return pow(maxf(1.0-_refill_pop_time/0.10,0.0),2.0)
func _apply_refill_visual() -> void:
	scale = Vector2.ONE*(refill_scale() if flight_state!=Phase.HELD else 1.0)
	if _refill_material!=null: _refill_material.set_shader_parameter("refill_flash",refill_flash())
func _sync_enchantment_candidate() -> void:
	if not is_inside_tree(): return
	# Permanent charged poles must not add another full-N scan to every graph edge.
	if charged:
		if is_in_group("MCUnenchantedTrident"): remove_from_group("MCUnenchantedTrident")
	elif not is_in_group("MCUnenchantedTrident"): add_to_group("MCUnenchantedTrident")
func key() -> String: return str(unit.get_path())+":"+str(serial).pad_zeros(6)
func eligible() -> bool:
	return not is_queued_for_deletion() and is_instance_valid(unit) and unit.health>0 and unit.is_combat_runtime_active()
func enchantment_position() -> Vector2:
	return unit.trident_hand_position() if flight_state==Phase.HELD else global_position
func _reset_enchantment_timer() -> void:
	_enchant_elapsed = 0.0
	_enchant_phase = flight_state
func _advance_enchantment(delta:float) -> void:
	if charged: return
	if _enchant_phase!=flight_state: _reset_enchantment_timer()
	if flight_state!=Phase.HELD and flight_state!=Phase.STUCK:
		_enchant_elapsed = 0.0
		return
	_enchant_elapsed += maxf(delta,0.0)*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(unit)
	var duration:float = unit.held_enchant_delay if flight_state==Phase.HELD else unit.stuck_enchant_delay
	if _enchant_elapsed>=maxf(duration,0.1): charge()
func launch(direction:Vector2,origin:Variant = null,aim:Variant = null) -> void:
	flight_state = Phase.OUTBOUND
	planted = false
	ground_seek = false
	_reset_enchantment_timer()
	_impact_emitted = false
	var start:Vector2 = origin if origin is Vector2 else unit.trident_hand_position()
	if not unit.mc_line_clear(unit.global_position,start): start = unit.global_position
	global_position = start
	# 出手方向 = 实际出手点 → 出手当帧敌人所在坐标；出手点被挡回身体时也重新校正，
	# 保证弹道正好经过敌人当前位置（不预判、不锁定蓄力开始时的方向）。
	var locked:bool = aim is Vector2 and (aim as Vector2).distance_squared_to(start)>0.0001
	if locked:
		axis = (aim as Vector2 - start).normalized()
	else:
		axis = direction.normalized() if direction.length_squared()>0.0001 else Vector2.RIGHT
	# Aim is direction-only. Passing the enemy's old position is NOT impact.
	aim_point = (aim as Vector2) if locked else start+axis*maxf(unit.trident_range,1.0)
	flight_length = maxf(unit.trident_range,1.0)
	rotation = axis.angle()+PI*0.25
	traveled = 0.0
	unit.has_trident = false
	_apply_refill_visual()
	_apply_plant_visual()
	if is_instance_valid(unit.hand_visual): unit.hand_visual.sync_pose()
	queue_redraw()
func _physics_process(delta:float) -> void: advance(delta)
func advance(delta:float) -> void:
	if not is_instance_valid(unit) or unit.health<=0:
		retire()
		return
	if flight_state==Phase.HELD: global_position = unit.trident_hand_position()
	if Game.now_stop_state or get_tree().paused or not unit.is_combat_runtime_active(): return
	_clock += delta
	_refill_pop_time = minf(_refill_pop_time+maxf(delta,0.0),1.0)
	_apply_refill_visual()
	if not unit.is_multiplayer_authority():
		if flight_state==Phase.RETURNING: _return_elapsed+=maxf(delta,0.0)
		charge_visual.advance(delta)
		return_trail.advance(delta,self)
		queue_redraw()
		return
	if not unit.mc_live(): return
	# Migrate an already-existing old ground pole on the next active tick.
	if flight_state==Phase.STUCK and planted: _begin_return()
	# A missing supporting wall retires the item before it can finish enchanting.
	if flight_state==Phase.STUCK and wall_ref!=null:
		var wall:Variant = wall_ref.get_ref()
		if not is_instance_valid(wall):
			retire()
			return
		global_position = wall.to_global(wall_local)
	var was_charged:bool = charged
	_advance_enchantment(delta)
	match flight_state:
		Phase.OUTBOUND: _fly_out(delta)
		Phase.RETURNING:
			var previous:float=_return_elapsed
			_return_elapsed+=maxf(delta,0.0)
			rotation+=_return_integral(_return_elapsed,4.0,RETURN_SPIN_SPEED,RETURN_SPIN_ACCEL_TIME)-_return_integral(previous,4.0,RETURN_SPIN_SPEED,RETURN_SPIN_ACCEL_TIME)
			var hand:Vector2 = unit.trident_hand_position()
			var travel:float=_return_integral(_return_elapsed,65.0,unit.trident_return_speed*1.5)-_return_integral(previous,65.0,unit.trident_return_speed*1.5)
			global_position = global_position.move_toward(hand,travel)
			if global_position.distance_to(hand)<=5.0:
				# Legacy ground poles may return after a replacement already exists.
				# Do not leave two held weapons or overwrite the active throw.
				if is_instance_valid(unit._trident) and unit._trident != self:
					retire()
					return
				flight_state = Phase.HELD
				_reset_enchantment_timer()
				unit.catch_trident(self)
		Phase.STUCK:
			# A newly enchanted item begins its first-lightning delay now, not retroactively.
			if charged and was_charged:
				lightning_left -= delta
				if lightning_left<=0.0:
					lightning_left = maxf(unit.lightning_interval,unit.lightning_warning+0.5)
					unit.summon_trident_lightning(self)
	charge_visual.advance(delta)
	return_trail.advance(delta,self)
	queue_redraw()
func _flight_limit() -> float:
	# 本次投掷的飞行长度；没有锁定终点（未走 launch）时退回整条射程。
	return maxf(unit.trident_range,1.0) if flight_length<=0.0 else flight_length
func _fly_out(delta:float) -> void:
	var from:Vector2 = global_position
	var limit:float = _flight_limit()
	if traveled>=limit-0.0001:
		_begin_return()
		return
	var remaining:float = maxf(limit-traveled,0.0)
	if remaining<=0.0:
		_begin_return()
		return
	var distance:float = minf(unit.trident_speed*delta,remaining)
	var to:Vector2 = from+axis*distance
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,from,to): return
	var wall:Dictionary = GEOMETRY.wall_ray(self,from,to,[unit.get_rid()])
	var wall_t:float = from.distance_to(wall.position)/maxf(distance,0.00001) if not wall.is_empty() else INF
	var best:float = wall_t
	var victim:ball
	var candidates:Array[Dictionary]=[]
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not GEOMETRY.enemy(unit,raw): continue
		var t:float = GEOMETRY.sweep_circle(from,to,ball.body_point_seg(raw,from,to),GEOMETRY.radius(raw)+3.0)
		if t<best: candidates.append({"target":raw,"t":t})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return a.t<b.t)
	for contact:Dictionary in candidates:
		var target:ball=contact.target
		if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): continue
		best=contact.t
		victim=target
		break
	if victim!=null:
		global_position = from.lerp(to,best)
		unit.mc_damage_with_impact(victim,unit.trident_hit_damage(),global_position)
		unit.native_feedback.request("item.trident.hit",global_position,-12.0,0.08)
		_charged_contact()
		_begin_return() # One hit only. Return rotation never deals a second hit.
	elif not wall.is_empty():
		traveled += from.distance_to(wall.position)
		stick(wall.position+wall.normal*1.0,wall.collider as Node2D)
	else:
		var landed:bool = traveled+distance>=limit-0.0001
		global_position = to
		traveled += distance
		# No character or obstacle before full range: ordinary loyalty return.
		if landed: _begin_return()
func return_speed_at(time:float) -> float:
	return lerpf(65.0,unit.trident_return_speed*1.5,smoothstep(0.0,RETURN_ACCEL_TIME,maxf(time,0.0)))
func return_spin_at(time:float) -> float:
	return lerpf(4.0,RETURN_SPIN_SPEED,smoothstep(0.0,RETURN_SPIN_ACCEL_TIME,maxf(time,0.0)))
func _return_integral(time:float,start:float,finish:float,ramp:float=RETURN_ACCEL_TIME) -> float:
	var t:float=maxf(time,0.0)
	var u:float=clampf(t/ramp,0.0,1.0)
	return start*t+(finish-start)*(ramp*(u*u*u-0.5*u*u*u*u)+maxf(t-ramp,0.0))
func _begin_return() -> void:
	if flight_state==Phase.RETURNING: return
	flight_state = Phase.RETURNING
	planted = false
	ground_seek = false
	wall_ref = null
	_apply_plant_visual()
	_return_elapsed=0.0
	if not is_instance_valid(unit._trident):
		unit._trident = self
		unit.has_trident = false
		unit._refill_left = -1.0
	_reset_enchantment_timer()
	unit.native_feedback.request("item.trident.return",global_position,-8.0,0.0)
func _charged_contact() -> void:
	if not charged or _impact_emitted: return
	_impact_emitted = true
	unit.summon_trident_lightning(self,true)
func stick(point:Vector2,surface:Node2D = null) -> void:
	if flight_state==Phase.STUCK: return
	if not is_instance_valid(surface):
		_begin_return()
		return
	var was_outbound:bool = flight_state==Phase.OUTBOUND
	flight_state = Phase.STUCK
	planted = false
	_reset_enchantment_timer()
	global_position = point
	wall_ref = weakref(surface) if surface!=null else null
	wall_local = surface.to_local(point) if surface!=null else point
	lightning_left = unit.lightning_first_delay
	unit.trident_stuck(self)
	unit.native_feedback.request("item.trident.hit_ground",global_position,-7.0,0.08)
	if was_outbound: _charged_contact()
	_apply_plant_visual()
	queue_redraw()
func stick_ground(_point:Vector2) -> void:
	# Compatibility with older callers/saves: ground lodging is no longer a
	# gameplay state. A miss keeps loyalty and returns instead of making a pole.
	if flight_state!=Phase.HELD: _begin_return()

func _plant_ground_ok(point:Vector2) -> bool:
	# Legacy ground-visual helper; no current flight path plants in the ground.
	var inner:Rect2 = unit.mc_arena_rect().grow(-8.0)
	if inner.size.x>24.0 and inner.size.y>24.0 and not inner.has_point(point): return false
	return unit.mc_position_clear(point,6.0)
func plant_head_direction() -> Vector2:
	# 戟叉尖端指向（世界坐标）：插地时基本竖直朝下。
	return PLANT_HEAD.normalized().rotated(rotation)
func _plant_head_offset() -> Vector2:
	# 节点中心 → 戟叉接触地面处，沿戟轴向下的偏移。
	return plant_head_direction()*(PLANT_REACH-PLANT_SINK)
func plant_contact_point() -> Vector2:
	# 戟叉穿过土表的位置：插地时的落点，等于 _safe_ground_point 的返回值。
	return global_position+plant_head_direction()*(PLANT_REACH-PLANT_SINK)
func plant_tip_point() -> Vector2:
	# 戟叉真正埋进土里的尖端：沿戟轴再往下没入 PLANT_SINK。
	return plant_contact_point()+plant_head_direction()*PLANT_SINK
func plant_buried_units() -> float:
	return PLANT_SINK
func _safe_ground_point(point:Vector2) -> Vector2:
	# 落点必须留在地图内并避开墙体：先夹进地图内边界，仍然落在墙里就沿弹道回退，
	# 再不行就朝地图中心收，直到找到空位（次数有上限，避免死循环）。
	var arena:Rect2 = unit.mc_arena_rect()
	var inner:Rect2 = arena.grow(-8.0)
	var bounded:bool = inner.size.x>24.0 and inner.size.y>24.0
	var landing:Vector2 = _clamp_inside(inner,point) if bounded else point
	for step:int in range(28):
		if unit.mc_position_clear(landing,6.0): return landing
		if step<10:
			landing -= axis*6.0
		elif bounded:
			landing = landing.lerp(inner.get_center(),0.25)
		else:
			break
		if bounded: landing = _clamp_inside(inner,landing)
	return landing
func _clamp_inside(inner:Rect2,point:Vector2) -> Vector2:
	return Vector2(clampf(point.x,inner.position.x,inner.end.x),clampf(point.y,inner.position.y,inner.end.y))
func _apply_plant_visual() -> void:
	# 土堆只在“插在地面”时出现；节点带倾角时用反向旋转让土堆保持水平摆放。
	var grounded:bool = planted and flight_state==Phase.STUCK
	if is_instance_valid(stuck_mound):
		stuck_mound.visible = grounded
		stuck_mound.z_as_relative = false
		stuck_mound.z_index = z_index+2
		if stuck_mound.visible:
			stuck_mound.position = PLANT_GROUND
			stuck_mound.rotation = -rotation
			stuck_mound.queue_redraw()
	_apply_plant_clip(grounded)
	if is_instance_valid(charge_visual): charge_visual.sync_plant_clip()
func plant_clip_enabled() -> bool:
	# 插地（不是插墙）时才做土表裁切。
	return planted and flight_state==Phase.STUCK
func plant_clip_y() -> float:
	# 土表裁切线（世界 y）：落点再往上 PLANT_CUT_ABOVE，正好在戟叉顶端之上。
	return plant_contact_point().y-PLANT_CUT_ABOVE
func configure_plant_clip(material:ShaderMaterial,enabled:bool) -> void:
	# All render layers clip their actual world vertices against this same plane.
	if material==null: return
	material.set_shader_parameter("plant_clip",1.0 if enabled else 0.0)
	material.set_shader_parameter("plant_clip_y",plant_clip_y() if enabled else 0.0)
func _apply_plant_clip(enabled:bool) -> void:
	configure_plant_clip(_refill_material,enabled)
func _spawn_ground_debris(replay_age:float = 0.0) -> void:
	# Same floor sampler/block-flight renderer as the mace. Keep this one-shot
	# burst independent of weapon collection/retirement after touching ground.
	var debris:Node2D = GROUND_DEBRIS.new()
	debris.name = "TridentGroundDebris"
	debris.set_meta("mc_trident_source_id",get_instance_id())
	preload("res://scripts/effects/我的世界/mc_explosion.gd").runtime_container(unit).add_child(debris,true)
	debris.start(plant_contact_point(),unit.mc_arena_rect(),replay_age)
func charge() -> bool:
	if charged or not eligible() or not unit.mc_live() or Game.now_stop_state or get_tree().paused: return false
	charged = true
	_enchant_elapsed = 0.0
	global_position = enchantment_position()
	unit.native_feedback.request("block.enchantment_table.use",global_position,-9.0,0.0)
	lightning_left = maxf(unit.lightning_first_delay,0.05)
	unit._sync_left = 0.0
	charge_visual.advance(0.0)
	queue_redraw()
	return true
func _self_foot_world_position() -> Vector2: return global_position
func snapshot() -> Dictionary:
	return {"id":serial,"phase":flight_state,"point":global_position,"rotation":rotation,"charged":charged,"planted":planted,"aim":aim_point,"flight":flight_length,"enchant_elapsed":_enchant_elapsed,"refill_pop_time":_refill_pop_time,"return_elapsed":_return_elapsed,"ground_impact_id":0,"ground_impact_age":10000.0}
func receive(data:Dictionary) -> void:
	flight_state = int(data.phase)
	_return_elapsed=maxf(float(data.get("return_elapsed",0.0)),0.0)
	global_position = data.point
	rotation = float(data.rotation)
	charged = bool(data.charged)
	# Old ground-state snapshots must not recreate a ground pole or debris.
	if flight_state==Phase.STUCK and bool(data.get("planted",false)):
		flight_state = Phase.RETURNING
		_return_elapsed = 0.0
	planted = false
	ground_seek = false
	aim_point = data.get("aim",aim_point)
	flight_length = float(data.get("flight",-1.0))
	_refill_pop_time = clampf(float(data.get("refill_pop_time",1.0)),0.0,1.0)
	_apply_refill_visual()
	_apply_plant_visual()
	_enchant_phase = flight_state
	_enchant_elapsed = maxf(float(data.get("enchant_elapsed",0.0)),0.0)
	charge_visual.advance(0.0)
	queue_redraw()
func retire() -> void:
	if is_queued_for_deletion(): return
	remove_from_group("MCTrident")
	if is_in_group("MCUnenchantedTrident"): remove_from_group("MCUnenchantedTrident")
	if is_instance_valid(unit): unit.trident_retired(self)
	queue_free()
func _draw() -> void:
	if not is_instance_valid(unit) or unit.health<=0: return
	# The independent native rightItem layer draws the hand; never draw twice.
	if flight_state!=Phase.HELD:
		draw_texture_rect(TEXTURE,Rect2(Vector2.ONE*(-DRAW_SIZE*0.5),Vector2.ONE*DRAW_SIZE),false)
