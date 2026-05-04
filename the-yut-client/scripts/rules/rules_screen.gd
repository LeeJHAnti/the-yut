extends Control

## Rules screen — visual pixel-art tutorial with minimal text
## Uses _draw() for pixel diagrams. Swipe/tap arrows to page through.

signal closed

const BG = Color("FFF8E8")
const PANEL_BG = Color("F8F0D8")
const BORDER = Color("503820")
const BORDER_LIGHT = Color("907040")
const TEXT_DARK = Color("503820")
const TEXT_MID = Color("907040")
const TEXT_LIGHT = Color("B89868")
const NODE_COLOR = Color("E8D8B0")
const NODE_LINE = Color("8C6C44")
const HIGHLIGHT = Color("58B068")
const RED = Color("D05848")
const BLUE = Color("5880C8")
const RUBY = Color("D05848")
const SAPPHIRE = Color("5880C8")

var current_page: int = 0
var total_pages: int = 6
var font: Font
var anim_time: float = 0.0

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_process(true)

func _process(delta: float) -> void:
	anim_time += delta
	queue_redraw()

func _draw() -> void:
	# Full screen background
	draw_rect(Rect2(0, 0, 520, 960), BG)

	# Main panel
	var pr = Rect2(10, 10, 500, 940)
	draw_rect(pr, PANEL_BG)
	draw_rect(pr, BORDER, false, 3.0)
	# Inner border highlight
	draw_rect(Rect2(14, 14, 492, 932), BORDER_LIGHT, false, 1.0)

	# Title bar
	draw_rect(Rect2(14, 14, 492, 36), Color(BORDER, 0.1))
	_draw_text_centered(">> HOW TO PLAY <<", 260, 38, 18, TEXT_DARK)

	# Page indicator dots
	for i in range(total_pages):
		var dx = 260 + (i - total_pages * 0.5 + 0.5) * 18
		if i == current_page:
			draw_circle(Vector2(dx, 930), 5, BORDER)
		else:
			draw_circle(Vector2(dx, 930), 4, BORDER_LIGHT)
			draw_circle(Vector2(dx, 930), 3, NODE_COLOR)

	# Navigation arrows
	var arrow_alpha = 0.5 + sin(anim_time * 3.0) * 0.2
	if current_page > 0:
		_draw_arrow_left(30, 480, Color(BORDER, arrow_alpha))
	if current_page < total_pages - 1:
		_draw_arrow_right(490, 480, Color(BORDER, arrow_alpha))

	# Draw current page content
	match current_page:
		0: _draw_page_overview()
		1: _draw_page_throw()
		2: _draw_page_board()
		3: _draw_page_stack_capture()
		4: _draw_page_shortcuts()
		5: _draw_page_finish()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var x = event.position.x
		var y = event.position.y
		# Close button area (top-right corner)
		if x > 460 and y < 60:
			_close()
			return
		# Left/right navigation
		if x < 130:
			if current_page > 0:
				current_page -= 1
				AudioManager.play_sfx("ui_click")
		elif x > 390:
			if current_page < total_pages - 1:
				current_page += 1
				AudioManager.play_sfx("ui_click")
		else:
			# Tap center to advance
			if current_page < total_pages - 1:
				current_page += 1
				AudioManager.play_sfx("ui_click")
			else:
				_close()

func _close() -> void:
	AudioManager.play_sfx("ui_back")
	closed.emit()
	queue_free()

