extends Control

## Rules screen — displays game rules in English
## Styled to match the Nintendo RPG game theme

signal closed

func _ready() -> void:
	# Create semi-transparent backdrop
	var backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.5)
	backdrop.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_close()
	)
	add_child(backdrop)

	# Main panel
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(PRESET_CENTER)
	panel.position = Vector2(20, 30)
	panel.size = Vector2(480, 880)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("F8F0D8")
	panel_style.border_color = Color("503820")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel_style.shadow_color = Color(0, 0, 0, 0.3)
	panel_style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = ">> HOW TO PLAY <<"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("503820"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Scroll container for rules text
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var rules_label = RichTextLabel.new()
	rules_label.bbcode_enabled = true
	rules_label.fit_content = true
	rules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_label.add_theme_font_size_override("normal_font_size", 13)
	rules_label.add_theme_font_size_override("bold_font_size", 14)
	rules_label.add_theme_color_override("default_color", Color("503820"))
	rules_label.text = _get_rules_text()
	scroll.add_child(rules_label)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "> CLOSE"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.pressed.connect(_close)
	vbox.add_child(close_btn)

func _close() -> void:
	closed.emit()
	queue_free()

func _get_rules_text() -> String:
	return """[b]YUTNORI[/b] is a traditional Korean board game for 2-4 players. Race your 4 pieces around the board to the finish!

[b]THE BOARD[/b]
The board has 20 outer nodes forming a rectangle, plus 2 diagonal shortcuts through the center. Pieces move counter-clockwise from START (bottom-right corner).

[b]THROWING YUT[/b]
Each turn, you throw 4 yut sticks. The result determines how many steps your piece moves:
  [b]Do[/b] (1 flat) = 1 step
  [b]Gae[/b] (2 flat) = 2 steps
  [b]Geol[/b] (3 flat) = 3 steps
  [b]Yut[/b] (4 flat) = 4 steps + extra throw!
  [b]Mo[/b] (0 flat) = 5 steps + extra throw!
  [b]BackDo[/b] (special) = 1 step backward

[b]MOVING PIECES[/b]
Drag a piece to move it. Pieces start off the board and enter at START (node 0) on their first move.

[b]SHORTCUTS[/b]
When landing on corner nodes (top-right or top-left), you may choose to take a diagonal shortcut through the center — a faster path to the finish!

[b]STACKING (EOPGI)[/b]
If your piece lands on a space occupied by your own piece, they stack together and move as one group.

[b]CAPTURING (JAPGI)[/b]
If your piece lands on an opponent's piece, the opponent's piece (and any stacked with it) is sent home! You also get a bonus throw.

[b]FINISHING[/b]
A piece finishes when it passes through or lands on START after completing the circuit. The first player to finish all 4 pieces wins!

[b]TEAM MODE (4 PLAYERS)[/b]
With 4 players, it's 2v2! Players 1 & 3 are a team, Players 2 & 4 are a team. Both teammates must finish all pieces to win.

[b]TIPS[/b]
Use shortcuts when possible — they save many steps! Stack pieces for safety but beware — if captured, you lose the whole group!"""
