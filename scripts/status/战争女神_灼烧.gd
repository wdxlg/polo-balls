extends Node2D

var target:ball = null
var source:ball = null
var remaining:float = 0.0
var tick_interval:float = 0.5
var tick_damage:float = 5.0
var _tick_left:float = 0.0
var _target_visual:CanvasItem = null
var _base_rgb:Color = Color.WHITE
var _minecraft_burn_visual:AnimatedSprite2D = null

const BURN_TINT := Color(1.0, 0.78, 0.52, 1.0)
const MINECRAFT_BURN_FRAMES:SpriteFrames = preload("res://particles/mc_burning_fire.tres")
const MINECRAFT_BURN_ANIMATION:StringName = &"burn"
const MINECRAFT_TAG:String = "我的世界"
const MINECRAFT_BURN_FRAME_SIZE := Vector2(16.0,16.0)
const MINECRAFT_BURN_HEIGHT_RATIO:float = 197.0/151.0
const MINECRAFT_BURN_WIDTH_RATIO:float = 1.18
const MINECRAFT_BURN_MIN_WIDTH:float = 44.0
const MINECRAFT_BURN_MAX_WIDTH:float = 132.0


func setup(new_target:ball,new_source:ball,duration:float,new_tick_interval:float,new_tick_damage:float) -> void:
	target = new_target
	source = new_source
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		queue_free()
		return
	remaining = maxf(duration,0.1)
	tick_interval = maxf(new_tick_interval,0.05)
	tick_damage = maxf(new_tick_damage,0.0)
	_tick_left = tick_interval
	_capture_target_visual()
	_apply_burn_tint()
	_sync_minecraft_burn_visual()


func refresh(new_source:ball,duration:float,new_tick_damage:float) -> void:
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		queue_free()
		return
	if new_source != null and is_instance_valid(new_source):
		source = new_source
	remaining = maxf(duration,0.1)
	if new_tick_damage >= 0.0:
		tick_damage = new_tick_damage
	_apply_burn_tint()
	_sync_minecraft_burn_visual()


func _capture_target_visual() -> void:
	_target_visual = null
	if target == null or not is_instance_valid(target):
		return
	if target.image is CanvasItem:
		_target_visual = target.image as CanvasItem
		var c:Color = _target_visual.self_modulate
		_base_rgb = Color(c.r,c.g,c.b,1.0)


func _apply_burn_tint() -> void:
	if _target_visual == null or not is_instance_valid(_target_visual):
		_capture_target_visual()
	if _target_visual == null or not is_instance_valid(_target_visual):
		return
	# 只把人物本身染成偏橙色；保留角色当前 Alpha（例如棍母的生命透明度）。
	var alpha:float = _target_visual.self_modulate.a
	_target_visual.self_modulate = Color(BURN_TINT.r,BURN_TINT.g,BURN_TINT.b,alpha)


func _restore_target_tint() -> void:
	if _target_visual == null or not is_instance_valid(_target_visual):
		return
	var alpha:float = _target_visual.self_modulate.a
	_target_visual.self_modulate = Color(_base_rgb.r,_base_rgb.g,_base_rgb.b,alpha)


func _source_is_minecraft() -> bool:
	return (
		source != null
		and is_instance_valid(source)
		and source.Type_Tags.has(MINECRAFT_TAG)
	)


func _sync_minecraft_burn_visual() -> void:
	if not _source_is_minecraft():
		if _minecraft_burn_visual != null and is_instance_valid(_minecraft_burn_visual):
			_minecraft_burn_visual.queue_free()
		_minecraft_burn_visual = null
		return
	if _minecraft_burn_visual == null or not is_instance_valid(_minecraft_burn_visual):
		_minecraft_burn_visual = AnimatedSprite2D.new()
		_minecraft_burn_visual.name = "MinecraftBurnLoop"
		_minecraft_burn_visual.sprite_frames = MINECRAFT_BURN_FRAMES
		_minecraft_burn_visual.animation = MINECRAFT_BURN_ANIMATION
		_minecraft_burn_visual.centered = true
		_minecraft_burn_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_minecraft_burn_visual.z_index = 7
		add_child(_minecraft_burn_visual)
		_minecraft_burn_visual.play(MINECRAFT_BURN_ANIMATION)
	_update_minecraft_burn_visual_layout()


func _target_local_bounds() -> Rect2:
	if target != null and is_instance_valid(target) and target.has_method("_character_ground_shadow_bounds"):
		var bounds:Rect2 = target.call("_character_ground_shadow_bounds")
		if bounds.size.x > 0.001 and bounds.size.y > 0.001:
			return bounds
	return Rect2(Vector2(-40.0,-50.0),Vector2(80.0,100.0))


func _update_minecraft_burn_visual_layout() -> void:
	if _minecraft_burn_visual == null or not is_instance_valid(_minecraft_burn_visual):
		return
	if target == null or not is_instance_valid(target):
		return
	var bounds:Rect2 = _target_local_bounds()
	var foot_center := Vector2(bounds.position.x + bounds.size.x * 0.5,bounds.end.y)
	var desired_width:float = clampf(
		bounds.size.x * MINECRAFT_BURN_WIDTH_RATIO,
		MINECRAFT_BURN_MIN_WIDTH,
		MINECRAFT_BURN_MAX_WIDTH
	)
	var desired_height:float = desired_width*MINECRAFT_BURN_HEIGHT_RATIO
	_minecraft_burn_visual.scale = Vector2(desired_width,desired_height)/MINECRAFT_BURN_FRAME_SIZE
	# AnimatedSprite2D 默认围绕中心绘制；把中心上移半个动画高度，
	# 就能让动画底部中心与目标底部中心严格重合。
	_minecraft_burn_visual.position = foot_center + Vector2(
		0.0,
		-desired_height * 0.5
	)


func _process(_delta:float) -> void:
	if target != null and is_instance_valid(target) and not target.can_receive_fire_status():
		queue_free()
		return
	if target != null and is_instance_valid(target):
		global_position = target.global_position
	_apply_burn_tint()
	_update_minecraft_burn_visual_layout()


func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		queue_free()
		return
	if not target.can_receive_fire_status():
		queue_free()
		return
	if source == null or not is_instance_valid(source) or source.health <= 0:
		queue_free()
		return
	if not source.is_multiplayer_authority():
		return
	if not source.is_combat_runtime_active():
		return
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
		return
	_tick_left -= delta
	while _tick_left <= 0.0:
		_tick_left += tick_interval
		var outgoing:float = source.effective_outgoing_damage(tick_damage)
		if outgoing > 0.0:
			var applied:bool = target.receive_fire_positional_damage(outgoing,target.global_position,false,source,{"focus_position":target.global_position})
			if applied and source.has_method("play_war_burn_tick_sfx"):
				source.call("play_war_burn_tick_sfx",target.global_position)


func _exit_tree() -> void:
	_restore_target_tint()
