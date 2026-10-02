extends Node2D
## 避雷针身下的能量条：原版蓝色 Boss 条（gui/sprites/boss_bar/blue_*）三段式拉伸绘制。
## 平时隐藏，能量变化或被使用（放电、雷圈）时显示一会儿再淡出；接近满时进度条闪亮。
## 挂在角色根节点而不是 Graphics 下：不吃附魔光、受击形变和颤抖。
const BACKGROUND:Texture2D = preload("res://Images/characters/我的世界/lightning_rod/boss_bar_blue_background.png")
const PROGRESS:Texture2D = preload("res://Images/characters/我的世界/lightning_rod/boss_bar_blue_progress.png")
const WIDTH:float = 84.0
const SCALE:float = 2.0
const CAP:float = 3.0

## 所属避雷针（动态读取 bar_alpha / storm_charge_ratio）。
var rod


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = 60


func _process(_delta:float) -> void:
	queue_redraw()


func _draw() -> void:
	if rod == null or not is_instance_valid(rod): return
	var alpha:float = float(rod.bar_alpha())
	if alpha <= 0.0: return
	var ratio:float = clampf(float(rod.storm_charge_ratio()),0.0,1.0)
	var height:float = BACKGROUND.get_height() * SCALE
	var origin := Vector2(-WIDTH * 0.5,-height * 0.5)
	_slice(BACKGROUND,origin,WIDTH,Color(1.0,1.0,1.0,alpha))
	var tint := Color(1.0,1.0,1.0,alpha)
	if ratio > float(rod.tremble_start):
		var glow:float = 0.5 + 0.5 * sin(float(rod.visual_clock()) * 18.0)
		tint = Color(1.0 + glow * 0.6,1.0 + glow * 0.6,1.0 + glow * 0.3,alpha)
	_slice(PROGRESS,origin,WIDTH * ratio,tint)


## 两端各保留 CAP 个原版像素，中段水平拉伸；宽度不足两端时只画左端的一截。
func _slice(texture:Texture2D,origin:Vector2,width:float,tint:Color) -> void:
	if width <= 0.0: return
	var source_w:float = texture.get_width()
	var source_h:float = texture.get_height()
	var height:float = source_h * SCALE
	var cap:float = CAP * SCALE
	if width <= cap * 2.0:
		draw_texture_rect_region(texture,Rect2(origin,Vector2(width,height)),Rect2(0.0,0.0,width / SCALE,source_h),tint)
		return
	draw_texture_rect_region(texture,Rect2(origin,Vector2(cap,height)),Rect2(0.0,0.0,CAP,source_h),tint)
	draw_texture_rect_region(texture,Rect2(origin + Vector2(cap,0.0),Vector2(width - cap * 2.0,height)),Rect2(CAP,0.0,source_w - CAP * 2.0,source_h),tint)
	draw_texture_rect_region(texture,Rect2(origin + Vector2(width - cap,0.0),Vector2(cap,height)),Rect2(source_w - CAP,0.0,CAP,source_h),tint)
