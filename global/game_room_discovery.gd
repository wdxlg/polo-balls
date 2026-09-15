extends RefCounted
## V127 局域网 / 虚拟局域网房间发现（UDP 27019）
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node


func _init(game: Node) -> void:
	_game = game


# 游戏 ENet 仍固定 UDP 27018；房间发现使用独立 UDP 27019，避免和 ENet 争用同一端口。
const ROOM_DISCOVERY_PORT:int = 27019

const ROOM_DISCOVERY_MAGIC:String = "POLO_BALLS_ROOM_DISCOVERY"

const ROOM_DISCOVERY_PROTOCOL:int = 1

const ROOM_DISCOVERY_INTERVAL:float = 2.5

const ROOM_DISCOVERY_EXPIRE_SECONDS:float = 6.0

var discovered_rooms:Dictionary = {}

var _room_host_socket:PacketPeerUDP = null

var _room_browser_socket:PacketPeerUDP = null

var _room_discovery_elapsed:float = 0.0

var _room_scan_token:int = 0

var _room_last_signature:String = ""


func _setup_room_browser_socket() -> void:
	if _room_browser_socket != null and _room_browser_socket.is_bound():
		return
	_room_browser_socket = PacketPeerUDP.new()
	_room_browser_socket.set_broadcast_enabled(true)
	var error:Error = _room_browser_socket.bind(0,"0.0.0.0")
	if error != OK:
		push_warning("房间发现浏览器 UDP 绑定失败: " + error_string(error))
		_room_browser_socket = null


func _start_room_host_socket() -> void:
	_close_room_host_socket()
	_room_host_socket = PacketPeerUDP.new()
	_room_host_socket.set_broadcast_enabled(true)
	var error:Error = _room_host_socket.bind(ROOM_DISCOVERY_PORT,"0.0.0.0")
	if error != OK:
		push_warning("房间发现主机 UDP 端口 " + str(ROOM_DISCOVERY_PORT) + " 绑定失败: " + error_string(error))
		_room_host_socket = null


func _close_room_host_socket() -> void:
	if _room_host_socket != null:
		_room_host_socket.close()
		_room_host_socket = null


func _room_packet_to_dictionary(packet:PackedByteArray) -> Dictionary:
	if packet.is_empty():
		return {}
	var parsed:Variant = JSON.parse_string(packet.get_string_from_utf8())
	if parsed is not Dictionary:
		return {}
	return parsed as Dictionary


func _room_discovery_packet(packet_type:String, sent_ms:int, scan_token:int) -> PackedByteArray:
	return JSON.stringify({
		"magic": ROOM_DISCOVERY_MAGIC,
		"protocol": ROOM_DISCOVERY_PROTOCOL,
		"type": packet_type,
		"game_port": _game.port,
		"sent_ms": sent_ms,
		"scan_token": scan_token,
	}).to_utf8_buffer()


func _room_info_packet(sent_ms:int, scan_token:int) -> PackedByteArray:
	var player_count:int = _game.get_network_peer_ids().size()
	if player_count <= 0 and _game.network_role == "host":
		player_count = 1
	return JSON.stringify({
		"magic": ROOM_DISCOVERY_MAGIC,
		"protocol": ROOM_DISCOVERY_PROTOCOL,
		"type": "room",
		"game_port": _game.port,
		"players": player_count,
		"max_players": _game.max_player,
		"sent_ms": sent_ms,
		"scan_token": scan_token,
	}).to_utf8_buffer()


func _is_valid_room_packet(data:Dictionary, expected_type:String) -> bool:
	return (
		str(data.get("magic","")) == ROOM_DISCOVERY_MAGIC
		and int(data.get("protocol",0)) == ROOM_DISCOVERY_PROTOCOL
		and str(data.get("type","")) == expected_type
	)


