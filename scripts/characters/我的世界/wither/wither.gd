extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")
## 旋转觉醒后发射头弹/冲撞；仅 Boss 特殊化半血召唤信标。权威端结算。
const PREVIEW = preload("res://Images/characters/我的世界/wither/bedrock/wither_preview.png")
const BODY = preload("res://Images/characters/我的世界/wither/wither_front.png")
const LIVE_RIG = preload("res://scripts/characters/我的世界/wither/bedrock_rig.gd")
const MC_EXPLOSION_SCENE:PackedScene = preload("res://scenes/effects/我的世界/MC爆炸.tscn")
const MC_EXPLOSION = preload("res://scripts/effects/我的世界/mc_explosion.gd")
const VANILLA_SOUND = preload("res://scripts/characters/我的世界/wither/audio.gd")
const SKULL = preload("res://scripts/characters/我的世界/wither/skull.gd")
const BEACON = preload("res://scenes/creatures/我的世界/凋零信标.tscn")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const HIT_GAIN = preload("res://scripts/effects/我的世界/hit_audio_gain.gd")
const ACTIVE_TOOLTIP = preload("res://scripts/ui/mc_active_effect_tooltip.gd")
const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const OBSTACLES = preload("res://scripts/effects/我的世界/ghast_obstacle_damage.gd")
const CHARGE_RESET = preload("res://scripts/characters/我的世界/wither/charge_reset.gd")
const CHARGE_DAMAGE:float = 80.0
const BOSS_CHARGE_DAMAGE:float = 100.0
const AWAKENING_DAMAGE:float = 80.0
const BOSS_AWAKENING_DAMAGE:float = 120.0
const CHARGE_SPEED:float = 325.0 # 65% of the previous speed; preserve the deceleration curve.
const CHARGE_VISUALS = preload("res://scripts/effects/我的世界/mc_visual_effects.gd")
const CHARGE_SMOKE = preload("res://Images/characters/我的世界/wither/big_smoke_0.png")
const AWAKENING_BLAST_RADIUS:float = 72.0
const BASE_ATTACK_DAMAGE:float = 75.0 # The unbuffed Damage in 凋灵.tscn; attack weights are relative to it.
const SKULL_WINDUP:float = 0.30
const SHOT_HEAD_ORDER = [0,2,1] # Center, screen-left, screen-right.
# Entire intro is now the spin; no hidden block-construction portion.
@export var summon_duration:float = 3.0
@export var skull_interval:float = 3.0 # Each head has its own cooldown.
@export var skull_global_cooldown:float = 0.45 # Shared gap after every shot.
@export var charge_interval:float = 12.0
var summon_time:float = 0.0
var summoned:bool = false
var heart_dropped:bool = false
var _boss_specialized:bool = false
var beacon:ball
var _head_shot_left:Array[float] = [1.0,1.0,1.0]
var _global_shot_left:float = 0.0
var _charge_left:float = 12.0
var _windup:float = 0.0
var _windup_head:int = -1 # Slot in SHOT_HEAD_ORDER, not a bone index.
var _manual_skull_windup:bool = false
var _manual_skull_point:Vector2 = Vector2.ZERO
var _charge_windup:float = 0.0
var _charge_dir:Vector2 = Vector2.RIGHT
var _charge_remaining:float = 0.0
var _charge_total_dist:float = 0.0
var _charge_smoke_distance:float = 0.0
var _charge_hits:Dictionary = {}
var _charge_broken:Dictionary = {}
var _sync_left:float = 0.0
var _buff:String = ""
var _buff_left:float = 0.0
var _summon_sound_played:bool = false
var _idle_left:float = 8.0
var _effects:Array[WeakRef] = []
var reflected_count:int = 0
var _bedrock_viewport:SubViewport
var _bedrock_model:Node3D
var _bedrock_camera:Camera3D
var _animation_life:float = 0.0
var _next_shoot_head:int = 0
var _remote_body_heading:Vector2 = Vector2.ZERO
var _remote_look_position:Vector2 = Vector2.ZERO
var _remote_aim_valid:bool = false

func has_training_boss_specialization() -> bool:
	return true

func prepare_training_boss_specialization(_boss_multiplier:float) -> void:
	# World has already applied generic scaling; only health is replaced.
	Max_health = 1000
	_boss_specialized = true

