extends Control

#引用
@onready var team: Control = $Team

var team_set_button_tem := preload("res://ui/team_set_button.tscn")
const MAP_BACKGROUND_THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
const BATTLE_MUSIC = preload("res://global/battle_music.gd")
@onready var team_box: VBoxContainer = $Team/Team/Team_Inner/VBoxContainer
@onready var char_box: VBoxContainer = $Team/Char/Char_Inner/CharScroll/VBoxContainer
@onready var char_scroll: ScrollContainer = $Team/Char/Char_Inner/CharScroll
@onready var char_search: LineEdit = $Team/Char/Char_Inner/Search
@onready var offset_timer: Timer = $Offset_Timer

# 队伍按钮使用 Toggle + ButtonGroup 作为唯一状态来源。
# allow_unpress=true 时，再点一次当前队伍可以真正回到“无队伍”。
var team_button_group:ButtonGroup = ButtonGroup.new()

# 运行时设置 UI。重打已提升为顶部工具栏正式功能，不再属于设置页。
var language_button:Button
var _battle_record_controls:Node

#========================================================
# 竖屏 UI 布局 + 原版鼠标视差
#========================================================

@onready var settings_bar: PanelContainer = $Settings
@onready var toolbar_game_setting_button:Button = $Settings/HBoxContainer/Game_Setting
@onready var toolbar_team_button:Button = $Settings/HBoxContainer/Team
@onready var toolbar_reset_button:Button = $Settings/HBoxContainer/Reset
@onready var toolbar_rematch_button:Button = $Settings/HBoxContainer/Rematch
@onready var toolbar_map_button:Button = $Settings/HBoxContainer/Map
@onready var toolbar_multiplayer_button:Button = $Settings/HBoxContainer/MultiPlayer
@onready var team_create_button:Button = $Team/Team/CreateButton

# 这两个位置不是写死坐标，而是在 apply_portrait_layout() 里
# 根据当前 Viewport 宽度、顶部工具栏尺寸自动计算。
var ori_position:Vector2 = Vector2.ZERO
var Team_ori_position:Vector2 = Vector2.ZERO
var _layout_ready:bool = false
var _connection_refresh_elapsed:float = 0.0

#偏移动画
@onready var offset := Vector2.ZERO
@export var max_offset := 2.0
#func _on_offset_timer_timeout() -> void:
	#offset = Vector2(randf_range(-max_offset,max_offset),randf_range(-max_offset,max_offset))

# 保留原版“整个 UI 和 Team 层有不同深度”的鼠标移动效果。
# 现在用归一化鼠标位置，不会因为从 1080 高变成 1920 高就移动过头。
@export var ui_parallax_enabled:bool = true
@export var root_parallax_amount:Vector2 = Vector2(30.0, 24.0)
@export var team_parallax_amount:Vector2 = Vector2(42.0, 30.0)
@export_range(0.01, 1.0, 0.01) var lerp_weight:float = 0.08

# 1080 宽时会自动使用 3x；720 宽使用 2x；更窄使用 1x。
# 始终用整数倍缩放，避免像素 UI/字体因为 2.005、0.813 等缩放变糊。
@export var max_integer_ui_scale:int = 3
@export var ui_top_margin:float = 12.0

