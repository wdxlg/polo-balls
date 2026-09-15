extends ball

const SNAPSHOT_BATCH = preload("res://classes/after_image_render_batch.gd")
# Keep the original path available for visual comparisons and unusual scenes.
@export var batch_after_image_snapshots:bool = true

func _spawn_after_image_at_transform(ghost_transform:Transform2D,world_trail_dir:Vector2) -> void:
	# A snapshot born inside a SceneTree tween callback must not be advanced by
	# an older renderer tween later in that same phase. Keep that rare path native.
	if batch_after_image_snapshots and Engine.is_in_physics_frame() and SNAPSHOT_BATCH.try_spawn(self,ghost_transform,world_trail_dir,AFTER_IMAGE_MATERIAL):
		return
	super._spawn_after_image_at_transform(ghost_transform,world_trail_dir)

func move(speed:float,delta:float):
	super(speed,delta)

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	
	if not is_multiplayer_authority():return
	state_machine.current_state = State.Die
func when_collide(_speed:float,_collision:KinematicCollision2D):
	if not is_multiplayer_authority():return
	
	if Collide_Audio != "":
		Audios.play_sfx(Collide_Audio ,{},true)
	
	Speed = 0
	direction = Vector2.ZERO
	
	if collide_tween:collide_tween.kill()
	
	state_machine.current_state = State.Die
	
func Die() -> void:
	if not is_multiplayer_authority():return
	image.visible = false
	
	await get_tree().create_timer(0.1).timeout
	Game.free_node(self)
