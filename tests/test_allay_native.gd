extends SceneTree
const ORBIT=preload("res://scripts/characters/我的世界/allay/orbit.gd")
var failures:int=0
var checks:int=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var cloud=ORBIT.new()
	for i:int in range(180): cloud.advance(8,Vector2.ZERO,0,1.0/60.0,46,-0.42)
	var min_x:float=INF
	var max_x:float=-INF
	var min_y:float=INF
	var max_y:float=-INF
	var bounded:bool=true
	for p:Vector2 in cloud.positions:
		min_x=minf(min_x,p.x);max_x=maxf(max_x,p.x)
		min_y=minf(min_y,p.y);max_y=maxf(max_y,p.y)
		bounded=bounded and p.length()<55
	check(bounded,"all blue particles remain in bounded ring, not a train")
	check(min_x< -25 and max_x>25 and min_y< -20 and max_y>15,"blue particles surround all four sides")
	var previous:Vector2=cloud.positions[0]
	cloud.advance(8,Vector2(120,0),0,1.0/60.0,46,-0.42)
	check(cloud.positions[0].distance_to(previous)>0 and cloud.positions[0].distance_to(previous)<20,"sudden turn translates particles gradually, not instantly")
	previous=cloud.positions[0]
	cloud.advance(8,Vector2(-120,0),0,1.0/60.0,46,-0.42)
	check(cloud.positions[0].distance_to(previous)<20,"reversal preserves smooth inertia")
	var survivor:Vector2=cloud.positions[1]
	var phase:float=cloud.phases[1]
	cloud.take_first(Vector2.ZERO)
	check(cloud.positions[0]==survivor and cloud.phases[0]==phase,"consuming one particle keeps all remaining slots stable")
	var saved:Vector2=cloud.positions[0]
	cloud.advance(7,Vector2(100,100),0,0,46,-0.42)
	check(cloud.positions[0]==saved,"paused orbit does not drift")
	var positions:Array[Vector2]=[]
	for fps:int in [30,60,120]:
		var sample=ORBIT.new()
		sample.resize(1,Vector2.ZERO)
		for i:int in range(fps): sample.advance(1,Vector2(40,20),0,1.0/fps,31,0.55)
		positions.append(sample.positions[0])
	check(positions[0].distance_to(positions[1])<0.001 and positions[1].distance_to(positions[2])<0.001,"exponential following independent of frame rate")
	var frames:SpriteFrames=load("res://Images/characters/我的世界/allay/allay.tres")
	check(frames.get_frame_count(&"idle")==32 and frames.get_frame_count(&"fly")==32,"64 frames baked from official model and animation")
	var sounds:Script=load("res://scripts/characters/我的世界/allay/native_sounds.gd")
	for event:String in ["entity.allay.ambient_with_item","entity.allay.ambient_without_item","entity.allay.hurt","entity.allay.death","entity.allay.item_given","entity.allay.item_thrown","block.note_block.harp"]:
		check(sounds.EVENTS.has(event) and sounds.EVENTS[event][0].stream is AudioStreamOggVorbis,"vanilla audio available: "+event)
	check(not FileAccess.file_exists("res://Images/characters/我的世界/allay/allay.svg") and not FileAccess.file_exists("res://Images/characters/我的世界/allay/note.svg"),"hand-drawn replacement textures removed")
	print("ALLAY_NATIVE_TEST checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
