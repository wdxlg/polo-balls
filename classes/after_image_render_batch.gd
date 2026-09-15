extends Node2D
## Render-only storage for ordinary knife snapshots. Same texture draw command,
## original shader, per-snapshot uniforms and Tween.interpolate_value curves.
## Unsupported Sprite2D features must keep the original Node/Tween path.
const META = &"_performance_knife_snapshot_renderer"
class Snapshot:
	extends RefCounted
	var canvas:RID
	var group:Node2D
	var source_id:int
	var elapsed:float = 0.0
	var lifetime:float
	var transform:Transform2D
	var start_scale:Vector2
	var end_scale:Vector2
	var texture:Texture2D
	var material:ShaderMaterial
	var draw_rect:Rect2

var material_cache:Dictionary = {}
var batch_shader:Shader
var snapshots:Array[Snapshot] = []
# Pool render-only records/RIDs, never gameplay Nodes or physics objects. A
# detached inactive canvas has no visual presence. Bound retention per world.
const MAX_IDLE_SNAPSHOTS:int = 2048
var idle_snapshots:Array[Snapshot] = []
var reused_snapshots:int = 0
var created_canvases:int = 0
var recorded_draws:int = 0
var reused_draws:int = 0
var groups:Dictionary = {}
var tail_group:Node2D
var tail_order:int = 0
var transform_helper:Node2D = Node2D.new()
var clock:Tween
static var signal_names:Array[StringName] = []

static func eligible(image:Node2D,world:Node) -> bool:
	if not image is Sprite2D or not world is Node2D:
		return false
	var sprite:Sprite2D = image
	if (sprite.get_script() != null or sprite.get_child_count(true) != 0
		or not sprite.scene_file_path.is_empty() or not sprite.get_meta_list().is_empty()
		or not sprite.get_groups().is_empty() or sprite.use_parent_material
		or sprite.show_behind_parent or sprite.top_level or sprite.y_sort_enabled
		or sprite.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED
		or sprite.process_mode != Node.PROCESS_MODE_INHERIT
		or sprite.visibility_layer != 1 or sprite.light_mask != 1
		or sprite.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE
		or sprite.texture_repeat != CanvasItem.TEXTURE_REPEAT_PARENT_NODE
		or sprite.region_enabled or sprite.hframes != 1 or sprite.vframes != 1
		or (world as Node2D).y_sort_enabled
		or bool(ProjectSettings.get_setting("physics/common/physics_interpolation",false))):
		return false
	# This fast path is for immutable imported knife textures, not animated/custom
	# textures whose changed signal can alter the snapshot layout after spawning.
	if not sprite.texture is CompressedTexture2D:
		return false
	if signal_names.is_empty():
		for info:Dictionary in sprite.get_signal_list():
			signal_names.append(StringName(info.name))
	for signal_name:StringName in signal_names:
		if not Signal(sprite,signal_name).has_connections():
			continue
		for connection:Dictionary in sprite.get_signal_connection_list(signal_name):
			if (int(connection.flags) & CONNECT_PERSIST) != 0:
				return false
	return true

static func try_spawn(source:ball,ghost_transform:Transform2D,world_trail_dir:Vector2,material:ShaderMaterial) -> bool:
	var image:Node2D = source.image
	var world:Node = source.get_tree().current_scene
	if image == null or not is_instance_valid(image) or not image.visible or world == null:
		return false
	if not eligible(image,world):
		return false
	if int(source.AfterImage_Texture_Source) != 0:
		return false
	var renderer:Node2D = world.get_meta(META) if world.has_meta(META) else null
	if renderer == null or not is_instance_valid(renderer):
		renderer = load("res://classes/after_image_render_batch.gd").new()
		renderer.name = "KnifeSnapshotRenderer"
		world.set_meta(META,renderer)
		world.add_child(renderer)
	renderer.add_snapshot(source,image as Sprite2D,ghost_transform,world_trail_dir,material)
	return true

func _ready() -> void:
	clock = create_tween()
	# SceneTree's Tween phase is after physics, process callbacks and scene timers.
	# A normal _process() callback would advance freshly spawned snapshots too early.
	clock.tween_method(_advance,0.0,1.0,1.0e20)

