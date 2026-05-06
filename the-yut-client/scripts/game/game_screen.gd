extends Control

## Game screen — 520×960 portrait layout (compact for ad banner)
##   y=0~34:    Turn marquee (h=34, 한줄 전광판)
##   y=36~566:  Board (h=530, 428×428 node area)
##   y=568~698: Player piece trays (h=130, dynamic split)
##   y=700~870: Yut throw area (h=170)
##
## Game flow:
##   1. Player throws yut (flick or tap)
##   2. Result auto-cycles (always index 0)
##   3. Player drags piece to highlighted node (magnetic snap)
##   4. Server validates → broadcasts piece_moved → turn progresses

const ParticleEffects = preload("res://scripts/game/particle_effects.gd")

@onready var board: Node2D = $Board
@onready var yut_input: Control = $YutInput
@onready var yut_animation: Node2D = $YutAnimation
@onready var camera: Camera2D = $Camera2D

# UI elements
@onready var turn_marquee: Label = $TurnMarquee
@onready var action_popup: PanelContainer = $ActionPopup
@onready var action_label: Label = $ActionPopup/ActionLabel
@onready var path_choice_panel: Control = $PathChoicePanel

var piece_nodes: Dictionary = {}
var pieces_container: Node2D
var selectable_pieces: Array = []
var awaiting_piece_select: bool = false

# ─── RESULT SELECTION STATE ───
var selected_result_index: int = 0

# ─── DRAG STATE ───
var dragging_piece_id: int = -1
var drag_valid_destinations: Array = []
var current_snap: Dictionary = {}

# ─── JUNCTION AUTO-RESPOND STATE ───
var junction_path_map: Dictionary = {}
var chosen_snap_node: int = -1

# ─── FINISH CONFIRM STATE ───
var finish_confirm_piece_id: int = -1
var finish_confirm_panel: PanelContainer = null

# ─── PLAYER ZODIAC (one animal per player, from 12 zodiac, no duplicates) ───
var player_zodiac: Dictionary = {}  # player_id → zodiac_index
var used_zodiac_indices: Array = []  # track which zodiac indices are assigned

# ─── INPUT GUARD (prevent duplicate prompt setup) ───
var _yut_anim_playing: bool = false  # true while yut animation is in progress

