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
	recorder._note_live_issue("slow","对战运行曾明显变慢。")
	recorder._note_live_issue("slow","对战运行曾明显变慢。")
	check(controls.last_message.begins_with("已保存") and not controls.last_message.contains("变慢"),"warnings never interrupt the UI while recording")
	controls._on_finished("zh.mp4",6000)
	check(controls.last_message.begins_with("已保存") and controls.last_message.contains("本次录制提示") and controls.last_message.contains("2 次"),"saved output includes aggregated quality warnings, not interruption")
	check(recorder.get_last_error().is_empty() and not recorder._timing_invalid,"quality warnings do not invalidate the saved movie")
	recorder._live_issues.clear()
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
	await recovery_cases(recorder)
	controls.english_path.free()
	controls.free()
	recorder.free()
	print("LIVE_SAFETY_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func recovery_cases(recorder:Node) -> void:
	recorder._last_error=""
	recorder.mode=recorder.Mode.LIVE
	recorder._capture_size=Vector2i(1,1)
	recorder._secondary=load("res://scripts/ui/battle_recorder.gd").new()
	recorder._secondary._capture_size=Vector2i(1,1)
	recorder._writer=Writer.new()
	recorder._secondary._writer=Writer.new()
	var zh:PackedByteArray=PackedByteArray([1,0,0,255])
	var en:PackedByteArray=PackedByteArray([2,0,0,255])
	var newer:PackedByteArray=PackedByteArray([3,0,0,255])
	recorder._write_live_pair(zh,en,120)
	for index:int in 1000: recorder._write_live_pair(newer,newer,60)
	check(recorder.is_recording() and recorder.get_last_error().is_empty(),"sustained live backpressure does not stop recording")
	check(recorder._writer._jobs.size()==1 and recorder._secondary._writer._jobs.size()==1,"1000 congested captures retain only one job per language")
	check(recorder._writer._bytes==4 and recorder._secondary._writer._bytes==4,"repeated duration does not grow raw-frame memory")
	check(recorder._writer._jobs[0].data==zh and recorder._secondary._writer._jobs[0].data==en,"both languages hold the same accepted capture")
	check(recorder._frame_index==60120 and recorder._secondary._frame_index==60120 and recorder._writer._frames==60120,"congestion preserves every timeline tick in both movies")
	check(recorder._live_issues.encoder.count==1000 and recorder._live_issues.size()==1,"warning storage is bounded by issue types")
	var folder:String=OS.get_cache_dir().path_join("polo_live_writer_"+str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(folder)
	var outputs:Array=[recorder,recorder._secondary]
	for index:int in outputs.size():
		check(outputs[index]._writer.begin(FileAccess.open(folder.path_join(str(index)+".rgba"),FileAccess.WRITE)),"start real file writer to drain repeat metadata")
	var deadline:int=Time.get_ticks_msec()+10000
	while (not recorder._writer.can_accept(8,1) or not recorder._secondary._writer.can_accept(8,1)) and Time.get_ticks_msec()<deadline: await process_frame
	check(recorder._writer.get_frames_written()==60120 and recorder._secondary._writer.get_frames_written()==60120,"worker expands all repeats to physical frames")
	recorder._write_live_pair(newer,en,1)
	check(recorder._previous_image==newer and recorder._writer._last_live_data==newer,"new motion resumes when the encoder catches up")
	var incomplete:Dictionary={"zh":newer,"en":PackedByteArray(),"zh_done":true,"en_done":false,"wanted":3,"since":0}
	recorder._live_pending.append(incomplete)
	recorder._frame_index+=3
	recorder._secondary._frame_index+=3
	recorder._flush_live_pending(true)
	check(recorder.is_recording() and recorder._live_pending.is_empty() and recorder._live_async_disabled,"readback timeout recovers and enables synchronous fallback")
	check(recorder._frame_index==60124 and recorder._secondary._frame_index==60124,"reserved readback frames are neither lost nor double-counted")
	recorder._on_live_readback(en,incomplete,"en")
	check(recorder._frame_index==60124 and recorder._live_pending.is_empty(),"late GPU callback cannot append already recovered frames")
	recorder._write_live_pair(PackedByteArray(),en,2)
	check(recorder.is_recording() and recorder._previous_image==newer and recorder._previous_secondary_image==en,"incomplete bilingual capture repeats the last valid pair")
	for index:int in outputs.size():
		var w:RefCounted=outputs[index]._writer
		w.close_when_empty()
		w.join()
		var file:FileAccess=FileAccess.open(folder.path_join(str(index)+".rgba"),FileAccess.READ)
		check(w.get_frames_written()==60126 and file.get_length()==60126*4,"saved bytes match the full bilingual timeline")
		file.close()
		DirAccess.remove_absolute(folder.path_join(str(index)+".rgba"))
		outputs[index]._writer=null
	var audio:RefCounted=load("res://scripts/ui/battle_record_audio.gd").new()
	audio.file=FileAccess.open(folder.path_join("silence.f32"),FileAccess.WRITE)
	audio.write_silence(5000)
	audio.finish()
	var pcm:FileAccess=FileAccess.open(folder.path_join("silence.f32"),FileAccess.READ)
	var samples:PackedFloat32Array=pcm.get_buffer(pcm.get_length()).to_float32_array()
	check(samples.size()==10000 and audio.samples_written==5000 and samples.count(0.0)==10000,"missing stereo audio is padded in bounded zero-filled chunks")
	pcm.close()
	DirAccess.remove_absolute(folder.path_join("silence.f32"))
	DirAccess.remove_absolute(folder)
	# Byte backpressure must recover before the 120-frame threshold is reached.
	recorder._writer=Writer.new()
	recorder._secondary._writer=Writer.new()
	recorder._capture_size=Vector2i(1024,1024)
	recorder._previous_image=PackedByteArray()
	recorder._previous_secondary_image=PackedByteArray()
	var large_zh:PackedByteArray=PackedByteArray()
	large_zh.resize(1024*1024*4)
	var large_en:PackedByteArray=large_zh.duplicate()
	large_zh[0]=1
	large_en[0]=2
	for index:int in 64: recorder._write_live_pair(large_zh,large_en,1)
	check(recorder.is_recording() and recorder._writer._jobs.size()<64 and recorder._writer._frames==64,"LIVE byte saturation holds frames without poisoning the writer")
	check(recorder._writer.peak_bytes<=Writer.MAX_BYTES and recorder._secondary._writer.peak_bytes<=Writer.MAX_BYTES,"LIVE raw-byte caps remain enforced independently of duration metadata")
	recorder._writer._error="模拟写入失败"
	recorder._write_live_pair(large_zh,large_en,1)
	check(not recorder.is_recording() and recorder.get_last_error().contains("模拟写入失败"),"unrecoverable write failure is not disguised as healthy recording")
	recorder._writer=null
	recorder._secondary._writer=null
	recorder.mode=recorder.Mode.IDLE
	recorder._secondary.free()
	recorder._secondary=null
	if DisplayServer.get_name()=="headless":
		recorder._begin_session(60.0,"live")
		check(recorder.get_recording_warnings().is_empty() and not recorder._live_async_disabled,"new sessions clear previous quality warnings and fallback state")
