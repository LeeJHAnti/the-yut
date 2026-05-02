extends Node2D

# ══════════════════════════════════════════════════════════════════
# Traditional Yut Board (윷판) — 520×960 PORTRAIT viewport
# ══════════════════════════════════════════════════════════════════
#
# Layout (top to bottom):
#   Turn marquee:   y=0~34   (h=34, 한줄 전광판)
#   Board area:     y=36~566 (h=530, 428×428 node area centered)
#   Player trays:   y=570~720 (h=150, dynamic split by player count)
#   Yut throw area: y=720~922 (h=202)
#
# Board: 428px square, node spacing = ~86px, 5 intervals per side
# Node margin: 46px (x: 46~474)
#
# Movement: COUNTER-CLOCKWISE  (0 = start/finish at bottom-right)
#
#   TL(10)---9----8----7----6---TR(5)
#     | ╲                     ╱ |
#    11   25               20   4
#     |     26           21     |
#    12       ╲   22   ╱        3
#     |        (center)         |
#    13       ╱   22   ╲        2
#     |     27           23     |
#    14   28               24   1
#     | ╱                     ╲ |
#   BL(15)--16---17---18---19--START(0)
# ══════════════════════════════════════════════════════════════════

# ═══ Preload sprite textures ═══
const TEX_NODE_BIG = preload("res://assets/sprites/node_big.png")
const TEX_NODE_SMALL = preload("res://assets/sprites/node_small.png")
const TEX_BOARD_BG = preload("res://assets/sprites/board_bg_tile.png")
const TEX_TAEGEUK = preload("res://assets/sprites/taegeuk.png")
const TEX_FRAME_BOARD = preload("res://assets/sprites/frame_board.png")
const TEX_FRAME_MARQUEE = preload("res://assets/sprites/frame_marquee.png")
const TEX_FRAME_TRAY = preload("res://assets/sprites/frame_tray.png")
const TEX_FRAME_THROW = preload("res://assets/sprites/frame_throw.png")

# ═══ Cute animal-theme decoration sprites ═══
const TEX_DECO_PAW = preload("res://assets/sprites/deco_paw.png")
const TEX_DECO_FLOWER = preload("res://assets/sprites/deco_flower.png")
const TEX_DECO_GRASS = preload("res://assets/sprites/deco_grass.png")
const TEX_DECO_STAR = preload("res://assets/sprites/deco_star.png")

const NODE_POSITIONS: Dictionary = {
	# ── Outer ring ── 428×428 board, ~86px spacing ──
	# Node area: x=46~474, y=87~515 (centered in board section y=36~566)
	# Right side (going UP): x=474
	0:  Vector2(474, 515),   # BR — START / FINISH
	1:  Vector2(474, 429),
	2:  Vector2(474, 344),
	3:  Vector2(474, 258),
	4:  Vector2(474, 173),
	5:  Vector2(474, 87),    # TR — junction → Diagonal A
	# Top side (going LEFT): y=87
	6:  Vector2(388, 87),
	7:  Vector2(303, 87),
	8:  Vector2(217, 87),
	9:  Vector2(132, 87),
	10: Vector2(46, 87),     # TL — junction → Diagonal B
	# Left side (going DOWN): x=46
	11: Vector2(46, 173),
	12: Vector2(46, 258),
	13: Vector2(46, 344),
	14: Vector2(46, 429),
	15: Vector2(46, 515),    # BL
	# Bottom side (going RIGHT): y=515
	16: Vector2(132, 515),
	17: Vector2(217, 515),
	18: Vector2(303, 515),
	19: Vector2(388, 515),
	# ── Diagonal A: TR(5) → center → BL(15)  step (-71, +71) ──
	20: Vector2(403, 158),
	21: Vector2(332, 229),
	22: Vector2(260, 301),   # ★ CENTER
	23: Vector2(189, 372),
	24: Vector2(118, 443),
	# ── Diagonal B: TL(10) → center → BR(0)  step (+71, +71) ──
	25: Vector2(117, 158),
	26: Vector2(188, 229),
	# 22 is shared center
	27: Vector2(331, 372),
	28: Vector2(402, 443),
}

