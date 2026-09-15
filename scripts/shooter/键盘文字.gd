extends ball

@export var word_text:String = "菜"
@export_range(0,100,1) var rage_damage_gain:int = 3
@export_range(0,10000,1) var base_word_damage:int = 0
@export_range(1.0,10.0,0.25) var negative_tag_damage_multiplier:float = 4.0
@export_range(1.0,20000.0,1.0) var rage_duration:float = 9999.0
@export_range(0.1,5.0,0.1) var wall_death_delay:float = 0.08

var _spent:bool = false
# 薇欧拉录音召唤版可把自己注册为命中观察者，用于继续累计原有火焰终结的“文字命中次数”。
var hit_observer:Node = null
var locked_target_ref:WeakRef = null

# V412：薇欧拉地图外支援文字从真实键盘侠本体生成。
# 文字在地图外到穿过边界墙这一小段暂时不与墙体碰撞；进入地图且离开边界实体后恢复原 collision_mask。
var _outside_launch_active:bool = false
var _outside_launch_map_rect:Rect2 = Rect2()
var _outside_launch_restore_collision_mask:int = 1
var _outside_launch_restore_z_as_relative:bool = true
var _outside_launch_restore_z_index:int = 0
@onready var word_label:Label = $Graphics/文字


func set_locked_target(target:Node) -> void:
	locked_target_ref = weakref(target) if target != null and is_instance_valid(target) else null


func _locked_target() -> ball:
	if locked_target_ref == null:
		return null
	var raw:Variant = locked_target_ref.get_ref()
	if is_instance_valid(raw) and raw is ball and int((raw as ball).health) > 0:
		return raw as ball
	return null


func enable_outside_map_launch(map_rect:Rect2) -> void:
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return
	_outside_launch_active = true
	_outside_launch_map_rect = map_rect
	_outside_launch_restore_collision_mask = collision_mask
	_outside_launch_restore_z_as_relative = z_as_relative
	_outside_launch_restore_z_index = z_index
	collision_mask = 0
	# 地图外这几帧也必须能看见文字，避免视觉上又像从墙边突然生成。
	z_as_relative = false
	z_index = 92
	set_meta(&"viola_keyboard_outside_launch",true)
	set_meta(&"submission_allow_map_escape",true)


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not _outside_launch_active or not is_multiplayer_authority():
		return
	# 必须先真正进入地图，并且当前文字碰撞半径已经离开边界墙实体，才恢复正常墙碰撞。
	if _outside_launch_map_rect.has_point(global_position) and _outside_launch_position_clear():
		collision_mask = _outside_launch_restore_collision_mask
		z_as_relative = _outside_launch_restore_z_as_relative
		z_index = _outside_launch_restore_z_index
		_outside_launch_active = false
		remove_meta(&"viola_keyboard_outside_launch")


func _outside_launch_position_clear() -> bool:
	if not is_inside_tree():
		return false
	var shape:=CircleShape2D.new()
	shape.radius = 9.0
	var params:=PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0,global_position)
	params.collision_mask = maxi(_outside_launch_restore_collision_mask,1)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if self is CollisionObject2D:
		params.exclude = [(self as CollisionObject2D).get_rid()]
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(params,16):
		var collider:Variant = hit.get("collider",null)
		if collider == null or collider is ball:
			continue
		return false
	return true


func _ready() -> void:
	super._ready()

	# 文字弹丸自身只有 1 点生命。以前它被敌方 Hitbox 碰掉时，
	# 即使没有真正伤到敌人，也会从隐藏血条位置冒出固定“-1”。
	# 文字弹丸不是可被攻击的单位，因此关闭自身 Hurtbox，并永久屏蔽自身浮动血量文字。
	if health_bar != null:
		health_bar.suppress_floating_text = true
	if self_hurtbox != null:
		self_hurtbox.collision_layer = 0
		self_hurtbox.collision_mask = 0
		self_hurtbox.monitorable = false

	if base_word_damage <= 0:
		base_word_damage = maxi(Damage,0)
	Damage = base_word_damage

	word_label.text = Game.t(word_text)
	_resize_collision_to_text()


func _resize_collision_to_text() -> void:
	var char_count:int = maxi(word_text.length(),1)
	var local_width:float = maxf(80.0,float(char_count) * 30.0)
	for shape_node in [
		collision_shape_2d,
		self_hitbox.get_node_or_null("CollisionShape2D"),
		self_hurtbox.get_node_or_null("CollisionShape2D")
	]:
		if shape_node == null or not (shape_node is CollisionShape2D):
			continue
		if shape_node.shape is RectangleShape2D:
			shape_node.shape = shape_node.shape.duplicate()
			(shape_node.shape as RectangleShape2D).size.x = local_width


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if _spent:
		return
	if state_machine.current_state == State.Die:
		return

	var hit_target:ball = _hurtbox_target_ball(hurt)
	# 薇欧拉的“录音键盘侠支援”可以把文字弹锁定到唯一目标。
	# 其它敌人即使碰到文字也不会受到伤害，普通键盘侠 locked_target_ref=null，行为完全不变。
	if locked_target_ref != null:
		var locked:ball = _locked_target()
		if locked == null:
			_spent = true
			state_machine.current_state = State.Die
			return
		if hit_target != locked:
			return

	# 伤害按“实际命中的角色”实时结算。文字与目标 Negative_Tags 完全匹配时，整次文字伤害乘 4。
	Damage = maxi(base_word_damage,0)
	if hit_target != null:
		if hit_target.has_negative_tag(word_text):
			Damage = maxi(
				int(round(float(base_word_damage) * maxf(negative_tag_damage_multiplier,1.0))),
				0
			)

	# 只有真正通过 hitbox 规则的命中才会进入这里；决斗者正面免疫时不会激怒。
	super(hurt)
	_spent = true

	if is_multiplayer_authority() and hit_target != null:
		var target:ball = hit_target
		# rage_damage_gain=0 时完全跳过 Buff 创建，确保薇欧拉召唤的键盘侠不会给敌人任何增伤效果。
		if rage_damage_gain > 0:
			var source = Master if Master != null and is_instance_valid(Master) else self
			get_tree().current_scene.new_buff(
				target,
				source,
				"键盘侠激怒",
				Buff.new(1,rage_duration,Buff.Buff_types.Damage,rage_damage_gain,Buff.Algorithms.add),
				"add"
			)
		if hit_observer != null and is_instance_valid(hit_observer) and hit_observer.has_method("notify_viola_text_hit"):
			hit_observer.call("notify_viola_text_hit",target)

	state_machine.current_state = State.Die


func when_collide(_speed:float,_collision:KinematicCollision2D) -> void:
	if not is_multiplayer_authority() or _spent:
		return
	_spent = true
	state_machine.current_state = State.Die


func Die() -> void:
	graphics.visible = false
	await get_tree().create_timer(maxf(wall_death_delay,0.01)).timeout
	if is_instance_valid(self):
		Game.free_node(self)
