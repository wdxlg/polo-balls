extends SceneTree
func _initialize() -> void:
	var paths:Array[String]=["res://scripts/effects/我的世界/pixel_arc.gd","res://scripts/characters/我的世界/cactus_note/note_wave.gd"]
	var failures:int=0
	for path:String in paths:
		var script:Script=load(path)
		if script==null or not script.can_instantiate(): failures+=1
	print("PIXEL_ARC_COMPILE checks=2 failures=",failures)
	quit(0 if failures==0 else 1)
