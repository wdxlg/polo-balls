extends Node2D
# Additive light spill works in Compatibility too; no project-wide HDR/bloom dependency.
# Owner supplies the paused impact clock; this node never advances a separate timer.
const AFTERGLOW_DURATION:float = 0.12
var source:Node2D
func _ready() -> void:
	z_index = -1
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = additive
func intensity() -> float:
	if not is_instance_valid(source) or not source._impact_started: return 0.0
	var t:float = source._impact_elapsed()
	var slot:int = source._flash_slot(t)
	if slot<0:
		if t>=source.bolt_lifetime: return 0.35*pow(clampf(1.0-(t-source.bolt_lifetime)/AFTERGLOW_DURATION,0.0,1.0),2.0)
		return 0.10 * (1.0-(t/source.bolt_lifetime))
	var start:float = 0.0 if slot==0 else source.bolt_lifetime*0.54
	var span:float = source.bolt_lifetime*(0.34 if slot==0 else 0.46)
	var p:float = clampf((t-start)/maxf(span,0.001),0.0,1.0)
	return (1.0 if slot==0 else 0.85)*lerpf(1.0,0.50,p)*(0.94+0.06*cos(t*95.0))
func _draw() -> void:
	var energy:float = intensity()
	if energy<=0.0: return
	_draw_halo(source._points,1.0,energy)
	for branch:PackedVector2Array in source._branches: _draw_halo(branch,0.6,energy*0.65)
	# Local falloff on the ground, not an opaque disk or fullscreen flash.
	for i:int in range(16):
		var p:float = float(i)/15.0
		var radius:float = source.impact_radius*lerpf(0.78,0.10,p)
		draw_circle(Vector2.ZERO,radius,Color(source.PALETTE.MIDDLE,energy*lerpf(0.009,0.025,p)))
func _draw_halo(path:PackedVector2Array,width_scale:float,energy:float) -> void:
	if path.size()<2: return
	var widths:Array[float] = [2.8,2.4,2.0,1.65,1.3,1.0,0.72]
	var alphas:Array[float] = [0.012,0.016,0.023,0.034,0.050,0.075,0.12]
	for i:int in range(widths.size()):
		var color:Color = source.PALETTE.OUTER.lerp(source.PALETTE.MIDDLE,float(i)/float(widths.size()-1))
		color.a = alphas[i]*energy
		draw_polyline(path,color,source.outer_glow_width*widths[i]*width_scale,true)
