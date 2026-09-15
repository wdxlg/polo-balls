extends ball

const TEXT_SCRIPT = preload("res://scripts/effects/重女文字.gd")
const BLACK_HOLE_VISUAL_SCRIPT = preload("res://scripts/effects/重女黑洞视觉.gd")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

const VISUAL_NORMAL:int = 0
const VISUAL_BLACK_HOLE:int = 1

@export_category("重女 - 外观")
@export var normal_texture:Texture2D
@export var black_hole_texture:Texture2D

@export_category("重女 - 文字")
@export_range(0.2,10.0,0.1) var text_spawn_interval:float = 1.4
@export_range(0.5,8.0,0.1) var text_reveal_duration:float = 3.6
@export_range(0.0,20.0,0.05) var text_min_damage_multiplier:float = 1.0
@export_range(0.0,20.0,0.05) var text_max_damage_multiplier:float = 11.0
@export_range(0.0,1.0,0.01) var red_text_chance:float = 0.24
@export var text_pool:PackedStringArray = PackedStringArray(["别走", "看着我", "为什么", "回来", "你在哪", "不要丢下我", "一直在一起", "听我说"])

@export_category("重女 - 第二形态")
@export_range(0.0,200.0,1.0) var phase2_self_drain_per_second:float = 26.0
# 吸力是局部效果：边缘处几乎没有拉力，只有进入这个半径后才开始明显被吸。
@export_range(60.0,500.0,5.0) var phase2_pull_radius:float = 230.0
@export_range(10.0,600.0,5.0) var phase2_pull_speed:float = 165.0
# 普通角色不会被硬拖到重女身体中心，避免持续实体碰撞；进入此半径后只承受范围伤害。
@export_range(20.0,160.0,2.0) var phase2_pull_stop_radius:float = 82.0
@export_range(20.0,300.0,2.0) var phase2_damage_radius:float = 105.0
@export_range(0.05,2.0,0.05) var phase2_damage_interval:float = 0.5
@export_range(0.0,20.0,0.05) var phase2_tick_damage_multiplier:float = 6.0
@export_range(0.0,2.0,0.05) var phase2_revive_health_ratio:float = 1.0

var _phase2:bool = false
var _text_elapsed:float = 0.0
var _damage_elapsed:float = 0.0
var _self_drain_accumulator:float = 0.0
var _black_hole_visual:Node2D

func get_health_threshold_values() -> PackedFloat32Array:
	# 0 血复活不在血条上做阈值标记。
	return PackedFloat32Array()

func _ready() -> void:
	# 重女本体没有接触/碰撞伤害；输出只来自文字与二阶段范围持续伤害。
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	_set_visual_state_local(VISUAL_NORMAL)
	_build_phase2_visual()

func _process(delta:float) -> void:
	_text_elapsed += delta
	# 第二形态文字生成频率翻倍。
	var current_spawn_interval:float = text_spawn_interval * (0.5 if _phase2 else 1.0)
	if is_multiplayer_authority() and health > 0 and _text_elapsed >= current_spawn_interval:
		_text_elapsed = 0.0
		_spawn_text()
	if _phase2 and health > 0:
		_update_phase2(delta)
	_update_phase2_visual()

func get_next_state(state:State) -> int:
	if health <= 0 and not _phase2 and is_multiplayer_authority():
		_activate_phase2()
		return State.Stand
	return super(state)

func _activate_phase2() -> void:
	if _phase2:
		return
	_phase2 = true
	_broadcast_visual_state(VISUAL_BLACK_HOLE)
	health = clampi(int(round(float(Max_health) * phase2_revive_health_ratio)),1,Max_health)
	Speed *= 0.42
	Has_Collision_Damage = false
	if self_hitbox != null:
		self_hitbox.monitoring = false

	# 二阶段本体仍可被 hurtbox 攻击，但 CharacterBody2D 不再与其他角色实体互撞。
	# 保留 collision mask 的地图层，避免她自己穿出地图；只移除角色层(第 2 层)。
	set_collision_layer_value(2,false)
	set_collision_mask_value(2,false)

	for raw:Node in get_tree().get_nodes_in_group("HeavyGirlText"):
		if raw != null and is_instance_valid(raw) and raw.has_method("set_pull_target"):
			raw.call("set_pull_target",self,phase2_pull_radius)

func _update_phase2(delta:float) -> void:
	_self_drain_accumulator += phase2_self_drain_per_second * delta
	var drain:int = int(floor(_self_drain_accumulator))
	if drain > 0:
		_self_drain_accumulator -= float(drain)
		health -= drain
	_pull_world_objects(delta)
	_damage_elapsed += delta
	if _damage_elapsed >= phase2_damage_interval:
		_damage_elapsed = 0.0
		for target:ball in TOOLS.enemies_in_radius(self,global_position,phase2_damage_radius):
			target.receive_positional_damage(attack_damage(phase2_tick_damage_multiplier),global_position,true,self)

