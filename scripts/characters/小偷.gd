extends ball

const STAT_FOLLOW_LABEL_SCRIPT := preload("res://scripts/characters/属性提示.gd")
const THIEF_READY_SFX:AudioStream = preload("res://audio/characters/小偷/小偷_坏笑.mp3")
const THIEF_SUCCESS_SFX:AudioStream = preload("res://audio/characters/小偷/小偷_金币.mp3")

@export_category("偷窃")
@export_range(0.1,30.0,0.1) var steal_interval:float = 4.5
@export_range(0.01,0.5,0.01) var steal_ratio_min:float = 0.06
@export_range(0.01,0.5,0.01) var steal_ratio_max:float = 0.16
@export_range(1.0,3.0,0.05) var health_steal_cap_ratio:float = 1.2
@export var stealable_attributes:Array[String] = ["伤害","速度","生命","攻速"]

@export_category("小偷 - 音效")
@export_range(-24.0,12.0,0.5) var steal_ready_volume_db:float = 7.0
@export_range(-24.0,12.0,0.5) var steal_success_volume_db:float = 5.0
@export_range(100.0,3000.0,50.0) var thief_sfx_max_distance:float = 1400.0
@export_range(0.05,2.0,0.05) var thief_sfx_attenuation:float = 0.35

@export_category("角色贴图")
@export var normal_texture:Texture2D
@export var steal_ready_texture:Texture2D

@export_category("偷窃提示")
@export_range(6,24,1) var stat_text_font_size:int = 8
@export_range(0.2,3.0,0.1) var stat_text_duration:float = 1.25
@export var stat_text_left_offset:Vector2 = Vector2(7.0,-7.0)

var _steal_ready:bool = false
var _steal_charge_left:float = 0.0
var _initial_max_health:int = 1


func _ready() -> void:
	# 小偷属于贴身角色，实体碰撞本身就应造成 Damage；必须在 ball._ready()
	# 关闭 hitbox.monitoring 之前把开关打开。
	Has_Collision_Damage = true
	super._ready()
	_steal_charge_left = maxf(steal_interval,0.05)
	_initial_max_health = maxi(int(default_properties.get("Max_health",Max_health)),1)
	_set_character_texture(normal_texture)


func tick_physics(state:State,delta:float) -> void:
	if not _steal_ready:
		_steal_charge_left -= delta
		if _steal_charge_left <= 0.0:
			_steal_ready = true
			_set_character_texture(steal_ready_texture)
			if is_multiplayer_authority():
				_play_thief_sfx_everywhere("ready",global_position)
	super.tick_physics(state,delta)


func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	if is_multiplayer_authority() and _steal_ready:
		var other = collision.get_collider()
		if _is_enemy_character(other):
			# 先锁掉本次机会，防止同一物理帧多次碰撞重复偷属性。
			_steal_ready = false
			_steal_charge_left = maxf(steal_interval,0.05)
			_set_character_texture(normal_texture)
			_steal_from(other as ball)

	super.when_collide(speed,collision)


func _set_character_texture(texture:Texture2D) -> void:
	if image is Sprite2D and texture != null:
		(image as Sprite2D).texture = texture


func _is_enemy_character(value) -> bool:
	if value == null or not is_instance_valid(value) or not (value is ball):
		return false
	var target:ball = value as ball
	if target == self or target.Type != Ball_Type.Ball or target.health <= 0:
		return false
	if Team != "" and target.Team != "" and Team == target.Team:
		return false
	return true


func _steal_from(target:ball) -> void:
	if stealable_attributes.is_empty():
		return

	# 一次碰撞最多成功偷“一种”属性。
	# 为避免随机到已到上/下限的属性后完全没效果，打乱后依次寻找第一个可偷项目。
	var choices:Array = stealable_attributes.duplicate()
	choices.shuffle()
	var result:Dictionary = {}

	for raw_attr in choices:
		var attr:String = str(raw_attr)
		match attr:
			"伤害":
				result = _steal_positive_stat(target,"Damage",1.0,"伤害",_roll_steal_ratio())
			"速度":
				result = _steal_positive_stat(target,"Speed",20.0,"速度",_roll_steal_ratio())
			"生命":
				result = _steal_max_health(target,_roll_steal_ratio())
			"攻速":
				result = _steal_attack_speed(target,_roll_steal_ratio())
			_:
				result = {}

		if not result.is_empty():
			_broadcast_steal_result(target,result)
			_play_thief_sfx_everywhere("success",global_position)
			return


