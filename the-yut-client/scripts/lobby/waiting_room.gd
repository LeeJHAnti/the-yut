extends Control

## Waiting room — matches waiting_room.tscn layout:
##   VBox/RoomCodeLabel, PlayerList, StartBtn, LeaveBtn, ChangeNameBtn, AddBotBtn

@onready var room_code_label: Label = $VBox/RoomCodeLabel
@onready var player_list: VBoxContainer = $VBox/PlayerList
@onready var start_btn: Button = $VBox/StartBtn
@onready var leave_btn: Button = $VBox/LeaveBtn
@onready var change_name_btn: Button = $VBox/ChangeNameBtn
@onready var add_bot_btn: Button = $VBox/AddBotBtn

# Decoration sprites
const TEX_DECO_FLOWER = preload("res://assets/sprites/deco_flower.png")
const TEX_DECO_PAW = preload("res://assets/sprites/deco_paw.png")
const TEX_DECO_STAR = preload("res://assets/sprites/deco_star.png")
const TEX_DECO_GRASS = preload("res://assets/sprites/deco_grass.png")

const ZODIAC_SPRITES: Array = [
	preload("res://assets/sprites/piece_rat.png"),
	preload("res://assets/sprites/piece_ox.png"),
	preload("res://assets/sprites/piece_tiger.png"),
	preload("res://assets/sprites/piece_rabbit.png"),
	preload("res://assets/sprites/piece_dragon.png"),
	preload("res://assets/sprites/piece_snake.png"),
	preload("res://assets/sprites/piece_horse.png"),
	preload("res://assets/sprites/piece_sheep.png"),
	preload("res://assets/sprites/piece_monkey.png"),
	preload("res://assets/sprites/piece_rooster.png"),
	preload("res://assets/sprites/piece_dog.png"),
	preload("res://assets/sprites/piece_pig.png"),
]

var is_editing_name: bool = false
var name_edit: LineEdit = null
var deco_time: float = 0.0

func _ready() -> void:
	start_btn.pressed.connect(_on_start)
	leave_btn.pressed.connect(_on_leave)
	change_name_btn.pressed.connect(_on_change_name)
	add_bot_btn.pressed.connect(_on_add_bot)

	GameState.state_updated.connect(_update_ui)

func _update_ui() -> void:
	room_code_label.text = "Room: " + GameState.room_code

	# Clear and rebuild player list
	for child in player_list.get_children():
		child.queue_free()

	for p in GameState.players:
		var label = Label.new()
		var pname = p.get("name", "???")
		var is_bot = p.get("is_bot", false)
		var is_me = int(p.get("id", -1)) == GameState.player_id

		if is_me:
			label.text = "> " + pname + " (YOU)"
			label.add_theme_color_override("font_color", Color("503820"))
		elif is_bot:
			label.text = "  " + pname + " [BOT]"
			label.add_theme_color_override("font_color", Color("907040"))
		else:
			label.text = "  " + pname
			label.add_theme_color_override("font_color", Color("907040"))

		label.add_theme_font_size_override("font_size", 20)
		player_list.add_child(label)

	# Empty slots
	var empty_slots = 4 - GameState.players.size()
	for _i in range(empty_slots):
		var label = Label.new()
		label.text = "  ---"
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color("E0C898"))
		player_list.add_child(label)

	# Team mode preview (4 players = 2v2)
	if GameState.players.size() == 4:
		var team_label = Label.new()
		var p0 = GameState.players[0].get("name", "P0")
		var p1 = GameState.players[1].get("name", "P1")
		var p2 = GameState.players[2].get("name", "P2")
		var p3 = GameState.players[3].get("name", "P3")
		team_label.text = "TEAM: " + p0 + "+" + p2 + " vs " + p1 + "+" + p3
		team_label.add_theme_font_size_override("font_size", 14)
		team_label.add_theme_color_override("font_color", Color("907040"))
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_list.add_child(team_label)

	# Button visibility
	var can_start = GameState.is_host and GameState.players.size() >= 2
	start_btn.visible = GameState.is_host
	start_btn.disabled = not can_start
	add_bot_btn.visible = GameState.is_host and GameState.players.size() < 4
	change_name_btn.visible = not is_editing_name
	leave_btn.visible = true

