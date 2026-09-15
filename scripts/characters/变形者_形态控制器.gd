extends Node

# 临时形态控制器：目标角色负责机制，本控制器只负责计时、恢复本体、
# 以及恢复前的 shader 扭曲预演与最终视觉尺寸限制。

const DISPLAY_NAME_META:StringName = &"morph_display_name"
const BATTLE_SETUP_META:StringName = &"battle_setup_id"
const CHARACTER_ROOT:String = "res://scenes/characters"
const MORPH_PREVIEW_SCRIPT = preload("res://scripts/characters/变形者_图片预演.gd")

var original_scene_path:String = ""
var transform_duration:float = 6.0
var transform_preview_duration:float = 0.85
var transform_preview_step:float = 0.11
var transform_distortion_strength:float = 0.22
var visual_min_ratio:float = 0.78
var visual_max_ratio:float = 1.0
var reference_visual_world_size:Vector2 = Vector2.ZERO
var preserved_default_properties:Dictionary = {}
var transform_config:Dictionary = {}
var display_name:String = "变形者"


func _ready() -> void:
	call_deferred("_start_form_timer")


func _start_form_timer() -> void:
	var host := get_parent()
	if not host is ball:
		queue_free()
		return

	var form:ball = host as ball
	if not form.is_multiplayer_authority():
		return

	await get_tree().create_timer(maxf(transform_duration,0.05)).timeout

	if not _form_can_restore(form):
		return

	await _restore_original(form)


func _form_can_restore(form:ball) -> bool:
	if not is_instance_valid(form):
		return false
	if form.health <= 0:
		return false
	if form.state_machine and form.state_machine.current_state == ball.State.Die:
		return false
	return true


func _restore_original(form:ball) -> void:
	if original_scene_path.is_empty():
		push_warning("变形者无法恢复：original_scene_path 为空")
		return

	# 恢复前先用当前形态的图片扭曲过渡到候选图，最后扭曲成变形者本体。
	var preview_paths:Array[String] = _collect_preview_scene_paths()
	await _play_image_shuffle(form,preview_paths,original_scene_path)
	if not _form_can_restore(form):
		return

	var packed := load(original_scene_path) as PackedScene
	if packed == null:
		push_warning("变形者无法恢复，场景加载失败: " + original_scene_path)
		return

	var original_node := packed.instantiate()
	if not original_node is ball:
		push_warning("变形者原始场景根节点不是 ball: " + original_scene_path)
		original_node.free()
		return

	var restored:ball = original_node as ball
	var live_state:Dictionary = capture_live_state(form)

	_apply_transform_config_before_ready(restored,transform_config)
	apply_base_properties_before_ready(restored,preserved_default_properties)
	apply_identity_before_ready(restored,live_state,display_name)

	var parent := form.get_parent()
	if parent == null:
		restored.free()
		return

	deactivate_for_swap(form)
	cleanup_owned_creatures(form)

	restored.name = Game.return_random_name(restored)
	parent.add_child(restored,true)
	if not restored.is_node_ready():
		await restored.ready

	if not is_instance_valid(restored):
		return

	apply_live_state_after_ready(
		restored,
		live_state,
		preserved_default_properties,
		display_name
	)

	MORPH_PREVIEW_SCRIPT.constrain_host_visual(
		restored,
		reference_visual_world_size,
		visual_min_ratio,
		visual_max_ratio
	)

	rebind_world_references(form,restored)

	if is_instance_valid(form):
		form.queue_free()


func _collect_preview_scene_paths() -> Array[String]:
	var result:Array[String] = []
	var seen:Dictionary = {}
	var categories = transform_config.get("transform_category_table",[])

	if categories is Array:
		for raw_category in categories:
			var category:String = str(raw_category).strip_edges()
			if category.is_empty():
				continue

			var folder_path:String = CHARACTER_ROOT.path_join(category)
			var dir := DirAccess.open(folder_path)
			if dir == null:
				continue

			for raw_file_name:String in dir.get_files():
				var file_name:String = raw_file_name
				if file_name.ends_with(".remap"):
					file_name = file_name.trim_suffix(".remap")
				if not file_name.ends_with(".tscn"):
					continue

				var scene_path:String = folder_path.path_join(file_name)
				if seen.has(scene_path):
					continue
				seen[scene_path] = true
				result.append(scene_path)

	if not original_scene_path.is_empty() and not seen.has(original_scene_path):
		result.append(original_scene_path)

	return result