# ─── PAGE 0: Overview ───
func _draw_page_overview() -> void:
	# Close X
	_draw_text_centered("X", 488, 38, 16, TEXT_MID)

	_draw_text_centered("YUTNORI", 260, 100, 28, TEXT_DARK)
	_draw_text_centered("Korean Board Game", 260, 126, 14, TEXT_MID)

	# Draw a mini board preview (centered)
	var cx = 260.0
	var cy = 330.0
	var s = 140.0  # half-size
	# Outer rectangle
	var corners = [
		Vector2(cx + s, cy + s),   # BR = START (0)
		Vector2(cx + s, cy - s),   # TR (5)
		Vector2(cx - s, cy - s),   # TL (10)
		Vector2(cx - s, cy + s),   # BL (15)
	]
	# Draw edges
	for i in range(4):
		draw_line(corners[i], corners[(i + 1) % 4], NODE_LINE, 2.0)
	# Draw diagonals
	draw_line(corners[1], corners[3], Color(NODE_LINE, 0.5), 1.5)  # TR→BL
	draw_line(corners[2], corners[0], Color(NODE_LINE, 0.5), 1.5)  # TL→BR

	# Draw nodes on edges (5 per side)
	for i in range(4):
		var from = corners[i]
		var to = corners[(i + 1) % 4]
		for j in range(6):
			var t = float(j) / 5.0
			var pos = from.lerp(to, t)
			var r = 7.0 if j == 0 else 5.0
			draw_circle(pos, r + 1, NODE_LINE)
			draw_circle(pos, r, NODE_COLOR)

	# Label corners
	_draw_text_centered("START", cx + s, cy + s + 22, 11, HIGHLIGHT)
	_draw_text_centered("5", cx + s, cy - s - 12, 10, TEXT_LIGHT)
	_draw_text_centered("10", cx - s, cy - s - 12, 10, TEXT_LIGHT)
	_draw_text_centered("15", cx - s, cy + s + 22, 10, TEXT_LIGHT)

	# Movement arrow (counter-clockwise)
	var arrow_y = cy + s + 45
	_draw_text_centered("Move counter-clockwise", 260, arrow_y, 12, TEXT_MID)
	draw_line(Vector2(170, arrow_y + 8), Vector2(350, arrow_y + 8), TEXT_LIGHT, 1.5)
	# arrowhead
	draw_line(Vector2(170, arrow_y + 8), Vector2(180, arrow_y + 3), TEXT_LIGHT, 1.5)
	draw_line(Vector2(170, arrow_y + 8), Vector2(180, arrow_y + 13), TEXT_LIGHT, 1.5)

	# Goal text
	_draw_text_centered("Race 4 pieces around the board!", 260, 560, 14, TEXT_DARK)
	_draw_text_centered("First to finish all pieces wins.", 260, 582, 13, TEXT_MID)

	# Animated piece at START
	var bob = sin(anim_time * 2.5) * 4.0
	draw_circle(corners[0] + Vector2(0, bob - 20), 8, RUBY)
	draw_circle(corners[0] + Vector2(0, bob - 20), 6, Color(RUBY, 0.7))

	# 4 home pieces illustration
	_draw_text_centered("Your 4 Pieces", 260, 640, 13, TEXT_DARK)
	for i in range(4):
		var px = 190 + i * 46
		draw_circle(Vector2(px, 672), 10, RUBY)
		draw_circle(Vector2(px, 672), 8, Color(RUBY, 0.6))
		_draw_text_centered(str(i + 1), px, 677, 10, Color.WHITE)

	_draw_text_centered("tap to continue >>", 260, 900, 12, Color(TEXT_LIGHT, 0.5 + sin(anim_time * 2.0) * 0.3))

