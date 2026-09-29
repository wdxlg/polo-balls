extends Node2D

const FIRE_FRAMES:SpriteFrames = preload("res://particles/mc_ground_fire.tres")
const SHARED_BURN:Script = preload("res://scripts/effects/我的世界/mc_shared_burn.gd")
const BURN_AMBIENT_SFX:AudioStream = preload("res://audio/sfx/我的世界/烈焰火焰燃烧.ogg")
const FIRE_AUDIO_NEXT_META:StringName = &"minecraft_blaze_fire_audio_next_msec"
const FIRE_AUDIO_COUNT_META:StringName = &"minecraft_blaze_fire_audio_source_count"
const MC_SMOKE_SCENE:PackedScene = preload("res://scenes/effects/我的世界/MC烟雾粒子.tscn")
const MC_DAMAGE_SFX:Script = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")

var _source_ref:WeakRef = null
var _source_team:String = ""
var _radius:float = 34.0
var _duration:float = 4.5
var _elapsed:float = 0.0
var _tick_interval:float = 0.50
var _tick_left:float = 0.0
var _area_tick_damage_multiplier:float = 0.11
var _burn_duration:float = 2.2
var _burn_tick_damage_multiplier:float = 0.05

var _main_fire:AnimatedSprite2D = null
var _fire_base_width:float = 24.0
var _fire_base_height:float = 24.0
var _fire_cell_rect:Rect2 = Rect2()
var _damage_center_offset:Vector2 = Vector2.ZERO
var _fire_visual_local_position:Vector2 = Vector2.ZERO
var _map_world_rect_cache:Rect2 = Rect2()
var _smoke_left:float = 0.0
var _rng:=RandomNumberGenerator.new()

func setup(source:ball,team:String,world_position:Vector2,radius:float,duration:float,tick_interval:float,area_tick_damage_multiplier:float,burn_duration:float,burn_tick_damage_multiplier:float) -> void:
	_source_ref = weakref(source) if source != null else null
	_source_team = team
	_radius = maxf(radius,8.0)
	_duration = maxf(duration,0.4)
	_tick_interval = maxf(tick_interval,0.10)
	_tick_left = 0.06
	_area_tick_damage_multiplier = maxf(area_tick_damage_multiplier,0.0)
	_burn_duration = maxf(burn_duration,0.1)
	_burn_tick_damage_multiplier = maxf(burn_tick_damage_multiplier,0.0)

	# 原版MC fire_0逐帧素材；烈焰人火场不复用薇欧拉的“出现/呼吸/收束”演出。
	# 火焰覆盖落点所在的一格地图方块，底边对齐格子底边；视觉尺寸与伤害半径解耦。
	_fire_cell_rect = _fire_cell_rect_at(world_position)
	_fire_base_width = _fire_cell_rect.size.x
	_fire_base_height = _fire_cell_rect.size.y

	# V36：火场根节点保留在烈焰弹的实际撞击点附近。
	# 若撞到地图边墙，只把“火焰视觉中心”和“伤害圆中心”分别向地图内部偏移，
	# 不再把整个火场根节点按伤害半径硬推离墙边。这样火焰会贴墙出现，同时仍不越界。
	global_position = _fit_and_clamp_fire_patch_to_current_map(world_position)

	# World 的地图外遮罩在 z=90。火场固定放到其上方、黑色地图边框(z=100)下方，
	# 这样贴近地图边缘时火焰与烟雾不会再被“地图外”遮掉。
	z_as_relative = false
	z_index = 92
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/我的世界/烈焰火场.gd:_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_smoke_left = _rng.randf_range(0.06,0.18)
	_build_fire_visual()
	_register_burn_audio_source()

func _build_fire_visual() -> void:
	if FIRE_FRAMES == null or FIRE_FRAMES.get_frame_count(&"default") <= 0:
		return
	_main_fire = AnimatedSprite2D.new()
	_main_fire.name = "MainFireSequence"
	_main_fire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_main_fire.sprite_frames = FIRE_FRAMES
	_main_fire.animation = &"default"
	_main_fire.frame = _rng.randi_range(0,maxi(FIRE_FRAMES.get_frame_count(&"default") - 1,0))
	_main_fire.speed_scale = 1.0
	_main_fire.z_index = 2
	_main_fire.self_modulate = Color.WHITE
	add_child(_main_fire)
	_apply_static_fire_visual()
	_main_fire.play()