const CONNECTIONS: Array = [
	# Outer ring
	[0,1],[1,2],[2,3],[3,4],[4,5],
	[5,6],[6,7],[7,8],[8,9],[9,10],
	[10,11],[11,12],[12,13],[13,14],[14,15],
	[15,16],[16,17],[17,18],[18,19],[19,0],
	# Diagonal A: TR(5) → BL(15)
	[5,20],[20,21],[21,22],[22,23],[23,24],[24,15],
	# Diagonal B: TL(10) → BR(0)
	[10,25],[25,26],[26,22],[22,27],[27,28],[28,0],
]

# Big nodes: 4 corners + center
const BIG_NODES: Array = [0, 5, 10, 15, 22]

# Player tray area bounds (dynamic layout)
const TRAY_Y_START := 570.0
const TRAY_Y_END   := 720.0
const TRAY_HEIGHT  := 150.0  # TRAY_Y_END - TRAY_Y_START

var player_count: int = 2  # set dynamically

func get_dynamic_home_position(player_index: int, piece_index: int) -> Vector2:
	var count = maxi(player_count, 2)
	var row_h = TRAY_HEIGHT / count
	var row_y = TRAY_Y_START + player_index * row_h + row_h * 0.5
	# 4 piece slots spread across x=180~400
	var piece_x = 185 + piece_index * 55
	return Vector2(piece_x, row_y)

func get_tray_row_rect(player_index: int) -> Rect2:
	var count = maxi(player_count, 2)
	var row_h = TRAY_HEIGHT / count
	var row_y = TRAY_Y_START + player_index * row_h
	return Rect2(12, row_y, 516, row_h)

# ─── Client-side board graph (mirrors server board.rs) ───
var GRAPH: Dictionary = {}
var REVERSE_GRAPH: Dictionary = {}  # for backward movement (BackDo)

func _ready() -> void:
	_build_graph()

func _build_graph() -> void:
	GRAPH.clear()
	REVERSE_GRAPH.clear()
	for n in range(19):
		_add_edge(n, "Outer", n + 1, "Outer")
	_add_edge(19, "Outer", 0, "Outer")
	_add_edge(5, "Outer", 20, "ShortcutA")
	_add_edge(10, "Outer", 25, "ShortcutB")
	_add_edge(20, "ShortcutA", 21, "ShortcutA")
	_add_edge(21, "ShortcutA", 22, "ShortcutA")
	_add_edge(22, "ShortcutA", 23, "ShortcutA")
	_add_edge(23, "ShortcutA", 24, "ShortcutA")
	_add_edge(24, "ShortcutA", 15, "Outer")
	_add_edge(25, "ShortcutB", 26, "ShortcutB")
	_add_edge(26, "ShortcutB", 22, "ShortcutB")
	_add_edge(22, "ShortcutB", 27, "ShortcutB")
	_add_edge(27, "ShortcutB", 28, "ShortcutB")
	_add_edge(28, "ShortcutB", 0, "Outer")
	_add_edge(22, "ShortcutA", 27, "ShortcutB")

func _add_edge(from_node: int, from_path: String, to_node: int, to_path: String) -> void:
	var key = str(from_node) + ":" + from_path
	var val = str(to_node) + ":" + to_path
	if not GRAPH.has(key):
		GRAPH[key] = []
	GRAPH[key].append(val)
	# Build reverse graph
	if not REVERSE_GRAPH.has(val):
		REVERSE_GRAPH[val] = []
	REVERSE_GRAPH[val].append(key)

## Get the previous node for backward movement (BackDo).
## Returns the node_id of the previous position, or -1 if can't go back.
func get_prev_node(node_id: int, path: String) -> int:
	var key = str(node_id) + ":" + path
	if REVERSE_GRAPH.has(key):
		var prev_list = REVERSE_GRAPH[key]
		if prev_list.size() > 0:
			# Prefer same-path predecessor
			for prev_key in prev_list:
				var parts = prev_key.split(":")
				if parts[1] == path:
					return int(parts[0])
			# Fallback to first predecessor
			return int(prev_list[0].split(":")[0])
	return -1