# ─── PAGE 1: Throw results ───
func _draw_page_throw() -> void:
	_draw_text_centered("X", 488, 38, 16, TEXT_MID)
	_draw_text_centered("THROWING", 260, 80, 22, TEXT_DARK)
	_draw_text_centered("Flick or tap to throw yut sticks", 260, 104, 12, TEXT_MID)

	# Draw yut stick results with visual stick diagrams
	var results = [
		{"name": "Do", "steps": 1, "flat": 1, "extra": false, "color": TEXT_DARK},
		{"name": "Gae", "steps": 2, "flat": 2, "extra": false, "color": TEXT_DARK},
		{"name": "Geol", "steps": 3, "flat": 3, "extra": false, "color": TEXT_DARK},
		{"name": "Yut", "steps": 4, "flat": 4, "extra": true, "color": HIGHLIGHT},
		{"name": "Mo", "steps": 5, "flat": 0, "extra": true, "color": HIGHLIGHT},
		{"name": "BackDo", "steps": -1, "flat": -1, "extra": false, "color": RED},
	]

	var sy = 150
	for i in range(results.size()):
		var r = results[i]
		var y = sy + i * 105
		var row_bg = Color(BORDER, 0.04) if i % 2 == 0 else Color.TRANSPARENT
		draw_rect(Rect2(30, y - 12, 460, 95), row_bg)

		# Result name
		_draw_text(r["name"], 40, y + 8, 18, r["color"])

		# Steps badge
		var step_text = "+" + str(r["steps"]) if int(r["steps"]) > 0 else str(r["steps"])
		var badge_x = 160
		var badge_color = r["color"]
		draw_rect(Rect2(badge_x - 16, y - 6, 36, 24), badge_color)
		_draw_text_centered(step_text, badge_x + 2, y + 12, 14, Color.WHITE)

		# Draw 4 yut sticks (flat = filled, round = outline)
		var stick_x = 220
		var flat_count = int(r["flat"])
		if r["name"] == "BackDo":
			# Special: 1 marked stick flat + 3 round
			for j in range(4):
				var sx2 = stick_x + j * 30
				if j == 0:
					# marked stick (flat) — with X mark
					draw_rect(Rect2(sx2, y - 4, 22, 18), BORDER)
					draw_rect(Rect2(sx2 + 2, y - 2, 18, 14), Color("D4B888"))
					# X mark
					draw_line(Vector2(sx2 + 5, y + 1), Vector2(sx2 + 17, y + 9), RED, 2.0)
					draw_line(Vector2(sx2 + 17, y + 1), Vector2(sx2 + 5, y + 9), RED, 2.0)
				else:
					# round (back side)
					draw_rect(Rect2(sx2, y - 4, 22, 18), BORDER)
					draw_rect(Rect2(sx2 + 2, y - 2, 18, 14), BORDER_LIGHT)
		else:
			for j in range(4):
				var sx2 = stick_x + j * 30
				if j < flat_count:
					# flat side (light)
					draw_rect(Rect2(sx2, y - 4, 22, 18), BORDER)
					draw_rect(Rect2(sx2 + 2, y - 2, 18, 14), Color("D4B888"))
				else:
					# round side (dark)
					draw_rect(Rect2(sx2, y - 4, 22, 18), BORDER)
					draw_rect(Rect2(sx2 + 2, y - 2, 18, 14), BORDER_LIGHT)

		# Extra turn badge
		if r["extra"]:
			draw_rect(Rect2(370, y - 6, 110, 24), Color(HIGHLIGHT, 0.2))
			draw_rect(Rect2(370, y - 6, 110, 24), HIGHLIGHT, false, 1.5)
			_draw_text_centered("EXTRA TURN!", 425, y + 12, 11, HIGHLIGHT)

		# Description line
		var desc = ""
		match r["name"]:
			"Do": desc = "1 flat, 3 round"
			"Gae": desc = "2 flat, 2 round"
			"Geol": desc = "3 flat, 1 round"
			"Yut": desc = "All 4 flat"
			"Mo": desc = "All 4 round"
			"BackDo": desc = "Marked stick flat only"
		_draw_text(desc, 40, y + 38, 11, TEXT_LIGHT)

		# Draw step dots
		if int(r["steps"]) > 0:
			for d in range(int(r["steps"])):
				var dot_x = 220 + d * 16
				draw_circle(Vector2(dot_x, y + 42), 4, r["color"])
		elif int(r["steps"]) < 0:
			draw_circle(Vector2(220, y + 42), 4, RED)
			_draw_text("<", 228, y + 46, 10, RED)

	_draw_text_centered("<< prev    next >>", 260, 900, 12, Color(TEXT_LIGHT, 0.5))