func awakening_damage() -> float:
	return BOSS_AWAKENING_DAMAGE if _boss_specialized else AWAKENING_DAMAGE

func charge_damage() -> float:
	return BOSS_CHARGE_DAMAGE if _boss_specialized else CHARGE_DAMAGE

func skull_direct_damage() -> float:
	return SKULL.BOSS_DIRECT_DAMAGE if _boss_specialized else SKULL.DIRECT_DAMAGE

func skull_splash_damage() -> float:
	return SKULL.BOSS_SPLASH_DAMAGE if _boss_specialized else SKULL.SPLASH_DAMAGE

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	mc_audio_role = ""
	super._ready()
	_create_live_model()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bedrock_model.call("animate",0.0,Vector2.ZERO,false,0.0,false,[],0.0)
	_summon_visual()
	queue_redraw()

func _create_live_model() -> void:
	if not image is Sprite2D: return
	_bedrock_viewport = SubViewport.new()
	_bedrock_viewport.name = "MojangBedrockWitherLive3D"
	_bedrock_viewport.size = Vector2i(384,384)
	_bedrock_viewport.transparent_bg = true
	_bedrock_viewport.own_world_3d = true
	_bedrock_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_bedrock_viewport)
	var camera:=Camera3D.new()
	_bedrock_camera = camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.2 # Include the inflated shield and upward-looking central head.
	camera.position = Vector3(0,2.0,-6)
	_bedrock_viewport.add_child(camera)
	camera.look_at(Vector3(0,2.0,0),Vector3.UP)
	camera.current = true
	_bedrock_model = LIVE_RIG.new() as Node3D
	_bedrock_viewport.add_child(_bedrock_model)
	var sprite:Sprite2D = image as Sprite2D
	sprite.texture = _bedrock_viewport.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE*(0.425*5.2/4.3) # Preserve world texels per model unit despite extra camera margins.
func get_preview_texture() -> Texture2D:
	if _bedrock_viewport != null: return _bedrock_viewport.get_texture()
	# Selection/placement instances never enter the tree: no viewport exists.
	return PREVIEW
func _get_hit_effect_visual_texture() -> Texture2D:
	# CPU-only shadow sampling cannot read a live GPU ViewportTexture in headless
	# mode. Keep the original-source 2D silhouette solely for this sampler.
	return BODY
func set_character_visual_flip_h(_flipped:bool) -> void:
	# ball.move otherwise mirrors the 3D ViewportTexture after the model
	# leans, making head tracking and projected skull origins disagree.
	super.set_character_visual_flip_h(false)
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority(): return -1
	var next:int = State.Die if health <= 0 else (State.Move if summoned and is_combat_runtime_active() and not dizziness else State.Stand)
	return -1 if state == next else next
func Attack() -> void: Attacking = false
func Skill() -> void: Using_Skill = false
func take_damage(amount:float,ignore_block:bool = false) -> void:
	if not summoned and health > 0: return
	# The shared Resistance Buff is already applied in ball.take_damage().
	super.take_damage(amount,ignore_block)
func can_receive_hit_from(incoming_hit) -> bool:
	if summoned or not is_multiplayer_authority() or incoming_hit == null: return true
	var shot:Node = incoming_hit.get_parent()
	if not PROJECTILE_API.is_projectile(shot): shot = incoming_hit.owner
	try_reflect_projectile(shot)
	return false

func try_reflect_projectile(shot:Node) -> bool:
	if summoned or health <= 0 or not is_multiplayer_authority() or not shot is Node2D: return false
	if not PROJECTILE_API.reflect(shot,self,76.0): return false
	reflected_count += 1
	return true

func should_destroy_projectile_on_rejected_hit(incoming_hit:hitbox) -> bool:
	if incoming_hit == null: return true
	var shot:Node = incoming_hit.get_parent()
	return not (PROJECTILE_API.is_projectile(shot) and int(shot.get_meta("projectile_reflected_frame",-1)) == Engine.get_physics_frames())

func _reflect_shot(shot:Node) -> void:
	try_reflect_projectile(shot)