func add_snapshot(source:ball,image:Sprite2D,ghost_transform:Transform2D,world_trail_dir:Vector2,material:ShaderMaterial) -> void:
	var world:Node2D = get_parent() as Node2D
	var z:int = clampi(image.z_index - 1,RenderingServer.CANVAS_ITEM_Z_MIN,RenderingServer.CANVAS_ITEM_Z_MAX)
	# Only merge an uninterrupted run of last-child snapshots. New non-snapshot
	# siblings split the run, preserving transparent draw order at the same z.
	if (tail_group == null or not is_instance_valid(tail_group)
		or tail_group.is_queued_for_deletion() or tail_group.z_index != z
		or world.get_child(world.get_child_count()-1) != tail_group):
		tail_group = Node2D.new()
		tail_group.name = "KnifeSnapshotRun"
		tail_group.z_as_relative = false
		tail_group.z_index = z
		world.add_child(tail_group)
		groups[tail_group.get_instance_id()] = 0
		tail_order = 0
	var snapshot:Snapshot
	if idle_snapshots.is_empty():
		snapshot = Snapshot.new()
		snapshot.canvas = RenderingServer.canvas_item_create()
		created_canvases += 1
	else:
		snapshot = idle_snapshots.pop_back()
		reused_snapshots += 1
	snapshot.elapsed = 0.0
	snapshot.group = tail_group
	snapshot.source_id = source.get_instance_id()
	snapshot.lifetime = maxf(float(source.AfterImage_Lifetime),0.05)
	RenderingServer.canvas_item_set_parent(snapshot.canvas,tail_group.get_canvas_item())
	RenderingServer.canvas_item_set_draw_index(snapshot.canvas,tail_order)
	tail_order += 1
	RenderingServer.canvas_item_set_modulate(snapshot.canvas,image.modulate)
	RenderingServer.canvas_item_set_self_modulate(snapshot.canvas,image.self_modulate)
	var colors:Dictionary = source._get_after_image_snapshot_colors(ghost_transform)
	var uniforms:Dictionary = {
		&"source_flip_h":1.0 if bool(source._visual_facing_flipped_h) else 0.0,
		&"start_color":colors.get("start",source.AfterImage_Tint),
		&"end_color":colors.get("end",source.AfterImage_End_Tint),
		&"visual_params_a":Vector4(source.AfterImage_Alpha,source.AfterImage_End_Alpha,source.AfterImage_Blur_Pixels,source.AfterImage_End_Blur_Pixels),
		&"visual_params_b":Vector4(source.AfterImage_Smear_Pixels,source.AfterImage_End_Smear_Pixels,source.AfterImage_Distortion_Pixels,source.AfterImage_End_Distortion_Pixels),
		&"style_mode":int(source.AfterImage_Style),
		&"sample_count":clampi(int(source.AfterImage_Sample_Count),1,16),
		&"fade_mode":int(source.AfterImage_Fade),
	}
	var local_dir:Vector2 = world_trail_dir
	if local_dir.length_squared() <= 0.000001:
		local_dir = Vector2.RIGHT
	local_dir = local_dir.normalized().rotated(-ghost_transform.get_rotation())
	var descriptor:Array = uniforms.values()
	if not material_cache.has(descriptor):
		if batch_shader == null:
			batch_shader = Shader.new()
			batch_shader.code = material.shader.code.replace("instance uniform ","uniform ").replace("uniform float progress ","instance uniform float progress ").replace("uniform vec2 trail_direction ","instance uniform vec2 trail_direction ")
		var shared:ShaderMaterial = ShaderMaterial.new()
		shared.shader = batch_shader
		for key:StringName in uniforms:
			var value:Variant = uniforms[key]
			# Instance-uniform Color values use the linear global-uniform buffer.
			# Ordinary 2D material uniforms in an LDR viewport do not auto-convert.
			if value is Color and not get_viewport().use_hdr_2d:
				value = (value as Color).srgb_to_linear()
			shared.set_shader_parameter(key,value)
		if material_cache.size() >= 256:
			material_cache.clear()
		material_cache[descriptor] = shared
	var next_material:ShaderMaterial = material_cache[descriptor]
	if snapshot.material != next_material:
		snapshot.material = next_material
		RenderingServer.canvas_item_set_material(snapshot.canvas,next_material.get_rid())
	RenderingServer.canvas_item_set_instance_shader_parameter(snapshot.canvas,&"progress",0.0)
	RenderingServer.canvas_item_set_instance_shader_parameter(snapshot.canvas,&"trail_direction",local_dir.normalized())
	var size:Vector2 = image.texture.get_size()
	var offset:Vector2 = image.offset - size * 0.5 if image.centered else image.offset
	if get_viewport().is_snap_2d_transforms_to_pixel_enabled():
		offset = (offset + Vector2(0.5,0.5)).floor()
	var next_rect:Rect2 = Rect2(offset,size)
	# An invisible pooled RID can retain its immutable texture draw command.
	# Re-record only when texture identity or the effective rectangle changes;
	# all live transforms, colors, uniforms and draw order still update above/below.
	if snapshot.texture != image.texture or snapshot.draw_rect != next_rect:
		RenderingServer.canvas_item_clear(snapshot.canvas)
		image.texture.draw_rect_region(snapshot.canvas,next_rect,Rect2(Vector2.ZERO,size),Color.WHITE,false,false)
		snapshot.texture = image.texture
		snapshot.draw_rect = next_rect
		recorded_draws += 1
	else:
		reused_draws += 1
	var world_transform:Transform2D = source._after_image_transform_for_texture(ghost_transform,image.texture)
	transform_helper.transform = world.global_transform.affine_inverse() * world_transform
	snapshot.transform = transform_helper.transform
	var base_scale:Vector2 = transform_helper.scale
	var start:Vector2 = source.AfterImage_Start_Scale
	var finish:Vector2 = source.AfterImage_End_Scale
	snapshot.start_scale = base_scale * Vector2(maxf(absf(start.x),0.01),maxf(absf(start.y),0.01))
	snapshot.end_scale = base_scale * Vector2(maxf(absf(finish.x),0.01),maxf(absf(finish.y),0.01))
	transform_helper.scale = snapshot.start_scale
	RenderingServer.canvas_item_set_transform(snapshot.canvas,transform_helper.transform)
	RenderingServer.canvas_item_set_visible(snapshot.canvas,true)
	groups[tail_group.get_instance_id()] += 1
	snapshots.append(snapshot)

