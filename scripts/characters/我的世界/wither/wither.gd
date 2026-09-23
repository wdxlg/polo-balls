extends "res://scripts/characters/我的世界/mc_mob_base.gd"
## 召唤 -> 骷髅/玫瑰/冲撞 -> 半血下界之心。所有伤害由权威端结算。
const BODY = preload("res://Images/characters/我的世界/wither/wither_front.png")
const LIVE_RIG = preload("res://scripts/characters/我的世界/wither/bedrock_rig.gd")
const SOUL_SAND = preload("res://Images/characters/我的世界/wither/soul_sand.png")
const HEAD = preload("res://Images/characters/我的世界/wither/wither_skull.png")
const MC_EXPLOSION_SCENE:PackedScene = preload("res://scenes/effects/我的世界/MC爆炸.tscn")
const MC_EXPLOSION = preload("res://scripts/effects/我的世界/mc_explosion.gd")
const SUMMON_BLOCK_SIZE:float = 30.0
const SUMMON_HEAD_SIZE:float = 26.0
const VANILLA_SOUND = preload("res://scripts/characters/我的世界/wither/audio.gd")
const SKULL = preload("res://scripts/characters/我的世界/wither/skull.gd")
const ROSE = preload("res://scripts/characters/我的世界/wither/rose.gd")
const BEACON = preload("res://scenes/creatures/我的世界/凋零信标.tscn")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
@export var summon_duration:float = 3.0
@export var skull_interval:float = 5.0
@export var rose_interval:float = 10.0
@export var charge_interval:float = 12.0
var summon_time:float = 0.0
var summoned:bool = false
var heart_dropped:bool = false
var beacon:ball
var _shot_left:float = 5.0
var _rose_left:float = 10.0
var _charge_left:float = 12.0
var _windup:float = 0.0
var _charge_windup:float = 0.0
var _charge_dir:Vector2 = Vector2.RIGHT
var _charge_remaining:float = 0.0
var _charge_hits:Dictionary = {}
var _sync_left:float = 0.0
var _buff:String = ""
var _buff_left:float = 0.0
var _regen_clock:float = 0.0
var _summon_sound_played:bool = false
var _idle_left:float = 8.0
var _effects:Array[WeakRef] = []
var reflected_count:int = 0
var _bedrock_viewport:SubViewport
var _bedrock_model:Node3D
var _animation_life:float = 0.0

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	mc_audio_role = ""
	super._ready()
	_create_live_model()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if image is Sprite2D: (image as Sprite2D).visible = false
	queue_redraw()

func _create_live_model() -> void:
	if not image is Sprite2D: return
	_bedrock_viewport = SubViewport.new()
	_bedrock_viewport.name = "MojangBedrockWitherLive3D"
	_bedrock_viewport.size = Vector2i(192,192)
	_bedrock_viewport.transparent_bg = true
	_bedrock_viewport.own_world_3d = true
	_bedrock_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_bedrock_viewport)
	var camera:=Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.3
	camera.position = Vector3(0,1.68,-6)
	_bedrock_viewport.add_child(camera)
	camera.look_at(Vector3(0,1.68,0),Vector3.UP)
	camera.current = true
	_bedrock_model = LIVE_RIG.new() as Node3D
	_bedrock_viewport.add_child(_bedrock_model)
	var sprite:Sprite2D = image as Sprite2D
	sprite.texture = _bedrock_viewport.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE*0.85
func get_preview_texture() -> Texture2D:
	if _bedrock_viewport != null: return _bedrock_viewport.get_texture()
	return BODY
func _get_hit_effect_visual_texture() -> Texture2D:
	# CPU-only shadow sampling cannot read a live GPU ViewportTexture in headless
	# mode. Keep the original-source 2D silhouette solely for this sampler.
	return BODY
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:int = State.Die if health <= 0 else (State.Move if summoned and is_combat_runtime_active() and not dizziness else State.Stand)
	return -1 if state == next else next
func Attack() -> void: Attacking = false
func Skill() -> void: Using_Skill = false
func take_damage(amount:float,ignore_block:bool = false) -> void:
	if not summoned and health > 0: return
	if _buff == "resistance" and _buff_left > 0: amount *= 0.90
	super.take_damage(amount,ignore_block)
func can_receive_hit_from(incoming_hit) -> bool:
	if summoned or not is_multiplayer_authority() or incoming_hit == null: return true
	var projectile:Node = incoming_hit.get_parent()
	if not (projectile is ball) and incoming_hit.owner is ball: projectile = incoming_hit.owner
	if projectile is ball:
		var shot:ball = projectile as ball
		if shot.Type in [Ball_Type.Shooter,Ball_Type.Shooter_with_Health]:
			if not shot.has_meta(&"wither_reflected"):
				shot.set_meta(&"wither_reflected",true)
				call_deferred("_reflect_shot",shot)
			return false
	return false # 构筑期近战/其他投射物仍不能造成伤害。
