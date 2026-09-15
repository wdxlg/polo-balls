extends "res://scripts/characters/三角洲/跑刀仔.gd"

# V101：堵桥
# - 直接复用猛攻哥第二命的 PSG-1 枪械/换弹/瞄准/枪声/枪口视觉逻辑。
# - 固定只携带 PSG-1，降低射速并加入小幅散布。
# - 技能只从地图上边界跑出去；在地图上方可沿 X 轴左右移动、转向并持续攻击，然后从当前位置返回地图内。
# - 越界阶段临时关闭角色对地图墙/角色身体的实体碰撞，并向 World 标记合法越界。
# - 技能从地图外射出的专用 PSG 子弹可穿过“进入地图的那一道边界”，进入地图后恢复墙碰撞。
# - V102 新增丢火和巡飞弹：火圈同时伤敌和伤自己（自己半伤），敌人会叠加战争女神同款灼烧；
#   巡飞弹期间堵桥完全停下且不能开枪，导弹先向上飞，再以较慢转向速度追踪锁定目标，命中后范围爆炸并散出4枚延时小炸弹。
# - V103：燃烧区半径收至58；巡飞弹绘制层提到地图外遮罩之上；4枚小炸弹改用随机MC/TNT爆炸动画和对应tnt音效。
# - V104：巡飞弹大炮与 PSG 按猛攻哥双枪逻辑互为“手持/背枪”；发射巡飞弹时大炮到前手、PSG切到背后，结束后换回；乌鲁鲁人物整体略缩小。
# - V105：人物进一步缩小；PSG 与巡飞弹大炮整体放大；巡飞弹施放时锁定人物朝向与大炮发射角，避免目标跨左右时人物/大炮来回翻转。
# - V106：巡飞弹弹体缩小，并提高近距离转向修正；命中改为不依赖碰撞层的几何扫掠，减少“穿人不炸”。火区到时停止产火/伤害，让已有火苗自然走完淡出。
# - V108：接入乌鲁鲁专属音效；巡飞弹飞行循环音在爆炸时停止；主/子爆炸使用MC帧动画但改播乌鲁鲁专属爆炸声；
#   燃烧弹先收PSG并像切枪一样抽出，落地播放专属音效；实际胜利时播放大笑。
# - V109：手持燃烧弹视觉放大；抽出完成后额外停留约0.8秒再投掷（总准备时间1.2秒）；
#   巡飞弹飞行/爆炸/子炸弹爆炸及随机语音整体提亮音量，并减弱2D距离衰减。
# - V110：燃烧弹准备/投掷期间不再冻结人物移动；拿出燃烧弹时播放“拿火”，真正生成并扔出弹体时才播放新版“扔火”。

const BRIDGE_PSG_BULLET_SCENE:PackedScene = preload("res://scenes/shooter/堵桥PSG子弹.tscn")
const BRIDGE_FIRE_THROW_SCRIPT:Script = preload("res://scripts/effects/堵桥丢火.gd")
const BRIDGE_LOITER_MISSILE_SCRIPT:Script = preload("res://scripts/effects/堵桥巡飞弹.gd")
const BRIDGE_BURN_SFX:AudioStream = preload("res://audio/status/debuff/烫伤.wav")
const ULURU_CHARACTER_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/乌鲁鲁.png")
const ULURU_LAUNCHER_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/大炮.png")
const ULURU_FIRE_BOMB_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/火焰弹.png")

# V108：乌鲁鲁专属音效。用户明确要求忽略“巡飞弹飞.mp3”，因此项目只接入“巡飞弹飞中”。
const ULURU_TAKE_FIRE_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/拿火.mp3")
const ULURU_THROW_FIRE_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/扔火.mp3")
const ULURU_PARENT_LINE_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/我的父母死了.mp3")
const ULURU_SMALL_BOMB_EXPLOSION_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/小炸弹爆炸.mp3")
const ULURU_MISSILE_EXPLOSION_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/巡飞弹爆炸.mp3")
const ULURU_MISSILE_FLIGHT_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/巡飞弹飞中.mp3")
const ULURU_FIRE_LAND_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/火落地.mp3")
const ULURU_VICTORY_LAUGH_SFX:AudioStream = preload("res://audio/characters/乌鲁鲁/大笑.mp3")

# 继续复用项目已有的3套MC爆炸动画帧，但V108不再借用魔角猎人的TNT音效。
# 主巡飞弹和四枚小炸弹都由乌鲁鲁自己的爆炸音效负责声音。
const ULURU_MC_EXPLOSION_FRAMES:Array[SpriteFrames] = [
	preload("res://scenes/effects/魔角猎人_爆炸1动画帧.tres"),
	preload("res://scenes/effects/魔角猎人_爆炸2动画帧.tres"),
	preload("res://scenes/effects/魔角猎人_爆炸3动画帧.tres"),
]

@export_category("堵桥 - PSG")
@export_range(60.0,840.0,5.0) var bridge_psg_rpm:float = 480.0
@export_range(0.0,12.0,0.1) var bridge_psg_spread_deg:float = 2.4

@export_category("堵桥 - 丢火")
@export_range(1.0,30.0,0.1) var bridge_fire_cooldown:float = 7.8
@export_range(0.0,20.0,0.1) var bridge_fire_first_delay:float = 2.6
@export_range(0.15,2.0,0.01) var bridge_fire_throw_duration:float = 0.62
@export_range(8.0,180.0,1.0) var bridge_fire_arc_height:float = 72.0
@export_range(20.0,220.0,1.0) var bridge_fire_radius:float = 58.0
@export_range(0.5,12.0,0.1) var bridge_fire_duration:float = 5.2
@export_range(0.1,2.0,0.05) var bridge_fire_tick_interval:float = 0.75
@export_range(0.0,12.0,0.1) var bridge_fire_damage_multiplier:float = 2.4
@export_range(0.0,1.0,0.05) var bridge_fire_self_damage_ratio:float = 0.5
@export_range(0.2,12.0,0.1) var bridge_burn_duration:float = 4.0
@export_range(0.1,2.0,0.05) var bridge_burn_tick_interval:float = 0.5
@export_range(0.0,8.0,0.05) var bridge_burn_tick_damage_multiplier:float = 0.7
@export_range(0.006,0.08,0.0005) var bridge_fire_particle_interval:float = 0.0107
@export_category("乌鲁鲁 - 燃烧弹演出")
@export_range(0.2,2.0,0.05) var uluru_fire_prepare_time:float = 1.2
@export_range(0.1,0.8,0.05) var uluru_fire_draw_time:float = 0.40
@export_range(0.1,0.8,0.05) var uluru_fire_restore_time:float = 0.34
@export_range(12.0,90.0,1.0) var uluru_fire_hand_visual_length:float = 44.0

@export_category("堵桥 - 巡飞弹")
@export_range(2.0,40.0,0.1) var bridge_missile_cooldown:float = 12.5
@export_range(0.0,30.0,0.1) var bridge_missile_first_delay:float = 6.3
@export_range(0.05,1.2,0.01) var bridge_missile_rise_duration:float = 0.38
@export_range(80.0,900.0,5.0) var bridge_missile_rise_speed:float = 330.0
@export_range(120.0,1200.0,5.0) var bridge_missile_cruise_speed:float = 560.0
@export_range(20.0,360.0,1.0) var bridge_missile_turn_speed_deg:float = 150.0
@export_range(0.8,10.0,0.1) var bridge_missile_lifetime:float = 5.2
@export_range(3.0,40.0,0.5) var bridge_missile_hit_radius:float = 11.0
@export_range(20.0,220.0,1.0) var bridge_missile_impact_radius:float = 78.0
@export_range(0.0,30.0,0.1) var bridge_missile_impact_damage_multiplier:float = 8.0
@export_range(0.2,3.0,0.05) var bridge_missile_bomb_fuse:float = 0.9
@export_range(10.0,160.0,1.0) var bridge_missile_bomb_radius:float = 46.0
@export_range(0.0,15.0,0.1) var bridge_missile_bomb_damage_multiplier:float = 3.2
@export_range(0.0,1.0,0.01) var uluru_parent_line_chance:float = 0.25