func _ready() -> void:
	AudioManager.play_bgm("ingame")
	pieces_container = Node2D.new()
	pieces_container.name = "Pieces"
	board.add_child(pieces_container)

	yut_input.yut_flicked.connect(_on_yut_flicked)
	yut_animation.animation_finished.connect(_on_yut_anim_finished)

	GameState.state_updated.connect(_on_state_updated)
	GameState.turn_changed.connect(_on_turn_changed)
	GameState.error_received.connect(_on_error)
	NetworkManager.message_received.connect(_on_server_message)

	_hide_all_actions()
	path_choice_panel.visible = false

	# ─── Style action popup (Nintendo RPG notification banner) ───
	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color("F8F0D8", 0.95)
	popup_style.border_color = Color("503820")
	popup_style.set_border_width_all(2)
	popup_style.set_corner_radius_all(5)
	popup_style.content_margin_left = 12
	popup_style.content_margin_right = 12
	popup_style.content_margin_top = 6
	popup_style.content_margin_bottom = 6
	popup_style.shadow_color = Color(0, 0, 0, 0.15)
	popup_style.shadow_size = 3
	action_popup.add_theme_stylebox_override("panel", popup_style)

	# ─── Create finish confirmation panel (Nintendo RPG dialog style) ───
	var finish_panel_container = PanelContainer.new()
	finish_panel_container.name = "FinishConfirmContainer"
	finish_panel_container.visible = false
	finish_panel_container.position = Vector2(110, 580)
	finish_panel_container.custom_minimum_size = Vector2(300, 0)
	# RPG-style panel background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("F8F0D8")
	panel_style.border_color = Color("503820")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 14
	panel_style.shadow_color = Color(0, 0, 0, 0.2)
	panel_style.shadow_size = 4
	finish_panel_container.add_theme_stylebox_override("panel", panel_style)
	add_child(finish_panel_container)

	var finish_vbox = VBoxContainer.new()
	finish_vbox.add_theme_constant_override("separation", 10)
	finish_panel_container.add_child(finish_vbox)

	# Title label with decorative arrows
	var finish_label = Label.new()
	finish_label.text = ">> FINISH? <<"
	finish_label.add_theme_font_size_override("font_size", 18)
	finish_label.add_theme_color_override("font_color", Color("503820"))
	finish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finish_vbox.add_child(finish_label)

	# Description
	var finish_desc = Label.new()
	finish_desc.text = "Score this piece?"
	finish_desc.add_theme_font_size_override("font_size", 13)
	finish_desc.add_theme_color_override("font_color", Color("907040"))
	finish_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	finish_vbox.add_child(finish_desc)

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	finish_vbox.add_child(btn_row)

	# YES button (green accent)
	var yes_btn = Button.new()
	yes_btn.text = "> YES"
	yes_btn.add_theme_font_size_override("font_size", 16)
	yes_btn.custom_minimum_size = Vector2(100, 42)
	var yes_style = StyleBoxFlat.new()
	yes_style.bg_color = Color("58B068", 0.25)
	yes_style.border_color = Color("58B068")
	yes_style.set_border_width_all(2)
	yes_style.set_corner_radius_all(4)
	yes_style.content_margin_left = 8
	yes_style.content_margin_right = 8
	yes_style.content_margin_top = 4
	yes_style.content_margin_bottom = 6
	yes_btn.add_theme_stylebox_override("normal", yes_style)
	yes_btn.add_theme_color_override("font_color", Color("3A7A42"))
	yes_btn.pressed.connect(_on_finish_confirm_yes)
	btn_row.add_child(yes_btn)

	# NO button (red accent)
	var no_btn = Button.new()
	no_btn.text = "> NO"
	no_btn.add_theme_font_size_override("font_size", 16)
	no_btn.custom_minimum_size = Vector2(100, 42)
	var no_style = StyleBoxFlat.new()
	no_style.bg_color = Color("D05848", 0.2)
	no_style.border_color = Color("D05848")
	no_style.set_border_width_all(2)
	no_style.set_corner_radius_all(4)
	no_style.content_margin_left = 8
	no_style.content_margin_right = 8
	no_style.content_margin_top = 4
	no_style.content_margin_bottom = 6
	no_btn.add_theme_stylebox_override("normal", no_style)
	no_btn.add_theme_color_override("font_color", Color("B03830"))
	no_btn.pressed.connect(_on_finish_confirm_no)
	btn_row.add_child(no_btn)

	# Store outer PanelContainer for visibility toggle
	finish_confirm_panel = finish_panel_container

# ─── STATE MANAGEMENT ───

func _on_state_updated() -> void:
	_sync_pieces()
	_refresh_marquee()
	_update_board_tray()
	# Recovery: if it's my turn and no input is active, re-show prompts
	_check_input_recovery()

func _on_turn_changed(player_id: int) -> void:
	_refresh_marquee()
	_update_current_turn_index()

	# If yut animation is playing, don't set up prompts now.
	# _on_yut_anim_finished will handle it when the animation ends.
	if _yut_anim_playing:
		return

	_hide_all_actions()
	board.clear_highlights()

	if player_id == GameState.player_id:
		if GameState.must_throw:
			_show_throw_prompt()
		else:
			_show_piece_select()
		AudioManager.play_sfx("turn_start")
	else:
		var pname = _get_player_name(player_id)
		_set_action(pname + "'s turn...")

