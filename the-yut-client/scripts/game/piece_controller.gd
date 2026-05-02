extends Node2D

## Piece controller — Sprite-based zodiac animal pieces
## Uses pixel art sprite assets instead of manual _draw() calls.

const ParticleEffects = preload("res://scripts/game/particle_effects.gd")

# ═══ Preload sprite textures — 12 Zodiac Animals ═══
const ZODIAC_SPRITES: Array = [
	preload("res://assets/sprites/piece_rat.png"),       # 0: 쥐
	preload("res://assets/sprites/piece_ox.png"),        # 1: 소
	preload("res://assets/sprites/piece_tiger.png"),     # 2: 호랑이
	preload("res://assets/sprites/piece_rabbit.png"),    # 3: 토끼
	preload("res://assets/sprites/piece_dragon.png"),    # 4: 용
	preload("res://assets/sprites/piece_snake.png"),     # 5: 뱀
	preload("res://assets/sprites/piece_horse.png"),     # 6: 말
	preload("res://assets/sprites/piece_sheep.png"),     # 7: 양
	preload("res://assets/sprites/piece_monkey.png"),    # 8: 원숭이
	preload("res://assets/sprites/piece_rooster.png"),   # 9: 닭
	preload("res://assets/sprites/piece_dog.png"),       # 10: 개
	preload("res://assets/sprites/piece_pig.png"),       # 11: 돼지
]
const ZODIAC_NAMES: Array = [
	"쥐", "소", "호랑이", "토끼", "용", "뱀",
	"말", "양", "원숭이", "닭", "개", "돼지",
]
const TEX_SELECTION_RING = preload("res://assets/sprites/selection_ring.png")

var piece_id: int = 0
var owner_id: int = 0
var piece_status: String = "Home"  # Home, OnBoard, Finished

# Warm Pastel Wood Color Palette
const GBC_DARK     := Color("503820")
const GBC_MID_DARK := Color("907040")
const GBC_MID      := Color("E0C898")
const GBC_BRIGHT   := Color("FFFCF0")

# Per-player tint colors — soft pastel tones
const PLAYER_COLORS: Array = [
	Color("D05848"),  # Player 0: Soft ruby
	Color("5880C8"),  # Player 1: Soft sapphire
	Color("58B068"),  # Player 2: Soft emerald
	Color("A870C8"),  # Player 3: Soft amethyst
]

const PLAYER_OUTLINE_COLORS: Array = [
	Color("6C2820"),  # Dark red
	Color("283860"),  # Dark blue
	Color("284828"),  # Dark green
	Color("483060"),  # Dark purple
]

# Each piece gets a zodiac animal index (0-11, mapped to 12 zodiac sprites)
var zodiac_index: int = 0

var stack_count: int = 1
var is_animating: bool = false
var is_selected: bool = false
var is_home_display: bool = false
var is_dragging: bool = false
var is_turn_bounce: bool = false  # current turn's home pieces bounce
var is_completed_circuit: bool = false  # waiting at finish to score
var drag_origin: Vector2 = Vector2.ZERO
var bob_time: float = 0.0
var ghost_trail: Array = []
var base_position: Vector2 = Vector2.ZERO  # fixed reference position

# ─── EXPRESSION ANIMATION STATE ───
var expression_timer: float = 0.0       # countdown for next expression event
var expression_active: bool = false     # currently showing expression
var expression_type: int = 0            # 0=blink, 1=happy bounce, 2=sparkle
var expression_progress: float = 0.0    # 0~1 animation progress
var land_squash_time: float = -1.0      # >0 = playing landing squash animation

func set_base_position(pos: Vector2) -> void:
	base_position = pos
	position = pos

