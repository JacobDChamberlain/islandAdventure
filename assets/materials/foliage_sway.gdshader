shader_type spatial;
// Wind for the MultiMesh foliage.
//
// There are thousands of trees, bushes and grass tufts drawn as MultiMesh
// instances, so none of them can be animated individually — but a vertex shader
// moves every one of them for free, and the shadow pass runs the same code so
// the shadows sway too.
//
// Two details that make it read as wind rather than wobble:
//  - the offset is masked by height SQUARED, so trunks stay planted in the
//    ground and only the canopy moves;
//  - the phase comes from each instance's world position, so neighbouring trees
//    are out of step instead of the whole forest swaying as one object.

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool use_texture = false;
uniform float sway_strength = 0.07;   // metres of travel at full height
uniform float sway_speed = 1.1;
uniform float sway_height = 2.5;      // local Y at which the sway is full
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

void vertex() {
	// MODEL_MATRIX's translation is this INSTANCE's world position, which is
	// what de-synchronises the trees from each other.
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.35 + origin.z * 0.27;
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	h *= h;
	float t = TIME * sway_speed + phase;
	// Two frequencies so it doesn't read as a metronome.
	VERTEX.x += (sin(t) + 0.35 * sin(t * 1.7)) * sway_strength * h;
	VERTEX.z += cos(t * 0.9) * sway_strength * 0.6 * h;
}

void fragment() {
	vec4 c = albedo_color;
	if (use_texture) {
		c *= texture(albedo_tex, UV);
	}
	ALBEDO = c.rgb * COLOR.rgb;
	ROUGHNESS = roughness_value;
}
