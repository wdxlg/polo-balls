extends SceneTree
## Fast, no-world contract check for configurable obstacles and reusable script imports.
const PROFILE = preload("res://scripts/effects/我的世界/mc_obstacle_properties.gd")
var failures:int = 0
func check(ok:bool,label:String) -> void:
	if not ok: failures+=1; push_error("REUSE FAIL: "+label)
	else: print("REUSE PASS: "+label)

func _initialize() -> void:
	check(PROFILE!=null,"common obstacle properties parse")
	if PROFILE!=null:
		var obstacle:StaticBody2D = StaticBody2D.new()
		var property_node:Node = PROFILE.new()
		property_node.name="MCObstacleProperties"
		obstacle.add_child(property_node)
		check(PROFILE.can_break(obstacle) and is_equal_approx(PROFILE.progress_per_blast(obstacle),34.0),"default obstacle is breakable in three blasts")
		property_node.set("blast_step",20.0)
		property_node.set("crack_thresholds",PackedFloat32Array([20.0,60.0]))
		check(is_equal_approx(PROFILE.progress_per_blast(obstacle),20.0) and PROFILE.crack_index(obstacle,40.0)==0 and PROFILE.crack_index(obstacle,60.0)==1,"configurable 0-100 progression and native crack thresholds")
		property_node.set("destructible",false)
		check(not PROFILE.can_break(obstacle),"explicit obstacle immunity respected")
		property_node.set("destructible",true)
		obstacle.set_meta("mc_obstacle_blast_step",50.0)
		check(is_equal_approx(PROFILE.progress_per_blast(obstacle),50.0),"metadata override respected")
		obstacle.free()
	for path:String in ["res://scripts/effects/我的世界/ghast_obstacle_damage.gd","res://scripts/effects/physical_airborne_effect.gd","res://scripts/effects/我的世界/重锤落地冲击.gd","res://scripts/effects/我的世界/mc_combat_abilities.gd"]:
		check(load(path)!=null,path.get_file()+" parses")
	print("REUSE SMOKE FAILURES: ",failures)
	quit(1 if failures>0 else 0)
