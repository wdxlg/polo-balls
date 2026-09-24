extends "res://scripts/characters/我的世界/new5/base.gd"
const TEXTURES:Array[Texture2D] = [preload("res://Images/characters/我的世界/cactus_note/cactus_1.png"),preload("res://Images/characters/我的世界/cactus_note/cactus_2.png"),preload("res://Images/characters/我的世界/cactus_note/cactus_3.png"),preload("res://Images/characters/我的世界/cactus_note/cactus_4.png"),preload("res://Images/characters/我的世界/cactus_note/cactus_5.png")]
const THORN = preload("res://scenes/shooter/我的世界/仙人掌刺.tscn")
const FX = preload("res://scripts/effects/我的世界/mc_explosion.gd")
const ACTION_AUDIO = preload("res://scripts/characters/我的世界/cactus_note/block_audio.gd")
const HIT_SFX = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
const PLACE_SOUNDS:Array[AudioStream] = [preload("res://audio/characters/我的世界/仙人掌/place_0.ogg"),preload("res://audio/characters/我的世界/仙人掌/place_1.ogg"),preload("res://audio/characters/我的世界/仙人掌/place_2.ogg"),preload("res://audio/characters/我的世界/仙人掌/place_3.ogg")]
var volley_phase:int = 0 # idle, narrow, inflate, settle
var volley_age:float = 0.0
var growth_sounds:int = 0
var hit_sounds:int = 0
var _growth_players:Array[AudioStreamPlayer2D] = []
func _process(delta:float) -> void:
	super._process(delta)
	for i:int in range(_growth_players.size()-1,-1,-1):
		if not is_instance_valid(_growth_players[i]): _growth_players.remove_at(i)
		else: _growth_players[i].stream_paused = not is_combat_runtime_active()
func play_growth_sound() -> void:
	if multiplayer.has_multiplayer_peer(): _growth_sound.rpc()
	else: _growth_sound()
@rpc("authority","call_local","reliable")
func _growth_sound() -> void:
	growth_sounds += 1
	var player := AudioStreamPlayer2D.new()
	player.stream = PLACE_SOUNDS.pick_random()
	player.volume_db = 3.0
	player.pitch_scale = 0.8
	player.max_distance = 1400
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
	add_child(player)
	player.position = Vector2(0,48.0-96.0*levels)
	player.set_meta("mc_sound_event","block.wool.place")
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	_growth_players.append(player)
	player.play()
func play_contact_hit(point:Vector2) -> void:
	if multiplayer.has_multiplayer_peer(): _contact_hit_sound.rpc(point)
	else: _contact_hit_sound(point)
@rpc("authority","call_local","reliable")
func _contact_hit_sound(point:Vector2) -> void:
	hit_sounds += 1
	HIT_SFX.play(self,point)
func volley_scale() -> Vector2:
	if volley_phase == 1:
		return Vector2.ONE.lerp(Vector2(0.70,1.06),smoothstep(0.0,1.0,volley_age/0.26))
	if volley_phase == 2:
		return Vector2(0.70,1.06).lerp(Vector2(1.24,0.92),smoothstep(0.0,1.0,volley_age/0.08))
	if volley_phase == 3:
		var t:float = clampf(volley_age/0.32,0,1)
		var spring:float = exp(-6.0*t)*cos(TAU*1.4*t)*(1.0-t)
		return Vector2(1.0+0.24*spring,1.0-0.08*spring)
	return Vector2.ONE
func advance_volley(delta:float,emit:bool = true) -> void:
	var remaining:float = delta
	while volley_phase != 0 and remaining > 0:
		var duration:float = 0.26 if volley_phase == 1 else 0.08 if volley_phase == 2 else 0.32
		var consumed:float = minf(remaining,maxf(0,duration-volley_age))
		volley_age += consumed
		remaining -= consumed
		if volley_age+0.000001 < duration: break
		volley_phase = 0 if volley_phase == 3 else volley_phase+1
		volley_age = 0
		if volley_phase == 2 and emit: play_action_sound("entity.puffer_fish.sting")
		if volley_phase == 3 and emit: release_thorns()
func client_visual_step(delta:float) -> void:
	if retaliation_age>=0: advance_retaliation(delta,false)
	else: advance_volley(delta,false)
@export var growth_interval:float = 8.0
@export var volley_interval:float = 3.2
@export var contact_interval:float = 0.65
var levels:int = 1
var growth_elapsed:float = 0.0
var volley_left:float = 1.4
var contact_left:float = 0.0
var _contact_ready:Dictionary = {}
var _geometry_level:int = 0
var _health_base:Vector2
var volleys:int = 0
var last_volley_count:int = 0
var growth_count:int = 0
func get_preview_texture() -> Texture2D: return TEXTURES[0]
func _ready() -> void:
	super._ready()
	_health_base = get_node("Health_Bar").position
	image.z_as_relative = false
	image.z_index = 3
	apply_height()