@export_category("乌鲁鲁 - 武器视觉")
@export_range(80.0,260.0,2.0) var uluru_psg_visual_length:float = 186.0
@export_range(0.5,1.0,0.01) var uluru_psg_back_scale_ratio:float = 0.84
@export_range(80.0,280.0,2.0) var uluru_launcher_visual_length:float = 194.0
@export_range(0.5,1.0,0.01) var uluru_launcher_back_scale_ratio:float = 0.84

@export_category("堵桥 - 越界射击技能")
@export_range(1.0,30.0,0.1) var bridge_skill_cooldown:float = 9.0
@export_range(0.0,20.0,0.1) var bridge_skill_first_delay:float = 4.5
@export_range(0.5,8.0,0.1) var bridge_outside_fire_duration:float = 2.4
@export_range(8.0,120.0,1.0) var bridge_outside_gap:float = 34.0
@export_range(4.0,100.0,1.0) var bridge_return_inset:float = 24.0
@export_range(1.0,3.0,0.05) var bridge_skill_run_speed_multiplier:float = 1.65
@export_range(2.0,24.0,0.5) var bridge_skill_arrive_distance:float = 6.0
@export_range(2.0,40.0,0.5) var bridge_outside_horizontal_deadzone:float = 8.0
@export_range(0.25,2.0,0.05) var bridge_outside_horizontal_speed_multiplier:float = 1.0

const BRIDGE_PHASE_IDLE:int = 0
const BRIDGE_PHASE_RUN_OUT:int = 1
const BRIDGE_PHASE_FIRE_OUTSIDE:int = 2
const BRIDGE_PHASE_RETURN:int = 3

var _bridge_phase:int = BRIDGE_PHASE_IDLE
var _bridge_cooldown_left:float = 0.0
var _bridge_phase_left:float = 0.0
var _bridge_outside_target:Vector2 = Vector2.ZERO
var _bridge_return_target:Vector2 = Vector2.ZERO
var _bridge_saved_body_mask_layer1:bool = true
var _bridge_saved_body_mask_layer2:bool = true
var _bridge_saved_body_layer2:bool = true
var _bridge_saved_z_index:int = 0
var _bridge_escape_snapshot_valid:bool = false

var _bridge_fire_cooldown_left:float = 0.0
var _bridge_missile_cooldown_left:float = 0.0
var _bridge_missile_active:bool = false
var _bridge_missile_target_ref:WeakRef = null
var _uluru_launcher_sprite:Sprite2D = null
var _uluru_launcher_is_front:bool = false
var _uluru_launcher_locked_aim_angle:float = 0.0
var _uluru_launcher_locked_facing_sign:float = 1.0
var _uluru_launcher_pose_locked:bool = false

# V109：燃烧弹先用约0.4秒抽出，随后手持停留约0.8秒，再在总计约1.2秒时投掷。
var _uluru_fire_prepare_active:bool = false
var _uluru_fire_prepare_elapsed:float = 0.0
var _uluru_fire_recover_active:bool = false
var _uluru_fire_recover_elapsed:float = 0.0
var _uluru_fire_target_position:Vector2 = Vector2.ZERO
var _uluru_fire_pending_config:Dictionary = {}
var _uluru_fire_locked_aim_angle:float = 0.0
var _uluru_fire_locked_facing_sign:float = 1.0
var _uluru_fire_bomb_sprite:Sprite2D = null

var _uluru_missile_flight_player:AudioStreamPlayer2D = null
var _uluru_take_fire_player:AudioStreamPlayer2D = null
var _uluru_victory_laugh_played:bool = false
var _bridge_special_audio_serial:int = 0
var _uluru_explosion_serial:int = 0


func _ready()->void:
	standalone_berserker = true
	super._ready()
	# 跑刀仔基类的 standalone_berserker 初始化会把 Graphics/Image 强制换成猛攻哥第二命贴图。
	# 堵桥就是乌鲁鲁，所以在基类初始化结束后再次强制恢复乌鲁鲁本体，并重做视觉拟合。
	_apply_uluru_character_texture()
	_bridge_cooldown_left = maxf(bridge_skill_first_delay,0.0)
	_bridge_fire_cooldown_left = maxf(bridge_fire_first_delay,0.0)
	_bridge_missile_cooldown_left = maxf(bridge_missile_first_delay,0.0)
	_setup_uluru_launcher_visual()
	_setup_uluru_fire_visual()
	_setup_uluru_missile_flight_player()


# 跑刀仔/猛攻哥基类会在独立猛攻哥初始化时调用这个函数，把人物换成吴彦祖贴图。
# 堵桥在设定上就是乌鲁鲁，因此覆写它，从源头阻止基类把本体换回猛攻哥。
func _apply_runner_character_texture(_texture_path:String)->void:
	_apply_uluru_character_texture()


func _apply_uluru_character_texture()->void:
	var sprite:Sprite2D = get_node_or_null("Graphics/Image") as Sprite2D
	if sprite == null or ULURU_CHARACTER_TEXTURE == null:
		return
	image = sprite
	sprite.texture = ULURU_CHARACTER_TEXTURE
	sprite.visible = true
	sprite.centered = true
	sprite.modulate = Color.WHITE
	sprite.self_modulate = Color.WHITE
	sprite.rotation = 0.0
	sprite.flip_h = false
	# 猛攻哥贴图会开启轻微白化混合；乌鲁鲁不继承这个视觉参数。
	sprite.set_instance_shader_parameter("default_color",Color.WHITE)
	sprite.set_instance_shader_parameter("defualt_color_mix",0.0)
	dir_left = false

	# V105：乌鲁鲁本体继续独立缩小。项目普通人物 AutoFit 基准为 205，
	# 这里先给接近最终结果的尺寸，随后仍交给 CharacterAutoFit 按 alpha 可见区域精确拟合。
	var longest:float = maxf(float(ULURU_CHARACTER_TEXTURE.get_width()),float(ULURU_CHARACTER_TEXTURE.get_height()))
	if longest > 0.001:
		sprite.scale = Vector2.ONE * (174.25 / longest)
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null:
		# 0.85 = 205 * 0.85 ≈ 174.25，本体比普通人物再小约15%。
		auto_fit.set("visual_size_multiplier",0.85)
		if auto_fit.has_method("apply_visual_fit_only"):
			auto_fit.call_deferred("apply_visual_fit_only")


func get_preview_texture()->Texture2D:
	# World 的放置 Ghost 不会进入 SceneTree，必须单独覆盖预览贴图，否则仍会显示猛攻哥。
	return ULURU_CHARACTER_TEXTURE


# 基类会 call_deferred 这个函数；在派生类里覆写后，堵桥只获得固定 PSG。
func _build_random_standalone_berserker_loadout()->void:
	if not standalone_berserker or not is_multiplayer_authority():
		return

	_berserker_items.clear()
	_berserker_weapon_indices.clear()
	_berserker_armor_index = -1
	_berserker_active_weapon_slot = 0
	_berserker_reload_in_progress = false
	_berserker_using_item_index = -1
	_berserker_use_mode = ""
	_berserker_use_fraction = 0.0

	var occupied:Array = [false,false,false,false,false,false,false,false,false]
	var psg:Dictionary = _berserker_definition_for_weapon("PSG-1")
	if psg.is_empty():
		return
	psg["rpm"] = maxf(bridge_psg_rpm,1.0)
	psg["spread_deg"] = maxf(bridge_psg_spread_deg,0.0)
	_append_standalone_berserker_item(psg,occupied)

	var snapshot:Dictionary = {
		"items": _berserker_items.duplicate(true),
		"remaining_money": 0,
		"infinite": false,
	}
	if multiplayer.has_multiplayer_peer():
		_rpc_apply_berserker_loadout.rpc(snapshot)
	else:
		_rpc_apply_berserker_loadout(snapshot)


func _berserker_gun_target_long(weapon:Dictionary,back_slot:bool=false)->float:
	# V105：堵桥只装备 PSG-1。上一版沿用猛攻哥 150 的枪长，配合乌鲁鲁构图显得偏小；
	# 这里独立放大，不改共享跑刀仔/猛攻哥的枪械尺寸。
	if str(weapon.get("name","")) == "PSG-1":
		var target_long:float = maxf(uluru_psg_visual_length,80.0)
		if back_slot:
			target_long *= clampf(uluru_psg_back_scale_ratio,0.5,1.0)
		return target_long
	return super._berserker_gun_target_long(weapon,back_slot)


