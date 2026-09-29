extends Node

const EXECUTION_SFX:AudioStream = preload("res://audio/characters/骷髅/拔箭.mp3")
const EXECUTION_HP_PER_ARROW:int = 5
const EXECUTION_CINEMATIC_MIN_MAX_HP:int = 100
# 骷髅斩杀的慢动作是全场共享的强调效果，不能让短时间内连续斩杀反复续上慢动作。
# 使用 Time.get_ticks_usec() 的真实时间计时，不受 Engine.time_scale 本身影响。
const EXECUTION_SLOWMO_COOLDOWN_SEC:float = 3.0
const EXECUTION_SLOWMO_META_KEY:StringName = &"minecraft_skeleton_execution_slowmo_last_usec"

var target:ball = null
var arrows:Array[Node2D] = []
var _executing:bool = false
var _red_bar:TextureProgressBar = null
var _dash_nodes:Array[ColorRect] = []
var _last_source:Node = null
var _overlay_signature:String = ""
var _health_label:Label = null
var _health_label_original_z:int = 0
var _health_label_z_captured:bool = false
var _cinematic_focus_requested:bool = false
var _execution_arrow_count:int = 0


func setup(new_target:ball) -> void:
	target = new_target
	set_process(true)
	_refresh_overlay(true)


func register_arrow(arrow:Node2D,source:Node = null) -> void:
	if arrow == null or not is_instance_valid(arrow):
		return
	if not arrows.has(arrow):
		arrows.append(arrow)
	if source != null and is_instance_valid(source):
		_last_source = source
	var exited_callable:Callable = _on_arrow_exited.bind(arrow)
	if not arrow.tree_exited.is_connected(exited_callable):
		arrow.tree_exited.connect(exited_callable,CONNECT_ONE_SHOT)
	_refresh_overlay(true)


func _on_arrow_exited(arrow:Node2D) -> void:
	arrows.erase(arrow)
	call_deferred("_refresh_overlay",true)


func _process(_delta:float) -> void:
	if target == null or not is_instance_valid(target):
		_cleanup_overlay()
		queue_free()
		return
	_clean_arrows()
	_refresh_overlay(false)
	_update_red_fill()
	if _executing or arrows.is_empty() or target.health <= 0:
		return
	var threshold:int = arrows.size() * EXECUTION_HP_PER_ARROW
	if int(target.health) <= threshold:
		_begin_execution()


func _clean_arrows() -> void:
	for arrow:Node2D in arrows.duplicate():
		if arrow == null or not is_instance_valid(arrow):
			arrows.erase(arrow)


func _effective_arrow_count() -> int:
	# 处决动画开始后，箭会依次拔出并重新飞出。血条提示不能随着箭离开身体立刻消失，
	# 否则处决镜头里红色危险区会突然空掉。处决期间固定使用开始处决时的箭数。
	if _executing and _execution_arrow_count > 0:
		return _execution_arrow_count
	return arrows.size()


