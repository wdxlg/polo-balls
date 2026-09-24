extends Sprite2D
## Visual only. Explosion damage is resolved once by the sulfur cube at fuse=0.
const FRAMES:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_0.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_1.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_2.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_3.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_4.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_5.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_6.png"),
	preload("res://Images/characters/我的世界/sulfur_cube/explosion_7.png"),
]
var elapsed:float = 0.0
var blast_radius:float = 116.0

func _ready() -> void:
	z_as_relative = false
	z_index = 40
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = FRAMES[0]
	scale = Vector2.ONE * (blast_radius*2.0/float(texture.get_width()))
	add_to_group("BattleTransient")

func _process(delta:float) -> void:
	elapsed += delta
	var frame:int = mini(int(elapsed*18.0),FRAMES.size()-1)
	texture = FRAMES[frame]
	if elapsed >= float(FRAMES.size())/18.0: queue_free()
