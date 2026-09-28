extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## Passive proximity energy -> fresh monochrome subordinate of this cycle's top contributor.
const BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
const COPY_REQUEST = preload("res://scenes/effects/我的世界/角色复制请求.tscn")
const COPY_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const CLASSIFY = preload("res://classes/combat_classification.gd")
const AUDIO = preload("res://scripts/characters/我的世界/haochen/audio.gd")
const STREAM = preload("res://scripts/effects/我的世界/character_copy_request.gd")
const SOUL = preload("res://scripts/effects/我的世界/灵魂粒子.gd")
const CHARGE_SOUL_WIDTH:float = 8.0
const CHARGE_STREAM_INTERVAL:float = 0.12
const CHARGE_STREAM_PER_SOURCE:int = 1
const AURA_INTERVAL:float = 0.15
const AURA_SOUL_WIDTH:float = 7.0
const CHARGE_STREAM_MAX_SOURCES:int = 4
# Energy-gain sound (user choice, task 8): one random native soul_escape "whoosh" per
# absorbed batch of souls, throttled; pitch varies like vanilla. Local on every peer,
# driven by the same replicated state as the drain particles (no extra RPC).
const CHARGE_SOUND_INTERVAL:float = 0.22 # checked on drain ticks (0.12 s) -> one whoosh every 0.24 s
const CHARGE_SOUND_PITCH:Vector2 = Vector2(0.85,1.15)
# User-provided Minecraft skins: exact head front + hat layer, 16x nearest (no new pixels).
const FACE_NORMAL:Texture2D = preload("res://Images/characters/我的世界/皓宸/皓宸.png")
const FACE_LAUGH:Texture2D = preload("res://Images/characters/我的世界/皓宸/皓宸笑.png")
enum Phase { RESTING, CHARGING, COPYING }
@export_category("皓宸 / 可调基础参数")
@export var energy_capacity:float = 100.0
@export var energy_radius:float = 80.0
@export var energy_per_enemy_second:float = 20.0
@export_range(0.05,1.0) var minimum_move_ratio:float = 0.3
@export var slowing_seconds:float = 2.0
@export var recovery_seconds:float = 2.0
@export var copy_duration:float = 0.65
@export var copied_stat_factor:float = 0.5
## Copies are drawn/collide at half size (user request 2026-09-28, task 9).
@export var copied_body_scale:float = 0.5
@export var scan_interval:float = 0.08
@export var charge_energy:float = 0.0:
	set(value):
		charge_energy = clampf(value,0.0,maxf(energy_capacity,0.01))
		queue_redraw()
@export var movement_ratio:float = 1.0
@export var charge_phase:int = Phase.RESTING:
	set(value):
		charge_phase = value
		_refresh_face()
		queue_redraw()
@export var leader_label:String = ""
@export var completed_copies:int = 0
var contributions:Dictionary = {} # instance ID -> gain/order/snapshot/weak source
var _contributor_serial:int = 0
var _nearby:Array[WeakRef] = []
var _scan_left:float = 0.0
var _retry_left:float = 0.0
var _copy_request:WeakRef
var _source_dead:bool = false
var _fx_rng := RandomNumberGenerator.new()
var _sound_tickets:Dictionary = {}
var _sound_serial:int = 0
var _last_remote_sound:int = 0
var _ambient_left:float = 3.0
var _step_left:float = 0.15
var _previous_audio_position:Vector2
var _audio_sample_valid:bool = false
var _drain_left:float = 0.0
var _aura_left:float = 0.0
var _charge_sound_left:float = 0.0
var _drain_rng := RandomNumberGenerator.new() # visual-only; never touches battle RNG

func _ready() -> void:
	mc_audio_role = "haochen" # User-authorized temporary portrait; no borrowed gameplay/AI.
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Hit_Audio = ""
	Collide_Audio = ""
	Collide_Audio_Node = ""
	if Dead_Audio.is_empty(): Dead_Audio = "DeadBell"
	Health_Restore = 0
	super._ready()
	add_to_group(&"character_copy_friendly_guard") # task 10: his copies never hurt his side
	_fx_rng.seed = Game.battle_rng_seed_or("haochen_visual:"+str(name),int(get_instance_id()))
	_drain_rng.seed = int(get_instance_id())
	_previous_audio_position = global_position
	_refresh_face()
	queue_redraw()

