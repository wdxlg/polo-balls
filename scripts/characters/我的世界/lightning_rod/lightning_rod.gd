extends "res://scripts/characters/我的世界/new5/base.gd"
# 避雷针（原版 lightning_rod 方块模型侧视）：随机选上/下/左/右一侧，聚云 gather_time 秒后
# 乌云每 strike_interval 秒朝针尖劈一轮 2–5 条闪电；每 direction_interval 秒换到另一侧重新聚云。
# 闪电落到针上时对避雷针周围小范围造成伤害并眩晕（同一轮每个敌人只结算一次）；
# 每条闪电的路径留下一段连着云与针尖的电网，碰到的敌人受高频小伤和短眩晕。
# 针下能量条靠落雷充能：受到伤害时朝周围小范围放电并消耗能量；充满时释放大范围扩散雷圈。
# 能量接近满时针体颤抖，越接近满幅度越大。乌云在天上，闪电与电网不被墙阻挡。
const STORM = preload("res://scripts/characters/我的世界/lightning_rod/storm_visual.gd")
const RING = preload("res://scripts/characters/我的世界/lightning_rod/thunder_ring.gd")
const BAR = preload("res://scripts/characters/我的世界/lightning_rod/charge_bar.gd")
const ROD_AUDIO = preload("res://scripts/characters/我的世界/lightning_rod/lightning_rod_audio.gd")
const ON_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/lightning_rod/lightning_rod_on.png")
const DIRECTIONS:Array[Vector2] = [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]
# 针尖（4×4 头部中心）相对贴图中心的位置，单位为贴图像素。
const TIP_LOCAL:Vector2 = Vector2(0.0,-6.0)
const BAR_OFFSET:Vector2 = Vector2(0.0,66.0)

@export_category("避雷针 / 乌云")
@export var gather_time:float = 3.0
@export var strike_interval:float = 2.0
@export var direction_interval:float = 9.0
@export var bolts_min:int = 2
@export var bolts_max:int = 5
@export var bolt_stagger:float = 0.07
@export var cloud_distance:float = 250.0
@export var cloud_follow:float = 5.0
@export var cloud_map_margin:float = 70.0
@export_category("避雷针 / 落雷")
@export var impact_radius:float = 80.0
@export var impact_damage_ratio:float = 1.0
@export var impact_stun:float = 1.5
@export_category("避雷针 / 电网")
@export var net_lifetime:float = 1.6
@export var net_width:float = 7.0
@export var net_tick:float = 0.1
@export var net_damage_ratio:float = 0.1
@export var net_stun:float = 0.2
@export_category("避雷针 / 能量")
@export var storm_charge_max:float = 100.0
@export var charge_per_bolt:float = 4.0
@export var discharge_cost:float = 8.0
@export var discharge_cooldown:float = 0.45
@export var discharge_radius:float = 95.0
@export var discharge_damage_ratio:float = 0.5
@export var discharge_stun:float = 0.35
@export var tremble_start:float = 0.7
@export var tremble_max:float = 5.0
@export var bar_show_time:float = 1.3
@export var bar_fade_time:float = 0.35
@export_category("避雷针 / 雷圈")
@export var ring_waves:int = 3
@export var ring_wave_gap:float = 0.25
@export var ring_radius:float = 480.0
@export var ring_expand_time:float = 1.3
@export var ring_half_width:float = 22.0
@export var ring_tick:float = 0.08
@export var ring_damage_ratio:float = 0.2
@export var ring_stun:float = 0.5

var dir_index:int = -1
var cycle_age:float = 0.0
var cloud_serial:int = 0
var cloud_position:Vector2 = Vector2.ZERO
var storm_charge:float = 0.0
## 当前云上的电网：{"offset":相对云心的起点,"seed":int,"age":float}；终点始终是针尖。
var nets:Array[Dictionary] = []
var storm:Node2D
var charge_bar:Node2D
var _volleys_fired:int = 0
var _volley_serial:int = 0
var _volley_hits:Dictionary = {}
var _pending_bolts:Array[Dictionary] = []
var _bolt_clock:float = 0.0
var _net_next_tick:Dictionary = {}
var _discharge_wait:float = 0.0
var _manual_dir:int = -1
var _manual_wait:float = 0.0
var _struck_flash:float = 0.0
var _bar_left:float = 0.0
var _bar_seen_charge:float = 0.0
var _base_texture:Texture2D
var _rest_image_position:Vector2
var _rest_cached:bool = false


