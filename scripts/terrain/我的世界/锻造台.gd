extends StaticBody2D
## 钻石剑的下界合金竞技场锻造台：原版单格 3D 锻造台（mc_block_3d.gd），碰撞正好一格地图格。
const BLOCK = preload("res://scripts/effects/我的世界/mc_block_3d.gd")
var block:Node2D

func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MinecraftSmithingTable")
	var size:float = BLOCK.map_cell(self)
	var collider:CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collider != null:
		var shape := RectangleShape2D.new()
		shape.size = Vector2.ONE*size
		collider.shape = shape
	block = BLOCK.create(&"smithing_table",size)
	add_child(block)
