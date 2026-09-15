extends ball

enum CardType {
	YELLOW,
	BLUE,
	RED,
}

@export_category("裁判牌 - 外观（可留空）")
@export var card_texture:Texture2D
@export_range(8.0,80.0,1.0) var card_visual_width:float = 24.0

@export_category("裁判牌 - 效果")
@export var card_type:CardType = CardType.YELLOW
@export_range(0.0,8.0,0.05) var yellow_stun_duration:float = 1.15
@export_range(0.0,12.0,0.05) var red_damage_disable_duration:float = 3.6

var _visual_root:Node2D = null


func _ready() -> void:
	super._ready()
	_auto_load_card_texture()
	_setup_card_visual()


func _auto_load_card_texture() -> void:
	if card_texture != null:
		return
	var path:String = ""
	match card_type:
		CardType.BLUE:
			path = "res://Images/shooter/裁判牌/蓝牌.png"
		CardType.RED:
			path = "res://Images/shooter/裁判牌/红牌.png"
		_:
			path = "res://Images/shooter/裁判牌/黄牌.png"
	if ResourceLoader.exists(path):
		var resource:Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			card_texture = resource as Texture2D


func _setup_card_visual() -> void:
	if image is Sprite2D and card_texture != null:
		var sprite:Sprite2D = image as Sprite2D
		sprite.texture = card_texture
		sprite.visible = true
		sprite.z_index = 24
		# 用户不需要自己计算原图尺寸：按宽度自动缩放。
		var texture_size:Vector2 = card_texture.get_size()
		if texture_size.x > 0.0:
			var s:float = card_visual_width / texture_size.x
			sprite.scale = Vector2.ONE * s
		sprite.rotation = PI * 0.5
		return

	# 不填图片时隐藏 ball.tscn 继承来的默认人物图，改画简易牌面。
	if image != null:
		image.visible = false
	_create_card_visual()


func _create_card_visual() -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		return

	var holder := Node2D.new()
	holder.name = "CardVisual"
	holder.z_index = 24
	add_child(holder)
	_visual_root = holder

	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-12.0,-8.0),
		Vector2(12.0,-8.0),
		Vector2(12.0,8.0),
		Vector2(-12.0,8.0),
	])
	body.color = _card_color()
	holder.add_child(body)

	var label := Label.new()
	label.position = Vector2(-12.0,-10.0)
	label.size = Vector2(24.0,20.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = _card_letter()
	label.add_theme_font_size_override("font_size",13)
	label.add_theme_color_override("font_color",Color.BLACK if card_type != CardType.RED else Color.WHITE)
	label.add_theme_color_override("font_outline_color",Color(1.0,1.0,1.0,0.25))
	label.add_theme_constant_override("outline_size",1)
	holder.add_child(label)


func _card_color() -> Color:
	match card_type:
		CardType.BLUE:
			return Color(0.18,0.55,1.0,1.0)
		CardType.RED:
			return Color(0.92,0.08,0.08,1.0)
	return Color(1.0,0.88,0.08,1.0)


func _card_letter() -> String:
	match card_type:
		CardType.BLUE:
			return "B"
		CardType.RED:
			return "R"
	return "Y"


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	var target:ball = _hurtbox_target_ball(hurt)
	super(hurt)

	if not is_multiplayer_authority():
		return
	if target == null or not is_instance_valid(target):
		_finish_card()
		return

	match card_type:
		CardType.YELLOW:
			target.apply_stun(yellow_stun_duration)
		CardType.RED:
			# 只使用 ball.gd 的统一禁伤状态，避免再写一层 Buff 导致属性系统互相覆盖。
			target.apply_damage_disable(red_damage_disable_duration)
		CardType.BLUE:
			pass

	_finish_card()


func _hurtbox_target_ball(hurt:hurtbox) -> ball:
	if hurt == null or not is_instance_valid(hurt):
		return null
	var parent_node:Node = hurt.get_parent()
	if parent_node is ball:
		return parent_node as ball
	if hurt.owner is ball:
		return hurt.owner as ball
	return null


func when_collide(_speed:float,_collision:KinematicCollision2D) -> void:
	if not is_multiplayer_authority():
		return
	_finish_card()


func _finish_card() -> void:
	if state_machine == null or state_machine.current_state == State.Die:
		return
	Speed = 0.0
	direction = Vector2.ZERO
	state_machine.current_state = State.Die


func Die() -> void:
	if not is_multiplayer_authority():
		return
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.visible = false
	if image != null:
		image.visible = false
	await get_tree().create_timer(0.06).timeout
	if is_instance_valid(self):
		Game.free_node(self)