## Friendly-fire guard: nothing descended from Haochen (his copies and their
## projectiles, summons, AOE, bleeds) may ever hurt him, with or without the global
## Have_Team_Damage setting. The full-roster sweep
## (tests/test_haochen_copy_friendly_sweep.gd) showed every copy damage path lands
## in one of these entries: hitbox contact asks can_receive_hit_contact(), and all
## spatial/classified/directional/helper damage funnels into receive_positional_damage()
## (raw-health spatial damage and bleed are their own two entries).
const OWN_CHAIN_MAX_STEPS:int = 16
func is_own_summon_chain(source:Variant) -> bool:
	if not is_instance_valid(source) or not (source is Node) or source == self: return false
	var scene_root:Node = get_tree().current_scene if is_inside_tree() else null
	var my_id:int = get_instance_id()
	var current:Node = source as Node
	var seen:Dictionary = {}
	for _i:int in range(OWN_CHAIN_MAX_STEPS):
		if current == self: return true
		var id:int = current.get_instance_id()
		if seen.has(id): return false
		seen[id] = true
		# World family identity (world.bind_battle_lifecycle): partners/babies/backup squads
		# a copy spawns carry Haochen as their family root even without any Master link.
		var family:Variant = current.get_meta(&"battle_lifecycle_identity",{})
		if family is Dictionary and int((family as Dictionary).get("root",0)) == my_id: return true
		var next:Node = null
		var has_master:bool = "Master" in current
		if has_master:
			var master:Variant = current.get("Master")
			if is_instance_valid(master) and master is Node: next = master as Node
		# Many projectiles/summons only store Master_name (looked up beside them or in the world).
		if next == null and "Master_name" in current:
			var master_name:String = str(current.get("Master_name"))
			if not master_name.is_empty():
				for base:Node in [current.get_parent(),scene_root]:
					if next == null and is_instance_valid(base): next = base.get_node_or_null(NodePath(master_name))
		if next == null: next = _declared_launcher(current)
		# Hitbox/Area children of a projectile or effect: climb to their holder.
		if next == null and not has_master and not ("Master_name" in current): next = current.get_parent()
		if next == null or next == scene_root: return false
		current = next
	return false

## Launcher links used by projectiles that deliberately keep Master empty: Area bolts
## (_src_ref), neutral MC ghast fireballs (launch_owner_id; a reflected fireball
## belongs to whoever reflected it, so it is NOT attributed back) and bat cohorts.
func _declared_launcher(node:Node) -> Node:
	var ref:Variant = node.get("_src_ref")
	if ref is WeakRef:
		var shooter:Variant = (ref as WeakRef).get_ref()
		if is_instance_valid(shooter) and shooter is Node: return shooter as Node
	var launcher_id:Variant = node.get("launch_owner_id")
	if launcher_id is int and int(launcher_id) != 0 and not bool(node.get("reflected")):
		var launcher:Object = instance_from_id(int(launcher_id))
		if is_instance_valid(launcher) and launcher is Node: return launcher as Node
	var cohort:int = int(node.get_meta(&"mc_bat_cohort",0))
	if cohort != 0 and cohort != node.get_instance_id():
		var leader:Object = instance_from_id(cohort)
		if is_instance_valid(leader) and leader is Node: return leader as Node
	return null

func can_receive_hit_contact(hit:Node,_hurt:Node) -> bool:
	return not is_own_summon_chain(hit)

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if is_own_summon_chain(source): return false
	return super(damage,impact_position,ignore_block,source)

func _receive_spatial_damage_untyped(damage:float,damage_space:Variant,ignore_block:bool,raw_health:bool) -> bool:
	if damage_space is Dictionary and is_own_summon_chain((damage_space as Dictionary).get("source",null)): return false
	return super(damage,damage_space,ignore_block,raw_health)

func receive_internal_status_damage(damage:float,kind:StringName,source:Node = null) -> float:
	if is_own_summon_chain(source): return 0.0
	return super(damage,kind,source)

## Laughs for the whole time the meter is being built or cashed in. Driven by the
## replicated charge_phase, so every peer shows the same face without extra RPCs.
func is_laughing() -> bool:
	return not _source_dead and health>0 and charge_phase in [Phase.CHARGING,Phase.COPYING]

func _refresh_face() -> void:
	if not is_node_ready() or not is_instance_valid(image) or not image is Sprite2D: return
	var face:Texture2D = FACE_LAUGH if is_laughing() else FACE_NORMAL
	if (image as Sprite2D).texture != face: (image as Sprite2D).texture = face

func _process(delta:float) -> void:
	queue_redraw()
	_step_charge_stream(delta)

