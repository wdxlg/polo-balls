extends Node2D

# Sans 龙骨炮（Gaster Blaster，V408 音量修正；视觉/伤害主体沿用 V168）：
# - V50：允许“大风车”传入短于普通龙骨炮的演出时长；仅短时参数走 rapid 分支，普通龙骨炮时序完全保持原样。
# - V51：新增独立炮体宽度倍率；大风车保持正常高度/长度，只把本体局部 X 压窄，避免等比缩成小炮。
# - V52：曾允许大风车把激光截在瞄准点。
# - V53：大风车恢复完整贯穿激光；地图中心只负责给出发射方向，安全走廊改由 Sans 生成角度同时避开一对相对扇区。
# - V57：新增可选“完全出现后待发延迟”。普通龙骨炮默认 0；大风车先完整出现并短暂停住，再开始发射，以新旧炮开火时序自然形成旋转缺口。
# - V408：出现/开火音效提高基础响度并减弱 2D 距离衰减，修复龙骨炮位于地图外时声音整体偏小。
# - V168：淡出阶段整根激光保持直线，但整体宽度逐渐收窄到 0，同时透明度一起下降；不是尾端收尖。
# - V168：直接接触伤害每两个 physics tick 结算一次，伤害频率降为原来的一半；单次仍固定 1 点。
# - 从地图/屏幕外侧飞到地图边缘外；
# - 固定瞄准攻击开始时的目标点；
# - 播放前 4 帧蓄力，第 4 帧开始出白色激光；
# - 开火阶段循环第 5、6 帧；
# - 后坐力沿激光反方向把炮推出视野；
# - 激光是等宽直线，一直延伸到窗口外；屏幕内永远看不到激光尾端。
# - 激光接触按物理帧 1 伤害，并施加 KARMA。
# V149：龙骨炮本体和激光必须允许显示在地图外；World 的地图外视觉遮罩 z=90，
# V150：修正龙骨炮六帧 Atlas 裁切，并配合重新抠图后的完整黑色细节。
# V151：取消地图外“变细尾巴”；激光全程等宽并延长到当前窗口外。
# V152：炮体尺寸每次随机；激光宽度跟随炮体宽度；炮口起点向嘴内收。
# V156：出现时长直接贴“龙骨炮出现”原音频，只有小幅随机；攻击总时长直接贴“龙骨炮射”原音频，
#       并由炮体宽度决定倍率——越宽，激光持续/后坐退出越久。音频只做与该实际时长一致的小幅变速。
# 因此整套龙骨炮固定放到 z=95（血条 99 / 地图黑边 100 之下），不再被地图外遮罩盖掉。

const SANS_ATLAS:Texture2D = preload("res://Images/characters/传说之下/Sans/Sans_spritesheet.png")
const GASTER_FRAME_WIDTH_PX:float = 43.0
const GASTER_MOUTH_OFFSET_PX:float = 15.5
const SFX_APPEAR:AudioStream = preload("res://audio/characters/传说之下/Sans/龙骨炮出现.ogg")
const SFX_FIRE:AudioStream = preload("res://audio/characters/传说之下/Sans/龙骨炮射.ogg")
# V150：原图 6 帧龙骨炮的实际像素区域均为 43x57，横向步长 48。
# V148/V149 第 2~5 帧宽度/起点写错，会把炮体侧面直接裁掉。
const GASTER_REGIONS = [
	Rect2(5,861,43,57),
	Rect2(53,861,43,57),
	Rect2(101,861,43,57),
	Rect2(149,861,43,57),
	Rect2(197,861,43,57),
	Rect2(245,861,43,57),
]

var source:ball = null
var source_team:String = ""
var map_rect:Rect2 = Rect2()
var spawn_position:Vector2 = Vector2.ZERO
var park_position:Vector2 = Vector2.ZERO
var aim_point:Vector2 = Vector2.ZERO
var aim_direction:Vector2 = Vector2.RIGHT

var appearance_duration:float = 1.04
var attack_total_duration:float = 1.74
var fly_duration:float = 0.60
var frame_duration:float = 0.145
var fire_duration:float = 1.30
var fade_duration:float = 0.28
var recoil_distance:float = 170.0
var sprite_scale:float = 1.22
var sprite_width_scale:float = 1.0
var beam_width_ratio:float = 0.42
var beam_width:float = 22.0
var beam_stop_at_target:bool = false
var pre_fire_hold_duration:float = 0.0
var first_contact_karma:float = 10.0
var held_contact_karma:float = 1.0

