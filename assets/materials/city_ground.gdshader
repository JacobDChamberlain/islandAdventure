shader_type spatial;
// The city's ground, painted entirely from world position: asphalt with lane
// markings, crosswalks and stop lines; concrete sidewalk slabs with joints and
// cracks; brick pavers in the plaza; grass in the parks. city.gd feeds it the
// same grid numbers it builds the streets from, so paint and geometry agree.
// Parks are per-block random, so city.gd bakes them into a tiny block_data
// texture (one texel per block, red = park).

uniform float pitch = 56.0;          // block_size + road_width: road centrelines sit on multiples
uniform float road_width = 12.0;
uniform float block_size = 44.0;
uniform float plaza_radius = 34.0;
uniform float sidewalk_width = 4.5;  // park blocks are grass inside this ring
uniform float slab_target = 1.6;     // slab size, nudged so a whole number fit a block edge
uniform sampler2D block_data : filter_nearest;
uniform int block_offset = 8;        // texel = block index + offset

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + 17.1;
		a *= 0.5;
	}
	return v;
}

// 1 where |d| < hw, anti-aliased by the pixel footprint so thin lines fade to
// their true coverage in the distance instead of shimmering.
float band(float d, float hw) {
	float w = fwidth(d) + 1e-4;
	return 1.0 - smoothstep(hw - w, hw + w, abs(d));
}

// Fine detail fades out once it gets smaller than a pixel.
float detail_fade(vec2 p, float freq) {
	float w = length(fwidth(p)) * freq;
	return 1.0 - smoothstep(0.4, 1.2, w);
}

// Wandering hairline cracks, only where a low-frequency mask allows them.
// A noise contour is fat wherever the noise is flat, so the distance to it is
// divided by the noise's slope: that keeps every crack the same width in metres.
// The jitter on the lookup is what makes them jagged rather than smooth loops.
float cracks(vec2 p, float density) {
	float mask = smoothstep(1.0 - density, 1.0 - density + 0.15, vnoise(p * 0.08 + 3.0));
	if (mask <= 0.0) {
		return 0.0;
	}
	vec2 q = p * 0.35 + (vec2(vnoise(p * 2.5), vnoise(p * 2.5 + 9.0)) - 0.5) * 0.12;
	float n = fbm(q);
	float e = 0.01;
	vec2 slope = vec2(fbm(q + vec2(e, 0.0)) - n, fbm(q + vec2(0.0, e)) - n) / e * 0.35;
	float d = (n - 0.5) / max(length(slope), 0.02);
	return band(d, 0.01) * mask;
}

// --- Road --------------------------------------------------------------------
// u = across the road (0 at the centreline), v = along it (0 at the nearest
// intersection). Returns paint colour in rgb, paint coverage in a.
vec4 road_paint(float u, float v, vec2 p) {
	float hw = road_width * 0.5;
	float a = abs(v) - hw;                 // distance past the intersection's edge
	if (a < 0.0) {
		return vec4(0.0);                  // inside the junction: bare asphalt
	}
	vec3 white = vec3(0.86, 0.86, 0.82);
	vec3 yellow = vec3(0.88, 0.68, 0.16);
	float edge = hw - 1.3;                 // the curb ramp covers the outer metre
	// Zebra crosswalk: bars parallel to traffic, repeated across the road.
	if (a > 1.0 && a < 4.0 && abs(u) < edge) {
		float t = abs(fract(u / 1.2) - 0.5) * 1.2;   // triangle wave, 0..0.6
		float w = fwidth(t) + 1e-4;
		float bar = smoothstep(0.3 - w, 0.3 + w, t);
		bar *= band(a - 2.5, 1.45);
		return vec4(white, bar);
	}
	// Stop line, on the lane approaching the junction only (traffic keeps right).
	float stop = band(a - 4.65, 0.22) * step(0.3, abs(u)) * step(abs(u), edge)
			* step(0.0, sign(v) * sign(u));
	if (stop > 0.0) {
		return vec4(white, stop);
	}
	if (a < 4.0) {
		return vec4(0.0);
	}
	float centre = band(abs(u) - 0.18, 0.07) * step(4.9, a);
	if (centre > 0.0) {
		return vec4(yellow, centre);
	}
	return vec4(white, band(abs(u) - edge, 0.08));
}

vec3 asphalt(vec2 p, float u, out float rough) {
	float hw = road_width * 0.5;
	vec3 col = vec3(0.17, 0.175, 0.185) * (0.82 + 0.36 * fbm(p * 0.6));
	col *= 0.93 + 0.14 * vnoise(p * 28.0) * detail_fade(p, 28.0);
	// Oil darkens the middle of each lane; tyres polish the two tracks either side.
	float lane = abs(abs(u) - hw * 0.5);
	col *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.7, lane));
	col *= 1.0 + 0.06 * band(lane - 1.0, 0.35);
	// Patched repairs: the odd darker rectangle, fresher tar.
	vec2 cell = floor(p / vec2(7.0, 5.0));
	if (hash(cell) < 0.12) {
		vec2 f = fract(p / vec2(7.0, 5.0));
		float inside = step(0.15, f.x) * step(f.x, 0.75) * step(0.2, f.y) * step(f.y, 0.7);
		col = mix(col, col * 0.84, inside);
	}
	col = mix(col, vec3(0.05), cracks(p, 0.4) * 0.9);
	rough = 0.93;
	return col;
}

