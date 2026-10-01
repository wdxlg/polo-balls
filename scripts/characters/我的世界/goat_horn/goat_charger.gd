extends Node2D
## 山羊角召来的山羊：瞬时技能实体（无生命、不可选中、不计存续），全程穿过墙体与障碍。
## 权威端真实移动与结算：出现时锁定目标当时的位置，从屏幕外沿直线加速冲向该点（不追踪），
## 途中首次冲撞按速度结算伤害与击退，持续重叠时周期推撞；撞完或越过锁定点后加速冲出屏幕后释放。
## 脚步按实际移动距离计步，由权威端下发原版脚步声；奔跑时各端在身后地面上本地持续生成方块粒子。
## 贴图只朝左或朝右（按水平方向镜像），不随斜向移动旋转。
## 客户端只按山羊角下发的状态外推显示。伤害与击退来源始终是山羊角本体。
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const AUDIO = preload("res://scripts/characters/我的世界/goat_horn/goat_horn_audio.gd")
const FRAMES:SpriteFrames = preload("res://Images/characters/我的世界/goat_horn/goat/goat_frames.tres")
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
const BLOCK_FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const MAP_THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")

enum Phase { CHARGE, EXIT }

# 以下两项是角色根缩放为 1 时的尺寸，实际按山羊角本体的根缩放换算。
# 原版山羊与羊碰撞箱相同（0.9×1.3 格），显示尺寸对齐本项目的羊角色（约 20×26 世界像素 @0.2）。
const BODY_RADIUS_UNIT:float = 48.0
const SPRITE_SCALE:float = 1.1
# 帧画布 176×176，身体包围盒中心在 (85.5,103)：偏移后节点原点就是身体中心（判定圆心）。
const SPRITE_OFFSET:Vector2 = Vector2(2.5,-15.0)
const ENTER_SPEED:float = 90.0
const CHARGE_ACCEL:float = 130.0
const CHARGE_MAX_SPEED:float = 220.0
const EXIT_ACCEL:float = 300.0
const EXIT_MAX_SPEED:float = 480.0
const IMPACT_REFERENCE_SPEED:float = 245.0
const IMPACT_RATIO_MAX:float = 1.3
const RAM_SPEED_KEEP:float = 0.72
const PUSH_INTERVAL:float = 0.16
const CONTACT_RELEASE_MARGIN:float = 6.0
const BOW_LEAD_TIME:float = 0.12
const MAX_LIFE:float = 16.0
# 世界的地图外遮罩在绝对 z=90 用背景快照盖住越界视觉；山羊从屏幕外进出，必须画在它之上。
const DRAW_Z:int = 91
const OFFSCREEN_MARGIN:float = 140.0
const PRE_RAM_CHANCE:float = 0.38
# 步幅 = 4 个身体半径（按根缩放换算）；实际间隔随当前移速变化，见 footstep_cadence.gd。
const STEP_STRIDE_RADII:float = 4.0
# 身后方块粒子：每跑过 TRAIL_SPACING_RADII 个身体半径，从身后地面贴图取一小块 4×4 像素，碎成几颗小方块弹起落地。
const STEP_PARTICLE_TEXELS:int = 4
const STEP_PARTICLE_PIECES:int = 2
const TRAIL_SPACING_RADII:float = 1.2
const STEP_PARTICLE_BLOCK_RATIO:float = 0.2
# 原版 TerrainParticle 的 rCol/gCol/bCol = 0.6：地面碎屑比地面暗，和地面区分开。
const STEP_PARTICLE_SHADE:float = 0.6
const STEP_PARTICLE_Z:int = -1
static var _step_piece_cache:Dictionary = {}

var goat_id:int = 0
var heading:Vector2 = Vector2.LEFT
var speed:float = ENTER_SPEED
var phase:int = Phase.CHARGE
var bowed:bool = false
var life:float = 0.0
var unit_scale:float = 1.0
var body_radius:float = BODY_RADIUS_UNIT

var _horn_ref:WeakRef
var aim_point:Vector2 = Vector2.ZERO
var _authority:bool = false
var _contacts:Dictionary = {}
var _rammed:bool = false
var _seen_on_screen:bool = false
var _cadence:RefCounted = FOOTSTEP.new()
var _step_last:Vector2 = Vector2.ZERO
var _trail_progress:float = 0.0
var _fx_rng:RandomNumberGenerator = RandomNumberGenerator.new()
var _sprite:AnimatedSprite2D
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()
# 客户端外推：最近一次网络位置与其之后经过的时间。
var _net_position:Vector2 = Vector2.ZERO
var _net_age:float = 0.0


