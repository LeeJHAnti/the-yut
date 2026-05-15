extends Control

## Title screen — matches title_screen.tscn layout (redesigned for international players)

@onready var name_input: LineEdit = $VBox/NameInput
@onready var quick_start_btn: Button = $VBox/QuickStartBtn
@onready var create_room_btn: Button = $VBox/CreateRoomBtn
@onready var join_room_btn: Button = $VBox/JoinRoomBtn
@onready var join_code_input: LineEdit = $VBox/JoinCodeInput
@onready var status_label: Label = $VBox/StatusLabel
@onready var room_list_panel: VBoxContainer = $VBox/RoomListPanel
@onready var http_request: HTTPRequest = $HTTPRequest
@onready var how_to_play_btn: Button = $VBox/HowToPlayBtn

# Decoration sprites
const TEX_DECO_FLOWER = preload("res://assets/sprites/deco_flower.png")
const TEX_DECO_PAW = preload("res://assets/sprites/deco_paw.png")
const TEX_DECO_STAR = preload("res://assets/sprites/deco_star.png")
const TEX_DECO_GRASS = preload("res://assets/sprites/deco_grass.png")

# Only preload the 4 animals actually shown in title decoration (not all 12)
const TITLE_ANIMAL_SPRITES: Array = [
	preload("res://assets/sprites/piece_rabbit.png"),   # index 0
	preload("res://assets/sprites/piece_dragon.png"),   # index 1
	preload("res://assets/sprites/piece_monkey.png"),   # index 2
	preload("res://assets/sprites/piece_pig.png"),      # index 3
]

var join_mode: bool = false
var deco_time: float = 0.0
var _redraw_counter: int = 0

func _ready() -> void:
	AudioManager.play_bgm("title")
	name_input.text = GameState.player_name
	join_code_input.visible = false
	room_list_panel.visible = false
	_update_connection_status()

	quick_start_btn.pressed.connect(_on_quick_start)
	create_room_btn.pressed.connect(_on_create_room)
	join_room_btn.pressed.connect(_on_join_room)
	name_input.text_changed.connect(_on_name_changed)
	http_request.request_completed.connect(_on_room_list_received)
	how_to_play_btn.pressed.connect(_on_how_to_play)

	# ── Style "HOW TO PLAY" button — distinctive green accent ──
	var htp_style = StyleBoxFlat.new()
	htp_style.bg_color = Color("58B068", 0.25)
	htp_style.border_color = Color("58B068")
	htp_style.set_border_width_all(3)
	htp_style.set_corner_radius_all(6)
	htp_style.content_margin_left = 12
	htp_style.content_margin_right = 12
	htp_style.content_margin_top = 8
	htp_style.content_margin_bottom = 10
	htp_style.shadow_color = Color(0, 0, 0, 0.12)
	htp_style.shadow_size = 3
	how_to_play_btn.add_theme_stylebox_override("normal", htp_style)
	how_to_play_btn.add_theme_color_override("font_color", Color("3A7A42"))

	var htp_hover = htp_style.duplicate()
	htp_hover.bg_color = Color("58B068", 0.40)
	how_to_play_btn.add_theme_stylebox_override("hover", htp_hover)

	var htp_pressed = htp_style.duplicate()
	htp_pressed.bg_color = Color("58B068", 0.55)
	how_to_play_btn.add_theme_stylebox_override("pressed", htp_pressed)

	NetworkManager.connected.connect(_on_connected)
	NetworkManager.disconnected.connect(_on_disconnected)

func _update_connection_status() -> void:
	if NetworkManager.is_server_connected():
		status_label.text = "Connected"
		status_label.add_theme_color_override("font_color", Color("58B068"))
		_set_buttons_enabled(true)
	else:
		status_label.text = "Connecting..."
		status_label.add_theme_color_override("font_color", Color("907040"))
		_set_buttons_enabled(false)