var _sprite:Sprite2D = null
var _phase:int = 0 # 0 fly, 1 charge, 2 fire, 3 fade
var _elapsed:float = 0.0
var _beam_alpha:float = 0.0
var _beam_width_scale:float = 1.0
var _damage_tick_toggle:bool = false
var _beam_enabled:bool = false
var _contact_started:Dictionary = {}
var _last_frame_index:int = -1
var _appear_audio:AudioStreamPlayer2D = null
var _fire_audio:AudioStreamPlayer2D = null
var _fire_audio_started:bool = false


func configure(
	actor:ball,
	spawn_pos:Vector2,
	park_pos:Vector2,
	target_pos:Vector2,
	battle_rect:Rect2,
	appearance_time:float = 1.04,
	attack_time:float = 1.74,
	size_scale:float = 1.22,
	laser_width_ratio:float = 0.42,
	karma_first:float = 10.0,
	karma_held:float = 1.0,
	body_width_scale:float = 1.0,
	stop_at_target:bool = false,
	prefire_delay:float = 0.0
) -> void:
	# World 会用 z=90 的 MapOutsideVisualMask 覆盖普通战斗对象在地图外的部分。
	# 龙骨炮设计上本来就停在地图外，并且激光也要越过地图边界后继续延伸到窗口外，
	# 所以这里让整套效果高于遮罩、低于血条和地图黑边。
	z_as_relative = false
	z_index = 95
	source = actor
	source_team = actor.Team if actor != null else ""
	spawn_position = spawn_pos
	park_position = park_pos
	aim_point = target_pos
	map_rect = battle_rect.abs()
	# V50：大风车使用很短的 appearance/attack 参数。只有参数明确短于普通炮时才走 rapid 分支，
	# 普通龙骨炮继续保持 V156/V168 的音频贴合时序。
	var rapid_mode:bool = appearance_time < 0.30 or attack_time < 0.50
	if rapid_mode:
		appearance_duration = maxf(appearance_time,0.10)
		attack_total_duration = maxf(attack_time,0.18)
		fly_duration = maxf(appearance_duration * 0.46,0.035)
		frame_duration = maxf((appearance_duration - fly_duration) / 3.0,0.015)
		fade_duration = clampf(attack_total_duration * 0.22,0.045,0.10)
		fire_duration = maxf(attack_total_duration - frame_duration - fade_duration,0.05)
		attack_total_duration = frame_duration + fire_duration + fade_duration
	else:
		appearance_duration = maxf(appearance_time,0.30)
		attack_total_duration = maxf(attack_time,0.50)

		# 第 4 帧一出现就开火，所以“生成→开火”由：飞入 + 前 3 个完整帧组成。
		# 这里让飞入约占 58%，剩余时间平均给 0/1/2 三个预备帧。
		fly_duration = maxf(appearance_duration * 0.58,0.08)
		frame_duration = maxf((appearance_duration - fly_duration) / 3.0,0.035)

		# “开火→完全消失”必须严格落在 attack_total_duration：
		# 第 4 帧余下 1 个 frame_duration + 5/6 循环阶段 + 淡出退出。
		fade_duration = clampf(attack_total_duration * 0.16,0.16,0.34)
		fire_duration = maxf(attack_total_duration - frame_duration - fade_duration,0.12)
		# 极端 Inspector 值下，如果最小值钳制造成超时，则让记录值跟真实阶段和一致。
		attack_total_duration = frame_duration + fire_duration + fade_duration
	sprite_scale = clampf(size_scale,0.30,2.50)
	sprite_width_scale = clampf(body_width_scale,0.20,1.50)
	beam_width_ratio = clampf(laser_width_ratio,0.08,0.80)
	beam_width = maxf(GASTER_FRAME_WIDTH_PX * sprite_scale * beam_width_ratio,2.0)
	beam_stop_at_target = stop_at_target
	pre_fire_hold_duration = maxf(prefire_delay,0.0)
	first_contact_karma = maxf(karma_first,0.0)
	held_contact_karma = maxf(karma_held,0.0)
	global_position = spawn_position
	aim_direction = aim_point - park_position
	if aim_direction.length_squared() <= 0.000001:
		aim_direction = Vector2.RIGHT
	aim_direction = aim_direction.normalized()
	_build_sprite()
	_build_audio()
	_set_frame(0)
	_play_appear_audio()
	queue_redraw()


