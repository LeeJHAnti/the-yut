extends Node

signal state_updated
signal turn_changed(player_id: int)
signal game_over_signal(winner_id: int, winner_name: String)
signal error_received(message: String)

var player_id: int = -1
var player_name: String = ""
var session_token: String = ""
var room_code: String = ""
var is_host: bool = false

var players: Array = []
var pieces: Array = []
var current_turn: int = 0
var pending_results: Array = []
var must_throw: bool = true
var phase: String = "WaitingForPlayers"
var winner: int = -1
var teams: Array = []  # [[id_a, id_b], [id_c, id_d]] for 4-player team mode, empty otherwise

func _ready() -> void:
	NetworkManager.message_received.connect(_on_message)
	# Generate random default name
	player_name = "Player_%04d" % (randi() % 10000)

func _on_message(data: Dictionary) -> void:
	var msg_type = data.get("type", "")
	var payload = data.get("payload", {})

	match msg_type:
		"room_created":
			room_code = payload.get("code", "")
			player_id = int(payload.get("player_id", "0"))
			session_token = payload.get("session_token", "")
			is_host = true
			# Host is the first player — seed the players array
			players = [{"id": player_id, "name": player_name, "is_host": true, "is_bot": false}]
			state_updated.emit()

		"room_joined":
			room_code = payload.get("room_code", "")
			player_id = int(payload.get("player_id", "0"))
			session_token = payload.get("session_token", "")
			players = payload.get("players", [])
			is_host = false
			state_updated.emit()

		"player_joined":
			var new_player = {
				"id": int(payload.get("player_id", "0")),
				"name": payload.get("player_name", ""),
			}
			players.append(new_player)
			state_updated.emit()

		"player_left":
			var left_id = int(payload.get("player_id", "0"))
			players = players.filter(func(p): return p.get("id", -1) != left_id)
			state_updated.emit()

		"game_started":
			players = payload.get("players", [])
			phase = "Throwing"
			state_updated.emit()

		"your_turn":
			current_turn = int(payload.get("player_id", "0"))
			must_throw = payload.get("can_throw", true)
			turn_changed.emit(current_turn)

		"yut_result":
			var result = payload.get("result", "")
			var distance = int(payload.get("distance", 0))
			var extra_turn = payload.get("extra_turn", false)
			# Track the result locally so pending_results stays up to date
			# (important for extra turns where server doesn't send game_state_sync)
			pending_results.append(result)
			if extra_turn:
				must_throw = true
			else:
				must_throw = false
			state_updated.emit()

		"piece_moved":
			state_updated.emit()

		"game_state_sync":
			_apply_sync(payload)
			state_updated.emit()

		"game_over":
			var winner_id = int(payload.get("winner_id", "0"))
			var winner_name_str = payload.get("winner_name", "")
			winner = winner_id
			phase = "GameOver"
			game_over_signal.emit(winner_id, winner_name_str)

		"error":
			var message = payload.get("message", "Unknown error")
			print("[Server Error] ", message)
			error_received.emit(message)

func _apply_sync(data: Dictionary) -> void:
	if data.has("players"):
		players = data["players"]
	if data.has("pieces"):
		pieces = data["pieces"]
	if data.has("current_turn"):
		current_turn = int(data["current_turn"])
	if data.has("pending_results"):
		pending_results = data["pending_results"]
	if data.has("must_throw"):
		must_throw = data["must_throw"]
	if data.has("phase"):
		phase = data["phase"]
	if data.has("teams") and data["teams"] != null:
		teams = data["teams"]
	elif data.has("teams"):
		teams = []

func is_my_turn() -> bool:
	return current_turn == player_id

func is_team_mode() -> bool:
	return teams.size() > 0

func get_teammate_id() -> int:
	## Returns the teammate's player_id, or -1 if not in team mode.
	for team in teams:
		if team is Array and player_id in team:
			for tid in team:
				if int(tid) != player_id:
					return int(tid)
	return -1

func are_teammates(a: int, b: int) -> bool:
	if a == b:
		return true
	for team in teams:
		if team is Array and a in team and b in team:
			return true
	return false

func get_team_index(pid: int) -> int:
	## Returns 0 or 1 for team index, -1 if not in team mode.
	for i in range(teams.size()):
		if teams[i] is Array and pid in teams[i]:
			return i
	return -1

func reset() -> void:
	player_id = -1
	session_token = ""
	room_code = ""
	is_host = false
	players.clear()
	pieces.clear()
	current_turn = 0
	pending_results.clear()
	must_throw = true
	phase = "WaitingForPlayers"
	winner = -1
	teams = []
