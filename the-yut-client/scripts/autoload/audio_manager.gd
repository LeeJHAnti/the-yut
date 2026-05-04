extends Node

## Audio Manager — GBA-style chiptune BGM + SFX
## Autoloaded singleton. Call AudioManager.play_sfx("name") from anywhere.

# ═══ SFX Preloads ═══
const SFX_MAP: Dictionary = {
	"yut_throw":    preload("res://assets/audio/sfx/sfx_yut_throw.wav"),
	"yut_land":     preload("res://assets/audio/sfx/sfx_yut_land.wav"),
	"yut_extra":    preload("res://assets/audio/sfx/sfx_extra_turn.wav"),
	"piece_move":   preload("res://assets/audio/sfx/sfx_piece_move.wav"),
	"piece_land":   preload("res://assets/audio/sfx/sfx_piece_land.wav"),
	"piece_capture":preload("res://assets/audio/sfx/sfx_piece_capture.wav"),
	"piece_stack":  preload("res://assets/audio/sfx/sfx_piece_stack.wav"),
	"piece_pickup": preload("res://assets/audio/sfx/sfx_piece_select.wav"),
	"piece_place":  preload("res://assets/audio/sfx/sfx_piece_land.wav"),
	"piece_cancel": preload("res://assets/audio/sfx/sfx_ui_back.wav"),
	"piece_deploy": preload("res://assets/audio/sfx/sfx_piece_deploy.wav"),
	"piece_finish": preload("res://assets/audio/sfx/sfx_finish.wav"),
	"turn_start":   preload("res://assets/audio/sfx/sfx_turn_start.wav"),
	"extra_turn":   preload("res://assets/audio/sfx/sfx_extra_turn.wav"),
	"ui_click":     preload("res://assets/audio/sfx/sfx_ui_click.wav"),
	"ui_back":      preload("res://assets/audio/sfx/sfx_ui_back.wav"),
	"game_over":    preload("res://assets/audio/sfx/sfx_game_over.wav"),
	"path_choice":  preload("res://assets/audio/sfx/sfx_path_choice.wav"),
}

# ═══ BGM Preloads ═══
const BGM_MAP: Dictionary = {
	"title":   preload("res://assets/audio/bgm/bgm_title.wav"),
	"ingame":  preload("res://assets/audio/bgm/bgm_ingame.wav"),
	"victory": preload("res://assets/audio/bgm/bgm_victory.wav"),
}

# ═══ Audio Players ═══
var bgm_player: AudioStreamPlayer
var sfx_players: Array = []  # pool of SFX players
const SFX_POOL_SIZE := 6

var current_bgm: String = ""
var bgm_volume: float = -6.0   # dB — background music volume
var sfx_volume: float = -3.0   # dB — sound effects volume

func _ready() -> void:
	# Create BGM player
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Master"
	bgm_player.volume_db = bgm_volume
	add_child(bgm_player)

	# Create SFX player pool
	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = sfx_volume
		add_child(player)
		sfx_players.append(player)

func _get_free_sfx_player() -> AudioStreamPlayer:
	# Find a free player in the pool
	for player in sfx_players:
		if not player.playing:
			return player
	# All busy — reuse the oldest (first in array)
	return sfx_players[0]

# ═══════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════

func play_sfx(sfx_name: String) -> void:
	if sfx_name in SFX_MAP:
		var player = _get_free_sfx_player()
		player.stream = SFX_MAP[sfx_name]
		player.volume_db = sfx_volume
		player.play()
	else:
		print("[Audio] Unknown SFX: ", sfx_name)

func play_bgm(track_name: String = "ingame") -> void:
	if track_name == current_bgm and bgm_player.playing:
		return  # already playing this track
	if track_name in BGM_MAP:
		bgm_player.stream = BGM_MAP[track_name]
		bgm_player.volume_db = bgm_volume
		bgm_player.play()
		current_bgm = track_name
	else:
		print("[Audio] Unknown BGM: ", track_name)

func stop_bgm() -> void:
	bgm_player.stop()
	current_bgm = ""

func fade_bgm(duration: float = 1.0) -> void:
	## Fade out current BGM over duration seconds
	if not bgm_player.playing:
		return
	var tween = create_tween()
	tween.tween_property(bgm_player, "volume_db", -40.0, duration)
	tween.tween_callback(func():
		bgm_player.stop()
		bgm_player.volume_db = bgm_volume
		current_bgm = ""
	)

func set_bgm_volume(vol_db: float) -> void:
	bgm_volume = vol_db
	bgm_player.volume_db = vol_db

func set_sfx_volume(vol_db: float) -> void:
	sfx_volume = vol_db
	for player in sfx_players:
		player.volume_db = vol_db
