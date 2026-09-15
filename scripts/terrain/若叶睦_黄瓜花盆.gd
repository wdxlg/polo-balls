extends Node2D

# V162 若叶睦黄瓜盆栽：玩法数据留在根节点，所有图片位置/缩放都留在 tscn 的
# VisualRoot_可手动调整 及其子 Sprite2D 中，脚本不覆盖这些 Transform。
# 成长阶段由 Shader 连续揭示/交叠，不允许空盆->幼苗->藤蔓整张硬切。

const GROW_SHADER:Shader = preload("res://shaders/若叶睦_盆栽生长.gdshader")
const POT_SHATTER_SFX:AudioStream = preload("res://audio/characters/若叶睦/碎裂.mp3")

var owner_ref:WeakRef = null
var owner_instance_id:int = 0
var Team:String = ""

var interaction_radius:float = 34.0
var vine_growth_time:float = 7.0
var cucumber_growth_time:float = 10.0
var max_cucumbers:int = 3
var watering_growth_multiplier:float = 2.4
var instant_heal_ratio:float = 0.075
var hot_heal_ratio:float = 0.12
var hot_duration:float = 4.0
var eat_guard:float = 0.9
var wither_after_unwatered:float = 10.0
var wither_cucumber_interval:float = 0.40
var wither_disappear_delay:float = 0.65

var vine_progress:float = 0.0
var cucumber_progress:float = 0.0
var cucumber_count:int = 0
var _eat_guard_left:float = 0.0
var _watered_last_frame:bool = false
var _cucumber_visual_reveal:Array[float] = []
var _fully_grown_dry_elapsed:float = 0.0
var _withered:bool = false
var _wither_visual_progress:float = 0.0
var _wither_cucumber_elapsed:float = 0.0
var _withered_empty_elapsed:float = 0.0
var _shatter_started:bool = false

@onready var _empty_sprite:Sprite2D = get_node_or_null("VisualRoot_可手动调整/空盆土壤") as Sprite2D
@onready var _seedling_sprite:Sprite2D = get_node_or_null("VisualRoot_可手动调整/刚种下幼苗") as Sprite2D
@onready var _vine_sprite:Sprite2D = get_node_or_null("VisualRoot_可手动调整/茂盛藤蔓") as Sprite2D
@onready var _withered_sprite:Sprite2D = get_node_or_null("VisualRoot_可手动调整/枯萎藤蔓") as Sprite2D
@onready var _cucumber_root:Node2D = get_node_or_null("VisualRoot_可手动调整/黄瓜挂点_可手动调整") as Node2D

func setup(owner_node:Node, config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_node)
	owner_instance_id = owner_node.get_instance_id() if owner_node != null else 0
	Team = str(owner_node.get("Team")) if owner_node != null else ""
	interaction_radius = float(config.get("interaction_radius", interaction_radius))
	vine_growth_time = float(config.get("vine_growth_time", vine_growth_time))
	cucumber_growth_time = float(config.get("cucumber_growth_time", cucumber_growth_time))
	max_cucumbers = maxi(int(config.get("max_cucumbers", max_cucumbers)), 1)
	watering_growth_multiplier = maxf(float(config.get("watering_growth_multiplier", watering_growth_multiplier)), 1.0)
	instant_heal_ratio = maxf(float(config.get("instant_heal_ratio", instant_heal_ratio)), 0.0)
	hot_heal_ratio = maxf(float(config.get("hot_heal_ratio", hot_heal_ratio)), 0.0)
	hot_duration = maxf(float(config.get("hot_duration", hot_duration)), 0.05)
	eat_guard = maxf(float(config.get("eat_guard", eat_guard)), 0.05)
	wither_after_unwatered = maxf(float(config.get("wither_after_unwatered", wither_after_unwatered)), 0.1)
	wither_cucumber_interval = maxf(float(config.get("wither_cucumber_interval", wither_cucumber_interval)), 0.05)
	wither_disappear_delay = maxf(float(config.get("wither_disappear_delay", wither_disappear_delay)), 0.05)

