extends RefCounted
## Original Mojang Bedrock atlas and UVs; see MC_MINECART_ASSETS.json.
## Emission positions/lifetimes are adapted to this project's 2D combat, not a full Bedrock simulation.
const ATLAS:Texture2D = preload("res://Images/characters/我的世界/矿车/particles.png")
static func region(kind:String,progress:float = 0.0) -> Rect2:
	var frame:int = clampi(int(progress*8.0),0,7)
	match kind:
		"crit": return Rect2(frame*8,72,8,8)
		"magic": return Rect2(16,32,8,8)
		"electric": return Rect2(16,48,8,8)
		_: return Rect2(56-frame*8,0,8,8) # Native smoke/redstone flipbook, right to left.
static func tint(kind:String,progress:float = 0.0) -> Color:
	var t:float = clampf(progress,0.0,1.0)
	match kind:
		"crit": return Color(0.75,0.75,0.75).lerp(Color(0.75,0.5,0.3),t)
		"magic": return Color(0.75,0.75,0.8).lerp(Color(0.5,0.5,0.8),t)
		"electric": return Color(1.0,0.9,1.0)
		"redstone": return Color(0.7,0.0,0.0)
		_: return Color(0.4,0.4,0.4)
static func draw(node:Node2D,kind:String,point:Vector2,size:float,progress:float = 0.0,opacity:float = 1.0) -> void:
	var color:Color = tint(kind,progress)
	color.a = clampf(opacity,0.0,1.0)
	node.draw_texture_rect_region(ATLAS,Rect2(point-Vector2.ONE*size*0.5,Vector2.ONE*size),region(kind,progress),color)