func _notification(what:int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		call_deferred("_refresh_runtime_translations")


func _refresh_runtime_translations() -> void:
	if not is_node_ready():
		return

	# 只扫描 Control 自己的 UI 分支，不再递归整棵 World。
	# 对战时整棵场景包含大量角色/特效，旧版每次切语言都会遍历它们，因此会明显卡顿。
	_refresh_static_ui_texts(self)

	var world:World = get_tree().current_scene
	if world == null:
		return

	now_team.text = Game.ui_t("UI_NOW_TEAM") + " " + (Game.ui_t(world.now_choose_team) if not world.now_choose_team.is_empty() else Game.ui_t("UI_NONE"))
	now_char.text = Game.ui_t("UI_NOW_CHAR") + " " + (Game.ui_t(world.now_choose_char) if not world.now_choose_char.is_empty() else Game.ui_t("UI_NONE"))
	now_type.text = Game.ui_t("UI_NOW_TYPE") + " " + Game.ui_t(world.return_now_char_type())

	if is_instance_valid(language_button):
		language_button.text = Game.ui_t("UI_LANGUAGE") + ": " + Game.get_language_display_name()

	if is_instance_valid(toolbar_rematch_button):
		toolbar_rematch_button.text = Game.ui_t("UI_REMATCH")
		toolbar_rematch_button.tooltip_text = Game.ui_t("UI_REMATCH_TOOLTIP")

	if is_instance_valid(_battle_record_controls):
		_battle_record_controls.refresh()

	_refresh_settings_category_texts()


func _refresh_static_ui_texts(node:Node) -> void:
	# 下拉菜单要翻译每一个 item，而不是只改 OptionButton 当前显示文字。
	if node is OptionButton:
		var option:OptionButton = node
		var option_sources:Array = []
		if option.has_meta("_translation_option_sources"):
			option_sources = option.get_meta("_translation_option_sources")
		else:
			for index in range(option.item_count):
				var item_source:String = option.get_item_text(index)
				var item_key:String = Game.resolve_translation_key(item_source)
				option_sources.append(item_key if not item_key.is_empty() else item_source)
			option.set_meta("_translation_option_sources", option_sources)
		for index in range(mini(option.item_count, option_sources.size())):
			option.set_item_text(index, Game.translate_ui_text(str(option_sources[index])))
	# 选择按钮的显示文字可以翻译，但内部选择值必须保留原始资源/文件夹名字。
	elif node is Button and node.has_meta("choice_value"):
		(node as Button).text = Game.ui_t(str(node.get_meta("choice_value")))
	elif node is Label or node is Button or node is RichTextLabel:
		if not node.has_meta("_translation_source_text"):
			var source_text:String = str(node.get("text"))
			var canonical_key:String = Game.resolve_translation_key(source_text)
			# 即使当前 CSV 还没有完整 key，也保存最初文本；
			# 这样后续热更新 translations.csv 后还能重新翻译。
			node.set_meta(
				"_translation_source_text",
				canonical_key if not canonical_key.is_empty() else source_text
			)

		if node.has_meta("_translation_source_text"):
			node.set(
				"text",
				Game.translate_ui_text(str(node.get_meta("_translation_source_text")))
			)

	if node is LineEdit:
		var line_edit:LineEdit = node
		if not line_edit.has_meta("_translation_source_placeholder"):
			var placeholder:String = line_edit.placeholder_text
			var placeholder_key:String = Game.resolve_translation_key(placeholder)
			line_edit.set_meta(
				"_translation_source_placeholder",
				placeholder_key if not placeholder_key.is_empty() else placeholder
			)
		if line_edit.has_meta("_translation_source_placeholder"):
			line_edit.placeholder_text = Game.translate_ui_text(
				str(line_edit.get_meta("_translation_source_placeholder"))
			)

	for child in node.get_children():
		_refresh_static_ui_texts(child)


func _ready() -> void:
	_ensure_battle_record_controls()
	team_button_group.allow_unpress = true
	var tree = get_tree()
	var world:World = tree.current_scene
	await world.ready

	# UI 所在 CanvasLayer 保持在游戏画面上方。
	var canvas_parent := get_parent()
	if canvas_parent is CanvasLayer:
		canvas_parent.layer = 100

	# 像素风 UI 使用最近邻。
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	Create_char_buts()
	if not char_search.text_changed.is_connected(_on_character_search_changed):
		char_search.text_changed.connect(_on_character_search_changed)
	char_search.set_meta("_translation_source_placeholder", "UI_SEARCH_CHARACTER")
	char_search.placeholder_text = Game.ui_t("UI_SEARCH_CHARACTER")
	set_map_buts()
	add_game_set()
	if not Game.game_setting_changed.is_connected(_on_global_game_setting_changed):
		Game.game_setting_changed.connect(_on_global_game_setting_changed)
	if not Game.language_changed.is_connected(_on_ui_language_changed):
		Game.language_changed.connect(_on_ui_language_changed)
	if not Game.network_state_changed.is_connected(_on_network_state_changed):
		Game.network_state_changed.connect(_on_network_state_changed)
	if not Game.room_list_changed.is_connected(_on_room_list_changed):
		Game.room_list_changed.connect(_on_room_list_changed)
	_refresh_runtime_translations()
	Game.Set_Ui_drager(team)
	Game.Set_Ui_drager(map)
	# 设置面板现在内部使用 ScrollContainer。旧的 Set_Ui_drager 会把整个 VBoxContainer
	# 拖来拖去，和滚动容器冲突；add_game_set() 会绑定专用的中键滚动。
	# V126：多人玩家列表固定在多人面板内部，禁止再被 UI 拖动到屏幕外。
	Game.Set_Ui_sfx(self)

	map.hide()
	team.hide()
	game_setting.hide()
	multi_player.hide()

	# 恢复原场景的“中心定位节点”结构，只把小数缩放改成整数缩放。
	_prepare_pixel_crisp_controls()

	# 等 Theme / Container 完成尺寸计算后再定位。
	await get_tree().process_frame
	await get_tree().process_frame
	# 角色列表与设置列表共用同一套像素滚动条，避免选人界面出现 Godot 默认滚动条。
	_style_pixel_scroll_container(char_scroll)
	_configure_character_middle_drag()
	# 选地图列表同样使用像素滚动条，并支持中键按住上下拖动。
	_style_pixel_scroll_container(map_scroll)
	_configure_map_middle_drag()
	_style_character_search()
	apply_portrait_layout()
	_refresh_multiplayer_permissions_ui()

	if not get_viewport().size_changed.is_connected(apply_portrait_layout):
		get_viewport().size_changed.connect(apply_portrait_layout)

	visible = true
	settings_bar.visible = true

	_refresh_multiplayer_address_label()
	change_connect_state()


#========================================================
# 保留原 UI 构图，只修掉会导致文字模糊的小数缩放
#========================================================
func _prepare_pixel_crisp_controls() -> void:
	# Team / Char / Map 原先纵向 scale=0.8133334，文字会被非整数采样。
	# 竖屏高度足够，直接恢复 1x，面板会稍微高一点但更清晰。
	$Team/Team.scale = Vector2.ONE
	$Team/Char.scale = Vector2.ONE
	map.scale = Vector2.ONE
	player_list.scale = Vector2.ONE

	# Multiplayer 原先还有 0.72、1.2551532 等小数缩放。
	multi_player.scale = Vector2.ONE
	$MultiPlayer/MultiPlayer_Inner/HBoxContainer.scale = Vector2.ONE

	# 分类切换箭头与搜索框放在同一行：
	# [大左箭头]  间距  [搜索框]  间距  [大右箭头]
	# 不再通过 Control.scale 硬放大小纹理，而是扩大真正的按钮矩形，
	# 这样视觉尺寸与鼠标可点击区域一致。
	_layout_character_category_header()


func _layout_character_category_header() -> void:
	if not is_instance_valid(char_search):
		return

	var left_button:TextureButton = $Team/Char/Left
	var right_button:TextureButton = $Team/Char/Right

	# 搜索框保持改箭头之前的完整尺寸，不再为了箭头缩窄。
	# Char_Inner 位于 Char 的 (7,7)，搜索框在内层左右各留 5px，
	# 因此它的视觉范围约为 Char.x = 12..108，尺寸为 96x24。
	char_search.offset_left = 5.0
	char_search.offset_top = 5.0
	char_search.offset_right = -5.0
	char_search.offset_bottom = 29.0

	for button:TextureButton in [left_button, right_button]:
		button.scale = Vector2.ONE
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		button.custom_minimum_size = Vector2(18.0, 24.0)
		button.size = Vector2(18.0, 24.0)
		button.focus_mode = Control.FOCUS_NONE

	# 箭头不占搜索框宽度，直接放到整个角色面板左右外侧。
	# 搜索框左边缘约 x=12、右边缘约 x=108；这里各留约 2px 空隙。
	# y=12 与搜索框顶部完全对齐，高度同为 24px。
	left_button.position = Vector2(-8.0, 12.0)
	right_button.position = Vector2(110.0, 12.0)


#========================================================
# 1080x1920 / 其他竖屏尺寸自动适配
#
# 关键点：
# 不再把根 Control 改成 Full Rect，也不把所有面板强行放到右上角。
# 保留你原来 control.tscn 的相对布局：
#   - Toolbar 在根节点上方
#   - Team 在左右两侧
#   - Map / Settings / Multiplayer 在中间
# 只把“根节点原点”自动移动到屏幕顶部区域。
#========================================================
func apply_portrait_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	# 你的原 UI 横向总宽度大约是 360 个本地像素。
	# 1080 / 360 = 3，所以 1080 竖屏正好是 3x。
	var integer_scale:int = int(floor(viewport_size.x / 360.0))
	integer_scale = clampi(integer_scale, 1, max_integer_ui_scale)
	var ui_scale := float(integer_scale)

	# 恢复根节点为原本的“中心锚点 + 零尺寸定位节点”。
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	scale = Vector2(ui_scale, ui_scale)

	# Team 本身就是一个零尺寸定位节点；每次重排先恢复到根原点。
	team.position = Vector2.ZERO

	# 根据 Settings 实际宽度精确居中，不假设按钮数量/文字长度永远不变。
	# root_origin + settings.position * scale = 工具栏左上角。
	var toolbar_center_local_x:float = settings_bar.position.x + settings_bar.size.x * 0.5
	var root_x:float = viewport_size.x * 0.5 - toolbar_center_local_x * ui_scale
	var root_y:float = ui_top_margin - settings_bar.position.y * ui_scale

	global_position = Vector2(round(root_x), round(root_y))
	ori_position = global_position

	# 记录 Team 没有视差时的基准世界位置。
	Team_ori_position = team.global_position
	_layout_ready = true

	# V126：多人面板总宽度必须始终小于 360 个本地像素，玩家列表固定放到连接区下方，
	# 不再使用旧版 x=146..244 的右侧外挂面板。这样 720/1080 竖屏都不会越出右边界。
	_layout_multiplayer_panel()

	# 最大特效预览跟随当前窗口与整数 UI 缩放重新计算，避免旋转/改分辨率后超出屏幕。
	if current_settings_category == "effects" and _effect_preview_size_preset == "maximum" and is_instance_valid(game_setting) and game_setting.visible:
		call_deferred("_apply_effect_settings_window_size", _effect_preview_size_preset)


func _get_mouse_normalized() -> Vector2:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO

	var mouse_pos := get_viewport().get_mouse_position()
	var normalized := Vector2(
		mouse_pos.x / viewport_size.x,
		mouse_pos.y / viewport_size.y
	)
	normalized = (normalized - Vector2(0.5, 0.5)) * 2.0
	return normalized.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
func get_ip() -> String:
	# 公网 IP 只是给“异地互联网联机”参考；局域网联机不依赖这个 HTTP 请求。
	var http := HTTPRequest.new()
	add_child(http)
	var error:Error = http.request("https://api.ip.sb/ip")
	if error != OK:
		http.queue_free()
		return Game.ui_t("UI_NETWORK_UNAVAILABLE")
	var response:Array = await http.request_completed
	http.queue_free()
	if response.size() >= 4 and int(response[1]) == 200:
		return (response[3] as PackedByteArray).get_string_from_utf8().strip_edges()
	return Game.ui_t("UI_NETWORK_UNAVAILABLE")


func _refresh_multiplayer_address_label() -> void:
	if not is_instance_valid(ip_label):
		return
	var lan_ip:String = Game.get_preferred_lan_address()
	ip_label.text = (
		Game.ui_t("UI_LAN_IP") + lan_ip
		+ "   " + Game.ui_t("UI_PORT") + ": " + str(Game.get_network_port())
		+ "\n" + Game.ui_t("UI_PUBLIC_IP") + Game.ui_t("UI_NETWORK_QUERYING")
	)
	var public_ip:String = await get_ip()
	if not is_instance_valid(ip_label):
		return
	ip_label.text = (
		Game.ui_t("UI_LAN_IP") + lan_ip
		+ "   " + Game.ui_t("UI_PORT") + ": " + str(Game.get_network_port())
		+ "\n" + Game.ui_t("UI_PUBLIC_IP") + public_ip
	)


func _layout_multiplayer_panel() -> void:
	if not is_instance_valid(multi_player):
		return

	# 整个多人窗口固定为 258px 本地宽度；根 UI 会按 1x/2x/3x 整数缩放。
	multi_player.scale = Vector2.ONE
	multi_player.set_anchors_preset(Control.PRESET_CENTER)
	multi_player.offset_left = -129.0
	multi_player.offset_top = -74.0
	multi_player.offset_right = 129.0
	multi_player.offset_bottom = 222.0

	var inner:Panel = $MultiPlayer/MultiPlayer_Inner
	inner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	inner.offset_left = -122.0
	inner.offset_top = 8.0
	inner.offset_right = 122.0
	inner.offset_bottom = 50.0

	var row:HBoxContainer = $MultiPlayer/MultiPlayer_Inner/HBoxContainer
	row.scale = Vector2.ONE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6.0
	row.offset_top = 8.0
	row.offset_right = -6.0
	row.offset_bottom = -8.0
	row.add_theme_constant_override("separation",4)

	var server_button:Button = $MultiPlayer/MultiPlayer_Inner/HBoxContainer/Server
	var client_button:Button = $MultiPlayer/MultiPlayer_Inner/HBoxContainer/Client
	server_button.custom_minimum_size = Vector2(52.0,26.0)
	client_button.custom_minimum_size = Vector2(52.0,26.0)
	server_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	client_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	port.custom_minimum_size = Vector2(112.0,26.0)
	port.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port.set_meta("_translation_source_placeholder","UI_SERVER_ADDRESS")
	port.placeholder_text = Game.ui_t("UI_SERVER_ADDRESS")
	port.tooltip_text = Game.ui_t("UI_SERVER_ADDRESS_HINT")

	connect_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	connect_label.offset_left = -120.0
	connect_label.offset_top = 56.0
	connect_label.offset_right = 120.0
	connect_label.offset_bottom = 82.0
	connect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	connect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	ip_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ip_label.offset_left = -120.0
	ip_label.offset_top = 84.0
	ip_label.offset_right = 120.0
	ip_label.offset_bottom = 112.0
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 旧版玩家列表固定挂在右侧，横向总宽超过 360px，720 竖屏必然越界。
	# 现在作为多人窗口的下半部分固定居中。
	player_list.scale = Vector2.ONE
	player_list.set_anchors_preset(Control.PRESET_CENTER_TOP)
	player_list.offset_left = -122.0
	player_list.offset_top = 116.0
	player_list.offset_right = 122.0
	player_list.offset_bottom = 214.0

	var list_inner:Panel = $MultiPlayer/Player_list/Player_list_Inner
	list_inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	list_inner.offset_left = 6.0
	list_inner.offset_top = 6.0
	list_inner.offset_right = -6.0
	list_inner.offset_bottom = -6.0

	var list_box:VBoxContainer = $MultiPlayer/Player_list/Player_list_Inner/VBoxContainer
	list_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	list_box.offset_left = 4.0
	list_box.offset_top = 3.0
	list_box.offset_right = -4.0
	list_box.offset_bottom = -3.0
	list_box.custom_minimum_size = Vector2.ZERO


func _room_is_local_host(address:String) -> bool:
	return Game.network_role == "host" and (
		address == "127.0.0.1" or Game.get_local_ipv4_addresses().has(address)
	)


func _on_room_refresh_pressed() -> void:
	Game.request_room_scan(true)
	_refresh_multiplayer_player_list(true)


func _on_discovered_room_pressed(address:String) -> void:
	if address.is_empty() or _room_is_local_host(address):
		return
	port.text = address
	Game.join_game(address)
	change_connect_state()


func _refresh_discovered_room_browser(force:bool = false) -> void:
	if not is_instance_valid(player_list_box):
		return
	var rooms:Array[Dictionary] = Game.get_discovered_rooms()
	var room_signature:String = str(rooms)
	if (
		not force
		and player_list_box.has_meta("room_signature")
		and str(player_list_box.get_meta("room_signature")) == room_signature
	):
		return
	player_list_box.set_meta("room_signature",room_signature)
	if player_list_box.has_meta("peer_signature"):
		player_list_box.remove_meta("peer_signature")

	for child:Node in player_list_box.get_children():
		child.queue_free()

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation",4)
	player_list_box.add_child(header)

	var title := Label.new()
	title.text = Game.ui_t("UI_ROOM_LIST") + " (" + str(rooms.size()) + ")"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	var refresh := Button.new()
	refresh.text = Game.ui_t("UI_REFRESH_ROOMS")
	refresh.custom_minimum_size = Vector2(42,18)
	refresh.add_theme_font_size_override("font_size",9)
	refresh.pressed.connect(_on_room_refresh_pressed)
	header.add_child(refresh)
	Game.Set_Ui_sfx(refresh)

	if rooms.is_empty():
		var empty := Label.new()
		empty.text = Game.ui_t("UI_NO_ROOMS")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_list_box.add_child(empty)
		return

	# 这个项目只用于少量朋友联机。面板显示最近/最低延迟的前三个房间，标题仍显示真实总数。
	var visible_count:int = mini(rooms.size(),3)
	for index:int in range(visible_count):
		var room:Dictionary = rooms[index]
		var address:String = str(room.get("address",""))
		var players:int = int(room.get("players",0))
		var max_players:int = int(room.get("max_players",10))
		var ping_ms:int = int(room.get("ping_ms",-1))
		var button := Button.new()
		button.custom_minimum_size = Vector2(0,20)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",9)
		button.text = address + "  ·  " + str(players) + "/" + str(max_players)
		if ping_ms >= 0:
			button.text += "  ·  " + str(ping_ms) + "ms"
		if _room_is_local_host(address):
			button.text = "[" + Game.ui_t("UI_ROOM_LOCAL_HOST") + "]  " + button.text
			button.disabled = true
		else:
			button.tooltip_text = Game.ui_t("UI_ROOM_JOIN_HINT")
			button.pressed.connect(_on_discovered_room_pressed.bind(address))
		player_list_box.add_child(button)
		Game.Set_Ui_sfx(button)


func _refresh_multiplayer_player_list(force:bool = false) -> void:
	if not is_instance_valid(player_list_box):
		return

	var connected:bool = (
		multiplayer.has_multiplayer_peer()
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)
	# 未连接时，这块区域就是“当前找到的房间”；连接成功后切回当前房间的玩家列表。
	if not connected:
		_refresh_discovered_room_browser(force)
		return

	var peer_ids:Array[int] = Game.get_network_peer_ids()
	var local_id:int = multiplayer.get_unique_id()
	var signature:String = str(peer_ids) + ":" + str(local_id) + ":" + Game.network_role
	if (
		not force
		and player_list_box.has_meta("peer_signature")
		and str(player_list_box.get_meta("peer_signature")) == signature
	):
		return
	player_list_box.set_meta("peer_signature",signature)
	if player_list_box.has_meta("room_signature"):
		player_list_box.remove_meta("room_signature")

	for child:Node in player_list_box.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = Game.ui_t("UI_PLAYER_LIST") + " (" + str(peer_ids.size()) + ")"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_list_box.add_child(title)

	if peer_ids.is_empty():
		var empty := Label.new()
		empty.text = Game.ui_t("UI_NO_CONNECTED_PLAYERS")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_list_box.add_child(empty)
		return

	# 玩家 ID 用一个自动换行标签展示，避免 4~10 人时旧的逐行 Label 被面板裁掉。
	var entries:PackedStringArray = PackedStringArray()
	for peer_id:int in peer_ids:
		var entry:String = "#" + str(peer_id)
		var tags:PackedStringArray = PackedStringArray()
		if peer_id == 1:
			tags.append(Game.ui_t("UI_HOST"))
		if peer_id == local_id:
			tags.append(Game.ui_t("UI_LOCAL_PLAYER"))
		if not tags.is_empty():
			entry += "[" + "/".join(tags) + "]"
		entries.append(entry)
	var list_label := Label.new()
	list_label.text = "  ".join(entries)
	list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_list_box.add_child(list_label)


func _on_network_state_changed() -> void:
	change_connect_state()
	_refresh_multiplayer_permissions_ui()


func _on_room_list_changed() -> void:
	if is_instance_valid(multi_player) and multi_player.visible:
		_refresh_multiplayer_player_list(true)


func change_connect_state() -> void:
	if not is_instance_valid(connect_label):
		return
	if not multiplayer.has_multiplayer_peer():
		connect_label.text = Game.ui_t("UI_CONNECT_DISCONNECTED")
		_refresh_multiplayer_player_list()
		return

	var state:int = multiplayer.multiplayer_peer.get_connection_status()
	if state == MultiplayerPeer.CONNECTION_DISCONNECTED:
		connect_label.text = Game.ui_t("UI_CONNECT_DISCONNECTED")
		if not Game.network_last_error.is_empty():
			connect_label.text += " · " + Game.ui_t("UI_NETWORK_ERROR") + ": " + Game.network_last_error
	elif state == MultiplayerPeer.CONNECTION_CONNECTING:
		connect_label.text = Game.ui_t("UI_CONNECT_CONNECTING")
	else:
		if multiplayer.is_server() and multiplayer.get_unique_id() == 1:
			connect_label.text = Game.ui_t("UI_CONNECT_HOST")
		else:
			connect_label.text = Game.ui_t("UI_CONNECT_SUCCESS_IP") + Game.network_target_address
			if Game.network_rpc_verified:
				connect_label.text += " · " + Game.ui_t("UI_RPC_OK")
				if Game.network_ping_ms >= 0:
					connect_label.text += " " + str(Game.network_ping_ms) + "ms"
			else:
				connect_label.text += " · " + Game.ui_t("UI_RPC_CHECKING")
	_refresh_multiplayer_player_list()

func _input(event:InputEvent) -> void:
	# 中键拖动角色列表时由这里持续接管 motion。这样即使鼠标拖出某个按钮，
	# 列表也会继续滚，而不是因为 GUI hover 目标变化突然中断。
	if _character_middle_dragging or _map_middle_dragging:
		Game.mouse_drag = false
		if event is InputEventMouseMotion:
			if _character_middle_dragging:
				_scroll_character_list_by(-event.relative.y)
			else:
				_scroll_container_by(map_scroll,-event.relative.y)
			get_viewport().set_input_as_handled()
			return
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_MIDDLE
			and not event.is_pressed()
		):
			_character_middle_dragging = false
			_map_middle_dragging = false
			get_viewport().set_input_as_handled()
			return

	# 中键在设置面板外松开时也必须结束 UI 拖动状态。
	if (
		_settings_middle_dragging
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_MIDDLE
		and not event.is_pressed()
	):
		_settings_middle_dragging = false

	# V71：只有设置面板当前停在“特效”分类时才接管测试快捷键。
	# 其他分类和正常游戏输入完全不受影响。
	if (
		is_instance_valid(game_setting)
		and game_setting.visible
		and current_settings_category == "effects"
		and is_instance_valid(effect_preview_panel)
		and effect_preview_panel.has_method("handle_shortcut")
	):
		var handled:Variant = effect_preview_panel.call("handle_shortcut", event)
		if typeof(handled) == TYPE_BOOL and bool(handled):
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	if _layout_ready:
		var mouse_norm := _get_mouse_normalized() if ui_parallax_enabled else Vector2.ZERO

		# 和原版一样：整个 UI 朝鼠标反方向轻微移动。
		var root_target := ori_position + offset - Vector2(
			mouse_norm.x * root_parallax_amount.x,
			mouse_norm.y * root_parallax_amount.y
		)
		global_position = global_position.lerp(root_target, lerp_weight)

		# Team/Char 也必须和主 UI 一样朝鼠标移动的反方向偏移。
		# 例如鼠标向左，面板向右靠近鼠标所在一侧；只用更大的幅度保留景深感。
		# 使用 global_position 是为了不被根节点的偏移再次叠加。
		var team_target := Team_ori_position - Vector2(
			mouse_norm.x * team_parallax_amount.x,
			mouse_norm.y * team_parallax_amount.y
		)
		team.global_position = team.global_position.lerp(team_target, minf(lerp_weight * 2.0, 1.0))

	# 网络连接状态不需要每个渲染帧查询 ENet peer。
	_connection_refresh_elapsed += delta
	if _connection_refresh_elapsed >= 0.5:
		_connection_refresh_elapsed = 0.0
		change_connect_state()

#创建游戏设置
var game_setting_template := preload("res://ui/game_setting.tscn")
var effect_preview_panel_script := preload("res://scripts/ui/effect_preview_panel.gd")
var false_modulate = Color(2.652, 0.0, 0.0, 1.0)

