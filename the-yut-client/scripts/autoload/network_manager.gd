extends Node

signal connected
signal disconnected
signal message_received(data: Dictionary)

var websocket: WebSocketPeer
var server_url: String = ""
var is_connected: bool = false
var reconnect_attempts: int = 0
var max_reconnect_attempts: int = 3
var heartbeat_timer: float = 0.0
var heartbeat_interval: float = 10.0
var connection_timeout: float = 0.0
var connection_timeout_max: float = 5.0  # 5 second timeout

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	server_url = _detect_server_url()
	print("Server URL: ", server_url)
	# Pre-connect to server on startup for faster room creation
	call_deferred("_auto_connect")

func _auto_connect() -> void:
	connect_to_server()

## Auto-detect WebSocket URL based on platform.
## - Web build: derive from browser's current host (supports both ws:// and wss://)
## - Desktop/local: fall back to ws://localhost:9001/ws
func _detect_server_url() -> String:
	if OS.has_feature("web"):
		# Running in browser — use JavaScript to get current page origin
		var js_result = JavaScriptBridge.eval("""
			(function() {
				var proto = (location.protocol === 'https:') ? 'wss:' : 'ws:';
				return proto + '//' + location.host + '/ws';
			})()
		""")
		if js_result != null and str(js_result) != "":
			return str(js_result)
	# Fallback for desktop / editor / local dev
	return "ws://localhost:9001/ws"

func _process(delta: float) -> void:
	if not websocket:
		return
	websocket.poll()
	var state = websocket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			reconnect_attempts = 0
			connection_timeout = 0.0
			connected.emit()

		while websocket.get_available_packet_count():
			var packet = websocket.get_packet()
			var json_str = packet.get_string_from_utf8()
			var parsed = JSON.parse_string(json_str)
			if parsed != null:
				message_received.emit(parsed)

		# Heartbeat
		heartbeat_timer += delta
		if heartbeat_timer >= heartbeat_interval:
			heartbeat_timer = 0.0
			send_message({"type": "heartbeat"})

	elif state == WebSocketPeer.STATE_CONNECTING:
		# Track connection timeout
		connection_timeout += delta
		if connection_timeout >= connection_timeout_max:
			print("Connection timeout after ", connection_timeout_max, " seconds")
			websocket = null
			connection_timeout = 0.0
			disconnected.emit()

	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			disconnected.emit()
		connection_timeout = 0.0
		if reconnect_attempts < max_reconnect_attempts:
			reconnect()

func connect_to_server(url: String = server_url) -> void:
	server_url = url
	websocket = WebSocketPeer.new()
	var error = websocket.connect_to_url(server_url)
	if error != OK:
		print("Failed to connect to server: ", error)
		return
	is_connected = false
	connection_timeout = 0.0

func send_message(data: Dictionary) -> void:
	if websocket and websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_str = JSON.stringify(data)
		websocket.send_text(json_str)

func reconnect() -> void:
	reconnect_attempts += 1
	print("Attempting to reconnect (", reconnect_attempts, "/", max_reconnect_attempts, ")")

	if reconnect_attempts <= max_reconnect_attempts:
		await get_tree().create_timer(1.0).timeout  # Reduced from 2s to 1s
		connect_to_server()
	else:
		print("Max reconnection attempts reached")
		disconnected.emit()

func disconnect_from_server() -> void:
	if websocket:
		websocket.close()
		websocket = null
	is_connected = false
	reconnect_attempts = max_reconnect_attempts  # prevent auto-reconnect
	connection_timeout = 0.0

func is_server_connected() -> bool:
	return websocket and websocket.get_ready_state() == WebSocketPeer.STATE_OPEN