func _process(delta: float) -> void:
	# Position control (skip during animations and drags)
	if not is_animating and not is_dragging:
		if is_selected:
			# Selected piece: gentle bob relative to base_position
			bob_time += delta * 5.0
			position.y = base_position.y + sin(bob_time) * 2.0
			queue_redraw()
		elif is_completed_circuit:
			# Completed circuit pieces: subtle pulse animation
			bob_time += delta * 3.0
			queue_redraw()
		elif is_turn_bounce and is_home_display:
			# Current turn's home pieces: subtle breathing bounce
			bob_time += delta * 3.0
			position.y = base_position.y + sin(bob_time) * 1.0
			queue_redraw()
		elif base_position != Vector2.ZERO:
			# Not selected, not bouncing: lock to base position
			position = base_position

	# Expression animation tick (on-board pieces only)
	if piece_status == "OnBoard" and not is_dragging:
		if expression_active:
			expression_progress += delta * 4.0
			if expression_progress >= 1.0:
				expression_active = false
				expression_progress = 0.0
				expression_timer = randf_range(3.0, 7.0)
			queue_redraw()
		else:
			expression_timer -= delta
			if expression_timer <= 0:
				expression_active = true
				expression_type = randi() % 3  # blink, happy, sparkle
				expression_progress = 0.0

	# Landing squash animation
	if land_squash_time >= 0:
		land_squash_time += delta * 6.0
		if land_squash_time > 1.0:
			land_squash_time = -1.0
		queue_redraw()

	# Ghost trail fade (always runs)
	var i = ghost_trail.size() - 1
	while i >= 0:
		ghost_trail[i].alpha -= delta * 5.0
		if ghost_trail[i].alpha <= 0:
			ghost_trail.remove_at(i)
		i -= 1
	if ghost_trail.size() > 0:
		queue_redraw()

func _draw() -> void:
	if piece_status == "Finished":
		return

	# ─── DRAGGING ───
	if is_dragging:
		var color = PLAYER_COLORS[owner_id % 4]
		draw_circle(Vector2(4, 6), 28, Color(GBC_DARK, 0.5))
		_draw_zodiac_at(Vector2.ZERO, color, 1.35)
		_draw_selection_ring(1.4, 0.7)
		if stack_count > 1:
			_draw_stack_badges(1.2)
		return

	# ─── HOME pieces in tray ───
	if piece_status == "Home" and is_home_display:
		var home_color = PLAYER_COLORS[owner_id % 4]
		home_color.a = 0.8
		_draw_zodiac_at(Vector2.ZERO, home_color, 0.78)
		if is_selected:
			var glow_alpha = 0.3 + sin(bob_time * 2) * 0.2
			_draw_selection_ring(0.78, glow_alpha)
		return

	if piece_status == "Home":
		return

	# ─── ON BOARD pieces ───
	for g in ghost_trail:
		var ghost_color = Color(GBC_MID_DARK, g.alpha * 0.4)
		var ghost_pos = g.pos - global_position + position
		_draw_zodiac_at(ghost_pos, ghost_color, 0.8)

	var color = PLAYER_COLORS[owner_id % 4]
	var piece_scale = 1.1
	# Landing squash effect
	if land_squash_time >= 0:
		var t = land_squash_time
		var squash_x = 1.0 + sin(t * PI) * 0.25
		var squash_y = 1.0 - sin(t * PI) * 0.20
		piece_scale *= squash_y  # vertical squash applied via scale
		# We'll handle squash via draw transform instead
		draw_set_transform(Vector2.ZERO, 0, Vector2(squash_x, squash_y))

	_draw_zodiac_at(Vector2.ZERO, color, piece_scale)

	# Expression overlay (on-board only)
	if expression_active:
		_draw_expression(piece_scale)

	if land_squash_time >= 0:
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Completed circuit indicator — pulsing gold ring (waiting to score)
	if is_completed_circuit:
		var pulse = 0.5 + sin(bob_time * 3.0) * 0.3
		draw_arc(Vector2.ZERO, 24, 0, TAU, 24, Color("E0C898", pulse), 2.5)
		draw_arc(Vector2.ZERO, 27, 0, TAU, 24, Color("907040", pulse * 0.5), 1.5)

	if is_selected:
		var glow_alpha = 0.4 + sin(bob_time * 2) * 0.3
		_draw_selection_ring(1.0, glow_alpha)

	if stack_count > 1:
		_draw_stack_badges(0.9)

