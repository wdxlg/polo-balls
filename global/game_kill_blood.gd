extends RefCounted
## 通用击杀血液视觉与大奖红闪（非 RPC 部分）
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node


func _init(game: Node) -> void:
	_game = game


const KILL_BLOOD_SCRIPT:Script = preload("res://scripts/effects/若叶睦_击杀血液.gd")

# V39：批量击杀时，通用击杀血的玩法结算仍立即完成，但视觉实例分帧创建，避免同一帧几十/上百个节点分配造成卡顿。
const KILL_BLOOD_VISUAL_SPAWN_BUDGET_PER_FRAME:int = 2

const BLOOD_JACKPOT_AUDIO:AudioStream = preload("res://audio/system/血液爆炸.mp3")

var _pending_kill_blood_visuals:Array[Dictionary] = []

var _kill_blood_visual_drain_running:bool = false


# V96：掷骰子点数7与占卜师“四命运之轮”共用的全局大奖反馈。
# 这里只负责本机视觉/声音；调用者本身已有 call_local RPC，因此不会二次广播。
func play_blood_jackpot_flash_local() -> void:
	var scene_root:Node = _game.get_tree().current_scene
	if scene_root == null or not is_instance_valid(scene_root):
		return

	var flash_layer := CanvasLayer.new()
	flash_layer.name = "BloodJackpotFlash"
	flash_layer.layer = 190
	scene_root.add_child(flash_layer)

	var flash := ColorRect.new()
	flash.name = "RedFlash"
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.position = Vector2.ZERO
	flash.size = _game.get_viewport_rect().size
	flash.color = Color(0.92,0.0,0.025,0.0)
	flash_layer.add_child(flash)

	var flash_tween:Tween = flash.create_tween()
	flash_tween.tween_property(flash,"color:a",0.48,0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(flash,"color:a",0.0,0.19).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flash_tween.finished.connect(flash_layer.queue_free)

	var player := AudioStreamPlayer.new()
	player.name = "BloodJackpotAudio"
	player.stream = BLOOD_JACKPOT_AUDIO
	player.volume_db = 9.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	scene_root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func is_global_blood_effects_enabled() -> bool:
	return bool(_game.Game_Settings.get("Blood_Effects", false))


func _should_spawn_global_kill_blood(victim:Node, killer:Node) -> bool:
	if not is_global_blood_effects_enabled():
		return false
	if victim == null or killer == null or not is_instance_valid(victim) or not is_instance_valid(killer):
		return false
	if not (victim is Node2D) or not (killer is Node2D):
		return false

	# V262：全局“血液”开关只允许真正角色死亡生成击杀血。
	# ball 的 Shooter / Shooter_with_Health / Creature 也会进入 State.Die；
	# 高频投射物在互相碰撞、被攻击或正常销毁时，绝不能被当作“人物死亡”喷出通用击杀血。
	if not (victim is ball):
		return false
	var victim_ball:ball = victim as ball
	if victim_ball.Type != ball.Ball_Type.Ball:
		return false

	# 若叶睦/墨提斯的拳头或吉他已经按武器力度生成专属血液时，禁止再叠一层通用血。
	if bool(victim.get_meta("_wakaba_specific_kill_blood_spawned", false)):
		return false
	return true


func _capture_kill_blood_context(source:Node,target:Node,damage:float,health_before:float) -> void:
	# 在 Master 归因之前保存真实命中物的运动；只在已确认掉血后调用。
	var context:Dictionary = {"kind":"generic","speed":180.0,"damage":damage,"reference_health":health_before}
	if source is Node2D and target is Node2D:
		context["direction"] = ((target as Node2D).global_position - (source as Node2D).global_position).normalized()
	var motion:Vector2 = source.velocity if source is CharacterBody2D else Vector2.ZERO
	var explicit_motion:Variant = source.get_meta("blood_attack_velocity",motion)
	if explicit_motion is Vector2: motion = explicit_motion
	if motion.is_finite() and motion.length_squared() > 1.0:
		context["speed"] = minf(motion.length(),1600.0)
		if source.has_method("_is_projectile_motion_object") and bool(source.call("_is_projectile_motion_object")):
			context["kind"] = "pierce"
			context["direction"] = motion.normalized()
	var explicit_kind:String = str(source.get_meta("blood_damage_kind",""))
	if explicit_kind in ["pierce","slash","crush","blast","burn"]:
		context["kind"] = explicit_kind
		if explicit_kind == "pierce" and motion.length_squared() > 1.0:
			context["direction"] = motion.normalized()
	if str(target.get_meta("_blood_damage_element","")) == "fire":
		context["kind"] = "burn"
	target.set_meta("_kill_blood_context",context)


func _spawn_global_kill_blood(victim:Node, killer:Node) -> void:
	if not _should_spawn_global_kill_blood(victim,killer):
		return
	var victim_2d:Node2D = victim as Node2D
	var killer_2d:Node2D = killer as Node2D
	var direction_value:Vector2 = victim_2d.global_position - killer_2d.global_position
	if direction_value.length_squared() <= 0.000001:
		direction_value = Vector2.RIGHT
	else:
		direction_value = direction_value.normalized()
	var seed_value:int = int(randi())
	var context:Dictionary = victim.get_meta("_kill_blood_context",{})
	if _game.multiplayer.has_multiplayer_peer():
		_game._rpc_spawn_global_kill_blood.rpc(victim_2d.global_position,direction_value,seed_value,context)
	else:
		_game._rpc_spawn_global_kill_blood(victim_2d.global_position,direction_value,seed_value,context)


func _drain_kill_blood_visual_queue() -> void:
	if _kill_blood_visual_drain_running or not _game.is_inside_tree():
		return
	_kill_blood_visual_drain_running = true
	while _game.is_inside_tree() and not _pending_kill_blood_visuals.is_empty():
		var budget:int = maxi(KILL_BLOOD_VISUAL_SPAWN_BUDGET_PER_FRAME,1)
		while budget > 0 and not _pending_kill_blood_visuals.is_empty():
			var request:Dictionary = _pending_kill_blood_visuals.pop_front()
			_spawn_global_kill_blood_visual_now(
				request.get("origin",Vector2.ZERO),
				request.get("direction",Vector2.RIGHT),
				int(request.get("seed",0)),
				request.get("context",{})
			)
			budget -= 1
		if not _pending_kill_blood_visuals.is_empty():
			await _game.get_tree().process_frame
	_kill_blood_visual_drain_running = false


func _spawn_global_kill_blood_visual_now(origin:Vector2,base_direction:Vector2,seed_value:int,context:Dictionary = {}) -> void:
	if not _game.is_inside_tree():
		return
	var scene_root:Node = _game.get_tree().current_scene
	if scene_root == null:
		return
	var effect:Node2D = KILL_BLOOD_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "GlobalKillBloodBurst"
	scene_root.add_child(effect)
	# 通用人物击杀使用中等力度。若叶睦拳头/吉他会走角色自己的两个专属 profile。
	# V430 性能：大规模战斗时按 World 视觉密度减少血液粒子数量（7 -> 最低 3），人数回落自动恢复。
	var projectile_count:int = 7
	if scene_root.has_method("get_large_battle_visual_density"):
		var density:float = clampf(float(scene_root.call("get_large_battle_visual_density")),0.15,1.0)
		projectile_count = maxi(int(ceil(7.0 * density)),3)
	effect.call("configure",origin,base_direction,2,seed_value,projectile_count,10.0,220.0,context)