func _refresh_marquee() -> void:
	var current = GameState.current_turn
	var pname = _get_player_name(current)
	var is_me = (current == GameState.player_id)

	if is_me:
		var marquee = ">> YOUR TURN <<"
		if GameState.pending_results.size() > 0:
			marquee += "  [" + ", ".join(GameState.pending_results) + "]"
		turn_marquee.text = marquee
	else:
		var is_ally = GameState.is_team_mode() and GameState.are_teammates(GameState.player_id, current)
		var prefix = "(ALLY) " if is_ally else ""
		var marquee = prefix + pname + "'s Turn"
		if GameState.pending_results.size() > 0:
			marquee += "  [" + ", ".join(GameState.pending_results) + "]"
		turn_marquee.text = marquee

func _update_board_tray() -> void:
	var tray_names: Array = []
	var team_indices: Array = []
	for p in GameState.players:
		tray_names.append(p.get("name", "???"))
		team_indices.append(GameState.get_team_index(int(p.get("id", -1))))
	board.set_player_names(tray_names, team_indices)
	_update_current_turn_index()

func _update_current_turn_index() -> void:
	var turn_idx = -1
	for i in range(GameState.players.size()):
		if int(GameState.players[i].get("id", -1)) == GameState.current_turn:
			turn_idx = i
			break
	board.set_current_turn_index(turn_idx)

# ─── ACTION DISPLAY ───

func _hide_all_actions() -> void:
	yut_input.enabled = false
	yut_input.visible = false
	action_popup.visible = false
	path_choice_panel.visible = false
	if finish_confirm_panel:
		finish_confirm_panel.visible = false
		finish_confirm_piece_id = -1
	awaiting_piece_select = false
	selected_result_index = 0
	if dragging_piece_id >= 0 and piece_nodes.has(dragging_piece_id):
		piece_nodes[dragging_piece_id].cancel_drag()
	dragging_piece_id = -1
	drag_valid_destinations.clear()
	current_snap = {}
	junction_path_map = {}
	chosen_snap_node = -1
	_deselect_all_pieces()

func _set_action(text: String) -> void:
	action_label.text = text
	if text == "":
		action_popup.visible = false
	else:
		action_popup.visible = true

func _show_throw_prompt() -> void:
	_hide_all_actions()
	yut_input.visible = true
	yut_input.enabled = true
	_set_action("Flick or tap to throw!")

# ─── PIECE SELECTION (auto-cycle: always use first pending result) ───

func _show_piece_select() -> void:
	_hide_all_actions()
	selectable_pieces = _get_my_movable_pieces()

	if selectable_pieces.size() == 0:
		# No movable pieces — might be temporary (animation in progress, or state not synced yet).
		# _check_input_recovery will re-trigger when state updates.
		_set_action("Waiting...")
		return

	var results = GameState.pending_results
	if results.size() == 0:
		# No results yet — state sync may still be in transit.
		# _check_input_recovery will re-trigger when pending_results gets populated.
		_set_action("Waiting...")
		return

	selected_result_index = 0
	var result_name = _result_display_name(results[0])
	_enter_drag_mode()
	if results.size() > 1:
		_set_action("Using " + result_name + "  (" + str(results.size()) + " left)")
	else:
		_set_action("Using " + result_name)

func _result_display_name(result: String) -> String:
	match result:
		"Do": return "Do(1)"
		"Gae": return "Gae(2)"
		"Geol": return "Geol(3)"
		"Yut": return "Yut(4)"
		"Mo": return "Mo(5)"
		"BackDo": return "Back(-1)"
	return result

func _enter_drag_mode() -> void:
	awaiting_piece_select = true
	for pid in selectable_pieces:
		if piece_nodes.has(pid):
			piece_nodes[pid].set_selected(true)
	_highlight_destinations()
	if selectable_pieces.size() == 1:
		# Don't auto-select completed_circuit pieces — show finish confirm instead
		var only_pid = selectable_pieces[0]
		if piece_nodes.has(only_pid) and piece_nodes[only_pid].is_completed_circuit:
			_show_finish_confirm(only_pid)
		else:
			_select_piece(only_pid)

