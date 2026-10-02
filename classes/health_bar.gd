class_name Health_bar
extends Control

signal health_changed(last_health:int,health:int,max_health:int,if_tween:bool)
signal block_changed(last_block:int,block:int,max_block:int,if_tween:bool)
signal energy_changed(last_energy:int,energy:int,max_energy:int,if_tween:bool)

var damage_text := preload("res://scenes/damage_text.tscn")
@onready var texture_rect:TextureRect = $TextureRect
@onready var health_bar:TextureProgressBar = $TextureRect/Health
@onready var block_bar:TextureProgressBar = $TextureRect/Block
@onready var energy_outside:ColorRect = $Energy_Bar
@onready var energy_bar:TextureProgressBar = $Energy_Bar/Energy
@onready var label:Label = $TextureRect/Label

var damage_text_offset_range:float = 10
var _bar_tweens:Dictionary = {}
const HEALTH_NUMBER_HIT_SCALE:float = 1.25
const HEALTH_NUMBER_HIT_GROW_TIME:float = 0.075
const HEALTH_NUMBER_HIT_SETTLE_TIME:float = 0.32
var _health_number_base_scale:Vector2 = Vector2.ONE
var _health_number_hit_tween:Tween = null
# 受伤残影：失去的那段先留一条半透明白色，停一下再缩到当前生命；同时整条血条按损失比例抖一下。
const DAMAGE_GHOST_HOLD:float = 0.12
const DAMAGE_GHOST_DRAIN:float = 0.2
const DAMAGE_GHOST_COLOR:Color = Color(1.0,1.0,1.0,0.9)
const DAMAGE_GHOST_SETTLED_ALPHA:float = 0.55
const BAR_SHAKE_DURATION:float = 0.22
const BAR_SHAKE_MIN_DROP_RATIO:float = 0.01
const BAR_SHAKE_MAX_PIXELS:float = 95.0
var _damage_ghost_bar:TextureProgressBar = null
var _damage_ghost_tween:Tween = null
var _bar_shake_tween:Tween = null
var _bar_shake_pixels:float = 0.0
var _bar_shake_base_position:Vector2 = Vector2.ZERO
var _bar_shake_base_captured:bool = false
## 0 disables the visual drop limit for characters requiring complete feedback.
@export var max_live_damage_texts:int = 80

# V65：伤害跳字达到 11 位数后不再显示超长数字，统一显示循环彩色 INF。
# “超过十位数”即 >= 10,000,000,000；真正的浮点 INF 也走同一视觉。
const INFINITE_DAMAGE_DISPLAY_THRESHOLD:float = 10_000_000_000.0

const CHARACTER_HEALTH_BAR_SCALE_MULTIPLIER:float = 0.9
const CHARACTER_HEALTH_BAR_SHADER:Shader = preload("res://shaders/ui/角色十字血条.gdshader")
const ABSORPTION_GOLD_SHADER:Shader = preload("res://shaders/ui/吸收金光.gdshader")
# V411：十字血条没有 per-material 参数，所有人物可安全共享同一 ShaderMaterial；
# 个体差异继续由 CanvasItem 自身属性/instance 参数承担。
static var _shared_character_health_bar_material:ShaderMaterial = null

@export_category("生命阈值标记")
# health_bar.tscn 的生命条最终会被整体缩小，因此这里用生命条局部坐标的厚度。
# 22px 在角色当前 0.06 * 0.9 * 0.95 的默认显示缩放下约为 1.13 个屏幕像素。
@export_range(4.0,80.0,1.0) var health_threshold_marker_thickness:float = 22.0
var _health_threshold_markers:Array[ColorRect] = []
var _health_threshold_signature:String = ""
var _has_health_threshold_provider:bool = false
# 用于角色换形/节点替换时同步生命、护盾等 UI，避免把“状态迁移”误显示成受伤/回血。
var suppress_floating_text:bool = false
# V146：批量伤害可只对“下一次”血量变化关闭 Tween/跳字；消费后自动恢复。
var force_instant_update_once:bool = false

# V149：Sans KARMA（业力）预览层。
# 每个来源保存自己的待结算值，最终只把“当前真实生命中、未来会被 KR 扣掉的那一段”染成粉紫色。
# 生命数字只按真实生命百分比显示黑/白，不跟随 KARMA 的粉紫色；真正扣血由业力效果结算。
const KARMA_PREVIEW_COLOR:Color = Color(1.0,0.0,1.0,1.0)
var _karma_bar:TextureProgressBar = null
var _karma_sources:Dictionary = {}
var _absorption_bar:TextureProgressBar = null
var _absorption_source_id:int = 0

