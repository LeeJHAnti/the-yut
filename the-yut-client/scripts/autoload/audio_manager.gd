extends Node

## Audio Manager — 90s Fusion Jazz BGM + SFX
## Autoloaded singleton. Call AudioManager.play_sfx("name") from anywhere.
## Includes persistent sound UI overlay (speaker icon + volume slider + mute).

# ═══ SFX Preloads ═══
const SFX_MAP: Dictionary = {
	"yut_throw":    preload("res://assets/audio/sfx/sfx_yut_throw.wav"),
	"yut_land":     preload("res://assets/audio/sfx/sfx_yut_land.wav"),
	"yut_extra":    preload("res://assets/audio/sfx/sfx_extra_turn.wav"),
	"piece_move":   preload("res://assets/audio/sfx/sfx_piece_move.wav"),
	"piece_land":   preload("res://assets/audio/sfx/sfx_piece_land.wav"),
	"piece_capture":preload("res://assets/audio/sfx/sfx_piece_capture.wav"),
	"piece_burst":  preload("res://assets/audio/sfx/sfx_piece_burst.wav"),
	"piece_crash":  preload("res://assets/audio/sfx/sfx_piece_crash.wav"),
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
# Title: 1 fixed track  |  In-game: 5 random tracks  |  Game Over: 1 fixed track
# Style: 90s Japanese arcade fusion jazz × Korean traditional (gugak) arrangement
const BGM_TRACKS: Dictionary = {
	"title":    [preload("res://assets/audio/bgm/bgm_title.mp3")],
	"ingame":   [
		preload("res://assets/audio/bgm/bgm_ingame_1.mp3"),
		preload("res://assets/audio/bgm/bgm_ingame_2.mp3"),
		preload("res://assets/audio/bgm/bgm_ingame_3.mp3"),
		preload("res://assets/audio/bgm/bgm_ingame_4.mp3"),
		preload("res://assets/audio/bgm/bgm_ingame_5.mp3"),
	],
	"gameover": [preload("res://assets/audio/bgm/bgm_gameover.mp3")],
}

# ═══ Audio Players ═══
var bgm_player: AudioStreamPlayer
var sfx_players: Array = []
const SFX_POOL_SIZE := 8

var current_bgm: String = ""
var bgm_volume: float = -6.0   # dB
var sfx_volume: float = -14.0   # dB (lowered vs BGM -6dB for balance)

# ═══ Mute / Volume State ═══
var is_muted: bool = false
var pre_mute_master_vol: float = 0.0   # saved master volume before mute
var master_volume_linear: float = 0.8  # 0.0 ~ 1.0

# ═══ UI Overlay ═══
var ui_layer: CanvasLayer
var sound_btn: Control  # custom drawn speaker icon
var slider_panel: Control  # volume slider container
var volume_slider: HSlider
var slider_visible: bool = false
var _btn_anim_time: float = 0.0

# ── Theme colors ──
const COL_BG      = Color("503820")
const COL_BG_LITE = Color("6B4C30")
const COL_CREAM   = Color("F8F0E0")
const COL_MID     = Color("D4B888")
const COL_ACCENT  = Color("58B068")
const COL_MUTED   = Color("D05848")

func _ready() -> void:
	# ── Audio players ──
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Master"
	bgm_player.volume_db = bgm_volume
	add_child(bgm_player)

	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = sfx_volume
		add_child(player)
		sfx_players.append(player)

	# ── Apply initial master volume ──
	_apply_master_volume()

	# ── Build UI overlay ──
	_build_sound_ui()

func _process(delta: float) -> void:
	_btn_anim_time += delta
	if sound_btn:
		sound_btn.queue_redraw()

# ═══════════════════════════════════════
#  SOUND UI OVERLAY
# ═══════════════════════════════════════

func _build_sound_ui() -> void:
	# CanvasLayer on top of everything
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)

	# ── Speaker icon button (bottom-right) ──
	sound_btn = Control.new()
	sound_btn.custom_minimum_size = Vector2(44, 44)
	sound_btn.size = Vector2(44, 44)
	sound_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	sound_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	sound_btn.position = Vector2(-52, -52)
	sound_btn.gui_input.connect(_on_btn_input)
	sound_btn.draw.connect(_draw_speaker_icon)
	ui_layer.add_child(sound_btn)

	# ── Slider panel (hidden by default) ──
	slider_panel = Control.new()
	slider_panel.custom_minimum_size = Vector2(160, 60)
	slider_panel.size = Vector2(160, 60)
	slider_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	slider_panel.position = Vector2(-210, -62)
	slider_panel.visible = false
	slider_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	slider_panel.draw.connect(_draw_slider_bg)
	ui_layer.add_child(slider_panel)

	# ── Volume slider inside panel ──
	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = master_volume_linear
	volume_slider.custom_minimum_size = Vector2(120, 20)
	volume_slider.size = Vector2(120, 20)
	volume_slider.position = Vector2(20, 28)
	volume_slider.value_changed.connect(_on_volume_changed)

	# Style the slider to match pixel theme
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = COL_CREAM
	grabber_style.set_border_width_all(1)
	grabber_style.border_color = COL_BG
	grabber_style.set_corner_radius_all(2)
	grabber_style.content_margin_left = 6
	grabber_style.content_margin_right = 6
	grabber_style.content_margin_top = 6
	grabber_style.content_margin_bottom = 6
	volume_slider.add_theme_stylebox_override("grabber_area", _make_slider_track(COL_ACCENT))
	volume_slider.add_theme_stylebox_override("grabber_area_highlight", _make_slider_track(COL_ACCENT))
	volume_slider.add_theme_stylebox_override("slider", _make_slider_track(COL_BG_LITE))
	volume_slider.add_theme_icon_override("grabber", ImageTexture.new())
	volume_slider.add_theme_icon_override("grabber_highlight", ImageTexture.new())
	# Use a flat grabber via styleboxes
	volume_slider.add_theme_constant_override("grabber_offset", 0)

	slider_panel.add_child(volume_slider)

