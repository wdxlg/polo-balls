extends "res://scripts/shooter/knife.gd"
const NATIVE_PATH = "res://.performance_tools/native/knife_native.gdextension"
const META = &"_native_knife_snapshot_factory"
func _spawn_after_image_at_transform(t:Transform2D,d:Vector2) -> void:
	var w:Node = get_tree().current_scene
	if not is_instance_valid(image) or w == null:
		super._spawn_after_image_at_transform(t,d)
		return
	var factory:RefCounted = w.get_meta(META) if w.has_meta(META) else null
	if factory == null:
		if not ClassDB.class_exists("KnifeNativeSnapshots"):
			GDExtensionManager.load_extension(NATIVE_PATH)
		if not ClassDB.class_exists("KnifeNativeSnapshots"):
			super._spawn_after_image_at_transform(t,d)
			return
		factory = ClassDB.instantiate("KnifeNativeSnapshots")
		w.set_meta(META,factory)
	if not factory.spawn(self,image,w,t,d,AFTER_IMAGE_MATERIAL):
		super._spawn_after_image_at_transform(t,d)