func _highlight_destinations() -> void:
	var dest_nodes_set: Dictionary = {}
	for pid in selectable_pieces:
		var dests = _calc_destinations_for_piece(pid)
		for d in dests:
			dest_nodes_set[d] = true
	board.set_highlights(dest_nodes_set.keys())

func _result_to_distance(result: String) -> int:
	match result:
		"Do": return 1
		"Gae": return 2
		"Geol": return 3
		"Yut": return 4
		"Mo": return 5
		"BackDo": return -1
	return 0

func _show_path_choice(paths: Array) -> void:
	_hide_all_actions()
	path_choice_panel.visible = true
	AudioManager.play_sfx("path_choice")
	# Clear old buttons from the Buttons HBoxContainer
	var buttons_container = path_choice_panel.get_node("VBox/Buttons")
	for child in buttons_container.get_children():
		child.queue_free()
	for path_name in paths:
		var btn = Button.new()
		var display = path_name.to_upper()
		if path_name == "shortcut":
			display = "> SHORTCUT"
		elif path_name == "outer":
			display = "> OUTER"
		elif path_name == "center_exit":
			display = "> TO HOME"
		elif path_name == "continue":
			display = "> CONTINUE"
		else:
			display = "> " + display
		btn.text = display
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(140, 44)
		var choice = path_name
		btn.pressed.connect(func(): _on_path_chosen(choice))
		buttons_container.add_child(btn)
	_set_action("")

# ─── INPUT HANDLERS ───

func _on_yut_flicked(power: float) -> void:
	AudioManager.play_sfx("yut_throw")
	yut_input.enabled = false
	action_popup.visible = false
	NetworkManager.send_message({
		"type": "throw_yut",
		"payload": {"gesture_power": power}
	})

func _on_yut_anim_finished() -> void:
	yut_animation.clear()
	_yut_anim_playing = false

	# Don't interrupt if player is already interacting (dragging, choosing path)
	if _is_input_active():
		return

	if GameState.is_my_turn():
		if GameState.must_throw:
			_show_throw_prompt()
		else:
			_show_piece_select()
	else:
		var pname = _get_player_name(GameState.current_turn)
		_set_action(pname + "'s turn...")

func _viewport_to_world(viewport_pos: Vector2) -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * viewport_pos

func _input(event: InputEvent) -> void:
	if awaiting_piece_select and dragging_piece_id < 0:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
			_try_start_drag(_viewport_to_world(event.position))
			return

	if dragging_piece_id >= 0:
		if event is InputEventMouseMotion or event is InputEventScreenDrag:
			_update_drag(_viewport_to_world(event.position))
			return

	if dragging_piece_id >= 0:
		if (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and not event.pressed):
			_end_drag()
			return

func _try_start_drag(local_pos: Vector2) -> void:
	var best_id = -1
	var best_dist = 65.0  # Larger hit area for mobile touch

	for pid in selectable_pieces:
		if piece_nodes.has(pid):
			var pnode = piece_nodes[pid]
			if not pnode.visible:
				continue
			var dist = pnode.global_position.distance_to(local_pos)
			if dist < best_dist:
				best_dist = dist
				best_id = pid

	if best_id < 0:
		return

	# Intercept completed_circuit pieces — show finish confirm instead of dragging
	var piece_node = piece_nodes[best_id]
	if piece_node.is_completed_circuit:
		_show_finish_confirm(best_id)
		return

	dragging_piece_id = best_id
	piece_node.start_drag()

	drag_valid_destinations = _calc_destinations_for_piece(best_id)
	board.set_highlights(drag_valid_destinations)
	junction_path_map = _calc_junction_map_for_piece(best_id)

	_set_action("Drag to a highlighted node")
	AudioManager.play_sfx("piece_pickup")

func _update_drag(local_pos: Vector2) -> void:
	if dragging_piece_id < 0:
		return
	if not piece_nodes.has(dragging_piece_id):
		return

	var piece_node = piece_nodes[dragging_piece_id]
	piece_node.position = local_pos
	current_snap = board.update_snap_indicator(local_pos, drag_valid_destinations)
	if current_snap.size() > 0:
		piece_node.position = local_pos.lerp(current_snap["position"], 0.4)
	piece_node.queue_redraw()

