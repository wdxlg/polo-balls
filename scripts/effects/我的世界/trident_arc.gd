extends Node2D
const PALETTE = preload("res://scripts/effects/我的世界/mc_electric_palette.gd")
const ENCHANTMENT = preload("res://scripts/effects/我的世界/trident_enchantment.gd")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
var caster:ball
var first:WeakRef
var second:WeakRef
var start:Vector2
var end:Vector2
var lifetime:float = 0.36
var left:float = 0.36
var seed_value:int = 1
var _hit:Dictionary = {}
var _previous:Dictionary = {}
var _enchant_previous:Dictionary = {}
var _clock:float = 0.0
var _last_start:Vector2
var _last_end:Vector2
func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform2D.IDENTITY
	z_index = 7
	add_to_group("BattleTransient")
	add_to_group("MCTridentArc")
	_last_start = start
	_last_end = end
	_spread_enchantment()
func _spread_enchantment() -> void:
	if not is_instance_valid(caster) or Game.now_stop_state or get_tree().paused: return
	ENCHANTMENT.along_arc(caster,start,end,_last_start,_last_end,_enchant_previous)
func _physics_process(delta:float) -> void: advance(delta)
func advance(delta:float) -> void:
	if not is_instance_valid(caster) or caster.health<=0:
		queue_free()
		return
	if Game.now_stop_state or get_tree().paused or not caster.is_combat_runtime_active(): return
	for ref:WeakRef in [first,second]:
		if ref!=null and (not is_instance_valid(ref.get_ref()) or not ref.get_ref().eligible()):
			queue_free()
			return
	if first!=null: start = first.get_ref().global_position
	if second!=null: end = second.get_ref().global_position
	_clock += delta
	left -= delta
	if left<=0.0:
		queue_free()
		return
	# Each peer charges only its owned allied items; replicas never originate duplicates.
	_spread_enchantment()
	if caster.mc_live():
		for raw:Node in get_tree().get_nodes_in_group("Ball"):
			if not GEOMETRY.enemy(caster,raw) or _hit.has(raw.get_instance_id()): continue
			var id:int = raw.get_instance_id()
			var point:Vector2 = ball.body_point(raw,global_position)
			var previous:Vector2 = _previous.get(id,point)
			_previous[id] = point
			var touched:bool = GEOMETRY.touching(start,end,point,previous,GEOMETRY.radius(raw)+caster.network_width)
			if not touched:
				touched = Geometry2D.is_point_in_polygon(point,PackedVector2Array([_last_start,_last_end,end,start]))
			if not touched: continue
			_hit[id] = true
			if caster.mc_damage_with_impact(raw,caster.attack_damage()*caster.network_damage_ratio,point) and is_instance_valid(raw) and raw.health>0:
				raw.apply_stun(caster.network_stun)
	_last_start = start
	_last_end = end
	queue_redraw()
func _draw() -> void:
	paint(self,start,end,seed_value,_clock,clampf(left/lifetime,0.0,1.0))

## 抖动电弧连线（三层电光色），纯绘制。三叉戟电网、避雷针电网与放电共用。
static func paint(canvas:CanvasItem,from:Vector2,to:Vector2,arc_seed:int,clock:float,fade:float,jitter_scale:float = 3.0,segments:int = 12) -> void:
	if fade<=0.0: return
	var normal:Vector2 = (to-from).normalized().orthogonal()
	var count:int = maxi(segments,2)
	var points := PackedVector2Array([from])
	for i:int in range(1,count):
		var fraction:float = float(i)/float(count)
		var jitter:float = sin(float(arc_seed%997)+i*8.3+floor(clock*24.0)*5.2)*jitter_scale*sin(PI*fraction)
		points.append(from.lerp(to,fraction)+normal*jitter)
	points.append(to)
	canvas.draw_polyline(points,Color(PALETTE.OUTER,0.18*fade),8.0,true)
	canvas.draw_polyline(points,Color(PALETTE.MIDDLE,0.55*fade),3.0,true)
	canvas.draw_polyline(points,Color(PALETTE.CORE,fade),1.0,true)