func _ready() -> void:
	add_to_group("MutsumiCucumberPot")
	z_as_relative = false
	z_index = 2
	_prepare_growth_sprite(_empty_sprite)
	_prepare_growth_sprite(_seedling_sprite)
	_prepare_growth_sprite(_vine_sprite)
	if _withered_sprite != null:
		_withered_sprite.visible = false
		_withered_sprite.modulate.a = 0.0
	var slots:Array[Sprite2D] = _cucumber_sprites()
	_cucumber_visual_reveal.resize(slots.size())
	for i:int in range(slots.size()):
		_cucumber_visual_reveal[i] = 0.0
		_prepare_growth_sprite(slots[i])
		slots[i].visible = false
	_update_growth_visuals(0.0)

func _prepare_growth_sprite(sprite:Sprite2D) -> void:
	if sprite == null:
		return
	var material:=ShaderMaterial.new()
	material.shader = GROW_SHADER
	sprite.material = material

func _set_growth_shader(sprite:Sprite2D, reveal:float, opacity:float) -> void:
	if sprite == null:
		return
	sprite.visible = opacity > 0.003 and reveal > 0.003
	if sprite.material is ShaderMaterial:
		var mat:=sprite.material as ShaderMaterial
		mat.set_shader_parameter("reveal",clampf(reveal,0.0,1.0))
		mat.set_shader_parameter("opacity",clampf(opacity,0.0,1.0))

func _smooth01(value:float) -> float:
	var t:float = clampf(value,0.0,1.0)
	return t * t * (3.0 - 2.0 * t)

func _range01(value:float, from_value:float, to_value:float) -> float:
	return _smooth01((value - from_value) / maxf(to_value - from_value,0.0001))

func _cucumber_sprites() -> Array[Sprite2D]:
	var result:Array[Sprite2D] = []
	if _cucumber_root == null:
		return result
	for child:Node in _cucumber_root.get_children():
		if child is Sprite2D:
			result.append(child as Sprite2D)
	return result

func _update_growth_visuals(delta:float) -> void:
	# 三阶段始终柔和交叠。新阶段用 Shader 从下向上、带噪声边缘逐步长出来，
	# 旧阶段再渐隐，所以不会出现整张 PNG 瞬间替换。
	var p:float = clampf(vine_progress,0.0,1.0)
	var empty_fade:float = 1.0 - _range01(p,0.12,0.44)
	var seed_reveal:float = _range01(p,0.03,0.40)
	var seed_fade_in:float = _range01(p,0.06,0.28)
	var seed_fade_out:float = 1.0 - _range01(p,0.58,0.84)
	var vine_reveal:float = _range01(p,0.40,1.0)
	var vine_fade_in:float = _range01(p,0.46,0.74)
	if _withered:
		_wither_visual_progress = move_toward(_wither_visual_progress,1.0,maxf(delta,0.0) * 3.5)
	var healthy_alpha:float = 1.0 - _wither_visual_progress
	_set_growth_shader(_empty_sprite,1.0,empty_fade * healthy_alpha)
	_set_growth_shader(_seedling_sprite,seed_reveal,seed_fade_in * seed_fade_out * healthy_alpha)
	_set_growth_shader(_vine_sprite,vine_reveal,vine_fade_in * healthy_alpha)
	if _withered_sprite != null:
		_withered_sprite.visible = _wither_visual_progress > 0.003
		_withered_sprite.modulate.a = clampf(_wither_visual_progress,0.0,1.0)

	var slots:Array[Sprite2D] = _cucumber_sprites()
	if _cucumber_visual_reveal.size() != slots.size():
		_cucumber_visual_reveal.resize(slots.size())
	var growing_fraction:float = 0.0
	if not _withered and vine_progress >= 1.0 and cucumber_count < max_cucumbers:
		growing_fraction = clampf(cucumber_progress / maxf(cucumber_growth_time,0.05),0.0,1.0)
	for i:int in range(slots.size()):
		var desired:float = 0.0
		if i < mini(cucumber_count,max_cucumbers):
			desired = 1.0
		elif i == cucumber_count and i < max_cucumbers:
			# 下一根黄瓜在本轮生长后半段就开始从藤蔓上逐步显形。
			desired = _range01(growing_fraction,0.42,1.0)
		var speed:float = 3.2 if desired > _cucumber_visual_reveal[i] else 5.8
		_cucumber_visual_reveal[i] = move_toward(_cucumber_visual_reveal[i],desired,maxf(delta,0.0) * speed)
		_set_growth_shader(slots[i],_cucumber_visual_reveal[i],clampf(_cucumber_visual_reveal[i] * 1.18,0.0,1.0))

