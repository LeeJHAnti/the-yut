extends Control
## Action Stack HUD — shows pending yut results as badge chips at top center.
## Appears only when there are 2+ pending results (meaning extra turns stacked).
## Each result is shown as a small rounded pill with the result name and step count.
## GBA pixel-art style with warm wood palette.

const RESULT_COLORS: Dictionary = {
	"Do": Color("B89868"),     # warm mid
	"Gae": Color("B89868"),    # warm mid
	"Geol": Color("D4B888"),   # wooden coin
	"Yut": Color("D05848"),    # soft ruby (special!)
	"Mo": Color("D05848"),     # soft ruby (special!)
	"BackDo": Color("8C6C44"), # brown
}

const RESULT_LABELS: Dictionary = {
	"Do": "Do +1",
	"Gae": "Gae +2",
	"Geol": "Geol +3",
	"Yut": "Yut +4",
	"Mo": "Mo +5",
	"BackDo": "Back -1",
}

var _last_count: int = 0
var _pulse_time: float = 0.0
var _visible_anim: float = 0.0  # 0=hidden, 1=fully shown (slide-in)

func _process(delta: float) -> void:
	var count = GameState.pending_results.size()

	# Animate visibility
	var target = 1.0 if count >= 2 else 0.0
	_visible_anim = move_toward(_visible_anim, target, delta * 5.0)

	if _visible_anim <= 0.01:
		visible = false
		return
	else:
		visible = true

	# Pulse animation when new result added
	if count != _last_count:
		_pulse_time = 0.3
		_last_count = count

	if _pulse_time > 0:
		_pulse_time -= delta

	queue_redraw()

func _draw() -> void:
	var results = GameState.pending_results
	if results.size() < 2:
		return

	var badge_h: float = 20.0
	var badge_spacing: float = 4.0
	var badge_padding_x: float = 8.0
	var font_size: int = 11

	# Calculate total width to center everything (use actual font metrics)
	var font = ThemeDB.fallback_font
	if font == null:
		return
	var badge_widths: Array = []
	for r in results:
		var label_text = RESULT_LABELS.get(r, r)
		var text_w = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var w = text_w + badge_padding_x * 2
		badge_widths.append(w)

	var total_width: float = 0.0
	for w in badge_widths:
		total_width += w
	total_width += badge_spacing * (results.size() - 1)

	# Header label width (use font metrics)
	var header_text = "x" + str(results.size())
	var header_w = font.get_string_size(header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0

	var full_width = header_w + 6.0 + total_width + 12.0

	# Clamp full_width to control bounds so badges don't overflow
	var max_width = size.x - 16.0
	if full_width > max_width:
		var scale_factor = max_width / full_width
		for i in range(badge_widths.size()):
			badge_widths[i] *= scale_factor
		total_width *= scale_factor
		header_w *= scale_factor
		full_width = max_width

	# Position: centered horizontally, slight y offset with slide animation
	var cx = size.x * 0.5
	var slide_y = lerpf(-badge_h - 4, 0.0, _visible_anim)
	var start_x = cx - full_width * 0.5
	var y_pos = 2.0 + slide_y

	# Background panel (subtle rounded rect behind all badges)
	var bg_rect = Rect2(start_x - 4, y_pos - 2, full_width + 8, badge_h + 4)
	var bg_color = Color("503820", 0.85 * _visible_anim)
	draw_rect(bg_rect, bg_color, true)
	# Border
	var border_color = Color("6B4C30", 0.9 * _visible_anim)
	draw_rect(bg_rect, border_color, false, 1.5)

	# Header: "x3" count indicator
	var header_color = Color("F8F0E0", _visible_anim)
	var header_x = start_x + 4.0
	_draw_text(header_text, Vector2(header_x, y_pos + badge_h * 0.5 + 4.5), header_color, 13)

	# Draw each badge
	var bx = start_x + header_w + 6.0
	for i in range(results.size()):
		var r = results[i]
		var bw = badge_widths[i]
		var badge_rect = Rect2(bx, y_pos + 1, bw, badge_h - 2)

		# Badge background color
		var base_col = RESULT_COLORS.get(r, Color("B89868"))
		var alpha = _visible_anim * 0.9
		# Pulse effect on newest badge (last item)
		if i == results.size() - 1 and _pulse_time > 0:
			var pulse = _pulse_time / 0.3
			base_col = base_col.lightened(pulse * 0.3)
		draw_rect(badge_rect, Color(base_col, alpha), true)

		# Badge border
		draw_rect(badge_rect, Color("F8F0E0", alpha * 0.6), false, 1.0)

		# Badge text
		var label_text = RESULT_LABELS.get(r, r)
		var text_color = Color("F8F0E0", _visible_anim)
		# For special results (Yut/Mo) use brighter text
		if r == "Yut" or r == "Mo":
			text_color = Color("FFFFFF", _visible_anim)
		_draw_text(label_text, Vector2(bx + bw * 0.5, y_pos + badge_h * 0.5 + 4.0), text_color, font_size)

		bx += bw + badge_spacing

func _draw_text(text: String, pos: Vector2, color: Color, fsize: int) -> void:
	# Simple draw_string using default font
	var font = ThemeDB.fallback_font
	if font == null:
		return
	var text_width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, Vector2(pos.x - text_width * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