func _update_berserker_character_facing_from_motion()->void:
	# 巡飞弹/燃烧弹准备阶段都锁定人物朝向，避免武器抽取演出过程中左右翻面。
	if _uluru_launcher_is_front and _uluru_launcher_pose_locked:
		_berserker_character_facing_sign = _uluru_launcher_locked_facing_sign
		set_character_visual_flip_h(_uluru_launcher_locked_facing_sign < 0.0)
		return
	if _uluru_fire_prepare_active or _uluru_fire_recover_active:
		_berserker_character_facing_sign = _uluru_fire_locked_facing_sign
		set_character_visual_flip_h(_uluru_fire_locked_facing_sign < 0.0)
		return
	super._update_berserker_character_facing_from_motion()


func controlled_skill_action()->void:
	if not is_player_controlled() or not is_multiplayer_authority():
		return
	# 直接控制继续保留 V101 的右键“上方越界”技能；新增丢火/巡飞弹由 AI 自动施放，
	# 不额外占用输入映射，避免破坏现有控制方案。
	if _bridge_missile_active or _uluru_fire_prepare_active or _uluru_fire_recover_active or _bridge_phase != BRIDGE_PHASE_IDLE or _bridge_cooldown_left > 0.0001:
		return
	_start_bridge_skill()


func tick_physics(state:State,delta:float)->void:
	var safe_delta:float = maxf(delta,0.0)
	# 燃烧弹的切换演出在所有客户端本地推进；真正生成弹体仍只由 authority 决定并RPC同步。
	_tick_uluru_fire_prepare_visual(safe_delta)
	if is_multiplayer_authority():
		_tick_bridge_special_skills(safe_delta)
		_tick_bridge_skill(safe_delta)
	_update_uluru_launcher_aim()
	super.tick_physics(state,delta)


func move(speed:float,delta:float):
	if _bridge_missile_active:
		# 巡飞弹施放仍维持炮台式稳定姿态。
		# V110：燃烧弹抽出/等待/投掷阶段不再进入这里，人物照常使用原移动逻辑。
		velocity = Vector2.ZERO
		direction = Vector2.ZERO
		Repel = Vector2.ZERO
		return
	if _bridge_phase == BRIDGE_PHASE_RUN_OUT or _bridge_phase == BRIDGE_PHASE_RETURN:
		super.move(speed * maxf(bridge_skill_run_speed_multiplier,1.0),delta)
		return
	if _bridge_phase == BRIDGE_PHASE_FIRE_OUTSIDE:
		# V101：地图上方不是定点炮台。这里只允许左右移动，Y 始终锁在地图上边界之外。
		# AI 使用 _tick_bridge_skill() 给出的左右方向；玩家直接控制时只保留左右输入，忽略上下输入。
		Repel = Vector2.ZERO
		var saved_player_direction:Vector2 = player_control_direction
		if is_player_controlled():
			player_control_direction = Vector2(saved_player_direction.x,0.0)
		else:
			direction = Vector2(direction.x,0.0)
		super.move(speed * maxf(bridge_outside_horizontal_speed_multiplier,0.25),delta)
		if is_player_controlled():
			player_control_direction = saved_player_direction

		# 防止公共位移/恢复产生纵向漂移，也不允许从顶边外横移到左右边外。
		var map_rect:Rect2 = _bridge_map_rect()
		if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
			var tangent_margin:float = 12.0
			global_position.y = map_rect.position.y - bridge_outside_gap
			global_position.x = clampf(global_position.x,map_rect.position.x + tangent_margin,map_rect.end.x - tangent_margin)
		return
	super.move(speed,delta)


func _try_berserker_fire_now()->bool:
	# 巡飞弹、燃烧弹切换演出期间都不允许 PSG 穿模开火；跑出/返回途中同样不开枪。
	if _bridge_missile_active or _uluru_fire_prepare_active or _uluru_fire_recover_active:
		return false
	if _bridge_phase == BRIDGE_PHASE_RUN_OUT or _bridge_phase == BRIDGE_PHASE_RETURN:
		return false
	return super._try_berserker_fire_now()


func _tick_bridge_special_skills(delta:float)->void:
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		_bridge_missile_active = false
		_bridge_missile_target_ref = null
		_hide_uluru_launcher_visual()
		_cancel_uluru_fire_prepare_local()
		_stop_uluru_missile_flight_local()
		Using_Skill = false
		return
	if not is_combat_runtime_active():
		return

	_bridge_fire_cooldown_left = maxf(_bridge_fire_cooldown_left - delta,0.0)
	_bridge_missile_cooldown_left = maxf(_bridge_missile_cooldown_left - delta,0.0)
	if is_player_controlled() or _bridge_phase != BRIDGE_PHASE_IDLE or _bridge_missile_active or _uluru_fire_prepare_active or _uluru_fire_recover_active:
		return

	var enemy_node:Node = return_reusable_combat_target()
	if not enemy_node is ball or not is_instance_valid(enemy_node):
		return
	var enemy:ball = enemy_node as ball

	# 更强的巡飞弹优先级更高；两种技能都有独立冷却，因此不会挤掉原本的越界技能计时。
	if _bridge_missile_cooldown_left <= 0.0001:
		_start_bridge_missile(enemy)
		return
	if _bridge_fire_cooldown_left <= 0.0001:
		_start_bridge_fire(enemy)


func _start_bridge_fire(target:ball)->void:
	if (
		target == null
		or not is_instance_valid(target)
		or health <= 0
		or _bridge_missile_active
		or _uluru_fire_prepare_active
		or _uluru_fire_recover_active
	):
		return
	_bridge_fire_cooldown_left = maxf(bridge_fire_cooldown,0.2)
	var target_position:Vector2 = combat_target_position(target)
	var aim:Vector2 = target_position - global_position
	if aim.length_squared() <= 0.000001:
		aim = _berserker_fallback_facing_direction()
	aim = aim.normalized()
	var facing_sign:float = -1.0 if aim.x < -0.001 else (1.0 if aim.x > 0.001 else _berserker_character_facing_sign)
	var config:Dictionary = {
		"throw_duration": bridge_fire_throw_duration,
		"arc_height": bridge_fire_arc_height,
		"radius": bridge_fire_radius,
		"duration": bridge_fire_duration,
		"tick_interval": bridge_fire_tick_interval,
		"direct_damage_multiplier": bridge_fire_damage_multiplier,
		"self_damage_multiplier": bridge_fire_self_damage_ratio,
		"burn_duration": bridge_burn_duration,
		"burn_tick_interval": bridge_burn_tick_interval,
		"burn_tick_damage_multiplier": bridge_burn_tick_damage_multiplier,
		"particle_interval": bridge_fire_particle_interval,
		"prepare_time": maxf(uluru_fire_prepare_time,0.2),
		"draw_time": minf(maxf(uluru_fire_draw_time,0.1),maxf(uluru_fire_prepare_time,0.2)),
		"restore_time": maxf(uluru_fire_restore_time,0.1),
		"aim_angle": aim.angle(),
		"facing_sign": facing_sign,
	}
	# 先同步“收PSG/抽燃烧弹”演出。V109总准备约1.2秒：约0.4秒抽出 + 约0.8秒手持停顿后再投掷。
	if multiplayer.has_multiplayer_peer():
		_remote_begin_uluru_fire_prepare.rpc(target_position,config)
	else:
		_remote_begin_uluru_fire_prepare(target_position,config)


