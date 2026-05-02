extends Node2D

## Pixel-art yut throw animation.
## 4 yut sticks spin in the air, land with bounce, then show the result.
## Flat side (엎) = bright with cross marks,  Round side (뒤) = dark with highlight.
## Result text shown in Korean: 도 / 개 / 걸 / 윷 / 모

signal animation_finished

const ParticleEffects = preload("res://scripts/game/particle_effects.gd")

# ═══ Preload yut stick sprite textures ═══
const STICK_SPRITES_FLAT: Array = [
	preload("res://assets/sprites/yut_stick_0.png"),  # flat side variant 0
	preload("res://assets/sprites/yut_stick_1.png"),  # flat side variant 1
	preload("res://assets/sprites/yut_stick_2.png"),  # flat side variant 2
	preload("res://assets/sprites/yut_stick_3.png"),  # flat side variant 3
]
const STICK_SPRITE_ROUND = preload("res://assets/sprites/yut_stick_back.png")
const STICK_SPRITE_BAEKDO = preload("res://assets/sprites/yut_stick_back_baekdo.png")

# ═══ Preload Korean result text sprites ═══
const RESULT_TEXTURES: Dictionary = {
	"Do": preload("res://assets/sprites/result_do.png"),
	"Gae": preload("res://assets/sprites/result_gae.png"),
	"Geol": preload("res://assets/sprites/result_geol.png"),
	"Yut": preload("res://assets/sprites/result_yut.png"),
	"Mo": preload("res://assets/sprites/result_mo.png"),
}

var sticks: Array = []   # [{flat, pos, rotation, spin_speed, ...}]
var result_text: String = ""
var result_kr: String = ""   # Korean name
var show_result: bool = false
var result_scale: float = 0.0
var result_glow: float = 0.0
var is_extra: bool = false
var anim_phase: int = 0   # 0=idle, 1=flying, 2=landing, 3=showing result

# Stick pixel dimensions — scaled for 520x960 portrait throw area
# Sprites are 24×72 px; render at ~1.5x for good visibility in throw area
const STICK_W := 36       # display width  (24 * 1.5)
const STICK_H := 108      # display height (72 * 1.5)
const STICK_SPACING := 56  # spacing between sticks

func _draw() -> void:
	if anim_phase == 0 and sticks.is_empty():
		return

	# Draw shadow under each stick
	for stick in sticks:
		if stick.landed:
			var spos = stick.pos as Vector2
			_draw_ellipse(Vector2(spos.x, spos.y + STICK_H * 0.5 + 4), 12.0, 4.0, Color("503820", 0.35))

	# Draw yut sticks
	for stick in sticks:
		_draw_stick(stick)

	# Result popup
	if show_result and result_text != "":
		_draw_result_popup()

