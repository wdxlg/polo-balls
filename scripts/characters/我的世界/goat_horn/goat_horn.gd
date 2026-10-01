extends "res://scripts/characters/我的世界/new5/base.gd"
# 山羊角（原版 goat_horn 物品贴图）：每隔一段时间吹响号角，从屏幕外召来一群山羊冲向随机敌人。
# 吹奏时移速减半；起手阶段被眩晕会中断并稍后重试。山羊是瞬时技能实体（goat_charger.gd），
# 冲撞按速度结算伤害与击退，持续顶住会周期推撞，撞完或错过后加速冲出屏幕。
const GOAT = preload("res://scripts/characters/我的世界/goat_horn/goat_charger.gd")
const GOAT_AUDIO = preload("res://scripts/characters/我的世界/goat_horn/goat_horn_audio.gd")
const COMBAT_FX = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
# 声波环取山羊角物品贴图中较亮的灰褐、骨白两色，外加近白高光，保证在深色地面上可见。
const RING_PALETTE:Array[Color] = [Color("817e76"),Color("a3a393"),Color("f2f0e6")]
# 号口（喇叭口）在贴图中心左上方，单位为贴图像素；朝外方向指向左上。
const BELL_LOCAL:Vector2 = Vector2(-3.5,-4.5)
const BELL_OUTWARD:Vector2 = Vector2(-0.6,-0.8)
const BLOW_TILT:float = 0.4
const RING_DELAYS:Array[float] = [0.0,0.15,0.3]
const SYNC_INTERVAL:float = 0.075
const STEP_TOKENS_PER_SECOND:float = 24.0

enum BlowPhase { IDLE, WINDUP, HOLD }

@export var first_blow_delay:float = 4.0
@export var blow_interval:float = 15.0
@export var goats_min:int = 14
@export var goats_max:int = 16
@export var blow_windup:float = 0.35
@export var blow_hold:float = 1.4
@export var blow_move_ratio:float = 0.5
@export var stun_retry_delay:float = 1.0
@export var goat_spawn_start:float = 0.35
# 号声后山羊一只一只陆续出现：相邻两只间隔 goat_spawn_gap ± goat_spawn_jitter 秒；吹奏结束后仍按时间表继续出现。
@export var goat_spawn_gap:float = 0.4
@export var goat_spawn_jitter:float = 0.08
@export var goat_spawn_margin:float = 90.0

var _flip:bool = false
var _blow_wait:float = 4.0
var _blow_phase:int = BlowPhase.IDLE
var _blow_age:float = 0.0
var _blow_serial:int = 0
var _manual_request:bool = false
var _pending_goats:Array[float] = []
var _goat_clock:float = 0.0
var _goat_seq:int = 0
var _goats:Dictionary = {}
var _client_freed:Dictionary = {}
var _sync_wait:float = 0.0
var _synced_any:bool = false
var _step_tokens:float = STEP_TOKENS_PER_SECOND
var _last_goat_sound:Dictionary = {}
var _goat_sound_serial:int = 0
var _rest_image_position:Vector2
var _rest_image_scale:Vector2 = Vector2.ONE
var _rest_image_cached:bool = false


func _ready() -> void:
	Hit_Audio = ""
	Dead_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	Block_Audio = ""
	BlockBreak_Audio = ""
	Unique_Death_Audio = AUDIO.EVENTS["entity.item.break"][0].stream
	super._ready()
	_blow_wait = first_blow_delay
	if image is Sprite2D:
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func controlled_attack_action() -> void:
	if is_player_controlled() and is_multiplayer_authority(): _manual_request = true


func player_control_action_cancelled(index:int) -> void:
	if index == 0: _manual_request = false


func set_player_control_peer(peer_id:int) -> void:
	if peer_id != player_control_peer_id: _manual_request = false
	super.set_player_control_peer(peer_id)


func blow_ready() -> bool:
	return _blow_phase == BlowPhase.IDLE and _blow_wait <= 0.0