@rpc("authority","call_local","reliable")
func _remote_begin_uluru_fire_prepare(target_position:Vector2,config:Dictionary)->void:
	_uluru_fire_prepare_active = true
	_uluru_fire_prepare_elapsed = 0.0
	_uluru_fire_recover_active = false
	_uluru_fire_recover_elapsed = 0.0
	_uluru_fire_target_position = target_position
	_uluru_fire_pending_config = config.duplicate(true)
	_uluru_fire_locked_aim_angle = float(config.get("aim_angle",0.0))
	var facing_sign:float = float(config.get("facing_sign",_berserker_character_facing_sign))
	_uluru_fire_locked_facing_sign = 1.0 if facing_sign >= 0.0 else -1.0
	_berserker_character_facing_sign = _uluru_fire_locked_facing_sign
	set_character_visual_flip_h(_uluru_fire_locked_facing_sign < 0.0)
	Using_Skill = true
	Attacking = false
	# V110：这里只进入换枪/拿弹演出，不再清空 velocity / direction / Repel。
	# 因此乌鲁鲁可以像平时一样继续移动，只是准备期间仍禁止 PSG 开火。
	if _uluru_fire_bomb_sprite != null and is_instance_valid(_uluru_fire_bomb_sprite):
		_uluru_fire_bomb_sprite.visible = true
	_apply_uluru_weapon_pair_visual()
	# 拿出燃烧弹的瞬间播放“拿火”；真正投掷的声音改到弹体实际生成那一刻播放。
	_start_uluru_take_fire_audio_local()


func _tick_uluru_fire_prepare_visual(delta:float)->void:
	if not _uluru_fire_prepare_active and not _uluru_fire_recover_active:
		return
	if not is_combat_runtime_active():
		return

	if _uluru_fire_prepare_active:
		_uluru_fire_prepare_elapsed += delta
		var prepare_time:float = maxf(float(_uluru_fire_pending_config.get("prepare_time",uluru_fire_prepare_time)),0.2)
		if _uluru_fire_prepare_elapsed >= prepare_time:
			_uluru_fire_prepare_elapsed = prepare_time
			_uluru_fire_prepare_active = false
			if _uluru_fire_bomb_sprite != null and is_instance_valid(_uluru_fire_bomb_sprite):
				_uluru_fire_bomb_sprite.visible = false
			# 只有authority创建并同步真正的燃烧弹，避免每端各自生成造成重复伤害。
			if is_multiplayer_authority():
				_release_uluru_fire_throw_authority()
			_uluru_fire_recover_active = true
			_uluru_fire_recover_elapsed = 0.0

	if _uluru_fire_recover_active:
		_uluru_fire_recover_elapsed += delta
		var restore_time:float = maxf(float(_uluru_fire_pending_config.get("restore_time",uluru_fire_restore_time)),0.1)
		if _uluru_fire_recover_elapsed >= restore_time:
			_uluru_fire_recover_elapsed = restore_time
			_uluru_fire_recover_active = false
			if not _bridge_missile_active:
				Using_Skill = false
			_uluru_fire_pending_config.clear()
	_apply_uluru_weapon_pair_visual()


func _release_uluru_fire_throw_authority()->void:
	if health <= 0:
		return
	var start_position:Vector2 = global_position + Vector2(
		BERSERKER_HAND_GUN_FRONT_X * _uluru_fire_locked_facing_sign,
		8.0
	)
	if _uluru_fire_bomb_sprite != null and is_instance_valid(_uluru_fire_bomb_sprite):
		start_position = _uluru_fire_bomb_sprite.global_position
	var config:Dictionary = _uluru_fire_pending_config.duplicate(true)
	_spawn_bridge_fire_throw_local(start_position,_uluru_fire_target_position,config)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_bridge_fire_throw.rpc(start_position,_uluru_fire_target_position,config)


func _cancel_uluru_fire_prepare_local()->void:
	_uluru_fire_prepare_active = false
	_uluru_fire_prepare_elapsed = 0.0
	_uluru_fire_recover_active = false
	_uluru_fire_recover_elapsed = 0.0
	_uluru_fire_pending_config.clear()
	if _uluru_fire_bomb_sprite != null and is_instance_valid(_uluru_fire_bomb_sprite):
		_uluru_fire_bomb_sprite.visible = false
	_stop_uluru_take_fire_audio_local()
	_apply_uluru_weapon_pair_visual()


@rpc("authority","call_remote","reliable")
func _remote_spawn_bridge_fire_throw(start_position:Vector2,target_position:Vector2,config:Dictionary)->void:
	_spawn_bridge_fire_throw_local(start_position,target_position,config)


func _spawn_bridge_fire_throw_local(start_position:Vector2,target_position:Vector2,config:Dictionary)->void:
	if get_tree().current_scene == null:
		return
	# V110：声音与“真正扔出”严格同帧发生。这个函数本地/远端都会各执行一次。
	# “拿火”素材本身比当前1.2秒准备时间更长，因此投掷瞬间先停止它，避免和新版“扔火”叠音。
	_stop_uluru_take_fire_audio_local()
	_play_bridge_one_shot(ULURU_THROW_FIRE_SFX,global_position,4.0,1.0)
	var projectile:Node2D = BRIDGE_FIRE_THROW_SCRIPT.new() as Node2D
	if projectile == null:
		return
	projectile.name = "堵桥丢火_%d" % Time.get_ticks_usec()
	get_tree().current_scene.add_child(projectile,true)
	projectile.call("setup",self,start_position,target_position,config)


func _start_bridge_missile(target:ball)->void:
	if target == null or not is_instance_valid(target) or health <= 0 or _bridge_missile_active or _uluru_fire_prepare_active or _uluru_fire_recover_active:
		return
	_bridge_missile_active = true
	_bridge_missile_cooldown_left = maxf(bridge_missile_cooldown,0.5)
	Using_Skill = true
	Attacking = false
	velocity = Vector2.ZERO
	direction = Vector2.ZERO
	Repel = Vector2.ZERO
	var start_position:Vector2 = global_position + Vector2(0.0,-16.0)
	var target_path:NodePath = target.get_path()
	# 每次巡飞弹发射时先随机决定主爆炸与4枚子炸弹各自的MC动画版本，随后随RPC配置同步。
	# V108声音不再借用MC/TNT，改由乌鲁鲁专属巡飞弹/小炸弹爆炸音效统一播放。
	var bomb_mc_explosion_variants:Array = [
		randi_range(1,3),
		randi_range(1,3),
		randi_range(1,3),
		randi_range(1,3),
	]
	var launch_aim:Vector2 = combat_target_position(target) - global_position
	if launch_aim.length_squared() <= 0.000001:
		launch_aim = _berserker_fallback_facing_direction()
	launch_aim = launch_aim.normalized()
	var launch_facing_sign:float = -1.0 if launch_aim.x < -0.001 else (1.0 if launch_aim.x > 0.001 else _berserker_character_facing_sign)
	var config:Dictionary = {
		"launcher_aim_angle": launch_aim.angle(),
		"launcher_facing_sign": launch_facing_sign,
		"rise_duration": bridge_missile_rise_duration,
		"rise_speed": bridge_missile_rise_speed,
		"cruise_speed": bridge_missile_cruise_speed,
		"turn_speed_deg": bridge_missile_turn_speed_deg,
		"lifetime": bridge_missile_lifetime,
		"hit_radius": bridge_missile_hit_radius,
		"impact_radius": bridge_missile_impact_radius,
		"impact_damage_multiplier": bridge_missile_impact_damage_multiplier,
		"bomb_fuse": bridge_missile_bomb_fuse,
		"bomb_radius": bridge_missile_bomb_radius,
		"bomb_damage_multiplier": bridge_missile_bomb_damage_multiplier,
		"bomb_mc_explosion_variants": bomb_mc_explosion_variants,
		"missile_explosion_variant": randi_range(1,3),
	}
	# 用户明确要求使用“巡飞弹飞中”，并忽略“巡飞弹飞”。该声音循环到巡飞弹真正爆炸才停止。
	_start_uluru_missile_audio(randf() < clampf(uluru_parent_line_chance,0.0,1.0))
	_spawn_bridge_missile_local(target_path,start_position,config)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_bridge_missile.rpc(target_path,start_position,config)


@rpc("authority","call_remote","reliable")
func _remote_spawn_bridge_missile(target_path:NodePath,start_position:Vector2,config:Dictionary)->void:
	_spawn_bridge_missile_local(target_path,start_position,config)