# ─── PAGE 2: Board layout ───
func _draw_page_board() -> void:
	_draw_text_centered("X", 488, 38, 16, TEXT_MID)
	_draw_text_centered("THE BOARD", 260, 80, 22, TEXT_DARK)

	# Draw full board
	var cx = 260.0
	var cy = 380.0
	var s = 170.0

	var corners = [
		Vector2(cx + s, cy + s),   # BR=START(0)
		Vector2(cx + s, cy - s),   # TR(5)
		Vector2(cx - s, cy - s),   # TL(10)
		Vector2(cx - s, cy + s),   # BL(15)
	]

	# Edges
	for i in range(4):
		draw_line(corners[i], corners[(i + 1) % 4], NODE_LINE, 2.5)

	# Diagonals
	draw_dashed_line(corners[1], corners[3], Color(HIGHLIGHT, 0.6), 2.0, 6.0)
	draw_dashed_line(corners[2], corners[0], Color(BLUE, 0.6), 2.0, 6.0)

	# Center node
	draw_circle(Vector2(cx, cy), 10, NODE_LINE)
	draw_circle(Vector2(cx, cy), 8, Color("FFE8C0"))

	# Edge nodes
	for i in range(4):
		var from = corners[i]
		var to = corners[(i + 1) % 4]
		for j in range(6):
			var t = float(j) / 5.0
			var pos = from.lerp(to, t)
			var r = 9.0 if j == 0 else 6.0
			draw_circle(pos, r + 1, NODE_LINE)
			draw_circle(pos, r, NODE_COLOR)

	# Corner labels
	_draw_text_centered("0", cx + s, cy + s + 20, 12, HIGHLIGHT)
	_draw_text_centered("START", cx + s, cy + s + 34, 10, HIGHLIGHT)
	_draw_text_centered("5", cx + s, cy - s - 14, 12, TEXT_MID)
	_draw_text_centered("10", cx - s, cy - s - 14, 12, TEXT_MID)
	_draw_text_centered("15", cx - s, cy + s + 20, 12, TEXT_MID)

	# Movement direction arrows along bottom edge
	for i in range(4):
		var from = corners[0].lerp(corners[1], float(i) / 5.0 + 0.1)
		var to = corners[0].lerp(corners[1], float(i) / 5.0 + 0.3)
		var mid = (from + to) * 0.5
		_draw_small_arrow(from, to, Color(TEXT_LIGHT, 0.6))

	# Label the directions
	_draw_text_centered("UP", cx + s + 24, cy, 10, TEXT_LIGHT)
	_draw_text_centered("LEFT", cx, cy - s - 28, 10, TEXT_LIGHT)

	# Shortcut labels
	_draw_text("Shortcut A", 310, cy - 60, 11, HIGHLIGHT)
	_draw_text("Shortcut B", 290, cy + 50, 11, BLUE)

	# Animated piece moving along the path
	var t = fmod(anim_time * 0.3, 1.0)
	var anim_pos: Vector2
	if t < 0.25:
		anim_pos = corners[0].lerp(corners[1], t * 4)
	elif t < 0.5:
		anim_pos = corners[1].lerp(corners[2], (t - 0.25) * 4)
	elif t < 0.75:
		anim_pos = corners[2].lerp(corners[3], (t - 0.5) * 4)
	else:
		anim_pos = corners[3].lerp(corners[0], (t - 0.75) * 4)
	draw_circle(anim_pos, 8, RUBY)
	draw_circle(anim_pos, 6, Color(RUBY, 0.6))

	# Legend at bottom
	var ly = 620
	_draw_text_centered("20 outer nodes + 2 diagonal shortcuts", 260, ly, 12, TEXT_MID)
	ly += 24
	draw_line(Vector2(160, ly), Vector2(200, ly), NODE_LINE, 2.5)
	_draw_text("Outer path", 210, ly + 4, 11, TEXT_MID)
	ly += 22
	draw_dashed_line(Vector2(160, ly), Vector2(200, ly), HIGHLIGHT, 2.0, 6.0)
	_draw_text("Shortcut A (5 to 15)", 210, ly + 4, 11, HIGHLIGHT)
	ly += 22
	draw_dashed_line(Vector2(160, ly), Vector2(200, ly), BLUE, 2.0, 6.0)
	_draw_text("Shortcut B (10 to 0)", 210, ly + 4, 11, BLUE)

	_draw_text_centered("<< prev    next >>", 260, 900, 12, Color(TEXT_LIGHT, 0.5))

