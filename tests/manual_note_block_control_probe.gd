extends "res://scripts/characters/我的世界/cactus_note/note_block.gd"
## Dispatch and disc lifecycle only; audio resources are not initialized here.
var started_tracks:Array[int] = []
func _ready() -> void: pass
func can_act() -> bool: return true
func start_track(index:int,_at:float = 0.0) -> void:
	started_tracks.append(index)
	record_phase=0