## Visual only, on every peer from replicated positions/phase: native soul
## particles flow from each enemy feeding the meter into Haochen, and souls
## hover up around Haochen for as long as he is charging.
func _step_charge_stream(delta:float) -> void:
	if charge_phase!=Phase.CHARGING or _source_dead or health<=0 or not is_combat_runtime_active(): return
	_aura_left -= delta
	if _aura_left<=0.0:
		_aura_left = AURA_INTERVAL
		_emit_aura_soul()
	_charge_sound_left -= delta
	_drain_left -= delta
	if _drain_left>0.0: return
	_drain_left = CHARGE_STREAM_INTERVAL
	var fed:int = 0
	for raw:Variant in COPY_TOOLS.targeting_candidates(self):
		if fed>=CHARGE_STREAM_MAX_SOURCES: break
		if not _valid_energy_source(raw) or global_position.distance_squared_to(raw.global_position)>energy_radius*energy_radius: continue
		fed += 1
		STREAM.emit_stream(get_parent(),_drain_rng,raw.global_position,global_position,CHARGE_STREAM_PER_SOURCE,CHARGE_SOUL_WIDTH,&"MCHaochenChargeParticle",&"haochen_stream_owner",get_instance_id(),0.3,self)
	if fed>0 and _charge_sound_left<=0.0:
		_charge_sound_left = CHARGE_SOUND_INTERVAL
		AUDIO.play(self,&"charge_soul",global_position,_drain_rng.randi_range(0,AUDIO.EVENTS[&"charge_soul"].size()-1),_drain_rng.randf_range(CHARGE_SOUND_PITCH.x,CHARGE_SOUND_PITCH.y))

func _emit_aura_soul() -> void:
	var parent:Node = get_parent()
	if parent==null or not parent.is_inside_tree() or SOUL.room(get_tree())<=0: return
	var box:Vector2 = collision_shape_2d.shape.get_rect().size*collision_shape_2d.global_scale.abs() if collision_shape_2d!=null and collision_shape_2d.shape!=null else Vector2(18,17)
	var point:Vector2 = global_position+Vector2(_drain_rng.randf_range(-0.6,0.6)*box.x,_drain_rng.randf_range(-0.2,0.5)*box.y)
	var soul:Node2D = SOUL.new()
	parent.add_child(soul)
	soul.setup(point,Vector2(_drain_rng.randf_range(-3.0,3.0),-4.0),0.9,AURA_SOUL_WIDTH,10.0)
	soul.add_to_group("MCHaochenAuraParticle")
	soul.set_meta("haochen_stream_owner",get_instance_id())

func _draw() -> void:
	if _source_dead or health<=0: return
	var rect:Rect2 = BAR.below_body(self,collision_shape_2d,110.0,16.0,9.0)
	var ratio:float = charge_energy/maxf(energy_capacity,0.01)
	var color:Color = Color(0.76,0.62,1.0) if charge_phase!=Phase.COPYING else Color(0.94,0.94,1.0)
	BAR.paint(self,rect,ratio,ratio,color)

func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health>0 and not _source_dead and is_combat_runtime_active():
		_step_energy(delta)
		_step_creature_audio(delta)
	super.tick_physics(state,delta)

func move(speed:float,delta:float) -> void:
	# Scale voluntary locomotion only, never external knockback/pull/surface channels.
	super.move(speed*clampf(movement_ratio,minimum_move_ratio,1.0),delta)

func _valid_energy_source(raw:Variant) -> bool:
	if not is_instance_valid(raw) or not raw is ball: return false
	var unit:ball = raw as ball
	if not unit.is_inside_tree() or unit.is_queued_for_deletion() or unit.get_multiplayer()!=multiplayer or unit.get_world_2d()!=get_world_2d(): return false
	if not COPY_TOOLS.is_enemy(self,unit): return false
	var kind:String = str(CLASSIFY.profile_of(unit).get("entity_kind",""))
	if kind not in ["character","subentity"]: return false
	return not str(unit.scene_file_path).is_empty() and ResourceLoader.exists(str(unit.scene_file_path))

func _scan_enemies() -> void:
	_nearby.clear()
	for raw:Variant in COPY_TOOLS.targeting_candidates(self):
		if _valid_energy_source(raw) and global_position.distance_squared_to(raw.global_position)<=energy_radius*energy_radius:
			_nearby.append(weakref(raw))