func _draw_stick(stick: Dictionary) -> void:
	var pos = stick.pos as Vector2
	var rot = stick.rotation as float
	var is_flat = stick.flat as bool
	var hw = STICK_W / 2.0
	var hh = STICK_H / 2.0

	draw_set_transform(pos, rot, Vector2.ONE)

	# Use sprite textures for yut sticks
	var tex: Texture2D = null
	if is_flat:
		var idx = stick.get("stick_index", 0) % STICK_SPRITES_FLAT.size()
		tex = STICK_SPRITES_FLAT[idx]
	else:
		# One specific stick shows the baekdo mark on its back
		var is_baekdo_stick = stick.get("is_baekdo_stick", false)
		tex = STICK_SPRITE_BAEKDO if is_baekdo_stick else STICK_SPRITE_ROUND

	if tex:
		var tex_size = tex.get_size()
		# Scale sprite to match stick dimensions
		var scale_x = float(STICK_W) / tex_size.x
		var scale_y = float(STICK_H) / tex_size.y
		var draw_size = Vector2(STICK_W, STICK_H)
		draw_texture_rect(tex, Rect2(-hw, -hh, draw_size.x, draw_size.y), false)
	else:
		# Fallback to manual drawing
		if is_flat:
			draw_rect(Rect2(-hw, -hh, STICK_W, STICK_H), Color("E0C898"))
			draw_rect(Rect2(-hw, -hh, STICK_W, STICK_H), Color("503820"), false, 1.5)
		else:
			draw_rect(Rect2(-hw + 1, -hh, STICK_W - 2, STICK_H), Color("907040"))
			draw_rect(Rect2(-hw + 1, -hh, STICK_W - 2, STICK_H), Color("503820"), false, 1.5)

	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_rpg_panel(center: Vector2, w: float, h: float, alpha: float = 1.0) -> void:
	## Draw a Nintendo RPG-style beveled panel (like dialog boxes in Pokemon/FF)
	var hw = w * 0.5
	var hh = h * 0.5
	var rect = Rect2(center.x - hw, center.y - hh, w, h)
	var r = 6.0  # corner radius
	# Drop shadow
	var shadow = Rect2(rect.position + Vector2(3, 3), rect.size)
	draw_rect(shadow, Color("503820", 0.25 * alpha))
	# Main fill
	draw_rect(rect, Color("F8F0D8", alpha))
	# Outer border (dark)
	draw_rect(rect, Color("503820", alpha), false, 3.0)
	# Inner border (light inset) — gives the RPG double-border look
	var inset = Rect2(rect.position + Vector2(4, 4), rect.size - Vector2(8, 8))
	draw_rect(inset, Color("907040", 0.5 * alpha), false, 1.5)
	# Top highlight line
	draw_line(
		Vector2(rect.position.x + 5, rect.position.y + 3),
		Vector2(rect.position.x + rect.size.x - 5, rect.position.y + 3),
		Color("FFFCF0", 0.6 * alpha), 1.0)
	# Bottom shadow line
	draw_line(
		Vector2(rect.position.x + 5, rect.position.y + rect.size.y - 3),
		Vector2(rect.position.x + rect.size.x - 5, rect.position.y + rect.size.y - 3),
		Color("907040", 0.4 * alpha), 1.0)