# V269：角色可在真正无敌窗口把公共血条切成 INF + 金色脉冲发光。
# 只改变显示，不篡改 owner.health / Max_health，也不影响投射物 Health_Bar。
const INVINCIBLE_GOLD_DARK:Color = Color(0.95,0.53,0.04,1.0)
const INVINCIBLE_GOLD_BRIGHT:Color = Color(1.0,0.94,0.34,1.0)
var _invincible_display:bool = false
var _invincible_glow_tween:Tween = null
var _normal_health_self_modulate:Color = Color.WHITE
var _normal_label_font_color:Color = Color.BLACK
var _normal_label_outline_color:Color = Color(0.0,0.0,0.0,0.0)
var _normal_label_shadow_color:Color = Color(0.0,0.0,0.0,0.0)
var _normal_label_outline_size:int = 0

# Large (900 px) legacy health digits otherwise rasterize a new huge outlined
# bitmap on the first occurrence of EACH digit. MSDF keeps the same layout/size
# while rasterizing a small, shared distance-field glyph instead.
static var _mc_number_fonts:Dictionary = {}
static func prepare_minecraft_number_label(number:Label) -> void:
	var original:Font = number.get_theme_font("font")
	if not original is FontFile or original.multichannel_signed_distance_field: return
	var key:int = original.get_instance_id()
	if not _mc_number_fonts.has(key):
		var font:FontFile = original.duplicate() as FontFile
		font.multichannel_signed_distance_field = true
		font.msdf_size = 64
		font.msdf_pixel_range = 32
		_mc_number_fonts[key] = font
	number.add_theme_font_override("font",_mc_number_fonts[key])

func _ready() -> void:
	if owner != null and owner.scene_file_path.begins_with("res://scenes/characters/我的世界/"):
		prepare_minecraft_number_label(label)
	_apply_character_health_bar_visual()
	# V410：Sans KARMA 预览条改为首次真正出现业力时再复制，普通角色少一个 Control 节点。
	_set_hud_mouse_filter_ignore(self)
	_prepare_normal_health_label_style()
	_normal_health_self_modulate = health_bar.self_modulate
	_normal_label_font_color = label.get_theme_color("font_color")
	_normal_label_outline_color = label.get_theme_color("font_outline_color")
	_normal_label_shadow_color = label.get_theme_color("font_shadow_color")
	_normal_label_outline_size = label.get_theme_constant("outline_size")
	_label_base_font_size = label.get_theme_font_size("font_size")
	_health_number_base_scale = label.scale
	# 缩放只作用于数字；随 Label 布局变化仍以数字中心为轴，不挪动血条。
	label.pivot_offset_ratio = Vector2(0.5,0.5)
	health_changed.connect(when_value_changed.bind(health_bar))
	block_changed.connect(when_value_changed.bind(block_bar))
	energy_changed.connect(when_value_changed.bind(energy_bar))
	when_value_changed(owner.max_block,0,owner.max_block,false,block_bar)
	when_value_changed(owner.Max_health,owner.Max_health,owner.Max_health,false,health_bar)
	when_value_changed(owner.max_energy,owner.max_energy,owner.max_energy,false,energy_bar)

	# 只有明确提供“生命阈值”接口的角色才显示黑线。
	# 子节点的 _ready() 早于角色本体 _ready()，因此再延后一帧刷新一次，
	# 同时 _process() 只对这些少数角色开启，以兼容 Max_health 运行时变化。
	_has_health_threshold_provider = owner != null and owner.has_method("get_health_threshold_values")
	set_process(_has_health_threshold_provider)
	if _has_health_threshold_provider:
		call_deferred("_refresh_health_threshold_markers",true)


func _prepare_normal_health_label_style() -> void:
	# Old scenes can embed their own copy of the health bar; normalize once on enter.
	label.add_theme_color_override("font_color",Color.BLACK)
	label.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.0))
	label.add_theme_color_override("font_shadow_color",Color(0.0,0.0,0.0,0.0))
	for key:String in ["outline_size","shadow_outline_size","shadow_offset_x","shadow_offset_y"]:
		label.add_theme_constant_override(key,0)


