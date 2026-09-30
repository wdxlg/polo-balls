extends Node2D

const ATTACHED_TIMER_AUDIO:AudioStream = preload("res://audio/characters/炸弹客/计时.mp3")
const EXPLOSION_AUDIO:AudioStream = preload("res://audio/characters/炸弹客/爆炸.mp3")

# 炸弹客的逻辑炸弹：
# - is_ground=true：永久留在地面，不自行计时爆炸，只会被其他炸弹的爆炸连锁引爆。
# - is_ground=false：附着目标，倒计时结束后爆炸。
# 场景带 MultiplayerSynchronizer，运行时参数和位置都会同步。

@export_category("炸弹 - 外观（可留空）")
@export var bomb_texture:Texture2D
@export_range(12.0,80.0,1.0) var bomb_visual_size:float = 30.0

@export_category("炸弹 - 逻辑")
@export var Master_name:String = ""
@export var Team:String = ""
@export var attached_target_name:String = ""
@export var is_ground:bool = true
@export_range(0.05,10.0,0.05) var fuse_duration:float = 1.55
@export_range(10.0,600.0,5.0) var explosion_radius:float = 118.0
@export_range(0.0,3000.0,5.0) var damage_amount:float = 90.0
@export_range(10.0,800.0,5.0) var chain_trigger_radius:float = 118.0
@export_range(0.0,300.0,5.0) var explosion_knockback_distance:float = 55.0
@export_range(50.0,1800.0,10.0) var explosion_knockback_speed:float = 620.0

@export_category("炸弹 - 音效")
@export_range(-30.0,6.0,0.5) var attached_timer_volume_db:float = -1.5
@export_range(100.0,2000.0,10.0) var attached_timer_max_distance:float = 720.0
@export_range(-30.0,6.0,0.5) var explosion_volume_db:float = -4.0
@export_range(100.0,3000.0,10.0) var explosion_audio_max_distance:float = 1100.0

var _fuse_left:float = 0.0
var _exploded:bool = false
var _target:ball = null
var _visual_phase:float = 0.0
var _fallback_visual:Node2D = null
var _attached_timer_player:AudioStreamPlayer2D = null
var _attached_timer_started:bool = false
@onready var _sprite:Sprite2D = get_node_or_null("Sprite2D") as Sprite2D


func _ready() -> void:
	add_to_group("BomberBomb")
	add_to_group("BattleTransient")
	_auto_load_texture()
	_setup_visual()
	_fuse_left = maxf(fuse_duration,0.05)
	if not is_ground:
		call_deferred("_resolve_attached_target")
		call_deferred("_start_attached_timer_audio")


func _auto_load_texture() -> void:
	if bomb_texture != null:
		return
	var path:String = "res://Images/shooter/炸弹客/炸弹.png"
	if ResourceLoader.exists(path):
		var resource:Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			bomb_texture = resource as Texture2D


func _setup_visual() -> void:
	if _sprite != null and bomb_texture != null:
		_sprite.texture = bomb_texture
		_sprite.visible = true
		var texture_size:Vector2 = bomb_texture.get_size()
		var max_dimension:float = maxf(texture_size.x,texture_size.y)
		if max_dimension > 0.0:
			_sprite.scale = Vector2.ONE * (bomb_visual_size / max_dimension)
		return

	if _sprite != null:
		_sprite.visible = false
	_create_fallback_bomb()


func _create_fallback_bomb() -> void:
	if _fallback_visual != null and is_instance_valid(_fallback_visual):
		return
	var holder := Node2D.new()
	holder.name = "FallbackBombVisual"
	add_child(holder)
	_fallback_visual = holder

	var body := Polygon2D.new()
	body.polygon = _circle_points(bomb_visual_size * 0.43,24)
	body.color = Color(0.10,0.10,0.10,1.0)
	holder.add_child(body)

	var fuse := Line2D.new()
	fuse.width = 2.0
	fuse.default_color = Color(0.55,0.38,0.20,1.0)
	fuse.points = PackedVector2Array([Vector2(0.0,-bomb_visual_size * 0.42),Vector2(5.0,-bomb_visual_size * 0.63),Vector2(9.0,-bomb_visual_size * 0.50)])
	holder.add_child(fuse)