func _step_energy(delta:float) -> void:
	if not is_multiplayer_authority() or health<=0 or _source_dead or not is_combat_runtime_active() or delta<=0.0: return
	_retry_left = maxf(_retry_left-delta,0.0)
	_scan_left -= delta
	if _scan_left<=0.0:
		_scan_left = maxf(scan_interval,0.01)
		_scan_enemies()
	var donors:Array[ball] = []
	if charge_phase!=Phase.COPYING and not dizziness and not is_damage_output_disabled() and _retry_left<=0.0:
		for reference:WeakRef in _nearby:
			var raw:Variant = reference.get_ref()
			if _valid_energy_source(raw) and global_position.distance_squared_to(raw.global_position)<=energy_radius*energy_radius:
				donors.append(raw as ball)
	var charging:bool = not donors.is_empty() and charge_phase!=Phase.COPYING
	if charge_phase!=Phase.COPYING:
		if charging and charge_phase!=Phase.CHARGING: _emit_audio(&"charge_start")
		charge_phase = Phase.CHARGING if charging else Phase.RESTING
	var target_ratio:float = minimum_move_ratio if charging else 1.0
	var seconds:float = slowing_seconds if charging else recovery_seconds
	movement_ratio = move_toward(movement_ratio,target_ratio,(1.0-minimum_move_ratio)*delta/maxf(seconds,0.01))
	if not charging: return
	var total:float = minf(maxf(energy_capacity-charge_energy,0.0),energy_per_enemy_second*delta*donors.size())
	if total>0.0:
		var each:float = total/float(donors.size()) # Cap overflow fairly; loop order cannot steal the last energy.
		for donor:ball in donors: _record_contribution(donor,each)
		charge_energy += total
	_update_leader()
	if charge_energy>=energy_capacity-0.00001: _begin_copy()

func _record_contribution(donor:ball,amount:float) -> void:
	if amount<=0.0 or not is_instance_valid(donor): return
	var snapshot:Dictionary = COPY_TOOLS.capture_character_template(donor)
	if snapshot.is_empty(): return
	var key:int = donor.get_instance_id()
	if not contributions.has(key):
		_contributor_serial += 1
		contributions[key] = {"energy":0.0,"order":_contributor_serial,"snapshot":snapshot,"source":weakref(donor)}
	var row:Dictionary = contributions[key]
	row.energy = float(row.energy)+amount
	row.snapshot = snapshot
	contributions[key] = row

func _winner() -> Dictionary:
	var best:Dictionary = {}
	for key:Variant in contributions:
		var row:Dictionary = contributions[key]
		if best.is_empty() or float(row.energy)>float(best.energy)+0.00001 or (is_equal_approx(float(row.energy),float(best.energy)) and int(row.order)<int(best.order)): best = row
	return best

func _update_leader() -> void:
	var row:Dictionary = _winner()
	leader_label = str(row.get("snapshot",{}).get("label","")) if not row.is_empty() else ""

func _begin_copy() -> void:
	if charge_phase==Phase.COPYING or not mc_live() or dizziness: return
	var winner:Dictionary = _winner()
	if winner.is_empty(): return
	var request:Node2D = COPY_REQUEST.instantiate()
	request.template_snapshot = (winner.snapshot as Dictionary).duplicate(true)
	request.owner_name = str(name)
	request.owner_team = Team
	request.neutral_owner = str(character_copy_profile.get("neutral_owner",str(name)))
	request.stat_factor = copied_stat_factor
	request.body_scale = copied_body_scale
	request.cast_duration = maxf(copy_duration,0.05)
	request.remaining = request.cast_duration
	request.visual_seed = _fx_rng.randi()
	request.owner_ref = weakref(self)
	# The copied character is linked to Haochen by a native particle stream.
	var source:ball = (winner.get("source") as WeakRef).get_ref() as ball if winner.get("source") is WeakRef else null
	request.source_ref = weakref(source) if is_instance_valid(source) else null
	request.link_visible = is_instance_valid(source)
	request.source_name = str(source.name) if is_instance_valid(source) else ""
	request.link_from = source.global_position if is_instance_valid(source) else global_position
	request.link_to = global_position
	request.set_multiplayer_authority(get_multiplayer_authority())
	var point:Vector2 = COPY_TOOLS.safe_spawn_position(self,global_position+Vector2.RIGHT.rotated(_fx_rng.randf_range(0.0,TAU))*28.0,24.0)
	request.position = (get_parent() as Node2D).to_local(point) if get_parent() is Node2D else point
	var world:Node = get_tree().current_scene
	if world.has_method("begin_battle_spawn"):
		request.lifecycle_ticket = world.begin_battle_spawn(self,request)
		if request.lifecycle_ticket<=0:
			request.free()
			_retry_left = 0.5
			return
	_copy_request = weakref(request)
	charge_phase = Phase.COPYING
	request.copy_finished.connect(_on_copy_finished.bind(request),CONNECT_ONE_SHOT)
	get_parent().add_child(request,true)
	# Original Evoker summon wind-up marks the confirmed cast once; the request
	# still owns the copy-appear clip (illusioner mirror_move) and the pixel assembly.
	_emit_audio(&"copy_start")

