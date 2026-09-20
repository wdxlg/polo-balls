extends Node2D
## One shared cold meter per victim, independent of how many snow golems hit it.
## Uses the existing Speed buff and reference-counted motion-lock protocol.
const LIMIT:float = 100.0
const PHASE_AUDIO = preload("res://scripts/characters/我的世界/snow_golem/audio.gd")
const ICE_SHELL = preload("res://scripts/characters/我的世界/snow_golem/ice_shell.gd")
const MAX_SLOW:float = 0.65
const BUFF_KEY:String = "mc_snow_cold"
# 寒冷同时拖慢出手：满值时攻击冷却 ×2（攻速减半）。通过 Attack_Cooling 的 mul Buff 走公共管线。
const MAX_ATTACK_SLOW:float = 0.5
const ATTACK_BUFF_KEY:String = "mc_snow_cold_attack"
# 冻住期间：每 FREEZE_TICK_INTERVAL 秒扣 FREEZE_TICK_DAMAGE 点（无视护盾），并且受到的一切伤害加倍。
# 加倍用 Damage_reduction 的 add Buff 实现：base - (1-base) 恰好让 (1-Damage_reduction) 翻倍。
const FREEZE_TICK_INTERVAL:float = 0.35
const FREEZE_TICK_DAMAGE:float = 2.0
const FREEZE_DAMAGE_MULTIPLIER:float = 2.0
const VULN_BUFF_KEY:String = "mc_snow_frozen_vulnerable"
# 冻住期间被攻击：冰碎脆响的最小间隔（同一帧多段伤害只响一次）。
const HIT_SOUND_INTERVAL:float = 0.09
const LOCK_COUNT:StringName = &"generic_motion_lock_count"
const LOCK_BASE:StringName = &"generic_motion_lock_baseline"
const FLAKES:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/snow_golem/snowflake_0.png"),
	preload("res://Images/characters/我的世界/snow_golem/snowflake_1.png"),
	preload("res://Images/characters/我的世界/snow_golem/snowflake_2.png"),
	preload("res://Images/characters/我的世界/snow_golem/snowflake_3.png"),
	preload("res://Images/characters/我的世界/snow_golem/snowflake_4.png"),
	preload("res://Images/characters/我的世界/snow_golem/snowflake_5.png"),
	preload("res://Images/characters/我的世界/snow_golem/snowflake_6.png"),
	preload("res://Images/characters/我的世界/snow_golem/snowflake_7.png")]
var target:ball
var amount:float = 0.0
var frozen_left:float = 0.0
var freeze_total:float = 0.0
var _ice:Node2D
var freeze_count:int = 0
var _locked:bool = false
var _buff:Buff
var _attack_buff:Buff
var _vuln_buff:Buff
var _freeze_tick_left:float = 0.0
var _source:ball
var freeze_damage_dealt:float = 0.0
# 冻住期间的外来命中检测：记录上次看到的生命/护盾，真实下降即视为被打（冻伤 tick 自己扣的血在 _freeze_tick 里先记账，不算）。
var _watch_health:float = 0.0
var _watch_block:float = 0.0
var _hit_sound_left:float = 0.0
var frozen_hit_count:int = 0
var _spawn_budget:float = 0.0
var particles:Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _last_image:CanvasItem
var _last_tint:float = -1.0
var _sync_left:float = 0.0

static func ensure(victim:ball) -> Node2D:
	var existing:Node = victim.get_node_or_null("MCSnowCold")
	if is_instance_valid(existing) and not existing.is_queued_for_deletion(): return existing as Node2D
	var effect:Node2D = load("res://scripts/characters/我的世界/snow_golem/cold.gd").new()
	effect.name = "MCSnowCold"
	effect.target = victim
	effect.set_multiplayer_authority(victim.get_multiplayer_authority())
	victim.add_child(effect)
	return effect

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 8
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	add_to_group("MCSnowCold")
	_buff = Buff.new(2,0.25,Buff.Buff_types.Speed,1.0,Buff.Algorithms.mul)
	_attack_buff = Buff.new(2,0.25,Buff.Buff_types.Attack_Cooling,1.0,Buff.Algorithms.mul)
	_vuln_buff = Buff.new(2,0.25,Buff.Buff_types.Damage_reduction,0.0,Buff.Algorithms.add)

