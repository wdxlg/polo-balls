extends SceneTree
func _initialize() -> void:
	var d:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/training/benchmark_native_profile_current.json"))
	var sig:Dictionary = d["signatures"]
	var frames:Array = d["frames"]
	# --last=N 只统计最后 N 帧（跳过生成期，只看稳态混战）。
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--last="):
			var keep:int = int(arg.trim_prefix("--last="))
			if keep > 0 and keep < frames.size():
				frames = frames.slice(frames.size() - keep)
	var agg:Dictionary = {}
	var srv:Dictionary = {}
	var n:int = 0
	var fr_t:float = 0.0; var pr_t:float = 0.0; var ph_t:float = 0.0; var sc_t:float = 0.0
	for f:Array in frames:
		n += 1
		fr_t += f[1]; pr_t += f[2]; ph_t += f[3]; sc_t += f[5]
		var idx:int = 6
		var server_count:int = int(f[idx]); idx += 1
		for s in range(server_count):
			var sname:String = str(f[idx]); idx += 1
			var fc:int = int(f[idx]); idx += 1
			for k in range(fc / 2):
				var fname:String = sname + "/" + str(f[idx]); var t:float = float(f[idx+1]); idx += 2
				srv[fname] = srv.get(fname,0.0) + t
		idx += 1 # element count, not function count
		while idx + 4 < f.size():
			var id:String = str(int(f[idx])); var calls:int = int(f[idx+1]); var selft:float = float(f[idx+2]); var total:float = float(f[idx+3]); idx += 5
			var name:String = str(sig.get(id,id))
			var a:Array = agg.get(name,[0,0.0,0.0])
			a[0] += calls; a[1] += total; a[2] += selft
			agg[name] = a
	print("frames=",n," avg frame_ms=",fr_t/n*1000," process=",pr_t/n*1000," physics=",ph_t/n*1000," script=",sc_t/n*1000)
	var keys:Array = srv.keys()
	keys.sort_custom(func(a,b): return srv[a] > srv[b])
	print("--- servers (avg ms/frame) ---")
	for i in range(mini(12,keys.size())):
		print("%8.3f  %s" % [srv[keys[i]]/n*1000.0, keys[i]])
	keys = agg.keys()
	keys.sort_custom(func(a,b): return agg[a][2] > agg[b][2])
	print("--- script functions by SELF ms/frame ---")
	for i in range(mini(60,keys.size())):
		var a:Array = agg[keys[i]]
		print("%8.3f self %8.3f total %7d calls  %s" % [a[2]/n*1000.0, a[1]/n*1000.0, a[0]/n, keys[i]])
	keys.sort_custom(func(a,b): return agg[a][1] > agg[b][1])
	print("--- script functions by TOTAL ms/frame ---")
	for i in range(mini(30,keys.size())):
		var a:Array = agg[keys[i]]
		print("%8.3f self %8.3f total %7d calls  %s" % [a[2]/n*1000.0, a[1]/n*1000.0, a[0]/n, keys[i]])
	var grep:String = ""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--grep="): grep = arg.trim_prefix("--grep=")
	if not grep.is_empty():
		print("--- TOTAL filtered by ", grep, " ---")
		var shown:int = 0
		for k in keys:
			if shown >= 60: break
			if str(k).find(grep) < 0: continue
			var a:Array = agg[k]
			print("%8.3f self %8.3f total %7d calls  %s" % [a[2]/n*1000.0, a[1]/n*1000.0, a[0]/n, k])
			shown += 1
	# 按脚本文件聚合 SELF 时间：看哪些角色/系统在吃帧。
	var by_file:Dictionary = {}
	for name:String in agg.keys():
		var file:String = name.split("::")[0]
		by_file[file] = float(by_file.get(file,0.0)) + agg[name][2]
	var files:Array = by_file.keys()
	files.sort_custom(func(a,b): return by_file[a] > by_file[b])
	print("--- script files by SELF ms/frame ---")
	for i in range(mini(40,files.size())):
		print("%8.3f  %s" % [by_file[files[i]]/n*1000.0, files[i]])
	quit()
