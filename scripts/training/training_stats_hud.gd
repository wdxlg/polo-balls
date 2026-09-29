extends Control

const MOJANGLES_FONT = preload("res://fonts/Mojangles.ttf")

# 训练模式专用：挂在当前地图下方的训练统计 / 积分 HUD。
# 该脚本由 World 动态创建，不需要额外修改 world.tscn。

#========================================================
# 积分规则：以后要调平衡，只改这里。
#========================================================
const SCORE_DODGE:int = 6
const SCORE_NEAR_MISS_BONUS:int = 3
# 伤害积分按“每 1 点实际生命伤害”即时结算，不设任何累计门槛。
# 每 1 点实际伤害 = 0.05 分；例如 1 伤害 = 0.05、20 伤害 = 1、100 伤害 = 5。
# 任何有效攻击都会立即获得非零积分，同时低伤害攻击仍明显低于一次普通闪避（+6）。
const SCORE_PER_DAMAGE_POINT:float = 0.05
# 存活是辅助分，不应成为主要收入来源。
const SCORE_SURVIVE_STEP:float = 0.5
const SURVIVE_STEP_SECONDS:float = 10.0
const SCORE_HIT:int = -6
const SCORE_DEATH:int = -20
# 极速者能量属于可主动消耗资源：每损失 1 点能量扣少量积分。
# 数值刻意远小于一次成功闪避，但持续无意义加速/攻击会逐步拉低总分。
const SCORE_SPEEDSTER_ENERGY_PER_POINT:float = -0.03

#========================================================
# HUD 布局 / 动画
#========================================================
const HUD_MIN_WIDTH:float = 150.0
const HUD_HEIGHT:float = 64.0
# 左右 RichTextLabel 可能因语言/宽度自动换行；HUD 会在运行时继续按完整内容高度向下扩展。
const HUD_CONTENT_VERTICAL_PADDING:float = 6.0
const HUD_MAP_GAP:float = 3.0
const PANEL_GAP:float = 2.0
const LEFT_RATIO:float = 0.36
const CENTER_RATIO:float = 0.30
const FONT_SIZE:int = 4
const HEADER_FONT_SIZE:int = 5
const FEED_FONT_SIZE:int = 4
const FEED_LINE_HEIGHT:float = 7.0
# 积分流采用“终端式”滚动：空时从顶部向下填满；满后新项固定出现在底部，
# 旧项才整体上移，最上方一项在滑出时渐隐。
# 位移动画使用 Time.get_ticks_msec() 计算真实时间，不受 Engine.time_scale 影响。
const FEED_STACK_SHIFT_SPEED:float = 40.0
const FEED_MAX_BUFFER:int = 32

#========================================================
# 训练统计窗口
#========================================================
const SHORT_WINDOW:float = 3.0
const BURST_WINDOW:float = 1.0

# 投射物闪避判定：按角色/投射物碰撞半径动态加余量。
const DODGE_EXTRA_RADIUS:float = 22.0
const NEAR_MISS_EXTRA_RADIUS:float = 9.0
const DODGE_RELEASE_EXTRA:float = 18.0
const PROJECTILE_TRACK_MAX_DISTANCE:float = 135.0

var _world:World = null
var _left_panel:PanelContainer = null
var _center_panel:PanelContainer = null
var _right_panel:PanelContainer = null
var _left_text:RichTextLabel = null
var _right_text:RichTextLabel = null
var _feed_root:Control = null
var _feed_title:Label = null
var _feed_area:Control = null

var _focus:ball = null
var _focus_setup_id:int = -1
var _last_health:float = -1.0
var _last_focus_energy:float = -1.0
var _was_dead:bool = false

var _session_time:float = 0.0
var _life_elapsed:float = 0.0
var _best_survival:float = 0.0
var _next_survival_reward:float = SURVIVE_STEP_SECONDS
var _score:float = 0.0
var _dodges:int = 0
var _near_misses:int = 0
var _hits_taken:int = 0
var _deaths:int = 0
var _damage_dealt:float = 0.0
var _damage_taken:float = 0.0
var _peak_burst_1s:float = 0.0
var _outgoing_samples:Array[Dictionary] = []
var _incoming_samples:Array[Dictionary] = []

# projectile instance id -> tracking record
var _projectile_tracks:Dictionary = {}
# feed record: label / y / target_y
var _feed_entries:Array[Dictionary] = []
var _stats_refresh_left:float = 0.0
var _last_layout_map:String = ""
var _last_layout_rect:Rect2 = Rect2()
var _last_feed_update_msec:int = 0
var _content_fit_queued:bool = false