@onready var set_box: VBoxContainer = $Game_Setting/Panel/VBoxContainer
var settings_tab_bar:HBoxContainer
var settings_tab_group:ButtonGroup
var settings_scroll:ScrollContainer
var settings_stack:VBoxContainer
var settings_category_boxes:Dictionary = {}
var settings_tab_buttons:Dictionary = {}
const SETTINGS_CATEGORY_ORDER:Array[String] = ["training", "parameters", "effects", "recording"]
var current_settings_category:String = "training"
var effect_preview_panel:Control
var _effect_preview_size_preset:String = "large"
var _settings_geometry_captured:bool = false
var _settings_base_outer_size:Vector2 = Vector2.ZERO
var _settings_base_outer_center:Vector2 = Vector2.ZERO
var _settings_base_outer_top:float = 0.0
var _settings_base_inner_size:Vector2 = Vector2.ZERO
var _settings_base_inner_center:Vector2 = Vector2.ZERO
var manual_training_options:VBoxContainer
var manual_attack_label:Label
var manual_attack_option:OptionButton
var manual_attack_hint:Label
var manual_attack_interval_label:Label
var manual_attack_interval_slider:HSlider
var manual_attack_interval_value_label:Label
var training_mode_label:Label
var training_mode_option:OptionButton
var map_background_label:Label
var map_background_option:OptionButton
var battle_music_label:Label
var battle_music_option:OptionButton
var battle_music_volume_label:Label
var battle_music_volume_slider:HSlider
var battle_music_volume_value:Label
var rotation_mode_options:VBoxContainer
var rotation_count_spins:Dictionary={}
var rotation_round_panel:Control
var rotation_round_box:VBoxContainer
var _rotation_round_ui_signature:String=""
var rotation_match_option:OptionButton
var rotation_match_label:Label
var timed_mode_options:VBoxContainer
var boss_mode_options:VBoxContainer
var timed_duration_label:Label
var timed_duration_spin:SpinBox
var boss_side_label:Label
var boss_side_option:OptionButton
var boss_multiplier_label:Label
var boss_multiplier_spin:SpinBox
var boss_specialization_row:Control
var development_options:VBoxContainer
var development_duration_spin:SpinBox
var development_speed_spin:SpinBox
var mode_section_gap:Control
var _settings_middle_dragging:bool = false
var _character_middle_dragging:bool = false
var _map_middle_dragging:bool = false

func add_game_set() -> void:
	# 新设置界面：顶部分类按钮 + 可滚动内容区。
	# 默认进入“训练”；设置页只保留已经完成的正式分类。
	for child:Node in set_box.get_children():
		child.queue_free()

	# 语言是全局 UI 设置，固定放在整个设置面板最上方，不再藏在“参数”列表底部。
	_create_language_setting_at_top()

	settings_tab_bar = HBoxContainer.new()
	settings_tab_bar.name = "SettingsCategoryTabs"
	settings_tab_bar.custom_minimum_size = Vector2(0, 24)
	settings_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_tab_bar.add_theme_constant_override("separation", 2)
	set_box.add_child(settings_tab_bar)

	settings_tab_group = ButtonGroup.new()
	settings_tab_group.allow_unpress = false
	for category:String in SETTINGS_CATEGORY_ORDER:
		var tab := Button.new()
		tab.name = "Category_" + category
		tab.toggle_mode = true
		tab.button_group = settings_tab_group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 23)
		tab.clip_text = true
		tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# 分类按钮统一使用紧凑字号，中文/英文都能在同一排显示。
		tab.add_theme_font_size_override("font_size", 9)
		tab.set_meta("settings_category", category)
		tab.pressed.connect(_show_settings_category.bind(category))
		settings_tab_bar.add_child(tab)
		settings_tab_buttons[category] = tab
		Game.Set_Ui_sfx(tab)

	settings_scroll = ScrollContainer.new()
	settings_scroll.name = "SettingsScroll"
	# 不能给滚动区写 128px 的最小高度：设置面板本身剩余空间不足时，
	# ScrollContainer 会被父 VBox 撑出面板，滚动条也一起被 clip 掉。
	# 让它吃“剩余高度”，内容超出后由自己的 VScrollBar 处理。
	settings_scroll.custom_minimum_size = Vector2(248, 0)
	settings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	settings_scroll.scroll_vertical_custom_step = 14.0
	settings_scroll.clip_contents = true
	set_box.add_child(settings_scroll)
	_style_pixel_scroll_container(settings_scroll)

	settings_stack = VBoxContainer.new()
	settings_stack.name = "SettingsStack"
	settings_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_stack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	settings_stack.add_theme_constant_override("separation", 2)
	settings_scroll.add_child(settings_stack)

	for category:String in SETTINGS_CATEGORY_ORDER:
		var box := VBoxContainer.new()
		box.name = "CategoryBox_" + category
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 2)
		settings_stack.add_child(box)
		settings_category_boxes[category] = box

	_build_training_settings(settings_category_boxes["training"] as VBoxContainer)
	_build_parameter_settings(settings_category_boxes["parameters"] as VBoxContainer)
	_build_effect_preview_settings(settings_category_boxes["effects"] as VBoxContainer)
	var recording_panel := preload("res://scripts/ui/battle_record_settings.gd").new()
	recording_panel.name = "RecordingSettings"
	(settings_category_boxes["recording"] as VBoxContainer).add_child(recording_panel)
	recording_panel.setup(_ensure_battle_record_controls().recorder)

	_refresh_settings_category_texts()
	_show_settings_category("training")
	# 动态创建完成后，把中键拖动绑定到分类按钮、开关、下拉框、滑条等所有子控件。
	_configure_settings_middle_drag()
	call_deferred("_refresh_settings_scroll_layout")


func _create_bool_setting_row(parent_box:VBoxContainer, setting:String) -> Control:
	var new_setting := game_setting_template.instantiate()
	var setting_key:String = "SETTING_" + setting.to_upper()
	var setting_label:Label = new_setting.get_node("Text/Label")
	setting_label.set_meta("_translation_source_text", setting_key)
	setting_label.text = Game.ui_t(setting_key)
	parent_box.add_child(new_setting)

	var but:TextureButton = new_setting.get_node("Set/TextureButton")
	but.set_meta("game_setting_key", setting)
	but.self_modulate = Color.WHITE if bool(Game.Game_Settings.get(setting, false)) else false_modulate
	but.button_up.connect(_on_game_setting_toggle.bind(setting, but))
	but.mouse_entered.connect(func(): but.modulate = Color(1.0, 1.0, 1.0, 0.8))
	but.mouse_exited.connect(func(): but.modulate = Color.WHITE)
	return new_setting


func _create_setting_title_from_template(setting_key:String, minimum_width:float = 64.0) -> Dictionary:
	# 直接复用 res://ui/game_setting.tscn 的 Text/PanelContainer，保证标题背景、字体、边框完全一致。
	var template:Control = game_setting_template.instantiate()
	var title:PanelContainer = template.get_node("Text") as PanelContainer
	template.remove_child(title)
	template.free()
	title.custom_minimum_size = Vector2(minimum_width,20.0)
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var label:Label = title.get_node("Label") as Label
	label.set_meta("_translation_source_text",setting_key)
	label.text = Game.ui_t(setting_key)
	return {"panel":title,"label":label}


func _create_boss_specialization_row(parent_box:VBoxContainer) -> Control:
	# Boss特殊化使用和“训练模式”等 bool 设置完全相同的 game_setting.tscn 模板。
	# 它只是在 Boss 附属选项区显式创建，因此不会再跑进“参数”页。
	var row:Control = game_setting_template.instantiate()
	var setting_key:String = "SETTING_TRAINING_BOSS_SPECIALIZATION"
	var label:Label = row.get_node("Text/Label") as Label
	label.set_meta("_translation_source_text",setting_key)
	label.text = Game.ui_t(setting_key)
	parent_box.add_child(row)
	var but:TextureButton = row.get_node("Set/TextureButton") as TextureButton
	but.set_meta("game_setting_key","Training_Boss_Specialization")
	but.self_modulate = Color.WHITE if Game.is_training_boss_specialization_enabled() else false_modulate
	but.button_up.connect(_on_game_setting_toggle.bind("Training_Boss_Specialization",but))
	but.mouse_entered.connect(func(): but.modulate = Color(1.0,1.0,1.0,0.8))
	but.mouse_exited.connect(func(): but.modulate = Color.WHITE)
	return row



var character_mode_option:OptionButton
var character_mode_label:Label
var random_category_box:VBoxContainer
var random_category_buttons:Dictionary = {}
var random_category_hint:Label
var random_exclude_hint:Label

