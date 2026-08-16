shader_type canvas_item;
// Old-school synthwave title background: gradient sky with a banded sun and a
// perspective grid scrolling toward the viewer.

uniform float speed : hint_range(0.0, 2.0) = 0.35;

const vec3 SKY_TOP = vec3(0.09, 0.02, 0.22);
const vec3 SKY_MID = vec3(0.45, 0.09, 0.36);
const vec3 SUN_TOP = vec3(1.0, 0.92, 0.45);
const vec3 SUN_BOT = vec3(1.0, 0.28, 0.5);
const vec3 GRID = vec3(0.95, 0.25, 0.85);
const vec3 GROUND = vec3(0.05, 0.01, 0.11);

void fragment() {
	vec2 uv = UV;
	float horizon = 0.60;
	vec3 col;

	if (uv.y < horizon) {
		// Sky gradient (top dark → warmer toward horizon).
		float t = uv.y / horizon;
		col = mix(SKY_TOP, SKY_MID, t * t);

		// Retro sun centered on the horizon (x scaled for a rounder shape).
		vec2 p = uv - vec2(0.5, horizon);
		p.x *= 1.7;
		float d = length(p);
		float inside = smoothstep(0.27, 0.255, d);
		float sy = clamp((uv.y - (horizon - 0.27)) / 0.27, 0.0, 1.0);
		vec3 suncol = mix(SUN_BOT, SUN_TOP, sy);
		// Horizontal cut bands across the lower half of the sun.
		float bands = step(0.5, fract((horizon - uv.y) * 45.0));
		float lower = smoothstep(horizon, horizon - 0.16, uv.y);
		inside *= 1.0 - bands * lower;
		col = mix(col, suncol, inside);
	} else {
		// Perspective ground grid.
		float g = (uv.y - horizon) / (1.0 - horizon);   // 0 at horizon .. 1 at bottom
		float depth = 0.15 / (g + 0.02);                // dense near horizon
		float lw = 0.05;
		float vx = fract((uv.x - 0.5) * depth * 8.0);
		float vline = smoothstep(lw, 0.0, min(vx, 1.0 - vx));
		float hy = fract(depth * 6.0 - TIME * speed);
		float hline = smoothstep(lw, 0.0, min(hy, 1.0 - hy));
		float grid = max(vline, hline) * clamp(g * 2.5, 0.0, 1.0);
		col = mix(GROUND, GRID, grid);
	}
	COLOR = vec4(col, 1.0);
}
