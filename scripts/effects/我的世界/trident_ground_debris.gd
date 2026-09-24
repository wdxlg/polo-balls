extends "res://scripts/effects/我的世界/重锤落地冲击.gd"
## 三叉戟插地：复用重锤的“真实地板取色”方块碎屑，不画重锤的白色冲击圈与放射线。
## 保持重锤同款方块数量/尺寸/飞行/停留/淡出，仅把来源范围收在三叉戟落点附近。
const DEBRIS_RADIUS:float = 16.0
# 重锤默认只采地图中央水印那一小块地板；三叉戟可能在场地任何位置落地，
# 所以这里用落点所在场地的真实矩形，碎屑才会取到落点附近的颜色。
var floor_rect:Rect2 = Rect2()
func start(point:Vector2,arena:Rect2 = Rect2(),replay_age:float = 0.0) -> void:
	floor_rect = arena
	add_to_group("MCTridentGroundDebris")
	add_to_group("BattleTransient")
	top_level = true
	global_scale = Vector2.ONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Parent defaults are the actual mace preset; do not replace it with a
	# much fainter, tiny approximation. Keep the spatial footprint compact.
	block_source_scatter = 3.0
	await super.setup(point,DEBRIS_RADIUS)
	if is_inside_tree():
		z_index = 4
		_elapsed = maxf(replay_age,0.0)
func _current_map_rect() -> Rect2:
	if floor_rect.size.x>1.0 and floor_rect.size.y>1.0: return floor_rect
	return super._current_map_rect()
func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	super._process(delta)
func _draw() -> void:
	# 只要方块碎屑，不要重锤的冲击圈/爆射线。
	_draw_block_particles()