func _build_audio() -> void:
	_appear_audio = AudioStreamPlayer2D.new()
	_appear_audio.name = "GasterAppearAudio"
	_appear_audio.stream = SFX_APPEAR
	# V408：龙骨炮长期停在地图外，默认 2D 距离衰减会让出现声在实机里明显偏小。
	# 保留左右空间感，但提高基础响度并把距离衰减改缓。
	_appear_audio.volume_db = 3.0
	_appear_audio.attenuation = 0.35
	_appear_audio.max_distance = 3600.0
	add_child(_appear_audio)

	_fire_audio = AudioStreamPlayer2D.new()
	_fire_audio.name = "GasterFireAudio"
	_fire_audio.stream = SFX_FIRE
	# 开火声略高于出现声；多炮同时开火时仍保留 AudioStreamPlayer2D 的空间衰减，避免完全叠成无定位爆音。
	_fire_audio.volume_db = 4.5
	_fire_audio.attenuation = 0.35
	_fire_audio.max_distance = 4000.0
	add_child(_fire_audio)


func _pitch_for_target_duration(stream:AudioStream,target_duration:float) -> float:
	if stream == null:
		return 1.0
	var source_duration:float = maxf(stream.get_length(),0.001)
	return clampf(source_duration / maxf(target_duration,0.03),0.20,4.0)




func _body_width_audio_pitch_multiplier() -> float:
	# V62：大风车只改横向宽度，不改 sprite_scale。
	# 普通炮 body_width_scale 恒为 1，因此这里不会影响普通龙骨炮；
	# 大风车越宽，出现声和开火声越低/越慢，越窄则越高/越快。
	# 直接绑定 width，而不是再通过 attack_duration 间接猜测，保证 Inspector 改宽度时声音一定同步变化。
	return clampf(1.0 / maxf(sprite_width_scale,0.20),0.55,1.80)
func _play_appear_audio() -> void:
	if _appear_audio == null:
		return
	# V156：出现演出本身就是按原音频长度生成的，只保留 Sans 侧的小幅随机。
	# pitch_scale 因此通常非常接近 1，而不是旧版为了塞进 0.5 秒左右而大幅加速。
	_appear_audio.pitch_scale = _pitch_for_target_duration(SFX_APPEAR,appearance_duration) * _body_width_audio_pitch_multiplier()
	_appear_audio.play()


func _start_fire_audio_once() -> void:
	if _fire_audio_started or _fire_audio == null:
		return
	_fire_audio_started = true
	# 第 4 帧开始开火，到炮体/激光完全退出的总时间由 attack_total_duration 统一控制。
	# V62：普通炮仍按 attack_total_duration；大风车另外直接按 body_width_scale 改 pitch，确保横向宽度变化能被听见。
	_fire_audio.pitch_scale = _pitch_for_target_duration(SFX_FIRE,attack_total_duration) * _body_width_audio_pitch_multiplier()
	_fire_audio.play()


func _build_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "GasterBlasterSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	_sprite.scale = Vector2(sprite_scale * sprite_width_scale,sprite_scale)
	# 图集中炮口默认朝下（+Y），旋到 aim_direction。
	_sprite.rotation = aim_direction.angle() - PI * 0.5
	# 根节点已经位于 z=95；Sprite 与根节点同层即可。父节点 _draw() 的激光先画，
	# 子 Sprite 随后画在炮口上方，同时两者都会越过 z=90 的地图外遮罩。
	_sprite.z_index = 0
	add_child(_sprite)


func _frame_texture(index:int) -> AtlasTexture:
	var safe_index:int = clampi(index,0,GASTER_REGIONS.size() - 1)
	var atlas:=AtlasTexture.new()
	atlas.atlas = SANS_ATLAS
	atlas.region = GASTER_REGIONS[safe_index]
	atlas.filter_clip = true
	return atlas