func setup(world:World) -> void:
	_world = world
	name = "TrainingStatsHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 104
	visibility_layer = 2
	_build_ui()
	visible = Game.is_training_mode() and Game.get_training_mode_type() == "manual"

	if not Game.game_setting_changed.is_connected(_on_game_setting_changed):
		Game.game_setting_changed.connect(_on_game_setting_changed)
	if not Game.training_damage_resolved.is_connected(_on_training_damage_resolved):
		Game.training_damage_resolved.connect(_on_training_damage_resolved)
	if not Game.language_changed.is_connected(_on_language_changed):
		Game.language_changed.connect(_on_language_changed)

	_reset_statistics()
	_refresh_focus(true)
	_refresh_all_text()


func _exit_tree() -> void:
	if Game.game_setting_changed.is_connected(_on_game_setting_changed):
		Game.game_setting_changed.disconnect(_on_game_setting_changed)
	if Game.training_damage_resolved.is_connected(_on_training_damage_resolved):
		Game.training_damage_resolved.disconnect(_on_training_damage_resolved)
	if Game.language_changed.is_connected(_on_language_changed):
		Game.language_changed.disconnect(_on_language_changed)


func _build_ui() -> void:
	_left_panel = _make_panel("TrainingInfo")
	_center_panel = _make_panel("ScoreFeed")
	_right_panel = _make_panel("ScoreRules")
	add_child(_left_panel)
	add_child(_center_panel)
	add_child(_right_panel)

	_left_text = _make_rich_text()
	_left_panel.add_child(_left_text)

	_right_text = _make_rich_text()
	_right_panel.add_child(_right_text)

	_feed_root = Control.new()
	_feed_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_panel.add_child(_feed_root)

	_feed_title = Label.new()
	_feed_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feed_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feed_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_title.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	_feed_title.add_theme_color_override("font_color", Color(0.94,0.96,1.0,0.96))
	_feed_title.add_theme_color_override("font_outline_color", Color(0.0,0.0,0.0,0.92))
	_feed_title.add_theme_constant_override("outline_size", 1)
	_feed_root.add_child(_feed_title)

	_feed_area = Control.new()
	_feed_area.name = "FlowArea"
	_feed_area.clip_contents = true
	_feed_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_root.add_child(_feed_area)


func _make_panel(panel_name:String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.035,0.055,0.86)
	style.border_color = Color(0.52,0.65,0.86,0.34)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_rich_text() -> RichTextLabel:
	var label := RichTextLabel.new()
	for font_name in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]:
		label.add_theme_font_override(font_name, MOJANGLES_FONT)
	label.bbcode_enabled = true
	label.fit_content = false
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	label.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	label.add_theme_color_override("default_color", Color(0.90,0.93,0.98,0.97))
	label.add_theme_color_override("font_outline_color", Color(0.0,0.0,0.0,0.95))
	label.add_theme_constant_override("outline_size", 1)
	return label


func _process(delta:float) -> void:
	var enabled:bool = Game.is_training_mode() and Game.get_training_mode_type() == "manual"
	if visible != enabled:
		visible = enabled
	if not enabled or _world == null or not is_instance_valid(_world):
		return

	_refresh_layout_if_needed()
	_refresh_focus(false)
	_update_feed_animation()

	if _focus == null or not is_instance_valid(_focus):
		_stats_refresh_left -= delta
		if _stats_refresh_left <= 0.0:
			_stats_refresh_left = 0.20
			_refresh_all_text()
		return

	# 统计时间使用游戏 delta，因此训练倍速下统计的也是“模拟时间”；
	# 积分流水动画单独用系统毫秒，保证 32x 训练时仍然看得清。
	if not get_tree().paused:
		_session_time += maxf(delta,0.0)
		if not _is_focus_dead():
			_life_elapsed += maxf(delta,0.0)
			_best_survival = maxf(_best_survival,_life_elapsed)
			while _life_elapsed >= _next_survival_reward:
				_award(SCORE_SURVIVE_STEP,"TRAINING_RULE_SURVIVE")
				_next_survival_reward += SURVIVE_STEP_SECONDS

	_update_health_fallback()
	_update_speedster_energy_score()
	_update_death_state()
	_update_projectile_dodges()
	_prune_damage_samples()

	_stats_refresh_left -= delta
	if _stats_refresh_left <= 0.0:
		_stats_refresh_left = 0.20
		_refresh_all_text()


func _refresh_layout_if_needed() -> void:
	if not _world.map_group.has(_world.now_choose_map):
		return
	var map_variant:Variant = _world.map_group[_world.now_choose_map]
	if not map_variant is TileMapLayer:
		return
	var map_rect:Rect2 = _world.return_map_visual_rect(map_variant as TileMapLayer)
	if _last_layout_map == _world.now_choose_map and _last_layout_rect == map_rect:
		return
	_last_layout_map = _world.now_choose_map
	_last_layout_rect = map_rect
	_layout_under_map(map_rect)


