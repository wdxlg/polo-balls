extends Node2D

# V38：三套爆炸帧在脚本载入时预加载。旧版在爆炸发生的 _ready() 中同步 load()，
# 第一次触发某个 variant 时会把磁盘/资源解析成本集中到爆炸当帧，容易产生帧尖峰。
const FRAME_SETS:Array[SpriteFrames] = [
	preload("res://scenes/effects/魔角猎人_爆炸1动画帧.tres"),
	preload("res://scenes/effects/魔角猎人_爆炸2动画帧.tres"),
	preload("res://scenes/effects/魔角猎人_爆炸3动画帧.tres"),
]
const AUDIO_STREAMS:Array[AudioStream] = [
	preload("res://audio/characters/魔角猎人/爆炸/tnt1.wav"),
	preload("res://audio/characters/魔角猎人/爆炸/tnt2.wav"),
	preload("res://audio/characters/魔角猎人/爆炸/tnt3.wav"),
]

@export_range(1,3,1) var variant:int = 1
@export_range(32.0,240.0,1.0) var visual_diameter:float = 108.0
@export_range(-30.0,6.0,0.5) var volume_db:float = -5.0
@export_range(0.5,2.5,0.05) var animation_speed_scale:float = 1.35

@onready var animation:AnimatedSprite2D = $Animation
@onready var audio:AudioStreamPlayer2D = $ExplosionAudio


func setup(new_variant:int,world_position:Vector2,new_visual_diameter:float = 108.0,new_volume_db:float = -5.0) -> void:
	variant = clampi(new_variant,1,3)
	global_position = world_position
	visual_diameter = maxf(new_visual_diameter,16.0)
	volume_db = new_volume_db


func _ready() -> void:
	add_to_group("BattleTransient")
	set_as_top_level(true)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	z_index = 70
	var index:int = clampi(variant,1,3) - 1
	var frames:SpriteFrames = FRAME_SETS[index]
	if frames == null:
		queue_free()
		return
	animation.sprite_frames = frames
	animation.animation = &"explode"
	animation.frame = 0
	# 优化后的每帧固定 256x256，按实际爆炸直径统一缩放。
	var s:float = maxf(visual_diameter,16.0) / 256.0
	animation.scale = Vector2.ONE * s
	animation.speed_scale = maxf(animation_speed_scale,0.05)
	animation.play(&"explode")
	audio.stream = AUDIO_STREAMS[index]
	audio.volume_db = volume_db
	audio.play()
	var frame_duration:float = float(frames.get_frame_count(&"explode")) / maxf(frames.get_animation_speed(&"explode") * animation.speed_scale,1.0)
	var audio_duration:float = audio.stream.get_length() if audio.stream != null else 0.0
	await get_tree().create_timer(maxf(frame_duration,audio_duration) + 0.08).timeout
	if is_instance_valid(self):
		queue_free()