func setup_authority(horn:Node2D,id:int,target:Node2D,start:Vector2,seed_value:int) -> void:
	_authority = true
	goat_id = id
	_horn_ref = weakref(horn)
	_adopt_scale(horn)
	position = start
	_net_position = start
	_step_last = start
	_rng.seed = seed_value
	# 只在出现时取一次目标位置，之后不再追踪。
	aim_point = U.point(target,start) if is_instance_valid(target) else start + Vector2.LEFT * 800.0
	var aim:Vector2 = aim_point - start
	heading = aim.normalized() if aim.length_squared() > 0.01 else Vector2.LEFT
	speed = ENTER_SPEED
	name = "GoatHornGoat_%d" % id
	add_to_group("GoatHornGoat")
	add_to_group("AI_Hazard")


func setup_puppet(horn:Node2D,id:int,start:Vector2,direction:Vector2,speed_value:float,flags:int) -> void:
	_authority = false
	goat_id = id
	_horn_ref = weakref(horn)
	_adopt_scale(horn)
	position = start
	_net_position = start
	_step_last = start
	heading = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.LEFT
	speed = speed_value
	_apply_flags(flags)
	name = "GoatHornGoat_%d" % id
	add_to_group("GoatHornGoat")
	add_to_group("AI_Hazard")


func _adopt_scale(horn:Node2D) -> void:
	unit_scale = absf(horn.global_scale.x) if is_instance_valid(horn) and horn.global_scale.x != 0.0 else 1.0
	body_radius = BODY_RADIUS_UNIT * unit_scale


func _ready() -> void:
	z_as_relative = false
	z_index = DRAW_Z
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = FRAMES
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2.ONE * SPRITE_SCALE * unit_scale
	_sprite.offset = SPRITE_OFFSET
	add_child(_sprite)
	_fx_rng.randomize()
	_sprite.play(&"run")
	_sprite.frame = goat_id % FRAMES.get_frame_count(&"run")
	_update_visual()
	set_physics_process(_authority)


func horn() -> Node2D:
	var node:Variant = _horn_ref.get_ref() if _horn_ref != null else null
	return node as Node2D if is_instance_valid(node) and node.is_inside_tree() else null


func network_flags() -> int:
	return (1 if bowed else 0) | (2 if phase == Phase.EXIT else 0)


func _apply_flags(flags:int) -> void:
	bowed = (flags & 1) != 0
	phase = Phase.EXIT if (flags & 2) != 0 else Phase.CHARGE


func _runtime_active(owner_horn:Node2D) -> bool:
	return owner_horn != null and bool(owner_horn.call(&"is_combat_runtime_active"))


func _hostile(owner_horn:Node2D) -> bool:
	return owner_horn != null and float(owner_horn.get("health")) > 0.0 and not bool(owner_horn.call(&"is_damage_output_disabled"))


func impact_ratio(speed_value:float = -1.0) -> float:
	return clampf((speed if speed_value < 0.0 else speed_value) / IMPACT_REFERENCE_SPEED,0.0,IMPACT_RATIO_MAX)


func _physics_process(delta:float) -> void:
	if not _authority: return
	var owner_horn:Node2D = horn()
	if owner_horn == null:
		queue_free()
		return
	if not _runtime_active(owner_horn): return
	life += delta
	if not _hostile(owner_horn) and phase == Phase.CHARGE: begin_exit()
	if phase == Phase.CHARGE and (aim_point - global_position).dot(heading) <= 0.0: begin_exit()
	if phase == Phase.CHARGE: speed = minf(speed + CHARGE_ACCEL * delta,CHARGE_MAX_SPEED)
	else: speed = minf(speed + EXIT_ACCEL * delta,EXIT_MAX_SPEED)
	var from:Vector2 = global_position
	var to:Vector2 = from + heading * speed * delta
	global_position = to
	if _hostile(owner_horn): _resolve_contacts(owner_horn,from,to,delta)
	else: _contacts.clear()
	if phase == Phase.CHARGE and _rammed and _contacts.is_empty(): begin_exit()
	_update_bow()
	_announce(owner_horn)
	var view:Rect2 = view_rect(self)
	if phase == Phase.EXIT and view.size.x > 1.0 and not view.grow(OFFSCREEN_MARGIN).has_point(global_position):
		queue_free()
	elif life >= MAX_LIFE:
		queue_free()