func _layout_under_map(map_rect:Rect2) -> void:
	var total_width:float = maxf(map_rect.size.x,HUD_MIN_WIDTH)
	position = Vector2(
		map_rect.get_center().x - total_width * 0.5,
		map_rect.end.y + HUD_MAP_GAP
	)
	size = Vector2(total_width,HUD_HEIGHT)

	var usable:float = total_width - PANEL_GAP * 2.0
	var left_w:float = floor(usable * LEFT_RATIO)
	var center_w:float = floor(usable * CENTER_RATIO)
	var right_w:float = usable - left_w - center_w

	_left_panel.position = Vector2.ZERO
	_left_panel.size = Vector2(left_w,HUD_HEIGHT)
	_center_panel.position = Vector2(left_w + PANEL_GAP,0.0)
	_center_panel.size = Vector2(center_w,HUD_HEIGHT)
	_right_panel.position = Vector2(left_w + PANEL_GAP + center_w + PANEL_GAP,0.0)
	_right_panel.size = Vector2(right_w,HUD_HEIGHT)

	# PanelContainer 会给 FeedRoot 留出 style margin；这里在拿到最终尺寸后排内部区域。
	call_deferred("_layout_feed_children")
	_queue_content_fit()


func _queue_content_fit() -> void:
	if _content_fit_queued:
		return
	_content_fit_queued = true
	call_deferred("_fit_hud_height_to_content")


func _fit_hud_height_to_content() -> void:
	_content_fit_queued = false
	if _left_panel == null or _right_panel == null or _left_text == null or _right_text == null:
		return
	if not is_instance_valid(_left_panel) or not is_instance_valid(_right_panel):
		return
	# 宽度尚未由当前地图布局出来时不要测量，否则自动换行会得到一个虚假的超高值。
	if _left_panel.size.x <= 8.0 or _right_panel.size.x <= 8.0:
		return

	# RichTextLabel.get_content_height() 返回完整内容高度，即使控件本身当前更矮、内容被裁切。
	# 这里用真实内容高度反推整个 HUD 高度，中文/英文换行后都不会再丢底部信息。
	var left_content_h:float = float(_left_text.get_content_height())
	var right_content_h:float = float(_right_text.get_content_height())
	var required_height:float = maxf(
		HUD_HEIGHT,
		ceil(maxf(left_content_h,right_content_h) + HUD_CONTENT_VERTICAL_PADDING)
	)

	if absf(size.y - required_height) > 0.5:
		size.y = required_height
		_left_panel.size.y = required_height
		_center_panel.size.y = required_height
		_right_panel.size.y = required_height

	# PanelContainer 会在尺寸变化后重新给子控件分配可用区域；再延迟一拍刷新积分流水区域。
	call_deferred("_layout_feed_children")


func _layout_feed_children() -> void:
	if _feed_root == null or not is_instance_valid(_feed_root):
		return
	var w:float = _feed_root.size.x
	var h:float = _feed_root.size.y
	_feed_title.position = Vector2.ZERO
	_feed_title.size = Vector2(w,8.0)
	_feed_area.position = Vector2(0.0,8.0)
	_feed_area.size = Vector2(w,maxf(h - 8.0,1.0))
	for entry:Dictionary in _feed_entries:
		var label:Label = entry.get("label") as Label
		if label != null and is_instance_valid(label):
			label.size.x = w


func _refresh_focus(force:bool) -> void:
	# 复活后优先通过 battle_setup_id 找回原训练位，不重置统计。
	if _focus_setup_id >= 0:
		var rebound:ball = _find_character_by_setup_id(_focus_setup_id)
		if rebound != null:
			if rebound != _focus:
				_focus = rebound
				_last_health = float(_focus.health)
				_last_focus_energy = _read_focus_energy()
				_was_dead = _is_focus_dead()
			return
		if _focus != null and is_instance_valid(_focus) and _focus.is_inside_tree():
			return
		_focus = null

	var candidate:ball = _choose_training_character()
	if candidate == null:
		return
	var new_setup_id:int = int(candidate.get_meta("battle_setup_id",-1))
	var changed:bool = force or candidate != _focus or new_setup_id != _focus_setup_id
	_focus = candidate
	_focus_setup_id = new_setup_id
	if changed:
		_reset_statistics()
		_last_health = float(_focus.health)
		_last_focus_energy = _read_focus_energy()
		_was_dead = _is_focus_dead()
		_refresh_all_text()


func _choose_training_character() -> ball:
	var best:ball = null
	var best_setup_id:int = 2147483647
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if candidate.Type != ball.Ball_Type.Ball:
			continue
		if candidate.Master != null or not candidate.Master_name.is_empty():
			continue
		var setup_id:int = int(candidate.get_meta("battle_setup_id",-1))
		if setup_id >= 0 and setup_id < best_setup_id:
			best_setup_id = setup_id
			best = candidate
		elif best == null and setup_id < 0:
			best = candidate
	return best


