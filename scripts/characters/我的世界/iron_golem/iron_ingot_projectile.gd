extends Node2D
const TEXTURE:Texture2D = preload("res://Images/characters/我的世界/iron_golem/iron_ingot.png")
var source_ref:WeakRef
var heading:Vector2 = Vector2.RIGHT
var damage:float = 70.0
var speed:float = 280.0
var remaining:float = 240.0
var _spent:bool = false
var sprite:Sprite2D
func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("GolemIronProjectile")
	sprite = Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.scale = Vector2.ONE*0.45
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	z_index = 8
func _physics_process(delta:float) -> void: advance(delta)
func advance(delta:float) -> void:
	if _spent or Game.now_stop_state or get_tree().paused: return
	var source:Node2D = source_ref.get_ref() as Node2D if source_ref!=null else null
	if not is_instance_valid(source):
		finish()
		return
	if not source.is_combat_runtime_active(): return
	var travel:float = minf(speed*delta,remaining)
	var start:Vector2 = global_position
	var end:Vector2 = start+heading*travel
	sprite.rotation += delta*12.0
	if is_multiplayer_authority():
		var query := PhysicsRayQueryParameters2D.create(start,end,1)
		var wall:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if not wall.is_empty(): end = wall.position
		var steps:int = maxi(1,int(ceil(start.distance_to(end)/2.0)))
		var candidates:Array[Node] = get_tree().get_nodes_in_group("Ball")
		for i:int in range(steps+1):
			var point:Vector2 = start.lerp(end,float(i)/steps)
			for node:Node in candidates:
				if not source.mc_enemy(node) or not source.overlaps_target(node,point,2.5): continue
				if source.mc_live() and not source.dizziness and source.orphaned:
					if source.mc_damage_with_impact(node,damage,point):
						node.apply_knockback(heading,10.0,120.0,0.0,0.0,{"source":source})
				global_position = point
				finish()
				return
		if not wall.is_empty():
			source.play_iron_impact(end)
			finish()
			return
	global_position = end
	remaining -= travel
	if remaining<=0.0: finish()
func finish() -> void:
	if _spent: return
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _finish.rpc()
	else: _finish()
@rpc("authority","call_local","reliable")
func _finish() -> void:
	_spent = true
	queue_free()