func begin_exit() -> void:
	phase = Phase.EXIT


func _resolve_contacts(owner_horn:Node2D,from:Vector2,to:Vector2,delta:float) -> void:
	var source:ball = owner_horn as ball
	var touched:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(source,node) or U.wall_node(node): continue
		var victim:ball = node as ball
		var id:int = victim.get_instance_id()
		var reach:float = body_radius + U.radius(victim)
		if _contacts.has(id):
			if global_position.distance_to(U.point(victim,global_position)) > reach + CONTACT_RELEASE_MARGIN: continue
			touched[id] = true
			_contacts[id] = float(_contacts[id]) - delta
			if float(_contacts[id]) <= 0.0:
				_contacts[id] = PUSH_INTERVAL
				_push(source,victim)
			continue
		if U.segment_distance(ball.body_point_seg(victim,from,to),from,to) > reach: continue
		touched[id] = true
		_contacts[id] = PUSH_INTERVAL
		_ram(source,victim,to)
	for id:Variant in _contacts.keys():
		if not touched.has(id): _contacts.erase(id)


func _knockback_direction(victim:ball) -> Vector2:
	# 正面顶开为主，偏离中线的目标略向两侧分开，避免被山羊“吸”在额头上。
	var side:Vector2 = U.point(victim,global_position) - global_position
	var lateral:Vector2 = side - heading * side.dot(heading)
	var dir:Vector2 = heading + lateral.normalized() * 0.2 if lateral.length_squared() > 1.0 else heading
	return dir.normalized()


func _ram(source:ball,victim:ball,point:Vector2) -> void:
	var r:float = impact_ratio()
	var dealt:bool = U.damage(source,victim,source.attack_damage(0.35 + 1.25 * r),point)
	if dealt:
		victim.apply_knockback(_knockback_direction(victim),30.0 + 110.0 * r,160.0 + 520.0 * r,0.65,0.0,
			{"source":source,"max_wall_bounces":1,"collision_damage":source.attack_damage(0.25 + 0.8 * r),"collision_damage_wall_only":true,"redirect_blend_time":0.0})
		source.call(&"emit_goat_sound",AUDIO.KIND_IMPACT,_rng.randi_range(0,AUDIO.variant_count(AUDIO.KIND_IMPACT) - 1),point)
	speed *= RAM_SPEED_KEEP
	_rammed = true


func _push(source:ball,victim:ball) -> void:
	var r:float = impact_ratio()
	if not U.damage(source,victim,source.attack_damage(0.12 + 0.30 * r),U.point(victim,global_position)): return
	victim.apply_knockback(_knockback_direction(victim),16.0 + 44.0 * r,maxf(speed * 1.1,160.0 + 520.0 * r),0.65,0.0,
		{"source":source,"max_wall_bounces":1,"collision_damage":source.attack_damage(0.1 + 0.3 * r),"collision_damage_wall_only":true,"redirect_blend_time":0.0})


func _update_bow() -> void:
	if not _contacts.is_empty():
		bowed = true
		return
	bowed = false
	if phase != Phase.CHARGE: return
	var lead:float = speed * BOW_LEAD_TIME
	if global_position.distance_to(aim_point) <= body_radius * 2.0 + lead:
		bowed = true
		return
	var owner_horn:Node2D = horn()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(owner_horn as ball,node) or U.wall_node(node): continue
		var to_victim:Vector2 = U.point(node,global_position) - global_position
		if to_victim.dot(heading) > 0.0 and to_victim.length() <= body_radius + U.radius(node) + lead:
			bowed = true
			return


## 权威端：第一次进入镜头时按概率发出原版蓄力咩声。
func _announce(owner_horn:Node2D) -> void:
	if _seen_on_screen or not _on_screen(): return
	_seen_on_screen = true
	if phase == Phase.CHARGE and _rng.randf() < PRE_RAM_CHANCE:
		owner_horn.call(&"emit_goat_sound",AUDIO.KIND_PRE_RAM,_rng.randi_range(0,AUDIO.variant_count(AUDIO.KIND_PRE_RAM) - 1),global_position)


func _on_screen() -> bool:
	var view:Rect2 = view_rect(self)
	return view.size.x > 1.0 and view.has_point(global_position)


