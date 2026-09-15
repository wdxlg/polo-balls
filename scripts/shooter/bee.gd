extends ball

#引用

func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	super(hurt)
	
	state_machine.current_state = State.Die
func when_collide(_speed:float,_collision:KinematicCollision2D):
	if Collide_Audio != "":
		Audios.play_sfx(Collide_Audio ,{},true)
	
	state_machine.current_state = State.Die
	
func Die() -> void:
	Game.free_node(self)

var p0:Vector2
var p1:Vector2
var p2:Vector2
var curve:Curve2D
var length:float
var progress:float
func _ready() -> void:
	super()
	
	get_tree().current_scene.create_new_particle("Bee_Follow",self)
	get_tree().current_scene.create_new_particle("Bee_Stand",self)
	
	var enemy = Target_Enemy
	
	if enemy:
		var target_position = combat_target_position(enemy) + Vector2(randf_range(-10,10),randf_range(-10,10))
		
		p0 = global_position
		p1 = (global_position + target_position)  * randf_range(0.4,0.6) + Vector2(-(global_position - target_position).y,(global_position - target_position).x) * randf_range(-1,1)
		p2 = combat_target_position(enemy)
		
		curve = Curve2D.new()
		curve.add_point(p0,Vector2.ZERO,p1 - p0)
		curve.add_point(p2,p2 - p1,Vector2.ZERO)
		
		length = curve.get_baked_length()
func tick_physics(state:State,delta:float) -> void:
	super(state,delta)

	progress += Speed * delta
	if curve:
		direction = curve.sample_baked_with_rotation(progress,true).x
		global_rotation = Default_Rotation + direction.angle()
	if progress >= length and curve:curve = null