func _build_character_method_settings(parent_box:VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "CharacterMethodRow"
	row.custom_minimum_size = Vector2(0,24)
	row.add_theme_constant_override("separation",3)
	parent_box.add_child(row)
	var title:Dictionary = _create_setting_title_from_template("SETTING_CHARACTER_METHOD",64.0)
	row.add_child(title.panel)
	character_mode_label = title.label
	character_mode_option = OptionButton.new()
	character_mode_option.name = "CharacterMethodOption"
	character_mode_option.fit_to_longest_item = false
	character_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_mode_option.custom_minimum_size = Vector2(0,24)
	character_mode_option.add_item(Game.ui_t("CHARACTER_METHOD_RANDOM"))
	character_mode_option.add_item(Game.ui_t("CHARACTER_METHOD_CUSTOM"))
	character_mode_option.item_selected.connect(_on_character_mode_selected)
	row.add_child(character_mode_option)
	Game.Set_Ui_sfx(character_mode_option)
	random_category_box = VBoxContainer.new()
	random_category_box.name = "RandomCharacterCategories"
	random_category_box.add_theme_constant_override("separation",2)
	parent_box.add_child(random_category_box)
	random_category_hint = Label.new()
	random_category_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	random_category_box.add_child(random_category_hint)
	random_exclude_hint = Label.new()
	random_exclude_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	random_category_box.add_child(random_exclude_hint)
	_sync_character_mode_controls()

func _on_character_mode_selected(index:int) -> void:
	if Game.can_local_change_settings():
		Game.set_runtime_game_setting("Character_Placement_Mode","random" if index==0 else "custom")
	_sync_character_mode_controls()

func _on_random_category_toggled(enabled:bool,category:String) -> void:
	if Game.can_local_change_settings():
		var selected:Array = Game.Game_Settings.Random_Character_Categories.duplicate()
		if enabled and not selected.has(category): selected.append(category)
		elif not enabled: selected.erase(category)
		Game.set_runtime_game_setting("Random_Character_Categories",selected)
	_sync_character_mode_controls()

func _toggle_random_character_exclusion(button:Button) -> void:
	if not Game.can_local_change_settings(): return
	var world:World = get_tree().current_scene as World
	if world == null or not world.random_character_draft.is_enabled(): return
	var character_name:String = str(button.get_meta("choice_value",""))
	if world.is_placeable_obstacle(character_name,world.character_scene_path(character_name)): return
	var key:String = world.random_character_draft.picker_exclusion_key(character_name)
	if key.is_empty(): return
	var excluded:Array = Game.Game_Settings.Random_Character_Excluded.duplicate()
	if excluded.has(key): excluded.erase(key)
	else: excluded.append(key)
	Game.set_runtime_game_setting("Random_Character_Excluded",excluded)
	_sync_character_mode_controls()

func _sync_random_character_picker() -> void:
	var world:World = get_tree().current_scene as World
	if world == null or not is_instance_valid(char_box): return
	var draft:RefCounted = world.random_character_draft
	var random_mode:bool = draft.is_enabled()
	for child:Node in char_box.get_children():
		if not child is Button or child.is_queued_for_deletion(): continue
		var button:Button = child
		var character_name:String = str(button.get_meta("choice_value",""))
		button.button_group = null
		button.toggle_mode = random_mode
		button.set_pressed_no_signal(random_mode and draft.is_excluded(draft.picker_exclusion_key(character_name)))
		button.disabled = random_mode and (not Game.can_local_change_settings() or world.is_placeable_obstacle(character_name,world.character_scene_path(character_name)))
		button.self_modulate = Color.WHITE if random_mode or world.now_choose_char!=character_name else Color(0.671,0.671,0.671,0.675)
	if is_instance_valid(now_char):
		now_char.text = Game.ui_t("RANDOM_EXCLUDE_PICKER") if random_mode else Game.ui_t("UI_NOW_CHAR")+" "+(Game.ui_t(world.now_choose_char) if not world.now_choose_char.is_empty() else Game.ui_t("UI_NONE"))

func _sync_character_mode_controls() -> void:
	_sync_random_character_picker()
	if not is_instance_valid(character_mode_option): return
	var world:World = get_tree().current_scene as World
	if world == null: return
	var draft:RefCounted = world.random_character_draft
	character_mode_label.text = Game.ui_t("SETTING_CHARACTER_METHOD")
	character_mode_option.set_item_text(0,Game.ui_t("CHARACTER_METHOD_RANDOM"))
	character_mode_option.set_item_text(1,Game.ui_t("CHARACTER_METHOD_CUSTOM"))
	character_mode_option.select(0 if draft.is_enabled() else 1)
	character_mode_option.disabled = not Game.can_local_change_settings()
	random_category_box.visible = draft.is_enabled()
	var categories:PackedStringArray = draft.categories()
	for category:Variant in random_category_buttons.keys():
		if not categories.has(str(category)):
			random_category_buttons[category].hide()
			random_category_buttons[category].queue_free()
			random_category_buttons.erase(category)
	for category:String in categories:
		if not random_category_buttons.has(category):
			var button := CheckButton.new()
			button.text = Game.ui_t(category)
			button.toggled.connect(_on_random_category_toggled.bind(category))
			random_category_box.add_child(button)
			random_category_box.move_child(button,random_category_buttons.size())
			Game.Set_Ui_sfx(button)
			random_category_buttons[category] = button
		var button:CheckButton = random_category_buttons[category]
		button.text = Game.ui_t(category)
		button.set_pressed_no_signal(Game.Game_Settings.Random_Character_Categories.has(category))
		button.disabled = not Game.can_local_change_settings()
	var count:int = draft.pool().size()
	random_category_hint.text = Game.ui_t("RANDOM_CATEGORY_READY")%count if count>0 else Game.ui_t("RANDOM_CATEGORY_EMPTY" if Game.Game_Settings.Random_Character_Categories.is_empty() else "RANDOM_POOL_EMPTY")
	random_exclude_hint.text = Game.ui_t("RANDOM_EXCLUDE_HINT")
	call_deferred("_refresh_settings_scroll_layout")

func _build_training_settings(parent_box:VBoxContainer) -> void:
	_build_character_method_settings(parent_box)
	# 顶部先选训练玩法。当前玩法的附属选项紧跟在它下面，
	# 然后留出明显的小间距，再进入“训练模式”等独立主选项。
	var mode_row := HBoxContainer.new()
	mode_row.name = "TrainingModeRow"
	mode_row.custom_minimum_size = Vector2(0,24)
	mode_row.add_theme_constant_override("separation",3)
	parent_box.add_child(mode_row)

	var mode_title:Dictionary = _create_setting_title_from_template("SETTING_TRAINING_MODE_TYPE",64.0)
	mode_row.add_child(mode_title["panel"] as Control)
	training_mode_label = mode_title["label"] as Label

	training_mode_option = OptionButton.new()
	training_mode_option.name = "TrainingModeOption"
	training_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training_mode_option.custom_minimum_size = Vector2(0,24)
	training_mode_option.add_item(Game.ui_t("TRAINING_MODE_MANUAL"))
	training_mode_option.set_item_metadata(0,"manual")
	training_mode_option.add_item(Game.ui_t("TRAINING_MODE_ROTATION"))
	training_mode_option.set_item_metadata(1,"rotation")
	training_mode_option.add_item(Game.ui_t("TRAINING_MODE_TIMED"))
	training_mode_option.set_item_metadata(2,"timed")
	training_mode_option.add_item(Game.ui_t("TRAINING_MODE_BOSS"))
	training_mode_option.set_item_metadata(3,"boss")
	training_mode_option.item_selected.connect(_on_training_mode_type_selected)
	mode_row.add_child(training_mode_option)
	Game.Set_Ui_sfx(training_mode_option)

	rotation_mode_options = VBoxContainer.new()
	rotation_mode_options.name = "RotationModeOptions"
	rotation_mode_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_mode_options.add_theme_constant_override("separation",2)
	parent_box.add_child(rotation_mode_options)
	var rotation_row := HBoxContainer.new()
	rotation_row.name = "RotationMatchRow"
	rotation_row.custom_minimum_size = Vector2(0,24)
	rotation_row.add_theme_constant_override("separation",3)
	rotation_mode_options.add_child(rotation_row)
	var rotation_title:Dictionary = _create_setting_title_from_template("SETTING_ROTATION_MATCH_TYPE",64.0)
	rotation_row.add_child(rotation_title["panel"] as Control)
	rotation_match_label = rotation_title["label"] as Label
	rotation_match_option = OptionButton.new()
	rotation_match_option.name = "RotationMatchOption"
	rotation_match_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_match_option.custom_minimum_size = Vector2(0,24)
	_create_bool_setting_row(rotation_mode_options,"Training_Wheel_Battle")
	_create_bool_setting_row(rotation_mode_options,"Rotation_Multi_Characters")
	_create_rotation_count_setting("left")
	_create_rotation_count_setting("right")
	for key:String in ["ROTATION_DUEL","ROTATION_CHALLENGE"]:
		rotation_match_option.add_item(Game.ui_t(key))
	for index:int in range(2):
		rotation_match_option.set_item_metadata(index,["duel","challenge"][index])
	rotation_match_option.item_selected.connect(_on_rotation_match_selected)
	rotation_row.add_child(rotation_match_option)
	Game.Set_Ui_sfx(rotation_match_option)

	timed_mode_options = VBoxContainer.new()
	timed_mode_options.name = "TimedModeOptions"
	timed_mode_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timed_mode_options.add_theme_constant_override("separation",2)
	parent_box.add_child(timed_mode_options)
	# 计时模式的附属选项只保留“时间数值”本身，不再加“时间/秒”等文字。
	# 它紧贴模式选项；与后面的普通训练设置之间由 mode_section_gap 统一留白。
	var time_row := HBoxContainer.new()
	time_row.custom_minimum_size = Vector2(0,24)
	timed_mode_options.add_child(time_row)
	timed_duration_label = null
	timed_duration_spin = SpinBox.new()
	timed_duration_spin.name = "TimedDurationSpin"
	timed_duration_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timed_duration_spin.custom_minimum_size = Vector2(0,24)
	timed_duration_spin.min_value = 1.0
	timed_duration_spin.max_value = 86400.0
	timed_duration_spin.allow_greater = true
	timed_duration_spin.step = 1.0
	timed_duration_spin.rounded = true
	timed_duration_spin.suffix = ""
	timed_duration_spin.select_all_on_focus = true
	timed_duration_spin.set_value_no_signal(Game.get_training_timed_duration())
	timed_duration_spin.value_changed.connect(_on_timed_duration_changed)
	time_row.add_child(timed_duration_spin)
	_style_settings_spinbox(timed_duration_spin)

	boss_mode_options = VBoxContainer.new()
	boss_mode_options.name = "BossModeOptions"
	boss_mode_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_mode_options.add_theme_constant_override("separation",2)
	parent_box.add_child(boss_mode_options)

	var boss_side_row := HBoxContainer.new()
	boss_side_row.custom_minimum_size = Vector2(0,24)
	boss_side_row.add_theme_constant_override("separation",3)
	boss_mode_options.add_child(boss_side_row)
	var boss_side_title:Dictionary = _create_setting_title_from_template("SETTING_TRAINING_BOSS_SIDE",64.0)
	boss_side_row.add_child(boss_side_title["panel"] as Control)
	boss_side_label = boss_side_title["label"] as Label
	boss_side_option = OptionButton.new()
	boss_side_option.name = "BossSideOption"
	boss_side_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_side_option.custom_minimum_size = Vector2(0,24)
	boss_side_option.add_item(Game.ui_t("TRAINING_SIDE_LEFT"))
	boss_side_option.set_item_metadata(0,"left")
	boss_side_option.add_item(Game.ui_t("TRAINING_SIDE_RIGHT"))
	boss_side_option.set_item_metadata(1,"right")
	boss_side_option.item_selected.connect(_on_boss_side_selected)
	boss_side_row.add_child(boss_side_option)
	Game.Set_Ui_sfx(boss_side_option)

	var boss_multiplier_row := HBoxContainer.new()
	boss_multiplier_row.custom_minimum_size = Vector2(0,24)
	boss_multiplier_row.add_theme_constant_override("separation",3)
	boss_mode_options.add_child(boss_multiplier_row)
	var boss_multiplier_title:Dictionary = _create_setting_title_from_template("SETTING_TRAINING_BOSS_MULTIPLIER",64.0)
	boss_multiplier_row.add_child(boss_multiplier_title["panel"] as Control)
	boss_multiplier_label = boss_multiplier_title["label"] as Label
	boss_multiplier_spin = SpinBox.new()
	boss_multiplier_spin.name = "BossMultiplierSpin"
	boss_multiplier_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_multiplier_spin.custom_minimum_size = Vector2(0,24)
	boss_multiplier_spin.min_value = 1.0
	boss_multiplier_spin.max_value = 20.0
	boss_multiplier_spin.allow_greater = true
	boss_multiplier_spin.step = 0.1
	boss_multiplier_spin.suffix = "×"
	boss_multiplier_spin.select_all_on_focus = true
	boss_multiplier_spin.set_value_no_signal(Game.get_training_boss_multiplier())
	boss_multiplier_spin.value_changed.connect(_on_boss_multiplier_changed)
	boss_multiplier_row.add_child(boss_multiplier_spin)
	_style_settings_spinbox(boss_multiplier_spin)

	_create_bool_setting_row(boss_mode_options, "Training_Boss_Wheel_Battle")
	boss_specialization_row = _create_boss_specialization_row(boss_mode_options)
	# 和“训练模式 / Boss特殊化”等布尔设置使用完全相同的 game_setting.tscn 原生模板。
	_create_bool_setting_row(boss_mode_options, "Training_Boss_Intro")

	# 只在“模式 + 当前附属选项”这一组结束后留一次分组间距。
	# 下面的训练模式 / 调试 / 手动训练继续使用容器正常 separation，不能每项都隔一大段。
	mode_section_gap = _add_settings_gap(parent_box,8.0)

	_create_bool_setting_row(parent_box, "Training_Mode")
	_create_bool_setting_row(parent_box, "Training_Debug_Mode")
	parent_box.add_child(load("res://ui/battle_conditions_settings.gd").new(self))
	_create_bool_setting_row(parent_box, "Development_Mode")
	development_options = VBoxContainer.new()
	development_options.name = "DevelopmentOptions"
	development_options.add_theme_constant_override("separation",2)
	parent_box.add_child(development_options)
	var development_duration_row := HBoxContainer.new()
	development_duration_row.custom_minimum_size = Vector2(0,24)
	development_duration_row.add_theme_constant_override("separation",3)
	development_options.add_child(development_duration_row)
	development_duration_row.add_child(_create_setting_title_from_template("SETTING_DEVELOPMENT_TIME",64.0)["panel"])
	development_duration_spin = SpinBox.new()
	development_duration_spin.name = "DevelopmentDurationSpin"
	development_duration_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	development_duration_spin.custom_minimum_size = Vector2(0,24)
	development_duration_spin.min_value = 1.0
	development_duration_spin.max_value = 86400.0
	development_duration_spin.step = 1.0
	development_duration_spin.rounded = true
	development_duration_spin.select_all_on_focus = true
	development_duration_spin.set_value_no_signal(float(Game.Game_Settings.get("Development_Duration",60.0)))
	development_duration_spin.value_changed.connect(func(value:float): Game.set_runtime_game_setting("Development_Duration",value))
	development_duration_row.add_child(development_duration_spin)
	_style_settings_spinbox(development_duration_spin)
	var development_speed_row := HBoxContainer.new()
	development_speed_row.custom_minimum_size = Vector2(0,24)
	development_speed_row.add_theme_constant_override("separation",3)
	development_options.add_child(development_speed_row)
	development_speed_row.add_child(_create_setting_title_from_template("SETTING_DEVELOPMENT_SPEED",64.0)["panel"])
	development_speed_spin = SpinBox.new()
	development_speed_spin.name = "DevelopmentSpeedSpin"
	development_speed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	development_speed_spin.custom_minimum_size = Vector2(0,24)
	development_speed_spin.min_value = 1.0
	development_speed_spin.max_value = 32.0
	development_speed_spin.step = 1.0
	development_speed_spin.rounded = true
	development_speed_spin.suffix = "×"
	development_speed_spin.select_all_on_focus = true
	development_speed_spin.set_value_no_signal(float(Game.Game_Settings.get("Development_Speed",2.0)))
	development_speed_spin.value_changed.connect(func(value:float): Game.set_runtime_game_setting("Development_Speed",value))
	development_speed_row.add_child(development_speed_spin)
	_style_settings_spinbox(development_speed_spin)
	_create_bool_setting_row(parent_box, "Manual_Training")

	manual_training_options = VBoxContainer.new()
	manual_training_options.name = "ManualTrainingOptions"
	manual_training_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_training_options.add_theme_constant_override("separation", 2)
	parent_box.add_child(manual_training_options)

	_create_bool_setting_row(manual_training_options, "Manual_Collision_Damage")

	var attack_row := HBoxContainer.new()
	attack_row.name = "ManualAttackRow"
	attack_row.custom_minimum_size = Vector2(0, 24)
	manual_training_options.add_child(attack_row)

	var manual_attack_title:Dictionary = _create_setting_title_from_template("MANUAL_ATTACK_LABEL",64.0)
	attack_row.add_child(manual_attack_title["panel"] as Control)
	manual_attack_label = manual_attack_title["label"] as Label

	manual_attack_option = OptionButton.new()
	manual_attack_option.name = "ManualAttackOption"
	manual_attack_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_attack_option.custom_minimum_size = Vector2(0, 24)
	manual_attack_option.item_selected.connect(_on_manual_attack_selected)
	attack_row.add_child(manual_attack_option)
	Game.Set_Ui_sfx(manual_attack_option)

	var interval_row := HBoxContainer.new()
	interval_row.name = "ManualAttackIntervalRow"
	interval_row.custom_minimum_size = Vector2(0, 24)
	interval_row.add_theme_constant_override("separation", 3)
	manual_training_options.add_child(interval_row)

	var manual_interval_title:Dictionary = _create_setting_title_from_template("SETTING_MANUAL_ATTACK_INTERVAL",64.0)
	interval_row.add_child(manual_interval_title["panel"] as Control)
	manual_attack_interval_label = manual_interval_title["label"] as Label

	manual_attack_interval_slider = HSlider.new()
	manual_attack_interval_slider.name = "ManualAttackIntervalSlider"
	manual_attack_interval_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_attack_interval_slider.custom_minimum_size = Vector2(92, 20)
	manual_attack_interval_slider.min_value = Game.MANUAL_ATTACK_INTERVAL_MIN
	manual_attack_interval_slider.max_value = Game.MANUAL_ATTACK_INTERVAL_MAX
	manual_attack_interval_slider.step = Game.MANUAL_ATTACK_INTERVAL_STEP
	manual_attack_interval_slider.value = Game.get_manual_training_attack_interval()
	manual_attack_interval_slider.scrollable = true
	manual_attack_interval_slider.theme = load("res://ui/slider.tres") as Theme
	manual_attack_interval_slider.value_changed.connect(_on_manual_attack_interval_changed)
	manual_attack_interval_slider.drag_ended.connect(_on_manual_attack_interval_drag_ended)
	interval_row.add_child(manual_attack_interval_slider)

	manual_attack_interval_value_label = Label.new()
	manual_attack_interval_value_label.custom_minimum_size = Vector2(42, 22)
	manual_attack_interval_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	manual_attack_interval_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	manual_attack_interval_value_label.add_theme_font_size_override("font_size", 9)
	interval_row.add_child(manual_attack_interval_value_label)
	_refresh_manual_attack_interval_value()

	manual_attack_hint = Label.new()
	manual_attack_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manual_attack_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manual_attack_hint.add_theme_font_size_override("font_size", 9)
	manual_attack_hint.modulate = Color(1.0, 1.0, 1.0, 0.76)
	manual_training_options.add_child(manual_attack_hint)

	_populate_manual_attack_options()
	_sync_training_mode_controls()
	_update_training_mode_extra_visibility()
	_update_manual_training_options_visibility()


func _add_settings_gap(parent_box:VBoxContainer,height:float = 7.0) -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(0,maxf(height,0.0))
	parent_box.add_child(gap)
	return gap


func _style_settings_spinbox(spin:SpinBox) -> void:
	if not is_instance_valid(spin):
		return
	var edit:LineEdit = spin.get_line_edit()
	if not is_instance_valid(edit):
		return
	edit.add_theme_font_size_override("font_size",9)
	edit.add_theme_color_override("font_color",Color(0.95,0.92,0.82,1.0))
	edit.add_theme_color_override("caret_color",Color(0.95,0.88,0.64,1.0))
	edit.add_theme_color_override("selection_color",Color(0.52,0.46,0.30,0.72))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15,0.14,0.11,0.92)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.48,0.43,0.31,0.94)
	normal.content_margin_left = 5.0
	normal.content_margin_right = 4.0
	normal.content_margin_top = 2.0
	normal.content_margin_bottom = 2.0
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.82,0.75,0.52,1.0)
	edit.add_theme_stylebox_override("normal",normal)
	edit.add_theme_stylebox_override("focus",focus)