func _refresh_overlay(force:bool = false) -> void:
	if target == null or not is_instance_valid(target) or target.health_bar == null:
		return
	var count:int = _effective_arrow_count()
	if count <= 0:
		if _red_bar != null or not _dash_nodes.is_empty():
			_cleanup_overlay()
		_overlay_signature = ""
		return
	var hb:TextureProgressBar = target.health_bar.health_bar
	if hb == null or not is_instance_valid(hb):
		return
	var max_hp:float = maxf(float(target.Max_health),1.0)
	var threshold:float = minf(float(count * EXECUTION_HP_PER_ARROW),max_hp - 0.001)
	if threshold <= 0.0:
		_cleanup_overlay()
		_overlay_signature = ""
		return
	var signature:String = "%d|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [
		count,
		max_hp,
		hb.position.x,
		hb.position.y,
		hb.size.x,
		hb.size.y,
		hb.scale.x,
		hb.scale.y,
	]
	if not force and signature == _overlay_signature:
		return
	_overlay_signature = signature
	_cleanup_overlay()

	var parent:Control = hb.get_parent() as Control
	if parent == null:
		return
	_health_label = target.health_bar.label
	if _health_label != null and is_instance_valid(_health_label):
		if not _health_label_z_captured:
			_health_label_original_z = _health_label.z_index
			_health_label_z_captured = true
		_health_label.z_index = 8
	var ratio:float = clampf(threshold / max_hp,0.0,1.0)
	var sx:float = absf(hb.scale.x)
	var sy:float = absf(hb.scale.y)
	var width:float = hb.size.x * sx
	var height:float = hb.size.y * sy
	var line_y:float = hb.position.y + height * (1.0 - ratio)

	# 复制生命条自身纹理，只绘制“当前剩余生命中位于斩杀线以下的部分”。
	# 这样红色区域仍保持原血条/十字轮廓，不会变成盖住透明区域的矩形色块。
	_red_bar = TextureProgressBar.new()
	_red_bar.name = "MinecraftArrowRedHealth"
	_red_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_red_bar.texture_progress = hb.texture_progress
	_red_bar.texture_filter = hb.texture_filter
	_red_bar.fill_mode = hb.fill_mode
	# 生命条本体运行时挂有“角色十字血条”遮罩。红色危险区必须复用同一材质，
	# 否则原贴图四角/透明区会重新被染红，看起来就像红色溢出血条。
	if hb.material != null:
		_red_bar.material = hb.material
	_red_bar.min_value = 0.0
	_red_bar.max_value = 1.0
	_red_bar.step = 0.0
	_red_bar.position = hb.position
	_red_bar.size = hb.size
	_red_bar.scale = hb.scale
	_red_bar.pivot_offset = hb.pivot_offset
	_red_bar.self_modulate = Color(1.0,0.055,0.055,0.98)
	_red_bar.z_index = 4
	parent.add_child(_red_bar)
	_update_red_fill()

	# 黑色虚线必须完全落在红色区域里面，而不是压在红/正常生命的分界线上。
	# 同时生命条使用十字 Shader：离开横臂以后只有中间竖臂可见。这里按同一个
	# arm_half_width=0.19 计算该 Y 处真正可见的横向范围，避免黑线伸到血条外。
	var thickness:float = minf(maxf(32.0 * sy,2.0),maxf(height * 0.08,2.0))
	var dash_center_y:float = minf(line_y + thickness * 0.85,hb.position.y + height - thickness * 0.55)
	var local_y_ratio:float = clampf((dash_center_y - hb.position.y) / maxf(height,1.0),0.0,1.0)
	var cross_arm_half_width:float = 0.19
	var visible_left:float = hb.position.x
	var visible_width:float = width
	if absf(local_y_ratio - 0.5) >= cross_arm_half_width:
		visible_left = hb.position.x + width * (0.5 - cross_arm_half_width)
		visible_width = width * cross_arm_half_width * 2.0
	var side_inset:float = maxf(visible_width * 0.035,thickness * 0.75)
	visible_left += side_inset
	visible_width = maxf(visible_width - side_inset * 2.0,thickness * 3.0)
	var dash_count:int = 7
	var unit:float = visible_width / float(dash_count * 2 - 1)
	for i:int in range(dash_count):
		var dash := ColorRect.new()
		dash.name = "MinecraftArrowDash_%d" % i
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dash.color = Color(0.0,0.0,0.0,1.0)
		dash.z_index = 7
		dash.position = Vector2(visible_left + float(i * 2) * unit,dash_center_y - thickness * 0.5)
		dash.size = Vector2(unit,thickness)
		parent.add_child(dash)
		_dash_nodes.append(dash)


func _update_red_fill() -> void:
	if _red_bar == null or not is_instance_valid(_red_bar) or target == null or not is_instance_valid(target):
		return
	var max_hp:float = maxf(float(target.Max_health),1.0)
	var threshold:float = minf(float(_effective_arrow_count() * EXECUTION_HP_PER_ARROW),max_hp)
	var visible_red_hp:float = minf(maxf(float(target.health),0.0),threshold)
	_red_bar.value = clampf(visible_red_hp / max_hp,0.0,1.0)


func _cleanup_overlay() -> void:
	if _red_bar != null and is_instance_valid(_red_bar):
		_red_bar.queue_free()
	_red_bar = null
	for dash:ColorRect in _dash_nodes:
		if dash != null and is_instance_valid(dash):
			dash.queue_free()
	_dash_nodes.clear()
	if _health_label_z_captured and _health_label != null and is_instance_valid(_health_label):
		_health_label.z_index = _health_label_original_z
	_health_label = null
	_health_label_z_captured = false