func _begin_wither() -> void:
	if _withered:
		return
	_withered = true
	_fully_grown_dry_elapsed = 0.0
	_wither_cucumber_elapsed = 0.0
	_withered_empty_elapsed = 0.0
	cucumber_progress = 0.0


func _update_wither(delta:float) -> void:
	if not _withered:
		return
	if cucumber_count > 0:
		_wither_cucumber_elapsed += delta
		while _wither_cucumber_elapsed >= maxf(wither_cucumber_interval,0.05) and cucumber_count > 0:
			_wither_cucumber_elapsed -= maxf(wither_cucumber_interval,0.05)
			cucumber_count = maxi(cucumber_count - 1,0)
		if cucumber_count > 0:
			return
		_withered_empty_elapsed = 0.0
	_withered_empty_elapsed += delta
	if _withered_empty_elapsed >= maxf(wither_disappear_delay,0.05):
		_begin_shatter_and_disappear()


func _begin_shatter_and_disappear() -> void:
	if _shatter_started:
		return
	_shatter_started = true
	set_physics_process(false)
	_play_shatter_sound_world()
	var source:Sprite2D = _withered_sprite if _withered_sprite != null else _vine_sprite
	var scene_root:Node = get_tree().current_scene
	if source == null or source.texture == null or scene_root == null:
		queue_free()
		return
	var tex_size:Vector2 = source.texture.get_size()
	var columns:int = 3
	var rows:int = 2
	var piece_w:float = tex_size.x / float(columns)
	var piece_h:float = tex_size.y / float(rows)
	for row:int in range(rows):
		for col:int in range(columns):
			var piece:=Sprite2D.new()
			piece.name = "PotShatterPiece"
			piece.texture = source.texture
			piece.region_enabled = true
			piece.region_rect = Rect2(col * piece_w,row * piece_h,piece_w,piece_h)
			piece.centered = true
			piece.z_index = 30
			scene_root.add_child(piece)
			var local_center:=Vector2((float(col)+0.5)*piece_w - tex_size.x*0.5,(float(row)+0.5)*piece_h - tex_size.y*0.5)
			piece.global_position = source.to_global(local_center)
			piece.global_rotation = source.global_rotation
			piece.global_scale = source.global_scale
			var lateral:float = (float(col) - 1.0) * randf_range(42.0,72.0) + randf_range(-18.0,18.0)
			var rise:float = randf_range(62.0,105.0)
			var fall:float = randf_range(260.0,380.0)
			var up_time:float = randf_range(0.24,0.38)
			var down_time:float = randf_range(0.70,0.96)
			var start_pos:Vector2 = piece.global_position
			var peak:=start_pos + Vector2(lateral * 0.42,-rise)
			var end:=peak + Vector2(lateral,fall)
			var tween:=piece.create_tween()
			tween.tween_property(piece,"global_position",peak,up_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(piece,"rotation",piece.rotation + randf_range(-1.3,1.3),up_time)
			tween.tween_property(piece,"global_position",end,down_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(piece,"rotation",piece.rotation + randf_range(-2.8,2.8),down_time)
			tween.parallel().tween_property(piece,"modulate:a",0.0,down_time).set_delay(down_time * 0.55)
			tween.finished.connect(piece.queue_free,CONNECT_ONE_SHOT)
	var visual_root:Node = get_node_or_null("VisualRoot_可手动调整")
	if visual_root is CanvasItem:
		(visual_root as CanvasItem).visible = false
	var cleanup:=create_tween()
	cleanup.tween_interval(1.45)
	cleanup.tween_callback(queue_free)

func _play_shatter_sound_world() -> void:
	if POT_SHATTER_SFX == null or not is_inside_tree():
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "WakabaPotShatterSFX"
	player.stream = POT_SHATTER_SFX
	player.volume_db = 2.0
	player.max_distance = 900.0
	player.attenuation = 0.55
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	scene_root.add_child(player)
	player.global_position = global_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()

func is_owned_by(owner_node:Node) -> bool:
	return owner_node != null and is_instance_valid(owner_node) and owner_node.get_instance_id() == owner_instance_id

func _owner() -> Node:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is Node and is_instance_valid(raw):
		return raw as Node
	return null

func _physics_process(delta:float) -> void:
	var owner_node:Node = _owner()
	if owner_node == null:
		queue_free()
		return
	if owner_node.get("health") != null and int(owner_node.get("health")) <= 0:
		queue_free()
		return

	_eat_guard_left = maxf(_eat_guard_left - delta, 0.0)
	var touching:bool = false
	if owner_node is Node2D:
		touching = global_position.distance_to((owner_node as Node2D).global_position) <= maxf(interaction_radius, 1.0)
	var is_mutsumi:bool = owner_node.has_method("is_mutsumi_personality") and bool(owner_node.call("is_mutsumi_personality"))
	var watering:bool = touching and is_mutsumi and not _withered
	# V172：浇水依旧只属于睦；吃黄瓜不再由花盆检查人格。
	# 花盆只负责 ownership / 距离 / 黄瓜 / 枯萎 / guard，实际食用由角色 authority 主动调用。
	var growth_scale:float = watering_growth_multiplier if watering else 1.0

	if not _withered:
		if vine_progress < 1.0:
			vine_progress = minf(vine_progress + delta * growth_scale / maxf(vine_growth_time, 0.05), 1.0)
		else:
			if cucumber_count < max_cucumbers:
				cucumber_progress += delta * growth_scale
				while cucumber_progress >= maxf(cucumber_growth_time, 0.05) and cucumber_count < max_cucumbers:
					cucumber_progress -= maxf(cucumber_growth_time, 0.05)
					cucumber_count += 1

		# V174：“完全成熟”按用户定义为藤蔓已经长到“可以开始结黄瓜”的阶段。
		# 因此只看 vine_progress，不再要求黄瓜数量达到上限；成熟后只要持续缺水就会进入枯萎计时。
		var fully_grown:bool = vine_progress >= 0.999
		if fully_grown:
			if watering:
				_fully_grown_dry_elapsed = 0.0
			else:
				_fully_grown_dry_elapsed += delta
				if _fully_grown_dry_elapsed >= maxf(wither_after_unwatered,0.1):
					_begin_wither()
		else:
			_fully_grown_dry_elapsed = 0.0
	else:
		_update_wither(delta)

	_watered_last_frame = watering
	_update_growth_visuals(delta)


func try_consume_cucumber_by(owner_node:Node) -> bool:
	# V172：若叶睦 / 墨提斯共用这一条明确的“拥有者主动食用”入口。
	# 不再询问人格，避免墨提斯状态在花盆反向检测中漏掉。
	if _withered or cucumber_count <= 0 or _eat_guard_left > 0.0:
		return false
	if owner_node == null or not is_instance_valid(owner_node) or not is_owned_by(owner_node):
		return false
	if not owner_node is Node2D:
		return false
	if global_position.distance_to((owner_node as Node2D).global_position) > maxf(interaction_radius,1.0):
		return false
	if not owner_node.has_method("consume_cucumber_from_pot"):
		return false
	var consumed:bool = bool(owner_node.call(
		"consume_cucumber_from_pot",
		instant_heal_ratio,
		hot_heal_ratio,
		hot_duration
	))
	if not consumed:
		return false
	cucumber_count = maxi(cucumber_count - 1,0)
	_eat_guard_left = eat_guard
	# V174：吃掉黄瓜不会让藤蔓“退回未成熟”；成熟后的缺水计时只由是否正在浇水决定。
	return true