func _directed_broadcast_for_ipv4(address:String) -> String:
	var parts:PackedStringArray = address.split(".")
	if parts.size() != 4:
		return ""
	for part:String in parts:
		if not part.is_valid_int():
			return ""
		var value:int = int(part)
		if value < 0 or value > 255:
			return ""
	# 项目只需要局域网/虚拟局域网找房；EasyTier 默认本身就是 /24。
	return parts[0] + "." + parts[1] + "." + parts[2] + ".255"


func _room_discovery_targets() -> Array[String]:
	var targets:Array[String] = ["127.0.0.1","255.255.255.255"]
	for address:String in _game.get_local_ipv4_addresses():
		var broadcast:String = _directed_broadcast_for_ipv4(address)
		if not broadcast.is_empty() and not targets.has(broadcast):
			targets.append(broadcast)
	return targets


func _is_virtual_lan_interface(interface_data:Dictionary) -> bool:
	var description:String = (
		str(interface_data.get("name","")) + " "
		+ str(interface_data.get("friendly",""))
	).to_lower()
	return (
		description.contains("easytier")
		or description.contains("oray")
		or description.contains("pgy")
		or description.contains("蒲公英")
	)


func _virtual_lan_scan_prefixes() -> Array[String]:
	var prefixes:Array[String] = []
	# EasyTier 默认 DHCP 网段为 10.126.126.0/24。即使其 UDP broadcast relay 没开，
	# 也对这一 /24 做少量单播探测，避免“能直连 IP 却搜不到房间”。
	for address:String in _game.get_local_ipv4_addresses():
		var parts:PackedStringArray = address.split(".")
		if parts.size() == 4 and address.begins_with("10.126.126."):
			var prefix:String = parts[0] + "." + parts[1] + "." + parts[2] + "."
			if not prefixes.has(prefix):
				prefixes.append(prefix)

	# 自定义 EasyTier / 蒲公英虚拟网段：若系统网卡名称能识别，则同样扫描该适配器所在 /24。
	for interface_variant:Variant in IP.get_local_interfaces():
		if interface_variant is not Dictionary:
			continue
		var interface_data:Dictionary = interface_variant as Dictionary
		if not _is_virtual_lan_interface(interface_data):
			continue
		var addresses:Variant = interface_data.get("addresses",interface_data.get("address",[]))
		for raw_address:Variant in addresses:
			var address:String = str(raw_address)
			if address.contains(":"):
				continue
			var parts:PackedStringArray = address.split(".")
			if parts.size() != 4:
				continue
			var prefix:String = parts[0] + "." + parts[1] + "." + parts[2] + "."
			if not prefixes.has(prefix):
				prefixes.append(prefix)
	return prefixes


func request_room_scan(force:bool = false) -> void:
	_setup_room_browser_socket()
	if _room_browser_socket == null:
		return
	if not force and _room_discovery_elapsed < ROOM_DISCOVERY_INTERVAL:
		return
	_room_discovery_elapsed = 0.0
	_room_scan_token += 1
	var sent_ms:int = Time.get_ticks_msec()
	var packet:PackedByteArray = _room_discovery_packet("discover",sent_ms,_room_scan_token)

	# 普通 LAN 与支持广播转发的虚拟 LAN（EasyTier Game 的 WinIPBroadcast / UDP broadcast relay）走这里。
	for target:String in _room_discovery_targets():
		if _room_browser_socket.set_dest_address(target,ROOM_DISCOVERY_PORT) == OK:
			_room_browser_socket.put_packet(packet)

	# EasyTier 默认网段与可识别虚拟网卡提供单播 /24 fallback，不要求广播转发功能必须开启。
	var self_addresses:Array[String] = _game.get_local_ipv4_addresses()
	for prefix:String in _virtual_lan_scan_prefixes():
		for host:int in range(1,255):
			var target:String = prefix + str(host)
			if self_addresses.has(target):
				continue
			if _room_browser_socket.set_dest_address(target,ROOM_DISCOVERY_PORT) == OK:
				_room_browser_socket.put_packet(packet)