# ═══════════════════════════════════════════════════
# SPRITE-BASED ZODIAC DRAWING
# ═══════════════════════════════════════════════════

func _draw_zodiac_at(pos: Vector2, color: Color, s: float) -> void:
	var sprite_idx = zodiac_index % ZODIAC_SPRITES.size()
	var tex = ZODIAC_SPRITES[sprite_idx]
	if tex == null:
		draw_circle(pos, 14 * s, color)
		return
	var tex_size = tex.get_size()
	var draw_size = tex_size * s
	var offset = pos - draw_size * 0.5
	var alpha = color.a

	# Player-colored base circle (beneath the sprite)
	var base_r = max(draw_size.x, draw_size.y) * 0.40
	if alpha > 0.15:
		# Drop shadow
		draw_circle(pos + Vector2(1, 2) * s, base_r, Color(GBC_DARK, 0.2 * alpha))
		# Player color disc
		draw_circle(pos, base_r, Color(color.r, color.g, color.b, 0.45 * alpha))
		# Player color ring
		draw_arc(pos, base_r, 0, TAU, 16, Color(color.r, color.g, color.b, 0.7 * alpha), 1.5 * s)

	# Draw sprite with original pastel colors (alpha only, no color tint)
	draw_texture_rect(tex, Rect2(offset, draw_size), false, Color(1.0, 1.0, 1.0, alpha))

func _draw_expression(s: float) -> void:
	## Draw expression overlay effects on the piece
	var t = expression_progress
	match expression_type:
		0:  # BLINK — close eyes briefly
			if t < 0.3 or t > 0.7:
				return  # only show blink in the middle
			var blink_alpha = sin((t - 0.3) / 0.4 * PI) * 0.9
			# Draw small horizontal lines over eye area
			var eye_y = -4.0 * s
			draw_line(Vector2(-6 * s, eye_y), Vector2(-2 * s, eye_y),
				Color(GBC_DARK, blink_alpha), 2.0 * s)
			draw_line(Vector2(2 * s, eye_y), Vector2(6 * s, eye_y),
				Color(GBC_DARK, blink_alpha), 2.0 * s)
		1:  # HAPPY — draw ^_^ eyes and bounce
			var happy_alpha = sin(t * PI)
			var eye_y = -4.0 * s
			# ^  ^ eyes
			draw_line(Vector2(-6 * s, eye_y), Vector2(-4 * s, eye_y - 2 * s),
				Color(GBC_DARK, happy_alpha), 1.5 * s)
			draw_line(Vector2(-4 * s, eye_y - 2 * s), Vector2(-2 * s, eye_y),
				Color(GBC_DARK, happy_alpha), 1.5 * s)
			draw_line(Vector2(2 * s, eye_y), Vector2(4 * s, eye_y - 2 * s),
				Color(GBC_DARK, happy_alpha), 1.5 * s)
			draw_line(Vector2(4 * s, eye_y - 2 * s), Vector2(6 * s, eye_y),
				Color(GBC_DARK, happy_alpha), 1.5 * s)
		2:  # SPARKLE — tiny stars around the piece
			var sparkle_alpha = sin(t * PI) * 0.8
			var sparkle_r = 16.0 * s
			for si in range(3):
				var angle = t * TAU + si * TAU / 3.0
				var sp = Vector2(cos(angle) * sparkle_r, sin(angle) * sparkle_r - 4 * s)
				var star_sz = 2.0 * s
				draw_line(sp + Vector2(-star_sz, 0), sp + Vector2(star_sz, 0),
					Color("E0C898", sparkle_alpha), 1.5)
				draw_line(sp + Vector2(0, -star_sz), sp + Vector2(0, star_sz),
					Color("E0C898", sparkle_alpha), 1.5)

