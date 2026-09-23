extends RefCounted
## Exact orthographic projection of the vanilla inner model, not the glass shell.
## Source: beacon.json inner from [3,3,3] to [13,14,13]. Bake: 256px / 1.85.
const PLANE_RATIO:float=1.6/sqrt(15.56)
const CAMERA_RIGHT:Vector2=Vector2(3.0,-2.0)/sqrt(13.0)
const CAMERA_DEPTH:Vector2=Vector2(2.0,3.0)/sqrt(13.0)
const CAMERA_UP:float=sqrt(13.0)/sqrt(15.56)
const PIXELS_PER_MODEL_UNIT:float=256.0/1.85/16.0
const IMAGE_WIDTH:float=196.0
static func project(point:Vector3,body_width:float) -> Vector2:
	var p:Vector3=point-Vector3(8,8,8)
	var xz:=Vector2(p.x,p.z)
	return Vector2(xz.dot(CAMERA_RIGHT),xz.dot(CAMERA_DEPTH)*PLANE_RATIO-p.y*CAMERA_UP)*PIXELS_PER_MODEL_UNIT*body_width/IMAGE_WIDTH
static func core_center(body_width:float) -> Vector2:
	return project(Vector3(8,14,8),body_width)
static func glass_center(body_width:float) -> Vector2:
	return project(Vector3(8,16,8),body_width)
static func core_width(body_width:float) -> float:
	return project(Vector3(13,14,3),body_width).x-project(Vector3(3,14,13),body_width).x
static func beam_tip(body_width:float) -> Vector2:
	# Bounding-box bottom of the projected core top. X remains its central axis.
	return Vector2(0,project(Vector3(13,14,13),body_width).y)
static func core_top(body_width:float) -> PackedVector2Array:
	return PackedVector2Array([project(Vector3(3,14,3),body_width),project(Vector3(13,14,3),body_width),project(Vector3(13,14,13),body_width),project(Vector3(3,14,13),body_width)])
