extends ball

const HYDRA_HEAD_SCENE:PackedScene = preload("res://scenes/creatures/九头蛇_头.tscn")
const HYDRA_NECK_TEXTURE_PATH:String = "res://Images/characters/动物/九头蛇/九头蛇_脖子_线条.png"

var _hydra_neck_texture:Texture2D = null

@export_category("九头蛇 - 头部")
@export_range(1,9,1) var initial_head_count:int = 3
@export_range(1,5000,1) var head_max_health:int = 80
@export_range(0.0,10.0,0.05) var head_damage_multiplier:float = 1.0
@export_range(1.0,800.0,1.0) var head_speed:float = 235.0
@export_range(40.0,500.0,1.0) var head_move_radius:float = 145.0
@export_range(40.0,700.0,1.0) var head_attack_search_radius:float = 180.0
@export_range(20.0,300.0,1.0) var head_rest_radius:float = 64.0
@export_range(0.1,30.0,0.1) var head_respawn_delay:float = 2.6
@export_range(0.1,3.0,0.05) var head_regrow_emerge_duration:float = 0.8
@export_range(0.0,1.0,0.02) var head_regrow_stagger:float = 0.12
@export_range(1,6,1) var heads_regrown_per_death:int = 2
# 九头蛇硬上限：任何时候最多 9 个活头。断头依然尝试一变二，但达到 9 个后停止生成。
const HARD_MAX_HEAD_COUNT:int = 9
@export_range(1,9,1) var max_head_count:int = 9

@export_category("九头蛇 - 脖子")
@export_range(2.0,80.0,1.0) var neck_width:float = 30.0
@export var neck_color:Color = Color(0.18,0.48,0.24,1.0)
@export_range(0.0,60.0,1.0) var neck_curve_amount:float = 18.0
@export_range(0.0,30.0,1.0) var neck_wiggle_amount:float = 7.0
@export_range(0.1,8.0,0.1) var neck_wiggle_speed:float = 2.2
@export_range(0.0,60.0,1.0) var neck_root_inset:float = 14.0
@export_range(0.0,60.0,1.0) var neck_head_inset:float = 11.0

var _hydra_heads:Array[ball] = []
var _neck_lines:Dictionary = {}
var _dying:bool = false
var _next_head_serial:int = 0
var _neck_time:float = 0.0


func _ready() -> void:
	# 身体本身只负责正常移动、碰撞/反弹和承受伤害；所有伤害只来自头。
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	super._ready()

	# 双保险：即使别的系统之后误改了本体碰撞伤害配置，身体 Hitbox 也不监听。
	Has_Collision_Damage = false
	if self_hitbox != null:
		self_hitbox.monitoring = false

	if is_multiplayer_authority():
		call_deferred("_spawn_initial_heads")


func _process(delta:float) -> void:
	_neck_time += delta
	_prune_invalid_heads()
	_update_necks()


# 身体永远不产生碰撞伤害。父类的物理接触兜底会动态调用这个方法。
func has_collision_damage() -> bool:
	return false


# 即使某个外部系统意外手动触发身体 Hitbox，也不进行任何伤害结算。
func _on_hitbox_on_hit(_hurt:hurtbox) -> void:
	return


func _spawn_initial_heads() -> void:
	if _dying or health <= 0 or not is_multiplayer_authority():
		return
	if not _hydra_heads.is_empty():
		return

	var count:int = mini(maxi(initial_head_count,1),HARD_MAX_HEAD_COUNT)
	for index in range(count):
		_spawn_head_at_angle(_initial_head_angle(index,count))


func _initial_head_angle(index:int,count:int) -> float:
	if count <= 1:
		return -PI * 0.5
	# 头主要分布在身体上半圈，初始三个就是左上 / 正上 / 右上。
	return lerpf(deg_to_rad(-140.0),deg_to_rad(-40.0),float(index) / float(count - 1))


func _effective_head_cap() -> int:
	# Inspector 只能调低上限，不能突破角色设计的 9 头硬上限。
	return clampi(max_head_count,1,HARD_MAX_HEAD_COUNT)


func _can_spawn_more_heads() -> bool:
	return _valid_head_count() < _effective_head_cap()


func _valid_head_count() -> int:
	var count:int = 0
	for head in _hydra_heads:
		if head != null and is_instance_valid(head) and head.health > 0:
			count += 1
	return count


