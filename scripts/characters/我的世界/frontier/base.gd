extends "res://scripts/characters/我的世界/new5/base.gd"
## Shared presentation only. Damage, control and healing remain in ball's public pipeline.
const FRONTIER_FX = preload("res://scripts/characters/我的世界/frontier/fx.gd")
const FRONTIER_AUDIO = preload("res://scripts/characters/我的世界/frontier/audio.gd")
var frontier_fx:Node2D
var _frontier_event_id:int = 0
var _last_frontier_event:int = 0
var _status_text:String = ""
var _cue_players:Array[AudioStreamPlayer2D] = []
func role_key() -> String: return ""
func _ready() -> void:
	super._ready()
	# Keep the body above its own absolute-z ground tiles, below foreground FX/UI.
	image.z_as_relative = false
	image.z_index = 3
	frontier_fx = FRONTIER_FX.new()
	frontier_fx.actor = self
	add_child(frontier_fx)
func foes(point:Vector2,reach:float) -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if U.enemy(self,node) and point.distance_squared_to(ball.body_point(node,point)) <= reach*reach:
			result.append(node as ball)
	return result
func floor_clear(point:Vector2,radius_value:float = 8.0) -> bool:
	if not is_inside_tree(): return false
	var shape := CircleShape2D.new()
	shape.radius = maxf(radius_value,1.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,point)
	query.collision_mask = 1
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
func state_label(text:String,color:Color) -> void:
	if text == _status_text: return
	_status_text = text
	side_status_set_permanent("left","mc_frontier",text,color)
func english() -> bool: return str(Game.current_locale).begins_with("en")
func cue(event:String,volume_db:float = -7.0) -> void:
	if not is_multiplayer_authority(): return
	if multiplayer.has_multiplayer_peer(): _frontier_cue.rpc(event,global_position,volume_db)
	_frontier_cue(event,global_position,volume_db)
@rpc("authority","call_remote","reliable")
func _frontier_cue(event:String,point:Vector2,volume_db:float) -> void:
	var player:AudioStreamPlayer2D = FRONTIER_AUDIO.play(self,event,point,volume_db)
	if is_instance_valid(player): _cue_players.append(player)
func emit_effect(kind:String,point:Vector2,end_point:Vector2 = Vector2.ZERO) -> void:
	if not is_multiplayer_authority(): return
	_frontier_event_id += 1
	if multiplayer.has_multiplayer_peer(): _frontier_effect.rpc(_frontier_event_id,kind,point,end_point)
	_frontier_effect(_frontier_event_id,kind,point,end_point)
@rpc("authority","call_remote","reliable")
func _frontier_effect(id:int,kind:String,point:Vector2,end_point:Vector2) -> void:
	if id <= _last_frontier_event: return
	_last_frontier_event = id
	if is_instance_valid(frontier_fx): frontier_fx.burst(kind,point,end_point)

func _process(delta:float) -> void:
	for i:int in range(_cue_players.size()-1,-1,-1):
		if not is_instance_valid(_cue_players[i]): _cue_players.remove_at(i)
		else: _cue_players[i].stream_paused = not is_combat_runtime_active()
	super._process(delta)