func on_actual_health_damage_received(actual:float,before:float) -> void:
	super.on_actual_health_damage_received(actual,before)
	if actual > 0 and summoned and health > 0:
		_emit_sound("hurt%d" % _mc_rng.randi_range(1,4),global_position)
	if _boss_specialized and actual > 0 and summoned and not heart_dropped and health > 0 and health <= Max_health*0.5 and is_multiplayer_authority():
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
		if summon_time+0.0000001 >= summon_duration:
			summon_time = summon_duration
			summoned = true
			if image is Sprite2D:
				(image as Sprite2D).visible = true
			if multiplayer.has_multiplayer_peer(): _sync_event.rpc("awake",global_position)
			_blast(global_position,AWAKENING_BLAST_RADIUS,awakening_damage(),null,false)
			_show_explosion(global_position,AWAKENING_BLAST_RADIUS)
			_emit_sound("explode",global_position)
		return
	_idle_left -= delta
	if _idle_left <= 0:
		_idle_left = _mc_rng.randf_range(8.0,14.0)
		_emit_sound("idle%d" % _mc_rng.randi_range(1,2),global_position)
	_buff_left = maxf(_buff_left-delta,0.0)
	if _buff_left <= 0 and not _buff.is_empty():
		EFFECTS.clear(self,_buff,self)
		_buff = ""
	for i:int in range(3): _head_shot_left[i] = maxf(_head_shot_left[i]-delta,0.0)
	_global_shot_left = maxf(_global_shot_left-delta,0.0)
	_charge_left -= delta
	var target:ball = mc_nearest(delta)
	if _windup_head >= 0:
		if (not _manual_skull_windup and (target == null or target.health <= 0)) or dizziness or is_damage_output_disabled():
			# A cancelled windup must not consume this head's cooldown or the shared gap.
			_windup = 0.0
			_windup_head = -1
			_manual_skull_windup = false
		else:
			_windup = maxf(_windup-delta,0.0)
			if _windup <= 0.0:
				var firing_head:int = _windup_head
				_windup_head = -1
				var point:Vector2 = _manual_skull_point if _manual_skull_windup else ball.body_point(target,global_position)
				if has_player_control_aim(): point=player_control_aim_world_position()
				_manual_skull_windup = false
				_fire_skull(point,firing_head)
	elif not is_player_controlled() and _global_shot_left <= 0.0 and target != null and not dizziness and not is_damage_output_disabled():
		# Round-robin through READY heads; a cooling head cannot block the others.
		for offset:int in range(3):
			var head_slot:int = (_next_shoot_head+offset)%3
			if _head_shot_left[head_slot] <= 0.0:
				_windup_head = head_slot
				_windup = SKULL_WINDUP
				break
	if _charge_windup > 0:
		_charge_windup -= delta
		velocity = Vector2.ZERO
		if _charge_windup <= 0:
			_charge_remaining = _charge_wall_distance(global_position,_charge_dir)
			_charge_total_dist = _charge_remaining
			_charge_smoke_distance = 0.0
			if _charge_remaining > 0.0: _break_charge_obstacles(global_position,global_position)
	elif _charge_remaining > 0:
		var dist_frac:float = clampf(_charge_remaining/maxf(_charge_total_dist,1.0),0.0,1.0)
		var current_speed:float = lerpf(CHARGE_SPEED*0.45,CHARGE_SPEED*1.55,dist_frac)
		var travel:float = minf(current_speed*delta,_charge_remaining)
		var old:Vector2 = global_position
		var next:Vector2 = old+_charge_dir*travel
		# Check map boundary / obstacle wall intersection
		var max_avail:float = _charge_wall_distance(old,_charge_dir)
		if travel >= max_avail:
			travel = max_avail
			next = old+_charge_dir*travel
			_charge_remaining = 0.0
		else:
			_charge_remaining = maxf(_charge_remaining-travel,0.0)
		# The charge is a swept pass-through, not CharacterBody sliding. Break
		# obstacles BEFORE moving so neither props nor other bodies can stop it.
		_break_charge_obstacles(old,next)
		global_position = next
		velocity = _charge_dir*current_speed
		if travel > 0.0:
			_emit_charge_smoke(old,next)
			for node:Node in SubmissionCharacterTools.targeting_candidates(self):
				if node is ball and mc_enemy(node) and not _charge_hits.has(node.get_instance_id()):
					var enemy:ball = node as ball
					if enemy.is_in_group("BuilderWall") or (enemy.has_method("is_builder_wall") and enemy.is_builder_wall()): continue
					if Geometry2D.get_closest_point_to_segment(ball.body_point_seg(enemy,old,next),old,next).distance_to(ball.body_point(enemy,Geometry2D.get_closest_point_to_segment(ball.body_point_seg(enemy,old,next),old,next))) <= enemy.get_crowd_separation_radius_world()+42.0:
						_charge_hits[enemy.get_instance_id()] = true
						impact(enemy,charge_damage(),enemy.global_position,true)
						enemy.Repel += _charge_dir*60.0
			# Builder walls inherit ball and cannot be mined by the static-body
			# manager. They are obstacles, not another charge-damage combat target.
			_break_charge_builder_walls(old,next)
		if _charge_remaining <= 0.0:
			velocity = Vector2.ZERO
			_charge_total_dist = 0.0
	elif not is_player_controlled() and target != null: _begin_charge_at(ball.body_point(target,global_position))
	_sync_left -= delta
	if _sync_left <= 0:
		_sync_left = 0.15
		if multiplayer.has_multiplayer_peer():
			var body_heading:Vector2 = _visual_body_heading()
			_sync_appearance.rpc(summon_time,summoned,heart_dropped,_buff,_buff_left,body_heading,_visual_look_point(body_heading))