func _make_slider_track(color: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(2)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _draw_speaker_icon() -> void:
	# Pixel-art speaker icon drawn procedurally
	var cx = 22.0
	var cy = 22.0

	# Background circle
	var bg_color = COL_MUTED if is_muted else COL_BG
	var pulse = 0.0
	if not is_muted:
		pulse = sin(_btn_anim_time * 2.0) * 0.05
	sound_btn.draw_circle(Vector2(cx, cy), 20 + pulse * 4, bg_color)
	sound_btn.draw_circle(Vector2(cx, cy), 18, Color(bg_color, 0.7))

	# Speaker body (rectangle + triangle)
	var spk_color = COL_CREAM
	# Body rect
	sound_btn.draw_rect(Rect2(cx - 10, cy - 5, 8, 10), spk_color)
	# Cone triangle
	var cone = PackedVector2Array([
		Vector2(cx - 2, cy - 5),
		Vector2(cx + 6, cy - 10),
		Vector2(cx + 6, cy + 10),
		Vector2(cx - 2, cy + 5),
	])
	sound_btn.draw_colored_polygon(cone, spk_color)

	if is_muted:
		# X mark
		sound_btn.draw_line(Vector2(cx + 8, cy - 6), Vector2(cx + 16, cy + 6), COL_CREAM, 2.5)
		sound_btn.draw_line(Vector2(cx + 16, cy - 6), Vector2(cx + 8, cy + 6), COL_CREAM, 2.5)
	else:
		# Sound waves (arcs)
		var vol_level = master_volume_linear
		var wave_alpha = 0.4 + sin(_btn_anim_time * 3.0) * 0.2

		if vol_level > 0.1:
			# Small wave
			_draw_arc(sound_btn, Vector2(cx + 6, cy), 6, -0.6, 0.6, Color(spk_color, wave_alpha))
		if vol_level > 0.4:
			# Medium wave
			_draw_arc(sound_btn, Vector2(cx + 6, cy), 10, -0.5, 0.5, Color(spk_color, wave_alpha * 0.8))
		if vol_level > 0.7:
			# Large wave
			_draw_arc(sound_btn, Vector2(cx + 6, cy), 14, -0.4, 0.4, Color(spk_color, wave_alpha * 0.6))

func _draw_arc(target: Control, center: Vector2, radius: float, angle_from: float, angle_to: float, color: Color) -> void:
	var points = 8
	for i in range(points):
		var t1 = angle_from + (angle_to - angle_from) * float(i) / float(points)
		var t2 = angle_from + (angle_to - angle_from) * float(i + 1) / float(points)
		var p1 = center + Vector2(cos(t1), sin(t1)) * radius
		var p2 = center + Vector2(cos(t2), sin(t2)) * radius
		target.draw_line(p1, p2, color, 2.0)

func _draw_slider_bg() -> void:
	# Panel background matching game theme
	var r = Rect2(0, 0, 160, 60)
	slider_panel.draw_rect(r, COL_BG)
	slider_panel.draw_rect(Rect2(2, 2, 156, 56), Color(COL_BG_LITE, 0.5))
	slider_panel.draw_rect(r, COL_MID, false, 2.0)

	# Label
	var font = ThemeDB.fallback_font
	var label = "MUTED" if is_muted else "VOLUME"
	var label_color = COL_MUTED if is_muted else COL_CREAM
	slider_panel.draw_string(font, Vector2(20, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_color)

	# Volume percentage
	var pct = str(int(master_volume_linear * 100)) + "%"
	slider_panel.draw_string(font, Vector2(115, 18), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_MID)

# ═══ Input Handling ═══
# State machine: tap cycles through → show slider → mute → unmute+hide slider

func _on_btn_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not slider_visible and not is_muted:
			# State 1: nothing shown → show slider
			slider_visible = true
			slider_panel.visible = true
			slider_panel.queue_redraw()
			play_sfx("ui_click")
		elif slider_visible and not is_muted:
			# State 2: slider shown → mute + hide slider
			_toggle_mute()
			slider_visible = false
			slider_panel.visible = false
		elif is_muted:
			# State 3: muted → unmute
			_toggle_mute()
		sound_btn.accept_event()

func _toggle_mute() -> void:
	is_muted = not is_muted
	if is_muted:
		pre_mute_master_vol = master_volume_linear
		AudioServer.set_bus_volume_db(0, -80.0)
		play_sfx("ui_back")
	else:
		master_volume_linear = pre_mute_master_vol
		_apply_master_volume()
		play_sfx("ui_click")
	# Update slider position
	volume_slider.set_value_no_signal(master_volume_linear if not is_muted else 0.0)
	slider_panel.queue_redraw()

func _on_volume_changed(value: float) -> void:
	master_volume_linear = value
	if is_muted and value > 0:
		# Unmute when slider is moved
		is_muted = false
	_apply_master_volume()
	slider_panel.queue_redraw()

func _apply_master_volume() -> void:
	if is_muted:
		AudioServer.set_bus_volume_db(0, -80.0)
	else:
		# Convert linear 0~1 to dB (-40 ~ 0)
		if master_volume_linear <= 0.0:
			AudioServer.set_bus_volume_db(0, -80.0)
		else:
			var db = linear_to_db(master_volume_linear)
			AudioServer.set_bus_volume_db(0, db)

# ═══════════════════════════════════════
#  Hide UI during gameplay drag (optional)
# ═══════════════════════════════════════

func set_ui_visible(vis: bool) -> void:
	if sound_btn:
		sound_btn.visible = vis
	if slider_panel and not vis:
		slider_panel.visible = false
		slider_visible = false

# ═══════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════

func _get_free_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	return sfx_players[0]

func play_sfx(sfx_name: String) -> void:
	if is_muted:
		return
	if sfx_name in SFX_MAP:
		var player = _get_free_sfx_player()
		player.stream = SFX_MAP[sfx_name]
		player.volume_db = sfx_volume
		player.play()
	else:
		print("[Audio] Unknown SFX: ", sfx_name)

func play_bgm(track_name: String = "ingame") -> void:
	if track_name == current_bgm and bgm_player.playing:
		return
	if track_name in BGM_TRACKS:
		var tracks = BGM_TRACKS[track_name]
		# Pick a random track from the array
		var stream = tracks[randi() % tracks.size()]
		bgm_player.stream = stream
		# Enable infinite looping
		if bgm_player.stream is AudioStreamMP3:
			bgm_player.stream.loop = true
		elif bgm_player.stream is AudioStreamWAV:
			bgm_player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			bgm_player.stream.loop_end = bgm_player.stream.data.size() / 2
		bgm_player.volume_db = bgm_volume
		bgm_player.play()
		current_bgm = track_name
	else:
		print("[Audio] Unknown BGM: ", track_name)

func stop_bgm() -> void:
	bgm_player.stop()
	current_bgm = ""

func fade_bgm(duration: float = 1.0) -> void:
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
