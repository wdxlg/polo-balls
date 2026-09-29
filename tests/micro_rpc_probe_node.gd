extends Node
@rpc("any_peer","call_local")
func noop(_a:String,_b:Dictionary = {},_c:bool = false) -> void:
	pass
@rpc("any_peer","call_local")
func noop_vec(_a:Vector2,_b:int) -> void:
	pass
@rpc("any_peer","call_local","unreliable")
func noop_vec_unreliable(_a:Vector2,_b:int) -> void:
	pass
