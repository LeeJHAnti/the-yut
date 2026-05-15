extends Node2D
## Lightweight Game Boy-style particle effects drawn with _draw().
## Spawn via static helpers — each instance auto-frees after its lifetime.
## Scaled for 540×960 viewport. GBC color palette.

# ═══ Preload particle sprite ═══
const TEX_STAR = preload("res://assets/sprites/particle_star.png")

# ─── Dust Puff (landing / hop) ───
class DustPuff extends Node2D:
	var lifetime := 0.35
	var age := 0.0
	var particles: Array = []
	var _rc: int = 0

	func _init(count: int = 5, spread: float = 20.0):
		for i in range(count):
			particles.append({
				"pos": Vector2(randf_range(-spread, spread), 0),
				"vel": Vector2(randf_range(-25, 25), randf_range(-35, -12)),
				"size": randf_range(3.0, 7.0),
			})

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		for p in particles:
			p.pos += p.vel * delta
			p.vel.y += 60 * delta
		_rc += 1
		if _rc >= 3:
			_rc = 0
			queue_redraw()

	func _draw() -> void:
		var alpha = clampf(1.0 - age / lifetime, 0, 1)
		var color = Color("907040", alpha)
		for p in particles:
			draw_circle(p.pos, p.size * (1.0 - age / lifetime), color)


# ─── Star Burst (yut/mo, capture, finish) ───
class StarBurst extends Node2D:
	var lifetime := 0.5
	var age := 0.0
	var rays: Array = []
	var _rc: int = 0

	func _init(ray_count: int = 8, max_radius: float = 60.0):
		for i in range(ray_count):
			var angle = (TAU / ray_count) * i + randf_range(-0.15, 0.15)
			rays.append({
				"angle": angle,
				"speed": max_radius / 0.3,
				"length": randf_range(12.0, 25.0),
				"dist": 0.0,
			})

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		for r in rays:
			r.dist += r.speed * delta
		_rc += 1
		if _rc >= 3:
			_rc = 0
			queue_redraw()

	func _draw() -> void:
		var alpha = clampf(1.0 - age / lifetime, 0, 1)
		var bright = Color("E0C898", alpha)
		var dim = Color("907040", alpha * 0.6)
		for r in rays:
			var dir = Vector2.from_angle(r.angle)
			var start = dir * maxf(r.dist - r.length, 0)
			var end = dir * r.dist
			draw_line(start, end, bright, 2.0)
			draw_line(start * 0.8, end * 0.8, dim, 1.5)


# ─── Impact Ring (capture hit) ───
class ImpactRing extends Node2D:
	var lifetime := 0.3
	var age := 0.0
	var max_radius := 40.0
	var _rc: int = 0

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		_rc += 1
		if _rc >= 3:
			_rc = 0
			queue_redraw()

	func _draw() -> void:
		var t = age / lifetime
		var radius = max_radius * t
		var alpha = 1.0 - t
		var color = Color("E0C898", alpha)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 12, color, 3.0)
		if radius > 10:
			draw_arc(Vector2.ZERO, radius * 0.6, 0, TAU, 10, Color("907040", alpha * 0.5), 2.0)


# ─── Speed Lines (piece moving fast) ───
class SpeedLines extends Node2D:
	var lifetime := 0.2
	var age := 0.0
	var direction := Vector2.LEFT
	var lines: Array = []
	var _rc: int = 0

	func _init(dir: Vector2 = Vector2.LEFT, count: int = 5):
		direction = dir.normalized()
		for i in range(count):
			lines.append({
				"offset": Vector2(randf_range(-12, 12), randf_range(-18, 18)),
				"length": randf_range(12, 30),
			})

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		_rc += 1
		if _rc >= 3:
			_rc = 0
			queue_redraw()

	func _draw() -> void:
		var alpha = clampf(1.0 - age / lifetime, 0, 1)
		var color = Color("907040", alpha)
		for l in lines:
			var start = l.offset
			var end = start + direction * l.length
			draw_line(start, end, color, 2.0)


# ─── Rising Sparkles (finish celebration) ───
class Sparkles extends Node2D:
	var lifetime := 0.8
	var age := 0.0
	var sparks: Array = []
	var _rc: int = 0

	func _init(count: int = 10, spread: float = 40.0):
		for i in range(count):
			sparks.append({
				"pos": Vector2(randf_range(-spread, spread), randf_range(-6, 6)),
				"vel": Vector2(randf_range(-18, 18), randf_range(-60, -25)),
				"blink_rate": randf_range(8, 16),
			})

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		for s in sparks:
			s.pos += s.vel * delta
			s.vel.x *= 0.98
		_rc += 1
		if _rc >= 3:
			_rc = 0
			queue_redraw()

	func _draw() -> void:
		var alpha = clampf(1.0 - age / lifetime, 0, 1)
		for s in sparks:
			if int(age * s.blink_rate) % 2 == 0:
				if TEX_STAR:
					var tex_size = TEX_STAR.get_size()
					draw_texture(TEX_STAR, s.pos - tex_size * 0.5, Color("E0C898", alpha))
				else:
					draw_rect(Rect2(s.pos.x, s.pos.y, 3, 3), Color("E0C898", alpha))


# ─── Merge Pulse (stacking) ───
class MergePulse extends Node2D:
	var lifetime := 0.25
	var age := 0.0
	var _rc: int = 0

	func _process(delta: float) -> void:
		age += delta
		if age >= lifetime:
			queue_free()
			return
		_rc += 1
		if _rc >= 3:
			_rc = 0
			queue_redraw()

	func _draw() -> void:
		var t = age / lifetime
		var radius = 10.0 + 25.0 * t
		var alpha = 1.0 - t
		draw_arc(Vector2.ZERO, radius, 0, TAU, 12, Color("E0C898", alpha), 2.0)


# ─── Spawn helpers (call from any node) ───
static func spawn_dust(parent: Node, pos: Vector2, count: int = 5) -> void:
	var dust = DustPuff.new(count)
	dust.position = pos
	parent.add_child(dust)

static func spawn_stars(parent: Node, pos: Vector2, count: int = 8) -> void:
	var stars = StarBurst.new(count)
	stars.position = pos
	parent.add_child(stars)

static func spawn_impact(parent: Node, pos: Vector2) -> void:
	var ring = ImpactRing.new()
	ring.position = pos
	parent.add_child(ring)

static func spawn_speed_lines(parent: Node, pos: Vector2, dir: Vector2) -> void:
	var lines = SpeedLines.new(dir)
	lines.position = pos
	parent.add_child(lines)

static func spawn_sparkles(parent: Node, pos: Vector2, count: int = 10) -> void:
	var sp = Sparkles.new(count)
	sp.position = pos
	parent.add_child(sp)

static func spawn_merge_pulse(parent: Node, pos: Vector2) -> void:
	var mp = MergePulse.new()
	mp.position = pos
	parent.add_child(mp)
