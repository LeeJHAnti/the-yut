extends Node2D

## Piece controller — Sprite-based zodiac animal pieces
## Uses animated sprite sheets with 5 states × 4 frames per animal.

const ParticleEffects = preload("res://scripts/game/particle_effects.gd")

# ═══ Preload sprite textures — 12 Zodiac Animals (base) ═══
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

# ═══ Animation sprite sheets — 5 rows × 4 columns per animal ═══
# Rows: 0=idle, 1=happy, 2=sad, 3=selected, 4=victory
const ZODIAC_ANIM_SHEETS: Array = [
	preload("res://assets/sprites/anim/piece_rat_anim.png"),
	preload("res://assets/sprites/anim/piece_ox_anim.png"),
	preload("res://assets/sprites/anim/piece_tiger_anim.png"),
	preload("res://assets/sprites/anim/piece_rabbit_anim.png"),
	preload("res://assets/sprites/anim/piece_dragon_anim.png"),
	preload("res://assets/sprites/anim/piece_snake_anim.png"),
	preload("res://assets/sprites/anim/piece_horse_anim.png"),
	preload("res://assets/sprites/anim/piece_sheep_anim.png"),
	preload("res://assets/sprites/anim/piece_monkey_anim.png"),
	preload("res://assets/sprites/anim/piece_rooster_anim.png"),
	preload("res://assets/sprites/anim/piece_dog_anim.png"),
	preload("res://assets/sprites/anim/piece_pig_anim.png"),
]

# Animation state enum
enum AnimState { IDLE = 0, HAPPY = 1, SAD = 2, SELECTED = 3, VICTORY = 4 }
const ANIM_FRAME_W := 48
const ANIM_FRAME_H := 48
const ANIM_FRAMES_PER_ROW := 4
const ANIM_FPS := 6.0  # frames per second for sprite sheet animation
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
var stacked_zodiac_info: Array = []  # [{zodiac: int, owner: int}, ...] for side-by-side display
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

# ─── SPRITE SHEET ANIMATION STATE ───
var anim_state: int = AnimState.IDLE      # current animation state (row in sheet)
var anim_time: float = 0.0               # time accumulator for frame cycling
var anim_frame: int = 0                  # current frame index (0-3)
var is_capture_sad: bool = false         # show sad face before capture fly-away
var capture_sad_timer: float = 0.0       # duration of sad expression display
var happy_timer: float = 0.0            # timed happy expression after landing

var land_squash_time: float = -1.0      # >0 = playing landing squash animation

func set_base_position(pos: Vector2) -> void:
	base_position = pos
	position = pos