func calc_destinations(node_id: int, path: String, distance: int) -> Array:
	if distance <= 0:
		return [node_id]
	var current: Array = [str(node_id) + ":" + path]
	for step in range(distance):
		var next_set: Dictionary = {}
		for pos_key in current:
			if GRAPH.has(pos_key):
				var neighbors = GRAPH[pos_key]
				if step > 0 and _is_junction_key(pos_key) and neighbors.size() > 1:
					var cur_path = pos_key.split(":")[1] if ":" in pos_key else "Outer"
					for neighbor in neighbors:
						var nb_path = neighbor.split(":")[1] if ":" in neighbor else "Outer"
						if nb_path == cur_path:
							next_set[neighbor] = true
				else:
					for neighbor in neighbors:
						next_set[neighbor] = true
		current = next_set.keys()
		if current.size() == 0:
			break
	var node_ids: Dictionary = {}
	for pos_key in current:
		var parts = pos_key.split(":")
		var nid = int(parts[0])
		node_ids[nid] = true
	return node_ids.keys()

func _is_junction_key(pos_key: String) -> bool:
	return pos_key == "5:Outer" or pos_key == "10:Outer" or pos_key == "22:ShortcutA"

const JUNCTION_CHOICE_MAP: Dictionary = {
	"5:Outer": {"20:ShortcutA": "shortcut", "6:Outer": "outer"},
	"10:Outer": {"25:ShortcutB": "shortcut", "11:Outer": "outer"},
	"22:ShortcutA": {"23:ShortcutA": "continue", "27:ShortcutB": "center_exit"},
}

func calc_junction_path_map(node_id: int, path: String, distance: int) -> Dictionary:
	var start_key = str(node_id) + ":" + path
	if not _is_junction_key(start_key):
		return {}
	if distance <= 0:
		return {}
	if not GRAPH.has(start_key):
		return {}
	if not JUNCTION_CHOICE_MAP.has(start_key):
		return {}
	var choice_map: Dictionary = JUNCTION_CHOICE_MAP[start_key]
	var result: Dictionary = {}
	for first_step_key in choice_map:
		var path_choice = choice_map[first_step_key]
		var current: Array = [first_step_key]
		for step in range(distance - 1):
			var next_set: Dictionary = {}
			for pos_key in current:
				if GRAPH.has(pos_key):
					var neighbors = GRAPH[pos_key]
					if step > 0 and _is_junction_key(pos_key) and neighbors.size() > 1:
						var cur_path_str = pos_key.split(":")[1] if ":" in pos_key else "Outer"
						for neighbor in neighbors:
							var nb_path = neighbor.split(":")[1] if ":" in neighbor else "Outer"
							if nb_path == cur_path_str:
								next_set[neighbor] = true
					else:
						for neighbor in neighbors:
							next_set[neighbor] = true
			current = next_set.keys()
			if current.size() == 0:
				break
		for pos_key in current:
			var parts = pos_key.split(":")
			var nid = int(parts[0])
			result[nid] = path_choice
	return result

func passes_through_finish(node_id: int, path: String, distance: int) -> bool:
	var current: Array = [str(node_id) + ":" + path]
	for _step in range(distance):
		var next_set: Dictionary = {}
		for pos_key in current:
			if GRAPH.has(pos_key):
				for neighbor in GRAPH[pos_key]:
					if neighbor.begins_with("0:"):
						return true
					next_set[neighbor] = true
		current = next_set.keys()
		if current.size() == 0:
			break
	return false

var highlight_nodes: Array = []
var snap_target_pos: Vector2 = Vector2.ZERO
var snap_active: bool = false
var player_tray_names: Array = []
var player_team_indices: Array = []  # per-player team index (0 or 1), empty if no teams

const SNAP_RADIUS := 65.0  # Larger for mobile touch

