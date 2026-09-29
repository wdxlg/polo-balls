extends RefCounted
# Short animation tests can finish while World's asynchronous character loads
# are still compiling. Drain those requests before teardown, not during shutdown.
static func wait_for_preloads(tree:SceneTree) -> bool:
	var prewarm:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	var deadline:int = Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		var pending:bool = false
		for character:String in prewarm.CHARACTERS:
			var path:String = "res://scenes/characters/我的世界/"+character+".tscn"
			if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pending = true
				break
		if not pending: return true
		await tree.process_frame
	push_error("Timed out draining World character preloads before test teardown")
	return false
