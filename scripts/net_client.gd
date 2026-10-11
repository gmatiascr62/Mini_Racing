class_name NetClient
extends Node
## WebSocket client for the Mini Racing authoritative server.
## Messages are JSON objects with a "t" (type) field.

signal opened
signal message(msg: Dictionary)
signal closed(reason: String)

var _ws: WebSocketPeer
var _connected := false
var _pending: Array = []
var _connect_started := 0.0
var _ping_timer := 0.0
var url := ""
## Round-trip time in milliseconds (from pings).
var rtt_ms := 0.0


func is_open() -> bool:
	return _ws != null and _connected


func is_active() -> bool:
	return _ws != null


func open(p_url: String) -> Error:
	close()
	url = p_url.strip_edges()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 18
	_ws.outbound_buffer_size = 1 << 18
	_ws.max_queued_packets = 4096
	_connected = false
	_pending.clear()
	_connect_started = Time.get_ticks_msec() / 1000.0
	var err := _ws.connect_to_url(url)
	if err != OK:
		_ws = null
		return err
	return OK


func close(reason: String = "") -> void:
	if _ws != null:
		if _connected:
			_ws.close(1000, "bye")
		_ws = null
		_connected = false
		_pending.clear()
		if reason != "":
			closed.emit(reason)


func send(msg: Dictionary) -> void:
	if _ws == null:
		return
	if not _connected:
		_pending.append(msg)
		return
	_ws.send_text(JSON.stringify(msg))


func _process(delta: float) -> void:
	poll(delta)


func poll(delta: float = 0.0) -> void:
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			for m in _pending:
				_ws.send_text(JSON.stringify(m))
			_pending.clear()
			opened.emit()
		while _ws != null and _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			var parsed = JSON.parse_string(pkt.get_string_from_utf8())
			if parsed is Dictionary:
				if parsed.get("t", "") == "pong":
					rtt_ms = Time.get_ticks_msec() - float(parsed.get("c", 0))
				else:
					message.emit(parsed)
		_ping_timer += delta
		if _ws != null and _ping_timer > 5.0:
			_ping_timer = 0.0
			send({"t": "ping", "c": Time.get_ticks_msec()})
	elif st == WebSocketPeer.STATE_CONNECTING:
		if Time.get_ticks_msec() / 1000.0 - _connect_started > NetConfig.CONNECT_TIMEOUT:
			_ws = null
			closed.emit("NO SE PUDO CONECTAR AL SERVIDOR")
	elif st == WebSocketPeer.STATE_CLOSED:
		var was := _connected
		var code := _ws.get_close_code()
		_ws = null
		_connected = false
		if was:
			closed.emit("CONEXION CERRADA (%d)" % code)
		else:
			closed.emit("NO SE PUDO CONECTAR AL SERVIDOR")
