extends SceneTree
func _initialize() -> void:
	var d:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/training/benchmark_native_profile_current.json"))
	var f:Array = d["frames"][60]
	print("size=",f.size())
	for i in range(mini(60,f.size())):
		print(i,": ",str(f[i]).left(60))
	var sig:Dictionary = d["signatures"]
	var ks:Array = sig.keys()
	for i in range(5): print(ks[i]," => ",sig[ks[i]])
	quit()
