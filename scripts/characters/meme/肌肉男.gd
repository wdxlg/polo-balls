extends ball

# 肌肉男：独立手臂持续绕身体旋转并不断加速；只有真正命中角色才停。
# 旋转越快，伤害越高、目标击退越强、手臂反向回弹角度越大，旋转音越大。短暂停顿后重新从最低转速开始。
# 旋转音不是资源 Loop：每段在“真实音频长度 - 0.33 秒”时启动下一段，双播放器交替重叠。
const SFX_SPIN:AudioStream = preload("res://audio/characters/meme/肌肉男/旋转.mp3")

@export_category("肌肉男 - 旋转拳")
@export_range(40.0,220.0,1.0) var orbit_radius:float = 82.0
@export_range(0.2,30.0,0.1) var start_angular_speed:float = 6.5
@export_range(0.1,30.0,0.1) var angular_acceleration:float = 6.0
@export_range(1.0,40.0,0.1) var max_angular_speed:float = 28.0
# Damage（攻击力）就是最低转速拳伤；这里只保留高速时相对基础攻击力的倍率。
@export_range(1.0,10.0,0.05) var max_spin_damage_multiplier:float = 4.6666667
@export_range(0.0,700.0,5.0) var min_knockback_distance:float = 45.0
@export_range(0.0,1000.0,5.0) var max_knockback_distance:float = 180.0
@export_range(100.0,2500.0,10.0) var min_knockback_speed:float = 520.0
@export_range(100.0,3500.0,10.0) var max_knockback_speed:float = 1050.0
@export_range(0.05,2.0,0.05) var hit_stop_duration:float = 0.55

@export_category("肌肉男 - 手臂命中回弹")
@export_range(0.0,90.0,1.0) var min_hand_recoil_degrees:float = 12.0
@export_range(0.0,120.0,1.0) var max_hand_recoil_degrees:float = 52.0
@export_range(30.0,360.0,5.0) var hand_recoil_recovery_degrees_per_second:float = 150.0
@export_range(0.5,2.0,0.05) var hand_recoil_speed_curve:float = 1.10

@export_category("肌肉男 - 手臂随速度变大")
@export_range(0.50,2.00,0.01) var arm_visual_min_scale_multiplier:float = 1.00
@export_range(1.00,2.50,0.01) var arm_visual_max_scale_multiplier:float = 1.65
@export_range(1.00,2.00,0.01) var fist_hitbox_max_radius_multiplier:float = 1.42
@export_range(0.1,10.0,0.1) var arm_scale_growth_speed:float = 5.0
@export_range(0.1,5.0,0.1) var arm_scale_recovery_speed:float = 1.25

@export_category("肌肉男 - 旋转音效")
@export_range(0.0,1.0,0.01) var spin_audio_overlap_seconds:float = 0.33
@export_range(-80.0,-20.0,1.0) var spin_audio_min_volume_db:float = -48.0
@export_range(-12.0,12.0,0.5) var spin_audio_max_volume_db:float = 3.0
@export_range(100.0,3000.0,50.0) var spin_audio_max_distance:float = 1300.0

@onready var orbit_fist_hitbox:hitbox = $OrbitFistHitbox
@onready var orbit_fist_shape:CollisionShape2D = $OrbitFistHitbox/CollisionShape2D
@onready var arm_visual:Sprite2D = $OrbitFistHitbox/ArmVisual
@onready var spin_audio_a:AudioStreamPlayer2D = $SpinAudioA
@onready var spin_audio_b:AudioStreamPlayer2D = $SpinAudioB

var _orbit_angle:float = 0.0
var _angular_speed:float = 0.0
var _spinning:bool = true
var _hit_stop_left:float = 0.0
var _spin_audio_next_in:float = 0.0
var _spin_audio_sequence_active:bool = false
var _spin_audio_use_a:bool = true
var _base_arm_visual_scale:Vector2 = Vector2.ONE
var _base_fist_radius:float = 22.0
var _displayed_visual_ratio:float = 0.0
var _hand_recoil_angle:float = 0.0