func _ready() -> void:
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	Unique_Death_Audio = ROD_AUDIO.BREAK[0]
	super._ready()
	if image is Sprite2D:
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_base_texture = image.texture
	cloud_position = global_position
	storm = STORM.new()
	storm.name = "LightningRodStorm"
	storm.rod = self
	add_child(storm)
	charge_bar = BAR.new()
	charge_bar.name = "LightningRodChargeBar"
	charge_bar.rod = self
	charge_bar.position = BAR_OFFSET
	add_child(charge_bar)


func get_preview_texture() -> Texture2D:
	return _base_texture if _base_texture != null else (image.texture if image is Sprite2D else null)


# ---------------------------------------------------------------- 查询（表现与威胁显示共用）

func direction_vector() -> Vector2:
	return DIRECTIONS[dir_index] if dir_index >= 0 else Vector2.UP


func tip_world_position() -> Vector2:
	if image == null or not is_instance_valid(image): return global_position
	return image.global_transform * TIP_LOCAL


func cloud_visible() -> bool:
	return dir_index >= 0 and health > 0


func storm_charge_ratio() -> float:
	return clampf(storm_charge / maxf(storm_charge_max,1.0),0.0,1.0)


func visual_clock() -> float:
	return _view_clock


func bar_alpha() -> float:
	if _bar_left <= 0.0 or health <= 0: return 0.0
	return clampf(_bar_left / maxf(bar_fade_time,0.01),0.0,1.0)


## 本方向下一轮落雷还有多久；本方向不会再劈时返回 -1。
func time_to_next_volley() -> float:
	if dir_index < 0: return -1.0
	var at:float = gather_time + float(_volleys_fired) * strike_interval
	if at >= direction_interval: return -1.0
	return maxf(at - cycle_age,0.0)


func cloud_target() -> Vector2:
	var goal:Vector2 = global_position + direction_vector() * cloud_distance
	var rect:Rect2 = SubmissionCharacterTools.map_rect(self)
	if rect.size.x > cloud_map_margin * 2.0 and rect.size.y > cloud_map_margin * 2.0:
		rect = rect.grow(-cloud_map_margin)
		goal = Vector2(clampf(goal.x,rect.position.x,rect.end.x),clampf(goal.y,rect.position.y,rect.end.y))
	return goal


# ---------------------------------------------------------------- 权威端循环

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or not has_player_control_aim(): return
	var aim:Vector2 = player_control_aim_world_position(global_position) - global_position
	if aim.length_squared() < 1.0: return
	if absf(aim.x) > absf(aim.y): _manual_dir = 3 if aim.x > 0.0 else 2
	else: _manual_dir = 1 if aim.y > 0.0 else 0


func step_mob(delta:float) -> void:
	if Game.now_stop_state: return
	_discharge_wait = maxf(_discharge_wait - delta,0.0)
	_manual_wait = maxf(_manual_wait - delta,0.0)
	if dir_index < 0: _choose_direction(_random_direction(-1))
	if _manual_dir >= 0:
		var wanted:int = _manual_dir
		_manual_dir = -1
		if _manual_wait <= 0.0 and wanted != dir_index:
			_choose_direction(wanted)
			_manual_wait = direction_interval
	cycle_age += delta
	if cycle_age >= direction_interval:
		_choose_direction(_random_direction(dir_index))
	while true:
		var at:float = gather_time + float(_volleys_fired) * strike_interval
		if at >= direction_interval or cycle_age < at: break
		_volleys_fired += 1
		_fire_volley()
	_follow_cloud(delta)
	_advance_bolts(delta)
	_age_nets(delta)
	_net_damage()
	_age_visual(delta)


func _random_direction(exclude:int) -> int:
	var options:Array[int] = []
	for i:int in range(DIRECTIONS.size()):
		if i != exclude: options.append(i)
	return options[rng.randi_range(0,options.size() - 1)]


func _choose_direction(index:int) -> void:
	cloud_serial += 1
	if multiplayer.has_multiplayer_peer(): _receive_direction.rpc(index,cloud_serial)
	_apply_direction(index,cloud_serial)


@rpc("authority","call_remote","reliable")
func _receive_direction(index:int,serial:int) -> void:
	if serial <= cloud_serial and not is_multiplayer_authority() and dir_index == index: return
	_apply_direction(index,serial)