func _play_image_shuffle(
	form:ball,
	candidates:Array[String],
	final_path:String
) -> void:
	await MORPH_PREVIEW_SCRIPT.play_shuffle(
		form,
		candidates,
		final_path,
		transform_preview_duration,
		transform_preview_step,
		reference_visual_world_size,
		visual_min_ratio,
		visual_max_ratio,
		transform_distortion_strength
	)


static func capture_live_state(source:ball) -> Dictionary:
	var state:Dictionary = {
		"global_position": source.global_position,
		"direction": source.direction,
		"Team": source.Team,
		"health": source.health,
		"block": source.block,
		"energy": source.energy,
		"Buff_Dic": source.Buff_Dic.duplicate(true),
		"Target_Enemy": source.Target_Enemy,
		"Nearest_Enemy": source.Nearest_Enemy,
		"Master": source.Master,
		"Master_name": source.Master_name,
		# 变形只改变视觉与角色机制，不改变“变形者这颗球”的物理外壳和脚步声。
		"Collide_Audio_Node": source.Collide_Audio_Node,
		"Collide_Audio": source.Collide_Audio,
		"collision_shell": _capture_collision_shell(source),
		"last_state_dis": {},
	}

	if source.state_machine:
		state["last_state_dis"] = source.state_machine.last_state_dis.duplicate(true)

	if source.has_meta(BATTLE_SETUP_META):
		state["battle_setup_id"] = source.get_meta(BATTLE_SETUP_META)

	return state


static func apply_base_properties_before_ready(
	target:ball,
	base_properties:Dictionary
) -> void:
	for property_name in base_properties:
		target.set(str(property_name),base_properties[property_name])


static func apply_identity_before_ready(
	target:ball,
	live_state:Dictionary,
	display_name:String
) -> void:
	target.Team = str(live_state.get("Team",target.Team))
	target.direction = live_state.get("direction",Vector2.ZERO)
	target.Master = live_state.get("Master",null)
	target.Master_name = str(live_state.get("Master_name",""))
	target.Collide_Audio_Node = str(live_state.get("Collide_Audio_Node",target.Collide_Audio_Node))
	target.Collide_Audio = str(live_state.get("Collide_Audio",target.Collide_Audio))
	target.set_meta(DISPLAY_NAME_META,display_name)

	if live_state.has("battle_setup_id"):
		target.set_meta(BATTLE_SETUP_META,live_state["battle_setup_id"])


static func apply_live_state_after_ready(
	target:ball,
	live_state:Dictionary,
	base_properties:Dictionary,
	display_name:String
) -> void:
	target.default_properties = base_properties.duplicate(true)

	for property_name in base_properties:
		target.set(str(property_name),base_properties[property_name])

	target.global_position = live_state.get("global_position",target.global_position)
	target.direction = live_state.get("direction",target.direction)
	target.Team = str(live_state.get("Team",target.Team))
	target.Target_Enemy = live_state.get("Target_Enemy",null)
	target.Nearest_Enemy = live_state.get("Nearest_Enemy",null)
	target.Master = live_state.get("Master",null)
	target.Master_name = str(live_state.get("Master_name",target.Master_name))
	target.Collide_Audio_Node = str(live_state.get("Collide_Audio_Node",target.Collide_Audio_Node))
	target.Collide_Audio = str(live_state.get("Collide_Audio",target.Collide_Audio))
	target.set_meta(DISPLAY_NAME_META,display_name)

	# 目标场景在 _ready() 中已经初始化过自己的 CollisionShape2D。这里再覆盖一次，
	# 保证变形后主体碰撞、Hitbox、Hurtbox 的形状和 Transform 都仍是变形前那一套。
	# 同时刷新 ball.defualt_collision，避免下一次碰撞挤压 Tween 又把它恢复成目标角色的尺寸。
	_apply_collision_shell(target,live_state.get("collision_shell",{}))

	if live_state.has("battle_setup_id"):
		target.set_meta(BATTLE_SETUP_META,live_state["battle_setup_id"])

	target.Buff_Dic = live_state.get("Buff_Dic",{}).duplicate(true)

	# 形态切换不是战斗伤害。同步资源时临时关闭浮动伤害/回血文字。
	var health_ui = target.health_bar
	if health_ui != null:
		health_ui.suppress_floating_text = true

	target.health = clampi(
		int(live_state.get("health",target.Max_health)),
		0,
		target.Max_health
	)
	target.block = clampi(
		int(live_state.get("block",0)),
		0,
		target.max_block
	)
	target.energy = clampi(
		int(live_state.get("energy",target.max_energy)),
		0,
		target.max_energy
	)

	if health_ui != null:
		health_ui.suppress_floating_text = false

	if target.state_machine:
		var cooldown_state = live_state.get("last_state_dis",{})
		if cooldown_state is Dictionary:
			target.state_machine.last_state_dis = cooldown_state.duplicate(true)