func add_cold(value:float,duration:float = 1.4,source:ball = null) -> bool:
	if not is_multiplayer_authority() or not _usable() or not target.is_combat_runtime_active(): return false
	if value <= 0.0 or frozen_left > 0.0 or not target.can_receive_negative_effects(): return false
	set_process(true)
	set_physics_process(true)
	if source != null and is_instance_valid(source): _source = source
	amount = minf(LIMIT,amount+value*target.get_negative_effect_ratio())
	if amount >= LIMIT-0.0001:
		amount = 0.0
		frozen_left = maxf(duration,0.05)*target.get_negative_effect_ratio()
		freeze_total = frozen_left
		freeze_count += 1
		_freeze_tick_left = FREEZE_TICK_INTERVAL
		_acquire_lock()
		_begin_ice()
		_hit_sound_left = 0.0
		_watch()
		_play_phase("freeze")
	_update_buff()
	_sync_state()
	_update_tint()
	return true

func _play_phase(phase:String) -> void:
	if not is_multiplayer_authority() or not _usable(): return
	var field:Node = get_tree().current_scene.get_node_or_null("MCSnowField")
	if is_instance_valid(field) and not field.is_queued_for_deletion(): field.emit_phase(phase,target.global_position)
	else: PHASE_AUDIO.play_phase(self,phase,target.global_position)

func _begin_ice() -> void:
	if not is_instance_valid(_ice):
		_ice = ICE_SHELL.new()
		_ice.name = "IceEnclosure"
		add_child(_ice)
	_ice.begin(self)

func _end_ice(shatter:bool = true) -> void:
	if is_instance_valid(_ice): _ice.finish(shatter)

func _usable() -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion() and target.health > 0 and target.is_inside_tree()

func speed_ratio() -> float: return 1.0-MAX_SLOW*clampf(amount/LIMIT,0.0,1.0)
# 攻速倍率（越低出手越慢）与对应的攻击冷却倍率。
func attack_speed_ratio() -> float: return 1.0-MAX_ATTACK_SLOW*clampf(amount/LIMIT,0.0,1.0)
func attack_cooling_ratio() -> float: return 1.0/maxf(attack_speed_ratio(),0.05)
# 冻住时叠加到 Damage_reduction 上的量：让 (1-Damage_reduction) 变为原来的 FREEZE_DAMAGE_MULTIPLIER 倍。
func frozen_vulnerability_delta() -> float:
	if not is_instance_valid(target): return 0.0
	var base:float = float(target.default_properties.get("Damage_reduction",target.Damage_reduction))
	return -(FREEZE_DAMAGE_MULTIPLIER-1.0)*(1.0-base)
func intensity() -> float: return 1.0 if frozen_left > 0.0 else clampf(amount/LIMIT,0.0,1.0)
func particle_rate() -> float: return 0.0 if intensity() <= 0.0 else 3.0+33.0*intensity()

func _update_buff() -> void:
	if not is_instance_valid(target): return
	var key:int = get_instance_id()
	var slowed:bool = amount > 0.0
	var frozen:bool = frozen_left > 0.0
	if not slowed and not frozen:
		if target.Buff_Dic.has(key): target.Buff_Dic.erase(key)
		return
	if not target.Buff_Dic.has(key): target.Buff_Dic[key] = {}
	var entry:Dictionary = target.Buff_Dic[key]
	if slowed:
		_buff.amount = speed_ratio()
		_buff.duration = 0.25
		_attack_buff.amount = attack_cooling_ratio()
		_attack_buff.duration = 0.25
		entry[BUFF_KEY] = _buff
		entry[ATTACK_BUFF_KEY] = _attack_buff
	else:
		entry.erase(BUFF_KEY)
		entry.erase(ATTACK_BUFF_KEY)
	if frozen:
		_vuln_buff.amount = frozen_vulnerability_delta()
		_vuln_buff.duration = 0.25
		entry[VULN_BUFF_KEY] = _vuln_buff
	else:
		entry.erase(VULN_BUFF_KEY)
	if entry.is_empty(): target.Buff_Dic.erase(key)

