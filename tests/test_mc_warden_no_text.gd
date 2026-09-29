extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	var w:Node2D=actor("监守者",o)
	await process_frame
	for form:int in range(4):
		w.form=form
		w.state_label("old overhead status",Color.WHITE)
		w.visual_mob()
		check(w._status_text.is_empty(),"form "+str(form)+" removes old overhead text")
		w.visual_mob()
		check(w._status_text.is_empty(),"form "+str(form)+" does not recreate overhead text")
	check(is_instance_valid(w.frontier_fx),"existing bars and echo FX remain")
	print("WARDEN NO TEXT: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
