extends Control

signal yut_flicked(power: float)

var touch_start: Vector2 = Vector2.ZERO
var touch_start_time: float = 0.0
var is_touching: bool = false
var enabled: bool = false

const MIN_FLICK_DISTANCE: float = 30.0  # In game coords (540x960 portrait)
const MAX_FLICK_TIME: float = 0.5

func _input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseButton:
		if event.pressed:
			touch_start = event.position
			touch_start_time = Time.get_ticks_msec() / 1000.0
			is_touching = true
		elif is_touching:
			is_touching = false
			_check_flick(event.position)

	elif event is InputEventScreenTouch:
		if event.pressed:
			touch_start = event.position
			touch_start_time = Time.get_ticks_msec() / 1000.0
			is_touching = true
		else:
			is_touching = false
			_check_flick(event.position)

func _check_flick(end_pos: Vector2) -> void:
	var delta = end_pos - touch_start
	var distance = delta.length()
	var elapsed = (Time.get_ticks_msec() / 1000.0) - touch_start_time

	if distance >= MIN_FLICK_DISTANCE and elapsed <= MAX_FLICK_TIME:
		var power = clampf(distance / 200.0, 0.0, 1.0)
		yut_flicked.emit(power)
	elif elapsed <= MAX_FLICK_TIME:
		# Tap also counts as a throw (low power)
		yut_flicked.emit(0.5)