func _find_character_by_setup_id(setup_id:int) -> ball:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if candidate.Type != ball.Ball_Type.Ball:
			continue
		if int(candidate.get_meta("battle_setup_id",-1)) == setup_id:
			return candidate
	return null


func _reset_statistics() -> void:
	_session_time = 0.0
	_life_elapsed = 0.0
	_best_survival = 0.0
	_next_survival_reward = SURVIVE_STEP_SECONDS
	_score = 0.0
	_dodges = 0
	_near_misses = 0
	_hits_taken = 0
	_deaths = 0
	_damage_dealt = 0.0
	_damage_taken = 0.0
	_peak_burst_1s = 0.0
	_outgoing_samples.clear()
	_incoming_samples.clear()
	_projectile_tracks.clear()
	_clear_feed()
	_last_health = float(_focus.health) if _focus != null and is_instance_valid(_focus) else -1.0
	_last_focus_energy = _read_focus_energy()
	_was_dead = _is_focus_dead() if _focus != null and is_instance_valid(_focus) else false


func _on_game_setting_changed(setting:String,value:Variant) -> void:
	if setting not in ["Training_Mode","Training_Mode_Type"]:
		return
	var enabled:bool = Game.is_training_mode() and Game.get_training_mode_type() == "manual"
	visible = enabled
	if enabled:
		_focus = null
		_focus_setup_id = -1
		_reset_statistics()
		_refresh_focus(true)
	else:
		_projectile_tracks.clear()
		_clear_feed()


func _on_language_changed(_locale:String) -> void:
	_refresh_all_text()


func _on_training_damage_resolved(source:Node,target:Node,actual_health_damage:float) -> void:
	if not Game.is_training_mode() or Game.get_training_mode_type() != "manual" or _focus == null or not is_instance_valid(_focus):
		return
	var amount:float = maxf(actual_health_damage,0.0)
	if amount <= 0.0:
		return

	if target == _focus:
		_record_incoming_damage(amount,true)
		_mark_nearest_projectile_hit()
		_last_health = float(_focus.health)
		# 致死伤害可能同一帧就开始离树，立即检查一次避免漏掉死亡扣分。
		_update_death_state()

	if _source_belongs_to_focus(source):
		_record_outgoing_damage(amount)


func _source_belongs_to_focus(source:Node) -> bool:
	if source == null or _focus == null:
		return false
	var current:Node = source
	for _i:int in range(5):
		if current == _focus:
			return true
		if not current is ball:
			break
		var owner_ball:ball = current as ball
		if owner_ball.Master == null or not is_instance_valid(owner_ball.Master):
			break
		current = owner_ball.Master
	return false


func _record_incoming_damage(amount:float,count_hit:bool) -> void:
	_damage_taken += amount
	_incoming_samples.append({"t":_session_time,"damage":amount})
	if count_hit:
		_hits_taken += 1
		_award(SCORE_HIT,"TRAINING_RULE_HIT", "-%d HP" % int(round(amount)))


func _record_outgoing_damage(amount:float) -> void:
	_damage_dealt += amount
	_outgoing_samples.append({"t":_session_time,"damage":amount})

	# 每 1 点实际伤害都立即产生积分；没有“先攒够 N 点伤害才得分”的门槛。
	# 例如：1 伤害 = +0.04，14 伤害 = +0.56，22 伤害 = +0.88。
	var damage_score:float = amount * SCORE_PER_DAMAGE_POINT
	_award(
		damage_score,
		"TRAINING_EVENT_DAMAGE",
		"%s DMG" % _format_damage_amount(amount)
	)


func _update_health_fallback() -> void:
	if _focus == null or not is_instance_valid(_focus):
		return
	var now_health:float = float(_focus.health)
	if _last_health < 0.0:
		_last_health = now_health
		return
	if now_health < _last_health - 0.01:
		# 某些训练工具直接调用 take_damage，不经过 hitbox 的统一 signal；这里兜底补统计。
		_record_incoming_damage(_last_health - now_health,true)
		_mark_nearest_projectile_hit()
	_last_health = now_health


func _focus_is_speedster() -> bool:
	if _focus == null or not is_instance_valid(_focus):
		return false
	# 不依赖显示名/翻译名判断，避免语言或场景命名改变后失效。
	return _focus.has_method("rl_get_training_snapshot") and _has_property(_focus,"energy")


func _read_focus_energy() -> float:
	if not _focus_is_speedster():
		return -1.0
	return maxf(float(_focus.get("energy")),0.0)