# ─── PAGE 3: Stack & Capture ───
func _draw_page_stack_capture() -> void:
	_draw_text_centered("X", 488, 38, 16, TEXT_MID)
	_draw_text_centered("STACK & CAPTURE", 260, 80, 22, TEXT_DARK)

	# --- STACKING ---
	var sy = 130
	_draw_text_centered("STACKING", 260, sy, 16, HIGHLIGHT)
	_draw_text_centered("Land on your own piece", 260, sy + 20, 12, TEXT_MID)

	# Before: two separate pieces
	var bx = 130
	var by = sy + 70
	_draw_text_centered("Before", bx, by - 20, 11, TEXT_LIGHT)
	draw_circle(Vector2(bx - 20, by), 12, NODE_LINE)
	draw_circle(Vector2(bx - 20, by), 10, NODE_COLOR)
	draw_circle(Vector2(bx - 20, by), 8, RUBY)  # piece on node
	draw_circle(Vector2(bx + 30, by), 12, NODE_LINE)
	draw_circle(Vector2(bx + 30, by), 10, NODE_COLOR)
	draw_circle(Vector2(bx + 30, by), 8, RUBY)  # another piece
	# Arrow
	_draw_small_arrow(Vector2(bx + 60, by), Vector2(bx + 100, by), TEXT_MID)

	# After: stacked pieces
	var ax = 370
	_draw_text_centered("After", ax, by - 20, 11, TEXT_LIGHT)
	draw_circle(Vector2(ax, by), 14, NODE_LINE)
	draw_circle(Vector2(ax, by), 12, NODE_COLOR)
	draw_circle(Vector2(ax, by), 9, RUBY)
	# Stack badge
	draw_circle(Vector2(ax + 12, by - 10), 8, Color.WHITE)
	draw_circle(Vector2(ax + 12, by - 10), 7, HIGHLIGHT)
	_draw_text_centered("2", ax + 12, by - 6, 10, Color.WHITE)

	_draw_text_centered("They move together as one!", 260, by + 40, 12, TEXT_MID)

	# --- CAPTURING ---
	var cy2 = 330
	_draw_text_centered("CAPTURING", 260, cy2, 16, RED)
	_draw_text_centered("Land on opponent's piece", 260, cy2 + 20, 12, TEXT_MID)

	# Before: red approaching blue
	var cbx = 130
	var cby = cy2 + 70
	_draw_text_centered("Before", cbx, cby - 20, 11, TEXT_LIGHT)
	draw_circle(Vector2(cbx - 20, cby), 12, NODE_LINE)
	draw_circle(Vector2(cbx - 20, cby), 10, NODE_COLOR)
	draw_circle(Vector2(cbx - 20, cby), 8, RUBY)
	draw_circle(Vector2(cbx + 30, cby), 12, NODE_LINE)
	draw_circle(Vector2(cbx + 30, cby), 10, NODE_COLOR)
	draw_circle(Vector2(cbx + 30, cby), 8, SAPPHIRE)
	_draw_small_arrow(Vector2(cbx + 60, cby), Vector2(cbx + 100, cby), TEXT_MID)

	# After: red on node, blue sent home with X
	var cax = 370
	_draw_text_centered("After", cax, cby - 20, 11, TEXT_LIGHT)
	draw_circle(Vector2(cax, cby), 12, NODE_LINE)
	draw_circle(Vector2(cax, cby), 10, NODE_COLOR)
	draw_circle(Vector2(cax, cby), 8, RUBY)
	# Blue piece with X (sent home)
	draw_circle(Vector2(cax + 40, cby), 8, Color(SAPPHIRE, 0.4))
	draw_line(Vector2(cax + 34, cby - 6), Vector2(cax + 46, cby + 6), RED, 2.0)
	draw_line(Vector2(cax + 46, cby - 6), Vector2(cax + 34, cby + 6), RED, 2.0)
	_draw_text("HOME", cax + 52, cby + 5, 9, RED)

	_draw_text_centered("Opponent goes home!", 260, cby + 30, 12, TEXT_MID)

	# Bonus throw badge
	var bonus_y = cby + 60
	draw_rect(Rect2(160, bonus_y, 200, 28), Color(HIGHLIGHT, 0.15))
	draw_rect(Rect2(160, bonus_y, 200, 28), HIGHLIGHT, false, 2.0)
	_draw_text_centered("+ BONUS THROW!", 260, bonus_y + 20, 14, HIGHLIGHT)

	# Warning about stacked captures
	var wy = bonus_y + 60
	_draw_text_centered("Capturing a stack sends", 260, wy, 12, TEXT_DARK)
	_draw_text_centered("ALL stacked pieces home!", 260, wy + 18, 13, RED)

	# Visual: stacked group captured
	var gx = 180
	var gy = wy + 55
	draw_circle(Vector2(gx, gy), 10, SAPPHIRE)
	draw_circle(Vector2(gx + 10, gy - 5), 8, Color.WHITE)
	draw_circle(Vector2(gx + 10, gy - 5), 7, SAPPHIRE)
	_draw_text_centered("3", gx + 10, gy - 1, 9, Color.WHITE)
	_draw_small_arrow(Vector2(gx + 30, gy), Vector2(gx + 60, gy), RED)
	# All 3 with X
	for i in range(3):
		var ex = gx + 80 + i * 24
		draw_circle(Vector2(ex, gy), 7, Color(SAPPHIRE, 0.3))
		draw_line(Vector2(ex - 4, gy - 4), Vector2(ex + 4, gy + 4), RED, 1.5)
		draw_line(Vector2(ex + 4, gy - 4), Vector2(ex - 4, gy + 4), RED, 1.5)

	_draw_text_centered("<< prev    next >>", 260, 900, 12, Color(TEXT_LIGHT, 0.5))

