extends Area2D
## Weaving's web on death: slows entities inside, not the original infected
## entity (which can move through webs unhindered).  World-owned, not a fake
## attack Buff, and automatically cleaned up with other battle transients.
const WEB_RADIUS:float = 13.0
const WEB_LIFETIME:float = 20.0 # Arena has no mineable, persistent web blocks.
var remaining:float = WEB_LIFETIME
var _inside:Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	monitoring = true
	var shape:CollisionShape2D = CollisionShape2D.new()
	var circle:CircleShape2D = CircleShape2D.new()
	circle.radius = WEB_RADIUS
	shape.shape = circle
	add_child(shape)
	add_to_group("BattleTransient")
	add_to_group("MCWeavingWeb")
	area_entered.connect(_entered)
	area_exited.connect(_exited)
	queue_redraw()

func _entered(area:Area2D) -> void:
	var unit:ball = area.get_parent() as ball
	if unit != null and is_instance_valid(unit): _inside[unit.get_instance_id()] = weakref(unit)

func _exited(area:Area2D) -> void:
	var unit:ball = area.get_parent() as ball
	if unit == null or not is_instance_valid(unit): return
	_inside.erase(unit.get_instance_id())
	unit.Buff_Dic.erase(get_instance_id())

func _physics_process(delta:float) -> void:
	remaining -= delta
	if remaining <= 0.0:
		queue_free()
		return
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("new_buff"): return
	for key:int in _inside.keys():
		var ref:WeakRef = _inside[key] as WeakRef
		var unit:ball = ref.get_ref() as ball if ref != null else null
		if unit == null or not is_instance_valid(unit) or unit.health <= 0:
			_inside.erase(key)
			continue
		if unit.has_minecraft_status("weaving"): continue
		if unit.is_multiplayer_authority():
			world.call("new_buff",unit,self,"MC蛛网减速",Buff.new(2,0.25,Buff.Buff_types.Speed,0.25,Buff.Algorithms.mul))

func _exit_tree() -> void:
	for ref:WeakRef in _inside.values():
		var unit:Variant = ref.get_ref() if ref != null else null
		if is_instance_valid(unit) and unit is ball: (unit as ball).Buff_Dic.erase(get_instance_id())
	_inside.clear()

func _draw() -> void:
	var white:Color = Color(0.91,0.94,1.0,0.82)
	for i:int in range(8):
		var a:Vector2 = Vector2.from_angle(TAU * float(i)/8.0)*WEB_RADIUS
		draw_line(Vector2.ZERO,a,white,1.0)
	for r:float in [4.0,8.0,12.0]:
		draw_arc(Vector2.ZERO,r,0.0,TAU,32,white,1.0)