func _update_speedster_energy_score() -> void:
	var energy_now:float = _read_focus_energy()
	if energy_now < 0.0:
		_last_focus_energy = -1.0
		return
	if _last_focus_energy < 0.0:
		_last_focus_energy = energy_now
		return

	var energy_lost:float = maxf(_last_focus_energy - energy_now,0.0)
	if energy_lost > 0.001:
		_award(
			energy_lost * SCORE_SPEEDSTER_ENERGY_PER_POINT,
			"TRAINING_EVENT_ENERGY_USED",
			"%s EN" % _format_damage_amount(energy_lost)
		)
	# 回能不加分，只更新基准；这样无法靠“先乱耗再回满”刷分。
	_last_focus_energy = energy_now


func _has_property(object:Object,property_name:String) -> bool:
	# V431 性能：按脚本缓存属性名集合（classes/property_index.gd），不再逐次 get_property_list()。
	return PROPERTY_INDEX.has_property(object,property_name)


const PROPERTY_INDEX = preload("res://classes/property_index.gd")


func _update_death_state() -> void:
	var dead_now:bool = _is_focus_dead()
	if dead_now and not _was_dead:
		_deaths += 1
		_best_survival = maxf(_best_survival,_life_elapsed)
		_award(SCORE_DEATH,"TRAINING_RULE_DEATH")
		_life_elapsed = 0.0
		_next_survival_reward = SURVIVE_STEP_SECONDS
	elif not dead_now and _was_dead:
		_life_elapsed = 0.0
		_next_survival_reward = SURVIVE_STEP_SECONDS
	_was_dead = dead_now


func _is_focus_dead() -> bool:
	if _focus == null or not is_instance_valid(_focus):
		return false
	if _focus.health <= 0:
		return true
	return _focus.state_machine != null and _focus.state_machine.current_state == ball.State.Die


func _prune_damage_samples() -> void:
	var keep_from:float = _session_time - SHORT_WINDOW - 0.25
	while not _outgoing_samples.is_empty() and float(_outgoing_samples[0].get("t",0.0)) < keep_from:
		_outgoing_samples.pop_front()
	while not _incoming_samples.is_empty() and float(_incoming_samples[0].get("t",0.0)) < keep_from:
		_incoming_samples.pop_front()
	_peak_burst_1s = maxf(_peak_burst_1s,_sum_samples(_outgoing_samples,BURST_WINDOW))


func _sum_samples(samples:Array[Dictionary],window:float) -> float:
	var from_time:float = _session_time - window
	var total:float = 0.0
	for sample:Dictionary in samples:
		if float(sample.get("t",0.0)) >= from_time:
			total += float(sample.get("damage",0.0))
	return total


func _update_projectile_dodges() -> void:
	if _focus == null or not is_instance_valid(_focus) or _is_focus_dead():
		_projectile_tracks.clear()
		return

	var current_ids:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var projectile:ball = node as ball
		if projectile == _focus:
			continue
		if projectile.Type != ball.Ball_Type.Shooter and projectile.Type != ball.Ball_Type.Shooter_with_Health:
			continue
		if _source_belongs_to_focus(projectile):
			continue
		var projectile_id:int = projectile.get_instance_id()
		var already_tracked:bool = _projectile_tracks.has(projectile_id)
		var distance:float = projectile.global_position.distance_to(_focus.global_position)
		if distance > PROJECTILE_TRACK_MAX_DISTANCE and not already_tracked:
			continue
		# 一旦已经进入跟踪，就继续观察它越过角色后的离开过程；
		# 否则投射物飞过目标后朝向点积会翻负，永远无法结算“成功躲避”。
		if not already_tracked and not _projectile_targets_focus(projectile,distance):
			continue

		current_ids[projectile_id] = true
		var contact_radius:float = _estimate_body_radius(_focus) + _estimate_body_radius(projectile)
		var dodge_radius:float = contact_radius + DODGE_EXTRA_RADIUS
		var near_radius:float = contact_radius + NEAR_MISS_EXTRA_RADIUS
		var release_radius:float = dodge_radius + DODGE_RELEASE_EXTRA

		var rec:Dictionary = _projectile_tracks.get(projectile_id,{})
		if rec.is_empty():
			rec = {
				"instance_id":projectile_id,
				"min_distance":distance,
				"last_distance":distance,
				"entered":distance <= dodge_radius,
				"hit":false,
				"dodge_radius":dodge_radius,
				"near_radius":near_radius,
				"release_radius":release_radius,
			}
		else:
			rec["min_distance"] = minf(float(rec.get("min_distance",distance)),distance)
			if distance <= dodge_radius:
				rec["entered"] = true

		var entered:bool = bool(rec.get("entered",false))
		var min_distance:float = float(rec.get("min_distance",distance))
		var last_distance:float = float(rec.get("last_distance",distance))
		if (
			entered
			and not bool(rec.get("hit",false))
			and distance >= release_radius
			and distance > last_distance
			and distance > min_distance + DODGE_RELEASE_EXTRA * 0.55
		):
			_finalize_dodge(rec)
			_projectile_tracks.erase(projectile_id)
			continue

		rec["last_distance"] = distance
		_projectile_tracks[projectile_id] = rec

	# 本帧没有再次扫描到的已跟踪投射物，视为已销毁/离树/不再属于有效投射物。
	# 跟踪记录只保存 instance_id，不保存 Node 引用，避免对象 free() 后字典里留下悬空引用。
	for raw_id:Variant in _projectile_tracks.keys().duplicate():
		var projectile_id:int = int(raw_id)
		if current_ids.has(projectile_id):
			continue
		var rec:Dictionary = _projectile_tracks[raw_id]
		if bool(rec.get("entered",false)) and not bool(rec.get("hit",false)):
			_finalize_dodge(rec)
		_projectile_tracks.erase(raw_id)