func _end_drag() -> void:
	if dragging_piece_id < 0:
		return

	var piece_node = piece_nodes[dragging_piece_id]
	var pid = dragging_piece_id
	dragging_piece_id = -1

	if current_snap.size() > 0:
		piece_node.end_drag(current_snap["position"])
		board.clear_highlights()
		_set_action("")
		action_popup.visible = false
		awaiting_piece_select = false
		_deselect_all_pieces()
		chosen_snap_node = current_snap.get("node_id", -1)
		NetworkManager.send_message({
			"type": "select_piece",
			"payload": {
				"piece_id": pid,
				"result_index": selected_result_index
			}
		})
		AudioManager.play_sfx("piece_place")
	else:
		piece_node.cancel_drag()
		current_snap = {}
		_set_action("Drop on a highlighted node!")
		AudioManager.play_sfx("piece_cancel")

func _calc_destinations_for_piece(pid: int) -> Array:
	var dest_nodes: Array = []
	var results = GameState.pending_results
	if selected_result_index >= results.size():
		return dest_nodes
	var result_name = results[selected_result_index]
	var distance = _result_to_distance(result_name)

	for piece_data in GameState.pieces:
		var piece_id = int(piece_data.get("id", 0))
		if piece_id != pid:
			continue
		var status = piece_data.get("status", "Home")
		var completed = piece_data.get("completed_circuit", false)

		# Completed-circuit piece at node 0: any throw finishes → destination is node 0
		if completed and status == "OnBoard":
			dest_nodes = [0]
			break

		if status == "Home":
			if distance > 0:
				dest_nodes = board.calc_destinations(0, "Outer", distance)
			# BackDo on Home = stays home, no valid destinations
		elif status == "OnBoard":
			var node_id = piece_data.get("node", null)
			var path_str = piece_data.get("path", "Outer")
			if path_str == null:
				path_str = "Outer"
			if node_id != null:
				if distance < 0:
					# BackDo: move backward using reverse graph
					var prev = board.get_prev_node(int(node_id), path_str)
					if prev >= 0:
						dest_nodes = [prev]
					else:
						dest_nodes = [int(node_id)]  # can't go back, stay
				else:
					dest_nodes = board.calc_destinations(int(node_id), path_str, distance)
					# If piece would pass through finish (node 0) mid-movement,
					# add node 0 as a valid click target so the player can choose to finish.
					# The server auto-finishes on pass-through, so this just enables the UI.
					if not (0 in dest_nodes) and board.passes_through_finish(int(node_id), path_str, distance):
						dest_nodes.append(0)
		break
	return dest_nodes

func _calc_junction_map_for_piece(pid: int) -> Dictionary:
	var results = GameState.pending_results
	if selected_result_index >= results.size():
		return {}
	var result_name = results[selected_result_index]
	var distance = _result_to_distance(result_name)
	if distance <= 0:
		return {}
	for piece_data in GameState.pieces:
		var piece_id = int(piece_data.get("id", 0))
		if piece_id != pid:
			continue
		var status = piece_data.get("status", "Home")
		if status == "Home":
			return {}
		elif status == "OnBoard":
			var node_id = piece_data.get("node", null)
			var path_str = piece_data.get("path", "Outer")
			if path_str == null:
				path_str = "Outer"
			if node_id != null:
				return board.calc_junction_path_map(int(node_id), path_str, distance)
		break
	return {}

func _select_piece(piece_id: int) -> void:
	awaiting_piece_select = false
	_deselect_all_pieces()
	board.clear_highlights()
	_set_action("")
	action_popup.visible = false
	NetworkManager.send_message({
		"type": "select_piece",
		"payload": {
			"piece_id": piece_id,
			"result_index": selected_result_index
		}
	})

