extends Camera2D

## Enhanced screen effects: shake, flash, freeze-frame, zoom punch.

var shake_intensity: float = 0.0
var shake_timer: float = 0.0
var shake_decay: float = 1.0

var freeze_timer: float = 0.0
var is_frozen: bool = false

func _process(delta: float) -> void:
	# Freeze frame (time stops briefly for impact)
	if freeze_timer > 0:
		freeze_timer -= delta
		if freeze_timer <= 0:
			is_frozen = false
			Engine.time_scale = 1.0
		return

	# Camera shake with decay
	if shake_timer > 0:
		shake_timer -= delta
		var t = shake_timer / shake_decay
		var current_intensity = shake_intensity * t
		offset = Vector2(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)
		if shake_timer <= 0:
			offset = Vector2.ZERO

## Standard shake with decay
func shake(intensity: float = 8.0, duration: float = 0.2) -> void:
	shake_intensity = intensity
	shake_timer = duration
	shake_decay = duration

## Heavy shake for captures / Yut / Mo
func heavy_shake(duration: float = 0.4) -> void:
	shake(16.0, duration)

## Screen flash (white overlay)
func flash(duration: float = 0.1) -> void:
	var flash_rect = get_node_or_null("FlashRect")
	if flash_rect:
		flash_rect.visible = true
		flash_rect.modulate.a = 0.9
		var tween = create_tween()
		tween.tween_property(flash_rect, "modulate:a", 0.0, duration)
		tween.tween_callback(func(): flash_rect.visible = false)

## Brief freeze-frame for dramatic impact
func freeze_frame(duration: float = 0.06) -> void:
	is_frozen = true
	freeze_timer = duration
	Engine.time_scale = 0.05

## Zoom punch: quick zoom in then back (for Yut/Mo)
func zoom_punch(amount: float = 0.1, duration: float = 0.2) -> void:
	var original_zoom = zoom
	var punched = original_zoom + Vector2(amount, amount)
	var tween = create_tween()
	tween.tween_property(self, "zoom", punched, duration * 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "zoom", original_zoom, duration * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
