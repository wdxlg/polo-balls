extends SceneTree
var server:TCPServer = TCPServer.new()
var peer:StreamPeerTCP
var packets:PacketPeerStream = PacketPeerStream.new()
var signatures:Dictionary = {}
var frames:Array = []
var totals:Array = []
var enabled:bool = false
var elapsed:float = 0.0
func _initialize() -> void:
	Engine.max_fps = 60
	var err:int = server.listen(6011,"127.0.0.1")
	if err != OK:
		push_error("Profiler listener failed: " + str(err))
		quit(1)
	print("PROFILE_LISTENER_READY")
func _process(delta:float) -> bool:
	elapsed += delta
	if peer == null and server.is_connection_available():
		peer = server.take_connection()
		packets.stream_peer = peer
		packets.encode_buffer_max_size = 8388608
	if peer != null:
		peer.poll()
		while packets.get_available_packet_count() > 0:
			var msg:Variant = packets.get_var(false)
			if not msg is Array or msg.size() != 3:
				continue
			if not enabled:
				packets.put_var(["profiler:servers",msg[1],[true,[256,true]]])
				enabled = true
				print("PROFILE_ENABLED thread=",msg[1])
			var topic:String = str(msg[0])
			var data:Array = msg[2]
			if topic == "servers:function_signature":
				signatures[str(data[1])] = data[0]
			elif topic == "servers:profile_frame":
				frames.append(data)
				if frames.size() > 120:
					frames.pop_front()
			elif topic == "servers:profile_total":
				totals = data
		if peer.get_status() in [StreamPeerTCP.STATUS_NONE,StreamPeerTCP.STATUS_ERROR]:
			_finish()
	if elapsed > 170.0:
		_finish()
	return false
func _finish() -> void:
	var file:FileAccess = FileAccess.open("res://scripts/training/benchmark_native_profile_current.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"signatures":signatures,"frames":frames,"totals":totals},"\t"))
	file.close()
	print("PROFILE_CAPTURED frames=",frames.size()," signatures=",signatures.size())
	server.stop()
	quit()