func _set_hud_mouse_filter_ignore(node:Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child:Node in node.get_children():
		_set_hud_mouse_filter_ignore(child)


func _is_character_health_bar_owner() -> bool:
	if owner == null or not is_instance_valid(owner):
		return false

	# 只认角色场景。投射物虽然也继承 ball.tscn 并拥有 Health_Bar，
	# 但它们位于 scenes/shooter/ 等目录，不能套用人物血条视觉。
	var scene_path:String = owner.scene_file_path
	if scene_path.begins_with("res://scenes/characters/"):
		return true

	# 极少数运行时派生节点可能没有 scene_file_path；只在脚本明确位于
	# scripts/characters/ 时做保守兜底，仍不会把 shooter/ 当人物。
	var owner_script:Script = owner.get_script() as Script
	if owner_script != null:
		var script_path:String = owner_script.resource_path
		return script_path.begins_with("res://scripts/characters/")

	return false


func _apply_character_health_bar_visual() -> void:
	if not _is_character_health_bar_owner():
		return

	# 用户要求人物头顶血条整体缩小10%。乘现有实例scale，保留个别角色
	# 在场景里已经做过的自定义缩放，不把它们强制统一成固定值。
	scale *= CHARACTER_HEALTH_BAR_SCALE_MULTIPLIER

	# 原图继续复用，不创建替代图片。Shader只扩大四角透明缺口，让轮廓
	# 更接近明确的“十字”而不是带小缺口的方框。
	# V411：旧版每个人物都 new 一份内容完全相同的 ShaderMaterial。
	# 共享材质减少 50+ 人时的 Material 数量与渲染状态管理，不改变 Shader 或任何显示参数。
	if _shared_character_health_bar_material == null:
		_shared_character_health_bar_material = ShaderMaterial.new()
		_shared_character_health_bar_material.shader = CHARACTER_HEALTH_BAR_SHADER
	texture_rect.material = _shared_character_health_bar_material
	health_bar.material = _shared_character_health_bar_material
	block_bar.material = _shared_character_health_bar_material


func _setup_karma_preview_bar() -> void:
	if health_bar == null or health_bar.get_parent() == null:
		return
	if _karma_bar != null and is_instance_valid(_karma_bar):
		return

	var duplicate_node:Node = health_bar.duplicate()
	_karma_bar = duplicate_node as TextureProgressBar
	if _karma_bar == null:
		return

	_karma_bar.name = "SansKarmaPreview"
	_karma_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_karma_bar.visible = false
	_karma_bar.z_index = health_bar.z_index
	_karma_bar.modulate = Color.WHITE
	_karma_bar.self_modulate = KARMA_PREVIEW_COLOR

	var parent_node:Node = health_bar.get_parent()
	parent_node.add_child(_karma_bar)
	# 同 z_index 时，后绘制的 sibling 在上方。把 KARMA 放到正常生命条之前，
	# 于是正常生命覆盖“安全生命”区间，而 KARMA 层只从安全生命末端延伸到当前生命。
	# 这样紫色永远属于当前还真实存在的生命，不是额外增加的一条预览条。
	parent_node.move_child(_karma_bar,health_bar.get_index())

func _setup_absorption_bar() -> void:
	if not _is_character_health_bar_owner() or not is_instance_valid(health_bar): return
	if is_instance_valid(_absorption_bar): return
	# Same silhouette, position and size as the existing health bar. Its fill
	# starts at the TOP and can only occupy pixels INSIDE that bar; no new bar.
	_absorption_bar = health_bar.duplicate() as TextureProgressBar
	_absorption_bar.name = "AbsorptionInsideHealth"
	_absorption_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_absorption_bar.visible = false
	_absorption_bar.step = 0.0
	_absorption_bar.fill_mode = TextureProgressBar.FILL_TOP_TO_BOTTOM
	_absorption_bar.modulate = Color.WHITE
	_absorption_bar.self_modulate = Color.WHITE
	_absorption_bar.z_index = health_bar.z_index
	var gold_material:ShaderMaterial = ShaderMaterial.new()
	gold_material.shader = ABSORPTION_GOLD_SHADER
	_absorption_bar.material = gold_material
	var parent_node:Node = health_bar.get_parent()
	parent_node.add_child(_absorption_bar)
	# Draw over ordinary HP but under its number and any real block shield.
	parent_node.move_child(_absorption_bar,health_bar.get_index()+1)

func set_absorption_visual(amount:float,source_id:int) -> void:
	if not _is_character_health_bar_owner(): return
	_absorption_source_id = source_id
	if amount <= 0.0:
		if is_instance_valid(_absorption_bar): _absorption_bar.visible = false
		return
	_setup_absorption_bar()
	if not is_instance_valid(_absorption_bar): return
	# Each absorbed HP is one HP-height within the SAME bar; clip overflow.
	# Top-to-bottom filling means a hit erases gold from the BOTTOM upward.
	_absorption_bar.value = clampf(amount/maxf(float(owner.Max_health),1.0),0.0,1.0)
	_absorption_bar.visible = _absorption_bar.value > 0.0

func clear_absorption_visual(source_id:int) -> void:
	if source_id != _absorption_source_id: return # an old status must not erase a newer one
	_absorption_source_id = 0
	if is_instance_valid(_absorption_bar): _absorption_bar.visible = false


func set_karma_preview(source_key:Variant,amount:float) -> void:
	var key:String = str(source_key)
	var safe_amount:float = maxf(amount,0.0)
	if safe_amount <= 0.0001:
		_karma_sources.erase(key)
	else:
		_karma_sources[key] = safe_amount
	_apply_karma_overlay()


func clear_karma_preview(source_key:Variant) -> void:
	_karma_sources.erase(str(source_key))
	_apply_karma_overlay()


func clear_all_karma_preview() -> void:
	_karma_sources.clear()
	_apply_karma_overlay()


func get_karma_preview_total() -> float:
	var total:float = 0.0
	for raw_value:Variant in _karma_sources.values():
		total += maxf(float(raw_value),0.0)
	return total


func _apply_karma_overlay() -> void:
	# 没有业力来源时无需创建预览节点；如果以前创建过，要把正常生命条恢复到真实血量。
	if _karma_sources.is_empty():
		if _karma_bar != null and is_instance_valid(_karma_bar):
			_karma_bar.visible = false
			if owner != null and is_instance_valid(owner) and not _invincible_display:
				var restore_max_health:float = maxf(float(owner.Max_health),1.0)
				var restore_health:float = clampf(float(owner.health),0.0,restore_max_health)
				var restore_ratio:float = clampf(restore_health / restore_max_health,0.0,1.0)
				health_bar.value = restore_ratio
				health_bar.modulate = Color(1.0,restore_ratio,restore_ratio)
				_set_health_label_color(restore_health,restore_max_health)
		return
	if _karma_bar == null or not is_instance_valid(_karma_bar):
		_setup_karma_preview_bar()
	if _karma_bar == null or not is_instance_valid(_karma_bar):
		return
	if owner == null or not is_instance_valid(owner):
		_karma_bar.visible = false
		return
	if _invincible_display:
		_karma_bar.visible = false
		return

	var max_health_value:float = maxf(float(owner.Max_health),1.0)
	var current_health:float = clampf(float(owner.health),0.0,max_health_value)
	var pending:float = minf(get_karma_preview_total(),maxf(current_health - 1.0,0.0))
	var current_ratio:float = clampf(current_health / max_health_value,0.0,1.0)

	if pending <= 0.0001:
		_karma_bar.visible = false
		health_bar.value = current_ratio
		health_bar.modulate = Color(1.0,current_ratio,current_ratio)
		if not _invincible_display:
			_set_health_label_color(current_health,max_health_value)
		return

	_kill_bar_tween(health_bar)
	_karma_bar.visible = true
	_karma_bar.value = current_ratio
	_karma_bar.modulate = Color.WHITE
	_karma_bar.self_modulate = KARMA_PREVIEW_COLOR

	var safe_health:float = maxf(current_health - pending,0.0)
	var safe_ratio:float = clampf(safe_health / max_health_value,0.0,1.0)
	health_bar.value = safe_ratio
	health_bar.modulate = Color(1.0,safe_ratio,safe_ratio)
	# KARMA 只预览未来掉血；生命数字仍按真实生命百分比切换黑/白。
	_set_health_label_color(current_health,max_health_value)



# 生命数字自适应：无描边，字号按字符串宽度缩小，防止 1000/12345 等长数值溢出。
var _label_base_font_size:int = 0
func _set_health_label_color(value:float,max_health:float) -> void:
	if _invincible_display or not is_instance_valid(label):
		return
	# 严格大于半血为黑；恰好 50% 以及更低均为不透明纯白。
	var color:Color = Color.BLACK if max_health > 0.0 and value > max_health * 0.5 else Color.WHITE
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color",color)

func _set_label_text(value:String,max_health:int = -1) -> void:
	label.text = value
	_fit_label_text()
	if not _invincible_display and value.is_valid_int():
		var maximum:float = float(max_health)
		if max_health < 0 and is_instance_valid(owner):
			maximum = float(owner.Max_health)
		_set_health_label_color(float(value.to_int()),maximum)


func _fit_label_text() -> void:
	if not is_instance_valid(label):
		return
	if _label_base_font_size <= 0:
		_label_base_font_size = label.get_theme_font_size("font_size")
	var font:Font = label.get_theme_font("font")
	if font == null:
		return
	var outline:int = label.get_theme_constant("outline_size")
	# 不能拿 label.size 当参考：Label 会随文字最小宽度自动撑大。以血条本体宽度为准，
	# INF 特殊状态可能有描边；普通数字为 0，再留 8% 余量。
	var bar_width:float = health_bar.size.x * absf(health_bar.scale.x) if is_instance_valid(health_bar) else label.size.x
	var available:float = maxf(bar_width * 0.92 - float(outline) * 2.0,1.0)
	var font_size:int = _label_base_font_size
	var width:float = font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,-1,font_size).x
	# 按比例缩一次后再复测，最多迭代几轮直到放得下（像素字体取整会有少量误差）。
	for _step:int in range(6):
		if width <= available or font_size <= 1:
			break
		var next_size:int = mini(int(floor(float(font_size) * available / width)),font_size - 1)
		font_size = maxi(next_size,1)
		width = font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,-1,font_size).x
	if label.get_theme_font_size("font_size") != font_size:
		label.add_theme_font_size_override("font_size",font_size)


