extends Node2D

var owner_ref:WeakRef = null
var target_ref:WeakRef = null
var damage_amount:float = 10.0
var speed:float = 420.0
var lifetime:float = 5.0
var word:String = "质疑"
var elapsed:float = 0.0
var hit_radius:float = 14.0
var travel_direction:Vector2 = Vector2.RIGHT
var aimed_position:Vector2 = Vector2.ZERO
var _label:Label = null
var _visual_root:Node2D = null

# V158：严格参考键盘侠文字的实际战场视觉尺寸。
# 键盘文字.tscn 使用 font_size=34 / outline_size=3，但继承的 ball 根节点 scale=0.2，
# 因此这里使用同样的 34/3，再把文字视觉容器缩放到 0.2。
const KEYBOARD_TEXT_VISUAL_SCALE:float = 0.2
const KEYBOARD_TEXT_FONT_SIZE:int = 34
const KEYBOARD_TEXT_OUTLINE_SIZE:int = 3

func setup(owner_node:Node,target_node:Node2D,start_position:Vector2,config:Dictionary = {}) -> void:
	owner_ref = weakref(owner_node)
	target_ref = weakref(target_node)
	global_position = start_position
	damage_amount = maxf(float(config.get("damage",damage_amount)),0.0)
	speed = maxf(float(config.get("speed",speed)),20.0)
	lifetime = maxf(float(config.get("lifetime",lifetime)),0.2)
	hit_radius = maxf(float(config.get("hit_radius",hit_radius)),2.0)
	word = str(config.get("word",word))
	if _label != null:
		_label.text = word
	# 每一发真正生成时只读取一次目标“当前”位置；之后沿这条直线飞行，不追踪转向。
	aimed_position = target_node.global_position if target_node != null and is_instance_valid(target_node) else start_position + Vector2.RIGHT
	var aim:Vector2 = aimed_position - start_position
	travel_direction = aim.normalized() if aim.length_squared() > 0.000001 else Vector2.RIGHT
	# V160：弹道继续锁定生成瞬间的目标位置；文字视觉单独计算“可读朝向”。
	# 文字不会镜像，也不会旋转到上下颠倒；始终保持从左到右的正常阅读顺序。
	rotation = 0.0
	_apply_readable_text_rotation()

func _ready() -> void:
	z_as_relative = false
	z_index = 70

	_visual_root = Node2D.new()
	_visual_root.name = "文字视觉"
	_visual_root.scale = Vector2.ONE * KEYBOARD_TEXT_VISUAL_SCALE
	add_child(_visual_root)

	_label = Label.new()
	_label.name = "文字"
	_label.text = word
	# 与键盘文字.tscn 的 Label 矩形一致；0.2 视觉根缩放后战场尺寸也一致。
	_label.position = Vector2(-120.0,-36.0)
	_label.size = Vector2(240.0,72.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_size_override("font_size",KEYBOARD_TEXT_FONT_SIZE)
	_label.add_theme_color_override("font_color",Color(1.0,1.0,1.0,1.0))
	_label.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,1.0))
	_label.add_theme_constant_override("outline_size",KEYBOARD_TEXT_OUTLINE_SIZE)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_root.add_child(_label)

	# setup() 通常在 add_child() 后调用；无论调用顺序如何都刷新可读朝向。
	rotation = 0.0
	_apply_readable_text_rotation()


func _apply_readable_text_rotation() -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	var angle:float = travel_direction.angle()
	# 将朝向折叠到 [-90°, 90°]。这样文字仍跟随弹道的斜率，
	# 但当弹道朝左时不会把整行文字倒转 180°，也不需要 flip_h。
	if angle > PI * 0.5:
		angle -= PI
	elif angle < -PI * 0.5:
		angle += PI
	_visual_root.rotation = angle
	_visual_root.scale = Vector2.ONE * KEYBOARD_TEXT_VISUAL_SCALE

func _physics_process(delta:float) -> void:
	elapsed += delta
	if elapsed >= lifetime:
		queue_free()
		return
	var target:Node2D = _target()
	if target == null:
		queue_free()
		return
	var previous_position:Vector2 = global_position
	var travel_distance:float = maxf(speed,20.0) * delta
	global_position += travel_direction * travel_distance
	# V160：飞行方向不变；只刷新不会倒置/镜像的文字视觉角度。
	rotation = 0.0
	_apply_readable_text_rotation()
	if _distance_point_to_segment(target.global_position,previous_position,global_position) <= hit_radius:
		_hit_target(target)

func _distance_point_to_segment(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var length_sq:float = ab.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(a)
	var t:float = clampf((point - a).dot(ab) / length_sq,0.0,1.0)
	return point.distance_to(a + ab * t)

func _target() -> Node2D:
	if target_ref == null:
		return null
	var raw:Variant = target_ref.get_ref()
	if raw is Node2D and is_instance_valid(raw):
		var node:Node2D = raw as Node2D
		if node.get("health") != null and int(node.get("health")) <= 0:
			return null
		return node
	return null

func _owner() -> Node:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is Node and is_instance_valid(raw):
		return raw as Node
	return null

func _hit_target(target:Node2D) -> void:
	var owner_node:Node = _owner()
	var did_hit:bool = false
	# V276：文字弹会在所有 peer 生成视觉镜像；只有薇欧拉 authority 结算伤害/计数。
	if owner_node != null and owner_node.is_multiplayer_authority() and target.has_method("receive_spatial_damage"):
		did_hit = bool(target.call("receive_spatial_damage",damage_amount,{"point":target.global_position,"source":owner_node},false,false))
	if did_hit and owner_node != null and owner_node.has_method("notify_viola_text_hit"):
		owner_node.call("notify_viola_text_hit",target)
	queue_free()