# ─── Warm Pastel Wood Color Palette ───
const GBC_BG       := Color("FFF8E8")     # Nintendo warm cream background
const GBC_BOARD_BG := Color("F8F0D8")     # Nintendo panel cream
const GBC_LINE     := Color("907040")     # Nintendo border light
const GBC_NODE     := Color("E0C898")     # Nintendo node
const GBC_BRIGHT   := Color("FFFCF0")     # Nintendo highlight
const GBC_DARK     := Color("503820")     # Nintendo dark border
const GBC_WHITE    := Color("FFFCF0")     # Nintendo highlight (= GBC_BRIGHT)
const GBC_MID      := Color("E8D8B0")     # Nintendo button tone

const LINE_WIDTH   := 2.5
const BIG_RADIUS   := 18.0   # big node radius (corners + center)
const SMALL_RADIUS := 13.0   # small node radius

var current_turn_player_idx: int = -1  # which player index has current turn (for bounce)

func _draw() -> void:
	_draw_turn_marquee()
	_draw_board_bg()
	_draw_lines()
	_draw_nodes()
	_draw_player_trays()
	_draw_throw_area()
	_draw_snap_indicator()

func _draw_turn_marquee() -> void:
	# ═══ TOP MARQUEE BAR: y=0~34 ═══
	if TEX_FRAME_MARQUEE:
		var tex_size = TEX_FRAME_MARQUEE.get_size()
		draw_texture_rect(TEX_FRAME_MARQUEE, Rect2(0, 0, 520, 34), false)
	else:
		draw_rect(Rect2(0, 0, 520, 34), GBC_DARK)
		draw_rect(Rect2(0, 0, 520, 34), GBC_LINE, false, 2.0)
		draw_rect(Rect2(3, 3, 514, 28), Color(GBC_LINE, 0.35), false, 1.0)

func _draw_board_bg() -> void:
	# ═══ BOARD SECTION: y=36~566 ═══
	var by := 36.0
	var bh := 530.0

	# Tiling background pattern
	if TEX_BOARD_BG:
		var tile_size = TEX_BOARD_BG.get_size()
		var tile_color = Color(1, 1, 1, 0.15)  # subtle overlay
		var tx = 6
		while tx < 514:
			var ty = by + 6
			while ty < by + bh - 6:
				draw_texture(TEX_BOARD_BG, Vector2(tx, ty), tile_color)
				ty += int(tile_size.y)
			tx += int(tile_size.x)

	# Frame sprite overlay (stretch to fit new size)
	if TEX_FRAME_BOARD:
		draw_texture_rect(TEX_FRAME_BOARD, Rect2(0, by, 520, bh), false)
	else:
		draw_rect(Rect2(0, by, 520, bh), Color(GBC_DARK, 0.6))
		draw_rect(Rect2(0, by, 520, bh), GBC_LINE, false, 2.0)
		draw_rect(Rect2(3, by + 3, 514, bh - 6), Color(GBC_LINE, 0.4), false, 1.0)

	# ── Cute Animal Theme Decorations ──
	_draw_cute_decorations()

func _draw_lines() -> void:
	# Draw softer dotted-style lines for cute theme
	for conn in CONNECTIONS:
		var a = conn[0] as int
		var b = conn[1] as int
		if NODE_POSITIONS.has(a) and NODE_POSITIONS.has(b):
			var pa = NODE_POSITIONS[a]
			var pb = NODE_POSITIONS[b]
			# Soft main line
			draw_line(pa, pb, Color(GBC_LINE, 0.5), LINE_WIDTH)
			# Dotted overlay: small circles along path
			var dist = pa.distance_to(pb)
			var dot_count = int(dist / 14.0)
			for i in range(1, dot_count):
				var t = float(i) / float(dot_count)
				var dp = pa.lerp(pb, t)
				draw_circle(dp, 1.5, Color(GBC_LINE, 0.35))