func apply_height() -> void:
	levels = clampi(levels,1,5)
	if _geometry_level == levels: return
	_geometry_level = levels
	var height:float = 96.0*levels
	var shift:float = -48.0*(levels-1)
	for path:String in ["CollisionShape2D","hitbox/CollisionShape2D","hurtbox/CollisionShape2D"]:
		var node:CollisionShape2D = get_node(path)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(84,height)
		node.shape = shape
		node.position = Vector2(0,shift)
	image.texture = TEXTURES[levels-1]
	image.position = Vector2(0,shift)
	image.scale = Vector2.ONE
	get_node("Health_Bar").position = _health_base+Vector2(0,-96.0*(levels-1))
func step_mob(delta:float) -> void:
	growth_elapsed += delta
	while growth_elapsed >= growth_interval and levels < 5:
		growth_elapsed -= growth_interval
		levels += 1
		growth_count += 1
		apply_height()
		play_growth_sound()
	volley_left = maxf(0,volley_left-delta)
	contact_left = maxf(0,contact_left-delta)
	if not can_act():
		if retaliation_age>=0: advance_retaliation(delta)
		volley_phase = 0
		volley_age = 0
		return
	if retaliation_age>=0: advance_retaliation(delta)
	else: advance_volley(delta)
	if contact_left <= 0:
		contact_left = 0.06
		check_side_contact()
	if not is_player_controlled() and volley_left <= 0: fire_thorns()
func check_side_contact() -> void:
	# Only narrow left/right vertical strips. No top/bottom damage region.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12,96.0*levels-8)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for side:float in [-1.0,1.0]:
		query.transform = global_transform*Transform2D(0,Vector2(side*44,-48.0*(levels-1)))
		for contact:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,64):
			var area:Node = contact.collider
			var target:Node = area
			while is_instance_valid(target) and not target is ball: target = target.get_parent()
			if not target is ball or area != target.self_hurtbox or not U.enemy(self,target): continue
			if absf(to_local(target.global_position).x)<42.0: continue
			var id:int = target.get_instance_id()
			if clock < float(_contact_ready.get(id,-1)): continue
			if not U.line_clear(self,global_position,target.global_position): continue
			_contact_ready[id] = clock+contact_interval
			if U.damage(self,target,attack_damage(1.0),area.global_position): play_contact_hit(area.global_position)
	if _contact_ready.size()>128:
		for id:Variant in _contact_ready.keys():
			if clock >= float(_contact_ready[id]): _contact_ready.erase(id)
func fire_thorns() -> bool:
	if not can_act() or volley_left > 0 or volley_phase != 0 or retaliation_age>=0: return false
	volley_left = volley_interval
	volley_phase = 1
	volley_age = 0
	play_action_sound("entity.puffer_fish.blow_out")
	return true
func release_thorns() -> void:
	volleys += 1
	var points:Array[Vector2] = []
	var headings:Array[Vector2] = []
	# Per-side variation is just one thorn; every additional level adds two.
	for side:float in [-1.0,1.0]:
		var count:int = levels*2+rng.randi_range(0,1)
		for i:int in range(count):
			var y:float = lerpf(40.0,48.0-96.0*levels+8.0,(float(i)+0.5)/float(count))
			var stretch:Vector2 = presentation_scale()
			points.append(to_global(Vector2(side*48*stretch.x,48.0+(y-48.0)*stretch.y)))
			headings.append(Vector2(side,0).rotated(rng.randf_range(deg_to_rad(-10.0),deg_to_rad(10.0))))
	last_volley_count = points.size()
	if multiplayer.has_multiplayer_peer(): _thorn_volley.rpc(points,headings,attack_damage(0.6))
	else: _thorn_volley(points,headings,attack_damage(0.6))
@rpc("authority","call_local","reliable")
func _thorn_volley(points:Array[Vector2],headings:Array[Vector2],damage:float,fixed:bool = false) -> void:
	for i:int in range(points.size()):
		if not fixed and get_tree().get_nodes_in_group("MCCactusThorn").size()>=256: break
		var thorn:Area2D = THORN.instantiate()
		thorn.set_multiplayer_authority(get_multiplayer_authority())
		FX.runtime_container(self).add_child(thorn)
		thorn.global_position = points[i]
		thorn.fixed_retaliation_damage = fixed
		thorn.configure_plain(self,Team,headings[i],180.0,damage,0,90.0,3.0)
func Skill() -> void:
	Using_Skill = false
	fire_thorns()
func player_control_action(index:int) -> void:
	if index == 1: fire_thorns()
func visual_mob() -> void:
	apply_height()
	image.rotation = 0
	image.scale = presentation_scale()
	image.position = Vector2(0,48.0-48.0*levels*image.scale.y)
	get_node("Health_Bar").position = _health_base+Vector2(0,-96.0*(levels-1)+96.0*levels*(1.0-image.scale.y))
	face_horizontal(velocity if velocity.length_squared()>1.0 else direction,false)