func _advance(_unused:float) -> void:
	advance_snapshots(get_process_delta_time())

func advance_snapshots(delta:float) -> void:
	var write_index:int = 0
	for snapshot:Snapshot in snapshots:
		snapshot.elapsed += delta
		if snapshot.elapsed >= snapshot.lifetime:
			var group_id:int = snapshot.group.get_instance_id()
			groups[group_id] -= 1
			if groups[group_id] == 0:
				groups.erase(group_id)
				snapshot.group.queue_free()
			_retire_snapshot(snapshot)
			continue
		# Original tween_method is bound to the projectile. Its progress callback
		# ceases after the projectile is freed; the independent scale tween continues.
		if is_instance_id_valid(snapshot.source_id):
			RenderingServer.canvas_item_set_instance_shader_parameter(snapshot.canvas,&"progress",Tween.interpolate_value(0.0,1.0,snapshot.elapsed,snapshot.lifetime,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT))
		transform_helper.transform = snapshot.transform
		transform_helper.scale = Tween.interpolate_value(snapshot.start_scale,snapshot.end_scale-snapshot.start_scale,snapshot.elapsed,snapshot.lifetime,Tween.TRANS_QUAD,Tween.EASE_OUT)
		RenderingServer.canvas_item_set_transform(snapshot.canvas,transform_helper.transform)
		snapshots[write_index] = snapshot
		write_index += 1
	snapshots.resize(write_index)

func _retire_snapshot(snapshot:Snapshot) -> void:
	if idle_snapshots.size() >= MAX_IDLE_SNAPSHOTS:
		RenderingServer.free_rid(snapshot.canvas)
		return
	RenderingServer.canvas_item_set_visible(snapshot.canvas,false)
	RenderingServer.canvas_item_set_parent(snapshot.canvas,RID())
	snapshot.group = null
	snapshot.source_id = 0
	# Keep only render resources, bounded by MAX_IDLE_SNAPSHOTS. No projectile
	# Node, physics identity, await or source reference is retained.
	idle_snapshots.append(snapshot)

func _exit_tree() -> void:
	if clock != null and clock.is_valid():
		clock.kill()
	for snapshot:Snapshot in snapshots:
		RenderingServer.free_rid(snapshot.canvas)
	snapshots.clear()
	for snapshot:Snapshot in idle_snapshots:
		RenderingServer.free_rid(snapshot.canvas)
	idle_snapshots.clear()
	if is_instance_valid(transform_helper):
		transform_helper.free()
