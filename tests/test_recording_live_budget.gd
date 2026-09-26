extends SceneTree
## Headless lifecycle checks; actual foreground/GPU throughput uses the editor fixture.
var checks:int = 0
var failures:int = 0

func check(value:bool, message:String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS: " if value else "FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original_fps:int = Engine.max_fps
	var original_scale:float = Engine.time_scale
	var original_physics:int = Engine.physics_ticks_per_second
	var script:Script = load("res://scripts/ui/battle_recorder.gd")
	var recorder:Node = script.new()
	check(recorder._live_saved_max_fps == -1, "idle has no render-budget ownership")
	Engine.max_fps = 0
	recorder._acquire_live_render_budget()
	check(Engine.max_fps == 60, "uncapped LIVE rendering is paced at output rate")
	recorder._acquire_live_render_budget()
	check(recorder._live_saved_max_fps == 0, "repeated acquire never replaces the original limit")
	check(Engine.time_scale == original_scale and Engine.physics_ticks_per_second == original_physics, "render pacing does not change battle speed or physics frequency")
	recorder._release_live_render_budget()
	check(Engine.max_fps == 0, "uncapped policy restored")
	recorder._release_live_render_budget()
	check(Engine.max_fps == 0, "repeated release is harmless")
	Engine.max_fps = 144
	recorder._acquire_live_render_budget()
	check(Engine.max_fps == 60, "higher display limit yields encoding headroom")
	recorder._release_live_render_budget()
	check(Engine.max_fps == 144, "higher original limit restored")
	Engine.max_fps = 30
	recorder._acquire_live_render_budget()
	check(Engine.max_fps == 30, "an existing lower limit is not raised")
	recorder._release_live_render_budget()
	check(Engine.max_fps == 30, "lower limit preserved on release")
	Engine.max_fps = 144
	recorder._acquire_live_render_budget()
	Engine.max_fps = 45
	recorder._release_live_render_budget()
	check(Engine.max_fps == 45, "another owner's later runtime change is not overwritten")
	var variant:Node = script.new()
	variant._is_variant = true
	Engine.max_fps = 120
	variant._acquire_live_render_budget()
	check(Engine.max_fps == 120 and variant._live_saved_max_fps == -1, "English variant cannot take ownership")
	variant.free()
	Engine.max_fps = 144
	check(not recorder.start_live(), "headless startup failure remains explicit")
	check(Engine.max_fps == 144 and recorder._live_saved_max_fps == -1, "failed startup restores the render limit")
	root.add_child(recorder)
	recorder._acquire_live_render_budget()
	check(Engine.max_fps == 60, "tree-owned recorder acquires budget")
	var idle:Node = script.new()
	idle._release_live_render_budget()
	idle.free()
	check(Engine.max_fps == 60, "unrelated idle instance does not release the active budget")
	recorder.free()
	check(Engine.max_fps == 144, "scene exit releases an active budget")
	Engine.max_fps = original_fps
	print("LIVE_BUDGET_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