func visual_state() -> Dictionary: return {"time":clock,"levels":levels,"growth":growth_elapsed,"volley":volley_left,"volley_phase":volley_phase,"volley_age":volley_age,"retaliation_age":retaliation_age,"retaliation_start":retaliation_start}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	levels = int(data.get("levels",1))
	growth_elapsed = float(data.get("growth",0))
	volley_left = float(data.get("volley",0))
	volley_phase = int(data.get("volley_phase",0))
	volley_age = float(data.get("volley_age",0))
	retaliation_age = float(data.get("retaliation_age",-1))
	retaliation_start = data.get("retaliation_start",Vector2.ONE)
	apply_height()
@rpc("authority","call_local","reliable")
func _death_visual() -> void:
	if _death_visual_done: return
	_death_visual_done = true
	ITEM_DEATH.spawn(self)
func get_skill_description() -> String:
	return "每8秒向上长一节，最多5节，底部不动，碰撞箱和血条同步升高。只有左右两侧有接触伤害；技能先收细，再弹性胀开并从左右射出本体刺色的细条，长得越高越多，数量小幅随机，主动散射为左右向外±10°。实际掉血时先快速胀粗爆刺再弹性回缩，反伤刺向外±45°、每根基础伤害固定5；总数量向下取整(实际掉血×反伤幅度÷5)，每层幅度40%、最多200%，左右合计不翻倍。每次长高播放仙人掌放置音，成功命中播放MC受击音。刺命中一次后扎在人或墙上，3秒后消失，无持续伤害或处决。"

func play_action_sound(event:String) -> void:
	if multiplayer.has_multiplayer_peer(): _action_sound.rpc(event,global_position)
	else: _action_sound(event,global_position)
@rpc("authority","call_local","reliable")
func _action_sound(event:String,point:Vector2) -> void:
	ACTION_AUDIO.play(self,event,point,-1.0 if event.ends_with("sting") else -3.0)

const RETALIATION_DAMAGE:float = 5.0
var retaliation_age:float = -1.0
var retaliation_start:Vector2 = Vector2.ONE
var retaliation_pending:int = 0
var last_retaliation_count:int = 0
var retaliation_bursts:int = 0
var retaliation_spawned:int = 0
func retaliation_ratio() -> float: return minf(2.0,0.4*levels)
func retaliation_count(amount:float) -> int:
	return int(floor(maxf(amount,0)*retaliation_ratio()/RETALIATION_DAMAGE+0.000001))
func on_actual_health_damage_received(amount:float,before:float) -> void:
	super.on_actual_health_damage_received(amount,before)
	if not is_multiplayer_authority() or not is_inside_tree() or amount<=0 or is_damage_output_disabled(): return
	var count:int = retaliation_count(minf(amount,before))
	last_retaliation_count = count
	retaliation_pending += count
	if health<=0:
		# A lethal hit still gets its damage-budgeted burst; no resurrection.
		emit_retaliation()
		return
	if retaliation_age<0 or retaliation_age>=0.055:
		retaliation_start = presentation_scale()
		retaliation_age = 0.0
func presentation_scale() -> Vector2:
	if retaliation_age<0: return volley_scale()
	if retaliation_age<0.055:
		return retaliation_start.lerp(Vector2(1.32,0.94),smoothstep(0,0.055,retaliation_age))
	var t:float = clampf((retaliation_age-0.055)/0.30,0,1)
	var spring:float = exp(-6*t)*cos(TAU*1.2*t)*(1-t)
	return Vector2(1.0+0.32*spring,1.0-0.06*spring)
func advance_retaliation(delta:float,emit:bool = true) -> void:
	if retaliation_age<0: return
	var previous:float = retaliation_age
	retaliation_age += delta
	if previous<0.055 and retaliation_age>=0.055 and emit:
		var final_age:float = retaliation_age
		retaliation_age = 0.055
		emit_retaliation()
		retaliation_age = final_age
	if retaliation_age>=0.355: retaliation_age = -1.0
func emit_retaliation() -> void:
	var count:int = retaliation_pending
	retaliation_pending = 0
	if count<=0: return
	retaliation_bursts += 1
	retaliation_spawned += count
	var points:Array[Vector2] = []
	var headings:Array[Vector2] = []
	var first_side:float = -1.0 if rng.randi_range(0,1)==0 else 1.0
	var stretch:Vector2 = presentation_scale()
	for i:int in range(count):
		var side:float = first_side if i%2==0 else -first_side
		var y:float = rng.randf_range(48.0-96.0*levels+8.0,40.0)
		points.append(to_global(Vector2(side*48.0*stretch.x,48.0+(y-48.0)*stretch.y)))
		headings.append(Vector2(side,0).rotated(rng.randf_range(-PI/4.0,PI/4.0)))
	play_action_sound("entity.puffer_fish.sting")
	if multiplayer.has_multiplayer_peer(): _thorn_volley.rpc(points,headings,RETALIATION_DAMAGE,true)
	else: _thorn_volley(points,headings,RETALIATION_DAMAGE,true)
