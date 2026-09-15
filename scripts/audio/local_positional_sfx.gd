extends RefCounted

# 本地空间音效表。只使用项目内已有资源，不联网、不下载、不写 user:// 缓存。
const LIBRARY:Dictionary = {
	"gun_a": preload("res://audio/sfx/枪/单发/g18_单发.mp3"),
	"gun_b": preload("res://audio/sfx/枪/单发/MP7_单发.mp3"),
	"reload": preload("res://audio/sfx/战斗/霰弹枪上膛.mp3"),
	"rocket_launch": preload("res://audio/sfx/战斗/火箭筒发射.mp3"),
	"explosion": preload("res://audio/sfx/战斗/火箭筒爆炸.mp3"),
	"punch": preload("res://audio/characters/拳击手/拳击手_命中.mp3"),
	"stone_break": preload("res://audio/characters/矿工/攻击.mp3"),
	"stone_land": preload("res://audio/characters/矿工/石子.mp3"),
	"throw": preload("res://audio/characters/拳击手/拳击手_挥拳.mp3"),
	"teleport": preload("res://audio/characters/时光客/倒放.mp3"),
	"warp_in": preload("res://audio/characters/时光客/倒放.mp3"),
	"warp_out": preload("res://audio/characters/时光客/倒放.mp3"),
	"purchase": preload("res://audio/characters/收债人/结账.mp3"),
	"click": preload("res://audio/ui/button/Button_Down1.ogg"),
	"bullet_hit": preload("res://audio/sfx/战斗/子弹打人.mp3"),
	"snake_bite": preload("res://audio/characters/猎人/蛇叫.mp3"),
	"snake_die": preload("res://audio/characters/猎人/蛇叫.mp3"),
	"balloon_pop": preload("res://audio/characters/气球/爆炸.mp3"),
	"waraxe_swing": preload("res://audio/characters/战斧重骑兵/挥舞.mp3"),
	"waraxe_hit": preload("res://audio/characters/战斧重骑兵/砍人.mp3"),
	"waraxe_armor_break": preload("res://audio/characters/战斧重骑兵/破甲.mp3"),
}

static func play(
	anchor:Node,
	key:String,
	world_position:Vector2,
	volume_db:float = -6.0,
	pitch_scale:float = 1.0,
	max_distance:float = 800.0
) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var stream:AudioStream = LIBRARY.get(key) as AudioStream
	if stream == null:
		return
	var tree:SceneTree = anchor.get_tree()
	if tree == null:
		return
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	if parent == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "LocalSfxPlayer"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch_scale,0.05)
	player.max_distance = maxf(max_distance,50.0)
	player.attenuation = 1.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	parent.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