func _spawn_bridge_missile_local(target_path:NodePath,start_position:Vector2,config:Dictionary)->void:
	if get_tree().current_scene == null:
		return
	var target_node:Node = get_tree().root.get_node_or_null(target_path)
	if not target_node is ball:
		# 任一客户端若因网络路径解析时序失败，都要本地收掉飞行循环/大炮视觉；
		# authority 还会同时解除真实技能锁。
		_bridge_on_loiter_missile_finished()
		return
	_bridge_missile_target_ref = weakref(target_node as ball)
	_lock_uluru_missile_pose(config,target_node as ball)
	_show_uluru_launcher_visual()
	var missile:Node2D = BRIDGE_LOITER_MISSILE_SCRIPT.new() as Node2D
	if missile == null:
		_bridge_on_loiter_missile_finished()
		return
	missile.name = "堵桥巡飞弹_%d" % Time.get_ticks_usec()
	get_tree().current_scene.add_child(missile,true)
	missile.call("setup",self,target_node as ball,start_position,config)


func _bridge_on_loiter_missile_finished()->void:
	# 所有客户端都可能先后收到本地巡飞弹结束；先本地停掉飞行循环，authority爆炸RPC会再做一次幂等停止。
	_stop_uluru_missile_flight_local()
	_bridge_missile_target_ref = null
	_hide_uluru_launcher_visual()
	_uluru_launcher_pose_locked = false
	# 远端只负责收掉视觉；authority 才维护真实技能状态。
	if not _bridge_missile_active:
		return
	_bridge_missile_active = false
	Using_Skill = false
	Attacking = false
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO


func _setup_uluru_launcher_visual()->void:
	if ULURU_LAUNCHER_TEXTURE == null:
		return
	var graphics:Node = get_node_or_null("Graphics")
	if graphics == null:
		return
	_uluru_launcher_sprite = Sprite2D.new()
	_uluru_launcher_sprite.name = "乌鲁鲁大炮"
	_uluru_launcher_sprite.texture = ULURU_LAUNCHER_TEXTURE
	_uluru_launcher_sprite.centered = true
	_uluru_launcher_sprite.visible = true
	graphics.add_child(_uluru_launcher_sprite)
	_uluru_launcher_is_front = false
	_apply_uluru_weapon_pair_visual()


func _setup_uluru_fire_visual()->void:
	if ULURU_FIRE_BOMB_TEXTURE == null:
		return
	var graphics:Node = get_node_or_null("Graphics")
	if graphics == null:
		return
	_uluru_fire_bomb_sprite = Sprite2D.new()
	_uluru_fire_bomb_sprite.name = "乌鲁鲁手持燃烧弹"
	_uluru_fire_bomb_sprite.texture = ULURU_FIRE_BOMB_TEXTURE
	_uluru_fire_bomb_sprite.centered = true
	_uluru_fire_bomb_sprite.visible = false
	_uluru_fire_bomb_sprite.z_index = 5
	graphics.add_child(_uluru_fire_bomb_sprite)


func _uluru_fire_hand_scale()->Vector2:
	if ULURU_FIRE_BOMB_TEXTURE == null:
		return Vector2.ONE
	var longest:float = maxf(
		float(ULURU_FIRE_BOMB_TEXTURE.get_width()),
		float(ULURU_FIRE_BOMB_TEXTURE.get_height())
	)
	return Vector2.ONE * (maxf(uluru_fire_hand_visual_length,12.0) / maxf(longest,1.0))


func _lock_uluru_missile_pose(config:Dictionary,target:ball)->void:
	var fallback:Vector2 = Vector2.RIGHT if _berserker_character_facing_sign >= 0.0 else Vector2.LEFT
	var aim_angle:float = float(config.get("launcher_aim_angle",fallback.angle()))
	var facing_sign:float = float(config.get("launcher_facing_sign",0.0))
	if absf(facing_sign) < 0.5 and target != null and is_instance_valid(target):
		var to_target:Vector2 = combat_target_position(target) - global_position
		if absf(to_target.x) > 0.001:
			facing_sign = 1.0 if to_target.x > 0.0 else -1.0
	if absf(facing_sign) < 0.5:
		facing_sign = _berserker_character_facing_sign
	_uluru_launcher_locked_aim_angle = aim_angle
	_uluru_launcher_locked_facing_sign = 1.0 if facing_sign >= 0.0 else -1.0
	_uluru_launcher_pose_locked = true
	_berserker_character_facing_sign = _uluru_launcher_locked_facing_sign
	set_character_visual_flip_h(_uluru_launcher_locked_facing_sign < 0.0)


func _show_uluru_launcher_visual()->void:
	# 大炮和 PSG 是两把互换前后位置的武器。巡飞弹开始时，大炮到前手、PSG 收背后。
	_uluru_launcher_is_front = true
	_apply_uluru_weapon_pair_visual()


func _hide_uluru_launcher_visual()->void:
	# 巡飞弹结束：PSG 回到前手，大炮背回身后，同时解除施放姿态锁。
	_uluru_launcher_is_front = false
	_apply_uluru_weapon_pair_visual()
	_uluru_launcher_pose_locked = false


func _update_uluru_launcher_aim()->void:
	if (
		_uluru_launcher_sprite == null
		or not is_instance_valid(_uluru_launcher_sprite)
		or not _uluru_launcher_is_front
	):
		return

	# V105：发射瞬间锁定大炮姿态。巡飞弹本体仍会独立追踪目标，
	# 但人物与发射器不再因为目标在角色左右两侧来回穿越而每帧反转。
	var render_angle:float = _uluru_launcher_locked_aim_angle
	if not _uluru_launcher_pose_locked:
		var target:ball = _bridge_missile_target()
		if target == null:
			return
		var aim:Vector2 = combat_target_position(target) - global_position
		if aim.length_squared() <= 0.000001:
			return
		render_angle = aim.normalized().angle()
	_uluru_launcher_sprite.rotation = render_angle + PI
	_uluru_launcher_sprite.flip_h = false
	_uluru_launcher_sprite.flip_v = cos(render_angle) > 0.0


func _uluru_launcher_scale(front:bool)->Vector2:
	if ULURU_LAUNCHER_TEXTURE == null:
		return Vector2.ONE
	var longest:float = maxf(
		float(ULURU_LAUNCHER_TEXTURE.get_width()),
		float(ULURU_LAUNCHER_TEXTURE.get_height())
	)
	var target_long:float = uluru_launcher_visual_length
	if not front:
		target_long *= clampf(uluru_launcher_back_scale_ratio,0.5,1.0)
	return Vector2.ONE * (target_long / maxf(longest,1.0))