func step_mob(delta:float) -> void:
	if not _pending_goats.is_empty():
		_goat_clock += delta
		while not _pending_goats.is_empty() and _pending_goats[0] <= _goat_clock:
			_pending_goats.pop_front()
			_spawn_goat()
	match _blow_phase:
		BlowPhase.IDLE:
			_update_facing()
			_blow_wait = maxf(_blow_wait - delta,0.0)
			var want:bool = false
			if is_player_controlled():
				want = _manual_request
				_manual_request = false
			else:
				want = pick_goat_target() != null
			if want and _blow_wait <= 0.0 and can_act(): _begin_blow()
		BlowPhase.WINDUP:
			set_motion_speed_factor(&"goat_horn_blow",self,blow_move_ratio,0.1)
			if dizziness or not can_act():
				_blow_phase = BlowPhase.IDLE
				_blow_age = 0.0
				_blow_wait = maxf(_blow_wait,stun_retry_delay)
				return
			_blow_age += delta
			if _blow_age >= blow_windup: _toot()
		BlowPhase.HOLD:
			set_motion_speed_factor(&"goat_horn_blow",self,blow_move_ratio,0.1)
			_blow_age += delta
			if _blow_age - blow_windup >= blow_hold:
				_blow_phase = BlowPhase.IDLE
				_blow_age = 0.0


func _update_facing() -> void:
	var hint:Vector2 = Vector2.ZERO
	if is_player_controlled():
		if has_player_control_aim(): hint = player_control_aim_world_position(global_position) - global_position
	else:
		var target:ball = U.nearest(self)
		if target != null: hint = U.point(target,global_position) - global_position
	# 原图号口朝左：敌人在左边保持原图，在右边水平镜像；小幅横向抖动不来回翻。
	if absf(hint.x) > 8.0: _flip = hint.x > 0.0


func _begin_blow() -> void:
	_blow_phase = BlowPhase.WINDUP
	_blow_age = 0.0
	_blow_wait = blow_interval
	set_motion_speed_factor(&"goat_horn_blow",self,blow_move_ratio,0.1)


func _toot() -> void:
	_blow_phase = BlowPhase.HOLD
	_blow_age = blow_windup
	_blow_serial += 1
	_pending_goats.clear()
	var count:int = rng.randi_range(mini(goats_min,goats_max),maxi(goats_min,goats_max))
	_goat_clock = 0.0
	var t:float = goat_spawn_start
	for i:int in range(count):
		_pending_goats.append(t)
		t += maxf(goat_spawn_gap + rng.randf_range(-goat_spawn_jitter,goat_spawn_jitter),0.1)
	_prune_goats()
	var call_index:int = _voice_rng.randi_range(0,GOAT_AUDIO.variant_count(GOAT_AUDIO.KIND_CALL) - 1)
	var bell:Vector2 = bell_world_position()
	var outward:Vector2 = bell_outward_direction()
	if multiplayer.has_multiplayer_peer(): _receive_toot.rpc(_blow_serial,call_index,bell,outward)
	_receive_toot(_blow_serial,call_index,bell,outward)


@rpc("authority","call_remote","reliable")
func _receive_toot(serial:int,call_index:int,bell:Vector2,outward:Vector2) -> void:
	_blow_serial = maxi(_blow_serial,serial)
	if not is_multiplayer_authority():
		_blow_phase = BlowPhase.HOLD
		_blow_age = blow_windup
	GOAT_AUDIO.play(self,GOAT_AUDIO.KIND_CALL,call_index,bell)
	for i:int in range(RING_DELAYS.size()):
		if RING_DELAYS[i] <= 0.0: _spawn_ring(bell,outward,i)
		else: get_tree().create_timer(RING_DELAYS[i],false).timeout.connect(_spawn_ring.bind(bell,outward,i))


func _spawn_ring(point:Vector2,outward:Vector2,index:int) -> void:
	if not is_inside_tree(): return
	var world:Node = get_tree().current_scene
	if world == null: return
	# 起始半径约为号身显示宽度的一半，三道波依次更大，最终扩散到约号身的 3 倍。
	var horn_width:float = 16.0 * absf(image.global_scale.x) if image != null and is_instance_valid(image) else 20.0
	var ring:Node2D = COMBAT_FX.expanding_ring(world,point,horn_width * (0.5 + 0.2 * index),
		{"name":"GoatHornCallRing","palette":RING_PALETTE,"end_scale":3.2 + 0.4 * index,"lifetime":0.6,
		 "direction":outward,"depth_ratio":0.4})
	if ring != null: ring.add_to_group("GoatHornCallRing")