func _apply_direction(index:int,serial:int) -> void:
	if is_instance_valid(storm):
		storm.release_nets(nets,cloud_position,tip_world_position())
		storm.release_cloud(cloud_position,dir_index,cycle_age)
	nets.clear()
	_pending_bolts.clear()
	cloud_serial = serial
	dir_index = clampi(index,0,DIRECTIONS.size() - 1)
	cycle_age = 0.0
	_volleys_fired = 0
	cloud_position = cloud_target()
	ROD_AUDIO.play(self,ROD_AUDIO.Kind.THUNDER,cloud_position,-16.0,-1,0.9)


func _follow_cloud(delta:float) -> void:
	if dir_index < 0: return
	cloud_position = cloud_position.lerp(cloud_target(),1.0 - exp(-maxf(cloud_follow,0.0) * delta))


func _fire_volley() -> void:
	var points:Array[Vector2] = STORM.facing_points(dir_index,-direction_vector())
	if points.is_empty(): return
	var count:int = rng.randi_range(mini(bolts_min,bolts_max),maxi(bolts_min,bolts_max))
	var offsets := PackedVector2Array()
	var seeds := PackedInt32Array()
	var pool:Array[Vector2] = []
	pool.assign(points)
	for i:int in range(count):
		if pool.is_empty(): pool.assign(points)
		offsets.append(pool.pop_at(rng.randi_range(0,pool.size() - 1)))
		seeds.append(rng.randi_range(1,2147483646))
	_volley_serial += 1
	if multiplayer.has_multiplayer_peer(): _receive_volley.rpc(_volley_serial,cloud_serial,offsets,seeds)
	_queue_volley(_volley_serial,offsets,seeds)


@rpc("authority","call_remote","reliable")
func _receive_volley(serial:int,cloud:int,offsets:PackedVector2Array,seeds:PackedInt32Array) -> void:
	if cloud != cloud_serial: return
	_volley_serial = maxi(_volley_serial,serial)
	_queue_volley(serial,offsets,seeds)


func _queue_volley(serial:int,offsets:PackedVector2Array,seeds:PackedInt32Array) -> void:
	for i:int in range(mini(offsets.size(),seeds.size())):
		_pending_bolts.append({"at":_bolt_clock + float(i) * maxf(bolt_stagger,0.0),"offset":offsets[i],"seed":seeds[i],"volley":serial,"first":i == 0})


func _advance_bolts(delta:float) -> void:
	_bolt_clock += delta
	while not _pending_bolts.is_empty() and float(_pending_bolts[0].at) <= _bolt_clock:
		_land_bolt(_pending_bolts.pop_front())


func _land_bolt(bolt:Dictionary) -> void:
	var tip:Vector2 = tip_world_position()
	var start:Vector2 = cloud_position + Vector2(bolt.offset)
	nets.append({"offset":Vector2(bolt.offset),"seed":int(bolt.seed),"age":0.0})
	_struck_flash = 0.1
	if is_instance_valid(storm): storm.add_bolt(start,tip,int(bolt.seed))
	if bool(bolt.first): ROD_AUDIO.play(self,ROD_AUDIO.Kind.THUNDER,tip,-8.0)
	ROD_AUDIO.play(self,ROD_AUDIO.Kind.IMPACT,tip,-13.0 if bool(bolt.first) else -17.0,-1,randf_range(0.95,1.08))
	if not is_multiplayer_authority(): return
	_impact_damage(int(bolt.volley))
	_add_charge(charge_per_bolt)


func _age_nets(delta:float) -> void:
	for net:Dictionary in nets: net.age = float(net.age) + delta
	nets.assign(nets.filter(func(net:Dictionary) -> bool: return float(net.age) < net_lifetime + 0.3))


func _age_visual(delta:float) -> void:
	_struck_flash = maxf(_struck_flash - delta,0.0)
	_bar_left = maxf(_bar_left - delta,0.0)


# ---------------------------------------------------------------- 伤害

func _hit(target:ball,amount:float,point:Vector2,shape:String,radius:float,stun:float) -> void:
	if amount <= 0.0 or is_damage_output_disabled(): return
	var accepted:bool = target.receive_classified_spatial_damage(amount,{"shape":shape,"point":point,"origin":global_position,"radius":radius,
		"source":self,"focus_position":point,"carrier":"area"},&"ordinary",false,false)
	if accepted and is_instance_valid(target) and target.health > 0 and stun > 0.0: target.apply_stun(stun,self)


func _enemies() -> Array[ball]:
	var result:Array[ball] = []
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if U.enemy(self,raw) and (raw as ball).health > 0 and not U.wall_node(raw): result.append(raw as ball)
	return result


