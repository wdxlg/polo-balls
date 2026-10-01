extends RefCounted
## Migration policy only; damage remains entirely in ball's existing receive paths.
## 1: settle feedback at the victim; 0: retain an already-correct/manual or explicit
## replacement implementation. Most-derived script wins (notably spear-mace).
const GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const QUEUE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
const OWNERS = preload("res://classes/projectile_interactions.gd")
const POLICIES:Dictionary = {
	"res://scripts/characters/默认/丁某人睡觉.gd": 1,
	"res://scripts/characters/默认/ding_sleep/z.gd": 1,
	"res://scripts/characters/我的世界/cactus_note/cactus.gd": 1,
	"res://scripts/characters/我的世界/wither/wither.gd": 0,
	"res://scripts/characters/我的世界/wither_skeleton/wither_skeleton.gd": 0,
	"res://scripts/characters/我的世界/new5/slime.gd": 1,
	"res://scripts/characters/我的世界/唤魔者.gd": 0,
	"res://scripts/characters/我的世界/clock/clock.gd": 1,
	"res://scripts/characters/我的世界/cactus_note/note_block.gd": 0,
	"res://scripts/characters/我的世界/new6/heavenfall_longbow.gd": 1,
	"res://scripts/characters/我的世界/女巫.gd": 1,
	"res://scripts/characters/我的世界/new5/guardian.gd": 1,
	"res://scripts/characters/我的世界/new6/bow.gd": 1,
	"res://scripts/characters/我的世界/new5/ghast.gd": 1,
	"res://scripts/characters/我的世界/allay/allay.gd": 1,
	"res://scripts/characters/我的世界/frontier/wooden_sword.gd": 0,
	"res://scripts/characters/我的世界/木矛.gd": 1,
	"res://scripts/characters/我的世界/new6/oak_boat.gd": 1,
	"res://scripts/characters/我的世界/末影人.gd": 1,
	"res://scripts/characters/我的世界/溺尸.gd": 0,
	"res://scripts/characters/我的世界/潜影贝.gd": 1,
	"res://scripts/characters/我的世界/烈焰人.gd": 1,
	"res://scripts/characters/我的世界/frontier/warden.gd": 0,
	"res://scripts/characters/我的世界/石矛.gd": 0,
	"res://scripts/characters/我的世界/minecart/minecart.gd": 0,
	"res://scripts/characters/我的世界/硫方怪.gd": 0,
	"res://scripts/characters/我的世界/new5/piston.gd": 1,
	"res://scripts/characters/我的世界/new6/sheep.gd": 1,
	"res://scripts/characters/我的世界/frontier/moss.gd": 0,
	"res://scripts/characters/我的世界/苦力怕.gd": 1,
	"res://scripts/characters/我的世界/蜘蛛.gd": 0,
	"res://scripts/characters/我的世界/bat/bat.gd": 1,
	"res://scripts/characters/我的世界/蠹虫.gd": 1,
	"res://scripts/characters/我的世界/重锤.gd": 1,
	"res://scripts/characters/我的世界/new5/fishing_rod.gd": 1,
	"res://scripts/characters/我的世界/钻石剑.gd": 1,
	"res://scripts/characters/我的世界/钻石长矛.gd": 0,
	"res://scripts/characters/我的世界/铁傀儡.gd": 0,
	"res://scripts/characters/我的世界/铁匠村民.gd": 1,
	"res://scripts/characters/我的世界/铁砧.gd": 0,
	"res://scripts/characters/我的世界/铜剑.gd": 0,
	"res://scripts/characters/我的世界/snow_golem/snow_golem.gd": 0,
	"res://scripts/characters/我的世界/fog_man/actor.gd": 1,
	"res://scripts/characters/我的世界/鞘翅重锤.gd": 1,
	"res://scripts/characters/我的世界/鞘翅重锤长矛.gd": 0,
	"res://scripts/characters/我的世界/鞘翅长矛.gd": 1,
	"res://scripts/characters/我的世界/骷髅.gd": 1,
	"res://scripts/characters/我的世界/new5/fireball.gd": 1,
	"res://scripts/creatures/mc_short_lived_mob.gd": 1,
}
static var _script_policy:Dictionary = {}
static var _rng := RandomNumberGenerator.new()
static var _seeded:bool = false

static func script_policy(script:Script) -> int:
	if script == null: return -1
	var key:int = script.get_instance_id()
	if _script_policy.has(key): return int(_script_policy[key])
	var current:Script = script
	var result:int = -1
	while current != null:
		if POLICIES.has(current.resource_path):
			result = int(POLICIES[current.resource_path])
			break
		current = current.get_base_script()
	_script_policy[key] = result
	return result

static func manages(source:Node) -> bool:
	var seen:Dictionary = {}
	while is_instance_valid(source):
		var id:int = source.get_instance_id()
		if seen.has(id): return false
		seen[id] = true
		var policy:int = script_policy(source.get_script())
		if policy >= 0: return policy == 1
		source = OWNERS.source_of(source)
	return false

static func actual_loss(target:Node,before:float) -> float:
	return maxf(maxf(before,0.0)-(maxf(float(target.health),0.0) if is_instance_valid(target) else 0.0),0.0)

static func settled(source:Node,target:Node,before:float,point:Vector2) -> void:
	if manages(source): emit(target,actual_loss(target,before),point)

static func finish(source:Node,target:Node,before:float,point:Vector2) -> void:
	# Explicit status adapter: auto sources were already reported by the receive path.
	if not manages(source): emit(target,actual_loss(target,before),point)

static func emit(target:Node,actual:float,point:Vector2) -> void:
	if not is_instance_valid(target) or not target.has_method("request_mc_damage_audio"): return
	if not is_finite(actual) or actual<=0.0: return
	target.request_mc_damage_audio(actual,point)

static func variant(event:String) -> int:
	if not _seeded:
		_rng.randomize()
		_seeded = true
	return _rng.randi_range(0,AUDIO.EVENTS[event].size()-1)

static func play(target:Node2D,actual:float,point:Vector2,index:int,serial:int) -> Dictionary:
	if not is_instance_valid(target) or not is_finite(actual) or actual<=0.0: return {}
	var event:String = GAIN.damage_event(actual)
	var records:Array = AUDIO.EVENTS[event]
	if index<0 or index>=records.size(): return {}
	var parent:Node = target.get_tree().current_scene
	if parent is Node2D and target.get_world_2d()!=parent.get_world_2d():
		parent = target
		while parent.get_parent() is Node2D and parent.get_parent().get_world_2d()==target.get_world_2d(): parent = parent.get_parent()
	return QUEUE.queue_stream(target,records[index].stream,point,{
		"audio_parent":parent,"volume_db":GAIN.damage_gain(actual),"pitch":1.0,
		"priority":true,"keep_after_source":true,
		"metadata":{"mc_sound_event":event,"mc_actual_damage":actual,"mc_damage_serial":serial,"mc_damage_target":target.get_instance_id(),"mc_unified_hit":true}})