func _process_room_host_requests() -> void:
	if _room_host_socket == null or _game.network_role != "host":
		return
	while _room_host_socket.get_available_packet_count() > 0:
		var packet:PackedByteArray = _room_host_socket.get_packet()
		var sender_ip:String = _room_host_socket.get_packet_ip()
		var sender_port:int = _room_host_socket.get_packet_port()
		var data:Dictionary = _room_packet_to_dictionary(packet)
		if not _is_valid_room_packet(data,"discover"):
			continue
		if sender_ip.is_empty() or sender_port <= 0:
			continue
		var sent_ms:int = int(data.get("sent_ms",0))
		var scan_token:int = int(data.get("scan_token",0))
		if _room_host_socket.set_dest_address(sender_ip,sender_port) == OK:
			_room_host_socket.put_packet(_room_info_packet(sent_ms,scan_token))


func _process_room_browser_replies() -> void:
	if _room_browser_socket == null:
		return
	var changed:bool = false
	while _room_browser_socket.get_available_packet_count() > 0:
		var packet:PackedByteArray = _room_browser_socket.get_packet()
		var sender_ip:String = _room_browser_socket.get_packet_ip()
		var data:Dictionary = _room_packet_to_dictionary(packet)
		if not _is_valid_room_packet(data,"room"):
			continue
		if sender_ip.is_empty():
			continue
		var game_port:int = int(data.get("game_port",_game.port))
		if game_port <= 0 or game_port > 65535:
			continue
		var sent_ms:int = int(data.get("sent_ms",0))
		var now_ms:int = Time.get_ticks_msec()
		var ping_ms:int = maxi(now_ms - sent_ms,0) if sent_ms > 0 else -1
		var room_key:String = sender_ip + ":" + str(game_port)
		var room:Dictionary = {
			"address": sender_ip,
			"port": game_port,
			"players": clampi(int(data.get("players",1)),0,_game.max_player),
			"max_players": maxi(int(data.get("max_players",_game.max_player)),1),
			"ping_ms": ping_ms,
			"last_seen_ms": now_ms,
		}
		discovered_rooms[room_key] = room
		changed = true
	if changed:
		_emit_room_list_if_changed()


func _expire_discovered_rooms() -> void:
	var now_ms:int = Time.get_ticks_msec()
	var expire_ms:int = int(ROOM_DISCOVERY_EXPIRE_SECONDS * 1000.0)
	var removed:bool = false
	for room_key:Variant in discovered_rooms.keys():
		var room:Dictionary = discovered_rooms[room_key] as Dictionary
		if now_ms - int(room.get("last_seen_ms",0)) > expire_ms:
			discovered_rooms.erase(room_key)
			removed = true
	if removed:
		_emit_room_list_if_changed()


func _emit_room_list_if_changed() -> void:
	var signature_parts:PackedStringArray = PackedStringArray()
	for room:Dictionary in get_discovered_rooms():
		signature_parts.append(
			str(room.get("address","")) + ":" + str(room.get("port",0))
			+ ":" + str(room.get("players",0))
			+ ":" + str(room.get("ping_ms",-1))
		)
	var signature:String = "|".join(signature_parts)
	if signature == _room_last_signature:
		return
	_room_last_signature = signature
	_game.room_list_changed.emit()


func get_discovered_rooms() -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	for room_variant:Variant in discovered_rooms.values():
		if room_variant is Dictionary:
			result.append((room_variant as Dictionary).duplicate())
	result.sort_custom(func(a:Dictionary,b:Dictionary) -> bool:
		var ap:int = int(a.get("ping_ms",999999))
		var bp:int = int(b.get("ping_ms",999999))
		if ap == bp:
			return str(a.get("address","")) < str(b.get("address",""))
		return ap < bp
	)
	return result


func _process_room_discovery(delta:float) -> void:
	_room_discovery_elapsed += maxf(delta,0.0)
	_process_room_host_requests()
	_process_room_browser_replies()
	_expire_discovered_rooms()
	if _room_discovery_elapsed >= ROOM_DISCOVERY_INTERVAL:
		request_room_scan(true)