func _physics_process(delta:float) -> void:
	_elapsed += maxf(delta,0.0)
	if _elapsed >= _duration:
		queue_free()
		return

	_update_burn_ambient_audio()
	_update_fire_smoke(maxf(delta,0.0))

	var source:ball = _source_ball()
	if source == null or not is_instance_valid(source) or not source.is_multiplayer_authority() or not source.is_combat_runtime_active():
		return
	_tick_left -= maxf(delta,0.0)
	while _tick_left <= 0.0:
		_tick_left += _tick_interval
		_damage_inside(source)

func _apply_static_fire_visual() -> void:
	if _main_fire == null or not is_instance_valid(_main_fire):
		return
	var reference:Texture2D = FIRE_FRAMES.get_frame_texture(&"default",0)
	if reference == null:
		return
	var tex_size:Vector2 = reference.get_size()
	_main_fire.scale = Vector2(
		_fire_base_width / maxf(tex_size.x,1.0),
		_fire_base_height / maxf(tex_size.y,1.0)
	)
	# 子视觉覆盖所在格子，底部落在方块底边；根节点仍记录实际撞击点。
	_main_fire.position = _fire_visual_local_position
	_main_fire.modulate = Color.WHITE

func _update_fire_smoke(delta:float) -> void:
	if MC_SMOKE_SCENE == null or get_tree() == null or get_tree().current_scene == null:
		return
	_smoke_left -= maxf(delta,0.0)
	if _smoke_left > 0.0:
		return
	_smoke_left = _rng.randf_range(0.24,0.42)
	_spawn_fire_smoke()


func _spawn_fire_smoke() -> void:
	var smoke:Node2D = MC_SMOKE_SCENE.instantiate() as Node2D
	if smoke == null or get_tree() == null or get_tree().current_scene == null:
		return
	smoke.name = "MC烟雾_火场_%d" % smoke.get_instance_id()
	_runtime_container().add_child(smoke,true)
	var spawn_position:Vector2 = global_position + _fire_visual_local_position + Vector2(
		_rng.randf_range(-_fire_base_width * 0.34,_fire_base_width * 0.34),
		_rng.randf_range(-_fire_base_height * 0.26,_fire_base_height * 0.32)
	)
	if _map_world_rect_cache.size.x > 0.001 and _map_world_rect_cache.size.y > 0.001:
		spawn_position = _clamp_center_inside_rect(spawn_position,_map_world_rect_cache,5.0,5.0)
	if smoke.has_method("configure"):
		smoke.call(
			"configure",
			spawn_position,
			_rng.randf_range(6.5,10.0),
			_rng.randf_range(24.0,36.0),
			_rng.randf_range(3.0,7.0),
			95,
			_rng.randf_range(0.70,0.92)
		)


func _runtime_container() -> Node:
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world == null:
		return self
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func _register_burn_audio_source() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var world:Node = get_tree().current_scene
	var before_count:int = maxi(int(world.get_meta(FIRE_AUDIO_COUNT_META,0)),0)
	world.set_meta(FIRE_AUDIO_COUNT_META,before_count + 1)
	if before_count <= 0:
		if world.has_meta(FIRE_AUDIO_NEXT_META):
			world.remove_meta(FIRE_AUDIO_NEXT_META)
		_arm_burn_audio_clock()


func _exit_tree() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var world:Node = get_tree().current_scene
	var count:int = maxi(int(world.get_meta(FIRE_AUDIO_COUNT_META,0)) - 1,0)
	if count <= 0:
		if world.has_meta(FIRE_AUDIO_COUNT_META):
			world.remove_meta(FIRE_AUDIO_COUNT_META)
		if world.has_meta(FIRE_AUDIO_NEXT_META):
			world.remove_meta(FIRE_AUDIO_NEXT_META)
	else:
		world.set_meta(FIRE_AUDIO_COUNT_META,count)


func _arm_burn_audio_clock() -> void:
	if BURN_AMBIENT_SFX == null or get_tree() == null or get_tree().current_scene == null:
		return
	var world:Node = get_tree().current_scene
	if world.has_meta(FIRE_AUDIO_NEXT_META):
		return
	var first_delay:float = _rng.randf_range(0.25,0.75)
	world.set_meta(FIRE_AUDIO_NEXT_META,Time.get_ticks_msec() + int(round(first_delay * 1000.0)))