func _spawn_head_at_angle(rest_angle:float,emerge_from_body:bool = false) -> ball:
	if (
		_dying
		or health <= 0
		or not is_multiplayer_authority()
		or not _can_spawn_more_heads()
	):
		return null

	var world := get_tree().current_scene
	if world == null:
		return null

	var head := HYDRA_HEAD_SCENE.instantiate() as ball
	if head == null:
		return null

	_next_head_serial += 1
	head.Master = self
	head.Master_name = name
	head.Team = Team
	head.Target_Enemy = Target_Enemy
	head.Max_health = maxi(head_max_health,1)
	head.Damage = maxi(Damage,0)
	head.Speed = maxf(head_speed,1.0)
	head.direction = Vector2.from_angle(rest_angle)
	head.set("tether_radius",maxf(head_move_radius,40.0))
	head.set("attack_search_radius",maxf(head_attack_search_radius,40.0))
	head.set("rest_radius",minf(maxf(head_rest_radius,20.0),maxf(head_move_radius - 10.0,20.0)))
	head.set("rest_angle",rest_angle)
	head.set("head_serial",_next_head_serial)
	head.name = Game.return_random_name(head)

	world.add_child(head,true)
	if emerge_from_body:
		head.global_position = global_position
	else:
		head.global_position = global_position + Vector2.from_angle(rest_angle) * minf(head_rest_radius,head_move_radius * 0.72)
		# 角落出生时头不能放到墙里/墙外。
		if world.has_method("map_free_spawn_position"):
			head.global_position = world.call("map_free_spawn_position",head,head.global_position)
	_register_hydra_head(head)
	if emerge_from_body and head.has_method("begin_regrow_emergence"):
		head.call("begin_regrow_emergence",rest_angle,maxf(head_regrow_emerge_duration,0.08))
	return head


# 头会在本机/远端解析 Master 后主动调用这里，因此脖子在所有客户端都会显示。
func _register_hydra_head(head:ball) -> void:
	if head == null or not is_instance_valid(head):
		return
	if not _hydra_heads.has(head):
		_hydra_heads.append(head)
	if not Creatures.has(head):
		Creatures.append(head)
	_ensure_neck_for(head)


func _unregister_hydra_head(head:ball) -> void:
	if head == null:
		return
	_hydra_heads.erase(head)
	Creatures.erase(head)
	_remove_neck_for_instance_id(head.get_instance_id())


func _get_hydra_neck_texture() -> Texture2D:
	if _hydra_neck_texture != null:
		return _hydra_neck_texture

	# 不在脚本解析阶段 preload 新加入的 PNG。Godot 首次扫描/导入新图片时，
	# GDScript 可能比纹理导入更早解析，从而把正常 PNG 误报为
	# “no resource loaders (unrecognized file extension)”。
	if ResourceLoader.exists(HYDRA_NECK_TEXTURE_PATH, "Texture2D"):
		var imported:Resource = ResourceLoader.load(HYDRA_NECK_TEXTURE_PATH, "Texture2D")
		if imported is Texture2D:
			_hydra_neck_texture = imported as Texture2D
			return _hydra_neck_texture

	# 编辑器刚解压补丁、PNG 尚未来得及生成 .import 时的兜底。
	# 这里只读取原始 PNG，避免整个九头蛇脚本因为导入竞态而无法解析。
	if FileAccess.file_exists(HYDRA_NECK_TEXTURE_PATH):
		var image:Image = Image.load_from_file(HYDRA_NECK_TEXTURE_PATH)
		if image != null and not image.is_empty():
			_hydra_neck_texture = ImageTexture.create_from_image(image)

	return _hydra_neck_texture


func _ensure_neck_for(head:ball) -> void:
	if head == null or not is_instance_valid(head):
		return
	var instance_id:int = head.get_instance_id()
	if _neck_lines.has(instance_id):
		var existing = _neck_lines[instance_id]
		if existing is Line2D and is_instance_valid(existing):
			return
		_neck_lines.erase(instance_id)

	var world := get_tree().current_scene
	if world == null:
		return

	var line := Line2D.new()
	line.name = "HydraNeck_%s" % str(instance_id)
	line.width = neck_width
	# 使用拆分素材里的脖子纹理，同时继续复用原来的贝塞尔曲线点，
	# 因此九头蛇头移动/新生时脖子仍会跟随，而不是变成一张静止贴图。
	var neck_texture:Texture2D = _get_hydra_neck_texture()
	if neck_texture != null:
		line.texture = neck_texture
		line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	line.default_color = Color.WHITE
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_index = -2
	world.add_child(line)
	_neck_lines[instance_id] = line


func _remove_neck_for_instance_id(instance_id:int) -> void:
	if not _neck_lines.has(instance_id):
		return
	var line = _neck_lines[instance_id]
	_neck_lines.erase(instance_id)
	if line is Line2D and is_instance_valid(line):
		(line as Line2D).queue_free()


