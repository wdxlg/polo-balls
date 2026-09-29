extends ball

const FORM_CONTROLLER_SCRIPT = preload("res://scripts/characters/变形者_形态控制器.gd")
const MORPH_PREVIEW_SCRIPT = preload("res://scripts/characters/变形者_图片预演.gd")
const CHARACTER_ROOT:String = "res://scenes/characters"
const DISPLAY_NAME:String = "变形者"
const DISPLAY_NAME_META:StringName = &"morph_display_name"
const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")

# ========================================================
# 变形者
#
# 本体等待 -> 扭曲预演 -> 随机形态 -> 持续 ->
# 扭曲预演 -> 恢复本体 -> 再等待。
#
# 预演阶段只处理显示，不提前获得候选角色机制。
# 真正完成变形后才实例化目标角色场景。
# ========================================================

@export_category("变形配置")

# 每一项对应 res://scenes/characters/<分类名>/
@export var transform_category_table:Array[String] = ["动物","人物"]

@export_range(0.1,60.0,0.1) var transform_interval:float = 5.0
@export_range(0.1,60.0,0.1) var transform_duration:float = 6.0
@export var avoid_same_form_twice:bool = true

@export_category("变形动画")
# 整段洗牌总时间。
@export_range(0.05,3.0,0.05) var transform_preview_duration:float = 0.85
# 每一次“前一张 -> 后一张”的扭曲时长。
@export_range(0.03,0.5,0.01) var transform_preview_step:float = 0.11
# Shader 扭曲强度。只改变视觉，不影响碰撞/数值。
@export_range(0.0,0.6,0.01) var transform_distortion_strength:float = 0.22

@export_category("变形图片尺寸")
# 所有预演图片以及真正变形后的角色图片，都以“变形者本体 Image 的最终屏幕尺寸”为基准。
# 保持图片长宽比，只允许其视觉对角线落在这个比例范围内；同时不会超过 max_ratio 对应的宽/高边界。
@export_range(0.1,1.0,0.01) var transform_visual_min_ratio:float = 0.78
@export_range(0.1,1.5,0.01) var transform_visual_max_ratio:float = 1.00

var last_form_scene_path:String = ""
var _transform_wait_started:bool = false
var _preview_running:bool = false
var _manual_transform_in_progress:bool = false
# 这是“原始变形者 Image 真正显示到屏幕后的尺寸”。恢复后继续沿用，不会被当前形态反向污染。
var transform_reference_visual_world_size:Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	set_meta(DISPLAY_NAME_META,DISPLAY_NAME)
	if transform_reference_visual_world_size.length_squared() <= 0.001:
		transform_reference_visual_world_size = MORPH_PREVIEW_SCRIPT.get_host_visual_world_size(self)

	if is_multiplayer_authority():
		call_deferred("_start_transform_wait")


func set_player_control_peer(peer_id:int) -> void:
	var was_controlled:bool = is_player_controlled()
	super.set_player_control_peer(peer_id)
	if was_controlled and not is_player_controlled() and is_inside_tree() and is_in_group("Ball") and is_multiplayer_authority():
		call_deferred("_start_transform_wait")


func controlled_attack_action() -> void:
	if not is_player_controlled() or _manual_transform_in_progress or _preview_running or not _can_continue_transforming():
		return
	_manual_transform_in_progress = true
	_run_manual_transform()


func _run_manual_transform() -> void:
	await _transform_into_random_form()
	_manual_transform_in_progress = false


func _start_transform_wait() -> void:
	if _transform_wait_started or _preview_running or _manual_transform_in_progress or is_player_controlled():
		return
	_transform_wait_started = true

	await get_tree().create_timer(maxf(transform_interval,0.05)).timeout
	_transform_wait_started = false

	if is_player_controlled() or _manual_transform_in_progress or not _can_continue_transforming():
		return

	var transformed:bool = await _transform_into_random_form()
	if not transformed and _can_continue_transforming():
		call_deferred("_start_transform_wait")


func _can_continue_transforming() -> bool:
	if not is_instance_valid(self):
		return false
	if not is_multiplayer_authority():
		return false
	if health <= 0:
		return false
	if state_machine and state_machine.current_state == State.Die:
		return false
	return true


func _transform_into_random_form() -> bool:
	var candidates:Array[String] = _collect_transform_candidates()
	if candidates.is_empty():
		push_warning(
			"变形者没有找到可变换角色。当前分类表: "
			+ str(transform_category_table)
		)
		return false

	candidates.shuffle()

	for target_path:String in candidates:
		var packed := load(target_path) as PackedScene
		if packed == null:
			continue

		var node := packed.instantiate()
		if not node is ball:
			node.free()
			continue

		# 真正换脚本/碰撞之前先播放 shader 扭曲洗牌。
		_play_local_sfx_everywhere("warp_in",global_position,-7.0,1.0,650.0)
		await _play_image_shuffle(candidates,target_path)
		if not _can_continue_transforming():
			node.free()
			return false

		var target:ball = node as ball
		await _replace_self_with_form(target,target_path)
		return true

	return false