func _on_start() -> void:
	NetworkManager.send_message({"type": "start_game", "payload": {}})

func _on_leave() -> void:
	# Disconnect WebSocket so the server properly removes us from the room
	# (triggers handle_disconnect which cleans up the room)
	NetworkManager.disconnect_from_server()
	GameState.reset()
	get_parent().go_to_title()

func _on_change_name() -> void:
	# Toggle inline name editor
	if is_editing_name and name_edit != null:
		_submit_name_change()
		return

	is_editing_name = true
	change_name_btn.text = "OK"

	# Create inline LineEdit above the button
	name_edit = LineEdit.new()
	name_edit.text = GameState.player_name
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.add_theme_color_override("font_color", Color("503820"))
	name_edit.max_length = 20
	name_edit.text_submitted.connect(func(_text): _submit_name_change())

	# Insert before ChangeNameBtn in VBox
	var vbox = $VBox
	var btn_idx = change_name_btn.get_index()
	vbox.add_child(name_edit)
	vbox.move_child(name_edit, btn_idx)
	name_edit.grab_focus()
	change_name_btn.visible = true
	change_name_btn.text = "OK"

func _submit_name_change() -> void:
	if name_edit == null:
		return
	var new_name = name_edit.text.strip_edges()
	if new_name.length() == 0:
		new_name = GameState.player_name  # keep old name if empty

	GameState.player_name = new_name
	NetworkManager.send_message({
		"type": "change_name",
		"payload": {"name": new_name}
	})

	# Clean up editor
	name_edit.queue_free()
	name_edit = null
	is_editing_name = false
	change_name_btn.text = "CHANGE NAME"

func _process(delta: float) -> void:
	deco_time += delta
	queue_redraw()

func _draw() -> void:
	var w = size.x
	var h = size.y

	# Flowers along edges
	if TEX_DECO_FLOWER:
		var fs = TEX_DECO_FLOWER.get_size()
		var flower_spots = [
			Vector2(35, 45), Vector2(w - 45, 55),
			Vector2(30, h - 55), Vector2(w - 35, h - 45),
			Vector2(w * 0.5 - 160, 70), Vector2(w * 0.5 + 155, 75),
		]
		for i in range(flower_spots.size()):
			var fp = flower_spots[i]
			var bob = sin(deco_time * 1.3 + i * 1.4) * 2.5
			draw_texture(TEX_DECO_FLOWER, fp - fs * 0.5 + Vector2(0, bob), Color(1, 1, 1, 0.35))

	# Paw prints
	if TEX_DECO_PAW:
		var ps = TEX_DECO_PAW.get_size()
		for i in range(4):
			var px = 50 + i * 120
			draw_texture(TEX_DECO_PAW, Vector2(px, h - 30) - ps * 0.5, Color(1, 1, 1, 0.2))

	# Waiting animal (animated idle bounce) — show one animal per player slot
	var num_players = GameState.players.size()
	for i in range(mini(num_players, 4)):
		var animal_idx = (hash(i) * 7 + 3) % 12
		var tex = ZODIAC_SPRITES[animal_idx]
		var ts = tex.get_size()
		var ax = 35 + i * 25
		var ay = 160 + i * 85
		var bob = sin(deco_time * 1.8 + i * 1.5) * 4.0
		draw_texture_rect(tex, Rect2(Vector2(ax, ay + bob) - ts * 0.6, ts * 1.2), false, Color(1, 1, 1, 0.5))

	# Stars
	if TEX_DECO_STAR:
		var ss = TEX_DECO_STAR.get_size()
		for i in range(5):
			var sx = 60 + i * 95
			var sy = 25 + sin(i * 1.8) * 15
			var twinkle = 0.15 + sin(deco_time * 2.5 + i * 2.0) * 0.15
			draw_texture(TEX_DECO_STAR, Vector2(sx, sy) - ss * 0.5, Color(1, 1, 1, twinkle))

func _on_add_bot() -> void:
	NetworkManager.send_message({
		"type": "add_bot",
		"payload": {"difficulty": "medium"}
	})