func _physics_process(delta:float) -> void:
	_visual_phase += delta
	# 附着炸弹的计时声跟着炸弹/目标移动。远端同步到 is_ground=false 后也会自动补播。
	if not is_ground and not _exploded and not _attached_timer_started:
		_start_attached_timer_audio()
	if is_multiplayer_authority():
		if not is_ground:
			if _target == null or not is_instance_valid(_target):
				_resolve_attached_target()
			if _target != null and is_instance_valid(_target):
				global_position = _target.global_position
			_fuse_left -= delta
			if _fuse_left <= 0.0:
				explode()
				return

	# 只做轻微呼吸/倒计时闪烁，不参与游戏逻辑。
	var pulse:float = 1.0 + sin(_visual_phase * (7.5 if is_ground else 11.0)) * 0.06
	scale = Vector2.ONE * pulse


func _resolve_attached_target() -> void:
	if attached_target_name.is_empty():
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var resolved = world.get_node_or_null(NodePath(attached_target_name))
	if resolved is ball:
		_target = resolved as ball


func _resolve_master() -> ball:
	if Master_name.is_empty():
		return null
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var resolved = world.get_node_or_null(NodePath(Master_name))
	return resolved as ball if resolved is ball else null


func explode() -> void:
	if _exploded or not is_multiplayer_authority():
		return
	_exploded = true

	var blast_position:Vector2 = global_position
	# 爆炸发生的一刻，先停止附着炸弹的计时声，再在爆炸点播放用户提供的爆炸音效。
	if multiplayer.has_multiplayer_peer():
		_rpc_explosion_audio.rpc(blast_position)
	else:
		_rpc_explosion_audio(blast_position)
	if multiplayer.has_multiplayer_peer():
		_rpc_show_explosion.rpc(blast_position,explosion_radius)
	else:
		_rpc_show_explosion(blast_position,explosion_radius)

	_apply_explosion_damage(blast_position)
	_trigger_ground_bomb_chain(blast_position)
	Game.free_node(self)


func trigger_chain_explosion() -> void:
	if not is_ground or _exploded:
		return
	explode()


func _apply_explosion_damage(blast_position:Vector2) -> void:
	var master:ball = _resolve_master()
	var damage_enabled:bool = true
	if master != null and master.is_damage_output_disabled():
		damage_enabled = false

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _can_damage_target(target,master):
			continue

		var distance:float = blast_position.distance_to(target.global_position)
		if distance > explosion_radius:
			continue

		var falloff:float = lerpf(1.0,0.62,clampf(distance / maxf(explosion_radius,1.0),0.0,1.0))
		var applied_damage:float = damage_amount * falloff if damage_enabled else 0.0
		if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,blast_position,applied_damage)):
			continue
		if applied_damage > 0.0:
			target.receive_spatial_damage(
				applied_damage,
				{"shape":"circle","center":blast_position,"radius":maxf(explosion_radius,1.0),"source":self},
				false
			)

		if explosion_knockback_distance > 0.0:
			var push_dir:Vector2 = target.global_position - blast_position
			if push_dir.length_squared() <= 0.000001:
				push_dir = Vector2.RIGHT.rotated(randf_range(0.0,TAU))
			target.apply_knockback(
				push_dir.normalized(),
				explosion_knockback_distance,
				explosion_knockback_speed,
				0.45,
				0.0,
				{
					"source": master,
					"max_wall_bounces": 1,
					"stop_on_character": true,
				}
			)