func _build_effect_preview_settings(parent_box:VBoxContainer) -> void:
	# V72：特效测试器独立成 scripts/ui 组件；尺寸下拉框通过信号请求设置窗口同步扩展。
	if effect_preview_panel != null and is_instance_valid(effect_preview_panel):
		effect_preview_panel.queue_free()
	var panel_variant:Variant = effect_preview_panel_script.new()
	if not (panel_variant is Control):
		return
	effect_preview_panel = panel_variant as Control
	effect_preview_panel.name = "EffectPreviewPanel"
	effect_preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_box.add_child(effect_preview_panel)
	if effect_preview_panel.has_signal("preview_size_requested"):
		effect_preview_panel.connect("preview_size_requested", _on_effect_preview_size_requested)
	if effect_preview_panel.has_method("emit_current_size_request"):
		effect_preview_panel.call_deferred("emit_current_size_request")


func _capture_settings_geometry_once() -> void:
	if _settings_geometry_captured or not is_instance_valid(game_setting):
		return
	var inner:Control = game_setting.get_node_or_null("Panel") as Control
	if inner == null:
		return
	_settings_base_outer_size = Vector2(
		game_setting.offset_right - game_setting.offset_left,
		game_setting.offset_bottom - game_setting.offset_top
	)
	_settings_base_outer_center = Vector2(
		(game_setting.offset_left + game_setting.offset_right) * 0.5,
		(game_setting.offset_top + game_setting.offset_bottom) * 0.5
	)
	_settings_base_outer_top = game_setting.offset_top
	_settings_base_inner_size = Vector2(
		inner.offset_right - inner.offset_left,
		inner.offset_bottom - inner.offset_top
	)
	_settings_base_inner_center = Vector2(
		(inner.offset_left + inner.offset_right) * 0.5,
		(inner.offset_top + inner.offset_bottom) * 0.5
	)
	_settings_geometry_captured = true


func _set_center_anchored_size(control:Control, center_offset:Vector2, target_size:Vector2) -> void:
	if not is_instance_valid(control):
		return
	var half:Vector2 = target_size * 0.5
	control.offset_left = center_offset.x - half.x
	control.offset_right = center_offset.x + half.x
	control.offset_top = center_offset.y - half.y
	control.offset_bottom = center_offset.y + half.y


func _set_settings_outer_size(target_size:Vector2) -> void:
	if not is_instance_valid(game_setting):
		return
	# 设置工具栏固定在屏幕顶部，因此特效窗口只向下增长，避免“大/最大”把上半截顶出屏幕。
	var half_width:float = target_size.x * 0.5
	game_setting.offset_left = _settings_base_outer_center.x - half_width
	game_setting.offset_right = _settings_base_outer_center.x + half_width
	game_setting.offset_top = _settings_base_outer_top
	game_setting.offset_bottom = _settings_base_outer_top + target_size.y


func _effect_preview_target_window_size(preset_id:String) -> Vector2:
	_capture_settings_geometry_once()
	if not _settings_geometry_captured:
		return Vector2(270.0, 172.0)
	match preset_id:
		"compact":
			return _settings_base_outer_size
		"medium":
			return Vector2(maxf(_settings_base_outer_size.x, 300.0), maxf(_settings_base_outer_size.y, 340.0))
		"large":
			return Vector2(maxf(_settings_base_outer_size.x, 330.0), maxf(_settings_base_outer_size.y, 470.0))
		"maximum":
			var ui_scale:float = maxf(absf(scale.x), 1.0)
			var local_view:Vector2 = get_viewport_rect().size / ui_scale
			return Vector2(
				clampf(local_view.x - 20.0, _settings_base_outer_size.x, 350.0),
				clampf(local_view.y - 72.0, _settings_base_outer_size.y, 540.0)
			)
	return Vector2(maxf(_settings_base_outer_size.x, 330.0), maxf(_settings_base_outer_size.y, 470.0))


func _apply_effect_settings_window_size(preset_id:String) -> void:
	_capture_settings_geometry_once()
	if not _settings_geometry_captured:
		return
	var target:Vector2 = _effect_preview_target_window_size(preset_id)
	var inner:Control = game_setting.get_node_or_null("Panel") as Control
	var frame_delta:Vector2 = _settings_base_outer_size - _settings_base_inner_size
	var inner_target := Vector2(
		maxf(target.x - frame_delta.x, _settings_base_inner_size.x),
		maxf(target.y - frame_delta.y, _settings_base_inner_size.y)
	)
	_set_settings_outer_size(target)
	if inner != null:
		_set_center_anchored_size(inner, _settings_base_inner_center, inner_target)
	call_deferred("_refresh_settings_scroll_layout")


func _restore_default_settings_window_size() -> void:
	_capture_settings_geometry_once()
	if not _settings_geometry_captured:
		return
	var inner:Control = game_setting.get_node_or_null("Panel") as Control
	_set_settings_outer_size(_settings_base_outer_size)
	if inner != null:
		_set_center_anchored_size(inner, _settings_base_inner_center, _settings_base_inner_size)
	call_deferred("_refresh_settings_scroll_layout")


func _on_effect_preview_size_requested(preset_id:String) -> void:
	_effect_preview_size_preset = preset_id
	if current_settings_category == "effects" and is_instance_valid(game_setting) and game_setting.visible:
		_apply_effect_settings_window_size(_effect_preview_size_preset)


