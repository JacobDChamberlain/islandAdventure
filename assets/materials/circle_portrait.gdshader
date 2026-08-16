shader_type canvas_item;
// Masks a square viewport texture into a circle, fills empty background,
// and draws a colored ring frame around the edge.

uniform vec4 bg_color : source_color = vec4(0.08, 0.10, 0.14, 1.0);
uniform vec4 ring_color : source_color = vec4(0.95, 0.55, 0.15, 1.0);
uniform float ring_thickness = 0.10;

void fragment() {
	vec2 c = (UV - vec2(0.5)) * 2.0; // -1..1 from center
	float d = length(c);
	if (d > 1.0) {
		discard; // outside the circle
	}
	vec4 tex = texture(TEXTURE, UV);
	// Composite the head over the solid background (viewport is transparent).
	vec3 col = mix(bg_color.rgb, tex.rgb, tex.a);
	// Ring near the outer edge.
	float ring = smoothstep(1.0 - ring_thickness, 1.0 - ring_thickness * 0.5, d);
	col = mix(col, ring_color.rgb, ring);
	// Soft anti-aliased outer edge.
	float edge = 1.0 - smoothstep(0.97, 1.0, d);
	COLOR = vec4(col, edge);
}
