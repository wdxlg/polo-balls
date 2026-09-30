extends "res://scripts/characters/我的世界/mc_mob_base.gd"

# 蜘蛛地网：铺在地面的蛛网区域（ball 实体，2 次攻击可破坏，9 秒自然消失）。
# 区域内的敌人持续受减速 Buff 与蛛丝毒伤；蜘蛛本体免疫自己的网。
const AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")

var _lifetime:float = 9.0
var _left:float = 9.0
var _tick:float = 0.8
var _tick_left:float = 0.8
var _damage:float = 5.0
var _slow_multiplier:float = 0.45
var _slow_duration:float = 1.0
var _slow_buff:String = "蜘蛛_地网"
var _durability:int = 2
var _flash:float = 0.0
var _sound_left:float = 0.0
var _consumed:bool = false
# 椭圆半轴（世界单位），与场景 100x72 形状一致。
var _half:Vector2 = Vector2(50.0,36.0)

func _ready() -> void:
	Type = Ball_Type.Shooter_with_Health
	collision_layer = 0
	collision_mask = 1
	super._ready()
	self_hitbox.set_deferred("monitoring",false)
	add_to_group("MCWebPatch")
	if health_bar != null:
		health_bar.suppress_floating_text = true
		health_bar.hide()
		health_bar.visibility_layer = 0
		health_bar.process_mode = Node.PROCESS_MODE_DISABLED

func setup(_caster:ball,lifetime:float,tick:float,damage:float,slow_multiplier:float,slow_duration:float,slow_buff:String) -> void:
	_lifetime = maxf(lifetime,0.5)
	_left = _lifetime
	_tick = maxf(tick,0.2)
	_tick_left = _tick * 0.5
	_damage = maxf(damage,0.0)
	_slow_multiplier = clampf(slow_multiplier,0.05,1.0)
	_slow_duration = maxf(slow_duration,0.2)
	_slow_buff = slow_buff

func has_collision_damage() -> bool: return false

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if _consumed or health <= 0:
		retire()
		return
	if not mc_live(): return
	_left -= delta
	_flash = maxf(_flash - delta,0.0)
	_sound_left = maxf(_sound_left - delta,0.0)
	if _left <= 0.0:
		retire()
		return
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left += _tick
		_tick_zone()
	queue_redraw()

# 地网不移动：吞掉公共移动。
func move(_speed:float,_delta:float) -> void: pass
func when_collide(_speed:float,_collision:KinematicCollision2D) -> void: pass

func _inside(point:Vector2) -> bool:
	var p:Vector2 = (point - global_position) / _half
	return p.length_squared() <= 1.0

func _tick_zone() -> void:
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not target is ball or not mc_enemy(target): continue
		var candidate:ball = target
		if not _inside(candidate.global_position): continue
		# 先刷新减速，再结算毒伤：毒伤本身吃“网中猎物”加成。
		_apply_slow(candidate)
		var bonus:float = 1.0
		if Master != null and is_instance_valid(Master) and Master.has_method("webbed_multiplier"):
			bonus = Master.call("webbed_multiplier",candidate)
		if mc_damage_with_impact(candidate,_damage * bonus,candidate.global_position):
			if _sound_left <= 0.0:
				_sound_left = 0.5
				AUDIO.play(self,"entity.spider_web.patch",candidate.global_position,-5.0)

func _apply_slow(candidate:ball) -> void:
	if candidate == null or not is_instance_valid(candidate) or candidate.health <= 0: return
	var tree:SceneTree = candidate.get_tree()
	if tree == null: return
	var world:Node = tree.current_scene
	if world == null or not world.has_method("new_buff"): return
	world.call("new_buff",candidate,Master if is_instance_valid(Master) else self,_slow_buff,Buff.new(2,_slow_duration,Buff.Buff_types.Speed,_slow_multiplier,Buff.Algorithms.mul),"cover")

# 耐久按攻击次数计算，单次再高的伤害也只扣一格。
func take_damage(damage:float,_ignore_block:bool = false) -> void:
	if damage <= 0.0 or health <= 0 or not is_multiplayer_authority(): return
	_durability -= 1
	_flash = 0.15
	AUDIO.play(self,"entity.spider_web.hit",global_position,-4.0)
	if _durability <= 0:
		health = 0
		retire()

func retire() -> void:
	if is_queued_for_deletion(): return
	_consumed = true
	if is_in_group("MCWebPatch"): remove_from_group("MCWebPatch")
	if is_in_group("Ball"): remove_from_group("Ball")
	hide()
	if self_hitbox != null:
		self_hitbox.set_deferred("monitoring",false)
	queue_free()

func Die() -> void: retire()

func _draw() -> void:
	# 程序化蛛网：放射丝 + 同心椭圆蛛丝；最后 2 秒淡出；受击闪白。
	var fade:float = 1.0
	if _left < 2.0: fade = clampf(_left / 2.0,0.0,1.0)
	var tint:Color = Color(0.88,0.92,0.96,0.85 * fade)
	if _flash > 0.0: tint = Color(1.0,1.0,1.0,fade)
	for i:int in range(12):
		var a:float = TAU * float(i) / 12.0
		draw_line(Vector2.ZERO,Vector2.from_angle(a) * _half,tint.lightened(0.2),1.1)
	for r:int in range(1,5):
		var rr:Vector2 = _half * (float(r) / 4.0)
		var pts:PackedVector2Array = []
		for i:int in range(25):
			var a:float = TAU * float(i) / 24.0
			pts.append(Vector2.from_angle(a) * rr)
		draw_polyline(pts,tint,1.0)