func _create_map_background_setting(parent_box:VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "MapBackgroundRow"
	row.custom_minimum_size = Vector2(0,24)
	row.add_theme_constant_override("separation",3)
	parent_box.add_child(row)
	var title:Dictionary = _create_setting_title_from_template("SETTING_MAP_BACKGROUND",64.0)
	row.add_child(title["panel"])
	map_background_label = title["label"]
	map_background_option = OptionButton.new()
	map_background_option.name = "MapBackgroundOption"
	# A long translated item must not enlarge the entire settings VBox and tabs.
	map_background_option.fit_to_longest_item = false
	map_background_option.clip_text = true
	map_background_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_background_option.custom_minimum_size = Vector2(0,24)
	map_background_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_background_option.add_theme_font_size_override("font_size",9)
	for key:String in MAP_BACKGROUND_THEMES.OPTIONS:
		map_background_option.add_item(Game.ui_t("MAP_BACKGROUND_" + key.to_upper()))
		map_background_option.set_item_metadata(map_background_option.item_count - 1,key)
	map_background_option.item_selected.connect(_on_map_background_selected)
	row.add_child(map_background_option)
	Game.Set_Ui_sfx(map_background_option)
	_sync_map_background_setting()
func _sync_map_background_setting() -> void:
	if not is_instance_valid(map_background_option): return
	map_background_label.text = Game.ui_t("SETTING_MAP_BACKGROUND")
	for index:int in range(map_background_option.item_count):
		var key:String = str(map_background_option.get_item_metadata(index))
		map_background_option.set_item_text(index,Game.ui_t("MAP_BACKGROUND_" + key.to_upper()))
	var chosen:String = MAP_BACKGROUND_THEMES.normalize(str(Game.Game_Settings.get("Map_Background","blue")))
	map_background_option.select(MAP_BACKGROUND_THEMES.OPTIONS.find(chosen))
	map_background_option.tooltip_text = Game.ui_t("MAP_BACKGROUND_" + chosen.to_upper())
func _on_map_background_selected(index:int) -> void:
	Game.set_runtime_game_setting("Map_Background",str(map_background_option.get_item_metadata(index)))

func _create_battle_music_setting(parent_box:VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "BattleMusicRow"
	row.custom_minimum_size = Vector2(0,24)
	row.add_theme_constant_override("separation",3)
	parent_box.add_child(row)
	var title:Dictionary = _create_setting_title_from_template("SETTING_BATTLE_MUSIC",64.0)
	row.add_child(title["panel"])
	battle_music_label = title["label"]
	battle_music_option = OptionButton.new()
	battle_music_option.name = "BattleMusicOption"
	battle_music_option.fit_to_longest_item = false
	battle_music_option.clip_text = true
	battle_music_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	battle_music_option.custom_minimum_size = Vector2(0,24)
	battle_music_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_music_option.add_theme_font_size_override("font_size",9)
	for key:String in BATTLE_MUSIC.OPTIONS:
		battle_music_option.add_item(Game.ui_t("BATTLE_MUSIC_" + key.to_upper()))
		battle_music_option.set_item_metadata(battle_music_option.item_count - 1,key)
	battle_music_option.item_selected.connect(_on_battle_music_selected)
	row.add_child(battle_music_option)
	Game.Set_Ui_sfx(battle_music_option)
	var volume_row := HBoxContainer.new()
	volume_row.name = "BattleMusicVolumeRow"
	volume_row.custom_minimum_size = Vector2(0,24)
	volume_row.add_theme_constant_override("separation",3)
	parent_box.add_child(volume_row)
	var volume_title:Dictionary = _create_setting_title_from_template("SETTING_BATTLE_MUSIC_VOLUME",64.0)
	volume_row.add_child(volume_title["panel"])
	battle_music_volume_label = volume_title["label"]
	battle_music_volume_slider = HSlider.new()
	battle_music_volume_slider.name = "BattleMusicVolumeSlider"
	battle_music_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_music_volume_slider.custom_minimum_size = Vector2(72,20)
	battle_music_volume_slider.min_value = 0.0
	battle_music_volume_slider.max_value = 100.0
	battle_music_volume_slider.step = 1.0
	battle_music_volume_slider.scrollable = true
	battle_music_volume_slider.theme = preload("res://ui/slider.tres")
	battle_music_volume_slider.value_changed.connect(_on_battle_music_volume_changed)
	volume_row.add_child(battle_music_volume_slider)
	battle_music_volume_value = Label.new()
	battle_music_volume_value.name = "BattleMusicVolumeValue"
	battle_music_volume_value.custom_minimum_size = Vector2(36,22)
	battle_music_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	battle_music_volume_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	battle_music_volume_value.add_theme_font_size_override("font_size",9)
	volume_row.add_child(battle_music_volume_value)
	_sync_battle_music_setting()
func _sync_battle_music_setting() -> void:
	if not is_instance_valid(battle_music_option): return
	battle_music_label.text = Game.ui_t("SETTING_BATTLE_MUSIC")
	for index:int in range(battle_music_option.item_count):
		var key:String = str(battle_music_option.get_item_metadata(index))
		battle_music_option.set_item_text(index,Game.ui_t("BATTLE_MUSIC_" + key.to_upper()))
	var chosen:String = BATTLE_MUSIC.normalize(Game.Game_Settings.get(BATTLE_MUSIC.SETTING_KEY,BATTLE_MUSIC.NONE))
	battle_music_option.select(maxi(BATTLE_MUSIC.OPTIONS.find(chosen),0))
	battle_music_option.tooltip_text = Game.ui_t("BATTLE_MUSIC_" + chosen.to_upper())
	if is_instance_valid(battle_music_volume_slider):
		var volume:float = BATTLE_MUSIC.normalize_volume(Game.Game_Settings.get(BATTLE_MUSIC.VOLUME_KEY,BATTLE_MUSIC.DEFAULT_VOLUME))
		battle_music_volume_label.text = Game.ui_t("SETTING_BATTLE_MUSIC_VOLUME")
		battle_music_volume_slider.set_value_no_signal(volume)
		battle_music_volume_value.text = "%d%%" % roundi(volume)
		battle_music_volume_slider.tooltip_text = "%s: %d%%" % [Game.ui_t("SETTING_BATTLE_MUSIC_VOLUME"),roundi(volume)]
func _on_battle_music_volume_changed(value:float) -> void:
	Game.set_runtime_game_setting(BATTLE_MUSIC.VOLUME_KEY,value)
	_sync_battle_music_setting()

func _on_battle_music_selected(index:int) -> void:
	Game.set_runtime_game_setting(BATTLE_MUSIC.SETTING_KEY,str(battle_music_option.get_item_metadata(index)))

var _feedback_groups:Dictionary = {}
var _feedback_spins:Dictionary = {}

func _create_feedback_options(parent_box:VBoxContainer,group:String) -> void:
	var inset := MarginContainer.new()
	inset.name = group+"Options"
	inset.add_theme_constant_override("margin_left",6)
	parent_box.add_child(inset)
	_feedback_groups[group] = inset
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",3)
	inset.add_child(box)
	var reset := Button.new()
	reset.name = "ResetFeedback"
	reset.set_meta("feedback_group",group)
	reset.set_meta("_translation_source_text","FEEDBACK_RESET_GROUP")
	reset.text = Game.ui_t("FEEDBACK_RESET_GROUP")
	reset.add_theme_font_size_override("font_size",9)
	reset.pressed.connect(func(): Game.reset_feedback_settings(group))
	for key:String in Game.FEEDBACK_SETTINGS.SIMPLE_LABELS:
		var spec:Dictionary = Game.FEEDBACK_SETTINGS.SPECS[key]
		if str(spec.group)!=group: continue
		var row := HBoxContainer.new()
		row.name = key+"Row"
		row.add_theme_constant_override("separation",3)
		box.add_child(row)
		var title:Dictionary = _create_setting_title_from_template(str(Game.FEEDBACK_SETTINGS.SIMPLE_LABELS[key]),96.0)
		var panel:PanelContainer = title.panel
		var label:Label = title.label
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		var spin := SpinBox.new()
		spin.name = key
		spin.set_meta("feedback_setting",key)
		spin.custom_minimum_size = Vector2(76,24)
		spin.min_value = float(spec.min)
		spin.max_value = float(spec.max)
		spin.step = float(spec.step)
		spin.suffix = str(spec.unit)
		spin.select_all_on_focus = true
		spin.get_line_edit().add_theme_font_size_override("font_size",9)
		spin.set_value_no_signal(Game.FEEDBACK_SETTINGS.number(Game.Game_Settings,key))
		spin.value_changed.connect(_on_feedback_value_changed.bind(key))
		row.add_child(spin)
		_feedback_spins[key] = spin
	box.add_child(reset)
	_sync_feedback_options()

func _on_feedback_value_changed(value:float,key:String) -> void:
	Game.set_simple_feedback_setting(key,value)
	_sync_feedback_options()

func _sync_feedback_options() -> void:
	var layout_changed:bool = false
	for group:String in _feedback_groups:
		var panel:Control = _feedback_groups[group]
		if not is_instance_valid(panel): continue
		var enabled:bool = bool(Game.Game_Settings.get(group,false))
		layout_changed = layout_changed or panel.visible!=enabled
		panel.visible = enabled
	for key:String in _feedback_spins:
		var spin:SpinBox = _feedback_spins[key]
		if is_instance_valid(spin):
			spin.set_value_no_signal(Game.FEEDBACK_SETTINGS.number(Game.Game_Settings,key))
			var spec:Dictionary = Game.FEEDBACK_SETTINGS.SPECS[key]
			spin.tooltip_text = Game.ui_t(str(Game.FEEDBACK_SETTINGS.SIMPLE_LABELS[key]))+"\n"+(Game.ui_t("FEEDBACK_VALUE_HINT")%[str(spec.min),str(spec.max),str(spec.default)])+"\n"+Game.ui_t("FEEDBACK_SIMPLE_SHAKE_HINT" if str(spec.group)=="Shaking_Camera" else "FEEDBACK_SIMPLE_SPECIAL_HINT")
			(spin.get_parent().get_node("Text/Label") as Label).tooltip_text = spin.tooltip_text
	if layout_changed: call_deferred("_refresh_settings_scroll_layout")

func _build_parameter_settings(parent_box:VBoxContainer) -> void:
	_create_map_background_setting(parent_box)
	_create_battle_music_setting(parent_box)
	var door_preview:Button = preload("res://scripts/ui/dark_oak_transition_button.gd").new()
	parent_box.add_child(door_preview)
	if not Game.Game_Settings.has("Minecraft_Clouds"): Game.Game_Settings["Minecraft_Clouds"] = true
	_create_bool_setting_row(parent_box,"Minecraft_Clouds")
	var excluded:Dictionary = {
		"Minecraft_Clouds": true,
		"Training_Mode": true,
		"Manual_Training": true,
		"Manual_Collision_Damage": true,
		"Training_Debug_Mode": true,
		"Random_Events": true,
		"Random_Event_Selection": true,
		"Environment": true,
		"Development_Mode": true,
		"Development_Duration": true,
		"Development_Speed": true,
		"Training_Mode_Type": true,
		"Training_Wheel_Battle": true,
		"Rotation_Match_Type": true,
		"Rotation_Multi_Characters": true,
		"Rotation_Blue_Count": true,
		"Rotation_Red_Count": true,
		"Training_Timed_Duration": true,
		"Training_Boss_Side": true,
		"Training_Boss_Wheel_Battle": true,
		"Training_Boss_Multiplier": true,
		"Training_Boss_Specialization": true,
		"Training_Boss_Intro": true,
		# 这个选项单独固定在“参数”第一行，不能依赖 Dictionary 的遍历顺序。
		"Only_In_Game_Translation": true,
		# 旧水印开关已删除。保留排除项，避免旧字典遍历时又生成这个按钮。
		"Show_Center_Watermark": true,
	}

	# 明确放在参数页最上方，保证一打开“参数”就能看到。
	# 旧存档不会包含新 key，这里也做一次兼容兜底。
	if not Game.Game_Settings.has("Only_In_Game_Translation"):
		Game.Game_Settings["Only_In_Game_Translation"] = false
	_create_bool_setting_row(parent_box, "Only_In_Game_Translation")

	for raw_setting:Variant in Game.Game_Settings.keys():
		var setting:String = str(raw_setting)
		if excluded.has(setting):
			continue
		if Game.Game_Settings[setting] is bool:
			_create_bool_setting_row(parent_box, setting)
			if setting in ["Shaking_Camera","High_Damage_Feedback"]:
				_create_feedback_options(parent_box,setting)


func _refresh_game_setting_toggle_visuals() -> void:
	_sync_character_mode_controls()
	_sync_feedback_options()
	_sync_map_background_setting()
	_sync_battle_music_setting()
	if settings_stack == null or not is_instance_valid(settings_stack):
		return
	for row:Node in _collect_descendants(settings_stack):
		var but:TextureButton = row.get_node_or_null("Set/TextureButton") as TextureButton
		if but == null or not but.has_meta("game_setting_key"):
			continue
		var setting:String = str(but.get_meta("game_setting_key"))
		if not Game.Game_Settings.has(setting):
			continue
		but.self_modulate = Color.WHITE if bool(Game.Game_Settings[setting]) else false_modulate
	_sync_training_mode_controls()
	_update_training_mode_extra_visibility()
	_update_manual_training_options_visibility()
	_update_development_options_visibility()


func _collect_descendants(root:Node) -> Array[Node]:
	var result:Array[Node] = []
	for child:Node in root.get_children():
		result.append(child)
		result.append_array(_collect_descendants(child))
	return result


func _on_global_game_setting_changed(_setting:String, _value:Variant) -> void:
	# 训练类型、计时长度和普通开关都可能由场景脚本修改；统一延迟刷新。
	call_deferred("_refresh_game_setting_toggle_visuals")
	if _setting == "Guest_Free_Permissions":
		call_deferred("_refresh_multiplayer_permissions_ui")


func _on_ui_language_changed(_locale:String) -> void:
	call_deferred("_refresh_runtime_translations")


func _on_game_setting_toggle(setting:String, but:TextureButton) -> void:
	if not Game.can_local_change_settings():
		_refresh_game_setting_toggle_visuals()
		return
	if not Game.Game_Settings.has(setting):
		return

	var new_value:bool = not bool(Game.Game_Settings[setting])
	Game.set_runtime_game_setting(setting, new_value)
	but.self_modulate = Color.WHITE if bool(Game.Game_Settings[setting]) else false_modulate

	if setting in ["Training_Mode", "Manual_Training"]:
		_update_manual_training_options_visibility()
	_refresh_game_setting_toggle_visuals()


func _show_settings_category(category:String) -> void:
	if not settings_category_boxes.has(category):
		return
	current_settings_category = category
	for raw_key:Variant in settings_category_boxes.keys():
		var key:String = str(raw_key)
		var box:VBoxContainer = settings_category_boxes[key] as VBoxContainer
		box.visible = key == category
	for raw_key:Variant in settings_tab_buttons.keys():
		var key:String = str(raw_key)
		var button:Button = settings_tab_buttons[key] as Button
		button.set_pressed_no_signal(key == category)
	if is_instance_valid(settings_scroll):
		settings_scroll.scroll_vertical = 0
	if category == "training":
		_update_manual_training_options_visibility()
	if category == "effects":
		_apply_effect_settings_window_size(_effect_preview_size_preset)
	else:
		_restore_default_settings_window_size()
	if is_instance_valid(effect_preview_panel) and effect_preview_panel.has_method("set_preview_active"):
		effect_preview_panel.call("set_preview_active", category == "effects" and is_instance_valid(game_setting) and game_setting.visible)
	call_deferred("_refresh_settings_scroll_layout")


func _refresh_settings_category_texts() -> void:
	_sync_character_mode_controls()
	_sync_feedback_options()
	if settings_tab_buttons.has("recording"):
		(settings_tab_buttons["recording"] as Button).text = Game.ui_t("UI_SETTINGS_CATEGORY_RECORDING")
	_sync_map_background_setting()
	_sync_battle_music_setting()
	if settings_tab_buttons.has("training"):
		(settings_tab_buttons["training"] as Button).text = Game.ui_t("SETTINGS_CATEGORY_TRAINING")
	if settings_tab_buttons.has("parameters"):
		(settings_tab_buttons["parameters"] as Button).text = Game.ui_t("SETTINGS_CATEGORY_PARAMETERS")
	if settings_tab_buttons.has("effects"):
		(settings_tab_buttons["effects"] as Button).text = Game.ui_t("SETTINGS_CATEGORY_EFFECTS")
	if is_instance_valid(effect_preview_panel) and effect_preview_panel.has_method("refresh_texts"):
		effect_preview_panel.call("refresh_texts")
	if is_instance_valid(manual_attack_label):
		manual_attack_label.text = Game.ui_t("MANUAL_ATTACK_LABEL")
	if is_instance_valid(manual_attack_interval_label):
		manual_attack_interval_label.text = Game.ui_t("SETTING_MANUAL_ATTACK_INTERVAL")
	if is_instance_valid(manual_attack_hint):
		manual_attack_hint.text = Game.ui_t("MANUAL_ATTACK_HINT")
	_sync_training_mode_controls()
	_refresh_manual_attack_interval_value()


func _sync_rotation_formation_ui() -> void:
	if not is_node_ready(): return
	var world:Node=get_tree().current_scene
	if not is_instance_valid(world): return
	var enabled:bool=Game.is_rotation_training_mode()
	if enabled and Game.rotation_multi_enabled() and int(world.rotation_selected_round)==0: world.select_rotation_round(1)
	for side:String in ["left","right"]:
		var key:String="__rotation_"+side
		var button:Button=null
		for child:Node in team_box.get_children():
			if child is Button and str(child.get_meta("choice_value",""))==key: button=child;break
		if enabled and button==null:
			button=create_new_but(team_box)
			button.name="RotationBlueTeam" if side=="left" else "RotationRedTeam"
			button.set_meta("choice_value",key);button.set_meta("rotation_reserved",true)
			button.set_meta("_translation_source_text",key)
			var color:Color=Color("418cff") if side=="left" else Color("ef4f50")
			for style:String in ["font_color","font_hover_color","font_pressed_color"]: button.add_theme_color_override(style,color)
			team_box.move_child(button,0 if side=="left" else 1)
		if button!=null:
			button.visible=enabled
			button.text=Game.ui_t(key)
			if not enabled: button.set_pressed_no_signal(false)
	if not enabled and str(world.now_choose_team).begins_with("__rotation_"): change_choose_team("")
	if not enabled:
		if is_instance_valid(rotation_round_panel): rotation_round_panel.hide()
		return
	if not is_instance_valid(rotation_round_panel):
		rotation_round_panel=$Team/Team.duplicate(0)
		rotation_round_panel.name="RotationRounds"
		team.add_child(rotation_round_panel)
		rotation_round_panel.position=$Team/Team.position+Vector2(0,$Team/Team.size.y+36)
		rotation_round_panel.scale=Vector2.ONE
		rotation_round_panel.get_node("Label").hide()
		var add:Button=rotation_round_panel.get_node("CreateButton")
		add.text="+";add.button_up.connect(_add_rotation_round)
		var inner:Control=rotation_round_panel.get_node("Team_Inner")
		for child:Node in inner.get_children():inner.remove_child(child);child.queue_free()
		var scroll:=ScrollContainer.new();inner.add_child(scroll)
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		rotation_round_box=VBoxContainer.new();rotation_round_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		scroll.add_child(rotation_round_box)
		Game.Set_Ui_sfx(rotation_round_panel)
	rotation_round_panel.show()
	rotation_round_panel.get_node("NowTeam").text=Game.ui_t("UI_ROTATION_ROUNDS")
	var signature:String=str([world.rotation_round_numbers(),world.rotation_selected_round,Game.rotation_multi_enabled(),Game.current_locale])
	if signature==_rotation_round_ui_signature: return
	_rotation_round_ui_signature=signature
	for child:Node in rotation_round_box.get_children():rotation_round_box.remove_child(child);child.queue_free()
	var choices:Array=world.rotation_round_numbers()
	if not Game.rotation_multi_enabled():choices.push_front(0)
	var group:=ButtonGroup.new()
	for number:int in choices:
		var button:Button=team_set_button_tem.instantiate()
		button.text=Game.ui_t("UI_ROTATION_AUTO") if number==0 else Game.ui_t("UI_ROTATION_ROUND_N")%number
		button.toggle_mode=true;button.button_group=group
		button.set_pressed_no_signal(number==int(world.rotation_selected_round))
		button.set_meta("rotation_round",number)
		button.pressed.connect(func(): world.select_rotation_round(number))
		rotation_round_box.add_child(button)
	Game.Set_Ui_sfx(rotation_round_box)

func _add_rotation_round() -> void:
	var world:Node=get_tree().current_scene
	if not is_instance_valid(world): return
	var numbers:Array=world.rotation_round_numbers()
	world.select_rotation_round(mini(int(numbers.back())+1,999))

func _create_rotation_count_setting(side:String) -> void:
	var key:String="Rotation_Blue_Count" if side=="left" else "Rotation_Red_Count"
	var row:=HBoxContainer.new();rotation_mode_options.add_child(row)
	row.add_child(_create_setting_title_from_template("SETTING_"+key.to_upper(),64.0)["panel"])
	var spin:=SpinBox.new();spin.name=key;spin.min_value=1;spin.max_value=100;spin.step=1
	spin.rounded=true;spin.suffix="x";spin.select_all_on_focus=true
	spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;spin.custom_minimum_size=Vector2(0,24)
	spin.value_changed.connect(func(value:float):Game.set_runtime_game_setting(key,int(value)))
	row.add_child(spin);_style_settings_spinbox(spin);rotation_count_spins[side]=spin

func _sync_training_mode_controls() -> void:
	_sync_rotation_formation_ui()
	for side:String in rotation_count_spins:
		var spin:SpinBox=rotation_count_spins[side]
		spin.set_value_no_signal(Game.rotation_team_count(side))
		spin.editable=Game.can_local_change_settings()
	if is_instance_valid(rotation_match_label): rotation_match_label.text = Game.ui_t("SETTING_ROTATION_MATCH_TYPE")
	if is_instance_valid(rotation_match_option):
		var keys:Array[String] = ["ROTATION_DUEL","ROTATION_CHALLENGE"]
		for index:int in range(2):
			rotation_match_option.set_item_text(index,Game.ui_t(keys[index]))
			if str(rotation_match_option.get_item_metadata(index)) == ("challenge" if str(Game.Game_Settings.get("Rotation_Match_Type","duel"))=="challenge" else "duel"): rotation_match_option.select(index)
		rotation_match_option.disabled = Game.is_network_guest() and not Game.guest_has_free_permissions()
		rotation_match_option.tooltip_text = Game.ui_t("ROTATION_CHALLENGE_HINT")
	if is_instance_valid(training_mode_label):
		training_mode_label.text = Game.ui_t("SETTING_TRAINING_MODE_TYPE")
	if is_instance_valid(timed_duration_label):
		timed_duration_label.text = Game.ui_t("SETTING_TRAINING_TIME")
	if is_instance_valid(boss_side_label):
		boss_side_label.text = Game.ui_t("SETTING_TRAINING_BOSS_SIDE")
	if is_instance_valid(boss_multiplier_label):
		boss_multiplier_label.text = Game.ui_t("SETTING_TRAINING_BOSS_MULTIPLIER")
	if is_instance_valid(training_mode_option):
		var mode_keys:Array[String] = ["TRAINING_MODE_MANUAL","TRAINING_MODE_ROTATION","TRAINING_MODE_TIMED","TRAINING_MODE_BOSS"]
		for i in range(mini(training_mode_option.item_count,mode_keys.size())):
			training_mode_option.set_item_text(i,Game.ui_t(mode_keys[i]))
		var wanted:String = Game.get_training_mode_type()
		for i in range(training_mode_option.item_count):
			if str(training_mode_option.get_item_metadata(i)) == wanted:
				training_mode_option.select(i)
				break
	if is_instance_valid(timed_duration_spin):
		timed_duration_spin.set_value_no_signal(Game.get_training_timed_duration())
	if is_instance_valid(boss_side_option):
		boss_side_option.set_item_text(0,Game.ui_t("TRAINING_SIDE_LEFT"))
		boss_side_option.set_item_text(1,Game.ui_t("TRAINING_SIDE_RIGHT"))
		var wanted_side:String = Game.get_training_boss_side()
		for i in range(boss_side_option.item_count):
			if str(boss_side_option.get_item_metadata(i)) == wanted_side:
				boss_side_option.select(i)
				break
	if is_instance_valid(boss_multiplier_spin):
		boss_multiplier_spin.set_value_no_signal(Game.get_training_boss_multiplier())
	if is_instance_valid(development_duration_spin):
		development_duration_spin.set_value_no_signal(float(Game.Game_Settings.get("Development_Duration",60.0)))
	if is_instance_valid(development_speed_spin):
		development_speed_spin.set_value_no_signal(float(Game.Game_Settings.get("Development_Speed",2.0)))
	_update_development_options_visibility()


func _update_development_options_visibility() -> void:
	if is_instance_valid(development_options):
		development_options.visible = bool(Game.Game_Settings.get("Development_Mode",false))
		call_deferred("_refresh_settings_scroll_layout")


func _update_training_mode_extra_visibility() -> void:
	var mode:String = Game.get_training_mode_type()
	if is_instance_valid(rotation_mode_options):
		rotation_mode_options.visible = mode == "rotation"
	if is_instance_valid(timed_mode_options):
		timed_mode_options.visible = mode == "timed"
	if is_instance_valid(boss_mode_options):
		boss_mode_options.visible = mode == "boss"
	call_deferred("_refresh_settings_scroll_layout")


func _refresh_settings_scroll_layout() -> void:
	if not is_instance_valid(settings_scroll) or not is_instance_valid(settings_stack):
		return
	# visibility / minimum_size 的变化要等 Container 完成一次排序。
	settings_stack.queue_sort()
	settings_scroll.queue_sort()
	await get_tree().process_frame
	if not is_instance_valid(settings_scroll):
		return
	var bar:VScrollBar = settings_scroll.get_v_scroll_bar()
	if is_instance_valid(bar):
		var max_scroll:int = int(maxf(bar.max_value - bar.page,0.0))
		settings_scroll.scroll_vertical = clampi(settings_scroll.scroll_vertical,0,max_scroll)
		_style_pixel_scroll_container(settings_scroll)


func _on_rotation_match_selected(index:int) -> void:
	if not is_instance_valid(rotation_match_option): return
	Game.set_runtime_game_setting("Rotation_Match_Type",str(rotation_match_option.get_item_metadata(index)))

func _on_training_mode_type_selected(index:int) -> void:
	if not is_instance_valid(training_mode_option):
		return
	var metadata:Variant = training_mode_option.get_item_metadata(index)
	var mode:String = str(metadata)
	if mode not in ["manual","rotation","timed","boss"]:
		mode = "manual"
	# 玩法类型独立于“训练模式”开关：轮放/计时/Boss 选择后直接按各自规则运行。
	Game.set_runtime_game_setting("Training_Mode_Type",mode)
	_update_training_mode_extra_visibility()
	_refresh_game_setting_toggle_visuals()


func _on_timed_duration_changed(value:float) -> void:
	Game.set_runtime_game_setting("Training_Timed_Duration",maxf(roundf(value),1.0))


func _on_boss_side_selected(index:int) -> void:
	if not is_instance_valid(boss_side_option):
		return
	var metadata:Variant = boss_side_option.get_item_metadata(index)
	var side:String = str(metadata)
	if side not in ["left","right"]:
		side = "right"
	Game.set_runtime_game_setting("Training_Boss_Side",side)


func _on_boss_multiplier_changed(value:float) -> void:
	var factor:float = maxf(snappedf(value,0.1),1.0)
	Game.set_runtime_game_setting("Training_Boss_Multiplier",factor)


func _update_manual_training_options_visibility() -> void:
	if is_instance_valid(manual_training_options):
		manual_training_options.visible = bool(Game.Game_Settings.get("Manual_Training", false))


func _on_manual_attack_interval_changed(value:float) -> void:
	Game.set_manual_training_attack_interval(value, false)
	_refresh_manual_attack_interval_value()


func _on_manual_attack_interval_drag_ended(value_changed:bool) -> void:
	if value_changed:
		Game.save_persistent_settings()


func _refresh_manual_attack_interval_value() -> void:
	if not is_instance_valid(manual_attack_interval_value_label):
		return
	manual_attack_interval_value_label.text = "%.2fs" % Game.get_manual_training_attack_interval()


func _style_character_search() -> void:
	if not is_instance_valid(char_search):
		return

	# 搜索框使用独立、克制的像素样式。深色底把它和角色按钮区分开，
	# 但边框/文字仍沿用设置面板的米黄色系。
	char_search.custom_minimum_size = Vector2(0, 24)
	char_search.add_theme_font_size_override("font_size", 9)
	char_search.add_theme_color_override("font_color", Color(0.96, 0.92, 0.80, 1.0))
	char_search.add_theme_color_override("font_placeholder_color", Color(0.82, 0.77, 0.64, 0.62))
	char_search.add_theme_color_override("caret_color", Color(0.95, 0.88, 0.64, 1.0))
	char_search.add_theme_color_override("selection_color", Color(0.52, 0.46, 0.30, 0.72))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.14, 0.11, 0.92)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.48, 0.43, 0.31, 0.94)
	normal.content_margin_left = 6.0
	normal.content_margin_right = 5.0
	normal.content_margin_top = 3.0
	normal.content_margin_bottom = 3.0

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.82, 0.75, 0.52, 1.0)
	focus.bg_color = Color(0.18, 0.16, 0.12, 0.98)

	char_search.add_theme_stylebox_override("normal", normal)
	char_search.add_theme_stylebox_override("focus", focus)
	char_search.add_theme_stylebox_override("read_only", normal)


