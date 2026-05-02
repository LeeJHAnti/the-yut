extends CanvasLayer

## Global dot-matrix LCD overlay.
## Applies a subtle Game Boy LCD texture across all scenes.
## No visible grid — just a faint pixel texture, noise, and vignette.

var overlay_rect: ColorRect

func _ready() -> void:
	layer = 100
	follow_viewport_enabled = false

	overlay_rect = ColorRect.new()
	overlay_rect.name = "DotMatrixRect"
	overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader = load("res://assets/shaders/dot_matrix.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader

	# Subtle dot modulation — gives LCD pixel feel without visible grid
	material.set_shader_parameter("dot_modulation", 0.04)
	material.set_shader_parameter("cell_size", 2.5)

	# Fine noise grain — LCD sub-pixel irregularity
	material.set_shader_parameter("noise_strength", 0.025)

	# Very faint scanlines
	material.set_shader_parameter("scanline_strength", 0.035)

	# Gentle edge darkening
	material.set_shader_parameter("vignette_strength", 0.10)

	# No brightness loss
	material.set_shader_parameter("brightness", 1.0)

	overlay_rect.material = material
	add_child(overlay_rect)