vec3 manhole(vec2 g, vec3 col) {
	// One cover per junction, off-centre in a lane.
	vec2 d = g - vec2(2.6, -2.4);
	float r = length(d);
	float disc = band(r, 0.6);
	vec3 iron = vec3(0.1, 0.1, 0.105);
	float grid = band(fract(d.x * 2.5) - 0.5, 0.1) + band(fract(d.y * 2.5) - 0.5, 0.1);
	iron *= 1.0 + 0.5 * clamp(grid, 0.0, 1.0) * step(r, 0.5);
	iron *= 1.0 - 0.6 * band(r - 0.56, 0.03);
	return mix(col, iron, disc);
}

// --- Sidewalk ----------------------------------------------------------------
vec3 concrete(vec2 lp, vec2 p, out float rough) {
	float slab = block_size / max(round(block_size / slab_target), 1.0);
	vec2 q = lp / slab;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float h = hash(id + 0.37);
	vec3 col = vec3(0.45, 0.45, 0.44) * (0.92 + 0.12 * h);
	col *= 0.9 + 0.2 * fbm(p * 0.9);
	col *= 0.9 + 0.2 * vnoise(p * 35.0) * detail_fade(p, 35.0);
	col *= 0.94 + 0.12 * vnoise(p * 8.0);
	// Joints between slabs.
	vec2 jd = min(f, 1.0 - f) * slab;
	float joint = max(band(jd.x, 0.012), band(jd.y, 0.012));
	col *= 1.0 - 0.5 * joint;
	// Some slabs have cracked right across, a few twice.
	vec2 c = f - 0.5;
	float crack = 0.0;
	if (h < 0.22) {
		float ang = hash(id + 1.7) * 3.1416;
		float d = dot(c, vec2(-sin(ang), cos(ang))) + (vnoise(c * 5.0 + id * 3.1) - 0.5) * 0.3;
		crack = band(d * slab, 0.012);
		if (h < 0.07) {
			float ang2 = ang + 1.2 + hash(id + 4.2);
			float d2 = dot(c - 0.1, vec2(-sin(ang2), cos(ang2))) + (vnoise(c * 7.0 + id) - 0.5) * 0.3;
			crack = max(crack, band(d2 * slab, 0.01) * step(0.0, dot(c, vec2(cos(ang2), sin(ang2)))));
		}
	}
	crack = max(crack, cracks(p, 0.25));
	col = mix(col, vec3(0.2, 0.2, 0.2), crack * 0.8);
	// Old stains: gum, drips, something spilled.
	float stain = smoothstep(0.8, 0.86, vnoise(p * 1.7 + 11.0));
	col *= 1.0 - 0.12 * stain;
	rough = 0.9;
	return col;
}

vec3 pavers(vec2 p, out float rough) {
	// Running-bond bricks with a ring of darker ones round the plaza.
	vec2 b = p / vec2(0.6, 0.3);
	b.x += 0.5 * mod(floor(b.y), 2.0);
	vec2 id = floor(b);
	vec2 f = fract(b);
	vec3 col = mix(vec3(0.62, 0.52, 0.44), vec3(0.5, 0.4, 0.34), hash(id));
	float r = length(p);
	col = mix(col, col * 0.7, band(r - (plaza_radius - 3.0), 0.6) + band(r - 9.0, 0.4));
	vec2 jd = min(f, 1.0 - f) * vec2(0.6, 0.3);
	col *= 1.0 - 0.4 * max(band(jd.x, 0.012), band(jd.y, 0.012)) * detail_fade(p, 6.0);
	col *= 0.9 + 0.2 * fbm(p * 0.5);
	rough = 0.85;
	return col;
}

vec3 grass(vec2 p, out float rough) {
	vec3 col = mix(vec3(0.24, 0.45, 0.2), vec3(0.36, 0.56, 0.26), fbm(p * 0.3));
	col *= 0.9 + 0.2 * vnoise(p * 9.0) * detail_fade(p, 9.0);
	col = mix(col, vec3(0.4, 0.34, 0.24), smoothstep(0.7, 0.8, vnoise(p * 0.6 + 5.0)) * 0.6);
	rough = 1.0;
	return col;
}

void fragment() {
	vec2 p = wpos.xz;
	float hw = road_width * 0.5;
	// Signed offsets from the nearest road centreline in each axis.
	vec2 g = p - round(p / pitch) * pitch;
	bool along_z = abs(g.x) <= hw;   // on a road running along Z
	bool along_x = abs(g.y) <= hw;
	float rough = 0.9;
	vec3 col;
	if (along_z || along_x) {
		float u = along_z ? g.x : g.y;
		float v = along_z ? g.y : g.x;
		col = asphalt(p, u, rough);
		if (along_z && along_x) {
			col = manhole(g, col);
		} else {
			vec4 paint = road_paint(u, v, p);
			// Worn paint: patchy, and missing where the road has cracked.
			paint.a *= 0.65 + 0.35 * fbm(p * 1.3 + 7.0);
			col = mix(col, paint.rgb, paint.a);
			rough = mix(rough, 0.7, paint.a);
		}
	} else if (length(p) < plaza_radius) {
		col = pavers(p, rough);
	} else {
		ivec2 bi = ivec2(floor(p / pitch));
		ivec2 texel = clamp(bi + block_offset, ivec2(0), textureSize(block_data, 0) - 1);
		bool park = texelFetch(block_data, texel, 0).r > 0.5;
		float edge = min(abs(g.x), abs(g.y)) - hw;   // distance in from the curb
		vec2 lp = p - (vec2(bi) * pitch + hw);       // 0..block_size inside this block
		if (park && edge > sidewalk_width) {
			col = grass(p, rough);
		} else {
			col = concrete(lp, p, rough);
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