## 各端：按实际走过的距离计步与撒粒子。权威端发脚步声（变体由权威端挑选并下发），粒子各端本地生成。
func _step_tick(owner_horn:Node2D,delta:float) -> void:
	var moved:float = global_position.distance_to(_step_last)
	_step_last = global_position
	if moved > body_radius * STEP_STRIDE_RADII * 3.0: moved = 0.0
	var on_screen:bool = _on_screen()
	_trail_progress += moved
	var spacing:float = maxf(body_radius * TRAIL_SPACING_RADII,0.5)
	if _trail_progress >= spacing:
		# 每帧最多撒一次，避免掉帧后一次补出一大团。
		_trail_progress = fmod(_trail_progress,spacing)
		if on_screen:
			var rear:Vector2 = global_position + Vector2(0.0,body_radius * 0.7) - heading * body_radius * 0.9
			spawn_step_particles(self,rear,body_radius,_fx_rng)
	if not _cadence.tick_stride(moved,delta,body_radius * STEP_STRIDE_RADII): return
	if not on_screen: return
	if _authority and owner_horn != null:
		owner_horn.call(&"emit_goat_sound",AUDIO.KIND_STEP,_rng.randi_range(0,AUDIO.variant_count(AUDIO.KIND_STEP) - 1),global_position)


## 脚下地面：站在墙/障碍物上或地图外（含传送门岛屿之间的空隙）时没有地面，返回空表。
## 方块主题地图用主题地板贴图与染色；原版格子地图用该格瓦片的图集区域。
static func floor_sample(context:Node2D,point:Vector2) -> Dictionary:
	if context == null or not context.is_inside_tree(): return {}
	var world:Node = context.get_tree().current_scene
	if world == null or not world.has_method("_current_map_node"): return {}
	var map_node:Variant = world.call("_current_map_node")
	if not map_node is Node: return {}
	var query:PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	for hit:Dictionary in context.get_world_2d().direct_space_state.intersect_point(query,8):
		if hit.collider is StaticBody2D or hit.collider is TileMapLayer: return {}
	var layers:Array[TileMapLayer] = []
	_collect_layers(map_node,layers)
	for layer:TileMapLayer in layers:
		var cell:Vector2i = layer.local_to_map(layer.to_local(point))
		var source_id:int = layer.get_cell_source_id(cell)
		if source_id < 0: continue
		var block_px:float = layer.global_transform.x.length() * float(layer.tile_set.tile_size.x)
		if world.has_method("map_background_style") and MAP_THEMES.tiled(str(world.call("map_background_style"))):
			var key:String = str(world.call("map_background_style"))
			var floor_texture:Texture2D = MAP_THEMES.floor_texture(key)
			return {"texture":floor_texture,"region":Rect2(Vector2.ZERO,floor_texture.get_size()),"modulate":MAP_THEMES.theme(key).get("floor_modulate",Color.WHITE),"block_px":block_px}
		var source:TileSetSource = layer.tile_set.get_source(source_id)
		if not source is TileSetAtlasSource: return {}
		var atlas:TileSetAtlasSource = source as TileSetAtlasSource
		return {"texture":atlas.texture,"region":Rect2(atlas.get_tile_texture_region(layer.get_cell_atlas_coords(cell))),"modulate":layer.modulate,"block_px":block_px}
	return {}


static func _collect_layers(node:Node,result:Array[TileMapLayer]) -> void:
	if node is TileMapLayer and (node as TileMapLayer).tile_set != null: result.append(node)
	for child:Node in node.get_children(): _collect_layers(child,result)