func trigger_land_expression() -> void:
	## Called when piece lands on the board — triggers squash + happy expression
	land_squash_time = 0.0
	expression_active = true
	expression_type = 1  # happy
	expression_progress = 0.0

func _draw_selection_ring(s: float, alpha: float) -> void:
	if TEX_SELECTION_RING:
		var tex_size = TEX_SELECTION_RING.get_size()
		var draw_size = tex_size * s
		var offset = -draw_size * 0.5
		draw_texture_rect(TEX_SELECTION_RING, Rect2(offset, draw_size), false, Color(1, 1, 1, alpha))
	else:
		draw_arc(Vector2.ZERO, 20 * s, 0, TAU, 16, Color(GBC_BRIGHT, alpha), 2.5)

## All individual _draw_*() animal functions have been replaced by sprite textures.
## Sprites are loaded from res://assets/sprites/piece_*.png
## See ZODIAC_SPRITES at the top of this file.

# (removed ~470 lines of manual draw code)

func _placeholder_removed_animals() -> void:
	pass  # Replaced by sprite-based rendering in _draw_zodiac_at()
	# Old functions: _draw_rat, _draw_ox, _draw_tiger, _draw_rabbit,
	# _draw_dragon, _draw_snake, _draw_horse, _draw_sheep,
	# _draw_monkey, _draw_rooster, _draw_dog, _draw_pig
func _draw_stack_badges(s: float) -> void:
	# Stack count badge above the animal
	if stack_count <= 1:
		return
	var badge_pos = Vector2(10, -14) * s
	draw_circle(badge_pos, 7, GBC_DARK)
	draw_circle(badge_pos, 5.5, GBC_BRIGHT)
	var font = ThemeDB.fallback_font
	var count_str = str(stack_count)
	var count_w = font.get_string_size(count_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, badge_pos + Vector2(-count_w * 0.5, 4), count_str,
		HORIZONTAL_ALIGNMENT_LEFT, 12, 11, GBC_DARK)

# ═══════════════════════════════════════════════════
# SETUP & ANIMATIONS (unchanged logic)
# ═══════════════════════════════════════════════════

func setup(p_id: int, p_owner: int, p_zodiac: int = -1) -> void:
	piece_id = p_id
	owner_id = p_owner
	if p_zodiac >= 0:
		zodiac_index = p_zodiac % ZODIAC_SPRITES.size()
	else:
		zodiac_index = randi() % ZODIAC_SPRITES.size()
	# Randomize initial expression timer so pieces don't all blink at once
	expression_timer = randf_range(2.0, 8.0)
	queue_redraw()

func animate_move(path: Array, on_complete: Callable) -> void:
	is_animating = true
	ghost_trail.clear()
	var tween = create_tween()

	for i in range(path.size()):
		var target_pos = path[i] as Vector2
		var prev_pos = position if i == 0 else path[i - 1]

		tween.tween_callback(func():
			ghost_trail.append({"pos": global_position, "alpha": 0.8})
		)
		tween.tween_callback(func():
			var dir = (prev_pos - target_pos).normalized()
			ParticleEffects.spawn_speed_lines(get_parent(), position, dir)
		)

		tween.tween_property(self, "scale", Vector2(1.2, 0.7), 0.04)
		tween.tween_property(self, "position",
			Vector2(target_pos.x, target_pos.y - 30), 0.10) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "scale", Vector2(0.8, 1.4), 0.10)
		tween.tween_property(self, "position", target_pos, 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "scale", Vector2(1.4, 0.6), 0.04)
		tween.tween_callback(func():
			ParticleEffects.spawn_dust(get_parent(), target_pos, 6)
		)
		tween.tween_property(self, "scale", Vector2(0.95, 1.1), 0.04)
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.03)

	var final_pos = path[path.size() - 1] as Vector2
	tween.tween_callback(func():
		is_animating = false
		base_position = final_pos
		position = final_pos
		ghost_trail.clear()
		trigger_land_expression()
		on_complete.call()
	)