func _apply_uluru_weapon_pair_visual()->void:
	if _uluru_launcher_sprite == null or not is_instance_valid(_uluru_launcher_sprite):
		return
	_uluru_launcher_sprite.visible = true

	# 燃烧弹演出优先级高于普通PSG显示；特殊技能不会与巡飞弹同时启动。
	if _uluru_fire_prepare_active or _uluru_fire_recover_active:
		# 巡飞弹大炮维持背枪位。
		_uluru_launcher_sprite.z_index = -2
		_uluru_launcher_sprite.position = BERSERKER_BACK_GUN_NORMAL_POSITION
		_uluru_launcher_sprite.rotation = BERSERKER_BACK_GUN_NORMAL_ROTATION
		_uluru_launcher_sprite.flip_h = false
		_uluru_launcher_sprite.flip_v = false
		_uluru_launcher_sprite.scale = _uluru_launcher_scale(false)

		var draw_time:float = maxf(float(_uluru_fire_pending_config.get("draw_time",uluru_fire_draw_time)),0.1)
		var progress:float = 1.0
		var recovering:bool = _uluru_fire_recover_active and not _uluru_fire_prepare_active
		if _uluru_fire_prepare_active:
			progress = _berserker_ease_out_cubic(clampf(_uluru_fire_prepare_elapsed / draw_time,0.0,1.0))
		else:
			var restore_time:float = maxf(float(_uluru_fire_pending_config.get("restore_time",uluru_fire_restore_time)),0.1)
			progress = 1.0 - _berserker_ease_out_cubic(clampf(_uluru_fire_recover_elapsed / restore_time,0.0,1.0))

		var front_position:=Vector2(BERSERKER_HAND_GUN_FRONT_X * _uluru_fire_locked_facing_sign,8.0)
		var fire_target_rotation:float = _uluru_fire_locked_aim_angle + PI

		# PSG从正常手持位平滑收到背后；投掷后用同一路径反向拿回。
		if is_instance_valid(_berserker_gun_sprite) and _berserker_gun_sprite.visible:
			var psg_front_position:Vector2 = _berserker_gun_sprite.position
			var psg_front_rotation:float = _berserker_gun_sprite.rotation
			var psg_front_scale:Vector2 = _berserker_gun_sprite.scale
			var psg_back_scale:Vector2 = psg_front_scale
			var current_index:int = _current_berserker_weapon_item_index()
			if current_index >= 0 and current_index < _berserker_items.size():
				var weapon:Dictionary = _berserker_items[current_index]
				var tex:Texture2D = _berserker_gun_sprite.texture
				if tex != null:
					var gun_long:float = maxf(float(tex.get_width()),float(tex.get_height()))
					psg_back_scale = Vector2.ONE * (
						_berserker_gun_target_long(weapon,true) / maxf(gun_long,1.0)
					)
			_berserker_gun_sprite.z_index = -2 if progress > 0.48 else 5
			_berserker_gun_sprite.position = psg_front_position.lerp(BERSERKER_BACK_GUN_NORMAL_POSITION,progress)
			_berserker_gun_sprite.rotation = lerp_angle(psg_front_rotation,BERSERKER_BACK_GUN_NORMAL_ROTATION,progress)
			_berserker_gun_sprite.scale = psg_front_scale.lerp(psg_back_scale,progress)
			_berserker_gun_sprite.flip_h = false
			_berserker_gun_sprite.flip_v = false if progress > 0.48 else _berserker_gun_sprite.flip_v

		if _uluru_fire_bomb_sprite != null and is_instance_valid(_uluru_fire_bomb_sprite):
			_uluru_fire_bomb_sprite.visible = not recovering
			if not recovering:
				# 像猛攻哥切枪一样，从背部略抬高的位置抽到前手，而不是瞬间出现。
				var start_position:Vector2 = BERSERKER_BACK_GUN_SWITCH_START_POSITION
				if _uluru_fire_locked_facing_sign < 0.0:
					start_position.x = -start_position.x
				_uluru_fire_bomb_sprite.position = start_position.lerp(front_position,progress)
				_uluru_fire_bomb_sprite.rotation = lerp_angle(
					BERSERKER_BACK_GUN_SWITCH_START_ROTATION,
					fire_target_rotation,
					progress
				)
				_uluru_fire_bomb_sprite.scale = _uluru_fire_hand_scale() * lerpf(0.78,1.0,progress)
				_uluru_fire_bomb_sprite.flip_h = false
				_uluru_fire_bomb_sprite.flip_v = cos(_uluru_fire_locked_aim_angle) > 0.0
		return

	if _uluru_fire_bomb_sprite != null and is_instance_valid(_uluru_fire_bomb_sprite):
		_uluru_fire_bomb_sprite.visible = false

	if _uluru_launcher_is_front:
		# 与猛攻哥当前手持枪相同：前枪跟随目标瞄准并在人物前景。
		_uluru_launcher_sprite.z_index = 5
		_uluru_launcher_sprite.position = Vector2(
			BERSERKER_HAND_GUN_FRONT_X * _berserker_character_facing_sign,
			8.0
		)
		_uluru_launcher_sprite.scale = _uluru_launcher_scale(true)
		_update_uluru_launcher_aim()

		# PSG 仍是猛攻哥真实枪械 Sprite，但巡飞弹期间把它切到背枪位。
		if is_instance_valid(_berserker_gun_sprite) and _berserker_gun_sprite.visible:
			var current_index:int = _current_berserker_weapon_item_index()
			if current_index >= 0 and current_index < _berserker_items.size():
				var weapon:Dictionary = _berserker_items[current_index]
				var tex:Texture2D = _berserker_gun_sprite.texture
				if tex != null:
					var gun_long:float = maxf(float(tex.get_width()),float(tex.get_height()))
					_berserker_gun_sprite.scale = Vector2.ONE * (
						_berserker_gun_target_long(weapon,true) / maxf(gun_long,1.0)
					)
			_berserker_gun_sprite.z_index = -2
			_berserker_gun_sprite.position = BERSERKER_BACK_GUN_NORMAL_POSITION
			_berserker_gun_sprite.rotation = BERSERKER_BACK_GUN_NORMAL_ROTATION
			_berserker_gun_sprite.flip_h = false
			_berserker_gun_sprite.flip_v = false
	else:
		# PSG 由猛攻哥基类维持正常手持；大炮按同一套背枪位置收在身后。
		_uluru_launcher_sprite.z_index = -2
		_uluru_launcher_sprite.position = BERSERKER_BACK_GUN_NORMAL_POSITION
		_uluru_launcher_sprite.rotation = BERSERKER_BACK_GUN_NORMAL_ROTATION
		_uluru_launcher_sprite.flip_h = false
		_uluru_launcher_sprite.flip_v = false
		_uluru_launcher_sprite.scale = _uluru_launcher_scale(false)


func _update_berserker_equipment_visual_transform()->void:
	# 先让猛攻哥基类计算 PSG 的正常手持/瞄准，再把乌鲁鲁两把枪按当前技能状态重新排成前枪+背枪。
	super._update_berserker_equipment_visual_transform()
	_apply_uluru_weapon_pair_visual()


func _bridge_missile_target()->ball:
	if _bridge_missile_target_ref == null:
		return null
	var raw:Variant = _bridge_missile_target_ref.get_ref()
	if raw is ball and is_instance_valid(raw) and (raw as ball).health > 0:
		return raw as ball
	return null


func _setup_uluru_take_fire_player()->void:
	if _uluru_take_fire_player != null and is_instance_valid(_uluru_take_fire_player):
		return
	_uluru_take_fire_player = AudioStreamPlayer2D.new()
	_uluru_take_fire_player.name = "乌鲁鲁拿火音效"
	_uluru_take_fire_player.stream = ULURU_TAKE_FIRE_SFX
	_uluru_take_fire_player.volume_db = 4.0
	_uluru_take_fire_player.max_distance = 1200.0
	_uluru_take_fire_player.attenuation = 0.78
	_uluru_take_fire_player.max_polyphony = 1
	# 不设 top_level，让较长的“拿火”在人物移动期间跟随乌鲁鲁位置。
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_uluru_take_fire_player.bus = &"GameplayRecord"
	add_child(_uluru_take_fire_player)


func _start_uluru_take_fire_audio_local()->void:
	_setup_uluru_take_fire_player()
	if _uluru_take_fire_player != null and is_instance_valid(_uluru_take_fire_player):
		_uluru_take_fire_player.stop()
		_uluru_take_fire_player.position = Vector2.ZERO
		_uluru_take_fire_player.play()


func _stop_uluru_take_fire_audio_local()->void:
	if _uluru_take_fire_player != null and is_instance_valid(_uluru_take_fire_player):
		_uluru_take_fire_player.stop()


func _setup_uluru_missile_flight_player()->void:
	if _uluru_missile_flight_player != null and is_instance_valid(_uluru_missile_flight_player):
		return
	_uluru_missile_flight_player = AudioStreamPlayer2D.new()
	_uluru_missile_flight_player.name = "乌鲁鲁巡飞弹飞行循环"
	_uluru_missile_flight_player.top_level = true
	_uluru_missile_flight_player.max_distance = 2600.0
	_uluru_missile_flight_player.attenuation = 0.28
	_uluru_missile_flight_player.volume_db = 6.0
	_uluru_missile_flight_player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_uluru_missile_flight_player.bus = &"GameplayRecord"
	add_child(_uluru_missile_flight_player)


func _start_uluru_missile_audio(play_parent_line:bool)->void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_uluru_missile_audio_start_rpc.rpc(play_parent_line)
	else:
		_uluru_missile_audio_start_rpc(play_parent_line)