func should_destroy_projectile_on_rejected_hit(incoming_hit:hitbox) -> bool:
	if not summoned and incoming_hit != null and incoming_hit.get_parent() is ball:
		var shot:ball = incoming_hit.get_parent()
		if shot.Type in [Ball_Type.Shooter,Ball_Type.Shooter_with_Health]: return false
	return true
func _reflect_shot(shot:ball) -> void:
	if not is_instance_valid(shot) or not is_multiplayer_authority(): return
	var previous:ball = shot.Master if shot.Master is ball else null
	var heading:Vector2 = -shot.direction
	if heading.length_squared() < 0.001: heading = (shot.global_position-global_position).normalized()
	if heading.length_squared() < 0.001: heading = Vector2.RIGHT
	shot.Master = self
	shot.Master_name = name
	shot.Team = Team
	shot.Ignore_Team_Damage_Setting = Ignore_Team_Damage_Setting
	shot.Target_Enemy = previous if is_instance_valid(previous) else null
	shot.direction = heading.normalized()
	shot.global_position = global_position + shot.direction*76.0
	shot.velocity = Vector2.ZERO
	shot.Repel = Vector2.ZERO
	shot.global_rotation = shot.Default_Rotation + shot.direction.angle()
	reflected_count += 1

func on_actual_health_damage_received(actual:float,before:float) -> void:
	super.on_actual_health_damage_received(actual,before)
	if actual > 0 and summoned and health > 0:
		_emit_sound("hurt%d" % _mc_rng.randi_range(1,4),global_position)
	if actual > 0 and summoned and not heart_dropped and health > 0 and health <= Max_health*0.5 and is_multiplayer_authority():
		heart_dropped = true
		var child:ball = BEACON.instantiate() as ball
		child.Master = self
		child.Team = Team
		child.Master_name = str(get_path())
		child.name = "下界之心_%d" % get_instance_id()
		get_tree().current_scene.add_child(child,true)
		child.global_position = global_position
		child.add_to_group("BattleTransient")
		beacon = child
		if multiplayer.has_multiplayer_peer(): _sync_event.rpc("heart",global_position)

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if health <= 0 or not is_combat_runtime_active(): return
	if not is_multiplayer_authority(): return
	if not summoned:
		if not _summon_sound_played:
			_summon_sound_played = true
			_emit_sound("spawn",global_position)
		summon_time = minf(summon_time+delta,summon_duration)
		_summon_visual()
		queue_redraw()
		if summon_time >= summon_duration:
			summoned = true
			if image is Sprite2D:
				(image as Sprite2D).visible = true
			if multiplayer.has_multiplayer_peer(): _sync_event.rpc("awake",global_position)
			_blast(global_position,110.0,45.0,null,false)
			_show_explosion(global_position,110.0)
			_emit_sound("explode",global_position)
		return
	_idle_left -= delta
	if _idle_left <= 0:
		_idle_left = _mc_rng.randf_range(8.0,14.0)
		_emit_sound("idle%d" % _mc_rng.randi_range(1,2),global_position)
	_buff_left = maxf(_buff_left-delta,0.0)
	if _buff_left <= 0: _buff = ""
	if _buff == "regeneration":
		_regen_clock += delta
		if _regen_clock >= 1.0:
			_regen_clock -= 1.0
			health = minf(health+2.0,Max_health)
	_shot_left -= delta
	_rose_left -= delta
	_charge_left -= delta
	var target:ball = mc_nearest(delta)
	if _windup > 0:
		_windup -= delta
		if _windup <= 0 and target != null and health > 0: _fire_skull(target.global_position)
	elif _shot_left <= 0 and target != null and not dizziness and is_damage_output_disabled() == false:
		_windup = 0.5
		_shot_left = skull_interval*(0.9 if _buff == "haste" else 1.0)
	if _rose_left <= 0:
		_rose_left = rose_interval
		var own_roses:int = 0
		for rose:Node in get_tree().get_nodes_in_group("WitherRose"):
			if is_instance_valid(rose) and rose.get("source_ref") is WeakRef and rose.get("source_ref").get_ref() == self: own_roses += 1
		if own_roses < 3: _grow_rose()
	if _charge_windup > 0:
		_charge_windup -= delta
		if _charge_windup <= 0: _charge_remaining = 130.0
	elif _charge_remaining > 0:
		var travel:float = minf(500.0*delta,_charge_remaining)
		var old:Vector2 = global_position
		# Even the special charge uses the normal CharacterBody collision solver.
		velocity = _charge_dir*500.0+Repel
		move_and_slide()
		var next:Vector2 = global_position
		var moved:float = old.distance_to(next)
		_charge_remaining = maxf(_charge_remaining-moved,0.0) if moved > 0.1 else 0.0
		if moved > 0.1:
			for node:Node in SubmissionCharacterTools.targeting_candidates(self):
				if node is ball and mc_enemy(node) and not _charge_hits.has(node.get_instance_id()):
					var enemy:ball = node as ball
					if Geometry2D.get_closest_point_to_segment(enemy.global_position,old,next).distance_to(enemy.global_position) <= enemy.get_crowd_separation_radius_world()+42.0 and mc_line_clear(old,enemy.global_position):
						_charge_hits[enemy.get_instance_id()] = true
						impact(enemy,32.0,enemy.global_position)
						enemy.Repel += _charge_dir*60.0
	elif _charge_left <= 0 and target != null and global_position.distance_to(target.global_position) < 175.0 and _windup <= 0:
		_charge_dir = (target.global_position-global_position).normalized()
		_charge_windup = 0.45
		_charge_left = charge_interval
		_charge_hits.clear()
		_emit_sound("shoot",global_position)
	_sync_left -= delta
	if _sync_left <= 0:
		_sync_left = 0.15
		if multiplayer.has_multiplayer_peer(): _sync_appearance.rpc(summon_time,summoned,heart_dropped,_buff)

