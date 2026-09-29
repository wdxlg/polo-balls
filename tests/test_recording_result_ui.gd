extends SceneTree
## Real embedded Window layout/render checks at physical game-window sizes.
var checks:int = 0
var failures:int = 0
var controls:Node
var evidence:String
var rows:Array = []
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
 checks+=1
 if not ok: failures+=1
 print(("PASS: " if ok else "FAIL: ")+label)
func wait_frames(n:int = 4) -> void:
 for i:int in range(n): await process_frame
func click_control(control:Control) -> void:
 var pos:Vector2 = Vector2(controls.result_dialog.position) + control.get_global_transform_with_canvas() * (control.size*0.5)
 var motion:=InputEventMouseMotion.new()
 motion.position = pos
 motion.global_position = pos
 root.push_input(motion,true)
 await process_frame
 for down:bool in [true,false]:
  var ev:=InputEventMouseButton.new()
  ev.position = pos
  ev.global_position = pos
  ev.button_index = MOUSE_BUTTON_LEFT
  ev.pressed = down
  root.push_input(ev,true)
  await process_frame
func run() -> void:
 evidence = OS.get_environment("RECORDING_UI_EVIDENCE_DIR")
 DirAccess.make_dir_recursive_absolute(evidence)
 create_timer(70.0,true,false,true).timeout.connect(func(): print("UI_TIMEOUT"); quit(2))
 var game:Node = root.get_node("Game")
 root.gui_embed_subwindows = true
 root.content_scale_size = Vector2i(1080,1920)
 root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
 var host:=Control.new()
 root.add_child(host)
 var trigger:=Button.new()
 host.add_child(trigger)
 controls = load("res://scripts/ui/battle_record_controls.gd").new()
 host.add_child(controls)
 controls.setup(trigger)
 var output:String = "C:/Godot/recordings/"+"目录较长 Long folder/".repeat(4)+"3个钻石剑 vs 2个木剑.mp4"
 for size:Vector2i in [Vector2i(540,960),Vector2i(320,480),Vector2i(1280,720)]:
  root.size = size
  await wait_frames()
  for locale:String in ["zh","en"]:
   game.current_locale = locale
   controls.recorder.last_outputs = {"zh":output,"en":output.get_base_dir()+"/Diamond Sword ＊ 3 vs Wooden Sword ＊ 2.mp4"}
   controls.recorder._last_error = ""
   controls._on_finished(output,600)
   await wait_frames(8)
   var scale:Vector2 = root.get_stretch_transform().get_scale().abs()
   var usable:Vector2 = root.get_visible_rect().size
   var dialog:AcceptDialog = controls.result_dialog
   var pixels:Vector2 = Vector2(dialog.size)*scale
   check(dialog.is_embedded(),"embedded popup uses game canvas")
   check((Vector2(dialog.position)+Vector2(dialog.size)*0.5-usable*0.5).length()<2.0,"popup is centered in logical viewport, not desktop pixels")
   check(pixels.y>=minf(559.0,usable.y*scale.y-81.0),"popup uses the intended physical height without desktop-pixel clamping")
   check(dialog.size.x<=usable.x and dialog.size.y+40.0/scale.y<=usable.y,"popup fits visible game viewport "+str(size)+locale)
   check(pixels.x>=minf(float(size.x)-40.0,usable.x*scale.x-40.0),"popup uses the available physical width")
   check(controls.message_label.get_theme_font_size("font_size")*scale.y>=19.9,"body text is at least 20 physical pixels")
   check(dialog.get_ok_button().size.y*scale.y>=47.9,"buttons are at least 48 physical pixels high")
   check(controls.output_path.text==output and not controls.output_path.editable,"long Chinese path preserved and readonly")
   check(controls.english_path.visible and controls.english_path.text==controls.recorder.last_outputs.en,"separate literal English path preserved")
   check(dialog.get_ok_button().get_global_rect().end.y<=dialog.size.y,"OK stays reachable below scrollable body")
   check(controls.result_scroll.size.x<=dialog.size.x,"scroll body stays within popup")
   var slug:String = "%dx%d_%s"%[size.x,size.y,locale]
   rows.append({"case":slug,"window":str(root.size),"visible_rect":str(root.get_visible_rect()),"stretch":str(scale),"popup":str(dialog.size),"physical_popup":str(pixels),"body_physical_font":controls.message_label.get_theme_font_size("font_size")*scale.y})
   await RenderingServer.frame_post_draw
   check(root.get_texture().get_image().save_png(evidence.path_join(slug+".png"))==OK,"real rendered screenshot "+slug)
   paused = true
   controls.output_path.select_all()
   check(controls.output_path.get_selected_text()==output,"path can be selected while game is paused")
   await click_control(dialog.get_ok_button())
   check(not dialog.visible,"mouse OK dismisses the popup while paused")
   controls._on_finished(output,600)
   await wait_frames()
   if dialog.visible:
    dialog.get_ok_button().grab_focus()
    for down:bool in [true,false]:
     var key:=InputEventAction.new()
     key.action = &"ui_accept"
     key.pressed = down
     dialog.push_input(key,true)
     await process_frame
   check(not dialog.visible,"keyboard OK dismisses the popup while paused")
   paused = false
 root.size = Vector2i(540,960)
 game.current_locale = "zh"
 await wait_frames()
 controls.recorder._last_error = "编码器异常："+"可读错误说明，保留输出文件。".repeat(40)
 controls.recorder.last_outputs = {}
 controls._on_finished("",0)
 await wait_frames(8)
 check(controls.last_message.begins_with("录制未完成"),"empty output reports failure")
 check(not controls.english_path.visible,"no empty secondary path shown")
 check(controls.result_scroll.get_v_scroll_bar().visible,"very long errors scroll instead of growing offscreen")
 check(controls.message_label.get_global_rect().end.x<=controls.result_scroll.get_v_scroll_bar().get_global_rect().position.x,"scrollbar never overlaps the error text")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence.path_join("long_error.png"))
 controls._on_finished(output,180)
 await wait_frames()
 check(controls.last_message.contains("部分录像") and controls.last_message.contains("不是完整对局"),"partial recording not reported as complete")
 controls.recorder._last_error = ""
 controls._on_finished(output.get_basename()+"_frames",180)
 await wait_frames()
 check(controls.last_message.contains("PNG") and controls.last_message.contains(".audio.f32"),"PNG fallback retains separate audio warning")
 check(not controls.output_path.text.contains("Mc小球"),"result path has no branding prefix")
 root.size = Vector2i(320,480)
 await wait_frames(10)
 check(controls.result_dialog.visible and controls.result_dialog.size.x<=root.get_visible_rect().size.x,"visible popup refits on resize")
 controls._on_result_window_resized()
 controls.result_dialog.hide()
 await wait_frames()
 check(not controls.result_dialog.visible,"queued resize cannot reopen a result dismissed by the user")
 var file:=FileAccess.open(evidence.path_join("ui_results.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":rows},"\t"))
 file.close()
 print("RECORDING_RESULT_UI: checks=%d failures=%d"%[checks,failures])
 quit(1 if failures else 0)