func _set_buttons_enabled(enabled: bool) -> void:
	quick_start_btn.disabled = not enabled
	create_room_btn.disabled = not enabled
	join_room_btn.disabled = not enabled

func _on_name_changed(new_text: String) -> void:
	GameState.player_name = new_text

func _on_how_to_play() -> void:
	AudioManager.play_sfx("ui_click")
	var rules_scene = preload("res://scenes/rules/rules_screen.tscn")
	var rules = rules_scene.instantiate()
	add_child(rules)

func _on_quick_start() -> void:
	AudioManager.play_sfx("ui_click")
	status_label.text = "Joining..."
	if not NetworkManager.is_server_connected():
		NetworkManager.connect_to_server()
		await NetworkManager.connected
	_send_name()
	NetworkManager.send_message({"type": "quick_match", "payload": {}})

func _on_create_room() -> void:
	AudioManager.play_sfx("ui_click")
	status_label.text = "Creating room..."
	if not NetworkManager.is_server_connected():
		NetworkManager.connect_to_server()
		await NetworkManager.connected
	_send_name()
	NetworkManager.send_message({"type": "create_room", "payload": {}})

func _on_join_room() -> void:
	AudioManager.play_sfx("ui_click")
	if not join_mode:
		join_mode = true
		join_code_input.visible = true
		join_room_btn.text = "GO"
		# Fetch and show room list
		_fetch_room_list()
		return

	var code = join_code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Enter 4-char code"
		return

	status_label.text = "Joining..."
	if not NetworkManager.is_server_connected():
		NetworkManager.connect_to_server()
		await NetworkManager.connected
	_send_name()
	NetworkManager.send_message({"type": "join_room", "payload": {"code": code}})

func _fetch_room_list() -> void:
	var server_url = NetworkManager.server_url
	var http_url = server_url.replace("wss://", "https://").replace("ws://", "http://")
	if http_url.ends_with("/ws"):
		http_url = http_url.left(http_url.length() - 3)
	http_url += "/admin/rooms"

	status_label.text = "Loading rooms..."
	var err = http_request.request(http_url)
	if err != OK:
		status_label.text = "Failed to fetch rooms"
		room_list_panel.visible = false

func _on_room_list_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "No rooms found"
		room_list_panel.visible = false
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json.has("rooms"):
		status_label.text = "No rooms found"
		room_list_panel.visible = false
		return

	var rooms = json["rooms"] as Array
	var waiting_rooms: Array = []
	for room in rooms:
		var phase = room.get("phase", "")
		if phase == "WaitingForPlayers":
			waiting_rooms.append(room)

	for child in room_list_panel.get_children():
		child.queue_free()

	if waiting_rooms.size() == 0:
		status_label.text = "No open rooms"
		var no_rooms = Label.new()
		no_rooms.text = "No open rooms found"
		no_rooms.add_theme_font_size_override("font_size", 14)
		no_rooms.add_theme_color_override("font_color", Color("907040"))
		no_rooms.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		room_list_panel.add_child(no_rooms)
		room_list_panel.visible = true
		return

	status_label.text = str(waiting_rooms.size()) + " room(s) available"

	for room in waiting_rooms:
		var code = room.get("code", "????")
		var player_count = int(room.get("player_count", 0))
		var names = room.get("player_names", [])
		var names_str = ", ".join(names) if names.size() > 0 else "empty"

		var btn = Button.new()
		btn.text = code + "  [" + str(player_count) + "/4]  " + names_str
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size = Vector2(0, 36)
		var room_code = code
		btn.pressed.connect(func(): _join_room_by_code(room_code))
		room_list_panel.add_child(btn)

	var refresh_btn = Button.new()
	refresh_btn.text = "REFRESH"
	refresh_btn.add_theme_font_size_override("font_size", 13)
	refresh_btn.custom_minimum_size = Vector2(0, 30)
	refresh_btn.pressed.connect(_fetch_room_list)
	room_list_panel.add_child(refresh_btn)

	room_list_panel.visible = true