func _ready() -> void:
    Has_Collision_Damage = false
    Can_Attack = false
    Can_Skill = false
    Health_Restore = 0
    super._ready()

    _angular_speed = maxf(start_angular_speed,0.01)
    orbit_fist_hitbox.collision_layer = 0
    orbit_fist_hitbox.collision_mask = 2
    orbit_fist_hitbox.monitoring = false
    orbit_fist_hitbox.monitorable = false
    orbit_fist_shape.disabled = true
    _prepare_runtime_fist_shape()
    _base_arm_visual_scale = arm_visual.scale if arm_visual != null else Vector2.ONE
    _configure_spin_audio_player(spin_audio_a)
    _configure_spin_audio_player(spin_audio_b)
    _sync_fist_transform()
    _apply_fist_scale_ratio(0.0)
    _sync_spin_damage()
    if is_multiplayer_authority():
        _begin_spin_audio_schedule()


func tick_physics(state:State,delta:float) -> void:
    super.tick_physics(state,delta)
    if not is_multiplayer_authority():
        return
    if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
        _set_spin_hitbox_active(false)
        _stop_spin_audio_everywhere()
        return
    if not is_combat_runtime_active() or is_damage_output_disabled():
        _set_spin_hitbox_active(false)
        _stop_spin_audio_everywhere()
        return

    if not _spinning:
        _stop_spin_audio_everywhere()
        _hit_stop_left -= delta
        # 命中停转时：手臂从反向弹开的角度缓缓回到正常轨道；
        # 已经随高速变大的手臂也缓缓缩回，而不是重启旋转时瞬间缩小。
        _hand_recoil_angle = move_toward(
            _hand_recoil_angle,
            0.0,
            deg_to_rad(maxf(hand_recoil_recovery_degrees_per_second,1.0)) * delta
        )
        _displayed_visual_ratio = move_toward(
            _displayed_visual_ratio,
            0.0,
            maxf(arm_scale_recovery_speed,0.01) * delta
        )
        _sync_fist_transform()
        _apply_fist_scale_ratio(_displayed_visual_ratio)
        if _hit_stop_left <= 0.0:
            _restart_spin()
        return

    _set_spin_hitbox_active(true)
    _angular_speed = minf(
        maxf(_angular_speed + angular_acceleration * delta,start_angular_speed),
        maxf(max_angular_speed,start_angular_speed)
    )
    _orbit_angle = fposmod(_orbit_angle + _angular_speed * delta,TAU)
    _hand_recoil_angle = move_toward(
        _hand_recoil_angle,
        0.0,
        deg_to_rad(maxf(hand_recoil_recovery_degrees_per_second,1.0)) * delta
    )
    _sync_fist_transform()
    var target_visual_ratio:float = pow(_spin_ratio(),0.72)
    var scale_follow_speed:float = arm_scale_growth_speed if target_visual_ratio >= _displayed_visual_ratio else arm_scale_recovery_speed
    _displayed_visual_ratio = move_toward(
        _displayed_visual_ratio,
        target_visual_ratio,
        maxf(scale_follow_speed,0.01) * delta
    )
    _apply_fist_scale_ratio(_displayed_visual_ratio)
    _sync_spin_damage()
    _update_spin_audio_schedule(delta)


func _spin_ratio() -> float:
    var min_speed:float = maxf(start_angular_speed,0.01)
    var max_speed:float = maxf(max_angular_speed,min_speed + 0.01)
    return clampf((_angular_speed - min_speed) / (max_speed - min_speed),0.0,1.0)


func current_hit_damage_multiplier() -> float:
    # V107：Damage 始终保持最低转速基础拳伤；转速只改变倍率，不再覆写攻击力。
    return lerpf(1.0,maxf(max_spin_damage_multiplier,1.0),_spin_ratio())