func _show_finish_confirm(piece_id: int) -> void:
	finish_confirm_piece_id = piece_id
	finish_confirm_panel.visible = true
	_set_action("")
	AudioManager.play_sfx("piece_pickup")

func _on_finish_confirm_yes() -> void:
	AudioManager.play_sfx("ui_click")
	var pid = finish_confirm_piece_id
	finish_confirm_panel.visible = false
	finish_confirm_piece_id = -1
	if pid >= 0:
		_select_piece(pid)

func _on_finish_confirm_no() -> void:
	AudioManager.play_sfx("ui_back")
	finish_confirm_panel.visible = false
	finish_confirm_piece_id = -1
	# Let player pick a different piece or throw
	if GameState.is_my_turn() and GameState.pending_results.size() > 0:
		_set_action("Pick another piece")
	else:
		_set_action("")

func _on_path_chosen(choice: String) -> void:
	AudioManager.play_sfx("ui_click")
	path_choice_panel.visible = false
	action_popup.visible = false
	NetworkManager.send_message({
		"type": "select_path",
		"payload": {"path_choice": choice}
	})

func _auto_respond_path_choice(paths: Array) -> void:
	if chosen_snap_node >= 0 and junction_path_map.has(chosen_snap_node):
		var choice = junction_path_map[chosen_snap_node]
		if choice in paths:
			NetworkManager.send_message({
				"type": "select_path",
				"payload": {"path_choice": choice}
			})
			junction_path_map = {}
			chosen_snap_node = -1
			return
	if paths.size() == 1:
		NetworkManager.send_message({
			"type": "select_path",
			"payload": {"path_choice": paths[0]}
		})
		return
	_show_path_choice(paths)

# ─── SERVER MESSAGES ───

func _on_server_message(data: Dictionary) -> void:
	var msg_type = data.get("type", "")
	var payload = data.get("payload", {})

	match msg_type:
		"yut_result":
			var result = payload.get("result", "")
			var extra = payload.get("extra_turn", false)
			_yut_anim_playing = true
			yut_animation.play_throw_animation(result, extra)
			camera.shake(3.0, 0.15)
			if extra:
				await get_tree().create_timer(0.3).timeout
				camera.heavy_shake(0.4)
				camera.flash(0.1)
				camera.zoom_punch(0.18, 0.35)

		"piece_moved":
			var piece_id = int(payload.get("piece_id", 0))
			var new_node = int(payload.get("new_position", 0))
			var captured = payload.get("captured", [])
			var finished = payload.get("finished", false)
			# Detect stacking: if another friendly piece is already on target node
			if not finished and captured.size() == 0:
				var moving_owner = -1
				for pd in GameState.pieces:
					if int(pd.get("id", -1)) == piece_id:
						moving_owner = int(pd.get("owner", -1))
						break
				if moving_owner >= 0:
					for pd in GameState.pieces:
						var pid = int(pd.get("id", -1))
						if pid != piece_id and int(pd.get("owner", -1)) == moving_owner \
								and pd.get("status", "") == "OnBoard" \
								and int(pd.get("node_id", -1)) == new_node:
							AudioManager.play_sfx("piece_stack")
							break
			_animate_piece_move(piece_id, new_node, captured, finished)

		"path_choice_required":
			var paths = payload.get("available_paths", [])
			_auto_respond_path_choice(paths)

# ─── PIECE MANAGEMENT ───

func _assign_player_zodiac(player_id: int) -> int:
	if not player_zodiac.has(player_id):
		# Pick random zodiac from 12 animals, no duplicates across players
		var available: Array = []
		for i in range(12):
			if i not in used_zodiac_indices:
				available.append(i)
		if available.is_empty():
			# Fallback if somehow all 12 are used (shouldn't happen with ≤4 players)
			available = range(12)
		# Use player_id as seed for deterministic randomization
		var idx = (hash(player_id) * 7 + 3) % available.size()
		var chosen = available[idx]
		player_zodiac[player_id] = chosen
		used_zodiac_indices.append(chosen)
	return player_zodiac[player_id]