func _process(delta: float) -> void:
	# ─── Update animation state based on context ───
	_update_anim_state()

	# ─── Advance sprite sheet frame ───
	anim_time += delta
	var frame_duration := 1.0 / ANIM_FPS
	if anim_time >= frame_duration:
		anim_time -= frame_duration
		anim_frame = (anim_frame + 1) % ANIM_FRAMES_PER_ROW
		queue_redraw()

	# ─── Capture sad timer ───
	if is_capture_sad:
		capture_sad_timer -= delta
		if capture_sad_timer <= 0:
			is_capture_sad = false
			_play_capture_flyaway()

	# ─── Happy timer (timed expression after landing) ───
	if happy_timer > 0:
		happy_timer -= delta
		queue_redraw()

	# Always advance bob_time for scale pulse / breathing effects
	bob_time += delta * 4.0

	# Position control (skip during animations and drags)
	if not is_animating and not is_dragging:
		if is_selected:
			position.y = base_position.y + sin(bob_time * 1.3) * 3.5
			queue_redraw()
		elif is_completed_circuit:
			queue_redraw()
		elif is_turn_bounce and is_home_display:
			position.y = base_position.y + sin(bob_time) * 2.0
			queue_redraw()
		elif happy_timer > 0:
			queue_redraw()
		elif base_position != Vector2.ZERO:
			position = base_position

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
		var _drag_diff_zodiac = stacked_zodiac_info.size() > 0 and _check_has_different_zodiac()
		if _drag_diff_zodiac:
			var half_off = 14.0
			var ds = 1.15
			_draw_zodiac_at(Vector2(-half_off, 0), color, ds)
			var left_count = int(stacked_zodiac_info[0].get("count", 1))
			if left_count > 1:
				_draw_side_badge(Vector2(-half_off - 6, -14), left_count)
			if stacked_zodiac_info.size() > 1:
				var info = stacked_zodiac_info[1]
				var stk_owner = int(info.get("owner", 0))
				var stk_zodiac = int(info.get("zodiac", 0))
				var stk_color = PLAYER_COLORS[stk_owner % 4]
				_draw_other_zodiac_at(Vector2(half_off, 0), stk_color, ds, stk_zodiac)
				var right_count = int(info.get("count", 1))
				if right_count > 1:
					_draw_side_badge(Vector2(half_off + 6, -14), right_count)
		else:
			_draw_zodiac_at(Vector2.ZERO, color, 1.35)
			if stack_count > 1:
				_draw_stack_badges(1.2)
		_draw_selection_ring(1.4, 0.7)
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
		_draw_zodiac_at(ghost_pos, ghost_color, 0.8, false)

	var color = PLAYER_COLORS[owner_id % 4]
	var piece_scale = 1.1
	# Landing squash effect
	if land_squash_time >= 0:
		var t = land_squash_time
		var squash_x = 1.0 + sin(t * PI) * 0.25
		var squash_y = 1.0 - sin(t * PI) * 0.20
		piece_scale *= squash_y
		draw_set_transform(Vector2.ZERO, 0, Vector2(squash_x, squash_y))
	# Gentle scale pulse when happy or selected (breathing effect)
	elif anim_state == AnimState.HAPPY or anim_state == AnimState.SELECTED:
		var pulse = 1.0 + sin(bob_time * 4.0) * 0.06
		piece_scale *= pulse
	# Victory bounce pulse
	elif anim_state == AnimState.VICTORY:
		var pulse = 1.0 + sin(bob_time * 5.0) * 0.08
		piece_scale *= pulse

	# Side-by-side display for team stacking with different animal types
	var _has_different_zodiac_stack = stacked_zodiac_info.size() > 0 and _check_has_different_zodiac()
	if _has_different_zodiac_stack:
		# Draw each zodiac group side-by-side (lead left, teammate right)
		var half_offset = 12.0 * piece_scale
		var s = piece_scale * 0.85
		# First group = lead piece zodiac (left)
		_draw_zodiac_at(Vector2(-half_offset, 0), color, s)
		var left_count = int(stacked_zodiac_info[0].get("count", 1))
		if left_count > 1:
			_draw_side_badge(Vector2(-half_offset - 6, -14) * piece_scale, left_count)
		# Second group = teammate zodiac (right)
		if stacked_zodiac_info.size() > 1:
			var info = stacked_zodiac_info[1]
			var stk_owner = int(info.get("owner", 0))
			var stk_zodiac = int(info.get("zodiac", 0))
			var stk_color = PLAYER_COLORS[stk_owner % 4]
			_draw_other_zodiac_at(Vector2(half_offset, 0), stk_color, s, stk_zodiac)
			var right_count = int(info.get("count", 1))
			if right_count > 1:
				_draw_side_badge(Vector2(half_offset + 6, -14) * piece_scale, right_count)
	else:
		_draw_zodiac_at(Vector2.ZERO, color, piece_scale)

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

	if stack_count > 1 and not _has_different_zodiac_stack:
		_draw_stack_badges(0.9)

# ═══════════════════════════════════════════════════
# ANIMATION STATE MANAGEMENT
# ═══════════════════════════════════════════════════

func _update_anim_state() -> void:
	## Determine current animation state based on piece context
	var new_state := AnimState.IDLE
	if is_capture_sad:
		new_state = AnimState.SAD
	elif is_completed_circuit:
		new_state = AnimState.VICTORY
	elif is_selected:
		new_state = AnimState.SELECTED
	elif land_squash_time >= 0 or happy_timer > 0:
		new_state = AnimState.HAPPY
	elif piece_status == "OnBoard":
		new_state = AnimState.IDLE
	# Reset frame on state change for snappy transitions
	if new_state != anim_state:
		anim_frame = 0
		anim_time = 0.0
	anim_state = new_state

# ═══════════════════════════════════════════════════
# SPRITE-BASED ZODIAC DRAWING (with animation sheets)
# ═══════════════════════════════════════════════════

func _draw_zodiac_at(pos: Vector2, color: Color, s: float, use_anim: bool = true) -> void:
	var sprite_idx = zodiac_index % ZODIAC_SPRITES.size()
	var alpha = color.a

	# Player-colored base circle (beneath the sprite)
	var frame_size := Vector2(ANIM_FRAME_W, ANIM_FRAME_H)
	var draw_size = frame_size * s
	var base_r = max(draw_size.x, draw_size.y) * 0.40
	if alpha > 0.15:
		draw_circle(pos + Vector2(1, 2) * s, base_r, Color(GBC_DARK, 0.2 * alpha))
		draw_circle(pos, base_r, Color(color.r, color.g, color.b, 0.45 * alpha))
		draw_arc(pos, base_r, 0, TAU, 16, Color(color.r, color.g, color.b, 0.7 * alpha), 1.5 * s)

	# Try animated sprite sheet first
	if use_anim and sprite_idx < ZODIAC_ANIM_SHEETS.size():
		var sheet = ZODIAC_ANIM_SHEETS[sprite_idx]
		if sheet != null:
			var src_rect = Rect2(
				anim_frame * ANIM_FRAME_W,
				anim_state * ANIM_FRAME_H,
				ANIM_FRAME_W, ANIM_FRAME_H
			)
			var dst_rect = Rect2(pos - draw_size * 0.5, draw_size)
			draw_texture_rect_region(sheet, dst_rect, src_rect, Color(1.0, 1.0, 1.0, alpha))
			return

	# Fallback to base sprite
	var tex = ZODIAC_SPRITES[sprite_idx]
	if tex == null:
		draw_circle(pos, 14 * s, color)
		return
	var tex_size = tex.get_size()
	draw_size = tex_size * s
	var offset = pos - draw_size * 0.5
	draw_texture_rect(tex, Rect2(offset, draw_size), false, Color(1.0, 1.0, 1.0, alpha))

