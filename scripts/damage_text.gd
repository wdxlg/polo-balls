extends Label

var base_position:Vector2 = position

var if_shake:bool = false
var shake_amount:float = 1
var target_scale:float = 1

# V65：超十位数伤害显示为循环彩色 INF。仅这类跳字开启逐帧色相更新。
var _infinite_damage_visual:bool = false
var _infinite_damage_hue:float = 0.0
const INFINITE_DAMAGE_HUE_SPEED:float = 1.35

func set_infinite_damage_visual() -> void:
	_infinite_damage_visual = true
	_infinite_damage_hue = randf()
	text = "INF"
	add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,1.0))
	add_theme_constant_override("outline_size",maxi(get_theme_constant("outline_size"),4))
	_apply_infinite_damage_color()
	set_process(true)

func _apply_infinite_damage_color() -> void:
	if not _infinite_damage_visual:
		return
	var rainbow:Color = Color.from_hsv(_infinite_damage_hue,0.82,1.0,1.0)
	add_theme_color_override("font_color",rainbow)
	add_theme_color_override("font_shadow_color",Color(rainbow.r,rainbow.g,rainbow.b,0.62))

func _process(delta:float) -> void:
	if not _infinite_damage_visual:
		set_process(false)
		return
	_infinite_damage_hue = fmod(_infinite_damage_hue + maxf(delta,0.0) * INFINITE_DAMAGE_HUE_SPEED,1.0)
	_apply_infinite_damage_color()

func set_properties(hp:float):
	shake_amount = clamp(float(hp) / 10.0,1,5)
	add_theme_font_size_override("font_size", int(clampf(float(hp) / 5.0, 10.0, 25.0)))

func move(poi:Vector2):
	base_position = poi - Vector2(get_theme_font_size("font_size"),get_theme_font_size("font_size"))
	
	var random_angle = randf_range(0,2*PI)
	position = base_position + Vector2(cos(random_angle),sin(random_angle)) * shake_amount / 10.0

@onready var multiplayer_synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
func _ready() -> void:
	set_process(_infinite_damage_visual)
	# V109：地图外视觉遮罩位于 World z=90，地图黑边位于 z=100。
	# 伤害/回血跳字属于战斗反馈，不应因为文字跨出地图矩形而被遮罩擦掉。
	z_as_relative = false
	z_index = 98

	if not is_multiplayer_authority():return
	
	scale = Vector2(0,0)
	var tween = create_tween()
	
	tween.set_parallel(true)
	tween.tween_property(self,"scale",Vector2(1,1),0.1)
	tween.tween_property(self,"modulate",Color(modulate,0),1* target_scale)
	
	tween.tween_method(move,position,position + Vector2(0,-10 * target_scale * randf_range(0.5,2)),1 * target_scale)
	
	tween.finished.connect(Game.free_node.bind(self))

 