# ─── PAGE 4: Shortcuts ───
func _draw_page_shortcuts() -> void:
	_draw_text_centered("X", 488, 38, 16, TEXT_MID)
	_draw_text_centered("SHORTCUTS", 260, 80, 22, TEXT_DARK)
	_draw_text_centered("Take diagonal paths to save steps!", 260, 104, 12, TEXT_MID)

	# Draw board with shortcuts highlighted
	var cx = 260.0
	var cy = 340.0
	var s = 150.0

	var corners = [
		Vector2(cx + s, cy + s),
		Vector2(cx + s, cy - s),
		Vector2(cx - s, cy - s),
		Vector2(cx - s, cy + s),
	]

	# Draw outer ring (dimmed)
	for i in range(4):
		draw_line(corners[i], corners[(i + 1) % 4], Color(NODE_LINE, 0.3), 2.0)

	# Outer path distance label
	_draw_text_centered("Outer: 20 steps", 260, cy + s + 40, 12, TEXT_LIGHT)

	# Shortcut A: TR(5) → center → BL(15) — 6 steps vs 10 outer
	draw_line(corners[1], corners[3], HIGHLIGHT, 3.0)
	# nodes along shortcut A
	for j in range(6):
		var t = float(j) / 5.0
		var pos = corners[1].lerp(corners[3], t)
		draw_circle(pos, 7, NODE_LINE)
		draw_circle(pos, 5, Color("C8E8C0"))

	# Shortcut B: TL(10) → center → START(0) — 6 steps vs 10 outer
	draw_line(corners[2], corners[0], BLUE, 3.0)
	for j in range(6):
		var t = float(j) / 5.0
		var pos = corners[2].lerp(corners[0], t)
		draw_circle(pos, 7, NODE_LINE)
		draw_circle(pos, 5, Color("C0D8E8"))

	# Corner labels
	_draw_text_centered("START(0)", cx + s + 4, cy + s + 20, 10, HIGHLIGHT)
	_draw_text_centered("5", cx + s + 16, cy - s - 8, 11, HIGHLIGHT)
	_draw_text_centered("10", cx - s - 18, cy - s - 8, 11, BLUE)
	_draw_text_centered("15", cx - s - 4, cy + s + 20, 10, HIGHLIGHT)

	# Center label
	_draw_text_centered("Center", cx, cy - 16, 10, TEXT_MID)

	# Comparison boxes
	var boxy = 560

	# Shortcut A comparison
	draw_rect(Rect2(30, boxy, 220, 80), Color(HIGHLIGHT, 0.1))
	draw_rect(Rect2(30, boxy, 220, 80), HIGHLIGHT, false, 2.0)
	_draw_text_centered("Shortcut A", 140, boxy + 18, 13, HIGHLIGHT)
	_draw_text_centered("5 -> 15", 140, boxy + 38, 12, TEXT_DARK)
	_draw_text_centered("6 steps (saves 4!)", 140, boxy + 56, 11, HIGHLIGHT)

	# Shortcut B comparison
	draw_rect(Rect2(270, boxy, 220, 80), Color(BLUE, 0.1))
	draw_rect(Rect2(270, boxy, 220, 80), BLUE, false, 2.0)
	_draw_text_centered("Shortcut B", 380, boxy + 18, 13, BLUE)
	_draw_text_centered("10 -> 0 (finish!)", 380, boxy + 38, 12, TEXT_DARK)
	_draw_text_centered("6 steps (saves 4!)", 380, boxy + 56, 11, BLUE)

	# Center junction note
	var jy = boxy + 110
	_draw_text_centered("At the center, you can switch", 260, jy, 12, TEXT_DARK)
	_draw_text_centered("from Shortcut A to Shortcut B!", 260, jy + 18, 12, TEXT_DARK)

	# Animated piece on shortcut
	var at = fmod(anim_time * 0.5, 1.0)
	var ap = corners[1].lerp(corners[3], at)
	draw_circle(ap, 9, RUBY)
	draw_circle(ap, 7, Color(RUBY, 0.6))

	_draw_text_centered("<< prev    next >>", 260, 900, 12, Color(TEXT_LIGHT, 0.5))