func _prune_invalid_heads() -> void:
	for head in _hydra_heads.duplicate():
		if head == null or not is_instance_valid(head):
			_hydra_heads.erase(head)

	var live_ids:Dictionary = {}
	for head in _hydra_heads:
		if head != null and is_instance_valid(head):
			live_ids[head.get_instance_id()] = true

	for raw_id in _neck_lines.keys():
		var instance_id:int = int(raw_id)
		if not live_ids.has(instance_id):
			_remove_neck_for_instance_id(instance_id)


func _update_necks() -> void:
	for head in _hydra_heads:
		if head == null or not is_instance_valid(head):
			continue
		_ensure_neck_for(head)
		var line = _neck_lines.get(head.get_instance_id())
		if not (line is Line2D) or not is_instance_valid(line):
			continue
		_update_one_neck(line as Line2D,head)


func _update_one_neck(line:Line2D,head:ball) -> void:
	var body_position:Vector2 = global_position
	var head_position:Vector2 = head.global_position
	var body_to_head:Vector2 = head_position - body_position
	var body_distance:float = body_to_head.length()
	if body_distance <= 0.01:
		line.points = PackedVector2Array([line.to_local(body_position),line.to_local(body_position)])
		return

	var dir:Vector2 = body_to_head / body_distance
	# 新生头还在身体里面时按当前长度压缩两端 inset，脖子会从身体中心逐渐长长，不会反折。
	var root_inset:float = minf(neck_root_inset,body_distance * 0.28)
	var head_inset:float = minf(neck_head_inset,body_distance * 0.28)
	var start:Vector2 = body_position + dir * root_inset
	var finish:Vector2 = head_position - dir * head_inset
	var _chord:Vector2 = finish - start
	var perpendicular:Vector2 = Vector2(-dir.y,dir.x)
	var phase:float = float(head.get_instance_id() % 997) * 0.017
	var wiggle:float = sin(_neck_time * neck_wiggle_speed + phase) * neck_wiggle_amount
	var bend_sign:float = -1.0 if (head.get_instance_id() & 1) == 0 else 1.0
	var control:Vector2 = (start + finish) * 0.5 + perpendicular * (neck_curve_amount * bend_sign + wiggle)

	var points := PackedVector2Array()
	const SEGMENTS:int = 8
	for index in range(SEGMENTS + 1):
		var t:float = float(index) / float(SEGMENTS)
		var inv:float = 1.0 - t
		var world_point:Vector2 = inv * inv * start + 2.0 * inv * t * control + t * t * finish
		points.append(line.to_local(world_point))
	line.points = points


func _on_hydra_head_died(head:ball,death_position:Vector2) -> void:
	_unregister_hydra_head(head)
	if _dying or health <= 0 or not is_multiplayer_authority():
		return
	call_deferred("_regrow_heads_after_delay",death_position)


func _regrow_heads_after_delay(death_position:Vector2) -> void:
	await get_tree().create_timer(maxf(head_respawn_delay,0.05)).timeout
	if _dying or health <= 0 or not is_instance_valid(self) or not is_multiplayer_authority():
		return

	var death_offset:Vector2 = death_position - global_position
	var base_angle:float = death_offset.angle() if death_offset.length_squared() > 0.001 else -PI * 0.5
	var count:int = maxi(heads_regrown_per_death,1)
	for index in range(count):
		if _dying or health <= 0 or not is_instance_valid(self) or not is_multiplayer_authority():
			break
		if not _can_spawn_more_heads():
			break
		var centered:float = float(index) - float(count - 1) * 0.5
		var spread:float = centered * deg_to_rad(22.0)
		# 断头重生：新头先在身体中心生成，再沿新脖子方向伸出去。
		_spawn_head_at_angle(base_angle + spread,true)
		if index < count - 1 and head_regrow_stagger > 0.0:
			await get_tree().create_timer(head_regrow_stagger).timeout


func Die() -> void:
	if _dying:
		return
	_dying = true
	super()

	# 身体死亡时，所有头立即一起死亡，而且这些死亡不会触发“一变二”。
	if is_multiplayer_authority():
		for head in _hydra_heads.duplicate():
			if head == null or not is_instance_valid(head):
				continue
			if head.has_method("die_with_body"):
				head.call("die_with_body")
			else:
				Game.free_node(head)

	_clear_all_necks()
	await get_tree().create_timer(1.4).timeout
	if is_instance_valid(self):
		Game.free_node(self)


func _clear_all_necks() -> void:
	for line in _neck_lines.values():
		if line is Line2D and is_instance_valid(line):
			(line as Line2D).queue_free()
	_neck_lines.clear()
	_hydra_heads.clear()
	Creatures.clear()


func _exit_tree() -> void:
	_clear_all_necks()