func animate_capture() -> void:
	is_animating = true
	ParticleEffects.spawn_impact(get_parent(), position)
	ParticleEffects.spawn_stars(get_parent(), position, 12)

	var tween = create_tween()
	# Brief "hit flash" — scale up then pause for dramatic effect
	tween.tween_property(self, "scale", Vector2(1.6, 1.6), 0.04)
	tween.tween_property(self, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.03)  # white flash
	tween.tween_interval(0.06)  # freeze moment
	tween.tween_property(self, "modulate", Color.WHITE, 0.02)
	# Fly away with spin
	var fly_dir = Vector2(randf_range(-80, 80), -100)
	tween.tween_property(self, "position", position + fly_dir, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "rotation", randf_range(-5, 5), 0.35)
	tween.parallel().tween_property(self, "scale", Vector2(0.2, 0.2), 0.35)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
	# Spawn extra dust at the capture point
	tween.parallel().tween_callback(func():
		ParticleEffects.spawn_dust(get_parent(), position, 8)
	).set_delay(0.05)

	tween.tween_callback(func():
		is_animating = false
		visible = false
		rotation = 0
		scale = Vector2.ONE
		modulate.a = 1.0
		base_position = Vector2.ZERO
	)

func animate_finish() -> void:
	is_animating = true
	ParticleEffects.spawn_sparkles(get_parent(), position, 16)
	ParticleEffects.spawn_stars(get_parent(), position, 12)

	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(self, "position:y", position.y - 50, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.35)
	tween.parallel().tween_callback(func():
		ParticleEffects.spawn_sparkles(get_parent(), position, 8)
	).set_delay(0.15)

	tween.tween_callback(func():
		is_animating = false
		visible = false
		scale = Vector2.ONE
		modulate.a = 1.0
		base_position = Vector2.ZERO
	)

func animate_stack() -> void:
	ParticleEffects.spawn_merge_pulse(get_parent(), position)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.08)
	tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.05)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.04)
	queue_redraw()

func animate_deploy(target_pos: Vector2, on_complete: Callable) -> void:
	is_animating = true
	is_home_display = false
	visible = true
	position = target_pos + Vector2(0, -80)
	modulate.a = 0.0
	scale = Vector2(0.3, 0.3)

	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, 0.25) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), 0.18)
	tween.tween_callback(func():
		ParticleEffects.spawn_dust(get_parent(), target_pos, 8)
	)
	tween.tween_property(self, "scale", Vector2(1.3, 0.7), 0.05)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.05)
	tween.tween_callback(func():
		is_animating = false
		base_position = target_pos
		position = target_pos
		trigger_land_expression()
		on_complete.call()
	)

func start_drag() -> void:
	is_dragging = true
	drag_origin = base_position if base_position != Vector2.ZERO else position
	z_index = 10
	queue_redraw()

func end_drag(snap_pos: Vector2 = Vector2.ZERO) -> void:
	is_dragging = false
	z_index = 0
	if snap_pos != Vector2.ZERO:
		base_position = snap_pos
		position = snap_pos
	queue_redraw()

func cancel_drag() -> void:
	is_dragging = false
	z_index = 0
	base_position = drag_origin
	position = drag_origin
	queue_redraw()

func set_selected(sel: bool) -> void:
	is_selected = sel
	bob_time = 0.0
	if not sel and base_position != Vector2.ZERO:
		position = base_position
	queue_redraw()

func set_stack(count: int) -> void:
	stack_count = count
	if count > 1:
		animate_stack()
	queue_redraw()