func _set_frame(index:int) -> void:
	if _sprite == null:
		return
	var safe_index:int = clampi(index,0,GASTER_REGIONS.size() - 1)
	if safe_index == _last_frame_index:
		return
	_last_frame_index = safe_index
	_sprite.texture = _frame_texture(safe_index)


func _process(delta:float) -> void:
	if Game.now_stop_state:
		return
	_elapsed += maxf(delta,0.0)
	match _phase:
		0:
			var p:float = clampf(_elapsed / fly_duration,0.0,1.0)
			var smooth:float = p * p * (3.0 - 2.0 * p)
			global_position = spawn_position.lerp(park_position,smooth)
			if p >= 1.0:
				global_position = park_position
				_elapsed = 0.0
				_phase = 1
		1:
			var charge_index:int = clampi(int(floor(_elapsed / frame_duration)),0,3)
			_set_frame(charge_index)
			# V57：第 4 帧已经完全出现后，可额外保持一段“待发”时间。
			# 普通龙骨炮 pre_fire_hold_duration=0，行为与旧版一致；大风车会在这里停住，
			# 让新炮先排出来、过一会再开火，从时间上自然留下旋转缺口。
			var fire_start_time:float = frame_duration * 3.0 + pre_fire_hold_duration
			if _elapsed >= fire_start_time:
				_set_frame(3)
				_start_fire_audio_once()
				_beam_enabled = true
				_beam_alpha = 1.0
				_beam_width_scale = 1.0
				var fourth_frame_progress:float = clampf(
					(_elapsed - fire_start_time) / frame_duration,
					0.0,
					1.0
				)
				global_position = park_position - aim_direction * (recoil_distance * 0.08 * fourth_frame_progress)
				queue_redraw()
			if _elapsed >= fire_start_time + frame_duration:
				_elapsed = 0.0
				_phase = 2
		2:
			_beam_enabled = true
			_beam_alpha = 1.0
			_beam_width_scale = 1.0
			var loop_index:int = 4 + (int(floor(_elapsed / frame_duration)) % 2)
			_set_frame(loop_index)
			var fire_p:float = clampf(_elapsed / fire_duration,0.0,1.0)
			global_position = park_position - aim_direction * lerpf(recoil_distance * 0.08,recoil_distance * 0.72,fire_p)
			queue_redraw()
			if fire_p >= 1.0:
				_elapsed = 0.0
				_phase = 3
		3:
			var fade_p:float = clampf(_elapsed / fade_duration,0.0,1.0)
			_set_frame(4 + (int(floor(_elapsed / frame_duration)) % 2))
			global_position = park_position - aim_direction * lerpf(recoil_distance * 0.72,recoil_distance,fade_p)
			_beam_enabled = true
			_beam_alpha = 1.0 - fade_p
			_beam_width_scale = 1.0 - fade_p
			if _sprite != null:
				_sprite.modulate.a = 1.0 - fade_p
			queue_redraw()
			if fade_p >= 1.0:
				queue_free()


func _physics_process(_delta:float) -> void:
	if Game.now_stop_state:
		return
	if not _beam_enabled or _beam_alpha <= 0.02:
		return
	if source == null or not is_instance_valid(source) or not source.is_multiplayer_authority():
		return
	if source.health <= 0 or source.is_damage_output_disabled():
		return
	# V168：从“每 physics tick 1 点”改为每两个 physics tick 1 点，伤害频率严格减半。
	_damage_tick_toggle = not _damage_tick_toggle
	if not _damage_tick_toggle:
		return
	_apply_beam_damage()


func _draw() -> void:
	if not _beam_enabled or _beam_alpha <= 0.001:
		return
	var mouth:Vector2 = aim_direction * (GASTER_MOUTH_OFFSET_PX * sprite_scale)
	var mouth_world:Vector2 = global_position + mouth
	var length:float = _beam_visual_length(mouth_world)
	var beam_end:Vector2 = mouth + aim_direction * length
	var alpha:float = clampf(_beam_alpha,0.0,1.0)
	var current_width:float = maxf(beam_width * clampf(_beam_width_scale,0.0,1.0),0.01)

	# 始终是一根笔直、全长同宽的激光；V168 淡出时是“整根一起变细”，不是尾端做锥形。
	# 终点继续强制落到可视窗口之外，因此玩家不会看到激光末端。
	draw_line(mouth,beam_end,Color(1.0,1.0,1.0,alpha),current_width,true)


