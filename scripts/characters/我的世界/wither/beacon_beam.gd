extends Node2D
## Orthographically projected rotating prism, not a flat textured strip.
## All luminous volume stays inside the shared damage width; only halo is cosmetic.
const TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_beam.png")
const SHADER = preload("res://shaders/mc_beacon_beam.gdshader")
const PLANE_RATIO:float=1.6/sqrt(15.56)
const CAMERA_RIGHT:Vector2=Vector2(3.0,-2.0)/sqrt(13.0)
const CAMERA_DEPTH:Vector2=Vector2(2.0,3.0)/sqrt(13.0)
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
func update_beam(distance:float,simulation_time:float,width:float,opacity:float,preparing:bool,firing:bool) -> void:
	length=distance
	phase=simulation_time
	warning=preparing
	core_width=width
	alpha=opacity
	visible=(preparing or firing) and length>0.001 and core_width>0.0001 and alpha>0.0001
	beam_material.set_shader_parameter("scroll",fposmod(simulation_time*0.2,1.0))
	beam_material.set_shader_parameter("tiles",maxf(length/16.0,0.001))
	beam_material.set_shader_parameter("faceted",not warning)
	queue_redraw()
func prism_angle() -> float:
	# Simulation time only: replay/pause cannot keep turning the column.
	return phase*0.38
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
	var section:PackedVector2Array=projected_section(width,angle)
	for i:int in range(4):
		var a:Vector2=section[i]
		var b:Vector2=section[(i+1)%4]
		if (b.x<a.x)!=front or absf(b.x-a.x)<0.0001: continue
		a.y=maxf(a.y,-length)
		b.y=maxf(b.y,-length)
		var face_tint:Color=tint
		if lit:
			var normal:Vector2=Vector2(0,-1).rotated(angle+float(i)*PI*0.5)
			var light:float=0.42+0.58*maxf(normal.dot(Vector2(-0.2,0.98).normalized()),0.0)
			face_tint=Color(tint.r*light,tint.g*light,tint.b*light,tint.a)
		# Each physical side gets the original full tile. Rotation compresses and
		# reveals its pixels around the corner instead of sliding a flat billboard.
		draw_colored_polygon(PackedVector2Array([a,b,Vector2(b.x,-length),Vector2(a.x,-length)]),face_tint,PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]),TEXTURE)
func _draw() -> void:
	if length<=0.001 or core_width<=0.0001: return
	for i:int in range(3,0,-1):
		var glow_width:float=core_width+float(i)*(0.75 if warning else 0.65)
		draw_texture_rect(TEXTURE,Rect2(-glow_width*0.5,-length,glow_width,length),false,Color(0.35,0.78,1.0,alpha*0.045))
	if warning:
		draw_texture_rect(TEXTURE,Rect2(-core_width*0.5,-length,core_width,length),false,Color(0.85,1.0,1.1,alpha))
		return
	var angle:float=prism_angle()
	# Transparent rear shell -> solid, lit inner prism -> transparent front shell.
	# The shell's full width remains the gameplay/AI rectangle, never inflated.
	_draw_faces(core_width,angle,Color(0.12,0.48,0.85,alpha*0.26),false,false)
	_draw_faces(core_width*0.68,angle,Color(1.25,1.45,1.55,alpha),true,true)
	_draw_faces(core_width,angle,Color(0.26,0.78,1.0,alpha*0.26),true,true)