func _projectile_targets_focus(projectile:ball,distance:float) -> bool:
	if projectile.has_meta("manual_training_target_id"):
		return int(projectile.get_meta("manual_training_target_id",-1)) == _focus.get_instance_id()
	if projectile.Target_Enemy == _focus or projectile.Nearest_Enemy == _focus:
		return true
	if projectile.Team == _focus.Team and not projectile.Team.is_empty():
		return false
	if distance <= 0.001 or projectile.direction.length_squared() <= 0.0001:
		return false
	var toward:Vector2 = (_focus.global_position - projectile.global_position).normalized()
	return projectile.direction.normalized().dot(toward) >= 0.42


func _estimate_body_radius(node:ball) -> float:
	if node == null or not is_instance_valid(node):
		return 8.0
	if node.has_meta("manual_training_radius"):
		return maxf(float(node.get_meta("manual_training_radius",8.0)),3.0)
	if node.collision_shape_2d != null and node.collision_shape_2d.shape != null:
		var shape:Shape2D = node.collision_shape_2d.shape
		if shape is CircleShape2D:
			return maxf((shape as CircleShape2D).radius,3.0)
		if shape is RectangleShape2D:
			return maxf(minf((shape as RectangleShape2D).size.x,(shape as RectangleShape2D).size.y) * 0.5,3.0)
		if shape is CapsuleShape2D:
			return maxf((shape as CapsuleShape2D).radius,3.0)
	return 8.0


func _mark_nearest_projectile_hit() -> void:
	if _focus == null:
		return
	var best_id:int = -1
	var best_distance:float = INF
	for raw_id:Variant in _projectile_tracks.keys():
		var projectile_id:int = int(raw_id)
		if not is_instance_id_valid(projectile_id):
			continue
		var projectile_object:Object = instance_from_id(projectile_id)
		if projectile_object == null or not projectile_object is Node2D:
			continue
		var rec:Dictionary = _projectile_tracks[raw_id]
		var distance:float = (projectile_object as Node2D).global_position.distance_to(_focus.global_position)
		var allowed:float = float(rec.get("dodge_radius",36.0)) + 12.0
		if distance <= allowed and distance < best_distance:
			best_distance = distance
			best_id = int(raw_id)
	if best_id >= 0 and _projectile_tracks.has(best_id):
		var rec:Dictionary = _projectile_tracks[best_id]
		rec["hit"] = true
		_projectile_tracks[best_id] = rec


func _finalize_dodge(rec:Dictionary) -> void:
	var min_distance:float = float(rec.get("min_distance",INF))
	var near_radius:float = float(rec.get("near_radius",0.0))
	_dodges += 1
	if min_distance <= near_radius:
		_near_misses += 1
		_award(
			SCORE_DODGE + SCORE_NEAR_MISS_BONUS,
			"TRAINING_EVENT_NEAR_MISS",
			"%.1fpx" % min_distance
		)
	else:
		_award(SCORE_DODGE,"TRAINING_RULE_DODGE","%.1fpx" % min_distance)


func _format_score_amount(value:float) -> String:
	var rounded_value:float = roundf(value)
	if is_equal_approx(value,rounded_value):
		return str(int(rounded_value))
	if absf(value) < 1.0:
		return "%.2f" % value
	return "%.1f" % value


func _format_damage_amount(value:float) -> String:
	var rounded_value:float = roundf(value)
	if is_equal_approx(value,rounded_value):
		return str(int(rounded_value))
	return "%.1f" % value


func _award(delta_score:float,text_key:String,detail:String = "") -> void:
	if is_zero_approx(delta_score):
		return
	_score += delta_score
	var description:String = Game.t(text_key)
	if not detail.is_empty():
		description += "  " + detail
	_push_feed(delta_score,description)
	_refresh_right_text()