func _emit_charge_smoke(from:Vector2,to:Vector2) -> void:
	var length:float = from.distance_to(to)
	if length <= 0.0: return
	var heading:Vector2 = from.direction_to(to)
	var sample:Dictionary = CHARGE_VISUALS.sample_smoke_trail(from,to,12.0,30.0,_charge_smoke_distance)
	var points:PackedVector2Array = sample.points
	_charge_smoke_distance = float(sample.distance)
	if points.is_empty(): return
	_show_charge_smoke(points,heading)
	if multiplayer.has_multiplayer_peer(): _show_charge_smoke.rpc(points,heading)

@rpc("authority","call_remote","unreliable")
func _show_charge_smoke(points:PackedVector2Array,heading:Vector2) -> void:
	if health <= 0 or not is_combat_runtime_active(): return
	var side:Vector2 = heading.orthogonal()
	for point:Vector2 in points:
		for sign_value:float in [-1.0,1.0]:
			CHARGE_VISUALS.smoke_particle(self,point+side*sign_value*8.0,CHARGE_SMOKE,
				-heading*18.0+side*sign_value*12.0,0.65,12.0,Color(0.22,0.22,0.22,0.85))

@rpc("authority","call_remote","unreliable")
func _show_skull_trail(points:PackedVector2Array,heading:Vector2) -> void:
	# Skull nodes only simulate on the authority. Replicate visuals on the stable Wither path.
	if health <= 0 or not is_combat_runtime_active(): return
	for index:int in range(mini(points.size(),48)):
		CHARGE_VISUALS.smoke_particle(self,points[index],CHARGE_SMOKE,
			-heading*12.0,0.5,8.0,Color(0.22,0.22,0.22,0.85))

func controlled_attack_action() -> void:
	if not is_player_controlled() or not mc_live() or not summoned or dizziness or not has_player_control_aim() or _windup_head>=0 or _global_shot_left>0.0: return
	for offset:int in range(3):
		var slot:int=(_next_shoot_head+offset)%3
		if _head_shot_left[slot]<=0.0:
			_windup_head=slot
			_windup=SKULL_WINDUP
			_manual_skull_windup=true
			_manual_skull_point=player_control_aim_world_position()
			break
func controlled_skill_action() -> void:
	# With flowers removed, charge is the second action (right mouse); no empty middle slot.
	if is_player_controlled() and mc_live() and summoned and not dizziness and has_player_control_aim(): _begin_charge_at(player_control_aim_world_position())
func _begin_charge_at(point:Vector2) -> void:
	if _charge_left>0.0 or _windup_head>=0 or _charge_windup>0.0 or _charge_remaining>0.0 or dizziness or is_damage_output_disabled(): return
	var offset:Vector2=point-global_position
	if offset.length_squared()<0.0001 or offset.length()>=175.0: return
	_charge_dir=offset.normalized()
	_charge_windup=0.45
	_charge_left=charge_interval
	_charge_hits.clear()
	_charge_broken.clear()
	Repel=Vector2.ZERO
	_emit_sound("charge",global_position)

