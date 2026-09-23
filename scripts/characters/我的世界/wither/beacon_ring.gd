extends Node2D
## The mace's three-band pixel ring, projected onto the beacon's TOP plane.
## A visual cue only: no damage/hazard group and no additional impact sound.
const ARC=preload("res://scripts/effects/我的世界/pixel_arc.gd")
const LIFETIME:float=0.46
# Same orthographic camera used by tools/minecraft/bake_beacon_block.gd:
# viewing vector (2,1.6,3), hence the horizontal plane's projected Y/X ratio.
const PLANE_RATIO:float=1.6/sqrt(2.0*2.0+1.6*1.6+3.0*3.0)
const TOP_SURFACE_UV:Vector2=Vector2(0.5,0.196)
var front_half:bool=false
var age:float=-1.0
var radius:float=0.0
var opacity:float=0.0
var unit:float=1.0
func _ready() -> void:
	visible=false
	set_process(false)
func update_ring(elapsed:float,body_width:float,alive:bool) -> void:
	age=elapsed
	visible=alive and age>=0 and age<LIFETIME
	unit=maxf(body_width/64.0,0.001)
	var p:float=clampf(age/LIFETIME,0.0,1.0)
	# Same ease-out and fade exponents as the original heavy-mace white ring.
	radius=lerpf(24.0,110.0,1.0-pow(1.0-p,3.1))*unit
	opacity=pow(1.0-p,1.28) if visible else 0.0
	queue_redraw()
func _draw() -> void:
	if not visible or opacity<=0: return
	var start:float=0.0 if front_half else PI
	var end:float=PI if front_half else TAU
	var depth:float=1.0 if front_half else 0.52
	# Flatten the whole annulus, including its stroke, not just the centreline.
	# Back half is drawn before the laser; front half after it for depth overlap.
	draw_set_transform(Vector2.ZERO,0.0,Vector2(unit,unit*PLANE_RATIO))
	ARC.draw(self,Vector2.ZERO,radius/unit,start,end,64,Color(0.08,0.3,1.0,0.16*opacity*depth),7.0,true)
	ARC.draw(self,Vector2.ZERO,radius/unit,start,end,64,Color(0.12,0.5,1.0,0.40*opacity*depth),3.6,true)
	ARC.draw(self,Vector2.ZERO,radius/unit,start,end,64,Color(0.22,0.7,1.0,0.98*opacity*depth),1.35,true)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
