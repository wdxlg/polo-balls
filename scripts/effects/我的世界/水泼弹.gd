extends Node2D

# 水泼弹：短程直飞水滴，命中一次施加“浸湿”（减速 + 后续三叉戟加成）；撞墙溅散。
const AUDIO = preload("res://scripts/effects/我的世界/mc_native_audio.gd")

const SPEED:float = 300.0
const RANGE:float = 420.0

var _caster:WeakRef
var _direction:Vector2 = Vector2.RIGHT
var _damage:float = 5.0
var _slow_multiplier:float = 0.78
var _slow_duration:float = 2.8
var _slow_buff:String = "溺尸_浸湿"
var _distance:float = 0.0
var _hit:bool = false
var _age:float = 0.0

func setup(caster:ball,_origin:Vector2,damage:float,slow_multiplier:float,slow_duration:float,slow_buff:String) -> void:
	add_to_group("AllayExtendedProjectile")
	_caster = weakref(caster)
	_direction = Vector2.RIGHT.rotated(rotation).normalized()
	_damage = maxf(damage,0.0)
	_slow_multiplier = clampf(slow_multiplier,0.05,1.0)
	_slow_duration = maxf(slow_duration,0.1)
	_slow_buff = slow_buff
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2
	add_to_group("BattleTransient")
	add_to_group("MCWaterBlob")

func _physics_process(delta:float) -> void:
	var caster:Variant = _caster.get_ref() if _caster != null else null
	if not is_instance_valid(caster) or caster.health <= 0:
		queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	_age += delta
	var prev:Vector2 = global_position
	var step:float = SPEED * delta
	_distance += step
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,global_position,global_position+_direction*step): return
	global_position += _direction * step
	queue_redraw()
	if not caster.mc_line_clear(prev,global_position):
		_die()
		return
	if _distance >= RANGE:
		_die()
		return
	if not _hit:
		for target:Node in get_tree().get_nodes_in_group("Ball"):
			if not target is ball or not caster.mc_enemy(target): continue
			var candidate:ball = target
			if global_position.distance_to(ball.body_point(candidate,global_position)) > 15.0 + candidate.get_crowd_separation_radius_world() * 0.5: continue
			if candidate.has_method("try_full_projectile_dodge") and bool(candidate.call("try_full_projectile_dodge",self)): continue
			_hit = true
			if caster.mc_damage_with_impact(candidate,_damage,global_position):
				_apply_wet(caster,candidate)
			AUDIO.play(caster,"entity.drowned.splash",global_position,-3.0)
			_die()
			return

func _apply_wet(caster:ball,target:ball) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0: return
	var tree:SceneTree = target.get_tree()
	if tree == null: return
	var world:Node = tree.current_scene
	if world == null or not world.has_method("new_buff"): return
	world.call("new_buff",target,caster,_slow_buff,Buff.new(2,_slow_duration,Buff.Buff_types.Speed,_slow_multiplier,Buff.Algorithms.mul),"cover")

func _die() -> void:
	if is_queued_for_deletion(): return
	remove_from_group("MCWaterBlob")
	queue_free()

func _draw() -> void:
	var c:Color = Color(0.35,0.62,0.95,0.9)
	draw_circle(Vector2.ZERO,5.0,c)
	draw_circle(Vector2.LEFT * 4.0,3.4,c.darkened(0.15))
	draw_circle(Vector2(-1.5,-2.0),1.6,Color(0.8,0.9,1.0,0.7))