func move(speed:float,delta:float) -> void:
	if not summoned or _charge_remaining > 0 or _charge_windup > 0:
		velocity = Vector2.ZERO
		return
	# The regular ball AI/player direction, collision response, speed modifiers,
	# knockback and crowd separation must all come from the common move path.
	super.move(speed*(1.1 if _buff == "speed" else 1.0),delta)

func _fire_skull(point:Vector2) -> void:
	var skull:Node2D = SKULL.new()
	get_tree().current_scene.add_child(skull,true)
	skull.global_position = global_position+(point-global_position).normalized()*58.0
	skull.call("configure",self,(point-global_position).normalized())
	skull.add_to_group("BattleTransient")
	_emit_sound("shoot",global_position)
func _grow_rose() -> void:
	var rect:Rect2 = mc_arena_rect().grow(-30.0)
	var where:Vector2 = global_position
	for i:int in range(14):
		var point:Vector2 = Vector2(_mc_rng.randf_range(rect.position.x,rect.end.x),_mc_rng.randf_range(rect.position.y,rect.end.y))
		if mc_position_clear(point,14.0):
			where = point
			break
	var rose:Node2D = ROSE.new()
	get_tree().current_scene.add_child(rose,true)
	rose.global_position = where
	rose.call("configure",self)
	rose.add_to_group("BattleTransient")
	_emit_sound("rose",where)
func impact(target:ball,amount:float,point:Vector2) -> float:
	if not is_multiplayer_authority() or not mc_enemy(target) or is_damage_output_disabled(): return 0.0
	var before:float = maxf(target.health,0.0)
	var adjusted:float = amount*(1.1 if _buff == "strength" and _buff_left > 0 else 1.0)
	target.receive_positional_damage(adjusted,point,false,self)
	var actual:float = maxf(before-maxf(target.health,0.0),0.0) if is_instance_valid(target) else before
	if actual > 0:
		if multiplayer.has_multiplayer_peer(): _hit_sound.rpc(point,actual)
		_hit_sound(point,actual)
	return actual
@rpc("authority","call_remote","reliable")
func _hit_sound(point:Vector2,actual:float) -> void:
	AUDIO.play(self,"entity.player.attack.crit" if actual > 50.0 else "entity.player.hurt",point,HIT_GAIN.damage_gain(actual),false,true,true,true)
func apply_wither(target:ball) -> void:
	if not mc_enemy(target) or not target.can_receive_negative_effects(): return
	var status:Node = target.get_node_or_null("WitherStatus")
	if status == null:
		status = preload("res://scripts/characters/我的世界/wither/status.gd").new()
		status.name = "WitherStatus"
		target.add_child(status)
	status.call("refresh",self)
func _blast(center:Vector2,radius:float,damage:float,direct:ball,apply_effect:bool) -> void:
	for node:Node in SubmissionCharacterTools.targeting_candidates(self):
		if node is ball and mc_enemy(node):
			var target:ball = node as ball
			if target.global_position.distance_to(center) > radius+target.get_crowd_separation_radius_world(): continue
			if not mc_line_clear(center,target.global_position): continue
			if impact(target,75.0 if target == direct else damage,center) > 0 and apply_effect: apply_wither(target)
func apply_beacon_buff(kind:String) -> void:
	_buff = kind
	_buff_left = 6.0
	_regen_clock = 0.0