# ─── PAGE 5: Finishing ───
func _draw_page_finish() -> void:
	_draw_text_centered("X", 488, 38, 16, TEXT_MID)
	_draw_text_centered("FINISHING", 260, 80, 22, TEXT_DARK)

	# Finish condition diagram
	var cy2 = 170
	_draw_text_centered("Complete the circuit", 260, cy2, 14, TEXT_MID)
	_draw_text_centered("and reach START to finish!", 260, cy2 + 18, 14, TEXT_MID)

	# Draw a simplified path from node 18→19→0(FINISH)
	var path_y = cy2 + 70
	for i in range(4):
		var nx = 120 + i * 90
		var is_finish = (i == 3)
		var r = 14.0 if is_finish else 10.0
		if is_finish:
			draw_circle(Vector2(nx, path_y), r + 2, HIGHLIGHT)
		draw_circle(Vector2(nx, path_y), r, NODE_LINE)
		draw_circle(Vector2(nx, path_y), r - 2, NODE_COLOR if not is_finish else Color("C8E8C0"))
		var label = str(17 + i) if i < 3 else "0"
		_draw_text_centered(label, nx, path_y + 5, 11, TEXT_DARK if not is_finish else HIGHLIGHT)
		if i < 3:
			_draw_small_arrow(Vector2(nx + 14, path_y), Vector2(nx + 76, path_y), TEXT_LIGHT)

	_draw_text_centered("FINISH!", 120 + 3 * 90, path_y + 24, 12, HIGHLIGHT)

	# Animated piece moving to finish
	var ft = fmod(anim_time * 0.6, 1.0)
	var fpi = int(ft * 3)
	var fpt = fmod(ft * 3, 1.0)
	var fpx1 = 120 + fpi * 90
	var fpx2 = 120 + min(fpi + 1, 3) * 90
	var fpx = lerp(float(fpx1), float(fpx2), fpt)
	if ft < 0.95:
		draw_circle(Vector2(fpx, path_y - 16), 8, RUBY)

	# Pass-through rule
	var pry = path_y + 70
	_draw_text_centered("If your move passes through", 260, pry, 13, TEXT_DARK)
	_draw_text_centered("START, you still finish!", 260, pry + 18, 13, HIGHLIGHT)

	# Win condition
	var wy = pry + 70
	draw_rect(Rect2(60, wy, 400, 60), Color(HIGHLIGHT, 0.1))
	draw_rect(Rect2(60, wy, 400, 60), HIGHLIGHT, false, 2.5)
	_draw_text_centered("WIN CONDITION", 260, wy + 20, 14, TEXT_DARK)
	_draw_text_centered("Finish all 4 pieces first!", 260, wy + 42, 13, HIGHLIGHT)

	# 4 pieces → all finished
	var fy = wy + 100
	for i in range(4):
		var px = 140 + i * 65
		draw_circle(Vector2(px, fy), 12, HIGHLIGHT)
		draw_circle(Vector2(px, fy), 10, Color(HIGHLIGHT, 0.5))
		# Checkmark
		draw_line(Vector2(px - 4, fy), Vector2(px - 1, fy + 4), Color.WHITE, 2.0)
		draw_line(Vector2(px - 1, fy + 4), Vector2(px + 5, fy - 4), Color.WHITE, 2.0)

	# Team mode note
	var ty = fy + 50
	draw_rect(Rect2(60, ty, 400, 50), Color(BORDER, 0.05))
	draw_rect(Rect2(60, ty, 400, 50), BORDER_LIGHT, false, 1.5)
	_draw_text_centered("4 Players = Team Mode (2v2)", 260, ty + 18, 13, TEXT_DARK)
	_draw_text_centered("Both teammates must finish!", 260, ty + 36, 12, TEXT_MID)

	# Tips section
	var tipy = ty + 80
	_draw_text_centered("TIPS", 260, tipy, 16, TEXT_DARK)
	tipy += 26
	# Tip icons
	draw_circle(Vector2(60, tipy), 6, HIGHLIGHT)
	_draw_text("Use shortcuts to save steps!", 76, tipy + 5, 12, TEXT_MID)
	tipy += 26
	draw_circle(Vector2(60, tipy), 6, Color("D4A030"))
	_draw_text("Stack pieces for protection", 76, tipy + 5, 12, TEXT_MID)
	tipy += 26
	draw_circle(Vector2(60, tipy), 6, RED)
	_draw_text("Capture opponents for bonus throws!", 76, tipy + 5, 12, TEXT_MID)

	_draw_text_centered("tap to close", 260, 900, 12, Color(TEXT_LIGHT, 0.5 + sin(anim_time * 2.0) * 0.3))

# ─── Drawing helpers ───

func _draw_text(text: String, x: float, y: float, size: int, color: Color) -> void:
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_text_centered(text: String, cx: float, y: float, size: int, color: Color) -> void:
	var tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(cx - tw * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_arrow_left(x: float, y: float, color: Color) -> void:
	draw_line(Vector2(x, y), Vector2(x + 12, y - 10), color, 2.5)
	draw_line(Vector2(x, y), Vector2(x + 12, y + 10), color, 2.5)

func _draw_arrow_right(x: float, y: float, color: Color) -> void:
	draw_line(Vector2(x, y), Vector2(x - 12, y - 10), color, 2.5)
	draw_line(Vector2(x, y), Vector2(x - 12, y + 10), color, 2.5)

func _draw_small_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	draw_line(from, to, color, 1.5)
	var dir = (to - from).normalized()
	var perp = Vector2(-dir.y, dir.x)
	draw_line(to, to - dir * 6 + perp * 4, color, 1.5)
	draw_line(to, to - dir * 6 - perp * 4, color, 1.5)