func _on_copy_finished(success:bool,_copy:Node,request:Node) -> void:
	var active:Variant = _copy_request.get_ref() if _copy_request != null else null
	if active!=request: return
	_copy_request = null
	if _source_dead or health<=0: return
	if success:
		completed_copies += 1
		charge_energy = 0.0
		contributions.clear()
		_contributor_serial = 0
		leader_label = ""
	else:
		_retry_left = 0.5 # Failed requests do not consume a completed meter.
	charge_phase = Phase.RESTING

func get_debug_detection_regions() -> Array:
	if health<=0 or _source_dead or charge_phase==Phase.COPYING: return []
	return [{"shape":"circle","position":global_position,"radius":energy_radius,"kind":"haochen_energy_detection"}]
func get_ai_attack_threats(_receiver:ball) -> Array: return []
func player_control_action_ids() -> Array[StringName]: return [] # Automatic charging/copy is a passive, not an invented active button.
func mc_ambient_event() -> String: return "" # The queued, duration-aware voice channel below owns idle audio.

func _step_creature_audio(delta:float) -> void:
	var traveled:Vector2 = global_position-_previous_audio_position
	_previous_audio_position = global_position
	var moving:bool = _audio_sample_valid and traveled.length()>0.02 and traveled.length()<maxf(36.0,_last_requested_velocity.length()*delta*5.0)
	_audio_sample_valid = true
	_step_left -= delta
	if moving and not dizziness and _step_left<=0.0 and not AUDIO.busy(_sound_tickets.get(&"step",{})):
		_emit_audio(&"step")
		_step_left = 0.30
	if charge_phase!=Phase.RESTING: return
	_ambient_left -= delta
	if _ambient_left<=0.0 and not AUDIO.busy(_sound_tickets.get(&"ambient",{})):
		_emit_audio(&"ambient")
		_ambient_left = _mc_voice_rng.randf_range(3.0,7.0)

func _emit_audio(event:StringName) -> void:
	if not is_multiplayer_authority(): return
	if event in [&"step",&"ambient",&"charge_start"] and AUDIO.busy(_sound_tickets.get(event,{})): return
	var index:int = AUDIO.variant(event)
	if index<0: return
	_sound_serial += 1
	_play_audio(event,index,global_position,_sound_serial)
	if multiplayer.has_multiplayer_peer(): _play_audio.rpc(event,index,global_position,_sound_serial)

@rpc("authority","call_remote","reliable")
func _play_audio(event:StringName,index:int,point:Vector2,serial:int) -> void:
	if serial<=_last_remote_sound: return
	_last_remote_sound = serial
	var ticket:Dictionary = AUDIO.play(self,event,point,index)
	if not ticket.is_empty(): _sound_tickets[event] = ticket

func mc_play(event:String,_volume:float = -4.0) -> AudioStreamPlayer2D:
	_emit_audio(StringName(event))
	return null

func Die() -> void:
	if _source_dead: return
	_source_dead = true
	for event:StringName in [&"step",&"ambient",&"charge_start"]: AUDIO.cancel(_sound_tickets.get(event,{}))
	# A confirmed COPY_REQUEST owns its own lifecycle ticket and may finish;
	# unconfirmed energy alone cannot keep a dead character alive.
	super.Die()
	_refresh_face()
	if not Dead_Audio.is_empty(): Audios.play_sfx(Dead_Audio,{},true)
	queue_redraw()

func get_armor_test_effect_summary() -> String:
	if Game.current_locale.begins_with("en"):
		return "Nearby enemies supply energy while Haochen gradually slows. With none nearby, movement recovers and stored energy is retained.\nA full meter copies this cycle's greatest contributor as a monochrome subordinate. Combat stats are halved except movement speed; skill parameters remain.\nEach successful copy starts a new contribution cycle. Existing copies remain and share Haochen's battle family."
	return "附近敌人持续提供能量，蓄能时逐渐减速；无人时恢复移速，已经积累的能量与贡献保留。\n满条复制本轮贡献最高的人物，成为黑白附属；除移速外公共战斗属性减半，技能参数保持。\n复制成功后重新计分，旧复制品继续留场，并与皓宸共用原角色的存续归属。"