func _sync_pieces() -> void:
	var home_index: Dictionary = {}

	var player_index_map: Dictionary = {}
	for i in range(GameState.players.size()):
		var pid = int(GameState.players[i].get("id", -1))
		player_index_map[pid] = i

	var in_stack_of: Dictionary = {}
	for piece_data in GameState.pieces:
		var stacked = piece_data.get("stacked_with", [])
		if stacked.size() > 0:
			var lead_pid = int(piece_data.get("id", 0))
			for sid in stacked:
				var sid_int = int(sid)
				if sid_int > lead_pid:
					in_stack_of[sid_int] = lead_pid

	var node_occupants: Dictionary = {}
	for piece_data in GameState.pieces:
		var pid = int(piece_data.get("id", 0))
		var status = piece_data.get("status", "Home")
		var node_id = piece_data.get("node", null)
		if status == "OnBoard" and node_id != null and not in_stack_of.has(pid):
			var nid = int(node_id)
			if not node_occupants.has(nid):
				node_occupants[nid] = []
			node_occupants[nid].append(pid)

	# Determine which player has the current turn (for bounce)
	var current_turn_owner = GameState.current_turn

	for piece_data in GameState.pieces:
		var pid = int(piece_data.get("id", 0))
		var owner = int(piece_data.get("owner", 0))
		var status = piece_data.get("status", "Home")
		var node_id = piece_data.get("node", null)

		if not piece_nodes.has(pid):
			_create_piece_node(pid, owner)

		var piece_node = piece_nodes[pid]

		if piece_node.is_animating:
			continue

		piece_node.piece_status = status
		piece_node.is_completed_circuit = piece_data.get("completed_circuit", false)
		var is_being_dragged = (pid == dragging_piece_id and piece_node.is_dragging)

		# Set bounce for current turn's home pieces
		piece_node.is_turn_bounce = (owner == current_turn_owner and status == "Home")

		if status == "OnBoard" and in_stack_of.has(pid):
			piece_node.visible = false
			continue

		if status == "OnBoard" and node_id != null:
			var nid = int(node_id)
			var target_pos = board.get_node_position(nid)
			if node_occupants.has(nid) and node_occupants[nid].size() > 1:
				var occupants = node_occupants[nid]
				var idx = occupants.find(pid)
				var count = occupants.size()
				var offset_step = Vector2(14, 14)
				var start_offset = -offset_step * (count - 1) * 0.5
				target_pos += start_offset + offset_step * idx
			if not is_being_dragged:
				piece_node.set_base_position(target_pos)
			piece_node.visible = true
			piece_node.is_home_display = false
		elif status == "Finished":
			piece_node.visible = false
		elif status == "Home":
			var player_idx = player_index_map.get(owner, 0)
			if not home_index.has(owner):
				home_index[owner] = 0
			var slot = home_index[owner]
			var home_pos = board.get_home_position(player_idx, slot)
			if not is_being_dragged:
				piece_node.set_base_position(home_pos)
			piece_node.visible = true
			piece_node.is_home_display = true
			home_index[owner] = slot + 1
		else:
			piece_node.visible = false

		var stacked = piece_data.get("stacked_with", [])
		piece_node.set_stack(1 + stacked.size())
		piece_node.queue_redraw()

func _create_piece_node(piece_id: int, owner_id: int) -> void:
	var piece_script = load("res://scripts/game/piece_controller.gd")
	var piece_node = Node2D.new()
	piece_node.set_script(piece_script)
	var zodiac = _assign_player_zodiac(owner_id)
	piece_node.setup(piece_id, owner_id, zodiac)
	pieces_container.add_child(piece_node)
	piece_nodes[piece_id] = piece_node

