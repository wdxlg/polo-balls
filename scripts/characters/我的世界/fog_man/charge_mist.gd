extends Node2D
## World-space textured mist replaces the complete actor/HUD during a rage rush.
var actor:Node2D
var motes:Array[Dictionary] = []
var time:float = 0.0
var spawn_left:float = 0.0
var textures:Array[Texture2D] = []
var face_tex:Texture2D = null
func _self_foot_world_position() -> Vector2:
	return actor._self_foot_world_position() if is_instance_valid(actor) else global_position
func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 97
	for i:int in range(4): textures.append(load("res://Images/characters/我的世界/fog_man/cloud_%d.png" % i))
func _process(delta:float) -> void:
	if not is_instance_valid(actor): queue_free(); return
	if not actor.is_combat_runtime_active(): return
	time += delta
	for i:int in range(motes.size()-1,-1,-1):
		motes[i].age += delta
		if motes[i].age>=0.32: motes.remove_at(i)
	if actor.phase==actor.Phase.VANISHED or actor.is_face_hidden(): motes.clear()
	if actor.is_rush_mist():
		spawn_left -= delta
		if spawn_left<=0.0:
			spawn_left = 0.035
			if motes.size()>=12: motes.pop_front()
			motes.append({"point":actor.global_position,"age":0.0,"frame":int(time*24.0)%4})
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(actor): return
	for mote:Dictionary in motes:
		var progress:float = mote.age/0.32
		var size:Vector2 = Vector2(65,50)*(1.0+progress*0.65)
		draw_texture_rect(textures[mote.frame],Rect2(mote.point-size*0.5,size),false,Color(0.77,0.86,0.91,(1.0-progress)*0.6))
	if actor.phase==actor.Phase.RAGE and actor.rush==actor.Rush.FACE_SHOW:
		# Reuse the body SpriteFrames already preloaded by the actor; a direct PNG load can fail.
		if face_tex==null and is_instance_valid(actor): face_tex = actor.BODY.get_frame_texture(&"idle",0)
		if face_tex!=null:
			var t:float = clampf((0.28-actor.rush_left)/0.28,0.0,1.0)
			for i:int in range(8):
				var offset:Vector2 = Vector2.RIGHT.rotated(TAU*i/8.0)*(12.0+t*34.0)
				draw_texture_rect(textures[i%4],Rect2(actor.face_point+offset-Vector2(26,20),Vector2(52,40)),false,Color(0.85,0.89,0.94,0.45*(1.0-t)))
			# Frames may be atlas regions of a sprite sheet: crop the head relative to the frame rect.
			var frame_size:Vector2 = face_tex.get_size()
			var crop:Rect2 = Rect2(frame_size.x*0.328,frame_size.y*0.234,frame_size.x*0.328,frame_size.y*0.25)
			var source:Texture2D = face_tex
			if face_tex is AtlasTexture:
				source = (face_tex as AtlasTexture).atlas
				crop.position += (face_tex as AtlasTexture).region.position
			var head_size:Vector2 = crop.size*(0.98+0.06*sin(t*PI))
			var head:Rect2 = Rect2(actor.face_point-Vector2(head_size.x*0.5,head_size.y*1.1),head_size)
			draw_texture_rect_region(source,head,crop,Color(1.15,1.15,1.15,1.0-t*0.2))
		return
	if not actor.is_rush_mist(): return
	for i:int in range(5):
		var offset := Vector2(sin(time*5.0+i*2.1)*12.0,cos(time*4.0+i*1.7)*16.0)
		var size := Vector2(80,65)*(1.0+0.1*sin(time*6.0+i))
		draw_texture_rect(textures[i%4],Rect2(actor.global_position+offset-size*0.5,size),false,Color(0.82,0.89,0.94,0.8))