func _feed_capacity() -> int:
	if _feed_area == null or _feed_area.size.y <= 0.0:
		return 1
	return maxi(int(floor(_feed_area.size.y / FEED_LINE_HEIGHT)),1)


func _recompute_feed_targets() -> void:
	var capacity:int = _feed_capacity()
	var overflow:int = maxi(_feed_entries.size() - capacity,0)
	for i:int in range(_feed_entries.size()):
		var entry:Dictionary = _feed_entries[i]
		entry["target_y"] = float(i - overflow) * FEED_LINE_HEIGHT
		_feed_entries[i] = entry


func _push_feed(delta_score:float,description:String) -> void:
	if _feed_area == null:
		return

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",FEED_FONT_SIZE)
	label.add_theme_color_override(
		"font_color",
		Color(0.55,1.0,0.70,1.0) if delta_score > 0 else Color(1.0,0.55,0.55,1.0)
	)
	label.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.95))
	label.add_theme_constant_override("outline_size",1)
	var score_text:String = _format_score_amount(delta_score)
	label.text = ("+" + score_text if delta_score > 0.0 else score_text) + "  " + description
	label.size = Vector2(_feed_area.size.x,FEED_LINE_HEIGHT)
	_feed_area.add_child(label)

	# 没填满时：第 1 条就在最上面，后续逐行往下。
	# 填满后：新条目直接出现在最底行，旧条目只在“有新积分产生”时整体上移。
	var capacity:int = _feed_capacity()
	var size_after_append:int = _feed_entries.size() + 1
	var overflow_after_append:int = maxi(size_after_append - capacity,0)
	var new_target_y:float = float(size_after_append - 1 - overflow_after_append) * FEED_LINE_HEIGHT
	label.position = Vector2(0.0,new_target_y)
	label.modulate.a = 1.0
	_feed_entries.append({
		"label":label,
		"y":new_target_y,
		"target_y":new_target_y,
	})
	_recompute_feed_targets()

	# 极端高倍训练可能在一个真实帧内产生大量事件；仅保留少量滚出缓冲，
	# 避免 UI 节点无限堆积。这个限制不会改变可见区域中的正常滚动行为。
	var max_buffer:int = maxi(FEED_MAX_BUFFER,_feed_capacity() + 8)
	while _feed_entries.size() > max_buffer:
		var oldest:Dictionary = _feed_entries.pop_front()
		var old_label:Label = oldest.get("label") as Label
		if old_label != null and is_instance_valid(old_label):
			old_label.queue_free()
	_recompute_feed_targets()


func _update_feed_animation() -> void:
	if _feed_area == null:
		return

	var now_msec:int = Time.get_ticks_msec()
	var real_delta:float = 0.0
	if _last_feed_update_msec > 0:
		real_delta = clampf(float(now_msec - _last_feed_update_msec) / 1000.0,0.0,0.10)
	_last_feed_update_msec = now_msec

	_recompute_feed_targets()

	for i:int in range(_feed_entries.size() - 1,-1,-1):
		var entry:Dictionary = _feed_entries[i]
		var label:Label = entry.get("label") as Label
		if label == null or not is_instance_valid(label):
			_feed_entries.remove_at(i)
			continue

		var y:float = float(entry.get("y",label.position.y))
		var target_y:float = float(entry.get("target_y",y))
		if real_delta > 0.0:
			y = move_toward(y,target_y,FEED_STACK_SHIFT_SPEED * real_delta)
		entry["y"] = y
		_feed_entries[i] = entry

		label.position = Vector2(0.0,y)
		label.size.x = _feed_area.size.x

		# 只有真正被新消息挤出顶部的条目才渐隐。
		# 未填满时，已有条目不会因为“活得久”而自己漂移或消失。
		var top_alpha:float = 1.0
		if target_y < 0.0 or y < 0.0:
			top_alpha = clampf((y + FEED_LINE_HEIGHT) / FEED_LINE_HEIGHT,0.0,1.0)
		label.modulate.a = top_alpha
		if target_y < 0.0 and y <= -FEED_LINE_HEIGHT + 0.05:
			label.queue_free()
			_feed_entries.remove_at(i)
			continue

	# 删除滚出项后，剩余条目的槽位重新收敛到 0..bottom。
	_recompute_feed_targets()


func _clear_feed() -> void:
	for entry:Dictionary in _feed_entries:
		var label:Label = entry.get("label") as Label
		if label != null and is_instance_valid(label):
			label.queue_free()
	_feed_entries.clear()
	_last_feed_update_msec = 0


func _refresh_all_text() -> void:
	if _feed_title != null:
		_feed_title.text = Game.t("TRAINING_HUD_SCORE_FLOW")
	_refresh_left_text()
	_refresh_right_text()
	_queue_content_fit()


