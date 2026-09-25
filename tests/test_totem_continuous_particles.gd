extends SceneTree
var failures:int = 0
var checks:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var script:GDScript = load("res://scripts/effects/我的世界/mc_totem_effect.gd")
	var owner:Node2D = Node2D.new()
	root.add_child(owner)
	owner.position = Vector2(100,100)
	var fx:Node2D = script.new()
	root.add_child(fx)
	fx.setup(owner.position,owner)
	fx.set_process(false)
	check(fx.particles.size() == 88,"bounded 88-particle budget")
	for t:float in [0.3,0.7,1.1,1.5,1.9]:
		fx.advance_visual(t-fx.age)
		var recent:int = 0
		for p:Dictionary in fx.particles:
			if p.started and t-float(p.delay) < 0.12 and p.sprite.visible: recent += 1
		check(recent >= 5,"continuous fresh particles at " + str(t))
	var spark:Dictionary = fx.particles[70]
	var before:Vector2 = spark.sprite.global_position
	owner.position += Vector2(120,30)
	fx.advance_visual(0.0)
	check(spark.sprite.global_position.distance_to(before) < 0.001,"emitted sparks stay world anchored")
	fx.advance_visual(fx.LIFETIME+0.01-fx.age)
	check(not fx.totem_sprite.visible and not fx.is_queued_for_deletion(),"item disappears but falling tail survives")
	var started:int = 0
	for p:Dictionary in fx.particles:
		if p.started: started += 1
	check(started == 88,"all scheduled particles emitted by item expiry")
	var last:Dictionary = fx.particles[87]
	fx.advance_visual(float(last.delay)+float(last.flight)+0.02-fx.age)
	check(last.sprite.visible and absf(last.sprite.global_position.y-float(last.ground_y)) < 0.001,"particle reaches floor before fading")
	var floor_pos:Vector2 = last.sprite.global_position
	fx.advance_visual(0.05)
	check(last.sprite.global_position.distance_to(floor_pos) < 0.001,"landed particle stops rather than falling through floor")
	paused = true
	var age_before:float = fx.age
	fx._process(0.1)
	check(fx.age == age_before,"pause freezes emitter")
	paused = false
	owner.free()
	fx.advance_visual(3.0)
	check(fx.is_queued_for_deletion(),"tail cleans up after owner removal")
	await process_frame
	print("TOTEM_PARTICLES_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