func _charge_half_size() -> Vector2:
	if collision_shape_2d != null and collision_shape_2d.shape != null:
		return collision_shape_2d.shape.get_rect().size*collision_shape_2d.global_scale.abs()*0.5
	return Vector2(42.0,42.0)

func _charge_wall_distance(start:Vector2,heading:Vector2) -> float:
	# The nearest map REGION, not the union bounding box: on portal/irregular
	# maps a charge must not cross a gap just because another island is ahead.
	var rect:Rect2 = Rect2()
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("map_island_rects"):
		var map_node:Node = world._current_map_node()
		if map_node != null:
			rect = world.nearest_map_island_rect(start,world.map_island_rects(map_node))
	if not rect.has_area(): rect = mc_arena_rect()
	var half:Vector2 = _charge_half_size()+Vector2.ONE
	rect = rect.grow_individual(-half.x,-half.y,-half.x,-half.y)
	if not rect.has_area() or not rect.has_point(start): return 0.0
	var distance:float = INF
	if heading.x > 0.00001: distance = minf(distance,(rect.end.x-start.x)/heading.x)
	elif heading.x < -0.00001: distance = minf(distance,(rect.position.x-start.x)/heading.x)
	if heading.y > 0.00001: distance = minf(distance,(rect.end.y-start.y)/heading.y)
	elif heading.y < -0.00001: distance = minf(distance,(rect.position.y-start.y)/heading.y)
	return maxf(distance,0.0) if is_finite(distance) else 0.0

func _charge_swept_rect(from:Vector2,to:Vector2) -> Rect2:
	var half:Vector2 = _charge_half_size()
	return Rect2(from.min(to)-half,to.max(from)-from.min(to)+half*2.0)

func _charge_world_rect(owner:Node2D,local:Rect2) -> Rect2:
	var result:Rect2 = Rect2(owner.to_global(local.position),Vector2.ZERO)
	for corner:Vector2 in [Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)]:
		result = result.expand(owner.to_global(corner))
	return result

func _break_charge_obstacles(from:Vector2,to:Vector2) -> void:
	# Reuse the existing reversible, multiplayer-safe Minecraft terrain
	# destruction path. Samples overlap but each obstacle is broken only once.
	var manager:Node = OBSTACLES.ensure(self)
	CHARGE_RESET.ensure(self)
	var world:Node = get_tree().current_scene
	var half:Vector2 = _charge_half_size()
	var pieces:int = maxi(1,ceili(from.distance_to(to)/maxf(minf(half.x,half.y)*0.5,12.0)))
	for i:int in range(pieces):
		var a:Vector2 = from.lerp(to,float(i)/pieces)
		var b:Vector2 = from.lerp(to,float(i+1)/pieces)
		var corridor:Rect2 = _charge_swept_rect(a,b)
		var updates:Array = manager.collect_blast(self,(a+b)*0.5,half.length()+a.distance_to(b)*0.5+2.0)
		var broken:Array = []
		for update:Dictionary in updates:
			var obstacle:Node = world.get_node_or_null(update.path)
			if not is_instance_valid(obstacle): continue
			var moss:bool = bool(update.get("moss",false))
			var key:String = "%s/moss/%s" % [str(update.path),str(update.serial)] if moss else str(update.key)
			if _charge_broken.has(key): continue
			if moss:
				if not corridor.has_point(update.point): continue
			elif obstacle is Node2D:
				if not corridor.intersects(_charge_world_rect(obstacle,update.rect),true): continue
			else: continue
			_charge_broken[key] = true
			if not moss:
				update.hits = 3 # Legacy hit counter for older clients and tests.
				update.force_progress = 100.0 # Full shatter even for tuned hard obstacles.
			broken.append(update)
		# Placeable terrain stones opt out of Ghast explosions, but they are
		# ordinary physical obstacles for this Wither-specific all-clearing ram.
		# They are transient scene nodes, not map ground or boundary colliders.
		for node:Node in get_tree().get_nodes_in_group("PlaceableObstacle"):
			if not node is StaticBody2D or not world.is_ancestor_of(node) or node.is_queued_for_deletion(): continue
			if not bool(node.get_meta("ghast_indestructible",false)) or bool(node.get_meta("mc_map_boundary",false)) or bool(node.get_meta("map_safety_frame",false)): continue
			var stone:StaticBody2D = node as StaticBody2D
			var id:String = "placed:%d" % stone.get_instance_id()
			if _charge_broken.has(id): continue
			var shape:CollisionShape2D = stone.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if shape == null or shape.disabled or shape.shape == null or not corridor.intersects(_charge_world_rect(shape,shape.shape.get_rect()),true): continue
			_charge_broken[id] = true
			var path:NodePath = world.get_path_to(stone)
			if multiplayer.has_multiplayer_peer(): _charge_placed_obstacle_destroy.rpc(path)
			_charge_placed_obstacle_destroy(path)
		if broken.is_empty(): continue
		if multiplayer.has_multiplayer_peer(): _charge_obstacle_damage.rpc(broken)
		manager.apply_updates(broken)