func _impact_damage(volley:int) -> void:
	if health <= 0 or is_damage_output_disabled(): return
	var hit:Dictionary = _volley_hits.get(volley,{})
	if _volley_hits.size() > 8: _volley_hits.clear()
	var center:Vector2 = global_position
	var amount:float = attack_damage(impact_damage_ratio)
	for target:ball in _enemies():
		var id:int = target.get_instance_id()
		if hit.has(id): continue
		var point:Vector2 = U.point(target,center)
		if point.distance_to(center) > impact_radius + U.radius(target): continue
		hit[id] = true
		_hit(target,amount,point,"circle",impact_radius,impact_stun)
	_volley_hits[volley] = hit


func _net_damage() -> void:
	if nets.is_empty() or health <= 0 or is_damage_output_disabled(): return
	var tip:Vector2 = tip_world_position()
	var amount:float = attack_damage(net_damage_ratio)
	for target:ball in _enemies():
		var id:int = target.get_instance_id()
		if float(_net_next_tick.get(id,-INF)) > clock: continue
		for net:Dictionary in nets:
			if float(net.age) >= net_lifetime: continue
			var a:Vector2 = cloud_position + Vector2(net.offset)
			var closest:Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position,a,tip)
			var point:Vector2 = U.point(target,closest)
			if U.segment_distance(point,a,tip) > net_width + U.radius(target): continue
			_net_next_tick[id] = clock + maxf(net_tick,0.02)
			_hit(target,amount,Geometry2D.get_closest_point_to_segment(point,a,tip),"circle",net_width,net_stun)
			break
	if _net_next_tick.size() > 64:
		for id:Variant in _net_next_tick.keys():
			if float(_net_next_tick[id]) < clock: _net_next_tick.erase(id)


func _add_charge(amount:float) -> void:
	storm_charge = clampf(storm_charge + amount,0.0,storm_charge_max)
	_bar_left = bar_show_time + bar_fade_time
	if storm_charge >= storm_charge_max: _release_ring()


func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if not is_multiplayer_authority() or amount <= 0.0: return
	_send_rod_sound(ROD_AUDIO.Kind.HIT,global_position,-6.0)
	if health <= 0 or _discharge_wait > 0.0 or storm_charge < discharge_cost or not is_combat_runtime_active(): return
	_discharge_wait = discharge_cooldown
	storm_charge = maxf(storm_charge - discharge_cost,0.0)
	_bar_left = bar_show_time + bar_fade_time
	# 受伤结算中途不嵌套再造成伤害：放电在本帧稍后执行。
	call_deferred("_discharge")


func _discharge() -> void:
	if health <= 0 or not is_combat_runtime_active(): return
	var seed_value:int = rng.randi_range(1,2147483646)
	if multiplayer.has_multiplayer_peer(): _receive_discharge.rpc(seed_value)
	_receive_discharge(seed_value)
	if is_damage_output_disabled(): return
	var center:Vector2 = global_position
	var amount:float = attack_damage(discharge_damage_ratio)
	for target:ball in _enemies():
		var point:Vector2 = U.point(target,center)
		if point.distance_to(center) > discharge_radius + U.radius(target): continue
		_hit(target,amount,point,"circle",discharge_radius,discharge_stun)


@rpc("authority","call_remote","reliable")
func _receive_discharge(seed_value:int) -> void:
	_bar_left = bar_show_time + bar_fade_time
	if is_instance_valid(storm): storm.add_discharge(seed_value,discharge_radius)
	ROD_AUDIO.play(self,ROD_AUDIO.Kind.FIZZ,global_position,-5.0,-1,randf_range(0.9,1.15))
	ROD_AUDIO.play(self,ROD_AUDIO.Kind.IMPACT,global_position,-18.0,-1,1.3)


func _release_ring() -> void:
	storm_charge = 0.0
	if multiplayer.has_multiplayer_peer(): _receive_ring.rpc(global_position)
	_receive_ring(global_position)


@rpc("authority","call_remote","reliable")
func _receive_ring(center:Vector2) -> void:
	_bar_left = bar_show_time + bar_fade_time
	var world:Node = get_tree().current_scene
	if world == null: return
	var ring:Node2D = RING.new()
	ring.name = "LightningRodRing"
	ring.setup(self,center)
	world.add_child(ring,true)
	ROD_AUDIO.play(self,ROD_AUDIO.Kind.THUNDER,center,-1.0)
	ROD_AUDIO.play(self,ROD_AUDIO.Kind.IMPACT,center,-3.0,-1,0.85)
	if is_instance_valid(storm):
		for i:int in range(16): storm.add_spark(center,260.0)