func _sync_spin_damage() -> void:
    if _spinning and orbit_fist_hitbox.monitoring:
        orbit_fist_hitbox.set_meta("threat_debug_damage",attack_damage(current_hit_damage_multiplier()))
    elif orbit_fist_hitbox.has_meta("threat_debug_damage"):
        orbit_fist_hitbox.remove_meta("threat_debug_damage")


func _prepare_runtime_fist_shape() -> void:
    if orbit_fist_shape == null or orbit_fist_shape.shape == null:
        return
    var runtime_shape:Shape2D = orbit_fist_shape.shape.duplicate() as Shape2D
    if runtime_shape != null:
        orbit_fist_shape.shape = runtime_shape
    var circle:CircleShape2D = orbit_fist_shape.shape as CircleShape2D
    if circle != null:
        _base_fist_radius = maxf(circle.radius,1.0)


func _sync_fist_transform() -> void:
    # _hand_recoil_angle 只影响手臂/拳头本身；身体位置完全不动。
    # 当前旋转方向是正角度，因此命中时写入负角度就是沿旋转反方向弹开。
    var display_angle:float = _orbit_angle + _hand_recoil_angle
    orbit_fist_hitbox.position = Vector2.RIGHT.rotated(display_angle) * orbit_radius
    orbit_fist_hitbox.rotation = display_angle


func _apply_fist_scale_ratio(visual_ratio:float) -> void:
    # 用持久的显示倍率驱动视觉和真实拳头半径。命中后该倍率在停转阶段逐帧恢复，
    # 不直接缩放 CollisionShape2D 节点本身。
    var safe_ratio:float = clampf(visual_ratio,0.0,1.0)
    var min_visual:float = maxf(arm_visual_min_scale_multiplier,0.01)
    var max_visual:float = maxf(arm_visual_max_scale_multiplier,min_visual)
    if arm_visual != null:
        arm_visual.scale = _base_arm_visual_scale * lerpf(min_visual,max_visual,safe_ratio)
    var circle:CircleShape2D = orbit_fist_shape.shape as CircleShape2D
    if circle != null:
        circle.radius = _base_fist_radius * lerpf(1.0,maxf(fist_hitbox_max_radius_multiplier,1.0),safe_ratio)


func _on_orbit_fist_on_hit(hurt:hurtbox) -> void:
    if not is_multiplayer_authority() or not _spinning:
        return
    if not is_combat_runtime_active() or is_damage_output_disabled():
        return
    if hurt == null or not is_instance_valid(hurt):
        return
    var target_node:Node = hurt.get_parent()
    if not target_node is ball:
        target_node = hurt.owner
    if not target_node is ball:
        return
    var target:ball = target_node as ball
    if target == self or target.health <= 0:
        return

    var ratio:float = _spin_ratio()
    var push_direction:Vector2 = target.global_position - global_position
    if push_direction.length_squared() <= 0.000001:
        # 完全重叠时用手臂当前所在的径向方向。
        push_direction = Vector2.RIGHT.rotated(_orbit_angle)

    var knockback_distance:float = lerpf(min_knockback_distance,max_knockback_distance,ratio)
    var knockback_speed:float = lerpf(min_knockback_speed,max_knockback_speed,ratio)
    target.apply_knockback(
        push_direction.normalized(),
        knockback_distance,
        knockback_speed,
        0.08,
        0.0,
        {"source":self,"max_wall_bounces":1,"stop_on_character":true}
    )

    # 命中回弹只作用于手臂：按当前转速，把拳头沿“旋转反方向”瞬间弹开一个角度。
    # 转得越快，弹开的角度越大；身体本身不再受到任何自我击退。
    var recoil_ratio:float = pow(ratio,maxf(hand_recoil_speed_curve,0.01))
    var recoil_degrees:float = lerpf(min_hand_recoil_degrees,max_hand_recoil_degrees,recoil_ratio)
    _hand_recoil_angle = -deg_to_rad(maxf(recoil_degrees,0.0))
    _sync_fist_transform()

    _spinning = false
    _hit_stop_left = maxf(hit_stop_duration,0.05)
    _set_spin_hitbox_active(false)
    _stop_spin_audio_everywhere()