func _draw_nodes() -> void:
	for node_id in NODE_POSITIONS:
		var pos: Vector2 = NODE_POSITIONS[node_id]
		var is_big: bool = node_id in BIG_NODES
		var is_highlight: bool = node_id in highlight_nodes

		# Use sprite textures for nodes
		var tex = TEX_NODE_BIG if is_big else TEX_NODE_SMALL
		if tex:
			var tex_size = tex.get_size()
			var tint = GBC_BRIGHT if is_highlight else Color.WHITE
			draw_texture(tex, pos - tex_size * 0.5, tint)
		else:
			var r: float = BIG_RADIUS if is_big else SMALL_RADIUS
			draw_circle(pos, r + 2, GBC_DARK)
			draw_circle(pos, r, GBC_BRIGHT if is_highlight else GBC_NODE)

		# Highlight glow for destination nodes (softer, cute)
		if is_highlight:
			var pulse = 0.3 + sin(Time.get_ticks_msec() * 0.005) * 0.15
			draw_arc(pos, (BIG_RADIUS if is_big else SMALL_RADIUS) + 4, 0, TAU, 24,
				Color(GBC_BRIGHT, pulse), 2.0)

		# Start/finish node — cute flower ring instead of harsh arcs
		if node_id == 0:
			var r: float = BIG_RADIUS
			# Soft double ring
			draw_arc(pos, r + 5, 0, TAU, 32, Color(GBC_MID, 0.5), 1.5)
			draw_arc(pos, r + 8, 0, TAU, 32, Color(GBC_LINE, 0.4), 1.5)
			# Tiny flower accents around start node
			if TEX_DECO_FLOWER:
				var flower_sz = TEX_DECO_FLOWER.get_size()
				for angle_deg in [45, 135, 225, 315]:
					var angle = deg_to_rad(angle_deg)
					var fp = pos + Vector2(cos(angle), sin(angle)) * (r + 12) - flower_sz * 0.5
					draw_texture(TEX_DECO_FLOWER, fp, Color(1, 1, 1, 0.5))

	# "S" label for start with paw accent
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(456, 531), "S", HORIZONTAL_ALIGNMENT_LEFT, 30, 10, GBC_MID)
	if TEX_DECO_PAW:
		draw_texture(TEX_DECO_PAW, Vector2(456, 533), Color(1, 1, 1, 0.3))

func _draw_player_trays() -> void:
	# ═══ PLAYER TRAY SECTION: y=566~724 ═══
	var ty := TRAY_Y_START - 4  # 566
	var th := TRAY_HEIGHT + 8    # 158
	var count = maxi(player_count, 2)
	var row_h = TRAY_HEIGHT / count
	var font = ThemeDB.fallback_font

	# Frame sprite or fallback
	if TEX_FRAME_TRAY:
		draw_texture_rect(TEX_FRAME_TRAY, Rect2(0, ty, 520, th), false)
	else:
		draw_rect(Rect2(0, ty, 520, th), Color(GBC_DARK, 0.85))
		draw_rect(Rect2(0, ty, 520, th), GBC_LINE, false, 2.0)
		draw_rect(Rect2(3, ty + 3, 514, th - 6), Color(GBC_LINE, 0.25), false, 1.0)

	# Section label
	draw_string(font, Vector2(10, ty + 12), "PLAYERS", HORIZONTAL_ALIGNMENT_LEFT, 80, 9, Color(GBC_LINE, 0.5))

	for i in range(mini(player_tray_names.size(), count)):
		var row_y = TRAY_Y_START + i * row_h
		var is_current = (i == current_turn_player_idx)

		# Row separator
		if i > 0:
			draw_line(Vector2(8, row_y), Vector2(512, row_y), Color(GBC_LINE, 0.3), 1.0)

		# Highlight current turn row
		if is_current:
			draw_rect(Rect2(4, row_y + 1, 512, row_h - 2), Color(GBC_LINE, 0.15))
			# Turn arrow indicator
			draw_string(font, Vector2(10, row_y + row_h * 0.5 + 4), ">",
				HORIZONTAL_ALIGNMENT_LEFT, 20, 14, GBC_BRIGHT)

		# Team badge (if in team mode)
		var name_x = 26.0
		if player_team_indices.size() > i:
			var team_idx = int(player_team_indices[i])
			var badge_label = "A" if team_idx == 0 else "B"
			var badge_color = Color("D05848") if team_idx == 0 else Color("5880C8")
			var bx = 26.0
			var by = row_y + row_h * 0.5
			var badge_center = Vector2(bx + 6, by)
			draw_circle(badge_center, 8, Color(badge_color, 0.7))
			var badge_tw = font.get_string_size(badge_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(font, Vector2(badge_center.x - badge_tw * 0.5, badge_center.y + 4), badge_label,
				HORIZONTAL_ALIGNMENT_LEFT, 14, 10, GBC_BRIGHT)
			name_x = 42.0

		# Player name (left side)
		var name_str = player_tray_names[i]
		if name_str.length() > 8:
			name_str = name_str.left(7) + ".."
		var name_color = GBC_BRIGHT if is_current else GBC_MID
		draw_string(font, Vector2(name_x, row_y + row_h * 0.5 + 4), name_str,
			HORIZONTAL_ALIGNMENT_LEFT, 120, 13, name_color)

		# Piece slot indicators (right side)
		for slot in range(4):
			var sx = 185 + slot * 55
			var sy = row_y + row_h * 0.5
			draw_circle(Vector2(sx, sy), 8, Color(GBC_LINE, 0.2))

func _draw_throw_area() -> void:
	# ═══ THROW AREA SECTION: y=720~922 ═══
	var area_y := 720.0
	var area_h := 202.0

	if TEX_FRAME_THROW:
		draw_texture_rect(TEX_FRAME_THROW, Rect2(0, area_y, 520, area_h), false)
	else:
		draw_rect(Rect2(0, area_y, 520, area_h), Color("FFF8E8"))
		draw_rect(Rect2(0, area_y, 520, area_h), GBC_LINE, false, 2.0)
		draw_rect(Rect2(3, area_y + 3, 514, area_h - 6), Color(GBC_LINE, 0.2), false, 1.0)

	# Section label
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(10, area_y + 12), "THROW", HORIZONTAL_ALIGNMENT_LEFT, 80, 9, Color(GBC_LINE, 0.4))