func _animate_piece_move(piece_id: int, target_node: int, captured: Array, finished: bool) -> void:
	if not piece_nodes.has(piece_id):
		return

	for cid in captured:
		var captured_id = int(cid)
		if piece_nodes.has(captured_id):
			piece_nodes[captured_id].is_animating = true

	var piece_node = piece_nodes[piece_id]
	var target_pos = board.get_node_position(target_node)

	if finished:
		piece_node.animate_finish()
		camera.shake(3.0, 0.2)
		AudioManager.play_sfx("piece_finish")
		return

	if piece_node.piece_status == "Home" or not piece_node.visible:
		piece_node.piece_status = "OnBoard"
		piece_node.animate_deploy(target_pos, func():
			camera.shake(2.0, 0.1)
			_handle_post_move_captures(captured)
		)
		AudioManager.play_sfx("piece_deploy")
	else:
		piece_node.visible = true
		piece_node.piece_status = "OnBoard"
		piece_node.animate_move([target_pos], func():
			camera.shake(1.5, 0.08)
			_handle_post_move_captures(captured)
		)
		AudioManager.play_sfx("piece_move")

func _handle_post_move_captures(captured: Array) -> void:
	if captured.size() > 0:
		camera.freeze_frame(0.06)
		camera.heavy_shake(0.3)
		AudioManager.play_sfx("piece_burst")
		AudioManager.play_sfx("piece_capture")

	for cid in captured:
		var captured_id = int(cid)
		if piece_nodes.has(captured_id):
			piece_nodes[captured_id].animate_capture()

func _deselect_all_pieces() -> void:
	for node in piece_nodes.values():
		node.set_selected(false)

func _get_my_movable_pieces() -> Array:
	var result = []
	# Check if current result is BackDo (backward move)
	var is_backdo = false
	var results = GameState.pending_results
	if selected_result_index < results.size():
		is_backdo = (results[selected_result_index] == "BackDo")

	for piece_data in GameState.pieces:
		var owner = int(piece_data.get("owner", 0))
		var status = piece_data.get("status", "Home")
		var completed = piece_data.get("completed_circuit", false)
		if owner == GameState.player_id and status != "Finished":
			# BackDo can't move Home pieces — skip them
			if is_backdo and status == "Home":
				continue
			# BackDo can't move pieces waiting at finish (completed_circuit at node 0)
			if is_backdo and completed:
				continue
			result.append(int(piece_data.get("id", 0)))
	return result

func _on_error(message: String) -> void:
	_set_action("ERR: " + message)
	await get_tree().create_timer(1.5).timeout
	# Re-enable input after error — don't leave the player stuck
	if GameState.is_my_turn():
		if GameState.must_throw:
			_show_throw_prompt()
		else:
			_show_piece_select()
	else:
		_refresh_marquee()
		var pname = _get_player_name(GameState.current_turn)
		_set_action(pname + "'s turn...")

func _get_player_name(pid: int) -> String:
	for p in GameState.players:
		if int(p.get("id", -1)) == pid:
			return p.get("name", "P" + str(pid))
	return "P" + str(pid)

# ─── INPUT RECOVERY SYSTEM ───

func _is_input_active() -> bool:
	## Returns true if any input mode is currently enabled
	if yut_input.enabled:
		return true
	if awaiting_piece_select:
		return true
	if dragging_piece_id >= 0:
		return true
	if path_choice_panel.visible:
		return true
	if finish_confirm_panel and finish_confirm_panel.visible:
		return true
	return false

func _check_input_recovery() -> void:
	## Safety net: if it's my turn, no animation playing, and no input active, re-show prompts.
	## This prevents the player from getting stuck after state sync / timing issues.
	if _yut_anim_playing:
		return
	if _is_input_active():
		return
	if not GameState.is_my_turn():
		return
	# Check that no pieces are currently animating (wait for animations to finish)
	for node in piece_nodes.values():
		if node.is_animating:
			return

	# We're stuck — re-enable the appropriate input
	if GameState.must_throw:
		_show_throw_prompt()
	elif GameState.pending_results.size() > 0:
		_show_piece_select()