func _break_charge_builder_walls(from:Vector2,to:Vector2) -> void:
	var corridor:Rect2 = _charge_swept_rect(from,to)
	for node:Node in get_tree().get_nodes_in_group("BuilderWall"):
		if not node is ball or node == self or node.health <= 0 or node.is_queued_for_deletion(): continue
		var wall:ball = node as ball
		if _charge_hits.has(wall.get_instance_id()): continue
		var shape:CollisionShape2D = wall.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape == null or shape.shape == null or not corridor.intersects(_charge_world_rect(shape,shape.shape.get_rect()),true): continue
		_charge_hits[wall.get_instance_id()] = true
		var previous:float = wall.health
		# Structural walls can have 98% damage reduction; scale by their
		# actual mitigation instead of using an arbitrary high raw damage.
		var break_damage:float = (maxf(previous,wall.Max_health)+maxf(wall.block,0.0)+1.0)/maxf(1.0-wall.Damage_reduction,0.0001)
		wall.receive_positional_damage(break_damage,wall.global_position,true,self)
		var actual:float = maxf(previous-maxf(wall.health,0.0),0.0)
		if actual > 0.0:
			if multiplayer.has_multiplayer_peer(): _hit_sound.rpc(wall.global_position,actual)
			_hit_sound(wall.global_position,actual)

@rpc("authority","call_remote","reliable")
func _charge_obstacle_damage(updates:Array) -> void:
	CHARGE_RESET.ensure(self)
	OBSTACLES.ensure(self).apply_updates(updates)

@rpc("authority","call_remote","reliable")
func _charge_placed_obstacle_destroy(path:NodePath) -> void:
	var world:Node = get_tree().current_scene
	if world == null: return
	var node:Node = world.get_node_or_null(path)
	if not node is StaticBody2D or not node.is_in_group("PlaceableObstacle") or node.is_queued_for_deletion(): return
	if not bool(node.get_meta("ghast_indestructible",false)) or bool(node.get_meta("mc_map_boundary",false)) or bool(node.get_meta("map_safety_frame",false)): return
	Game.free_node(node)

func move(speed:float,delta:float) -> void:
	if not summoned or _charge_remaining > 0 or _charge_windup > 0:
		velocity = Vector2.ZERO
		return
	# The regular ball AI/player direction, collision response, speed modifiers,
	# knockback and crowd separation must all come from the common move path.
	super.move(speed,delta) # Shared Speed Buff already changes the input speed.

func head_muzzle_world_position(index:int) -> Vector2:
	if _bedrock_model == null or _bedrock_camera == null or _bedrock_viewport == null or not image is Sprite2D:
		return global_position
	var heads:Dictionary = _bedrock_model.get("bones")
	var bone:Node3D = heads.get("head%d" % (clampi(index,0,2)+1)) as Node3D
	if bone == null: return global_position
	# Minecraft head cube face: central head 8x8, side heads 6x6.
	var mouth:Vector3 = Vector3(0.0,0.25,-0.29) if index == 0 else Vector3(0.0,0.1875,-0.23)
	var projected:Vector2 = _bedrock_camera.unproject_position(bone.to_global(mouth))
	return (image as Sprite2D).to_global(projected-Vector2(_bedrock_viewport.size)*0.5)