@rpc("authority","call_local","reliable")
func _uluru_missile_audio_start_rpc(play_parent_line:bool)->void:
	_setup_uluru_missile_flight_player()
	_stop_uluru_missile_flight_local()
	if _uluru_missile_flight_player != null and is_instance_valid(_uluru_missile_flight_player):
		var loop_stream:AudioStream = ULURU_MISSILE_FLIGHT_SFX.duplicate() as AudioStream
		# 这份“巡飞弹飞中”原音约7秒；仍显式设为循环，确保任何延长飞行都持续到爆炸。
		if loop_stream is AudioStreamMP3:
			(loop_stream as AudioStreamMP3).loop = true
			(loop_stream as AudioStreamMP3).loop_offset = 0.0
		_uluru_missile_flight_player.stream = loop_stream
		_uluru_missile_flight_player.global_position = global_position
		_uluru_missile_flight_player.play()
	if play_parent_line:
		_play_bridge_one_shot(ULURU_PARENT_LINE_SFX,global_position,4.0,1.0)


func _stop_uluru_missile_flight_local()->void:
	if _uluru_missile_flight_player != null and is_instance_valid(_uluru_missile_flight_player):
		_uluru_missile_flight_player.stop()


func update_uluru_missile_flight_audio_position(position_value:Vector2)->void:
	# 飞行循环声跟随巡飞弹本体，而不是停留在发射者身上。
	if _uluru_missile_flight_player != null and is_instance_valid(_uluru_missile_flight_player):
		_uluru_missile_flight_player.global_position = position_value


func play_uluru_missile_impact_feedback(position_value:Vector2)->void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_uluru_missile_impact_feedback_rpc.rpc(position_value)
	else:
		_uluru_missile_impact_feedback_rpc(position_value)


@rpc("authority","call_local","reliable")
func _uluru_missile_impact_feedback_rpc(position_value:Vector2)->void:
	_stop_uluru_missile_flight_local()
	_play_bridge_one_shot(ULURU_MISSILE_EXPLOSION_SFX,position_value,7.0,1.0)


func play_uluru_small_bomb_explosion_sfx(position_value:Vector2)->void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_uluru_small_bomb_explosion_sfx_rpc.rpc(position_value)
	else:
		_uluru_small_bomb_explosion_sfx_rpc(position_value)


@rpc("authority","call_local","reliable")
func _uluru_small_bomb_explosion_sfx_rpc(position_value:Vector2)->void:
	_play_bridge_one_shot(ULURU_SMALL_BOMB_EXPLOSION_SFX,position_value,6.0,randf_range(0.98,1.02))


func play_uluru_fire_land_sfx(position_value:Vector2)->void:
	if not is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		_uluru_fire_land_sfx_rpc.rpc(position_value)
	else:
		_uluru_fire_land_sfx_rpc(position_value)


@rpc("authority","call_local","reliable")
func _uluru_fire_land_sfx_rpc(position_value:Vector2)->void:
	_play_bridge_one_shot(ULURU_FIRE_LAND_SFX,position_value,2.0,1.0)


func on_battle_victory()->void:
	# World在真正完成胜负结算、触发胜利铃时调用，不靠“这一帧没敌人”猜胜利，避免轮换/复活间隙误笑。
	if not is_multiplayer_authority() or health <= 0 or _uluru_victory_laugh_played:
		return
	_uluru_victory_laugh_played = true
	if multiplayer.has_multiplayer_peer():
		_uluru_victory_laugh_rpc.rpc()
	else:
		_uluru_victory_laugh_rpc()


@rpc("authority","call_local","reliable")
func _uluru_victory_laugh_rpc()->void:
	_play_bridge_one_shot(ULURU_VICTORY_LAUGH_SFX,global_position,4.0,1.0)


func spawn_uluru_explosion_visual(position_value:Vector2,visual_diameter:float,variant:int)->void:
	# 只复用MC爆炸的三套帧动画，不创建魔角猎人的ExplosionAudio，因此不会叠加TNT音效。
	# 声音由巡飞弹爆炸/小炸弹爆炸各自的乌鲁鲁专属MP3负责。
	if not is_inside_tree() or ULURU_MC_EXPLOSION_FRAMES.is_empty():
		return
	var index:int = clampi(variant,1,ULURU_MC_EXPLOSION_FRAMES.size()) - 1
	var frames:SpriteFrames = ULURU_MC_EXPLOSION_FRAMES[index]
	if frames == null:
		return

	var holder:=Node2D.new()
	_uluru_explosion_serial += 1
	holder.name = "乌鲁鲁爆炸视觉_%d" % _uluru_explosion_serial
	holder.set_as_top_level(true)
	holder.z_as_relative = false
	holder.z_index = 99
	add_child(holder,true)
	holder.global_position = position_value

	var animation:=AnimatedSprite2D.new()
	animation.name = "ExplosionAnimation"
	animation.sprite_frames = frames
	animation.animation = &"explode"
	animation.frame = 0
	animation.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material:=CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	animation.material = material
	animation.scale = Vector2.ONE * (maxf(visual_diameter,16.0) / 256.0)
	animation.speed_scale = 1.35
	holder.add_child(animation)
	animation.play(&"explode")

	var frame_duration:float = float(frames.get_frame_count(&"explode")) / maxf(
		frames.get_animation_speed(&"explode") * animation.speed_scale,
		1.0
	)
	get_tree().create_timer(frame_duration + 0.10).timeout.connect(holder.queue_free,CONNECT_ONE_SHOT)


# 战争女神灼烧状态会寻找这个同名入口。堵桥直接复用同一份烫伤音效，
# 因此火圈刷新出的灼烧无需复制第二套状态/音频资源。
func play_war_burn_tick_sfx(position_value:Vector2)->void:
	if multiplayer.has_multiplayer_peer():
		_bridge_burn_tick_sfx_rpc.rpc(position_value)
	else:
		_bridge_burn_tick_sfx_rpc(position_value)


@rpc("authority","call_local","unreliable")
func _bridge_burn_tick_sfx_rpc(position_value:Vector2)->void:
	_play_bridge_one_shot(BRIDGE_BURN_SFX,position_value,1.0,randf_range(0.97,1.04))


func _play_bridge_one_shot(stream_value:AudioStream,position_value:Vector2,volume_db_value:float,pitch_value:float)->void:
	if stream_value == null or not is_inside_tree():
		return
	var player:=AudioStreamPlayer2D.new()
	_bridge_special_audio_serial += 1
	player.name = "BridgeSpecialSFX_%d" % _bridge_special_audio_serial
	player.top_level = true
	player.stream = stream_value
	player.volume_db = volume_db_value
	player.pitch_scale = maxf(pitch_value,0.05)
	player.max_distance = 1200.0
	player.attenuation = 0.78
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player,true)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _tick_bridge_skill(delta:float)->void:
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		if _bridge_phase != BRIDGE_PHASE_IDLE:
			_cancel_bridge_skill(false)
		return

	if not is_combat_runtime_active():
		# 暂停/未开战阶段不消耗技能冷却，也不让越界状态滞留。
		if _bridge_phase != BRIDGE_PHASE_IDLE:
			_cancel_bridge_skill(false)
		return

	if _bridge_phase == BRIDGE_PHASE_IDLE:
		_bridge_cooldown_left = maxf(_bridge_cooldown_left - delta,0.0)
		if _bridge_missile_active or _uluru_fire_prepare_active or _uluru_fire_recover_active:
			return
		if not is_player_controlled() and _bridge_cooldown_left <= 0.0001:
			var enemy:Node = return_reusable_combat_target()
			if enemy != null and is_instance_valid(enemy):
				_start_bridge_skill()
		return

	match _bridge_phase:
		BRIDGE_PHASE_RUN_OUT:
			var to_outside:Vector2 = _bridge_outside_target - global_position
			if to_outside.length() <= maxf(bridge_skill_arrive_distance,2.0):
				global_position = _bridge_outside_target
				direction = Vector2.ZERO
				velocity = Vector2.ZERO
				_bridge_phase = BRIDGE_PHASE_FIRE_OUTSIDE
				_bridge_phase_left = maxf(bridge_outside_fire_duration,0.5)
			else:
				direction = to_outside.normalized()

		BRIDGE_PHASE_FIRE_OUTSIDE:
			# V101：站在地图上方时可以自由左右游走。AI 会向当前敌人的 X 坐标靠近，
			# 因而敌人在左右换边时人物也会转向；PSG 枪口仍继续使用猛攻哥原本的缓慢瞄准逻辑。
			if not is_player_controlled():
				var enemy:Node = return_reusable_combat_target()
				if enemy != null and is_instance_valid(enemy) and enemy is Node2D:
					var map_rect:Rect2 = _bridge_map_rect()
					var desired_x:float = (enemy as Node2D).global_position.x
					if map_rect.size.x > 1.0:
						desired_x = clampf(desired_x,map_rect.position.x + 12.0,map_rect.end.x - 12.0)
					var dx:float = desired_x - global_position.x
					direction = Vector2(signf(dx),0.0) if absf(dx) > maxf(bridge_outside_horizontal_deadzone,2.0) else Vector2.ZERO
				else:
					direction = Vector2.ZERO
			_bridge_phase_left -= delta
			if _bridge_phase_left <= 0.0:
				_bridge_phase = BRIDGE_PHASE_RETURN
				# 从当前横向位置直接向下返回，不再斜着跑回技能开始时的位置。
				var return_rect:Rect2 = _bridge_map_rect()
				if return_rect.size.x > 1.0 and return_rect.size.y > 1.0:
					_bridge_return_target = Vector2(
						clampf(global_position.x,return_rect.position.x + 12.0,return_rect.end.x - 12.0),
						return_rect.position.y + bridge_return_inset
					)
				var to_return:Vector2 = _bridge_return_target - global_position
				direction = to_return.normalized() if to_return.length_squared() > 0.000001 else Vector2.ZERO

		BRIDGE_PHASE_RETURN:
			var to_inside:Vector2 = _bridge_return_target - global_position
			if to_inside.length() <= maxf(bridge_skill_arrive_distance,2.0):
				global_position = _bridge_return_target
				_finish_bridge_skill()
			else:
				direction = to_inside.normalized()