func _can_damage_target(target:ball,master:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_combat_targetable():
		return false
	if master != null and target == master:
		return false
	if (
		Team != ""
		and target.Team != ""
		and Team == target.Team
	):
		return false
	return true


func _trigger_ground_bomb_chain(blast_position:Vector2) -> void:
	# 先收集再触发，避免当前爆炸删除/连锁时修改 group 数组影响遍历。
	var chain_targets:Array[Node] = []
	for node:Node in get_tree().get_nodes_in_group("BomberBomb"):
		if node == self or not is_instance_valid(node):
			continue
		if not bool(node.get("is_ground")):
			continue
		if blast_position.distance_to((node as Node2D).global_position) <= chain_trigger_radius:
			chain_targets.append(node)

	for node:Node in chain_targets:
		if is_instance_valid(node) and node.has_method("trigger_chain_explosion"):
			node.call_deferred("trigger_chain_explosion")


func _start_attached_timer_audio() -> void:
	if is_ground or _exploded or _attached_timer_started or not is_inside_tree():
		return
	_attached_timer_started = true
	var player := AudioStreamPlayer2D.new()
	player.name = "AttachedFuseAudio"
	player.stream = ATTACHED_TIMER_AUDIO
	player.volume_db = attached_timer_volume_db
	player.max_distance = attached_timer_max_distance
	player.attenuation = 1.0
	add_child(player)
	player.position = Vector2.ZERO
	_attached_timer_player = player
	player.play()


func _stop_attached_timer_audio() -> void:
	if _attached_timer_player != null and is_instance_valid(_attached_timer_player):
		_attached_timer_player.stop()
		_attached_timer_player.queue_free()
	_attached_timer_player = null
	_attached_timer_started = false


@rpc("authority","call_local","reliable")
func _rpc_explosion_audio(blast_position:Vector2) -> void:
	# 远端实例也标记为已爆炸，避免停止计时声后在下一物理帧又被自动重新播放。
	_exploded = true
	_stop_attached_timer_audio()
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "BomberExplosionAudio"
	player.stream = EXPLOSION_AUDIO
	player.volume_db = explosion_volume_db
	player.max_distance = explosion_audio_max_distance
	player.attenuation = 1.0
	world.add_child(player)
	player.global_position = blast_position
	player.add_to_group("BattleTransient")
	player.finished.connect(player.queue_free)
	player.play()


func _exit_tree() -> void:
	# Reset、场景清理或其他机制提前删除炸弹时，也不能把计时声留在场景里。
	# 父节点正在退出树时不再 queue_free 子节点，只停止播放即可，子节点会随父节点一起释放。
	if _attached_timer_player != null and is_instance_valid(_attached_timer_player):
		_attached_timer_player.stop()
	_attached_timer_player = null
	_attached_timer_started = false


@rpc("authority","call_local","reliable")
func _rpc_show_explosion(blast_position:Vector2,radius:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var core := Polygon2D.new()
	core.polygon = _circle_points(radius,44)
	core.color = Color(1.0,0.36,0.08,0.70)
	core.global_position = blast_position
	core.scale = Vector2(0.10,0.10)
	core.z_index = 35
	world.add_child(core)
	core.add_to_group("BattleTransient")

	var ring := Line2D.new()
	ring.points = _circle_points(radius,44)
	ring.closed = true
	ring.width = 5.0
	ring.default_color = Color(1.0,0.82,0.28,0.95)
	ring.global_position = blast_position
	ring.scale = Vector2(0.12,0.12)
	ring.z_index = 36
	world.add_child(ring)
	ring.add_to_group("BattleTransient")

	var tween_core:Tween = core.create_tween()
	tween_core.set_parallel(true)
	tween_core.tween_property(core,"scale",Vector2.ONE,0.22)
	tween_core.tween_property(core,"modulate",Color(1.0,1.0,1.0,0.0),0.32)
	tween_core.finished.connect(core.queue_free)

	var tween_ring:Tween = ring.create_tween()
	tween_ring.set_parallel(true)
	tween_ring.tween_property(ring,"scale",Vector2.ONE,0.20)
	tween_ring.tween_property(ring,"modulate",Color(1.0,1.0,1.0,0.0),0.28)
	tween_ring.finished.connect(ring.queue_free)


func _circle_points(radius:float,count:int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments:int = maxi(count,8)
	for i:int in range(segments):
		var angle:float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle),sin(angle)) * radius)
	return points