func _fire_skull(point:Vector2,head_slot:int = -1) -> void:
	# Central -> left -> right: use the LIVE animated head's projected mouth,
	# not a guessed fixed offset from the character root.
	# Mojang head3 is screen-left and head2 is screen-right in this camera.
	var slot:int = _next_shoot_head if head_slot < 0 else clampi(head_slot,0,2)
	var head_index:int = SHOT_HEAD_ORDER[slot]
	_next_shoot_head = (slot+1)%3
	var haste_level:int = EFFECTS.level_of(self,"haste")
	var haste_rate:float = float(EFFECTS.properties("haste",haste_level).get("attack_rate",1.0))
	_head_shot_left[slot] = maxf(skull_interval,0.0)/maxf(haste_rate,0.0001)
	_global_shot_left = maxf(skull_global_cooldown,0.0)
	var origin:Vector2 = head_muzzle_world_position(head_index)
	var heading:Vector2 = point-origin
	if heading.length_squared() <= 0.000001: heading = Vector2.UP
	var skull:Node2D = SKULL.new()
	get_tree().current_scene.add_child(skull,true)
	skull.global_position = origin
	skull.call("configure",self,heading.normalized())
	skull.add_to_group("BattleTransient")
	if _bedrock_model != null: _bedrock_model.call("recoil_head",head_index)
	_emit_sound("shoot",origin)
func own_attack_damage(base_amount:float) -> float:
	# Only attacks emitted by the Wither itself read its live Damage attribute.
	# Strength/Weakness and other Damage buffs are already folded into Damage by
	# World; do not multiply the potion effect again at the hit site.
	return attack_damage(maxf(base_amount,0.0)/BASE_ATTACK_DAMAGE)
func impact(target:ball,amount:float,point:Vector2,from_wither_body:bool = false) -> float:
	if not is_multiplayer_authority() or not mc_enemy(target) or is_damage_output_disabled(): return 0.0
	var before:float = maxf(target.health,0.0)
	# Charge, head-skull (direct/splash) and awakening explosion belong to the
	# body. Beacon beams are independent attacks and keep their own
	# authored damage; the Wither status ticks off the victim's maximum health.
	var adjusted:float = own_attack_damage(amount) if from_wither_body else maxf(amount,0.0)
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
	if mc_enemy(target): EFFECTS.apply_effect(target,"wither",1,3.0,self)
func _blast(center:Vector2,radius:float,damage:float,direct:ball,apply_effect:bool) -> void:
	for node:Node in SubmissionCharacterTools.targeting_candidates(self):
		if node is ball and mc_enemy(node):
			var target:ball = node as ball
			if ball.body_point(target,center).distance_to(center) > radius+target.get_crowd_separation_radius_world(): continue
			if not mc_line_clear(center,ball.body_point(target,center)): continue
			if impact(target,skull_direct_damage() if target == direct else damage,center,true) > 0 and apply_effect: apply_wither(target)
func apply_beacon_buff(kind:String) -> void:
	if not _buff.is_empty() and _buff != kind: EFFECTS.clear(self,_buff,self)
	_buff = kind
	_buff_left = 6.0 if not kind.is_empty() else 0.0
	if not kind.is_empty():
		EFFECTS.apply_effect(self,kind,1,_buff_left,self)
	else:
		var tooltip:Node = get_node_or_null("Minecraft药水状态框")
		if tooltip != null:
			tooltip.call("refresh_display")
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
func _emit_sound(event:String,point:Vector2) -> void:
	VANILLA_SOUND.play(self,event,point)
	if multiplayer.has_multiplayer_peer(): _sync_event.rpc(event,point)
func _visual_body_heading() -> Vector2:
	# Turn whole body towards charge direction during windup and active charge
	if _charge_windup > 0.0 or _charge_remaining > 0.0: return _charge_dir
	if not summoned or velocity.length_squared() <= 36.0: return Vector2.ZERO
	return velocity.normalized()
func _visual_look_point(_body_heading:Vector2) -> Vector2:
	if _charge_windup > 0.0 or _charge_remaining > 0.0: return global_position + _charge_dir * 300.0
	if is_player_controlled() and has_player_control_aim(): return player_control_aim_world_position(global_position+Vector2.UP*250.0)
	var target:ball = mc_nearest(0.0) if is_multiplayer_authority() else null
	if target == null and is_instance_valid(Target_Enemy) and Target_Enemy is ball: target = Target_Enemy as ball
	if target != null and target.health > 0: return ball.body_point(target,global_position)
	return global_position+Vector2.UP*250.0