func _play_local_sfx_everywhere(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_local_sfx.rpc(key,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_local_sfx(key,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_local_sfx(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	LOCAL_SFX.play(self,key,position_value,volume_db,pitch,max_distance)


func _collect_transform_candidates() -> Array[String]:
	var result:Array[String] = []
	var seen:Dictionary = {}
	var self_path:String = scene_file_path

	for raw_category:String in transform_category_table:
		var category:String = raw_category.strip_edges()
		if category.is_empty():
			continue

		var folder_path:String = CHARACTER_ROOT.path_join(category)
		var dir := DirAccess.open(folder_path)
		if dir == null:
			push_warning("变形者分类不存在或无法读取: " + folder_path)
			continue

		for raw_file_name:String in dir.get_files():
			var file_name:String = raw_file_name
			if file_name.ends_with(".remap"):
				file_name = file_name.trim_suffix(".remap")
			if not file_name.ends_with(".tscn"):
				continue

			var scene_path:String = folder_path.path_join(file_name)
			if scene_path == self_path or seen.has(scene_path):
				continue

			seen[scene_path] = true
			result.append(scene_path)

	if avoid_same_form_twice and result.size() > 1 and not last_form_scene_path.is_empty():
		result.erase(last_form_scene_path)

	return result


func _play_image_shuffle(candidates:Array[String],final_path:String) -> void:
	if transform_preview_duration <= 0.0 or transform_preview_step <= 0.0:
		return
	if image == null or graphics == null:
		return

	_preview_running = true
	await MORPH_PREVIEW_SCRIPT.play_shuffle(
		self,
		candidates,
		final_path,
		transform_preview_duration,
		transform_preview_step,
		transform_reference_visual_world_size,
		transform_visual_min_ratio,
		transform_visual_max_ratio,
		transform_distortion_strength
	)
	_preview_running = false


func _replace_self_with_form(target:ball,target_path:String) -> void:
	var parent := get_parent()
	if parent == null:
		target.free()
		return

	var preserved_defaults:Dictionary = default_properties.duplicate(true)
	var live_state:Dictionary = FORM_CONTROLLER_SCRIPT.capture_live_state(self)

	FORM_CONTROLLER_SCRIPT.apply_base_properties_before_ready(target,preserved_defaults)
	FORM_CONTROLLER_SCRIPT.apply_identity_before_ready(target,live_state,DISPLAY_NAME)

	var controller := FORM_CONTROLLER_SCRIPT.new()
	controller.name = "MorphFormController"
	controller.original_scene_path = scene_file_path
	controller.transform_duration = transform_duration
	controller.transform_preview_duration = transform_preview_duration
	controller.transform_preview_step = transform_preview_step
	controller.transform_distortion_strength = transform_distortion_strength
	controller.visual_min_ratio = transform_visual_min_ratio
	controller.visual_max_ratio = transform_visual_max_ratio
	controller.reference_visual_world_size = transform_reference_visual_world_size
	controller.preserved_default_properties = preserved_defaults.duplicate(true)
	controller.display_name = DISPLAY_NAME
	controller.transform_config = {
		"transform_category_table": transform_category_table.duplicate(),
		"transform_interval": transform_interval,
		"transform_duration": transform_duration,
		"transform_preview_duration": transform_preview_duration,
		"transform_preview_step": transform_preview_step,
		"transform_distortion_strength": transform_distortion_strength,
		"transform_visual_min_ratio": transform_visual_min_ratio,
		"transform_visual_max_ratio": transform_visual_max_ratio,
		"transform_reference_visual_world_size": transform_reference_visual_world_size,
		"avoid_same_form_twice": avoid_same_form_twice,
		"last_form_scene_path": target_path,
	}
	target.add_child(controller)
	# 入树前承接控制者，避免新形态在 _ready 到服务器重绑期间自行使用 AI 招式。
	if is_player_controlled():
		target.set_player_control_peer(player_control_peer_id)

	FORM_CONTROLLER_SCRIPT.deactivate_for_swap(self)
	FORM_CONTROLLER_SCRIPT.cleanup_owned_creatures(self)

	target.name = Game.return_random_name(target)
	parent.add_child(target,true)
	if not target.is_node_ready():
		await target.ready

	if not is_instance_valid(target):
		return

	FORM_CONTROLLER_SCRIPT.apply_live_state_after_ready(
		target,
		live_state,
		preserved_defaults,
		DISPLAY_NAME
	)

	# 真正变形后的角色也强制使用“变形者本体 Image 大小”作为视觉尺寸基准。
	# 这里只缩放显示节点，不改变角色碰撞体、速度、生命等任何机制数值。
	MORPH_PREVIEW_SCRIPT.constrain_host_visual(
		target,
		transform_reference_visual_world_size,
		transform_visual_min_ratio,
		transform_visual_max_ratio
	)

	FORM_CONTROLLER_SCRIPT.rebind_world_references(self,target)
	Game.transfer_character_control_for_replacement(self,target)

	if is_instance_valid(self):
		queue_free()