func _freeze_tick() -> void:
	if not _usable(): return
	var source:Node = _source if is_instance_valid(_source) else null
	var before:float = float(target.health)
	# 冰从体内冻伤，护盾挡不住；伤害本身也吃冻结的加倍。
	target.receive_positional_damage(FREEZE_TICK_DAMAGE,target.global_position,true,source)
	freeze_damage_dealt += maxf(before-float(target.health),0.0)
	_watch()

func _watch() -> void:
	if not is_instance_valid(target): return
	_watch_health = float(target.health)
	_watch_block = float(target.block)

# 冻住的人挨打 → 冰壳被敲裂的脆响。任何伤害路径（碰撞、技能、流血）只要真的扣了生命或护盾都算。
func _detect_frozen_hit() -> void:
	if not _usable(): return
	var hit:bool = float(target.health) < _watch_health-0.001 or float(target.block) < _watch_block-0.001
	_watch()
	if not hit or _hit_sound_left > 0.0: return
	_hit_sound_left = HIT_SOUND_INTERVAL
	frozen_hit_count += 1
	_play_phase("ice_hit")

func _acquire_lock() -> void:
	if _locked or not is_instance_valid(target): return
	var count:int = int(target.get_meta(LOCK_COUNT,0))
	if count <= 0: target.set_meta(LOCK_BASE,target.dizziness)
	target.set_meta(LOCK_COUNT,count+1)
	target.dizziness = true
	_locked = true

func _release_lock() -> void:
	if not _locked: return
	_locked = false
	if not is_instance_valid(target): return
	var count:int = maxi(0,int(target.get_meta(LOCK_COUNT,0))-1)
	if count > 0:
		target.set_meta(LOCK_COUNT,count)
	else:
		target.dizziness = bool(target.get_meta(LOCK_BASE,false))
		target.remove_meta(LOCK_COUNT)
		target.remove_meta(LOCK_BASE)

func advance(delta:float) -> void:
	if not _usable():
		queue_free()
		return
	if not target.is_combat_runtime_active(): return
	if not target.can_receive_negative_effects():
		amount = 0.0
		frozen_left = 0.0
		freeze_total = 0.0
		_end_ice(false)
		_release_lock()
		_update_buff()
		_sync_state()
		queue_free()
		return
	if frozen_left > 0.0:
		frozen_left = maxf(0.0,frozen_left-maxf(delta,0.0))
		_hit_sound_left = maxf(0.0,_hit_sound_left-maxf(delta,0.0))
		_detect_frozen_hit()
		_freeze_tick_left -= maxf(delta,0.0)
		var guard:int = 0
		while _freeze_tick_left <= 0.0 and guard < 16 and _usable():
			_freeze_tick_left += FREEZE_TICK_INTERVAL
			guard += 1
			_freeze_tick()
		if not _usable():
			queue_free()
			return
		if frozen_left <= 0.0:
			freeze_total = 0.0
			_end_ice(true)
			_play_phase("ice_break")
			_release_lock()
			_sync_state()
	_update_buff()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = 0.25
		_sync_state()
	if amount <= 0.0 and frozen_left <= 0.0 and particles.is_empty():
		_update_tint()
		set_process(false)
		set_physics_process(false)

func _physics_process(delta:float) -> void:
	if is_multiplayer_authority(): advance(delta)