func _update_live_pose(delta:float) -> void:
	if _bedrock_model == null: return
	_animation_life += delta if is_combat_runtime_active() else 0.0
	var body_heading:Vector2 = _remote_body_heading if not is_multiplayer_authority() and _remote_aim_valid else _visual_body_heading()
	var look_position:Vector2 = _remote_look_position if not is_multiplayer_authority() and _remote_aim_valid else _visual_look_point(body_heading)
	var per_head:Array[Vector2] = []
	for i:int in range(3):
		var difference:Vector2 = look_position-head_muzzle_world_position(i)
		per_head.append(difference.normalized() if difference.length_squared() > 0.000001 else Vector2.UP)
	_bedrock_model.call("animate",_animation_life,body_heading,summoned,summon_time/maxf(summon_duration,0.01),health <= Max_health*0.5,per_head,delta)
func _process(delta:float) -> void:
	if not summoned: _summon_visual()
	_update_live_pose(delta)
	if health <= 0: return
	queue_redraw()
func _summon_visual() -> void:
	if not image is Sprite2D: return
	# Show the current live model immediately, including time zero / paused setup.
	(image as Sprite2D).visible = health>0
func get_ai_attack_threats(_receiver:ball) -> Array:
	if health <= 0: return []
	if not summoned and summon_time > summon_duration-0.4:
		return [{"shape":"circle","position":global_position,"radius":AWAKENING_BLAST_RADIUS,"damage":own_attack_damage(awakening_damage()),"danger_in":maxf(summon_duration-summon_time,0.0),"danger_duration":0.1,"source":self}]
	if _charge_windup > 0 or _charge_remaining > 0:
		var distance:float = _charge_wall_distance(global_position,_charge_dir) if _charge_windup>0 else _charge_remaining
		if distance > 0.0:
			return [{"shape":"segment","start":global_position,"end":global_position+_charge_dir*distance,"radius":42.0,"damage":own_attack_damage(charge_damage()),"danger_in":maxf(_charge_windup,0.0),"danger_duration":distance/CHARGE_SPEED,"source":self}]
	return []
func get_debug_attack_regions() -> Array: return get_ai_attack_threats(null)
@rpc("authority","call_remote","unreliable_ordered")
func _sync_appearance(time:float,awake:bool,dropped:bool,buff:String,buff_left:float,body_heading:Vector2,look_position:Vector2) -> void:
	summon_time = time
	summoned = awake
	heart_dropped = dropped
	if not _buff.is_empty() and _buff != buff: EFFECTS.clear(self,_buff,self)
	_buff = buff
	_buff_left = maxf(buff_left,0.0)
	if not _buff.is_empty() and _buff_left > 0.0:
		EFFECTS.apply_effect(self,_buff,1,_buff_left,self)
	else:
		var tooltip:Node = get_node_or_null("Minecraft药水状态框")
		if tooltip != null:
			tooltip.call("refresh_display")
	_remote_body_heading = body_heading
	_remote_look_position = look_position
	_remote_aim_valid = true
	if awake and image is Sprite2D:
		(image as Sprite2D).visible = true
	else: _summon_visual()
	queue_redraw()
@rpc("authority","call_remote","reliable")
func _sync_event(kind:String,point:Vector2) -> void:
	if kind == "awake": _show_explosion(point,AWAKENING_BLAST_RADIUS)
	elif kind == "skull_blast": _show_explosion(point,64.0)
	else: VANILLA_SOUND.play(self,kind,point)
func Die() -> void:
	if health <= 0 and summoned and is_multiplayer_authority(): _emit_sound("death",global_position)
	if is_instance_valid(beacon): beacon.queue_free()
	for ref:WeakRef in _effects:
		var effect:Node = ref.get_ref()
		if is_instance_valid(effect): effect.queue_free()
	if not _buff.is_empty(): EFFECTS.clear(self,_buff,self)
	_buff = ""
	super.Die()

func get_armor_test_effect_summary() -> String:
	return Game.t("MC_ARMOR_INTRO_WITHER")