func _style_pixel_scroll_container(scroll:ScrollContainer) -> void:
	if not is_instance_valid(scroll):
		return
	var bar:VScrollBar = scroll.get_v_scroll_bar()
	if not is_instance_valid(bar):
		return

	# 使用和现有米黄色面板接近的硬边像素风，而不是 Godot 默认的圆润白色滚动条。
	bar.custom_minimum_size.x = 8.0
	bar.add_theme_constant_override("padding_left", 1)
	bar.add_theme_constant_override("padding_right", 1)
	bar.focus_mode = Control.FOCUS_NONE

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.30, 0.27, 0.19, 0.58)
	track.border_width_left = 1
	track.border_width_top = 1
	track.border_width_right = 1
	track.border_width_bottom = 1
	track.border_color = Color(0.12, 0.11, 0.08, 0.88)
	track.content_margin_top = 1.0
	track.content_margin_bottom = 1.0

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.72, 0.66, 0.49, 1.0)
	grabber.border_width_left = 1
	grabber.border_width_top = 1
	grabber.border_width_right = 1
	grabber.border_width_bottom = 1
	grabber.border_color = Color(0.16, 0.14, 0.10, 1.0)
	grabber.content_margin_left = 2.0
	grabber.content_margin_right = 2.0

	var grabber_hover := grabber.duplicate() as StyleBoxFlat
	grabber_hover.bg_color = Color(0.82, 0.76, 0.58, 1.0)
	var grabber_pressed := grabber.duplicate() as StyleBoxFlat
	grabber_pressed.bg_color = Color(0.60, 0.55, 0.40, 1.0)

	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hover)
	bar.add_theme_stylebox_override("grabber_pressed", grabber_pressed)

	# 1x1 透明箭头，移除默认主题自带的大白色上下箭头。
	var empty_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	empty_image.fill(Color(0, 0, 0, 0))
	var empty_texture := ImageTexture.create_from_image(empty_image)
	for icon_name:String in [
		"decrement", "decrement_highlight", "decrement_pressed",
		"increment", "increment_highlight", "increment_pressed"
	]:
		bar.add_theme_icon_override(icon_name, empty_texture)


func _configure_settings_middle_drag() -> void:
	if not is_instance_valid(game_setting):
		return
	_connect_settings_middle_drag_recursive(game_setting)
	# VScrollBar 是 ScrollContainer 的内部控件，显式再连一次。
	if is_instance_valid(settings_scroll):
		_connect_settings_middle_drag_recursive(settings_scroll.get_v_scroll_bar())


func _connect_settings_middle_drag_recursive(node:Node) -> void:
	if node is Control:
		var control_node:Control = node as Control
		var callback:Callable = _on_settings_middle_drag_gui_input.bind(control_node)
		if not control_node.gui_input.is_connected(callback):
			control_node.gui_input.connect(callback)
	for child:Node in node.get_children():
		_connect_settings_middle_drag_recursive(child)


