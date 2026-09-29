extends Node
# 地表渲染快照：按项目地表最终Z层选择，支持纹理、调色、TileMap和Shader。
# 不辨认背景名称。未来背景沿用地表层(最终Z <= -5)，无需修改重锤。
# 同一帧多个冲击共享一次读回；不拍角色、血液(-4)、文字或上层特效。
const CAPTURE_LAYER:int = 1 << 19
const FLOOR_MAX_Z:int = -5
signal capture_finished
var _busy:bool = false
var _frame:int = -1
var _snapshot:Dictionary = {}

func capture(rect:Rect2) -> Dictionary:
	while _busy:
		await capture_finished
		if _snapshot_covers(rect): return _snapshot
	if _frame == Engine.get_process_frames() and _snapshot_covers(rect): return _snapshot
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or DisplayServer.get_name() == "headless":
		return {} # 无渲染环境保留冲击圈，不伪造蓝色碎屑。
	_busy = true
	var completed:Dictionary = {}
	var world:Node = get_parent()
	var viewport := SubViewport.new()
	viewport.name = "GroundCaptureViewport"
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.canvas_cull_mask = CAPTURE_LAYER
	viewport.world_2d = world.get_viewport().world_2d
	var ratio:float = minf(1.0,1024.0/maxf(rect.size.x,rect.size.y))
	viewport.size = Vector2i(maxi(1,int(ceil(rect.size.x*ratio))),maxi(1,int(ceil(rect.size.y*ratio))))
	var pixel_scale:Vector2 = Vector2(viewport.size)/rect.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	# 入树后Canvas才已注册，避免viewport_set_canvas_transform报错。
	viewport.canvas_transform = Transform2D(Vector2(pixel_scale.x,0),Vector2(0,pixel_scale.y),-rect.position*pixel_scale)
	# 只跨帧保存实例ID；节点可能在frame_post_draw之前被击杀/销毁。
	var changed:Dictionary = {}
	_mark_floor_items(world,0,changed)
	await RenderingServer.frame_post_draw
	if is_instance_valid(viewport):
		var image:Image = viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			completed = {"image":image,"rect":rect}
		viewport.queue_free()
	for instance_id:int in changed:
		var object:Object = instance_from_id(instance_id)
		if not is_instance_valid(object) or not (object is CanvasItem):
			continue
		var item:CanvasItem = object as CanvasItem
		item.visibility_layer = (item.visibility_layer & ~CAPTURE_LAYER) | (int(changed[instance_id]) & CAPTURE_LAYER)
	_snapshot = completed
	_frame = Engine.get_process_frames()
	_busy = false
	capture_finished.emit()
	return completed # A resumed waiter may already have begun a different capture.

func _snapshot_covers(rect:Rect2) -> bool:
	if _snapshot.is_empty(): return false
	var captured:Rect2 = _snapshot.get("rect",Rect2())
	return captured.encloses(rect)

func _mark_floor_items(node:Node,parent_z:int,changed:Dictionary) -> void:
	# Screen-following tooltips and recording text are not map ground. Their
	# world-canvas visibility bits must not be cleared during a ground snapshot.
	if node is Viewport or node is CanvasLayer or node.has_meta("recording_copy"): return
	var final_z:int = parent_z
	if node is CanvasItem:
		var item:CanvasItem = node as CanvasItem
		final_z = item.z_index + (parent_z if item.z_as_relative else 0)
		# 清除本次采样位，避免默认全可见掩码的上层物体漏入快照。
		var item_id:int = item.get_instance_id()
		if not changed.has(item_id): changed[item_id] = item.visibility_layer
		item.visibility_layer = item.visibility_layer & ~CAPTURE_LAYER
		if final_z <= FLOOR_MAX_Z and item.is_visible_in_tree():
			var ancestor:Node = item
			while ancestor != null:
				if ancestor is CanvasItem:
					var canvas:CanvasItem = ancestor as CanvasItem
					var canvas_id:int = canvas.get_instance_id()
					if not changed.has(canvas_id): changed[canvas_id] = canvas.visibility_layer
					canvas.visibility_layer = canvas.visibility_layer | CAPTURE_LAYER
				if ancestor == get_parent(): break
				ancestor = ancestor.get_parent()
	for child:Node in node.get_children(): _mark_floor_items(child,final_z,changed)