## 公共落地方块小粒子（block_fragments）：取脚下贴图的一个 4×4 小块，弹起后落地淡出。
static func spawn_step_particles(context:Node2D,feet:Vector2,radius:float,rng:RandomNumberGenerator) -> Node2D:
	var sample_info:Dictionary = floor_sample(context,feet)
	if sample_info.is_empty() or sample_info.texture == null: return null
	var region:Rect2 = sample_info.region
	var columns:int = maxi(int(region.size.x) / STEP_PARTICLE_TEXELS,1)
	var rows:int = maxi(int(region.size.y) / STEP_PARTICLE_TEXELS,1)
	var cx:int = rng.randi_range(0,columns - 1)
	var cy:int = rng.randi_range(0,rows - 1)
	var texture:Texture2D = sample_info.texture
	# 每张地面贴图最多缓存 (宽/4)×(高/4) 个小块，公共切块缓存不会随步数增长。
	var key:String = "%d:%d:%d:%d:%d" % [texture.get_instance_id(),int(region.position.x),int(region.position.y),cx,cy]
	var piece:AtlasTexture = _step_piece_cache.get(key)
	if piece == null:
		piece = AtlasTexture.new()
		piece.atlas = texture
		piece.region = Rect2(region.position + Vector2(cx,cy) * STEP_PARTICLE_TEXELS,Vector2.ONE * STEP_PARTICLE_TEXELS)
		piece.filter_clip = true
		_step_piece_cache[key] = piece
	var sprite:Sprite2D = Sprite2D.new()
	sprite.texture = piece
	var tint:Color = sample_info.modulate
	sprite.modulate = Color(tint.r * STEP_PARTICLE_SHADE,tint.g * STEP_PARTICLE_SHADE,tint.b * STEP_PARTICLE_SHADE,tint.a)
	context.add_child(sprite)
	sprite.global_position = feet
	sprite.global_rotation = 0.0
	sprite.global_scale = Vector2.ONE * maxf(float(sample_info.block_px) * STEP_PARTICLE_BLOCK_RATIO,1.0)
	var effect:Node2D = BLOCK_FRAGMENTS.spawn_obstacle(sprite,{},{"seed":rng.randi(),"max_pieces":STEP_PARTICLE_PIECES,
		"scatter_radius":radius * 0.7,"arc_height_min":radius * 0.15,"arc_height_max":radius * 0.45,"flight_min":0.18,"flight_max":0.32,
		"ground_hold":0.12,"fade_time":0.22,"spin_speed":0.0,"z_layer":STEP_PARTICLE_Z})
	sprite.free()
	return effect


## 客户端：收到权威状态。
func apply_network_state(point:Vector2,direction:Vector2,speed_value:float,flags:int) -> void:
	_net_position = point
	_net_age = 0.0
	if direction.length_squared() > 0.0001: heading = direction.normalized()
	speed = speed_value
	_apply_flags(flags)


func _process(delta:float) -> void:
	var owner_horn:Node2D = horn()
	var running:bool = _runtime_active(owner_horn)
	if not _authority and running:
		_net_age = minf(_net_age + delta,0.25)
		var predicted:Vector2 = _net_position + heading * speed * _net_age
		global_position = global_position.lerp(predicted,1.0 - exp(-18.0 * delta))
	if running: _step_tick(owner_horn,delta)
	else: _step_last = global_position
	_update_visual(running)


func _update_visual(running:bool = true) -> void:
	if _sprite == null: return
	var clip:StringName = &"ram" if bowed else &"run"
	if _sprite.animation != clip:
		var keep:int = _sprite.frame
		_sprite.play(clip)
		_sprite.frame = keep % FRAMES.get_frame_count(clip)
	_sprite.speed_scale = clampf(speed / 500.0,0.5,2.2) if running else 0.0
	# 原图朝左；向右跑时镜像。只分左右，不随斜向旋转。
	var flip:bool = heading.x > 0.0
	_sprite.flip_h = flip
	_sprite.rotation = 0.0


func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	var owner_horn:Node2D = horn()
	if owner_horn == null or not _hostile(owner_horn): return {}
	return {"shape":"circle","position":global_position,"velocity":heading * speed,"radius":body_radius,
		"damage":(owner_horn as ball).attack_damage(0.35 + 1.25 * impact_ratio()),"source":owner_horn,"danger_duration":0.1,"kind":"goat_ram"}


## 权威端视角（镜头可见世界矩形）；无镜头/无视口时退回当前地图矩形。
static func view_rect(node:Node) -> Rect2:
	if node == null or not node.is_inside_tree(): return Rect2()
	var viewport:Viewport = node.get_viewport()
	if viewport != null:
		var screen:Rect2 = viewport.get_visible_rect()
		if screen.size.x > 1.0 and screen.size.y > 1.0:
			var inverse:Transform2D = viewport.get_canvas_transform().affine_inverse()
			var result:Rect2 = Rect2(inverse * screen.position,Vector2.ZERO)
			for corner:Vector2 in [Vector2(screen.end.x,screen.position.y),screen.end,Vector2(screen.position.x,screen.end.y)]:
				result = result.expand(inverse * corner)
			return result
	return SubmissionCharacterTools.map_rect(node)
