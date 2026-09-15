extends Area2D

const ITEM_SPAWN_SHADER:Shader = preload("res://shaders/跑刀仔物资出生闪光.gdshader")
const CRACK_SHADER:Shader = preload("res://shaders/我的世界/下界合金锭裂纹.gdshader")
const RED_QUALITY_COLOR:Color = Color(1.0,0.18,0.14,1.0)
const HAMMER_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/重锤/重锤.png")
const HAMMER_REFERENCE_SPRITE_SCALE:float = 0.095
const BALL_REFERENCE_ROOT_SCALE:float = 0.20

const PLACE_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/下界合金锭/放置01.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/放置02.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/放置03.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/放置04.ogg"),
]
const BREAK_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/下界合金锭/破坏01.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/破坏02.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/破坏03.ogg"),
]
const DESTROY_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/下界合金锭/摧毁01.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/摧毁02.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/摧毁03.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/摧毁04.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/摧毁05.ogg"),
	preload("res://audio/sfx/我的世界/下界合金锭/摧毁06.ogg"),
]

const SFX_PLACE:int = 0
const SFX_BREAK:int = 1
const SFX_DESTROY:int = 2
const DESTROY_PROGRESS_MAX:int = 2

@export_range(0.60,1.10,0.01) var visual_size_vs_hammer:float = 0.95
@export_range(0.2,3.0,0.05) var break_shake_world_strength:float = 1.15
@export_range(0.08,0.35,0.01) var break_shake_duration:float = 0.16
@export_range(4,32,1) var break_particle_count:int = 14
@export_range(0.5,5.0,0.1) var break_particle_min_size:float = 1.2
@export_range(0.5,6.0,0.1) var break_particle_max_size:float = 2.8
@export_range(0.10,2.00,0.05) var enemy_destroy_touch_cooldown:float = 0.55

var _enemy_touch_count:int = 0
var _active_touch_ids:Dictionary = {}
var _next_enemy_destroy_touch_usec:int = 0
var _break_crack_sprite:Sprite2D = null
var _break_shake_tween:Tween = null
var _sprite_rest_position:Vector2 = Vector2.ZERO

@onready var _sprite:Sprite2D = $ItemSprite


func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MinecraftNetheriteIngot")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_fit_visual_to_hammer_size()
	_sprite_rest_position = _sprite.position if _sprite != null else Vector2.ZERO
	_setup_break_crack_visual()
	_setup_spawn_visual()
	# 下界合金锭由竞技场管理器 add_child() 后再写入 global_position；延迟一拍，
	# 让“出现/放置”音效从锭真正的出生位置播放，而不是默认的 (0, 0)。
	call_deferred("_play_spawn_place_sfx")


func _play_spawn_place_sfx() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_play_random_item_sfx_local(SFX_PLACE,global_position)


func _fit_visual_to_hammer_size() -> void:
	if _sprite == null or _sprite.texture == null or HAMMER_TEXTURE == null:
		return
	var tex_size:Vector2 = _sprite.texture.get_size()
	var own_long_edge:float = maxf(tex_size.x,tex_size.y)
	var hammer_size:Vector2 = HAMMER_TEXTURE.get_size()
	# 重锤自身 Sprite 是 0.095，但它还继承 ball.tscn 根节点的 0.20 缩放；
	# 下界合金锭的 Area2D 根节点没有这层 0.20。V82 漏掉了这一层，所以实际被放大了约 5 倍。
	var hammer_world_long_edge:float = maxf(hammer_size.x,hammer_size.y) * HAMMER_REFERENCE_SPRITE_SCALE * BALL_REFERENCE_ROOT_SCALE
	if own_long_edge <= 0.0 or hammer_world_long_edge <= 0.0:
		return
	var target_world_long_edge:float = hammer_world_long_edge * clampf(visual_size_vs_hammer,0.01,2.0)
	_sprite.scale = Vector2.ONE * (target_world_long_edge / own_long_edge)