func _refresh_left_text() -> void:
	if _left_text == null:
		return
	if _focus == null or not is_instance_valid(_focus):
		_left_text.text = "[b]%s[/b]\n%s" % [
			Game.t("TRAINING_HUD_TITLE"),
			Game.t("TRAINING_HUD_WAITING")
		]
		_queue_content_fit()
		return

	var role_name:String = _character_display_name(_focus)
	var short_out:float = _sum_samples(_outgoing_samples,SHORT_WINDOW)
	var short_in:float = _sum_samples(_incoming_samples,SHORT_WINDOW)
	var current_burst:float = _sum_samples(_outgoing_samples,BURST_WINDOW)
	_peak_burst_1s = maxf(_peak_burst_1s,current_burst)
	var attempts:int = _dodges + _hits_taken
	var dodge_rate:float = 100.0 * float(_dodges) / float(attempts) if attempts > 0 else 0.0

	_left_text.text = (
		"[b]%s[/b]  %s\n" +
		"%s %.1fs  |  %s %.1fs\n" +
		"%s %d  |  %s %d  |  %s %d\n" +
		"%s %.0f%%  |  %s %d\n" +
		"%s %.0f  |  %s %.0f\n" +
		"%s %.0f  |  %s %.0f\n" +
		"%s %d/%d"
	) % [
		Game.t("TRAINING_HUD_ROLE"),_escape_bbcode(role_name),
		Game.t("TRAINING_HUD_SURVIVAL"),_life_elapsed,Game.t("TRAINING_HUD_BEST"),_best_survival,
		Game.t("TRAINING_HUD_DODGES"),_dodges,Game.t("TRAINING_HUD_NEAR_MISS"),_near_misses,Game.t("TRAINING_HUD_HITS"),_hits_taken,
		Game.t("TRAINING_HUD_DODGE_RATE"),dodge_rate,Game.t("TRAINING_HUD_DEATHS"),_deaths,
		Game.t("TRAINING_HUD_DAMAGE_3S"),short_out,Game.t("TRAINING_HUD_TAKEN_3S"),short_in,
		Game.t("TRAINING_HUD_BURST"),_peak_burst_1s,Game.t("TRAINING_HUD_TOTAL_DAMAGE"),_damage_dealt,
		Game.t("TRAINING_HUD_HP"),int(_focus.health),int(_focus.Max_health)
	]
	_queue_content_fit()


func _refresh_right_text() -> void:
	if _right_text == null:
		return
	var score_rate_text:String = "--"
	if _session_time >= 10.0:
		var score_per_minute:float = _score * 60.0 / _session_time
		score_rate_text = "%s %s" % [
			_format_score_amount(score_per_minute),
			Game.t("TRAINING_HUD_SCORE_PER_MINUTE")
		]

	var lines:Array[String] = [
		"[b]%s: %s[/b]" % [Game.t("TRAINING_HUD_SCORE"),_format_score_amount(_score)],
		"%s: %s" % [Game.t("TRAINING_HUD_SCORE_RATE"),score_rate_text],
		"%s  [color=#78F0A0]+%d[/color]" % [Game.t("TRAINING_RULE_DODGE"),SCORE_DODGE],
		"%s  [color=#78F0A0]+%d[/color]" % [Game.t("TRAINING_RULE_NEAR_MISS"),SCORE_NEAR_MISS_BONUS],
		"%s  [color=#78F0A0]+%s[/color]" % [Game.t("TRAINING_RULE_DAMAGE"),_format_score_amount(SCORE_PER_DAMAGE_POINT)],
		"%s  [color=#78F0A0]+%s[/color]" % [Game.t("TRAINING_RULE_SURVIVE"),_format_score_amount(SCORE_SURVIVE_STEP)],
		"%s  [color=#FF8C8C]%d[/color]" % [Game.t("TRAINING_RULE_HIT"),SCORE_HIT],
		"%s  [color=#FF8C8C]%d[/color]" % [Game.t("TRAINING_RULE_DEATH"),SCORE_DEATH],
	]
	if _focus_is_speedster():
		lines.append(
			"%s  [color=#FF8C8C]%s[/color]" % [
				Game.t("TRAINING_RULE_SPEEDSTER_ENERGY"),
				_format_score_amount(SCORE_SPEEDSTER_ENERGY_PER_POINT)
			]
		)
	var right_text:String = ""
	for line:String in lines:
		if not right_text.is_empty():
			right_text += "\n"
		right_text += line
	_right_text.text = right_text
	_queue_content_fit()


func _character_display_name(character:ball) -> String:
	var raw_name:String = ""
	if not character.scene_file_path.is_empty():
		raw_name = character.scene_file_path.get_file().get_basename()
	if raw_name.is_empty():
		raw_name = str(character.name)
	return Game.t(raw_name).replace("_"," ")


func _escape_bbcode(text:String) -> String:
	return text.replace("[","[lb]")
