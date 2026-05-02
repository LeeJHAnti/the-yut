shader_type canvas_item;

// ═══════════════════════════════════════════════════════════
// Game Boy DMG LCD Dot-Matrix Shader  (Soft variant)
// ═══════════════════════════════════════════════════════════
// Gives a subtle "looking at an LCD" feeling through:
//   1. Fine per-pixel brightness modulation (dot texture, no grid)
//   2. Gentle scanlines
//   3. Soft vignette
//   4. Slight noise grain
// The grid itself is NOT visible — only the overall texture feel.
// ═══════════════════════════════════════════════════════════

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

// How much each pixel's brightness subtly varies (dot feel)
uniform float dot_modulation : hint_range(0.0, 0.15, 0.005) = 0.04;

// Pixel cell size for the modulation pattern
uniform float cell_size : hint_range(1.5, 6.0, 0.5) = 2.5;

// Fine noise grain strength
uniform float noise_strength : hint_range(0.0, 0.1, 0.005) = 0.025;

// Scanline
uniform float scanline_strength : hint_range(0.0, 0.15, 0.005) = 0.035;

// Vignette
uniform float vignette_strength : hint_range(0.0, 0.4, 0.01) = 0.10;

// Overall brightness
uniform float brightness : hint_range(0.7, 1.3, 0.01) = 1.0;

// Simple hash for per-pixel noise
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 pixel_coord = SCREEN_UV * screen_size;

	vec3 result = screen_color.rgb;

	// ── Dot modulation ──
	// Subtle brightness variation per pixel-cell.
	// Each cell's center is slightly brighter than edges,
	// but the difference is so small that no grid is visible —
	// just a faint LCD texture feel.
	vec2 cell = mod(pixel_coord, cell_size);
	vec2 center = vec2(cell_size * 0.5);
	float dist_from_center = length(cell - center) / (cell_size * 0.707);
	// Soft cosine falloff — no hard edge
	float dot_factor = 1.0 - dot_modulation * (0.5 + 0.5 * dist_from_center * dist_from_center);
	result *= dot_factor;

	// ── Fine noise grain ──
	// Adds a very subtle per-pixel static noise, like LCD sub-pixel irregularity
	float noise = hash(pixel_coord + fract(TIME * 0.1)) * 2.0 - 1.0;
	result += vec3(noise * noise_strength);

	// ── Scanlines ──
	// Very faint horizontal darkening every other line
	float scan = 1.0 - scanline_strength * (0.5 + 0.5 * sin(pixel_coord.y * PI));
	result *= scan;

	// ── Vignette ──
	vec2 uv_c = SCREEN_UV - 0.5;
	float vig = 1.0 - dot(uv_c, uv_c) * vignette_strength * 3.5;
	result *= vig;

	// ── Brightness ──
	result *= brightness;

	COLOR = vec4(result, screen_color.a);
}