func _stop_health_number_hit_pulse() -> void:
	if _health_number_hit_tween != null and _health_number_hit_tween.is_valid():
		_health_number_hit_tween.kill()
	_health_number_hit_tween = null
	if is_instance_valid(label):
		label.scale = _health_number_base_scale


func _pulse_health_number_on_hit() -> void:
	_stop_health_number_hit_pulse()
	_health_number_hit_tween = create_tween()
	_health_number_hit_tween.tween_property(
		label,"scale",_health_number_base_scale * HEALTH_NUMBER_HIT_SCALE,HEALTH_NUMBER_HIT_GROW_TIME
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_health_number_hit_tween.tween_property(
		label,"scale",_health_number_base_scale,HEALTH_NUMBER_HIT_SETTLE_TIME
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func pulse_health_number_on_silent_damage() -> void:
	# Sans 等逐帧伤害会静默更新血量以免刷屏；由真正结算伤害的调用者显式通知。
	# 一个完整脉冲结束前不再创建 Tween，避免 60Hz 伤害反复重置动画。
	if _invincible_display or not _is_character_health_bar_owner():
		return
	if _health_number_hit_tween != null and _health_number_hit_tween.is_running():
		return
	_pulse_health_number_on_hit()


func Set_Health_Text(health_text:int,max_health:int = -1) -> void:
	_set_label_text("INF" if _invincible_display else str(health_text),max_health)


func set_invincible_display(enabled:bool,animate_glow:bool = true) -> void:
	if _invincible_display == enabled:
		return
	_invincible_display = enabled

	if enabled:
		_stop_health_number_hit_pulse()
		_hide_damage_ghost()
		_kill_bar_tween(health_bar)
		if _karma_bar != null and is_instance_valid(_karma_bar):
			_karma_bar.visible = false
		health_bar.value = 1.0
		health_bar.modulate = Color.WHITE
		_set_label_text("INF")
		label.add_theme_color_override("font_color",INVINCIBLE_GOLD_BRIGHT)
		label.add_theme_color_override("font_outline_color",Color(0.20,0.10,0.0,1.0))
		label.add_theme_color_override("font_shadow_color",Color(1.0,0.64,0.02,0.86))
		label.add_theme_constant_override("outline_size",maxi(_normal_label_outline_size,220))
		if animate_glow:
			_start_invincible_glow()
		else:
			# 不死盔甲架使用静态 INF：保留清晰的无限生命标识，但不做金色明暗脉冲。
			_stop_invincible_glow()
			_set_invincible_glow_phase(1.0)
		return

	_stop_invincible_glow()
	health_bar.self_modulate = _normal_health_self_modulate
	label.add_theme_color_override("font_color",_normal_label_font_color)
	label.add_theme_color_override("font_outline_color",_normal_label_outline_color)
	label.add_theme_color_override("font_shadow_color",_normal_label_shadow_color)
	label.add_theme_constant_override("outline_size",_normal_label_outline_size)
	var max_health_value:int = maxi(int(owner.Max_health),1) if owner != null else 1
	var health_value:int = clampi(int(owner.health),0,max_health_value) if owner != null else 0
	var ratio:float = clampf(float(health_value) / float(max_health_value),0.0,1.0)
	health_bar.value = ratio
	health_bar.modulate = Color(1.0,ratio,ratio)
	_set_label_text(str(health_value),max_health_value)
	_apply_karma_overlay()


func _start_invincible_glow() -> void:
	_stop_invincible_glow()
	_set_invincible_glow_phase(0.0)
	_invincible_glow_tween = create_tween().set_loops()
	_invincible_glow_tween.tween_method(_set_invincible_glow_phase,0.0,1.0,0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_invincible_glow_tween.tween_method(_set_invincible_glow_phase,1.0,0.0,0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_invincible_glow() -> void:
	if _invincible_glow_tween != null and _invincible_glow_tween.is_valid():
		_invincible_glow_tween.kill()
	_invincible_glow_tween = null


func _set_invincible_glow_phase(phase:float) -> void:
	if not _invincible_display:
		return
	var t:float = clampf(phase,0.0,1.0)
	var gold:Color = INVINCIBLE_GOLD_DARK.lerp(INVINCIBLE_GOLD_BRIGHT,t)
	health_bar.self_modulate = gold
	label.add_theme_color_override("font_color",gold)
	label.add_theme_color_override("font_shadow_color",Color(gold.r,gold.g,gold.b,0.58 + t * 0.34))


func when_value_changed(last_value:int,value:int,max_value:int,if_tween:bool,bar:TextureProgressBar) -> void:
	if force_instant_update_once:
		force_instant_update_once = false
		if_tween = false

	if bar == health_bar and get_karma_preview_total() > 0.0001:
		# KARMA 的上下边界都可能每几帧变化一次。这里不用 0.2s Tween，
		# 否则普通生命层会追不上粉紫色层，出现“紫条穿帮”。
		if_tween = false

	if _invincible_display and bar == health_bar:
		_kill_bar_tween(health_bar)
		health_bar.value = 1.0
		health_bar.modulate = Color.WHITE
		_set_label_text("INF")
		return

	var target_value:float = 0.0
	if max_value > 0:
		target_value = clampf(float(value) / float(max_value),0.0,1.0)

	var changed_value:int = last_value - value
	# V64：生命伤害跳字显示“本次准备扣进生命的伤害”，不受目标剩余 HP / 0 下限限制。
	# 真实血条仍使用 value，只有浮字显示值读取 owner 在 health setter 发射期间提供的一次性数值。
	var floating_damage_value:int = changed_value
	if (
		bar == health_bar
		and last_value > value
		and owner != null
		and owner.has_method("pending_health_damage_text_amount")
	):
		floating_damage_value = maxi(
			int(owner.call("pending_health_damage_text_amount")),
			changed_value
		)

	if max_value > 0:
		value = clampi(value,0,max_value)
	else:
		value = 0
	# 只响应角色真实生命下降；护盾/能量变化、回血、静默状态迁移以及 INF
	# 不播放。连续受击会停止前一次 Tween 并从原尺寸重新起跳，不会叠乘。
	if bar == health_bar and last_value > value and not suppress_floating_text and _is_character_health_bar_owner():
		_pulse_health_number_on_hit()
	if bar == health_bar and max_value > 0 and _is_character_health_bar_owner():
		if last_value > value and get_karma_preview_total() <= 0.0001:
			var previous_ratio:float = clampf(float(last_value) / float(max_value),0.0,1.0)
			_show_damage_ghost(previous_ratio,target_value)
			_shake_bar_for_drop(previous_ratio - target_value)
		elif value > last_value:
			_damage_ghost_follow_heal(target_value)

	if if_tween:
		_kill_bar_tween(bar)

		var new_tween:Tween = create_tween()
		_bar_tweens[bar] = new_tween
		new_tween.set_parallel(true)
		new_tween.tween_property(bar,"value",target_value,0.2)

		if bar == health_bar:
			new_tween.tween_property(bar,"modulate",Color(1.0,target_value,target_value),0.2)
			new_tween.set_ease(Tween.EASE_OUT)
			new_tween.set_trans(Tween.TRANS_QUAD)
			new_tween.tween_method(Set_Health_Text.bind(max_value),last_value,value,0.2)

		# 数值下降：伤害/护盾损失跳字
		if last_value > value:
			if (
				not suppress_floating_text
				and is_multiplayer_authority()
				and bar != energy_bar
			):
				_spawn_damage_text(floating_damage_value,bar)

		# 生命上升：绿色回血跳字
		elif value > last_value and bar == health_bar:
			if not suppress_floating_text and is_multiplayer_authority():
				_spawn_heal_text(value - last_value)
	else:
		if bar == health_bar:
			_set_label_text(str(value),max_value)
		bar.value = target_value

	if bar == health_bar and get_karma_preview_total() > 0.0001:
		_apply_karma_overlay()

func _ensure_damage_ghost_bar() -> TextureProgressBar:
	if is_instance_valid(_damage_ghost_bar):
		return _damage_ghost_bar
	if health_bar == null or health_bar.get_parent() == null:
		return null
	_damage_ghost_bar = health_bar.duplicate() as TextureProgressBar
	if _damage_ghost_bar == null:
		return null
	_damage_ghost_bar.name = "HealthDamageGhost"
	_damage_ghost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_ghost_bar.visible = false
	_damage_ghost_bar.z_index = health_bar.z_index
	_damage_ghost_bar.modulate = Color.WHITE
	_damage_ghost_bar.self_modulate = DAMAGE_GHOST_COLOR
	var parent_node:Node = health_bar.get_parent()
	parent_node.add_child(_damage_ghost_bar)
	# 画在正常生命条之下：只露出刚失去的那一段。
	parent_node.move_child(_damage_ghost_bar,health_bar.get_index())
	return _damage_ghost_bar


func get_damage_ghost_value() -> float:
	if not is_instance_valid(_damage_ghost_bar) or not _damage_ghost_bar.visible:
		return -1.0
	return _damage_ghost_bar.value


func _show_damage_ghost(previous_ratio:float,current_ratio:float) -> void:
	if _invincible_display or previous_ratio <= current_ratio:
		return
	var ghost:TextureProgressBar = _ensure_damage_ghost_bar()
	if ghost == null:
		return
	if _damage_ghost_tween != null and _damage_ghost_tween.is_valid():
		_damage_ghost_tween.kill()
	# 连续受击：残影从当前位置接着缩，不重新停顿，避免连击时一直挂着不动。
	var continuing:bool = ghost.visible and ghost.value > previous_ratio
	ghost.value = ghost.value if continuing else previous_ratio
	_damage_ghost_tween = create_tween()
	if not continuing:
		ghost.self_modulate = DAMAGE_GHOST_COLOR
		ghost.visible = true
		_damage_ghost_tween.tween_property(ghost,"self_modulate:a",DAMAGE_GHOST_SETTLED_ALPHA,DAMAGE_GHOST_HOLD).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_damage_ghost_tween.tween_property(ghost,"value",current_ratio,DAMAGE_GHOST_DRAIN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_damage_ghost_tween.tween_callback(_hide_damage_ghost)


func _damage_ghost_follow_heal(current_ratio:float) -> void:
	if not is_instance_valid(_damage_ghost_bar) or not _damage_ghost_bar.visible:
		return
	if current_ratio >= _damage_ghost_bar.value:
		_hide_damage_ghost()


func _hide_damage_ghost() -> void:
	if _damage_ghost_tween != null and _damage_ghost_tween.is_valid():
		_damage_ghost_tween.kill()
	_damage_ghost_tween = null
	if is_instance_valid(_damage_ghost_bar):
		_damage_ghost_bar.visible = false


static func bar_shake_pixels_for_drop(drop_ratio:float) -> float:
	if not is_finite(drop_ratio) or drop_ratio < BAR_SHAKE_MIN_DROP_RATIO:
		return 0.0
	# 约 25% 最大生命的一下达到上限；小伤害只轻轻一动。
	return BAR_SHAKE_MAX_PIXELS * sqrt(clampf(drop_ratio / 0.25,0.0,1.0))


func _shake_bar_for_drop(drop_ratio:float) -> void:
	var pixels:float = bar_shake_pixels_for_drop(drop_ratio)
	if pixels <= 0.0 or not is_instance_valid(texture_rect):
		return
	if not _bar_shake_base_captured:
		_bar_shake_base_position = texture_rect.position
		_bar_shake_base_captured = true
	# 抖动进行中只让更强的一下重新开始。
	if _bar_shake_tween != null and _bar_shake_tween.is_valid() and _bar_shake_tween.is_running() and pixels < _bar_shake_pixels:
		return
	if _bar_shake_tween != null and _bar_shake_tween.is_valid():
		_bar_shake_tween.kill()
	_bar_shake_pixels = pixels
	_bar_shake_tween = create_tween()
	_bar_shake_tween.tween_method(_apply_bar_shake,0.0,1.0,BAR_SHAKE_DURATION)
	_bar_shake_tween.tween_callback(_apply_bar_shake.bind(1.0))


func _apply_bar_shake(progress:float) -> void:
	if not is_instance_valid(texture_rect):
		return
	var t:float = clampf(progress,0.0,1.0)
	if t >= 1.0:
		texture_rect.position = _bar_shake_base_position
		return
	var phase:float = t * BAR_SHAKE_DURATION * TAU * 26.0
	var envelope:float = pow(1.0 - t,1.6)
	texture_rect.position = _bar_shake_base_position + Vector2(sin(phase),sin(phase * 1.37 + 1.1) * 0.45) * _bar_shake_pixels * envelope


func _kill_bar_tween(bar:TextureProgressBar) -> void:
	if not _bar_tweens.has(bar):
		return

	var old_tween = _bar_tweens[bar]
	if old_tween is Tween and old_tween.is_valid():
		old_tween.kill()

	_bar_tweens.erase(bar)

# V430 性能：大规模战斗时按 World 视觉密度收紧同屏伤害飘字上限（人数回落自动恢复）。
func _effective_max_live_damage_texts() -> int:
	var limit:int = max_live_damage_texts
	var o:Node = owner
	if o != null and o.has_method("get_large_battle_visual_density"):
		limit = maxi(int(ceil(float(limit) * clampf(float(o.call("get_large_battle_visual_density")),0.15,1.0))),12)
	return limit

func _floating_text_point() -> Vector2:
	# Sample on the character's visual, respecting its scale/rotation, not the HUD.
	var rng:RandomNumberGenerator = preload("res://scripts/damage_text.gd").visual_random()
	var visual:Node2D = owner.image as Node2D
	if is_instance_valid(visual):
		var rect := Rect2(Vector2(-damage_text_offset_range,-damage_text_offset_range),Vector2.ONE*damage_text_offset_range*2.0)
		if visual is Sprite2D:
			rect = visual.get_rect()
		elif visual is AnimatedSprite2D:
			var animated := visual as AnimatedSprite2D
			if animated.sprite_frames != null and animated.sprite_frames.get_frame_count(animated.animation)>0:
				var texture:Texture2D = animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
				if texture != null:
					var extent:Vector2 = texture.get_size()
					rect = Rect2(animated.offset-extent*0.5 if animated.centered else animated.offset,extent)
		var point:Vector2 = rect.get_center()+Vector2(rng.randf_range(-0.32,0.32)*rect.size.x,rng.randf_range(-0.32,0.32)*rect.size.y)
		return visual.to_global(point)
	return owner.global_position

func _spawn_heal_text(heal_amount:int) -> void:
	if heal_amount <= 0: return
	_spawn_amount_text(float(heal_amount),&"heal")

func _spawn_damage_text(changed_value:Variant,bar:TextureProgressBar) -> void:
	var amount:float = float(changed_value)
	if amount <= 0.0 or is_nan(amount): return
	_spawn_amount_text(amount,&"block" if bar == block_bar else &"damage")

func _spawn_amount_text(amount:float,kind:StringName) -> void:
	var tree:SceneTree = get_tree()
	if max_live_damage_texts > 0 and tree.get_node_count_in_group("__damage_text_runtime") >= _effective_max_live_damage_texts(): return
	var popup:Label = damage_text.instantiate()
	popup.add_to_group("__damage_text_runtime")
	popup.set_meta("combat_visual_owner",weakref(owner))
	popup.configure_amount(amount,kind)
	popup.name = Game.return_random_name(popup)
	# Set the spawn point before entering the tree; defer flight until layout settles.
	popup.position = tree.current_scene.to_local(_floating_text_point()) if tree.current_scene is Node2D else _floating_text_point()
	tree.current_scene.add_child(popup,true)


func _process(_delta:float) -> void:
	if _has_health_threshold_provider:
		_refresh_health_threshold_markers(false)


func _refresh_health_threshold_markers(force:bool = false) -> void:
	if not _has_health_threshold_provider or owner == null or health_bar == null:
		_clear_health_threshold_markers()
		return

	var raw_values:Variant = owner.call("get_health_threshold_values")
	var max_health_value:float = maxf(float(owner.Max_health),1.0)
	var valid_values:Array[float] = []

	if raw_values != null:
		for raw_value in raw_values:
			var threshold:float = float(raw_value)
			# 只标记“仍有剩余生命的阶段阈值”。0HP 的复活/第二阶段不画线。
			# 超出当前生命上限的阈值同样不绘制。
			if threshold <= 0.0 or threshold >= max_health_value:
				continue
			var duplicated:bool = false
			for existing:float in valid_values:
				if is_equal_approx(existing,threshold):
					duplicated = true
					break
			if not duplicated:
				valid_values.append(threshold)

	valid_values.sort()

	var signature:String = "%0.3f|%0.3f|%0.3f|%0.3f|%0.3f|%0.3f|%0.3f" % [
		max_health_value,
		health_bar.position.x,
		health_bar.position.y,
		health_bar.size.x,
		health_bar.size.y,
		health_bar.scale.x,
		health_bar.scale.y,
	]
	for threshold:float in valid_values:
		signature += "|%0.3f" % threshold

	if not force and signature == _health_threshold_signature:
		return
	_health_threshold_signature = signature
	_clear_health_threshold_markers()

	# V137：阈值黑线不能继续作为 Health(TextureProgressBar) 的子节点。
	# Health 的同级 Block 护盾条 z_index=1，会把 Health 内部的 marker 压在下面；
	# 改为挂到二者共同父节点 TextureRect，并给 marker 更高 z_index。
	# 位置仍严格按 Health 自己的 position/size/scale 计算，因此复用的是同一套生命阈值，
	# 只修绘制层级，不新增文字、彩色线或 Boss 专用 UI。
	var marker_parent:Control = health_bar.get_parent() as Control
	if marker_parent == null:
		return
	var scale_x:float = absf(health_bar.scale.x)
	var scale_y:float = absf(health_bar.scale.y)
	var display_width:float = health_bar.size.x * scale_x
	var display_height:float = health_bar.size.y * scale_y
	var display_thickness:float = minf(
		maxf(health_threshold_marker_thickness * scale_y,1.0),
		maxf(display_height,1.0)
	)
	for threshold:float in valid_values:
		var ratio:float = clampf(threshold / max_health_value,0.0,1.0)
		# TextureProgressBar.fill_mode=FILL_BOTTOM_TO_TOP：
		# 满血在顶部，0HP 在底部，所以阈值中心 Y = (1-ratio)。
		var marker_center_y:float = health_bar.position.y + display_height * (1.0 - ratio)
		var marker_top:float = marker_center_y - display_thickness * 0.5
		var marker := ColorRect.new()
		marker.name = "HealthThresholdMarker_%d" % int(round(threshold))
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.color = Color(0.0,0.0,0.0,1.0)
		marker.z_index = 4
		marker.position = Vector2(health_bar.position.x,marker_top)
		marker.size = Vector2(display_width,display_thickness)
		marker_parent.add_child(marker)
		_health_threshold_markers.append(marker)


func _clear_health_threshold_markers() -> void:
	for marker:ColorRect in _health_threshold_markers:
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
	_health_threshold_markers.clear()


func show_energy_bar() -> void:
	energy_outside.show()