func _on_settings_middle_drag_gui_input(event:InputEvent, source:Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_settings_middle_dragging = event.is_pressed()
		Game.mouse_drag = false
		source.accept_event()
		return

	if event is InputEventMouseMotion and _settings_middle_dragging:
		Game.mouse_drag = false
		if is_instance_valid(settings_scroll):
			var bar:VScrollBar = settings_scroll.get_v_scroll_bar()
			var max_scroll:int = int(maxf(bar.max_value - bar.page, 0.0)) if is_instance_valid(bar) else 0
			settings_scroll.scroll_vertical = clampi(
				settings_scroll.scroll_vertical - roundi(event.relative.y),
				0,
				max_scroll
			)
		source.accept_event()


func _configure_character_middle_drag() -> void:
	if not is_instance_valid(char_scroll):
		return
	_connect_character_middle_drag_recursive(char_scroll)
	_connect_character_middle_drag_recursive(char_scroll.get_v_scroll_bar())


func _connect_character_middle_drag_recursive(node:Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		var control_node:Control = node as Control
		var callback:Callable = _on_character_middle_drag_gui_input.bind(control_node)
		if not control_node.gui_input.is_connected(callback):
			control_node.gui_input.connect(callback)
	for child:Node in node.get_children():
		_connect_character_middle_drag_recursive(child)


func _on_character_middle_drag_gui_input(event:InputEvent, source:Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_character_middle_dragging = event.is_pressed()
		Game.mouse_drag = false
		source.accept_event()


func _scroll_character_list_by(amount:float) -> void:
	_scroll_container_by(char_scroll,amount)


func _scroll_container_by(scroll:ScrollContainer,amount:float) -> void:
	if not is_instance_valid(scroll):
		return
	var bar:VScrollBar = scroll.get_v_scroll_bar()
	var max_scroll:int = int(maxf(bar.max_value - bar.page, 0.0)) if is_instance_valid(bar) else 0
	scroll.scroll_vertical = clampi(
		scroll.scroll_vertical + roundi(amount),
		0,
		max_scroll
	)


func _configure_map_middle_drag() -> void:
	if not is_instance_valid(map_scroll):
		return
	_connect_map_middle_drag_recursive(map_scroll)
	_connect_map_middle_drag_recursive(map_scroll.get_v_scroll_bar())


func _connect_map_middle_drag_recursive(node:Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		var control_node:Control = node as Control
		var callback:Callable = _on_map_middle_drag_gui_input.bind(control_node)
		if not control_node.gui_input.is_connected(callback):
			control_node.gui_input.connect(callback)
	for child:Node in node.get_children():
		_connect_map_middle_drag_recursive(child)


func _on_map_middle_drag_gui_input(event:InputEvent, source:Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_map_middle_dragging = event.is_pressed()
		Game.mouse_drag = false
		source.accept_event()


func _populate_manual_attack_options() -> void:
	if not is_instance_valid(manual_attack_option):
		return
	manual_attack_option.clear()
	var catalog:Array[Dictionary] = Game.get_manual_attack_catalog()
	if catalog.is_empty():
		manual_attack_option.add_item(Game.ui_t("MANUAL_NO_ATTACKS"))
		manual_attack_option.disabled = true
		return

	manual_attack_option.disabled = false
	var selected_index:int = 0
	var current_id:String = Game.get_manual_training_attack()
	for entry:Dictionary in catalog:
		var index:int = manual_attack_option.item_count
		manual_attack_option.add_item(Game.ui_t(str(entry.get("label", entry.get("id", "MANUAL_ATTACK_LABEL")))))
		manual_attack_option.set_item_metadata(index, str(entry.get("id", "")))
		if str(entry.get("id", "")) == current_id:
			selected_index = index
	manual_attack_option.select(selected_index)
	var selected_meta:Variant = manual_attack_option.get_item_metadata(selected_index)
	if selected_meta != null:
		Game.set_manual_training_attack(str(selected_meta))


func _on_manual_attack_selected(index:int) -> void:
	if not is_instance_valid(manual_attack_option):
		return
	if index < 0 or index >= manual_attack_option.item_count:
		return
	var metadata:Variant = manual_attack_option.get_item_metadata(index)
	if metadata != null:
		Game.set_manual_training_attack(str(metadata))


func _create_language_setting_at_top() -> void:
	language_button = Button.new()
	language_button.name = "LanguageButton"
	language_button.custom_minimum_size = Vector2(0,26)
	language_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_button.pressed.connect(_on_language_button_pressed)
	set_box.add_child(language_button)
	Game.Set_Ui_sfx(language_button)


func _on_language_button_pressed() -> void:
	# TranslationServer 会发 NOTIFICATION_TRANSLATION_CHANGED，统一由通知路径刷新 UI。
	Game.toggle_language()


func _refresh_multiplayer_permissions_ui() -> void:
	if not is_node_ready():
		return
	_sync_character_mode_controls()
	var restricted_guest:bool = Game.is_network_guest() and not Game.guest_has_free_permissions()
	# 受限房客顶部只保留“队伍 / 多人”。角色仍从队伍面板右侧选择并可正常放置。
	if is_instance_valid(toolbar_game_setting_button): toolbar_game_setting_button.visible = not restricted_guest
	if is_instance_valid(toolbar_reset_button): toolbar_reset_button.visible = not restricted_guest
	if is_instance_valid(toolbar_rematch_button): toolbar_rematch_button.visible = not restricted_guest
	if is_instance_valid(toolbar_map_button): toolbar_map_button.visible = not restricted_guest
	if is_instance_valid(toolbar_team_button): toolbar_team_button.visible = true
	if is_instance_valid(toolbar_multiplayer_button): toolbar_multiplayer_button.visible = true
	if is_instance_valid(team_create_button):
		team_create_button.visible = not restricted_guest
		team_create_button.disabled = restricted_guest
	if restricted_guest:
		game_setting.hide()
		map.hide()
	# HBox 子项变化后重新按真实宽度居中。
	call_deferred("apply_portrait_layout")

#按settings按钮
@onready var game_setting: Panel = $Game_Setting

func _request_toolbar_rematch(exact_replay:bool) -> void:
	if not Game.can_local_manage_world():
		return
	var world:World = get_tree().current_scene
	if world == null:
		return
	# 左键完整重演；右键只复用地图 / 人物 / 出生位置并重新随机。
	game_setting.hide()
	team.hide()
	map.hide()
	multi_player.hide()
	Game.request_world_rematch(exact_replay)
	call_deferred("_refresh_runtime_translations")


func _ensure_battle_record_controls() -> Node:
	if not is_instance_valid(_battle_record_controls):
		_battle_record_controls = preload("res://scripts/ui/battle_record_controls.gd").new()
		_battle_record_controls.name = "BattleRecordControls"
		add_child(_battle_record_controls)
		_battle_record_controls.setup($Settings/HBoxContainer/Record)
	return _battle_record_controls


func _on_record_button_up() -> void:
	_ensure_battle_record_controls().toggle_live()


func _on_record_button_gui_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_ensure_battle_record_controls().start_simulated()
		$Settings/HBoxContainer/Record.accept_event()


func _on_rematch_button_up() -> void:
	_request_toolbar_rematch(true)


func _on_rematch_button_gui_input(event:InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event:InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	_request_toolbar_rematch(false)
	toolbar_rematch_button.accept_event()


func _on_game_setting_button_up() -> void:
	if not Game.can_local_change_settings():
		return
	team.hide()
	map.hide()
	multi_player.hide()
	game_setting.visible = not game_setting.visible
	if not game_setting.visible and is_instance_valid(effect_preview_panel) and effect_preview_panel.has_method("set_preview_active"):
		effect_preview_panel.call("set_preview_active", false)
	elif game_setting.visible:
		_refresh_game_setting_toggle_visuals()
		# 每次打开设置默认回到训练分类。
		_show_settings_category("training")
func _on_team_button_up() -> void:
	game_setting.hide()
	map.hide()
	multi_player.hide()
	team.visible = not team.visible
func _on_map_button_up() -> void:
	if not Game.can_local_manage_world():
		return
	game_setting.hide()
	team.hide()
	multi_player.hide()
	map.visible = not map.visible

#多人游戏
@onready var multi_player: Panel = $MultiPlayer
# 节点名仍叫 Port 只为兼容旧场景；V126 起它实际输入的是“服务器地址/IP”，端口固定为 Game.port。
@onready var port: LineEdit = $MultiPlayer/MultiPlayer_Inner/HBoxContainer/Port
@onready var ip_label: Label = $MultiPlayer/Ip_Label
@onready var connect_label: Label = $MultiPlayer/Connect_Label
@onready var player_list: Panel = $MultiPlayer/Player_list
@onready var player_list_box: VBoxContainer = $MultiPlayer/Player_list/Player_list_Inner/VBoxContainer

func _on_multi_player_button_up() -> void:
	game_setting.hide()
	team.hide()
	map.hide()
	multi_player.visible = not multi_player.visible
	if multi_player.visible:
		_layout_multiplayer_panel()
		Game.request_room_scan(true)
		change_connect_state()

func _on_client_button_up() -> void:
	# 空地址默认连接同一台电脑的 127.0.0.1，便于本机双开测试。
	Game.join_game(port.text)
	change_connect_state()

func _on_server_button_up() -> void:
	Game.host_game()
	change_connect_state()
#地图
@onready var map: Panel = $Map
@onready var map_scroll: ScrollContainer = $Map/Map_Inner/ScrollContainer
@onready var map_box: VBoxContainer = $Map/Map_Inner/ScrollContainer/VBoxContainer
func set_map_buts() -> void:
	for c in get_parent().get_parent().get_children():
		if c is TileMapLayer or c is PortalMap:
			var but:Button = create_new_but(map_box)
			but.set_meta("choice_value", str(c.name))
			but.text = Game.ui_t(str(c.name))
			but.name = c.name
			if c.name == get_tree().current_scene.default_map:
				but.self_modulate = Color(0.671, 0.671, 0.671, 0.675)
	# 按钮建好后再绑一次：中键拖动要能从按钮上开始。
	_configure_map_middle_drag()
#队伍设置
	#通用
		#改变世界设置和文本
func change_choose_team(team_value:String,Type:String = "now_choose_team") -> void:
	if Type == "now_choose_team":
		get_tree().current_scene.now_choose_team = team_value
		now_team.text = Game.ui_t("UI_NOW_TEAM") + " " + (Game.ui_t(team_value) if not team_value.is_empty() else Game.ui_t("UI_NONE"))
	elif Type == "now_choose_map":
		if not Game.can_local_manage_world():
			return
		var target_map:String = get_tree().current_scene.default_map if team_value == "" else team_value
		Game.request_map_choice(target_map)
		if team_value == "" and map_box.has_node(get_tree().current_scene.default_map):
			map_box.get_node(get_tree().current_scene.default_map).self_modulate = Color(0.671, 0.671, 0.671, 0.675)
	else:
		get_tree().current_scene.now_choose_char = team_value
		now_char.text = Game.ui_t("UI_NOW_CHAR") + " " + (Game.ui_t(team_value) if not team_value.is_empty() else Game.ui_t("UI_NONE"))
		
		#恢复box中所有bug颜色
func set_team_buts_color(parent) -> void:
	for i in parent.get_children():
		i.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
		#设置选择
func _on_team_button_toggled(toggled_on:bool, but:Button) -> void:
	var choice_value:String = str(
		but.get_meta(
			"choice_value",
			but.text
		)
	)

	if toggled_on:
		change_choose_team(
			choice_value,
			"now_choose_team"
		)
	else:
		var world = get_tree().current_scene
		if (
			world != null
			and str(world.now_choose_team) == choice_value
		):
			change_choose_team(
				"",
				"now_choose_team"
			)

	_refresh_team_button_colors()


func _refresh_team_button_colors() -> void:
	for child in team_box.get_children():
		if not child is Button:
			continue

		var team_button:Button = child
		team_button.self_modulate = (
			Color(0.671, 0.671, 0.671, 0.675)
			if team_button.button_pressed
			else Color(1.0, 1.0, 1.0, 1.0)
		)


func set_team_button_callable_choose(but:Button) -> void:
	if but.get_parent() == char_box and str(Game.Game_Settings.Character_Placement_Mode)=="random":
		_toggle_random_character_exclusion(but)
		return
	var Type:String = "now_choose_team"
	if but.get_parent() == map_box:Type = "now_choose_map"
	elif but.get_parent() == char_box: Type = "now_choose_char"

	# 文本可以是 Cow / Calf / Delta，但游戏内部仍使用 牛 / 牛犊子 / 三角洲。
	var choice_value:String = str(but.get_meta("choice_value", but.text))
	var now_choose:String = str(get_tree().current_scene.get(Type))
	if now_choose == choice_value:
		change_choose_team("",Type)
		if Type != "now_choose_map" or now_choose != get_tree().current_scene.default_map:
			but.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		change_choose_team(choice_value,Type)
		if Type == "now_choose_team":set_team_buts_color(team_box)
		elif Type == "now_choose_map":set_team_buts_color(map_box)
		else:set_team_buts_color(char_box)
		but.self_modulate = Color(0.671, 0.671, 0.671, 0.675)

			#恢复box中所有bug颜色
func create_new_but(parent) -> Button:
	var new_team_but:Button = team_set_button_tem.instantiate()
	parent.add_child(new_team_but)

	if parent == team_box:
		new_team_but.toggle_mode = true
		new_team_but.button_group = team_button_group
		Game.should_connect(
			new_team_but.toggled,
			_on_team_button_toggled.bind(
				new_team_but
			)
		)
	else:
		Game.should_connect(
			new_team_but.button_up,
			set_team_button_callable_choose.bind(
				new_team_but
			)
		)

	return new_team_but

	#队伍
@onready var now_team: Label = $Team/Team/NowTeam
func return_random_team() -> String:
	var choices:Array[String]=[]
	for button:Node in team_box.get_children():
		if not button is Button: continue
		if button.has_meta("rotation_reserved") and not Game.is_rotation_training_mode(): continue
		choices.append(str(button.get_meta("choice_value",button.text)))
	return choices.pick_random() if not choices.is_empty() else ""

func reset_team_buts() -> void:
	var pressed_team:String = ""
	var user_index:int=0

	for i in team_box.get_children():
		if not i is Button:
			continue

		var team_button:Button = i
		if team_button.has_meta("rotation_reserved"):
			if team_button.button_pressed and Game.is_rotation_training_mode(): pressed_team=str(team_button.get_meta("choice_value"))
			continue
		var team_name:String = (
			"Team"
			+ str(user_index)
		)
		user_index+=1

		team_button.text = team_name
		team_button.set_meta(
			"choice_value",
			team_name
		)

		if team_button.button_pressed:
			pressed_team = team_name

	# 编号变化后，逻辑选择必须跟着真正按下的按钮走。
	# 一个都没按下时就是空队伍。
	change_choose_team(
		pressed_team,
		"now_choose_team"
	)

	_refresh_team_button_colors()
	Game.Set_Ui_sfx(team_box)

func set_team_button_callable_delete(event:InputEvent,but:Button) -> void:
	if but.has_meta("rotation_reserved"): return
	if not Game.can_local_edit_team_structure():
		return
	if event.is_echo():
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		Audios.play_sfx(
			"ButtonUpMouseOut",
			{},
			true
		)

		for child in team_box.get_children():
			if child is Button:
				child.set_pressed_no_signal(false)

		change_choose_team(
			"",
			"now_choose_team"
		)
		but.queue_free()

		# queue_free 在帧末真正移除节点，
		# 所以延迟到下一轮再按真实索引重编号。
		call_deferred(
			"reset_team_buts"
		)

func _on_create_button_button_up() -> void:
	if not Game.can_local_edit_team_structure():
		return
	var new_but:Button = create_new_but(team_box)
	Game.should_connect(new_but.gui_input,set_team_button_callable_delete.bind(new_but))
	reset_team_buts()
	#角色
@onready var now_char: Label = $Team/Char/NowChar
@onready var now_type: Label = $Team/Char/NowType

func Create_char_buts() -> void:
	var tree = get_tree()
	var world:World = tree.current_scene

	# 角色列表现在由 ScrollContainer 负责滚动，切分类时回到顶部。
	char_box.alignment = BoxContainer.ALIGNMENT_BEGIN

	for child in char_box.get_children():
		child.hide()
		child.queue_free()
	
	var search_query:String = char_search.text.strip_edges() if is_instance_valid(char_search) else ""
	var character_names:Array[String] = []
	if search_query.is_empty():
		for raw_name:Variant in tree.current_scene.Characters_Dic.keys():
			character_names.append(str(raw_name))
	else:
		# 有搜索词时跨所有角色分类查找，解决“人在别的分类里搜不到”的问题。
		character_names = world.return_all_character_names()

	for character_name:String in character_names:
		var new_but:Button = create_new_but(char_box)
		new_but.set_meta("choice_value", character_name)
		new_but.text = Game.ui_t(character_name)

	_sync_random_character_picker()
	_apply_character_search_filter(search_query)
	Game.Set_Ui_sfx(char_box)
	# 搜索会重建按钮；每次重建后重新把中键拖动绑定到新按钮。
	_configure_character_middle_drag()
	char_box.queue_sort()
	call_deferred("_reset_char_list_to_top")
	now_type.text = Game.ui_t("UI_NOW_TYPE") + " " + Game.ui_t(world.return_now_char_type())


func _reset_char_list_to_top() -> void:
	if not is_instance_valid(char_box):
		return
	char_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	char_box.queue_sort()
	if is_instance_valid(char_scroll):
		char_scroll.set_deferred("scroll_vertical",0)


func _on_character_search_changed(_text:String) -> void:
	# 搜索时重建列表，以便跨分类查找；清空搜索后恢复当前分类。
	Create_char_buts()


func _apply_character_search_filter(query:String) -> void:
	if not is_instance_valid(char_box):
		return
	var wanted:String = query.strip_edges().to_lower()
	for child:Node in char_box.get_children():
		if child.is_queued_for_deletion() or not child is Button:
			continue
		var button:Button = child as Button
		var raw_name:String = str(button.get_meta("choice_value",button.text))
		var searchable:String = (raw_name + " " + Game.t(raw_name) + " " + Game.ui_t(raw_name)).to_lower()
		button.visible = wanted.is_empty() or searchable.contains(wanted)
	
func _on_left_button_up() -> void:
	var tree = get_tree()
	var world:World = tree.current_scene
	
	if world.now_char_folder_index <= 0:
		var max_index = world.return_max_char_index()
		world.now_char_folder_index = max_index
	else:
		world.now_char_folder_index = world.now_char_folder_index - 1
	
	Create_char_buts()
func _on_right_button_up() -> void:
	var tree = get_tree()
	var world:World = tree.current_scene
	
	var max_index = world.return_max_char_index()
	if world.now_char_folder_index >= max_index:
		world.now_char_folder_index = 0
	else:
		world.now_char_folder_index = world.now_char_folder_index + 1
		
	Create_char_buts()
	
#开关菜单
func is_set_team() -> bool:
	return team.visible
func set_menu() -> void:
	if visible:
		map.hide()
		team.hide()
		game_setting.hide()
		multi_player.hide()
		
	visible = not visible
	Audios.play_sfx("ButtonDown1",{},true)
	
func _on_reset_button_up() -> void:
	if not Game.can_local_manage_world():
		return
	Game.request_world_reset()
	
