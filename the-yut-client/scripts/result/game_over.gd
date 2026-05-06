extends Control

## Game over screen with cute animal decorations

@onready var winner_label: Label = $VBox/WinnerLabel
@onready var play_again_btn: Button = $VBox/PlayAgainBtn
@onready var exit_btn: Button = $VBox/LobbyBtn

# Decoration sprites
const TEX_DECO_FLOWER = preload("res://assets/sprites/deco_flower.png")
const TEX_DECO_STAR = preload("res://assets/sprites/deco_star.png")
const TEX_DECO_PAW = preload("res://assets/sprites/deco_paw.png")

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

var sparkle_timer: float = 0.0
var deco_time: float = 0.0
var confetti_animals: Array = []  # celebration animals

func _ready() -> void:
	play_again_btn.pressed.connect(_on_play_again)
	exit_btn.pressed.connect(_on_exit)
	GameState.game_over_signal.connect(_on_game_over)

func _on_game_over(winner_id: int, winner_name: String) -> void:
	var is_my_win = (winner_id == GameState.player_id)
	# In team mode, check if the winner is our teammate
	if not is_my_win and GameState.is_team_mode():
		is_my_win = GameState.are_teammates(GameState.player_id, winner_id)

	if is_my_win:
		if GameState.is_team_mode():
			winner_label.text = "TEAM WIN!"
		else:
			winner_label.text = "YOU WIN!"
	else:
		winner_label.text = winner_name + "\nWINS!"

	AudioManager.fade_bgm(0.5)
	# Wait for fade to finish, then play victory or game_over sound
	get_tree().create_timer(0.55).timeout.connect(func():
		if is_my_win:
			AudioManager.play_bgm("victory")
		else:
			AudioManager.play_bgm("victory")
			AudioManager.play_sfx("game_over")
	)

	# Victory animation: scale bounce
	var tween = create_tween()
	winner_label.scale = Vector2(0.3, 0.3)
	tween.tween_property(winner_label, "scale", Vector2(1.2, 1.2), 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(winner_label, "scale", Vector2(1.0, 1.0), 0.1)

	# Setup confetti animals
	confetti_animals.clear()
	for i in range(6):
		confetti_animals.append({
			"idx": randi() % 12,
			"x": randf_range(30, size.x - 30),
			"y": randf_range(-80, -20),
			"speed": randf_range(60, 140),
			"wobble_phase": randf_range(0, TAU),
		})

func _process(delta: float) -> void:
	deco_time += delta
	# Animate confetti animals falling
	for a in confetti_animals:
		a["y"] += a["speed"] * delta
		if a["y"] > size.y + 60:
			a["y"] = randf_range(-80, -20)
			a["x"] = randf_range(30, size.x - 30)
			a["idx"] = randi() % 12
	queue_redraw()

func _draw() -> void:
	var w = size.x
	var h = size.y

	# Scattered flowers
	if TEX_DECO_FLOWER:
		var fs = TEX_DECO_FLOWER.get_size()
		var flower_positions = [
			Vector2(40, 50), Vector2(w - 50, 60), Vector2(30, h - 60),
			Vector2(w - 40, h - 50), Vector2(w * 0.5 - 150, 80),
			Vector2(w * 0.5 + 140, 90),
		]
		for i in range(flower_positions.size()):
			var fp = flower_positions[i]
			var bob = sin(deco_time * 1.5 + i * 1.1) * 3.0
			draw_texture(TEX_DECO_FLOWER, fp - fs * 0.5 + Vector2(0, bob), Color(1, 1, 1, 0.4))

	# Stars twinkling
	if TEX_DECO_STAR:
		var ss = TEX_DECO_STAR.get_size()
		for i in range(8):
			var sx = 40 + i * 60
			var sy = 30 + sin(i * 2.1) * 20
			var twinkle = 0.15 + sin(deco_time * 3.0 + i * 1.5) * 0.2
			draw_texture(TEX_DECO_STAR, Vector2(sx, sy) - ss * 0.5, Color(1, 1, 1, twinkle))

	# Paw prints along bottom
	if TEX_DECO_PAW:
		var ps = TEX_DECO_PAW.get_size()
		for i in range(6):
			var px = 50 + i * 80
			draw_texture(TEX_DECO_PAW, Vector2(px, h - 35) - ps * 0.5, Color(1, 1, 1, 0.2))

	# Confetti falling animals
	for a in confetti_animals:
		var tex = ZODIAC_SPRITES[a["idx"]]
		var ts = tex.get_size()
		var wobble_x = sin(deco_time * 2.0 + a["wobble_phase"]) * 15.0
		var pos = Vector2(a["x"] + wobble_x, a["y"]) - ts * 0.75
		draw_texture_rect(tex, Rect2(pos, ts * 1.5), false, Color(1, 1, 1, 0.6))

func _on_play_again() -> void:
	AudioManager.play_sfx("ui_click")
	NetworkManager.send_message({"type": "start_game", "payload": {}})

func _on_exit() -> void:
	AudioManager.play_sfx("ui_back")
	GameState.reset()
	get_parent().go_to_title()