func _pull_world_objects(delta:float) -> void:
	var radius:float = maxf(phase2_pull_radius,1.0)
	var radius_sq:float = radius * radius
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if target == self or target.health <= 0:
			continue

		var is_projectile:bool = target.Type == ball.Ball_Type.Shooter or target.Type == ball.Ball_Type.Shooter_with_Health
		if is_projectile:
			if TOOLS.same_side(self,target):
				continue
		elif not TOOLS.is_enemy(self,target):
			continue

		var offset:Vector2 = global_position - target.global_position
		var dist_sq:float = offset.length_squared()
		if dist_sq > radius_sq or dist_sq <= 1.0:
			continue
		var dist:float = sqrt(dist_sq)

		# 角色只被吸到黑洞伤害圈内部的安全环，不再被拖进本体碰撞盒。
		# 子弹仍可以被吸到中心并被吞掉/继续自己的逻辑。
		var stop_radius:float = 10.0 if is_projectile else minf(phase2_pull_stop_radius,phase2_damage_radius * 0.92)
		if dist <= stop_radius:
			continue

		# 吸力有限：边缘为 0，越靠近中心才越强，并有明确的最大移动速度。
		var proximity:float = clampf(1.0 - dist / radius,0.0,1.0)
		var strength:float = phase2_pull_speed * pow(proximity,1.35)
		var max_step:float = maxf((dist - stop_radius),0.0)
		var step:float = minf(strength * delta,max_step)
		if step > 0.0:
			target.global_position += offset.normalized() * step

	# 文字的吸力也遵守同一个有限半径，不再隔着整张地图被拉过来。
	for raw_text:Node in get_tree().get_nodes_in_group("HeavyGirlText"):
		if raw_text != null and is_instance_valid(raw_text) and raw_text.has_method("set_pull_target"):
			raw_text.call("set_pull_target",self,phase2_pull_radius)

func _spawn_text() -> void:
	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var red:bool = randf() < red_text_chance
	var raw_text:String = text_pool[randi() % text_pool.size()] if not text_pool.is_empty() else "..."
	var point := Vector2(randf_range(rect.position.x + 30.0,rect.end.x - 30.0),randf_range(rect.position.y + 30.0,rect.end.y - 30.0))
	var seed_value:int = randi()
	_spawn_text_local(raw_text,red,point,seed_value,false)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_text.rpc(raw_text,red,point,seed_value)


@rpc("authority","call_remote","unreliable")
func _rpc_spawn_text(raw_text:String,red:bool,point:Vector2,seed_value:int) -> void:
	_spawn_text_local(raw_text,red,point,seed_value,true)


func _spawn_text_local(raw_text:String,red:bool,point:Vector2,seed_value:int,visual_only:bool) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var text_node:Node2D = TEXT_SCRIPT.new()
	text_node.set("reveal_duration",text_reveal_duration * (0.5 if _phase2 else 1.0))
	text_node.set("min_damage",0.0 if visual_only else attack_damage(text_min_damage_multiplier))
	text_node.set("max_damage",0.0 if visual_only else attack_damage(text_max_damage_multiplier))
	text_node.call("setup",self,raw_text,red,point,seed_value,visual_only)
	if _phase2:
		text_node.call("set_pull_target",self,phase2_pull_radius)
	world.add_child(text_node)

func _broadcast_visual_state(state_value:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_visual_state.rpc(state_value)
	else:
		_rpc_set_visual_state(state_value)

@rpc("authority","call_local","reliable")
func _rpc_set_visual_state(state_value:int) -> void:
	_set_visual_state_local(state_value)

func _set_visual_state_local(state_value:int) -> void:
	if not (image is Sprite2D):
		return
	var wanted:Texture2D = normal_texture
	if state_value == VISUAL_BLACK_HOLE and black_hole_texture != null:
		wanted = black_hole_texture
	if wanted == null:
		return
	var sprite := image as Sprite2D
	if sprite.texture == wanted:
		return
	sprite.texture = wanted
	sprite.self_modulate = Color.WHITE
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _build_phase2_visual() -> void:
	_black_hole_visual = BLACK_HOLE_VISUAL_SCRIPT.new()

	# 黑洞放到 Graphics/Image 前面：地图之上、人物图片之后。
	# 外形恢复最初会持续扭曲变化的版本，内部由视觉脚本同步填黑。
	var graphics:Node = get_node_or_null("Graphics")
	if graphics is Node2D:
		(graphics as Node2D).add_child(_black_hole_visual)
		(graphics as Node2D).move_child(_black_hole_visual,0)
	else:
		add_child(_black_hole_visual)
	_black_hole_visual.z_index = 0
	_black_hole_visual.z_as_relative = true
	# 恢复早期版本的轮廓尺寸：直接使用二阶段伤害半径作为扭曲形状半径。
	_black_hole_visual.call("configure",phase2_damage_radius)
	_black_hole_visual.call("set_map_rect",TOOLS.map_rect(self))
	_black_hole_visual.call("set_active",false)

func _update_phase2_visual() -> void:
	if _black_hole_visual == null or not is_instance_valid(_black_hole_visual):
		return
	_black_hole_visual.call("set_active",_phase2)
	if _phase2:
		_black_hole_visual.call("set_map_rect",TOOLS.map_rect(self))