func _start_bridge_skill()->void:
	if _bridge_missile_active or _uluru_fire_prepare_active or _uluru_fire_recover_active or _bridge_phase != BRIDGE_PHASE_IDLE or health <= 0:
		return
	var enemy:Node = return_reusable_combat_target()
	if enemy == null or not is_instance_valid(enemy):
		return
	var map_rect:Rect2 = _bridge_map_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		_bridge_cooldown_left = 1.0
		return

	# V101：技能固定从地图上方出入。X 保持人物当前横向位置，不再选最近的左/右/下边界。
	var p:Vector2 = global_position
	var tangent_margin:float = 12.0
	var x_top:float = clampf(p.x,map_rect.position.x + tangent_margin,map_rect.end.x - tangent_margin)
	_bridge_outside_target = Vector2(x_top,map_rect.position.y - bridge_outside_gap)
	_bridge_return_target = Vector2(x_top,map_rect.position.y + bridge_return_inset)

	_bridge_begin_escape_collision_mode()
	_bridge_phase = BRIDGE_PHASE_RUN_OUT
	_bridge_phase_left = 0.0
	var to_outside:Vector2 = _bridge_outside_target - global_position
	direction = to_outside.normalized() if to_outside.length_squared() > 0.000001 else Vector2.ZERO


func _finish_bridge_skill()->void:
	_bridge_restore_escape_collision_mode()
	_bridge_phase = BRIDGE_PHASE_IDLE
	_bridge_phase_left = 0.0
	_bridge_cooldown_left = maxf(bridge_skill_cooldown,0.1)
	direction = Vector2.ZERO
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO


func _cancel_bridge_skill(start_cooldown:bool)->void:
	_bridge_restore_escape_collision_mode()
	_bridge_phase = BRIDGE_PHASE_IDLE
	_bridge_phase_left = 0.0
	if start_cooldown:
		_bridge_cooldown_left = maxf(bridge_skill_cooldown,0.1)
	direction = Vector2.ZERO
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO


func _bridge_begin_escape_collision_mode()->void:
	if _bridge_escape_snapshot_valid:
		return
	_bridge_escape_snapshot_valid = true
	_bridge_saved_body_mask_layer1 = get_collision_mask_value(1)
	_bridge_saved_body_mask_layer2 = get_collision_mask_value(2)
	_bridge_saved_body_layer2 = get_collision_layer_value(2)
	_bridge_saved_z_index = z_index

	# layer1 = 地图/安全框；layer2 = 普通角色身体。越界奔跑时都暂时不阻挡。
	set_collision_mask_value(1,false)
	set_collision_mask_value(2,false)
	set_collision_layer_value(2,false)
	set_meta(&"submission_allow_map_escape",true)
	# 地图外视觉裁切层是 z=90；技能角色临时放到其上、黑色地图边线(z=100)之下。
	z_index = 95


func _bridge_restore_escape_collision_mode()->void:
	if not _bridge_escape_snapshot_valid:
		if has_meta(&"submission_allow_map_escape"):
			remove_meta(&"submission_allow_map_escape")
		return
	set_collision_mask_value(1,_bridge_saved_body_mask_layer1)
	set_collision_mask_value(2,_bridge_saved_body_mask_layer2)
	set_collision_layer_value(2,_bridge_saved_body_layer2)
	z_index = _bridge_saved_z_index
	_bridge_escape_snapshot_valid = false
	if has_meta(&"submission_allow_map_escape"):
		remove_meta(&"submission_allow_map_escape")


func _bridge_map_rect()->Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var maps:Variant = world.get("map_group")
	var map_name:Variant = world.get("now_choose_map")
	if not maps is Dictionary:
		return Rect2()
	var map_dict:Dictionary = maps as Dictionary
	var key:String = str(map_name)
	if not map_dict.has(key):
		return Rect2()
	var map_node:Variant = map_dict[key]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.call("return_map_world_rect",map_node) as Rect2


# 基类 hardcode 了普通“子弹.tscn”；堵桥只改实例化这一点，其余 PSG 伤害、枪口、音频、弹匣逻辑保持一致。
func _fire_berserker_weapon(item_index:int,aim:Vector2)->void:
	if item_index < 0 or item_index >= _berserker_items.size():
		return
	var weapon:Dictionary = _berserker_items[item_index]
	var mag_current:int = int(weapon.get("mag_current",0))
	if mag_current <= 0:
		return

	var spread:float = deg_to_rad(maxf(float(weapon.get("spread_deg",0.0)),0.0))
	var shot_dir:Vector2 = aim.rotated(_rng.randf_range(-spread,spread)).normalized()
	var projectile := BRIDGE_PSG_BULLET_SCENE.instantiate() as ball
	if projectile == null:
		return
	projectile.set_collision_layer_value(2,false)
	projectile.Master = self
	projectile.Master_name = self.name
	projectile.Team = Team
	projectile.Speed = maxf(float(weapon.get("projectile_speed",500.0)),80.0)

	var base_character_damage:float = maxf(float(Damage),1.0)
	var weapon_damage:float = maxf(float(weapon.get("damage",Damage)),0.0)
	projectile.Damage = maxi(int(round(attack_damage(weapon_damage / base_character_damage))),0)

	# 只有从技能的地图外站位射出的子弹需要穿过边界。
	if _bridge_phase == BRIDGE_PHASE_FIRE_OUTSIDE:
		projectile.set_meta(&"bridge_pass_map_boundary",true)

	_update_berserker_equipment_visual_transform()
	projectile.global_position = _berserker_gun_muzzle_global_position(shot_dir)
	projectile.global_rotation = projectile.Default_Rotation + shot_dir.angle()
	projectile.direction = shot_dir
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)

	weapon["mag_current"] = mag_current - 1
	_berserker_items[item_index] = weapon
	_trigger_berserker_weapon_audio(weapon)

	if int(weapon.get("mag_current",0)) <= 0:
		_handle_empty_berserker_weapon()
	else:
		_sync_berserker_runtime_inventory()


func Die()->void:
	_bridge_missile_active = false
	_bridge_missile_target_ref = null
	_stop_uluru_missile_flight_local()
	_hide_uluru_launcher_visual()
	_cancel_uluru_fire_prepare_local()
	Using_Skill = false
	_cancel_bridge_skill(false)
	super.Die()


func _exit_tree()->void:
	_bridge_missile_active = false
	_bridge_missile_target_ref = null
	_stop_uluru_missile_flight_local()
	_hide_uluru_launcher_visual()
	_cancel_uluru_fire_prepare_local()
	_bridge_restore_escape_collision_mode()
	super._exit_tree()
