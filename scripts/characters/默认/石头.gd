extends StaticBody2D
## Placeable terrain, not a combat actor. No stats, state machine or hurtboxes.
const STONE_TEXTURE:Texture2D = preload("res://Images/characters/默认/石头/石头.png")
@onready var image:Sprite2D = $Graphics/Image

func get_preview_texture() -> Texture2D:
	return STONE_TEXTURE