func _setup_spawn_visual() -> void:
	if _sprite == null:
		return
	var material := ShaderMaterial.new()
	material.shader = ITEM_SPAWN_SHADER
	material.set_shader_parameter("flash_color",RED_QUALITY_COLOR)
	material.set_shader_parameter("flash_amount",1.0)
	_sprite.material = material
	var base_scale:Vector2 = _sprite.scale
	_sprite.scale = base_scale * 0.28
	var pop:Tween = create_tween()
	pop.tween_property(_sprite,"scale",base_scale * 1.38,0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_sprite,"scale",base_scale * 0.90,0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pop.tween_property(_sprite,"scale",base_scale,0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var flash:Tween = create_tween()
	flash.tween_interval(0.055)
	flash.tween_method(Callable(self,"_set_spawn_flash").bind(material),1.0,0.0,0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_spawn_flash(amount:float,material:ShaderMaterial) -> void:
	if material != null:
		material.set_shader_parameter("flash_amount",clampf(amount,0.0,1.0))


func _on_body_entered(body:Node2D) -> void:
	if not is_multiplayer_authority() or not body is ball:
		return
	var actor:ball = body as ball
	if actor.health <= 0:
		return
	var id:int = actor.get_instance_id()
	if _active_touch_ids.has(id):
		return

	if actor.is_in_group("MinecraftDiamondSword") and actor.has_method("receive_netherite_ingot"):
		_active_touch_ids[id] = true
		if bool(actor.call("receive_netherite_ingot")):
			# 钻石剑成功拿走锭时也播放“放置”组音效。播放器挂到 World，
			# 所以锭本体本帧 queue_free() 后声音仍能完整播完。
			_broadcast_item_sfx(SFX_PLACE,global_position)
			queue_free()
		return

	if not _is_enemy_of_any_diamond_sword(actor):
		return
	# V104：只有一次真实“重新碰到”才算一次破坏进度；同一身体必须先离开再进入。
	# 同时所有敌人的破坏进度共享一个短冷却，避免两个敌人在同一帧/极短时间
	# 同时进入时直接把两段进度瞬间吃满。
	_active_touch_ids[id] = true
	var now_usec:int = Time.get_ticks_usec()
	if now_usec < _next_enemy_destroy_touch_usec:
		return
	_next_enemy_destroy_touch_usec = now_usec + int(round(maxf(0.0,enemy_destroy_touch_cooldown) * 1000000.0))
	_enemy_touch_count = mini(DESTROY_PROGRESS_MAX,_enemy_touch_count + 1)
	if _enemy_touch_count >= DESTROY_PROGRESS_MAX:
		# V102：完全摧毁也喷出像素碎屑。粒子节点直接挂到当前场景，
		# 即使本帧把锭本体 queue_free()，碎屑仍会继续完成抛物线。
		_spawn_break_pixel_particles(true)
		_broadcast_item_sfx(SFX_DESTROY,global_position)
		queue_free()
	else:
		# 只有进入“破坏中”而尚未彻底摧毁时才显示裂纹、颤抖和像素碎屑。
		_play_enemy_touch_feedback()
		_broadcast_item_sfx(SFX_BREAK,global_position)


func _on_body_exited(body:Node2D) -> void:
	if body != null:
		_active_touch_ids.erase(body.get_instance_id())


func _is_enemy_of_any_diamond_sword(actor:ball) -> bool:
	var swords:Array[Node] = get_tree().get_nodes_in_group("MinecraftDiamondSword")
	for node:Node in swords:
		if not node is ball or not is_instance_valid(node):
			continue
		var sword:ball = node as ball
		if sword.health <= 0:
			continue
		if sword == actor:
			return false
		if sword.Team == "" or actor.Team == "" or sword.Team != actor.Team:
			return true
	return false


func _play_enemy_touch_feedback() -> void:
	if _sprite == null:
		return
	_update_break_crack_visual(_enemy_touch_count)
	_play_break_shake()
	# 方块碎屑节点/补间放到下一次 idle 调度再创建，避免和裂纹显示、音效、颤抖
	# 全部挤在同一个命中帧里造成瞬时卡顿。视觉上只晚一个调度周期。
	call_deferred("_spawn_break_pixel_particles")


func _setup_break_crack_visual() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	# V102：裂纹改成 CanvasItem Shader 直接在 GPU 上读取下界合金锭原贴图的 alpha。
	# 因此透明像素天然不会画裂纹，也彻底移除首个锭生成时 get_image() + 全图扫描 +
	# ImageTexture.create_from_image() 的一次性 CPU 峰值。
	_break_crack_sprite = Sprite2D.new()
	_break_crack_sprite.name = "MinecraftBreakCracks"
	_break_crack_sprite.centered = _sprite.centered
	_break_crack_sprite.texture = _sprite.texture
	_break_crack_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_break_crack_sprite.z_index = 2
	_break_crack_sprite.visible = false
	var crack_material := ShaderMaterial.new()
	crack_material.shader = CRACK_SHADER
	crack_material.set_shader_parameter("crack_progress",0.0)
	_break_crack_sprite.material = crack_material
	_sprite.add_child(_break_crack_sprite)


func _update_break_crack_visual(progress:int) -> void:
	if _break_crack_sprite == null:
		return
	var safe_progress:int = clampi(progress,0,DESTROY_PROGRESS_MAX)
	_break_crack_sprite.visible = safe_progress > 0
	if _break_crack_sprite.material is ShaderMaterial:
		var material:ShaderMaterial = _break_crack_sprite.material as ShaderMaterial
		material.set_shader_parameter(
			"crack_progress",
			float(safe_progress) / float(maxi(1,DESTROY_PROGRESS_MAX))
		)


func _spawn_break_pixel_particles(destroyed:bool = false) -> void:
	if _sprite == null or _sprite.texture == null:
		return
	if get_tree() == null or get_tree().current_scene == null:
		return

	# V102：不再用 Texture2D.get_image() 把整张纹理读回 CPU。每颗碎屑直接使用
	# 下界合金锭原贴图的 1x1 region，因此颜色就是那一个真实纹理像素；透明像素即使抽中
	# 也只是该颗碎屑不可见，不需要为了筛选它而在首个锭生成时扫描整张图片。
	var texture_size:Vector2 = _sprite.texture.get_size()
	if texture_size.x < 2.0 or texture_size.y < 2.0:
		return
	var base_count:int = maxi(1,break_particle_count)
	var count:int = int(round(float(base_count) * (1.55 if destroyed else 1.0)))
	var min_x:int = clampi(int(floor(texture_size.x * 0.14)),0,maxi(0,int(texture_size.x) - 1))
	var max_x:int = clampi(int(ceil(texture_size.x * 0.86)),min_x,maxi(min_x,int(texture_size.x) - 1))
	var min_y:int = clampi(int(floor(texture_size.y * 0.18)),0,maxi(0,int(texture_size.y) - 1))
	var max_y:int = clampi(int(ceil(texture_size.y * 0.82)),min_y,maxi(min_y,int(texture_size.y) - 1))

	for index:int in range(count):
		var px:int = randi_range(min_x,max_x)
		var py:int = randi_range(min_y,max_y)
		var local_pixel:Vector2 = Vector2(float(px) + 0.5,float(py) + 0.5) - texture_size * 0.5
		var start_world:Vector2 = _sprite.to_global(local_pixel)
		var size:float = randf_range(
			minf(break_particle_min_size,break_particle_max_size),
			maxf(break_particle_min_size,break_particle_max_size)
		)

		var chip := Sprite2D.new()
		chip.name = "NetheritePixelChip"
		chip.texture = _sprite.texture
		chip.region_enabled = true
		chip.region_rect = Rect2(Vector2(float(px),float(py)),Vector2.ONE)
		chip.centered = true
		chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		chip.scale = Vector2.ONE * size
		chip.rotation = 0.0
		chip.z_index = 10
		get_tree().current_scene.add_child(chip,true)
		chip.global_position = start_world

		# 保持正向、不旋转。横向只在锭周围小范围散开，纵向先升高再落出屏幕。
		var horizontal_sign:float = -1.0 if randf() < 0.5 else 1.0
		var horizontal_distance:float = horizontal_sign * randf_range(20.0,58.0)
		var apex_height:float = randf_range(18.0,46.0)
		var fall_distance:float = randf_range(380.0,560.0)
		var rise_time:float = randf_range(0.16,0.27)
		var fall_time:float = randf_range(0.62,0.92)
		var total_time:float = rise_time + fall_time
		var x_tween:Tween = chip.create_tween()
		x_tween.tween_property(chip,"global_position:x",start_world.x + horizontal_distance,total_time).set_trans(Tween.TRANS_LINEAR)
		var y_tween:Tween = chip.create_tween()
		y_tween.tween_property(chip,"global_position:y",start_world.y - apex_height,rise_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		y_tween.tween_property(chip,"global_position:y",start_world.y + fall_distance,fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		y_tween.tween_callback(Callable(chip,"queue_free"))


func _play_break_shake() -> void:
	if _sprite == null:
		return
	if _break_shake_tween != null and _break_shake_tween.is_valid():
		_break_shake_tween.kill()
	_sprite.position = _sprite_rest_position
	_break_shake_tween = create_tween()
	var step_count:int = 7
	var step_time:float = maxf(0.01,break_shake_duration / float(step_count + 1))
	for index:int in range(step_count):
		var remain:float = 1.0 - float(index) / float(step_count)
		var strength:float = break_shake_world_strength * remain
		var offset := Vector2(randf_range(-strength,strength),randf_range(-strength,strength))
		_break_shake_tween.tween_property(_sprite,"position",_sprite_rest_position + offset,step_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_break_shake_tween.tween_property(_sprite,"position",_sprite_rest_position,step_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _streams_for_kind(kind:int) -> Array[AudioStream]:
	match kind:
		SFX_PLACE:
			return PLACE_SFX
		SFX_BREAK:
			return BREAK_SFX
		SFX_DESTROY:
			return DESTROY_SFX
	return []


func _play_random_item_sfx_local(kind:int,world_position:Vector2) -> void:
	var streams:Array[AudioStream] = _streams_for_kind(kind)
	if streams.is_empty():
		return
	_play_item_sfx_local(kind,randi_range(0,streams.size() - 1),world_position)


func _broadcast_item_sfx(kind:int,world_position:Vector2) -> void:
	var streams:Array[AudioStream] = _streams_for_kind(kind)
	if streams.is_empty():
		return
	var index:int = randi_range(0,streams.size() - 1)
	_play_item_sfx_local(kind,index,world_position)
	if multiplayer.has_multiplayer_peer():
		_sync_item_sfx.rpc(kind,index,world_position)


@rpc("authority","call_remote","reliable")
func _sync_item_sfx(kind:int,index:int,world_position:Vector2) -> void:
	_play_item_sfx_local(kind,index,world_position)


func _play_item_sfx_local(kind:int,index:int,world_position:Vector2) -> void:
	var streams:Array[AudioStream] = _streams_for_kind(kind)
	if index < 0 or index >= streams.size():
		return
	var stream:AudioStream = streams[index]
	if stream == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MinecraftNetheriteIngotSfx"
	player.stream = stream
	player.volume_db = 0.0
	player.max_distance = 1500.0
	player.attenuation = 0.68
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	# 音效节点脱离锭本体，避免拾取/摧毁时锭 queue_free() 把声音截断。
	get_tree().current_scene.add_child(player,true)
	player.top_level = true
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
