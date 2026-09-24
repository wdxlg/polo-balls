extends Node2D

# 蛛网弹：直线快弹，命中一次后施加蛛网减速并消散；撞墙消散。
const AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")

var _caster:WeakRef
var _origin:Vector2
var _direction:Vector2 = Vector2.RIGHT
var _speed:float = 520.0
var _range:float = 230.0
var _damage:float = 10.0
var _slow_multiplier:float = 0.62
var _slow_duration:float = 2.0
var _slow_buff:String = "蜘蛛_蛛网"
var _distance:float = 0.0
var _hit:bool = false

func setup(caster:ball,origin:Vector2,direction:Vector2,speed:float,range:float,damage:float,slow_multiplier:float = 0.62,slow_duration:float = 2.0,slow_buff:String = "蜘蛛_蛛网") -> void:
	add_to_group("AllayExtendedProjectile")
	_caster = weakref(caster)
	_origin = origin
	_direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_speed = maxf(speed,1.0)
	_range = maxf(range,1.0)
	_damage = maxf(damage,0.0)
	_slow_multiplier = clampf(slow_multiplier,0.05,1.0)
	_slow_duration = maxf(slow_duration,0.1)
	_slow_buff = slow_buff
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2
	add_to_group("BattleTransient")
	add_to_group("MCWebPellet")

func _physics_process(delta:float) -> void:
	var caster:Variant = _caster.get_ref() if _caster != null else null
	if not is_instance_valid(caster) or caster.health <= 0:
		queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	var prev:Vector2 = global_position
	var step:float = _speed * delta
	_distance += step
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,global_position,global_position+_direction*step): return
	global_position += _direction * step
	if not caster.mc_line_clear(prev,global_position):
		_die()
		return
	if _distance >= _range:
		_die()
		return
	if not _hit:
		_try_hit(caster)
	queue_redraw()

func _try_hit(caster:ball) -> void:
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not target is ball or not caster.mc_enemy(target): continue
		var candidate:ball = target
		if global_position.distance_to(candidate.global_position) > 14.0 + candidate.get_crowd_separation_radius_world() * 0.5: continue
		if candidate.has_method("try_full_projectile_dodge") and bool(candidate.call("try_full_projectile_dodge",self)): continue
		_hit = true
		var bonus:float = 1.0
		if caster.has_method("webbed_multiplier"):
			bonus = caster.call("webbed_multiplier",candidate)
		if caster.mc_damage_with_impact(candidate,_damage * bonus,global_position):
			_apply_slow(caster,candidate)
		AUDIO.play(caster,"entity.spider_web.hit",global_position,-3.0)
		_die()
		return

func _apply_slow(caster:ball,target:ball) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0: return
	var tree:SceneTree = target.get_tree()
	if tree == null: return
	var world:Node = tree.current_scene
	if world == null or not world.has_method("new_buff"): return
	world.call("new_buff",target,caster,_slow_buff,Buff.new(2,_slow_duration,Buff.Buff_types.Speed,_slow_multiplier,Buff.Algorithms.mul),"cover")

func _die() -> void:
	if is_queued_for_deletion(): return
	remove_from_group("MCWebPellet")
	queue_free()

func _draw() -> void:
	# 白色蛛丝弹：圆核 + 四根短丝，朝向飞行方向。
	var c:Color = Color(0.93,0.95,0.97,0.95)
	draw_circle(Vector2.ZERO,4.5,c)
	for i:int in range(4):
		var a:float = TAU * float(i) / 4.0 + PI * 0.25
		var p1:Vector2 = Vector2.from_angle(a) * 4.0
		var p2:Vector2 = Vector2.from_angle(a) * 9.5
		draw_line(p1,p2,Color(0.93,0.95,0.97,0.55),1.4)
	draw_line(Vector2.LEFT * 12.0,Vector2.LEFT * 5.0,Color(0.93,0.95,0.97,0.3),1.2)