func _join_room_by_code(code: String) -> void:
	AudioManager.play_sfx("ui_click")
	join_code_input.text = code
	status_label.text = "Joining " + code + "..."
	if not NetworkManager.is_server_connected():
		NetworkManager.connect_to_server()
		await NetworkManager.connected
	_send_name()
	NetworkManager.send_message({"type": "join_room", "payload": {"code": code}})

func _send_name() -> void:
	NetworkManager.send_message({
		"type": "change_name",
		"payload": {"name": GameState.player_name}
	})

func _process(delta: float) -> void:
	deco_time += delta
	# Throttle decoration redraws to ~15fps
	_redraw_counter += 1
	if _redraw_counter >= 4:
		_redraw_counter = 0
		queue_redraw()

func _draw() -> void:
	_draw_decorations()

func _draw_decorations() -> void:
	var w = size.x
	var h = size.y

	# Scattered flowers around edges
	if TEX_DECO_FLOWER:
		var flower_positions = [
			Vector2(30, 60), Vector2(w - 40, 80), Vector2(50, h - 70),
			Vector2(w - 55, h - 50), Vector2(w * 0.5 - 180, 120),
			Vector2(w * 0.5 + 170, 130), Vector2(25, h * 0.4),
			Vector2(w - 30, h * 0.45),
		]
		var fs = TEX_DECO_FLOWER.get_size()
		for i in range(flower_positions.size()):
			var fp = flower_positions[i]
			var bob = sin(deco_time * 1.2 + i * 1.3) * 3.0
			draw_texture(TEX_DECO_FLOWER, fp - fs * 0.5 + Vector2(0, bob), Color(1, 1, 1, 0.45))

	# Paw prints
	if TEX_DECO_PAW:
		var paw_positions = [
			Vector2(70, 160), Vector2(w - 80, 170),
			Vector2(60, h - 140), Vector2(w - 70, h - 130),
		]
		var ps = TEX_DECO_PAW.get_size()
		for pp in paw_positions:
			draw_texture(TEX_DECO_PAW, pp - ps * 0.5, Color(1, 1, 1, 0.2))

	# Stars
	if TEX_DECO_STAR:
		var star_positions = [
			Vector2(100, 40), Vector2(w - 110, 50),
			Vector2(w * 0.5, h - 30),
		]
		var ss = TEX_DECO_STAR.get_size()
		for i in range(star_positions.size()):
			var sp = star_positions[i]
			var twinkle = 0.2 + sin(deco_time * 2.5 + i * 2.0) * 0.15
			draw_texture(TEX_DECO_STAR, sp - ss * 0.5, Color(1, 1, 1, twinkle))

	# 4 showcase zodiac animals near bottom corners
	var animal_scale = 1.5
	var animal_positions = [
		Vector2(50, h - 40), Vector2(130, h - 35),
		Vector2(w - 140, h - 35), Vector2(w - 55, h - 40),
	]
	for i in range(4):
		var tex = TITLE_ANIMAL_SPRITES[i]
		var ts = tex.get_size()
		var bob = sin(deco_time * 1.5 + i * 1.7) * 4.0
		var pos = animal_positions[i] - ts * animal_scale * 0.5 + Vector2(0, bob)
		draw_texture_rect(tex, Rect2(pos, ts * animal_scale), false, Color(1, 1, 1, 0.7))

	# Grass along bottom
	if TEX_DECO_GRASS:
		var gs = TEX_DECO_GRASS.get_size()
		for i in range(12):
			var gx = 20 + i * 42
			draw_texture(TEX_DECO_GRASS, Vector2(gx, h - 15) - gs * 0.5, Color(1, 1, 1, 0.3))

func _on_connected() -> void:
	status_label.text = "Connected"
	status_label.add_theme_color_override("font_color", Color("58B068"))
	_set_buttons_enabled(true)

func _on_disconnected() -> void:
	status_label.text = "Offline — check server"
	status_label.add_theme_color_override("font_color", Color("D05848"))
	_set_buttons_enabled(false)