func _update_burn_ambient_audio() -> void:
	if BURN_AMBIENT_SFX == null or get_tree() == null or get_tree().current_scene == null:
		return
	var world:Node = get_tree().current_scene
	var now_msec:int = Time.get_ticks_msec()
	var next_msec:int = int(world.get_meta(FIRE_AUDIO_NEXT_META,0))
	if next_msec <= 0:
		_arm_burn_audio_clock()
		return
	if now_msec < next_msec:
		return

	# 所有烈焰人火场共享同一个 World 级时间戳。
	# 即使场上同时有多块火，也只会由最先执行到这里的火场播放一声，
	# 随后其它火场立刻看到新的未来时间，避免多块火焰叠成一团噪声。
	var silence:float = _rng.randf_range(0.85,2.10)
	var next_delay:float = maxf(BURN_AMBIENT_SFX.get_length(),0.05) + silence
	world.set_meta(FIRE_AUDIO_NEXT_META,now_msec + int(round(next_delay * 1000.0)))
	_play_burn_ambient_sfx(world)


func _play_burn_ambient_sfx(world:Node) -> void:
	if world == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "BlazeFireAmbient"
	player.stream = BURN_AMBIENT_SFX
	player.volume_db = 4.0
	player.pitch_scale = 1.0
	player.max_distance = 1100.0
	player.attenuation = 0.78
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = global_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _damage_inside(source:ball) -> void:
	if get_world_2d() == null:
		return
	var shape := CircleShape2D.new()
	shape.radius = _radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	var damage_center:Vector2 = global_position + _damage_center_offset
	query.transform = Transform2D(0.0,damage_center)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 2
	var results:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,64)
	var seen:Dictionary = {}
	for item:Dictionary in results:
		var collider:Variant = item.get("collider",null)
		if not collider is ball:
			continue
		var target:ball = collider as ball
		if not _can_damage(target):
			continue
		var id:int = target.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		var health_before:float = maxf(float(target.health),0.0)
		var outgoing:float = source.attack_damage(_area_tick_damage_multiplier)
		var applied:bool = false
		if outgoing > 0.0:
			applied = target.receive_fire_positional_damage(outgoing,damage_center,false,source)
		var actual_damage:float = maxf(health_before - maxf(float(target.health),0.0),0.0)
		if applied and actual_damage > 0.0:
			MC_DAMAGE_SFX.play_scaled(target,target.global_position,actual_damage,source,"blaze_ground_fire")
		# 闪避/完全拒绝本次火场命中的角色不应该在瞬移后凭空被附加燃烧。
		if applied:
			_apply_burn(source,target)

func _fire_cell_rect_at(world_position:Vector2) -> Rect2:
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world != null:
		var maps:Variant = world.get("map_group")
		if maps is Dictionary:
			var map_node:Variant = maps.get(str(world.get("now_choose_map")))
			if map_node is Node:
				var layer:TileMapLayer = _fire_layer_near(map_node,world_position)
				if layer != null: return _cell_rect_on_layer(layer,world_position)
	# Non-tile test/custom arenas use the same 24px grid as MC terrain.
	var center:Vector2 = (world_position/24.0).round()*24.0
	return Rect2(center-Vector2.ONE*12.0,Vector2.ONE*24.0)
func _fire_layer_near(node:Node,point:Vector2) -> TileMapLayer:
	if node is TileMapLayer and node.tile_set != null: return node as TileMapLayer
	var closest:TileMapLayer = null
	var distance:float = INF
	for child:Node in node.get_children():
		var candidate:TileMapLayer = _fire_layer_near(child,point)
		if candidate == null: continue
		var rect:Rect2 = _cell_rect_on_layer(candidate,point)
		var gap:float = point.distance_squared_to(point.clamp(rect.position,rect.end))
		if gap < distance:
			closest = candidate
			distance = gap
	return closest
func _cell_rect_on_layer(layer:TileMapLayer,point:Vector2) -> Rect2:
	var cell:Vector2i = layer.local_to_map(layer.to_local(point))
	var used:Rect2i = layer.get_used_rect()
	if used.has_area():
		cell.x = clampi(cell.x,used.position.x,used.end.x-1)
		cell.y = clampi(cell.y,used.position.y,used.end.y-1)
	var center:Vector2 = layer.to_global(layer.map_to_local(cell))
	var tile_size:Vector2 = Vector2(layer.tile_set.tile_size)
	var size:Vector2 = Vector2(layer.global_transform.x.length()*tile_size.x,layer.global_transform.y.length()*tile_size.y)
	return Rect2(center-size*0.5,size)
