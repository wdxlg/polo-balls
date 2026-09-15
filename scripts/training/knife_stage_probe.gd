extends "res://scripts/shooter/knife.gd"
static var profile_us:Dictionary = {}
static var profile_calls:Dictionary = {}

func tick_physics(state:State,delta:float) -> void:
	var started:int = Time.get_ticks_usec()
	super.tick_physics(state,delta)
	profile_us["tick_physics"] = int(profile_us.get("tick_physics",0)) + Time.get_ticks_usec() - started
	profile_calls["tick_physics"] = int(profile_calls.get("tick_physics",0)) + 1

func _process_auto_after_image(delta:float) -> void:
	var started:int = Time.get_ticks_usec()
	super._process_auto_after_image(delta)
	profile_us["_process_auto_after_image"] = int(profile_us.get("_process_auto_after_image",0)) + Time.get_ticks_usec() - started
	profile_calls["_process_auto_after_image"] = int(profile_calls.get("_process_auto_after_image",0)) + 1

func _spawn_after_image_at_transform(ghost_transform:Transform2D,world_trail_dir:Vector2) -> void:
	var started:int = Time.get_ticks_usec()
	super._spawn_after_image_at_transform(ghost_transform,world_trail_dir)
	profile_us["_spawn_after_image_at_transform"] = int(profile_us.get("_spawn_after_image_at_transform",0)) + Time.get_ticks_usec() - started
	profile_calls["_spawn_after_image_at_transform"] = int(profile_calls.get("_spawn_after_image_at_transform",0)) + 1

func get_next_state(state:State) -> int:
	var started:int = Time.get_ticks_usec()
	var result:int = super.get_next_state(state)
	profile_us["get_next_state"] = int(profile_us.get("get_next_state",0)) + Time.get_ticks_usec() - started
	profile_calls["get_next_state"] = int(profile_calls.get("get_next_state",0)) + 1
	return result

func move(speed:float,delta:float) -> void:
	var started:int = Time.get_ticks_usec()
	super.move(speed,delta)
	profile_us["move"] = int(profile_us.get("move",0)) + Time.get_ticks_usec() - started
	profile_calls["move"] = int(profile_calls.get("move",0)) + 1

func _ready() -> void:
	var started:int = Time.get_ticks_usec()
	super._ready()
	profile_us["_ready"] = int(profile_us.get("_ready",0)) + Time.get_ticks_usec() - started
	profile_calls["_ready"] = int(profile_calls.get("_ready",0)) + 1

func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	var started:int = Time.get_ticks_usec()
	super._on_hitbox_on_hit(hurt)
	profile_us["hit_callback"] = int(profile_us.get("hit_callback",0)) + Time.get_ticks_usec() - started
	profile_calls["hit_callback"] = int(profile_calls.get("hit_callback",0)) + 1