func _restart_spin() -> void:
    _spinning = true
    _angular_speed = maxf(start_angular_speed,0.01)
    _set_spin_hitbox_active(true)
    # 不在这里强制把手臂缩回基础尺寸；残余放大量由 tick_physics 继续平滑恢复/跟随。
    _sync_fist_transform()
    _sync_spin_damage()
    _begin_spin_audio_schedule()


func _set_spin_hitbox_active(active:bool) -> void:
    var should_enable:bool = active and _spinning
    orbit_fist_shape.set_deferred("disabled",not should_enable)
    orbit_fist_hitbox.set_deferred("monitoring",should_enable)
    if not should_enable and orbit_fist_hitbox.has_meta("threat_debug_damage"):
        orbit_fist_hitbox.remove_meta("threat_debug_damage")


func _configure_spin_audio_player(player:AudioStreamPlayer2D) -> void:
    if player == null:
        return
    player.stream = SFX_SPIN
    player.volume_db = -80.0
    player.max_distance = maxf(spin_audio_max_distance,100.0)
    player.attenuation = 1.0
    player.pitch_scale = 1.0
    player.process_mode = Node.PROCESS_MODE_ALWAYS
    if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
        player.bus = &"GameplayRecord"


func _spin_segment_interval() -> float:
    if SFX_SPIN == null:
        return 0.25
    var stream_length:float = SFX_SPIN.get_length()
    if stream_length <= 0.0:
        stream_length = 1.25
    return maxf(stream_length - clampf(spin_audio_overlap_seconds,0.0,stream_length - 0.02),0.05)


func _begin_spin_audio_schedule() -> void:
    if not is_multiplayer_authority() or not _spinning:
        return
    _spin_audio_sequence_active = true
    _spin_audio_next_in = 0.0


func _update_spin_audio_schedule(delta:float) -> void:
    if not _spin_audio_sequence_active:
        _begin_spin_audio_schedule()
    _spin_audio_next_in -= delta
    if _spin_audio_next_in > 0.0:
        return
    var volume_value:float = lerpf(
        spin_audio_min_volume_db,
        spin_audio_max_volume_db,
        _spin_ratio()
    )
    _play_spin_segment_everywhere(volume_value)
    _spin_audio_next_in += _spin_segment_interval()
    if _spin_audio_next_in <= 0.0:
        _spin_audio_next_in = _spin_segment_interval()


func _play_spin_segment_everywhere(volume_db_value:float) -> void:
    if multiplayer.has_multiplayer_peer():
        _rpc_play_spin_segment.rpc(volume_db_value)
    else:
        _rpc_play_spin_segment(volume_db_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_spin_segment(volume_db_value:float) -> void:
    var player:AudioStreamPlayer2D = spin_audio_a if _spin_audio_use_a else spin_audio_b
    _spin_audio_use_a = not _spin_audio_use_a
    if player == null or SFX_SPIN == null:
        return
    player.stream = SFX_SPIN
    player.volume_db = clampf(volume_db_value,-80.0,12.0)
    # A/B 交替，因此下一段能在上一段结束前 0.33 秒开始，而不会重启上一段。
    player.stop()
    player.play()


func _stop_spin_audio_everywhere() -> void:
    if not _spin_audio_sequence_active:
        return
    _spin_audio_sequence_active = false
    _spin_audio_next_in = 0.0
    if multiplayer.has_multiplayer_peer():
        _rpc_stop_spin_audio.rpc()
    else:
        _rpc_stop_spin_audio()


@rpc("authority","call_local","unreliable")
func _rpc_stop_spin_audio() -> void:
    if spin_audio_a != null:
        spin_audio_a.stop()
        spin_audio_a.volume_db = -80.0
    if spin_audio_b != null:
        spin_audio_b.stop()
        spin_audio_b.volume_db = -80.0
