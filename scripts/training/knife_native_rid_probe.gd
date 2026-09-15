extends "res://scripts/shooter/knife.gd"
const NATIVE_PATH = "res://.performance_tools/native/knife_native.gdextension"
const META = &"_native_knife_snapshot_factory"
static func parameters(source:ball,t:Transform2D,d:Vector2) -> Array:
	var colors:Dictionary = source._get_after_image_snapshot_colors(t)
	var local_dir:Vector2 = d if d.length_squared()>0.000001 else Vector2.RIGHT
	local_dir = local_dir.normalized().rotated(-t.get_rotation()).normalized()
	var start:Vector2 = source.AfterImage_Start_Scale
	var finish:Vector2 = source.AfterImage_End_Scale
	return [source._after_image_transform_for_texture(t,source.image.texture),local_dir,
		maxf(source.AfterImage_Lifetime,0.05),
		Vector2(maxf(absf(start.x),0.01),maxf(absf(start.y),0.01)),
		Vector2(maxf(absf(finish.x),0.01),maxf(absf(finish.y),0.01)),
		1.0 if source._visual_facing_flipped_h else 0.0,
		colors.get("start",source.AfterImage_Tint),colors.get("end",source.AfterImage_End_Tint),
		Vector4(source.AfterImage_Alpha,source.AfterImage_End_Alpha,source.AfterImage_Blur_Pixels,source.AfterImage_End_Blur_Pixels),
		Vector4(source.AfterImage_Smear_Pixels,source.AfterImage_End_Smear_Pixels,source.AfterImage_Distortion_Pixels,source.AfterImage_End_Distortion_Pixels),
		int(source.AfterImage_Style),clampi(source.AfterImage_Sample_Count,1,16),int(source.AfterImage_Fade)]
func _spawn_after_image_at_transform(t:Transform2D,d:Vector2) -> void:
	# SceneTree captures the last Tween at phase entry. A new Tween created from
	# another idle Tween must wait until next frame; do not batch those callers.
	if not Engine.is_in_physics_frame():
		super._spawn_after_image_at_transform(t,d)
		return
	var w:Node = get_tree().current_scene
	if not is_instance_valid(image) or not image is Sprite2D or not w is Node2D or AfterImage_Texture_Source != 0:
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
	if factory.can_spawn_rid(image,w):
		if factory.spawn_rid(self,image,w,parameters(self,t,d),AFTER_IMAGE_MATERIAL):
			return
	super._spawn_after_image_at_transform(t,d)
