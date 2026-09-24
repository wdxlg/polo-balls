extends "res://scripts/characters/我的世界/frontier/moss_debris.gd"
# Reuse moss placement's six ballistic chips, but sample the original cobweb.
const WEB:Texture2D = preload("res://Images/characters/我的世界/蜘蛛/cobweb_native.png")
static var _palette:PackedColorArray = PackedColorArray()
func setup_web(owner_actor:Node2D,point:Vector2,diameter:float) -> void:
	super.setup(owner_actor,point,false,diameter,false,true)
	remove_from_group("MCMossPlaceDebris")
	add_to_group("MCSpiderWebDebris")
	add_to_group("BattleTransient")
	if _palette.is_empty():
		var pixels:Image = WEB.get_image()
		for y:int in range(pixels.get_height()):
			for x:int in range(pixels.get_width()):
				var color:Color = pixels.get_pixel(x,y)
				if color.a>0.5: _palette.append(color)
	for block:Dictionary in blocks:
		block.color = _palette[_rng.randi_range(0,_palette.size()-1)] if not _palette.is_empty() else Color.WHITE
		block.size = float(_rng.randi_range(1,2))
func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	super._process(delta)
func _draw() -> void:
	for block:Dictionary in blocks:
		if elapsed<float(block.delay): continue
		var pose:Dictionary = block_pose(block,elapsed)
		var color:Color = block.color
		color.a *= float(pose.alpha)
		var size:float = float(block.size)
		draw_rect(Rect2((pose.point-Vector2.ONE*size*0.5).round(),Vector2.ONE*size),color)