func _beam_visual_length(origin_world:Vector2) -> float:
	if beam_stop_at_target:
		# 大风车专用：激光到瞄准点（地图中心）就结束，不穿过中心进入对侧安全扇区。
		var to_target:Vector2 = aim_point - origin_world
		var projected:float = to_target.dot(aim_direction)
		return maxf(projected,8.0)
	return _beam_length_past_window(origin_world)


func _beam_length_past_window(origin_world:Vector2) -> float:
	var viewport:Viewport = get_viewport()
	if viewport == null:
		return maxf(map_rect.size.length() + 600.0,900.0)
	var camera:Camera2D = viewport.get_camera_2d()
	if camera == null:
		return maxf(map_rect.size.length() + 600.0,900.0)
	var zoom:Vector2 = camera.zoom.abs()
	var viewport_size:Vector2 = viewport.get_visible_rect().size
	var half_size:=Vector2(
		viewport_size.x / maxf(zoom.x,0.001),
		viewport_size.y / maxf(zoom.y,0.001)
	) * 0.5
	var screen_rect:=Rect2(camera.global_position - half_size,half_size * 2.0)
	var to_edge:float = _ray_rect_exit_distance(origin_world,aim_direction,screen_rect)
	# 再多画一截，保证抗锯齿/粗线端点也完全在窗口外。
	return maxf(to_edge + maxf(beam_width * 4.0,96.0),96.0)


func _apply_beam_damage() -> void:
	if get_world_2d() == null:
		return
	var mouth_world:Vector2 = global_position + aim_direction * (GASTER_MOUTH_OFFSET_PX * sprite_scale)
	var length:float
	if beam_stop_at_target:
		var to_target:Vector2 = aim_point - mouth_world
		length = maxf(to_target.dot(aim_direction),8.0)
	else:
		length = maxf(_ray_rect_exit_distance(mouth_world,aim_direction,map_rect),36.0)
	var shape:=RectangleShape2D.new()
	var current_width:float = maxf(beam_width * clampf(_beam_width_scale,0.0,1.0),0.5)
	shape.size = Vector2(length,current_width)
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(aim_direction.angle(),mouth_world + aim_direction * length * 0.5)
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,64)
	var seen:Dictionary = {}
	for hit:Dictionary in hits:
		var collider:Variant = hit.get("collider",null)
		if not collider is ball:
			continue
		var target:ball = collider as ball
		var id:int = target.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		if not _is_enemy(target):
			continue
		var karma_amount:float = held_contact_karma
		if not _contact_started.has(id):
			_contact_started[id] = true
			karma_amount = first_contact_karma
		source.call("apply_sans_frame_hit",target,target.global_position,karma_amount)


func _is_enemy(target:ball) -> bool:
	if target == null or target == source or target.health <= 0:
		return false
	if target.has_method("is_combat_targetable") and not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and not source_team.is_empty()
		and not target.Team.is_empty()
		and source_team == target.Team
	):
		return false
	return true


func _ray_rect_exit_distance(origin:Vector2,dir:Vector2,rect:Rect2) -> float:
	if rect.size.x <= 0.001 or rect.size.y <= 0.001:
		return 900.0
	var candidates:Array[float] = []
	var epsilon:float = 0.000001
	if absf(dir.x) > epsilon:
		for x_value in [rect.position.x,rect.end.x]:
			var x:float = float(x_value)
			var t:float = (x - origin.x) / dir.x
			if t >= 0.0:
				var y:float = origin.y + dir.y * t
				if y >= rect.position.y - 0.5 and y <= rect.end.y + 0.5:
					candidates.append(t)
	if absf(dir.y) > epsilon:
		for y_value in [rect.position.y,rect.end.y]:
			var y:float = float(y_value)
			var t:float = (y - origin.y) / dir.y
			if t >= 0.0:
				var x:float = origin.x + dir.x * t
				if x >= rect.position.x - 0.5 and x <= rect.end.x + 0.5:
					candidates.append(t)
	if candidates.is_empty():
		return maxf(rect.size.length(),320.0)
	var result:float = 0.0
	for value:float in candidates:
		result = maxf(result,value)
	return result