func _sync_state() -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer() or not is_instance_valid(target): return
	# Field exists on each peer before a shot can apply cold; status children are
	# created locally from a victim path, not sent as unsafe Object references.
	var field:Node = get_tree().current_scene.get_node_or_null("MCSnowField")
	if is_instance_valid(field): field.sync_cold(target,amount,frozen_left,freeze_total)

func accept_state(value:float,frozen:float,total:float = 0.0) -> void:
	set_process(true)
	var was_frozen:bool = frozen_left > 0.0
	amount = clampf(value,0.0,LIMIT)
	frozen_left = maxf(frozen,0.0)
	if frozen_left > 0.0:
		# Keep total duration, including negative-effect reduction, for late joins
		# and progress-based shaking. Do not restart the escape on each sync.
		freeze_total = maxf(total,frozen_left) if total > 0.0 else maxf(freeze_total,frozen_left)
		if not was_frozen or not is_instance_valid(_ice) or not _ice.enclosed: _begin_ice()
		else: _ice.refresh()
	else:
		freeze_total = 0.0
		if was_frozen: _end_ice(true)
	_update_tint()

func _update_tint() -> void:
	if not is_instance_valid(target) or not is_instance_valid(target.image): return
	var visual:CanvasItem = target.image as CanvasItem
	if _last_image != visual and is_instance_valid(_last_image): _last_image.set_instance_shader_parameter("snow_cold",0.0)
	var value:float = intensity()
	if visual != _last_image or not is_equal_approx(value,_last_tint):
		# Dedicated channel: never replace team color, poison, alpha, or hit flashes.
		visual.set_instance_shader_parameter("snow_cold",value)
		_last_image = visual
		_last_tint = value

func _process(delta:float) -> void:
	if not _usable():
		queue_free()
		return
	global_position = target.global_position
	_update_tint()
	if not target.is_combat_runtime_active(): return
	if not is_multiplayer_authority() and frozen_left > 0.0:
		frozen_left = maxf(0.0,frozen_left-delta)
		if frozen_left <= 0.0:
			freeze_total = 0.0
			_end_ice(true)
			_update_tint()
	for i:int in range(particles.size()-1,-1,-1):
		particles[i].age = float(particles[i].age)+delta
		if float(particles[i].age) >= float(particles[i].life):
			particles.remove_at(i)
		else:
			particles[i].point += particles[i].velocity*delta
	_spawn_budget += particle_rate()*delta
	while _spawn_budget >= 1.0 and particles.size() < 40:
		_spawn_budget -= 1.0
		var radius:float = maxf(target.get_crowd_separation_radius_world(),7.0)
		particles.append({"point":target.global_position+Vector2(_rng.randf_range(-radius,radius),_rng.randf_range(-radius,radius)),"velocity":Vector2(_rng.randf_range(-8.0,8.0),_rng.randf_range(-19.0,-8.0)),"age":0.0,"life":_rng.randf_range(0.65,1.0),"size":_rng.randf_range(2.8,5.0)})
	_spawn_budget = minf(_spawn_budget,1.0)
	queue_redraw()
	if not is_multiplayer_authority() and amount <= 0.0 and frozen_left <= 0.0 and particles.is_empty():
		_update_tint()
		set_process(false)

func _draw() -> void:
	for part:Dictionary in particles:
		var phase:float = float(part.age)/float(part.life)
		var texture:Texture2D = FLAKES[clampi(int(phase*8.0),0,7)]
		var size:Vector2 = Vector2.ONE*float(part.size)
		draw_texture_rect(texture,Rect2(to_local(part.point)-size*0.5,size),false,Color(0.94,0.98,1.0,1.0-smoothstep(0.7,1.0,phase)))

func _exit_tree() -> void:
	_end_ice(false)
	_release_lock()
	if is_instance_valid(target): target.Buff_Dic.erase(get_instance_id())
	if is_instance_valid(_last_image): _last_image.set_instance_shader_parameter("snow_cold",0.0)