func _fit_and_clamp_fire_patch_to_current_map(world_position:Vector2) -> Vector2:
	var map_rect:Rect2 = _current_map_world_rect()
	_map_world_rect_cache = map_rect
	_damage_center_offset = Vector2.ZERO
	_fire_visual_local_position = _fire_cell_rect.get_center()-world_position
	if map_rect.size.x <= 0.001 or map_rect.size.y <= 0.001:
		return world_position

	# 极小地图：伤害圆和火焰视觉分别按各自所需尺寸缩小。
	# 不再把两者合并成一个巨大包围盒，否则普通墙边命中也会被过度推向地图中央。
	var available_width:float = maxf(map_rect.size.x - 2.0,1.0)
	var available_height:float = maxf(map_rect.size.y - 2.0,1.0)
	var max_radius:float = maxf(minf(available_width,available_height) * 0.5,1.0)
	_radius = minf(_radius,max_radius)

	var visual_fit:float = minf(
		1.0,
		minf(available_width / maxf(_fire_base_width,1.0),available_height / maxf(_fire_base_height,1.0))
	)
	if visual_fit < 1.0:
		_fire_base_width = maxf(_fire_base_width * visual_fit,2.0)
		_fire_base_height = maxf(_fire_base_height * visual_fit,2.0)

	# 根节点只需要落在地图边界内；它代表烈焰弹的真实碰撞位置。
	# 只留半像素余量避免浮点误差，不使用伤害半径作为边距。
	var anchor:Vector2 = _clamp_center_inside_rect(world_position,map_rect,0.5,0.5)

	# 伤害圆必须完整位于地图内，因此只把伤害圆的查询中心向内移动。
	var damage_center:Vector2 = _clamp_center_inside_rect(anchor,map_rect,_radius,_radius)
	_damage_center_offset = damage_center - anchor

	# 火焰底边与所在格子的底边对齐，视觉占一格；地图边界仍进行安全裁限。
	var natural_visual_center:Vector2 = _fire_cell_rect.get_center()
	var visual_center:Vector2 = _clamp_center_inside_rect(
		natural_visual_center,
		map_rect,
		_fire_base_width * 0.5,
		_fire_base_height * 0.5
	)
	_fire_visual_local_position = visual_center - anchor
	return anchor


func _clamp_center_inside_rect(point:Vector2,rect:Rect2,half_width:float,half_height:float) -> Vector2:
	if rect.size.x <= 0.001 or rect.size.y <= 0.001:
		return point
	var min_x:float = rect.position.x + maxf(half_width,0.0)
	var max_x:float = rect.end.x - maxf(half_width,0.0)
	var min_y:float = rect.position.y + maxf(half_height,0.0)
	var max_y:float = rect.end.y - maxf(half_height,0.0)
	if max_x < min_x:
		min_x = rect.get_center().x
		max_x = min_x
	if max_y < min_y:
		min_y = rect.get_center().y
		max_y = min_y
	return Vector2(clampf(point.x,min_x,max_x),clampf(point.y,min_y,max_y))


func _current_map_world_rect() -> Rect2:
	if get_tree() == null or get_tree().current_scene == null:
		return Rect2()
	var world:Node = get_tree().current_scene
	if not world.has_method("return_map_world_rect"):
		return Rect2()
	var maps_value:Variant = world.get("map_group")
	if not maps_value is Dictionary:
		return Rect2()
	var maps:Dictionary = maps_value
	var map_name:String = str(world.get("now_choose_map"))
	if map_name.is_empty() or not maps.has(map_name):
		return Rect2()
	var map_node:Variant = maps[map_name]
	if not map_node is TileMapLayer:
		return Rect2()
	var rect_value:Variant = world.call("return_map_world_rect",map_node)
	if rect_value is Rect2:
		return rect_value
	return Rect2()

func _apply_burn(source:ball,target:ball) -> void:
	SHARED_BURN.apply(source,target,_burn_duration,_burn_tick_damage_multiplier)

func _can_damage(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0 or not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not _source_team.is_empty() and target.Team == _source_team:
		return false
	return true

func _source_ball() -> ball:
	if _source_ref == null:
		return null
	var raw:Variant = _source_ref.get_ref()
	return raw as ball if raw is ball and is_instance_valid(raw) else null
