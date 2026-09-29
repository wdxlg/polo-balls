extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for role:String in ["史莱姆","守卫者","恶魂","粘性活塞","钓鱼竿"]:
  var scene:PackedScene=load("res://scenes/characters/我的世界/"+role+".tscn")
  if scene!=null:
   var unit:Node=scene.instantiate()
   print("NEW5_LOAD ",role," ",unit.get_script().can_instantiate())
   unit.free()
 quit()