func _draw_result_popup() -> void:
	var font = ThemeDB.fallback_font
	var center = Vector2(0, -85)
	var s = result_scale

	draw_set_transform(center, 0, Vector2(s, s))

	# Glow effect behind panel (for Yut/Mo extra turn)
	if is_extra and result_glow > 0:
		# Radial glow lines
		for i in range(12):
			var angle = TAU * i / 12.0 + result_glow * 2.0
			var inner_r = 50.0
			var outer_r = 65.0 + result_glow * 12.0
			var p1 = Vector2(cos(angle) * inner_r, sin(angle) * inner_r)
			var p2 = Vector2(cos(angle) * outer_r, sin(angle) * outer_r)
			draw_line(p1, p2, Color("E0C898", result_glow * 0.5), 2.5)
		# Outer glow ring
		draw_arc(Vector2.ZERO, 58 + result_glow * 8, 0, TAU, 32,
			Color("E0C898", result_glow * 0.35), 3.0)

	# ─── RPG-style beveled panel ───
	_draw_rpg_panel(Vector2.ZERO, 136, 86)

	# Korean result text sprite (pre-rendered pixel art)
	var result_tex = RESULT_TEXTURES.get(result_text, null)
	if result_tex:
		var tex_size = result_tex.get_size()
		var draw_size = tex_size * 1.35
		var tex_offset = -draw_size * 0.5 + Vector2(0, -6)
		# Shadow
		draw_texture_rect(result_tex, Rect2(tex_offset + Vector2(2, 2), draw_size), false, Color("907040", 0.5))
		# Main
		draw_texture_rect(result_tex, Rect2(tex_offset, draw_size), false, Color("503820"))
	else:
		# Fallback: English text — centered in panel
		var text_w = font.get_string_size(result_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		draw_string(font, Vector2(-text_w * 0.5, 6), result_text,
			HORIZONTAL_ALIGNMENT_LEFT, 120, 28, Color("503820"))

	# Distance label centered under the result
	var dist_text = _get_distance_label(result_text)
	if dist_text != "":
		var dist_w = font.get_string_size(dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(-dist_w * 0.5, 30), dist_text,
			HORIZONTAL_ALIGNMENT_LEFT, 50, 12, Color("907040"))

	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# ─── "EXTRA TURN!" RPG banner for Yut/Mo ───
	if is_extra:
		var badge_y = center.y + 58 * s
		var badge_alpha = clampf(result_scale, 0, 1)
		var pulse = 1.0 + sin(result_glow * 8) * 0.08
		draw_set_transform(Vector2(center.x, badge_y), 0, Vector2(pulse, pulse))

		# RPG-style badge panel
		_draw_rpg_panel(Vector2.ZERO, 130, 32, badge_alpha)

		# Star decorations on each side
		var star_offset = 52.0
		for side in [-1.0, 1.0]:
			var sx = side * star_offset
			var star_pulse = 0.6 + sin(result_glow * 6.0 + side * 1.5) * 0.3
			_draw_mini_star(Vector2(sx, 0), 5.0, Color("E0C898", star_pulse * badge_alpha))

		# "EXTRA TURN!" text centered in the banner
		var et_text = "EXTRA TURN!"
		var et_w = font.get_string_size(et_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(-et_w * 0.5, 5), et_text,
			HORIZONTAL_ALIGNMENT_LEFT, 130, 13, Color("503820", badge_alpha))

		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_mini_star(pos: Vector2, size: float, color: Color) -> void:
	## Draw a small 4-pointed star decoration
	var points = PackedVector2Array()
	for i in range(8):
		var angle = TAU * i / 8.0 - PI / 8.0
		var r = size if i % 2 == 0 else size * 0.4
		points.append(pos + Vector2(cos(angle) * r, sin(angle) * r))
	draw_colored_polygon(points, color)

func _get_distance_label(result: String) -> String:
	match result:
		"Do": return "+1"
		"Gae": return "+2"
		"Geol": return "+3"
		"Yut": return "+4"
		"Mo": return "+5"
		"BackDo": return "-1"
	return ""

func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(8):
		var angle = TAU * i / 8.0
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(points, color)

func play_throw_animation(yut_result: String, extra_turn: bool) -> void:
	result_text = yut_result
	result_kr = _get_korean(yut_result)
	is_extra = extra_turn
	show_result = false
	result_glow = 0.0
	sticks.clear()
	anim_phase = 1

	# Determine which sticks are flat
	var flat_count = _get_flat_count(yut_result)
	var flat_indices = []
	var indices = [0, 1, 2, 3]
	indices.shuffle()
	for i in range(flat_count):
		flat_indices.append(indices[i])

	# Stick 0 is always the baekdo-marked stick (has mark on its back side).
	# For BackDo result, the baekdo stick must be the one that landed flat.
	var baekdo_stick_idx: int = 0
	if yut_result == "BackDo":
		if not (baekdo_stick_idx in flat_indices):
			if flat_indices.size() > 0:
				flat_indices[0] = baekdo_stick_idx

	# Initialize sticks — centered in throw area
	# YutAnimation is positioned at the center of the throw area.
	# Sticks must stay within roughly ±140 x, ±80 y of origin.
	var total_w = 3 * STICK_SPACING
	var start_x = -total_w / 2.0 - STICK_SPACING / 2.0  # center around origin
	for i in range(4):
		sticks.append({
			"flat": i in flat_indices,
			"stick_index": i,  # for selecting sprite variant
			"is_baekdo_stick": (i == baekdo_stick_idx),
			"pos": Vector2(start_x + i * STICK_SPACING, -60),
			"rotation": randf_range(-PI, PI),
			"spin_speed": randf_range(10.0, 18.0) * (1 if randf() > 0.5 else -1),
			"final_pos": Vector2(start_x + i * STICK_SPACING + randf_range(-6, 6), randf_range(-5, 5)),
			"final_rot": randf_range(-0.20, 0.20),
			"landed": false,
			"land_delay": i * 0.06,
		})

	queue_redraw()
	_animate_throw()

func _animate_throw() -> void:
	var tween = create_tween()

	# Phase 1: Sticks fly up and spin (constrained within area)
	for i in range(4):
		var stick = sticks[i]
		var peak_y = -100 - randf_range(0, 20)

		tween.parallel().tween_method(
			func(val: float):
				sticks[i].pos.y = val
				sticks[i].rotation += sticks[i].spin_speed * get_process_delta_time()
				queue_redraw(),
			sticks[i].pos.y,
			peak_y,
			0.2 + stick.land_delay
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Phase 2: Sticks fall down and land sequentially
	tween.tween_interval(0.05)

	for i in range(4):
		var final_p = sticks[i].final_pos
		var final_rot = sticks[i].final_rot

		tween.parallel().tween_method(
			func(val: float):
				sticks[i].pos.y = val
				var t = clampf((val - (-100)) / (final_p.y - (-100)), 0, 1)
				sticks[i].rotation = lerpf(sticks[i].rotation, final_rot, t * t)
				queue_redraw(),
			-80.0,
			final_p.y,
			0.18 + sticks[i].land_delay
		).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

		tween.parallel().tween_method(
			func(val: float): sticks[i].pos.x = val; queue_redraw(),
			sticks[i].pos.x,
			final_p.x,
			0.18 + sticks[i].land_delay
		)

	# Phase 3: Landing effects
	tween.tween_callback(func():
		anim_phase = 2
		for i in range(4):
			sticks[i].landed = true
			sticks[i].pos = sticks[i].final_pos
			sticks[i].rotation = sticks[i].final_rot
		ParticleEffects.spawn_dust(self, Vector2(0, 20), 12)
		AudioManager.play_sfx("yut_land")
		queue_redraw()
	)

	tween.tween_interval(0.15)

	# Phase 4: Show result with punch-in
	tween.tween_callback(func():
		anim_phase = 3
		show_result = true
	)

	# Punch scale animation
	tween.tween_method(
		func(val: float): result_scale = val; queue_redraw(),
		0.0, 1.5, 0.08
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(val: float): result_scale = val; queue_redraw(),
		1.5, 0.9, 0.05
	)
	tween.tween_method(
		func(val: float): result_scale = val; queue_redraw(),
		0.9, 1.0, 0.04
	)

	# Extra turn special effects
	if is_extra:
		tween.tween_callback(func():
			AudioManager.play_sfx("yut_extra")
			ParticleEffects.spawn_stars(self, Vector2(0, -105), 16)
		)
		tween.tween_method(
			func(val: float): result_glow = val; queue_redraw(),
			0.0, 1.0, 0.3
		)
		tween.tween_method(
			func(val: float): result_glow = val; queue_redraw(),
			1.0, 0.5, 0.2
		)
		tween.tween_interval(0.8)
	else:
		tween.tween_interval(0.6)

	# Done
	tween.tween_callback(func():
		anim_phase = 0
		animation_finished.emit()
	)

func _get_flat_count(result: String) -> int:
	match result:
		"Mo": return 0      # 모: all round (0 flat)
		"Do": return 1      # 도: 1 flat
		"BackDo": return 1  # 백도: 1 flat (the baekdo-marked stick)
		"Gae": return 2     # 개: 2 flat
		"Geol": return 3    # 걸: 3 flat
		"Yut": return 4     # 윷: all flat (4 flat)
	return 0

func _get_korean(result: String) -> String:
	match result:
		"Mo": return "모"
		"Do": return "도"
		"BackDo": return "백도"
		"Gae": return "개"
		"Geol": return "걸"
		"Yut": return "윷"
	return ""

func clear() -> void:
	sticks.clear()
	show_result = false
	result_text = ""
	result_kr = ""
	result_glow = 0.0
	anim_phase = 0
	queue_redraw()