func bell_world_position() -> Vector2:
	if image == null or not is_instance_valid(image): return global_position
	return image.global_transform * Vector2(-BELL_LOCAL.x if _flip else BELL_LOCAL.x,BELL_LOCAL.y)


func bell_outward_direction() -> Vector2:
	var local:Vector2 = Vector2(-BELL_OUTWARD.x if _flip else BELL_OUTWARD.x,BELL_OUTWARD.y)
	var basis:Transform2D = image.global_transform if image != null and is_instance_valid(image) else global_transform
	var world_dir:Vector2 = basis.basis_xform(local)
	return world_dir.normalized() if world_dir.length_squared() > 0.000001 else Vector2.UP


## 随机选一名可锁定的敌人（同 Team、皓宸一方与不可选中者已由 U.enemy 排除）。
func pick_goat_target() -> ball:
	var candidates:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if U.enemy(self,node) and node.is_combat_lockable() and not U.wall_node(node) and node.health > 0:
			candidates.append(node as ball)
	if candidates.is_empty(): return null
	return candidates[rng.randi_range(0,candidates.size() - 1)]


func _spawn_goat() -> void:
	var target:ball = pick_goat_target()
	var world:Node = get_tree().current_scene
	if target == null or world == null: return
	var aim:Vector2 = U.point(target,global_position)
	_goat_seq += 1
	var goat:Node2D = GOAT.new()
	goat.call(&"setup_authority",self,_goat_seq,target,goat_spawn_point(aim),rng.randi())
	world.add_child(goat)
	_goats[_goat_seq] = goat


## 从目标出发沿随机方向射向镜头矩形外沿（再外扩一圈），保证山羊从屏幕外跑进来。
func goat_spawn_point(aim:Vector2) -> Vector2:
	var view:Rect2 = GOAT.view_rect(self)
	if view.size.x <= 1.0 or view.size.y <= 1.0: view = Rect2(aim - Vector2(600,400),Vector2(1200,800))
	view = view.expand(aim).grow(goat_spawn_margin)
	var dir:Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0,TAU))
	var t:float = INF
	if dir.x > 0.0001: t = minf(t,(view.end.x - aim.x) / dir.x)
	elif dir.x < -0.0001: t = minf(t,(view.position.x - aim.x) / dir.x)
	if dir.y > 0.0001: t = minf(t,(view.end.y - aim.y) / dir.y)
	elif dir.y < -0.0001: t = minf(t,(view.position.y - aim.y) / dir.y)
	return aim + dir * (t if is_finite(t) else 800.0)


## 山羊的声音事件：由权威端山羊挑好变体后经本体可靠下发。脚步受全体共享的每秒令牌限制。
func emit_goat_sound(kind:int,index:int,point:Vector2) -> bool:
	if not is_multiplayer_authority(): return false
	if kind == GOAT_AUDIO.KIND_STEP:
		if _step_tokens < 1.0: return false
		_step_tokens -= 1.0
	_goat_sound_serial += 1
	if multiplayer.has_multiplayer_peer(): _receive_goat_sound.rpc(_goat_sound_serial,kind,index,point)
	_receive_goat_sound(_goat_sound_serial,kind,index,point)
	return true


@rpc("authority","call_remote","reliable")
func _receive_goat_sound(serial:int,kind:int,index:int,point:Vector2) -> void:
	if int(_last_goat_sound.get(kind,0)) >= serial: return
	_last_goat_sound[kind] = serial
	GOAT_AUDIO.play(self,kind,index,point)


func _process(delta:float) -> void:
	super._process(delta)
	# 脚步配额按真实战斗时间回充，不依赖本体状态机（本体被控时山羊照样有脚步声）。
	if is_combat_runtime_active(): _step_tokens = minf(_step_tokens + STEP_TOKENS_PER_SECOND * delta,STEP_TOKENS_PER_SECOND)
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer(): return
	_sync_wait -= delta
	if _sync_wait > 0.0: return
	_sync_wait = SYNC_INTERVAL
	_prune_goats()
	# 没有山羊时只补发一次空表，让客户端清掉最后一批。
	if _goats.is_empty() and not _synced_any: return
	_synced_any = not _goats.is_empty()
	var packed:PackedFloat32Array = PackedFloat32Array()
	for id:Variant in _goats.keys():
		var goat:Node2D = _goats[id]
		var h:Vector2 = goat.get("heading")
		packed.append_array([float(id),goat.global_position.x,goat.global_position.y,h.x,h.y,float(goat.get("speed")),float(goat.call(&"network_flags"))])
	_receive_goats.rpc(packed)


