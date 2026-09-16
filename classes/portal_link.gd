class_name PortalLink
extends Resource

# ============================================================
# 传送门连接（配合 PortalMap 使用）
#
# 一条连接描述“某个岛的某一条边（或边上的一段）”与“另一个岛的某一条边”之间的传送关系。
# - from_island / to_island：PortalMap 下 TileMapLayer 子节点的名字。
# - from_side / to_side：上下左右。两侧朝向可以不同（例如 左边 -> 上边），
#   穿越时位置和速度会按两条边的朝向差做旋转/镜像映射。
# - pass_mode：谁可以通过。不能通过的一类会被一堵不可见过滤墙挡住。
# - whole_edge=false 时，用 from_offset/from_length 指定边上的一段（像素，
#   从该边的上端/左端开始量）。to_offset/to_length 留 0 表示与 from 相同。
# ============================================================

# 注意：不能叫 Side，会与 Godot 全局枚举 Side(SIDE_LEFT...) 冲突。
enum Edge { LEFT = 0, RIGHT = 1, TOP = 2, BOTTOM = 3 }
enum PassMode { BOTH = 0, CHARACTERS_ONLY = 1, PROJECTILES_ONLY = 2 }

@export_storage var from_island:String = ""
@export_storage var from_side:Edge = Edge.RIGHT
@export_storage var to_island:String = ""
@export_storage var to_side:Edge = Edge.LEFT

@export_storage var pass_mode:PassMode = PassMode.BOTH
# true：两边都可以进入并传送到对方；false：只能从 from 进入，to 只作为出口。
@export_storage var bidirectional:bool = true
# 默认沿门方向按同一比例映射（左边靠上进 -> 右边靠上出）。
# mirror=true 时沿门方向镜像（靠上进 -> 靠下出），速度的切向分量也一起翻转。
@export_storage var mirror:bool = false

@export_storage var whole_edge:bool = true
# 只在 whole_edge=false 时生效，单位为世界像素，从边的上端（左右边）/左端（上下边）算起。
@export_storage var from_offset:float = 0.0
@export_storage var from_length:float = 32.0
# 0 表示沿用 from 的数值。
@export_storage var to_offset:float = 0.0
@export_storage var to_length:float = 0.0

# alpha 为 0 时按 pass_mode 自动配色：都可=青、仅角色=绿、仅子弹=橙。
@export_storage var color:Color = Color(0,0,0,0)


func resolved_color() -> Color:
	if color.a > 0.001:
		return color
	match pass_mode:
		PassMode.CHARACTERS_ONLY:
			return Color(0.35,0.95,0.45,1.0)
		PassMode.PROJECTILES_ONLY:
			return Color(1.0,0.62,0.2,1.0)
		_:
			return Color(0.3,0.85,1.0,1.0)


func allows_characters() -> bool:
	return pass_mode != PassMode.PROJECTILES_ONLY


func allows_projectiles() -> bool:
	return pass_mode != PassMode.CHARACTERS_ONLY
