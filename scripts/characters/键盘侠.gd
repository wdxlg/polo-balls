extends ball

const TEXT_PROJECTILE_SCENE := preload("res://scenes/shooter/键盘文字.tscn")

@export_category("词库")
@export var word_bank:Array[String] = [
	"菜",
	"就这",
	"不会玩",
	"急了急了",
	"你会不会玩",
	"建议重开",
	"这也能输",
	"畜生",
	"兔崽子",
	"牛马",
	"猫崽子",
	"毒狗",
	"刀狗",
	"虫子",
	"蜂狗",
	"怪物",
	"蛆",
	"阴人",
	"神棍",
	"剑奴",
	"莽夫",
	"小偷",
	"贼",
	"资本家",
	"奸商",
	"老六",
	"复读机",
	"官僚",
	"老登",
	"棋篓子",
	"酒鬼",
	"喷子",
	"键盘侠",
	"书呆子",
	"疯子",
	"骗子",
	"变色龙",
	"小丑",
	"乐子人",
	"铁疙瘩",
	"狼崽子",
	"老鼠",
	"网红",
	"木头人",
]

@export_category("文字攻击")
@export_range(0.0,10.0,0.05) var damage_per_character_multiplier:float = 1.0
@export_range(1.0,10.0,0.25) var negative_tag_damage_multiplier:float = 4.0
@export_range(0,100,1) var enemy_damage_gain_per_hit:int = 3
@export_range(10.0,1500.0,10.0) var text_speed:float = 280.0
@export_range(0.0,300.0,1.0) var spawn_offset:float = 32.0
@export_range(0.0,32.0,0.5) var spawn_lateral_jitter:float = 8.0
@export_range(0.0,16.0,0.5) var spawn_forward_jitter:float = 4.0
@export_range(0.0,1.0,0.005) var attack_windup:float = 0.02
@export var typing_audio_group:String = "键盘侠攻击"
@export var hit_audio:String = "balls_hit1"

# 可选命中观察者/唯一目标：仅薇欧拉录音地图外来客使用。普通键盘侠保持 null，行为完全不变。
var attack_observer:Node = null
var locked_attack_target:ball = null


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return

	var target = Target_Enemy if is_instance_valid(Target_Enemy) else Nearest_Enemy
	if (target == null or not is_instance_valid(target)) and not has_player_control_aim():
		Attacking = false
		return

	var text:String = "..."
	if not word_bank.is_empty():
		text = str(word_bank.pick_random())
	if text.is_empty():
		text = "..."

	var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (target.global_position - global_position)
	if dir.length_squared() <= 0.000001:
		dir = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	dir = dir.normalized()

	var projectile:ball = TEXT_PROJECTILE_SCENE.instantiate()
	projectile.set("word_text",text)
	projectile.set("rage_damage_gain",enemy_damage_gain_per_hit)
	projectile.set("hit_observer",attack_observer)
	if locked_attack_target != null and is_instance_valid(locked_attack_target):
		projectile.call("set_locked_target",locked_attack_target)
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Target_Enemy = null if has_player_control_aim() else target
	var word_damage:int = maxi(int(round(attack_damage(damage_per_character_multiplier * float(maxi(text.length(),1))))),0)
	projectile.Damage = word_damage
	projectile.set("base_word_damage",word_damage)
	projectile.set("negative_tag_damage_multiplier",negative_tag_damage_multiplier)
	projectile.Speed = text_speed
	projectile.Hit_Audio = hit_audio
	projectile.direction = dir
	var lateral_dir:Vector2 = Vector2(-dir.y,dir.x)
	var randomized_forward:float = spawn_offset + randf_range(-spawn_forward_jitter,spawn_forward_jitter)
	var randomized_side:float = randf_range(-spawn_lateral_jitter,spawn_lateral_jitter)
	projectile.global_position = global_position + dir * randomized_forward + lateral_dir * randomized_side
	projectile.global_rotation = dir.angle()
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)

	if typing_audio_group != "":
		Audios.play_sfx_from_node.rpc(typing_audio_group,{},false,true)

	Attacking = true
	await get_tree().create_timer(maxf(attack_windup,0.01)).timeout
	if is_instance_valid(self):
		Attacking = false


# 薇欧拉地图外支援专用：不依赖键盘侠 StateMachine，但文字仍由真实键盘侠实例自己生成，
# 使用键盘侠原生词库、spawn_offset/jitter、攻击音效和伤害计算。
func fire_viola_support_text(attack_target:ball,observer:Node,map_rect:Rect2) -> ball:
	if attack_target == null or not is_instance_valid(attack_target):
		return null
	if not is_inside_tree() or get_tree().current_scene == null:
		return null

	var text:String = "..."
	if not word_bank.is_empty():
		text = str(word_bank.pick_random())
	if text.is_empty():
		text = "..."

	var dir:Vector2 = attack_target.global_position-global_position
	if dir.length_squared() <= 0.000001:
		dir = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	dir = dir.normalized()

	var projectile:ball = TEXT_PROJECTILE_SCENE.instantiate()
	projectile.set("word_text",text)
	projectile.set("rage_damage_gain",0)
	projectile.set("hit_observer",observer)
	projectile.call("set_locked_target",attack_target)
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Target_Enemy = attack_target
	var word_damage:int = maxi(int(round(attack_damage(damage_per_character_multiplier * float(maxi(text.length(),1))))),0)
	projectile.Damage = word_damage
	projectile.set("base_word_damage",word_damage)
	projectile.set("negative_tag_damage_multiplier",negative_tag_damage_multiplier)
	projectile.Speed = text_speed
	projectile.Hit_Audio = hit_audio
	projectile.direction = dir
	var lateral_dir:Vector2 = Vector2(-dir.y,dir.x)
	var randomized_forward:float = spawn_offset + randf_range(-spawn_forward_jitter,spawn_forward_jitter)
	var randomized_side:float = randf_range(-spawn_lateral_jitter,spawn_lateral_jitter)
	# V412：从真实键盘侠本体前方生成，绝不再使用地图墙内侧伪造枪口。
	projectile.global_position = global_position + dir * randomized_forward + lateral_dir * randomized_side
	projectile.global_rotation = dir.angle()
	if map_rect.size.x > 1.0 and map_rect.size.y > 1.0 and projectile.has_method("enable_outside_map_launch"):
		projectile.call("enable_outside_map_launch",map_rect)
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)

	if typing_audio_group != "":
		Audios.play_sfx_from_node.rpc(typing_audio_group,{},false,true)
	return projectile


func Die() -> void:
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
