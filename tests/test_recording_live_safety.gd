extends SceneTree
const Writer = preload("res://scripts/ui/battle_record_writer.gd")
var checks:int=0
var failures:int=0
func check(value:bool,message:String) -> void:
	checks+=1
	if not value: failures+=1
	print("PASS: " if value else "FAIL: ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var recorder:Node=load("res://scripts/ui/battle_recorder.gd").new()
	check(not recorder.is_preparing(),"idle recorder is not preparing")
	recorder._live_preparing=true
	check(recorder.is_preparing() and recorder.get_pause_reason().contains("准备"),"preparation is explicitly observable")
	recorder._live_preparing=false
	var controls_script:=GDScript.new()
	controls_script.source_code="extends \"res://scripts/ui/battle_record_controls.gd\"\nfunc refresh() -> void: pass\nfunc _show_message(message:String) -> void: last_message=message\n"
	if controls_script.reload()!=OK: quit(2); return
	var controls:Node=controls_script.new()
	controls.recorder=recorder
	controls.english_path=LineEdit.new()
	recorder.last_outputs={"zh":"zh.mp4","en":"en.mp4"}
	recorder._last_error="编码速度跟不上：录制缓存已满"
	controls._on_finished("zh.mp4",36)
	check(controls.last_message.begins_with("录制中断") and controls.last_message.contains("不是完整对局"),"partial output is never presented as complete")
	check(controls.last_output=="zh.mp4" and controls.english_path.text=="en.mp4","partial output paths remain recoverable")
	recorder._last_error=""
	controls._on_finished("zh.mp4",6000)
	check(controls.last_message.begins_with("已保存"),"successful recording still reports saved")
	recorder._last_error="首帧失败"
	controls._on_finished("",0)
	check(controls.last_message=="录制未完成：首帧失败","no-frame failure preserves its reason")
	check(Writer.MAX_BYTES==256*1024*1024 and Writer.MAX_FRAMES==120,"both queue limits remain unchanged")
	var writer:RefCounted=Writer.new() # No worker: deterministic stalled sink.
	check(writer.enqueue(PackedByteArray([1]),120),"bounded queue accepts its exact frame capacity")
	check(not writer.can_accept(1,1),"backpressure detects frame saturation")
	check(not writer.enqueue(PackedByteArray([2]),1) and not writer.get_error().is_empty(),"real overflow still fails explicitly, without dropping frames")
	check(writer._jobs.size()==1 and writer._frames==120,"overflow never appends or replaces earlier frames")
	writer=Writer.new()
	writer._bytes=Writer.MAX_BYTES
	check(not writer.enqueue(PackedByteArray([3]),1),"byte-cap protection remains active")
	controls.english_path.free()
	controls.free()
	recorder.free()
	print("LIVE_SAFETY_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