func _draw_snap_indicator() -> void:
	if not snap_active:
		return
	var pulse = 0.5 + sin(Time.get_ticks_msec() * 0.008) * 0.3
	draw_arc(snap_target_pos, 24, 0, TAU, 32, Color(GBC_BRIGHT, pulse), 3.0)
	draw_arc(snap_target_pos, 16, 0, TAU, 24, Color(GBC_MID, pulse * 0.5), 2.0)
	var ch = 7.0
	draw_line(snap_target_pos + Vector2(-ch, 0), snap_target_pos + Vector2(ch, 0),
		Color(GBC_BRIGHT, pulse), 2.0)
	draw_line(snap_target_pos + Vector2(0, -ch), snap_target_pos + Vector2(0, ch),
		Color(GBC_BRIGHT, pulse), 2.0)

# ─── Cute Animal Theme Decorations ───

func _draw_cute_decorations() -> void:
	# Scatter paw prints, flowers, grass, and stars around the board
	# These are placed in the spaces between the board lines and edges

	# ── Paw prints along edges (subtle, rotated) ──
	if TEX_DECO_PAW:
		var paw_positions = [
			# Top edge
			Vector2(175, 60), Vector2(345, 60),
			# Bottom edge
			Vector2(175, 545), Vector2(345, 545),
			# Left edge
			Vector2(22, 215), Vector2(22, 395),
			# Right edge
			Vector2(495, 215), Vector2(495, 395),
		]
		for pp in paw_positions:
			var paw_sz = TEX_DECO_PAW.get_size()
			draw_texture(TEX_DECO_PAW, pp - paw_sz * 0.5, Color(1, 1, 1, 0.25))

	# ── Flowers in the four inner quadrants ──
	if TEX_DECO_FLOWER:
		var flower_positions = [
			# Top-left quadrant
			Vector2(110, 155), Vector2(155, 195),
			# Top-right quadrant
			Vector2(400, 155), Vector2(365, 195),
			# Bottom-left quadrant
			Vector2(110, 445), Vector2(155, 405),
			# Bottom-right quadrant
			Vector2(400, 445), Vector2(365, 405),
			# Center area accents
			Vector2(200, 265), Vector2(320, 340),
		]
		var flower_sz = TEX_DECO_FLOWER.get_size()
		for fp in flower_positions:
			draw_texture(TEX_DECO_FLOWER, fp - flower_sz * 0.5, Color(1, 1, 1, 0.35))

	# ── Grass tufts near outer nodes ──
	if TEX_DECO_GRASS:
		var grass_positions = [
			Vector2(132, 100), Vector2(303, 100), # top
			Vector2(132, 528), Vector2(303, 528), # bottom
			Vector2(58, 258), Vector2(58, 344),    # left
			Vector2(486, 258), Vector2(486, 344),  # right
		]
		var grass_sz = TEX_DECO_GRASS.get_size()
		for gp in grass_positions:
			draw_texture(TEX_DECO_GRASS, gp - grass_sz * 0.5, Color(1, 1, 1, 0.3))

	# ── Stars in diagonal path spaces ──
	if TEX_DECO_STAR:
		var star_positions = [
			# Diagonal A spaces
			Vector2(370, 140), Vector2(295, 260),
			# Diagonal B spaces
			Vector2(150, 140), Vector2(225, 260),
			# Center accent
			Vector2(260, 301),
		]
		var star_sz = TEX_DECO_STAR.get_size()
		for sp in star_positions:
			draw_texture(TEX_DECO_STAR, sp - star_sz * 0.5, Color(1, 1, 1, 0.3))

	# ── Soft border decoration (tiny circles instead of diamonds) ──
	var deco_col = Color(GBC_NODE, 0.15)
	# Top border
	for i in range(10):
		var cx = 50 + i * 44
		draw_circle(Vector2(cx, 50), 2.5, deco_col)
	# Bottom border
	for i in range(10):
		var cx = 50 + i * 44
		draw_circle(Vector2(cx, 552), 2.5, deco_col)
	# Left border
	for i in range(8):
		var cy = 110 + i * 55
		draw_circle(Vector2(20, cy), 2.5, deco_col)
	# Right border
	for i in range(8):
		var cy = 110 + i * 55
		draw_circle(Vector2(500, cy), 2.5, deco_col)

