shader_type canvas_item;
// Synthwave title background: gradient sky with a banded sun and a scrolling
// perspective grid — now viewed through an animated "water" layer that ripples,
// shimmers, and reacts to the mouse.

uniform float speed : hint_range(0.0, 2.0) = 0.35;
uniform vec2 mouse = vec2(0.5, 0.5);              // cursor pos in 0..1 (fed by title.gd)
uniform float ripple_strength : hint_range(0.0, 3.0) = 1.0;

const vec3 SKY_TOP = vec3(0.09, 0.02, 0.22);
const vec3 SKY_MID = vec3(0.45, 0.09, 0.36);
const vec3 SUN_TOP = vec3(1.0, 0.92, 0.45);
const vec3 SUN_BOT = vec3(1.0, 0.28, 0.5);
const vec3 GRID = vec3(0.95, 0.25, 0.85);
const vec3 GROUND = vec3(0.05, 0.01, 0.11);

// Procedural scene at a given uv (the original synthwave background).
vec3 scene(vec2 uv) {
	float horizon = 0.60;
	vec3 col;
	if (uv.y < horizon) {
		float t = uv.y / horizon;
		col = mix(SKY_TOP, SKY_MID, t * t);
		vec2 p = uv - vec2(0.5, horizon);
		p.x *= 1.7;
		float d = length(p);
		float inside = smoothstep(0.27, 0.255, d);
		float sy = clamp((uv.y - (horizon - 0.27)) / 0.27, 0.0, 1.0);
		vec3 suncol = mix(SUN_BOT, SUN_TOP, sy);
		float bands = step(0.5, fract((horizon - uv.y) * 45.0));
		float lower = smoothstep(horizon, horizon - 0.16, uv.y);
		inside *= 1.0 - bands * lower;
		col = mix(col, suncol, inside);
	} else {
		float g = (uv.y - horizon) / (1.0 - horizon);
		float depth = 0.15 / (g + 0.02);
		float lw = 0.05;
		float vx = fract((uv.x - 0.5) * depth * 8.0);
		float vline = smoothstep(lw, 0.0, min(vx, 1.0 - vx));
		float hy = fract(depth * 6.0 - TIME * speed);
		float hline = smoothstep(lw, 0.0, min(hy, 1.0 - hy));
		float grid = max(vline, hline) * clamp(g * 2.5, 0.0, 1.0);
		col = mix(GROUND, GRID, grid);
	}
	return col;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// Subtle parallax: the whole scene leans toward the cursor.
	uv += (mouse - 0.5) * 0.02;

	// Layered "water" wobble — bigger, slower swells (larger amplitude, lower freq/speed).
	vec2 w;
	w.x = sin(uv.y * 14.0 + t * 0.55) * 0.010 + sin(uv.y * 33.0 - t * 0.35) * 0.004;
	w.y = sin(uv.x * 12.0 + t * 0.5) * 0.010 + sin(uv.x * 29.0 + t * 0.4) * 0.004;

	// Ripples radiating out from the cursor (stronger near it, fading with distance).
	vec2 to_mouse = uv - mouse;
	float md = length(to_mouse);
	float ring = sin(md * 42.0 - t * 2.4) * exp(-md * 6.0) * 0.016;
	w += normalize(to_mouse + vec2(1e-4)) * ring;

	vec2 duv = uv + w * ripple_strength;
	vec3 col = scene(duv);

	// Watery shimmer/caustics — faint moving highlights, brighter near the cursor.
	float c = sin((duv.x * 30.0) + t * 0.8) * sin((duv.y * 27.0) - t * 0.6);
	c = smoothstep(0.55, 1.0, c);
	float near = 0.5 + 0.5 * exp(-md * 4.0);
	col += vec3(0.35, 0.5, 0.8) * c * 0.05 * near;

	COLOR = vec4(col, 1.0);
}