static func _capture_collision_shell(source:ball) -> Dictionary:
	var result:Dictionary = {}
	if source == null or not is_instance_valid(source):
		return result

	for raw_path:String in ["CollisionShape2D","hitbox/CollisionShape2D","hurtbox/CollisionShape2D"]:
		var shape_node := source.get_node_or_null(raw_path) as CollisionShape2D
		if shape_node == null:
			continue
		var shape_copy:Shape2D = null
		if shape_node.shape != null:
			shape_copy = shape_node.shape.duplicate(true) as Shape2D
		result[raw_path] = {
			"position": shape_node.position,
			"rotation": shape_node.rotation,
			"scale": shape_node.scale,
			"skew": shape_node.skew,
			"shape": shape_copy,
		}
	return result


static func _apply_collision_shell(target:ball,shell:Variant) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not shell is Dictionary:
		return

	var data_by_path:Dictionary = shell
	for raw_path in data_by_path:
		var path:String = str(raw_path)
		var saved:Variant = data_by_path[raw_path]
		if not saved is Dictionary:
			continue
		var shape_node := target.get_node_or_null(path) as CollisionShape2D
		if shape_node == null:
			continue
		var shape_data:Dictionary = saved
		shape_node.position = shape_data.get("position",shape_node.position)
		shape_node.rotation = float(shape_data.get("rotation",shape_node.rotation))
		shape_node.scale = shape_data.get("scale",shape_node.scale)
		shape_node.skew = float(shape_data.get("skew",shape_node.skew))
		var saved_shape:Variant = shape_data.get("shape",null)
		if saved_shape is Shape2D:
			shape_node.shape = (saved_shape as Shape2D).duplicate(true) as Shape2D

	# ball.gd 的 Figure_collide_transform 会以 defualt_collision 为 Tween 回弹目标。
	# 如果不更新这里，第一次碰撞后碰撞箱仍会悄悄变回目标角色自己的大小。
	if target.defualt_collision is Dictionary:
		var body_shape := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var hit_shape := target.get_node_or_null("hitbox/CollisionShape2D") as CollisionShape2D
		var hurt_shape := target.get_node_or_null("hurtbox/CollisionShape2D") as CollisionShape2D
		if body_shape != null:
			target.defualt_collision["Collidebox"] = _collision_transform_dict(body_shape)
		if hit_shape != null:
			target.defualt_collision["Hitbox"] = _collision_transform_dict(hit_shape)
		if hurt_shape != null:
			target.defualt_collision["Hurtbox"] = _collision_transform_dict(hurt_shape)


static func _collision_transform_dict(shape_node:CollisionShape2D) -> Dictionary:
	return {
		"position": shape_node.position,
		"scale": shape_node.scale,
		"rotation": shape_node.rotation,
		"skew": shape_node.skew,
	}


static func _apply_transform_config_before_ready(
	target:ball,
	config:Dictionary
) -> void:
	for property_name in config:
		target.set(str(property_name),config[property_name])


static func deactivate_for_swap(source:ball) -> void:
	source.remove_from_group("Ball")
	source.set_physics_process(false)
	source.set_process(false)

	if source.state_machine:
		source.state_machine.set_physics_process(false)

	source.collision_layer = 0
	source.collision_mask = 0

	if source.self_hitbox:
		source.self_hitbox.set_deferred("monitoring",false)
		source.self_hitbox.set_deferred("monitorable",false)
	if source.self_hurtbox:
		source.self_hurtbox.set_deferred("monitoring",false)
		source.self_hurtbox.set_deferred("monitorable",false)


static func cleanup_owned_creatures(source:ball) -> void:
	for creature in source.Creatures.duplicate():
		if is_instance_valid(creature):
			creature.queue_free()
	source.Creatures.clear()


static func rebind_world_references(old_form:ball,new_form:ball) -> void:
	var tree := new_form.get_tree()
	if tree == null:
		return

	for node in tree.get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var other:ball = node as ball
		if other == old_form:
			continue

		if other.Master == old_form:
			other.Master = new_form
			other.Master_name = new_form.name
		if other.Target_Enemy == old_form:
			other.Target_Enemy = new_form
		if other.Nearest_Enemy == old_form:
			other.Nearest_Enemy = new_form
