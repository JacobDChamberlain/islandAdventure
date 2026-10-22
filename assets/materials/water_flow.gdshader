shader_type spatial;
// Flowing water for Sky Valley's river and waterfall. The mesh's UV.y runs
// DOWNSTREAM (metres / uv_scale along the ribbon), so streaks of foam slide the
// way the water goes. `speed` is high on the waterfall, gentle on the river.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 deep : source_color = vec4(0.10, 0.48, 0.70, 0.82);
uniform vec4 foam : source_color = vec4(0.86, 0.95, 1.0, 1.0);
uniform float speed = 0.5;
uniform float foam_amount = 0.16;   // share of the surface that is white streak
uniform float stretch = 0.6;        // streak length (lower = longer)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float t = TIME * speed;
	float n = noise(vec2(UV.x * 6.0, UV.y * stretch - t * 3.0)) * 0.6
		+ noise(vec2(UV.x * 15.0, UV.y * stretch * 2.6 - t * 5.0)) * 0.4;
	float streak = smoothstep(1.0 - foam_amount, 1.0, n);
	ALBEDO = mix(deep.rgb, foam.rgb, streak);
	ALPHA = mix(deep.a, 1.0, streak);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 0.6;
	EMISSION = foam.rgb * streak * 0.12;
}