func _prune_goats() -> void:
	for id:Variant in _goats.keys():
		var goat:Variant = _goats[id]
		if not is_instance_valid(goat) or (goat as Node).is_queued_for_deletion(): _goats.erase(id)


@rpc("authority","call_remote","unreliable_ordered")
func _receive_goats(packed:PackedFloat32Array) -> void:
	if is_multiplayer_authority() or not is_inside_tree(): return
	var world:Node = get_tree().current_scene
	var present:Dictionary = {}
	var i:int = 0
	while i + 6 < packed.size():
		var id:int = int(packed[i])
		var point:Vector2 = Vector2(packed[i + 1],packed[i + 2])
		var dir:Vector2 = Vector2(packed[i + 3],packed[i + 4])
		var speed_value:float = packed[i + 5]
		var flags:int = int(packed[i + 6])
		i += 7
		present[id] = true
		var existing:Variant = _goats.get(id)
		if is_instance_valid(existing):
			existing.call(&"apply_network_state",point,dir,speed_value,flags)
		elif not _client_freed.has(id) and world != null:
			var goat:Node2D = GOAT.new()
			goat.call(&"setup_puppet",self,id,point,dir,speed_value,flags)
			world.add_child(goat)
			_goats[id] = goat
	for id:Variant in _goats.keys():
		if present.has(id): continue
		var gone:Variant = _goats[id]
		if is_instance_valid(gone): (gone as Node).queue_free()
		_goats.erase(id)
		_client_freed[id] = true


func _free_goats() -> void:
	for goat:Variant in _goats.values():
		if is_instance_valid(goat): (goat as Node).queue_free()
	_goats.clear()


func Die() -> void:
	_pending_goats.clear()
	_blow_phase = BlowPhase.IDLE
	for goat:Variant in _goats.values():
		if is_instance_valid(goat): goat.call(&"begin_exit")
	super.Die()


func _exit_tree() -> void:
	_free_goats()
	super._exit_tree()


@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	ITEM_DEATH.spawn(self)


func client_visual_step(delta:float) -> void:
	if _blow_phase != BlowPhase.IDLE and is_combat_runtime_active(): _blow_age += delta


func visual_mob() -> void:
	if image == null or not is_instance_valid(image): return
	if not _rest_image_cached:
		_rest_image_position = image.position
		_rest_image_scale = image.scale
		_rest_image_cached = true
	var tilt:float = 0.0
	var jitter:float = 0.0
	var pulse:float = 1.0
	if _blow_phase == BlowPhase.WINDUP:
		tilt = BLOW_TILT * smoothstep(0.0,maxf(blow_windup,0.01),_blow_age)
	elif _blow_phase == BlowPhase.HOLD:
		var t:float = maxf(_blow_age - blow_windup,0.0)
		tilt = BLOW_TILT * (1.0 - smoothstep(blow_hold - 0.35,blow_hold,t))
		# 吹响瞬间：号身震颤并轻微鼓胀，随后衰减。
		jitter = sin(t * 70.0) * 0.05 * exp(-t * 2.5)
		pulse = 1.0 + 0.12 * exp(-t * 7.0)
	set_character_visual_flip_h(_flip)
	# 号口在左时抬起为顺时针（正角），镜像后取反。
	image.rotation = (tilt + jitter) * (-1.0 if _flip else 1.0)
	image.scale = _rest_image_scale * pulse
	var pose:Vector2 = _rest_image_position + Vector2(0.0,sin(_view_clock * 2.6) * 1.6)
	if not image.position.is_equal_approx(pose): image.position = pose


func visual_state() -> Dictionary:
	return {"time":clock,"flip":_flip,"blow":_blow_serial,"phase":_blow_phase,"age":_blow_age}


func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	_flip = bool(data.get("flip",_flip))
	_blow_phase = int(data.get("phase",_blow_phase))
	_blow_age = float(data.get("age",_blow_age))