# ─── Public helpers ───

func set_player_names(names: Array, team_indices: Array = []) -> void:
	player_tray_names = names
	player_team_indices = team_indices
	player_count = names.size()
	queue_redraw()

func set_current_turn_index(idx: int) -> void:
	current_turn_player_idx = idx
	queue_redraw()

func get_node_position(node_id: int) -> Vector2:
	if NODE_POSITIONS.has(node_id):
		return NODE_POSITIONS[node_id]
	return Vector2.ZERO

func get_home_position(player_index: int, piece_index: int) -> Vector2:
	return get_dynamic_home_position(player_index, piece_index)

func set_highlights(nodes: Array) -> void:
	highlight_nodes = nodes
	queue_redraw()

func clear_highlights() -> void:
	highlight_nodes.clear()
	snap_active = false
	snap_target_pos = Vector2.ZERO
	queue_redraw()

func get_snap_target(world_pos: Vector2, valid_nodes: Array) -> Dictionary:
	var best_id: int = -1
	var best_dist: float = SNAP_RADIUS
	var best_pos: Vector2 = Vector2.ZERO
	for nid in valid_nodes:
		if not NODE_POSITIONS.has(nid):
			continue
		var npos: Vector2 = NODE_POSITIONS[nid]
		var dist = world_pos.distance_to(npos)
		if dist < best_dist:
			best_dist = dist
			best_id = nid
			best_pos = npos
	if best_id >= 0:
		return {"node_id": best_id, "position": best_pos}
	return {}

func update_snap_indicator(world_pos: Vector2, valid_nodes: Array) -> Dictionary:
	var snap = get_snap_target(world_pos, valid_nodes)
	if snap.size() > 0:
		snap_active = true
		snap_target_pos = snap["position"]
	else:
		snap_active = false
	queue_redraw()
	return snap
