extends "res://scripts/characters/我的世界/mc_mob_base.gd"

const FANG = preload("res://scripts/effects/我的世界/唤魔尖牙.gd")
const VISUAL = preload("res://Images/characters/我的世界/唤魔者/唤魔者.png")
const MC_EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const TOTEM_FX = preload("res://scripts/effects/我的世界/mc_totem_effect.gd")
const MC_EXPLOSION = preload("res://scripts/effects/我的世界/mc_explosion.gd")
const TOTEM_EFFECT_SECONDS:float = 10.0
@export var fang_interval:float = 2.2
# 恼鬼不再自然消散，只能被杀死，所以召唤间隔放慢：首次 6 秒、之后每 14 秒补员。
@export var summon_interval:float = 14.0
@export var max_vex:int = 3
var _fang_wait:float = 0.6
var _summon_wait:float = 6.0
var _vex:Array[WeakRef] = []
var _victory_cheered:bool = false
var _totem_used:bool = false
var _totem_visual_played:bool = false

func get_preview_texture() -> Texture2D: return VISUAL

func health_after_lethal_prevention(_health_before:int) -> int:
	# A totem is consumed only by an actual lethal health hit. Forced map
	# removal and a second death retain the normal death sound/pose/cleanup.
	if _totem_used or not is_multiplayer_authority() or bool(get_meta(&"__out_of_bounds_forced_death",false)):
		return 0
	_totem_used = true
	return mini(50,Max_health)

func on_lethal_health_loss_prevented() -> void:
	# Clear ALL negative Minecraft effects, including layers from other casters;
	# do not erase existing positive effects. The catalog owns their lifetimes.
	for kind:String in MC_EFFECTS.all_kinds():
		if not MC_EFFECTS.positive(kind): MC_EFFECTS.clear(self,kind)
	MC_EFFECTS.apply_effect(self,"regeneration",2,TOTEM_EFFECT_SECONDS,self)
	MC_EFFECTS.apply_effect(self,"fire_resistance",1,TOTEM_EFFECT_SECONDS,self)
	MC_EFFECTS.apply_effect(self,"absorption",2,TOTEM_EFFECT_SECONDS,self)
	if multiplayer.has_multiplayer_peer(): _show_totem_visual.rpc()
	_show_totem_visual()

@rpc("authority","call_remote","reliable")
func _show_totem_visual() -> void:
	if _totem_visual_played or not is_inside_tree(): return
	_totem_visual_played = true
	var fx:Node2D = TOTEM_FX.new()
	MC_EXPLOSION.runtime_container(self).add_child(fx)
	fx.call("setup",global_position)
	MC_AUDIO.play(self,"item.totem.use",global_position,-1.0,true,true)

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not mc_live() or dizziness: return
	var target:ball = mc_nearest(delta)
	if target == null: return
	_fang_wait -= delta
	_summon_wait -= delta
	if _fang_wait <= 0.0:
		_fang_wait = maxf(fang_interval,0.5)
		cast_fangs(target)
	if _summon_wait <= 0.0:
		_summon_wait = maxf(summon_interval,4.0)
		summon_vex()

func cast_fangs(target:ball) -> void:
	if not mc_live() or not mc_enemy(target): return
	mc_cast_animation(0.85)
	mc_play("prepare_attack",-4.0)
	var shared_hits:Dictionary = {}
	var axis:Vector2 = global_position.direction_to(target.global_position)
	if global_position.distance_to(target.global_position) < 65.0:
		for ring:int in range(3):
			var ring_hits:Dictionary = {} # 同圈只命中一次；被推向外圈可以再次被波及。
			var count:int = 12+ring*4
			for i:int in range(count):
				var point:Vector2 = global_position+Vector2.RIGHT.rotated(TAU*float(i)/float(count))*(24.0+12.0*ring)
				_spawn_fang(point,0.18+0.24*ring,ring_hits,true,[1.35,1.0,0.65][ring],[14.0,9.0,5.0][ring],[90.0,70.0,50.0][ring])
	else:
		for i:int in range(12):
			var point:Vector2 = global_position + axis * (24.0 + float(i) * 21.0)
			if not mc_line_clear(global_position,point): break
			_spawn_fang(point,0.25 + float(i) * 0.055,shared_hits)

func _spawn_fang(point:Vector2,delay:float,hits:Dictionary,push_back:bool = false,damage_ratio:float = 1.0,push_distance:float = 18.0,push_speed:float = 90.0) -> void:
	if not mc_position_clear(point,7.0) or not mc_line_clear(global_position,point): return
	if get_tree().get_nodes_in_group("MCEvokerFang").size() >= 144: return
	var fang:Node2D = FANG.new()
	get_tree().current_scene.add_child(fang)
	fang.global_transform = Transform2D(0.0,point)
	fang.setup(self,delay,attack_damage()*damage_ratio,hits,push_back,push_distance,push_speed)

func summon_vex() -> void:
	var spawned:int = 0
	for i:int in range(_vex.size()-1,-1,-1):
		var unit:Variant = _vex[i].get_ref()
		if not is_instance_valid(unit) or unit.health <= 0: _vex.remove_at(i)
	for i:int in range(mini(2,maxi(max_vex - _vex.size(),0))):
		if get_tree().get_nodes_in_group("MCVex").size() >= 32: break
		var point:Vector2 = global_position + Vector2.RIGHT.rotated(_mc_rng.randf_range(0.0,TAU)) * 28.0
		var unit:ball = mc_spawn_creature("res://scenes/creatures/唤魔恼鬼.tscn",point,0.55)
		if unit != null:
			_vex.append(weakref(unit))
			spawned += 1
	if spawned > 0:
		mc_play("prepare_summon",-4.0)
		mc_cast_animation(0.85)

func on_battle_victory() -> void:
	if _victory_cheered or health <= 0 or not is_multiplayer_authority(): return
	_victory_cheered = true
	mc_stop_ambient()
	MC_AUDIO.play(self,"entity.evoker.celebrate",global_position,-3.0,true)
func mc_ambient_allowed() -> bool: return not _victory_cheered
