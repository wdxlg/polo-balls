extends "res://scripts/effects/我的世界/重锤落地冲击.gd"
## Reuse the mace's real-floor sampling and ballistic square chips, without its impact ring/rays.
var actor:Node2D
var emerging:bool=true
var emission_duration:float=3.0
func start(owner_actor:Node2D,point:Vector2,is_emerging:bool,duration:float) -> void:
	actor=owner_actor
	emerging=is_emerging
	emission_duration=maxf(duration,0.1)
	add_to_group("MCWardenGroundDebris")
	add_to_group("BattleTransient")
	top_level=true
	global_scale=Vector2.ONE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	block_source_min_count=8; block_source_max_count=8
	blocks_per_source_min=8; blocks_per_source_max=8
	block_min_height=13.0 if emerging else 2.0
	block_max_height=42.0 if emerging else 8.0
	block_min_flight_time=0.34 if emerging else 0.18
	block_max_flight_time=0.68 if emerging else 0.32
	block_min_ground_hold=0.08
	block_max_ground_hold=0.25
	await super.setup(point,22.0)
	if is_inside_tree(): z_index=4
func _build_block_particles() -> void:
	super._build_block_particles()
	_effect_end_time=0.0
	for i:int in range(_blocks.size()):
		var block:Dictionary=_blocks[i]
		# Initial upward burst plus continuing earth chips during the climb.
		# Burrowing continuously sends out low chips across the entire animation.
		block.delay=_rng.randf_range(0.0,0.06) if emerging and i<12 else float(i)/maxf(float(_blocks.size()-1),1.0)*maxf(0.0,emission_duration-0.1)
		_effect_end_time=maxf(_effect_end_time,float(block.delay)+float(block.flight)+float(block.hold)+float(block.fade))
func _process(delta:float) -> void:
	if not is_instance_valid(actor) or actor.health<=0 or actor.is_queued_for_deletion():
		queue_free()
		return
	if not actor.is_combat_runtime_active() or Game.now_stop_state or get_tree().paused: return
	super._process(delta)
func _draw() -> void:
	_draw_block_particles()