func _begin_execution() -> void:
	if _executing or target == null or not is_instance_valid(target):
		return
	var living_arrows:Array[Node2D] = []
	for arrow:Node2D in arrows:
		if arrow != null and is_instance_valid(arrow):
			living_arrows.append(arrow)
	if living_arrows.is_empty():
		return

	_executing = true
	_execution_arrow_count = living_arrows.size()
	# 不要在处决开始时清掉红色危险区。镜头慢动作期间继续显示，直到真正斩杀完成。
	_refresh_overlay(true)
	_update_red_fill()
	_request_execution_camera_focus()
	var finished_counter:Array[int] = [0]
	for index:int in range(living_arrows.size()):
		var arrow:Node2D = living_arrows[index]
		var world_forward:Vector2 = Vector2.RIGHT.rotated(arrow.global_rotation)
		if arrow.has_method("get_flight_direction"):
			var raw_dir:Variant = arrow.call("get_flight_direction")
			if raw_dir is Vector2:
				var dir_value:Vector2 = raw_dir
				if dir_value.length_squared() > 0.000001:
					world_forward = dir_value.normalized()
		if world_forward.length_squared() <= 0.000001:
			world_forward = Vector2.RIGHT

		# 箭可能挂在目标的旋转视觉节点下（例如木矛），所以拔出/再刺入必须使用箭当前父节点的局部坐标系。
		var arrow_parent_2d:Node2D = arrow.get_parent() as Node2D
		var world_anchor:Vector2 = arrow.global_position
		var anchor:Node2D = arrow_parent_2d if is_instance_valid(arrow_parent_2d) else target
		var unit_scale:float = maxf(target.global_transform.x.length(),target.global_transform.y.length())
		# 以原角色根坐标的距离为基准，换到 Image/Graphics 后仍有相同世界拔箭距离。
		var local_step:Vector2 = anchor.to_local(world_anchor+world_forward*unit_scale)-anchor.to_local(world_anchor)
		var original_pos:Vector2 = arrow.position
		var pull_pos:Vector2 = original_pos-local_step*84.0
		var perpendicular:Vector2 = anchor.to_local(world_anchor+world_forward.orthogonal()*unit_scale*2.8)-anchor.to_local(world_anchor)
		var through_pos:Vector2 = original_pos+local_step*54.0
		var tw:Tween = arrow.create_tween()
		tw.tween_property(arrow,"position",pull_pos,0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if index == 0:
			tw.tween_callback(_play_pull_reinsert_sfx)
		# 拔出后略微颤抖，再突然刺入。
		tw.tween_property(arrow,"position",pull_pos + perpendicular,0.035).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(arrow,"position",pull_pos - perpendicular,0.035).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(arrow,"position",pull_pos + perpendicular * 0.65,0.03).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(arrow,"position",pull_pos,0.03).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(arrow,"position",through_pos,0.085).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tw.tween_callback(
			Callable(self,"_on_execution_arrow_passed_through").bind(
				arrow,
				world_forward,
				finished_counter,
				living_arrows.size()
			)
		)


func _request_execution_camera_focus() -> void:
	if _cinematic_focus_requested or target == null or not is_instance_valid(target):
		return
	# 按最大生命而不是斩杀时的残血判断；小单位不申请镜头，也不读取/消耗共享冷却。
	if target.Max_health < EXECUTION_CINEMATIC_MIN_MAX_HP:
		return
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world != null and world.has_method("request_cinematic_focus"):
		# 镜头拉近每次斩杀都保留；只有慢动作受全场共享冷却限制。
		# 冷却中的后续斩杀用 slow=1.0 注册镜头请求，因此不会重新触发/延长 0.25x 慢动作。
		var slow_factor:float = 0.25 if _consume_execution_slowmo_cooldown(world) else 1.0
		world.call("request_cinematic_focus",self,target,slow_factor,1.55)
		_cinematic_focus_requested = true


func _consume_execution_slowmo_cooldown(world:Node) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	var now_usec:int = Time.get_ticks_usec()
	var last_usec:int = int(world.get_meta(EXECUTION_SLOWMO_META_KEY,-1))
	var cooldown_usec:int = int(maxf(EXECUTION_SLOWMO_COOLDOWN_SEC,0.0) * 1000000.0)
	if last_usec >= 0 and now_usec - last_usec < cooldown_usec:
		return false
	world.set_meta(EXECUTION_SLOWMO_META_KEY,now_usec)
	return true


func _release_execution_camera_focus() -> void:
	if not _cinematic_focus_requested:
		return
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world != null and world.has_method("release_cinematic_focus"):
		world.call("release_cinematic_focus",self)
	_cinematic_focus_requested = false


func _play_pull_reinsert_sfx() -> void:
	if not _executing or is_queued_for_deletion() or not is_inside_tree(): return
	if EXECUTION_SFX == null:
		return
	if get_tree() == null or get_tree().current_scene == null:
		return

	# “拔箭”是处决的关键提示音。旧版使用 AudioStreamPlayer2D，目标离当前监听点较远时
	# 仍可能被距离衰减到几乎听不见。这里改成非位置 AudioStreamPlayer，保证处决镜头中
	# 一定能听到。播放器直接挂到 SceneTree 根，避免被当前 World 的 MultiplayerSpawner
	# 当成网络出生节点，同时目标/控制器被删除后也不会把 1.32 秒音效提前截断。
	var player := AudioStreamPlayer.new()
	player.name = "骷髅拔箭处决音效_%d" % Time.get_ticks_usec()
	player.stream = EXECUTION_SFX
	player.volume_db = 8.0
	player.pitch_scale = randf_range(0.98,1.02)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _on_execution_arrow_passed_through(
	arrow:Node2D,
	world_forward:Vector2,
	counter:Array[int],
	total:int
) -> void:
	if not _executing or is_queued_for_deletion(): return
	if arrow != null and is_instance_valid(arrow):
		if arrow.has_method("launch_execution_flyout"):
			if arrow.has_method("get_flight_direction"):
				world_forward = arrow.call("get_flight_direction")
			# 穿出目标后恢复为“真正的普通骷髅箭”，由箭脚本继续处理伤害、友军过滤和插墙。
			arrow.call("launch_execution_flyout",world_forward)
		else:
			# 兼容未来替换箭场景：至少把箭脱离人物并继续向前飞，不在处决瞬间硬删。
			var world:Node = get_tree().current_scene if get_tree() != null else null
			if world != null:
				arrow.reparent(world,true)
				var tw:Tween = arrow.create_tween()
				tw.tween_property(arrow,"global_position",arrow.global_position + world_forward * 180.0,0.24)
				tw.tween_callback(arrow.queue_free)
	counter[0] += 1
	if counter[0] >= total:
		_finish_execution()


func _finish_execution() -> void:
	if not _executing or is_queued_for_deletion(): return
	if target != null and is_instance_valid(target) and target.health > 0:
		var source:Node = _last_source if _last_source != null and is_instance_valid(_last_source) else self
		# 用结算这一刻的剩余生命，保证斩杀伤害/跳字不再显示额外的9999。
		var lethal:float = float(target.health)
		target.receive_spatial_raw_health_damage(lethal,{"point":target.global_position,"source":source})
	# 箭已经在“插穿”回调里脱离目标继续飞行；这里不能再 queue_free，否则会看起来凭空消失。
	arrows.clear()
	_execution_arrow_count = 0
	_cleanup_overlay()
	_release_execution_camera_focus()
	queue_free()


func _exit_tree() -> void:
	# 目标被其他来源提前删掉/切场景时也必须释放慢动作与镜头占用。
	_release_execution_camera_focus()

func cleanse_status_effect() -> void:
	# Stop pending execution before removing embeds; never run its lethal finish.
	_executing = false
	_execution_arrow_count = 0
	for arrow:Node2D in arrows.duplicate():
		if not is_instance_valid(arrow): continue
		if arrow.get_parent()!=null: arrow.get_parent().remove_child(arrow)
		arrow.queue_free()
	arrows.clear()
	_cleanup_overlay()
	_release_execution_camera_focus()