func _send_rod_sound(kind:int,point:Vector2,volume_db:float) -> void:
	if multiplayer.has_multiplayer_peer(): _receive_rod_sound.rpc(kind,point,volume_db)
	_receive_rod_sound(kind,point,volume_db)


@rpc("authority","call_remote","reliable")
func _receive_rod_sound(kind:int,point:Vector2,volume_db:float) -> void:
	ROD_AUDIO.play(self,kind,point,volume_db)


# ---------------------------------------------------------------- 威胁显示

func get_ai_attack_threats(receiver:ball = null) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	if health <= 0 or is_damage_output_disabled() or dir_index < 0: return result
	if is_instance_valid(receiver) and not U.enemy(self,receiver): return result
	var until:float = 0.0 if not _pending_bolts.is_empty() else time_to_next_volley()
	if until >= 0.0:
		result.append({"shape":"circle","position":global_position,"radius":impact_radius,"damage":attack_damage(impact_damage_ratio),"source":self,
			"kind":"lightning_rod_impact","danger_in":until,"danger_duration":0.1,"control":0.8})
	var tip:Vector2 = tip_world_position()
	var net_amount:float = attack_damage(net_damage_ratio)
	for net:Dictionary in nets:
		var left:float = net_lifetime - float(net.age)
		if left <= 0.0: continue
		result.append({"shape":"segment","start":cloud_position + Vector2(net.offset),"end":tip,"radius":net_width,"damage":net_amount,"source":self,
			"kind":"lightning_rod_net","danger_in":0.0,"danger_duration":left,"control":0.4})
	for raw:Node in get_tree().get_nodes_in_group("MCLightningRodRing"):
		if raw.has_method("source_unit") and raw.call("source_unit") == self: result.append_array(raw.call("threats",receiver))
	return result


func get_debug_detection_regions() -> Array:
	if health <= 0 or storm_charge < discharge_cost: return []
	return [{"shape":"circle","position":global_position,"radius":discharge_radius,"kind":"lightning_rod_discharge"}]


# ---------------------------------------------------------------- 客机与表现

func client_visual_step(delta:float) -> void:
	if not is_combat_runtime_active() or Game.now_stop_state or get_tree().paused or health <= 0: return
	if dir_index >= 0: cycle_age += delta
	_follow_cloud(delta)
	_advance_bolts(delta)
	_age_nets(delta)
	_age_visual(delta)


func visual_mob() -> void:
	if image == null or not is_instance_valid(image): return
	if not _rest_cached:
		_rest_image_position = image.position
		_rest_cached = true
	if not is_multiplayer_authority() and not is_equal_approx(storm_charge,_bar_seen_charge): _bar_left = bar_show_time + bar_fade_time
	_bar_seen_charge = storm_charge
	if image is Sprite2D:
		var wanted:Texture2D = ON_TEXTURE if _struck_flash > 0.0 else _base_texture
		if wanted != null and image.texture != wanted: image.texture = wanted
	var ratio:float = storm_charge_ratio()
	var shake := Vector2.ZERO
	var tilt:float = 0.0
	if ratio > tremble_start and health > 0:
		var amount:float = pow((ratio - tremble_start) / maxf(1.0 - tremble_start,0.01),1.5) * tremble_max
		var t:float = _view_clock
		shake = Vector2(sin(t * 83.0) + sin(t * 131.0) * 0.5,cos(t * 97.0) * 0.6) * amount * 0.67
		tilt = sin(t * 71.0) * amount * 0.012
	image.position = _rest_image_position + shake
	image.rotation = tilt


func visual_state() -> Dictionary:
	return {"time":clock,"dir":dir_index,"serial":cloud_serial,"age":cycle_age,"charge":storm_charge,"fired":_volleys_fired}


func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	var serial:int = int(data.get("serial",cloud_serial))
	if serial > cloud_serial: _apply_direction(int(data.get("dir",dir_index)),serial)
	if serial == cloud_serial:
		cycle_age = float(data.get("age",cycle_age))
		_volleys_fired = int(data.get("fired",_volleys_fired))
	storm_charge = float(data.get("charge",storm_charge))


func Die() -> void:
	_pending_bolts.clear()
	if is_instance_valid(storm):
		storm.dissipate()
		# 本体移除后残云继续散完。
		var world:Node = get_tree().current_scene if is_inside_tree() else null
		if world != null and storm.get_parent() != world: storm.reparent(world)
	nets.clear()
	super.Die()


@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	ITEM_DEATH.spawn(self)