func _show_explosion(point:Vector2,visual_radius:float) -> void:
	# Use the same shared, self-cleaning Minecraft visual as Creeper explosions.
	# Combat damage and the original Wither explosion sound are settled elsewhere.
	var effect:Node2D = MC_EXPLOSION_SCENE.instantiate() as Node2D
	if effect == null: return
	effect.set("radius",visual_radius)
	effect.set("play_audio",false)
	effect.name = "WitherExplosionVisual"
	effect.position = point
	MC_EXPLOSION.runtime_container(self).add_child(effect,true)
	effect.global_position = point
func _sync_skull_explosion(point:Vector2) -> void:
	if multiplayer.has_multiplayer_peer(): _sync_event.rpc("skull_blast",point)
func summon_sand_rect(index:int) -> Rect2:
	# Four identical square soul-sand blocks in the original T layout.
	var cells:Array[Vector2i] = [Vector2i(0,1),Vector2i(0,0),Vector2i(-1,0),Vector2i(1,0)]
	var column:Vector2i = cells[index]
	return Rect2(Vector2(float(column.x)*SUMMON_BLOCK_SIZE-SUMMON_BLOCK_SIZE*0.5,float(column.y)*SUMMON_BLOCK_SIZE-SUMMON_BLOCK_SIZE*0.5),Vector2.ONE*SUMMON_BLOCK_SIZE)
func summon_head_rect(index:int) -> Rect2:
	return Rect2(float(index-1)*SUMMON_BLOCK_SIZE-SUMMON_HEAD_SIZE*0.5,-SUMMON_BLOCK_SIZE-SUMMON_HEAD_SIZE*0.5, SUMMON_HEAD_SIZE,SUMMON_HEAD_SIZE)
func _emit_sound(event:String,point:Vector2) -> void:
	VANILLA_SOUND.play(self,event,point)
	if multiplayer.has_multiplayer_peer(): _sync_event.rpc(event,point)
func _draw() -> void:
	if summoned or summon_time <= 0 or health <= 0: return
	var t:float = summon_time/maxf(summon_duration,0.01)
	draw_texture_rect(SOUL_SAND,summon_sand_rect(0),false)
	if t > 0.20: draw_texture_rect(SOUL_SAND,summon_sand_rect(1),false)
	if t > 0.35: draw_texture_rect(SOUL_SAND,summon_sand_rect(2),false)
	if t > 0.48: draw_texture_rect(SOUL_SAND,summon_sand_rect(3),false)
	for i:int in range(3):
		if t > 0.53+float(i)*0.10: draw_texture_rect(HEAD,summon_head_rect(i),false)
func _process(delta:float) -> void:
	if not summoned: _summon_visual()
	if _bedrock_model != null:
		_animation_life += delta if is_combat_runtime_active() else 0.0
		_bedrock_model.call("animate",_animation_life,direction,summoned,summon_time/maxf(summon_duration,0.01),health <= Max_health*0.5)
	if health <= 0: return
	queue_redraw()
func _summon_visual() -> void:
	if not image is Sprite2D: return
	var t:float = summon_time/maxf(summon_duration,0.01)
	(image as Sprite2D).visible = t >= 0.8
func get_ai_attack_threats(_receiver:ball) -> Array:
	if health <= 0: return []
	if not summoned and summon_time > summon_duration-0.4:
		return [{"shape":"circle","position":global_position,"radius":110.0,"damage":45.0,"danger_in":maxf(summon_duration-summon_time,0.0),"danger_duration":0.1,"source":self}]
	if _charge_windup > 0 or _charge_remaining > 0:
		return [{"shape":"segment","start":global_position,"end":global_position+_charge_dir*(130.0 if _charge_windup>0 else _charge_remaining),"radius":42.0,"damage":32.0,"danger_in":maxf(_charge_windup,0.0),"danger_duration":0.3,"source":self}]
	return []
func get_debug_attack_regions() -> Array: return get_ai_attack_threats(null)
@rpc("authority","call_remote","unreliable_ordered")
func _sync_appearance(time:float,awake:bool,dropped:bool,buff:String) -> void:
	summon_time = time
	summoned = awake
	heart_dropped = dropped
	_buff = buff
	if awake and image is Sprite2D:
		(image as Sprite2D).visible = true
	else: _summon_visual()
	queue_redraw()
@rpc("authority","call_remote","reliable")
func _sync_event(kind:String,point:Vector2) -> void:
	if kind == "awake": _show_explosion(point,110.0)
	elif kind == "skull_blast": _show_explosion(point,64.0)
	else: VANILLA_SOUND.play(self,kind,point)
func Die() -> void:
	if health <= 0 and summoned and is_multiplayer_authority(): _emit_sound("death",global_position)
	if is_instance_valid(beacon): beacon.queue_free()
	for ref:WeakRef in _effects:
		var effect:Node = ref.get_ref()
		if is_instance_valid(effect): effect.queue_free()
	_buff = ""
	super.Die()
