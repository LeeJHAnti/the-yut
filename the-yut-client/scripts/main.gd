extends Node

@onready var title_screen = $TitleScreen
@onready var waiting_room = $WaitingRoom
@onready var game_screen = $GameScreen
@onready var game_over_screen = $GameOverScreen

func _ready() -> void:
	# Start on title screen
	_show_screen("title")

	# Listen for state changes to auto-navigate
	GameState.state_updated.connect(_on_state_updated)
	GameState.game_over_signal.connect(_on_game_over)

func _show_screen(screen_name: String) -> void:
	title_screen.visible = (screen_name == "title")
	waiting_room.visible = (screen_name == "waiting")
	game_screen.visible = (screen_name == "game")
	game_over_screen.visible = (screen_name == "gameover")

	# ── BGM switching per screen ──
	match screen_name:
		"title":
			AudioManager.play_bgm("title")
		"game":
			AudioManager.play_bgm("ingame")
		# "gameover" BGM is handled by game_over.gd with fade

func _on_state_updated() -> void:
	match GameState.phase:
		"WaitingForPlayers":
			if GameState.room_code != "":
				_show_screen("waiting")
		"DecidingOrder", "Throwing", "SelectingPiece", "SelectingPath":
			_show_screen("game")
		"GameOver":
			pass  # handled by _on_game_over

func _on_game_over(winner_id: int, winner_name: String) -> void:
	_show_screen("gameover")

func go_to_title() -> void:
	GameState.reset()
	_show_screen("title")

func go_to_waiting() -> void:
	_show_screen("waiting")