func _play_thief_sfx_everywhere(kind:String,position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_thief_sfx.rpc(kind,position_value)
	else:
		_rpc_play_thief_sfx(kind,position_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_thief_sfx(kind:String,position_value:Vector2) -> void:
	var stream:AudioStream = null
	var volume_value:float = 0.0
	match kind:
		"ready":
			stream = THIEF_READY_SFX
			volume_value = steal_ready_volume_db
		"success":
			stream = THIEF_SUCCESS_SFX
			volume_value = steal_success_volume_db
		_:
			return
	if stream == null or get_tree().current_scene == null:
		return

	# 放到场景根节点播放，避免小偷刚好死亡/被删除时把已触发的声音一起截断。
	var player := AudioStreamPlayer2D.new()
	player.name = "ThiefSfx_" + kind
	player.stream = stream
	player.volume_db = volume_value
	player.max_distance = thief_sfx_max_distance
	player.attenuation = thief_sfx_attenuation
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _roll_steal_ratio() -> float:
	# 每次真正偷属性时都在 Inspector 范围内重新随机，
	# 不再固定偷同一个百分比。即使同一属性连续被偷，数值也会不同。
	var low:float = clampf(minf(steal_ratio_min,steal_ratio_max),0.01,0.5)
	var high:float = clampf(maxf(steal_ratio_min,steal_ratio_max),low,0.5)
	return randf_range(low,high)


func _steal_positive_stat(target:ball,key:String,minimum_value:float,display_name:String,ratio:float) -> Dictionary:
	if not target.default_properties.has(key) or not default_properties.has(key):
		return {}

	var target_base:float = float(target.default_properties[key])
	var self_base:float = float(default_properties[key])
	var removable:float = maxf(target_base - minimum_value,0.0)
	var requested:float = maxf(target_base * ratio,0.0)
	var amount:float = minf(requested,removable)
	if amount <= 0.0001:
		return {}

	if key == "Damage":
		var enemy_value:int = maxi(int(round(target_base - amount)),int(minimum_value))
		var actual_amount:int = maxi(int(round(target_base)) - enemy_value,0)
		if actual_amount <= 0:
			return {}
		var my_value:int = maxi(int(round(self_base)) + actual_amount,0)
		target.default_properties[key] = enemy_value
		default_properties[key] = my_value
		target.Damage = enemy_value
		Damage = my_value
		return {"name":display_name,"self_delta":float(actual_amount),"target_delta":-float(actual_amount),"suffix":""}

	var enemy_speed:float = maxf(target_base - amount,minimum_value)
	var actual_speed_amount:float = maxf(target_base - enemy_speed,0.0)
	if actual_speed_amount <= 0.0001:
		return {}
	var my_speed:float = maxf(self_base + actual_speed_amount,0.0)
	target.default_properties[key] = enemy_speed
	default_properties[key] = my_speed
	target.Speed = enemy_speed
	Speed = my_speed
	return {"name":display_name,"self_delta":actual_speed_amount,"target_delta":-actual_speed_amount,"suffix":""}


func _steal_max_health(target:ball,ratio:float) -> Dictionary:
	var target_base:int = int(target.default_properties.get("Max_health",target.Max_health))
	var removable:int = maxi(target_base - 10,0)
	if removable <= 0:
		return {}

	var self_base:int = int(default_properties.get("Max_health",Max_health))
	var self_cap:int = maxi(int(round(float(_initial_max_health) * health_steal_cap_ratio)),_initial_max_health)
	var room:int = maxi(self_cap - self_base,0)
	if room <= 0:
		return {}

	var requested:int = maxi(int(round(float(target_base) * ratio)),1)
	var amount:int = mini(requested,mini(removable,room))
	if amount <= 0:
		return {}

	var target_new:int = maxi(target_base - amount,10)
	var self_new:int = mini(self_base + amount,self_cap)
	var actual_amount:int = self_new - self_base
	if actual_amount <= 0:
		return {}

	target.default_properties["Max_health"] = target_new
	target.Max_health = target_new
	if target.health_bar != null:
		target.health_bar.suppress_floating_text = true
	target.health = mini(target.health,target_new)
	if target.health_bar != null:
		target.health_bar.suppress_floating_text = false

	default_properties["Max_health"] = self_new
	Max_health = self_new
	if health_bar != null:
		health_bar.suppress_floating_text = true
	health = mini(health + actual_amount,Max_health)
	if health_bar != null:
		health_bar.suppress_floating_text = false

	return {"name":"生命","self_delta":float(actual_amount),"target_delta":-float(actual_amount),"suffix":""}


func _steal_attack_speed(target:ball,ratio:float) -> Dictionary:
	ratio = clampf(ratio,0.01,0.45)
	var target_base:float = maxf(float(target.default_properties.get("Attack_Cooling",target.Attack_Cooling)),0.05)
	var self_base:float = maxf(float(default_properties.get("Attack_Cooling",Attack_Cooling)),0.05)

	# Attack_Cooling 越小，实际攻速越快。
	var target_new:float = target_base * (1.0 + ratio)
	var self_new:float = maxf(self_base * (1.0 - ratio),0.15)
	if is_equal_approx(target_new,target_base) or is_equal_approx(self_new,self_base):
		return {}

	target.default_properties["Attack_Cooling"] = target_new
	default_properties["Attack_Cooling"] = self_new
	target.Attack_Cooling = target_new
	Attack_Cooling = self_new

	# “攻速”按 1 / Attack_Cooling 计算实际变化，而不是直接显示随机冷却比例。
	var self_percent:float = (self_base / self_new - 1.0) * 100.0
	var target_percent:float = (target_base / target_new - 1.0) * 100.0
	return {"name":"攻速","self_delta":self_percent,"target_delta":target_percent,"suffix":"%"}


func _format_delta(value:float,suffix:String) -> String:
	var sign:String = "+" if value >= 0.0 else "-"
	var abs_value:float = absf(value)
	var number:String
	if is_equal_approx(abs_value,round(abs_value)):
		number = str(int(round(abs_value)))
	else:
		number = "%.1f" % abs_value
	return sign + number + suffix


func _format_stat_change(attr_name:String,value:float,suffix:String) -> String:
	# 只显示真正发生的属性变化，例如“+伤害 3”“-攻速 9.1%”。
	var formatted_delta:String = _format_delta(value,suffix)
	var sign:String = formatted_delta.left(1)
	var amount:String = formatted_delta.substr(1)
	return "%s%s %s" % [sign,attr_name,amount]


func _broadcast_steal_result(target:ball,result:Dictionary) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var target_path:NodePath = target.get_path()
	if multiplayer.has_multiplayer_peer():
		_rpc_show_steal_result.rpc(target_path,result)
	else:
		_rpc_show_steal_result(target_path,result)


@rpc("authority","call_local","unreliable")
func _rpc_show_steal_result(target_path:NodePath,result:Dictionary) -> void:
	var value:Node = get_node_or_null(target_path)
	if not (value is ball) or not is_instance_valid(value):
		return
	_show_steal_result(value as ball,result)


func _show_steal_result(target:ball,result:Dictionary) -> void:
	var attr_name:String = str(result.get("name","属性"))
	var suffix:String = str(result.get("suffix",""))
	var self_delta:float = float(result.get("self_delta",0.0))
	var target_delta:float = float(result.get("target_delta",0.0))

	# 正面效果统一放右侧下方；负面效果统一放左侧。
	side_status_push_temporary(
		"positive",
		_format_stat_change(attr_name,self_delta,suffix),
		Color(0.30,1.0,0.40,1.0),
		stat_text_duration
	)
	target.side_status_push_temporary(
		"negative",
		_format_stat_change(attr_name,target_delta,suffix),
		Color(1.0,0.30,0.30,1.0),
		stat_text_duration
	)


func Die() -> void:
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
