extends Node2D
## 避雷针身下的能量条：共享能量条（creeper_style_bar）配原版蓝色 Boss 条的颜色。
## 平时隐藏，能量变化或被使用（放电、雷圈）时显示一会儿再淡出；接近满时进度条闪亮。
## 挂在角色根节点而不是 Graphics 下：不吃附魔光、受击形变和颤抖。
const BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
## 原版 blue_progress / blue_background 相对 white_* 的颜色倍率。
const FILL_COLOR:Color = Color(0.0,0.7755,1.0)
const TROUGH_COLOR:Color = Color(0.0,0.78,1.0)
const SIZE:Vector2 = Vector2(84.0,10.0)

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
	var fill:Color = FILL_COLOR
	if ratio > float(rod.tremble_start):
		var glow:float = 0.5 + 0.5 * sin(float(rod.visual_clock()) * 18.0)
		fill = Color(FILL_COLOR.r + glow * 0.6,FILL_COLOR.g + glow * 0.6,FILL_COLOR.b + glow * 0.3)
	BAR.paint(self,Rect2(-SIZE * 0.5,SIZE),ratio,0.0,fill,TROUGH_COLOR,alpha)
