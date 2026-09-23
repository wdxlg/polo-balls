extends Node2D
## Emissive prism rooted in the exact vanilla inner-core top plane.
## All luminous volume stays inside the shared damage width; only halo is cosmetic.
const TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_beam.png")
const SHADER = preload("res://shaders/mc_beacon_beam.gdshader")
const PLANE_RATIO:float=1.6/sqrt(15.56)
const CAMERA_RIGHT:Vector2=Vector2(3.0,-2.0)/sqrt(13.0)
const CAMERA_DEPTH:Vector2=Vector2(2.0,3.0)/sqrt(13.0)
const GLOW=preload("res://scripts/characters/我的世界/wither/beacon_glow.gd")
var _glow:Node2D
var source_width:float=0.0
var length:float=0.0
var phase:float=0.0
var warning:bool=false
var core_width:float=0.0
var alpha:float=0.0
var beam_material:ShaderMaterial
func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	beam_material=ShaderMaterial.new()
	beam_material.shader=SHADER
	material=beam_material
	# Draw behind the baked block: its front glass/core occlude the buried emitter.
	show_behind_parent=true
	_glow=GLOW.new()
	_glow.show_behind_parent=true
	add_child(_glow)
func update_beam(distance:float,simulation_time:float,width:float,opacity:float,preparing:bool,firing:bool,emitter_width:float=0.0) -> void:
	source_width=emitter_width if emitter_width>0 else width
	length=distance
	phase=simulation_time
	warning=preparing
	core_width=width
	alpha=opacity
	visible=(preparing or firing) and length>0.001 and core_width>0.0001 and alpha>0.0001
	beam_material.set_shader_parameter("scroll",fposmod(simulation_time*0.2,1.0))
	beam_material.set_shader_parameter("tiles",maxf(length/16.0,0.001))
	beam_material.set_shader_parameter("faceted",not warning)
	_glow.update_glow(core_width,length,alpha if visible else 0.0)
	queue_redraw()
func prism_angle() -> float:
	# The emitter and full prism stay aligned to the stationary vanilla blue cube.
	# Texture still travels upward, but spinning the base would detach its corners.
	return 0.0
func source_section(width:float) -> PackedVector2Array:
	var base_width:float=minf(width,source_width)
	var section:PackedVector2Array=projected_section(base_width,0.0)
	for i:int in range(4):
		section[i].y+=(base_width-source_width)*PLANE_RATIO*0.5
	return section
func projected_section(width:float,angle:float) -> PackedVector2Array:
	var points:=PackedVector2Array()
	var half_span:float=0.0
	var near_depth:float=-INF
	for corner:Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var world_xz:Vector2=corner.rotated(angle)
		var projected:=Vector2(world_xz.dot(CAMERA_RIGHT),world_xz.dot(CAMERA_DEPTH)*PLANE_RATIO)
		points.append(projected)
		half_span=maxf(half_span,absf(projected.x))
		near_depth=maxf(near_depth,projected.y)
	var unit:float=width/(2.0*half_span)
	for i:int in range(4):
		# Front tip touches the exact ray origin. No luminous face below the hitbox.
		points[i]=Vector2(points[i].x,points[i].y-near_depth)*unit
	return points
func _draw_faces(width:float,angle:float,tint:Color,front:bool,lit:bool) -> void:
	var section:PackedVector2Array=source_section(width)
	var upper:PackedVector2Array=projected_section(width,angle)
	for i:int in range(4):
		var a:Vector2=section[i]
		var b:Vector2=section[(i+1)%4]
		if (b.x<a.x)!=front or absf(b.x-a.x)<0.0001: continue
		a.y=maxf(a.y,-length)
		b.y=maxf(b.y,-length)
		var face_tint:Color=tint
		if lit:
			var normal:Vector2=Vector2(0,-1).rotated(angle+float(i)*PI*0.5)
			var light:float=0.62+0.38*maxf(normal.dot(Vector2(-0.2,0.98).normalized()),0.0)
			face_tint=Color(tint.r*light,tint.g*light,tint.b*light,tint.a)
		# Each physical side gets the original full tile. Side UVs preserve
		# the square core shape; upward flow never rotates the anchored base.
		draw_colored_polygon(PackedVector2Array([a,b,Vector2(upper[(i+1)%4].x,-length),Vector2(upper[i].x,-length)]),face_tint,PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]),TEXTURE)
func _draw() -> void:
	if length<=0.001 or core_width<=0.0001: return
	for i:int in range(3,0,-1):
		var glow_width:float=core_width+float(i)*(0.75 if warning else 0.65)
		draw_texture_rect(TEXTURE,Rect2(-glow_width*0.5,-length,glow_width,length),false,Color(0.35,0.78,1.0,alpha*0.045))
	if warning:
		draw_texture_rect(TEXTURE,Rect2(-core_width*0.5,-length,core_width,length),false,Color(0.85,1.0,1.1,alpha))
		return
	var angle:float=prism_angle()
	# The emitting volume itself matches the blue cube, not a narrower centre stripe.
	# A bright faceted column plus independent additive bloom reads as emitted light.
	_draw_faces(core_width,angle,Color(0.18,0.62,1.0,alpha*.18),false,false)
	_draw_faces(core_width,angle,Color(1.25,1.45,1.55,alpha),true,true)