func _check_has_different_zodiac() -> bool:
	## Returns true if stacked pieces include more than one zodiac type
	## stacked_zodiac_info is grouped: [{zodiac, owner, count}, ...]
	return stacked_zodiac_info.size() > 1

func _draw_other_zodiac_at(pos: Vector2, color: Color, s: float, z_index_override: int) -> void:
	## Draw another zodiac animal (used for side-by-side team stacking)
	var sprite_idx = z_index_override % ZODIAC_SPRITES.size()
	var alpha = color.a
	var frame_size := Vector2(ANIM_FRAME_W, ANIM_FRAME_H)
	var draw_size = frame_size * s

	var base_r = max(draw_size.x, draw_size.y) * 0.40
	if alpha > 0.15:
		draw_circle(pos + Vector2(1, 2) * s, base_r, Color(GBC_DARK, 0.2 * alpha))
		draw_circle(pos, base_r, Color(color.r, color.g, color.b, 0.45 * alpha))
		draw_arc(pos, base_r, 0, TAU, 16, Color(color.r, color.g, color.b, 0.7 * alpha), 1.5 * s)

	if sprite_idx < ZODIAC_ANIM_SHEETS.size():
		var sheet = ZODIAC_ANIM_SHEETS[sprite_idx]
		if sheet != null:
			var src_rect = Rect2(
				anim_frame * ANIM_FRAME_W,
				AnimState.IDLE * ANIM_FRAME_H,
				ANIM_FRAME_W, ANIM_FRAME_H
			)
			var dst_rect = Rect2(pos - draw_size * 0.5, draw_size)
			draw_texture_rect_region(sheet, dst_rect, src_rect, Color(1.0, 1.0, 1.0, alpha))
			return

	var tex = ZODIAC_SPRITES[sprite_idx]
	if tex == null:
		draw_circle(pos, 14 * s, color)
		return
	var tex_size = tex.get_size()
	draw_size = tex_size * s
	var offset = pos - draw_size * 0.5
	draw_texture_rect(tex, Rect2(offset, draw_size), false, Color(1.0, 1.0, 1.0, alpha))

func trigger_land_expression() -> void:
	## Called when piece lands on the board — triggers squash + happy expression
	land_squash_time = 0.0
	happy_timer = 1.2  # show happy face for 1.2 seconds after landing

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

func _draw_side_badge(badge_pos: Vector2, count: int) -> void:
	## Draw a small count badge at the given position (for side-by-side stacking)
	if count <= 1:
		return
	draw_circle(badge_pos, 6, GBC_DARK)
	draw_circle(badge_pos, 4.5, GBC_BRIGHT)
	var font = ThemeDB.fallback_font
	var count_str = str(count)
	var count_w = font.get_string_size(count_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, badge_pos + Vector2(-count_w * 0.5, 3.5), count_str,
		HORIZONTAL_ALIGNMENT_LEFT, 10, 10, GBC_DARK)

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

	# Phase 1: Show SAD face for 0.8 seconds before flying away
	is_capture_sad = true
	capture_sad_timer = 0.8

	# Brief hit flash
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.04)
	tween.tween_property(self, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.03)
	tween.tween_interval(0.06)
	tween.tween_property(self, "modulate", Color.WHITE, 0.02)
	# Sad shake: wiggle left-right while sad
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.05)
	tween.tween_property(self, "position:x", position.x - 3, 0.06)
	tween.tween_property(self, "position:x", position.x + 3, 0.06)
	tween.tween_property(self, "position:x", position.x - 2, 0.06)
	tween.tween_property(self, "position:x", position.x, 0.06)
	# Hold sad face
	tween.tween_interval(0.25)

func _play_capture_flyaway() -> void:
	## Phase 2: Fly away after sad expression
	var tween = create_tween()
	var fly_dir = Vector2(randf_range(-80, 80), -100)
	tween.tween_property(self, "position", position + fly_dir, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "rotation", randf_range(-5, 5), 0.35)
	tween.parallel().tween_property(self, "scale", Vector2(0.2, 0.2), 0.35)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
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
		anim_state = AnimState.IDLE
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
		anim_state = AnimState.IDLE
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

func set_stack(count: int, zodiac_info: Array = []) -> void:
	stack_count = count
	stacked_zodiac_info = zodiac_info
	if count > 1:
		animate_stack()
	queue_redraw()
