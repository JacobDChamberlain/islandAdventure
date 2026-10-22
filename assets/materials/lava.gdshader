shader_type spatial;
// Lava: a slow churn of glowing orange under a dark crust. Mapped in WORLD
// space (xz), so any lava surface — crater, channel, pool — needs no UVs and
// tiles seamlessly into its neighbours.
render_mode cull_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.5, 0.08);
uniform vec3 crust : source_color = vec3(0.13, 0.035, 0.02);
uniform float speed = 0.06;
uniform float glow = 3.2;
uniform vec2 flow = vec2(0.0, 1.0);   // drift direction (world xz)

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * speed;
	vec2 p = wpos.xz * 0.08;
	float n = noise(p + flow * t) * 0.6 + noise(p * 3.1 - flow * t * 1.7 + 4.0) * 0.4;
	float m = smoothstep(0.32, 0.72, n);
	ALBEDO = mix(crust, hot, m);
	EMISSION = hot * m * glow + vec3(0.5, 0.08, 0.0) * 0.5;
	ROUGHNESS = 0.85;
}
