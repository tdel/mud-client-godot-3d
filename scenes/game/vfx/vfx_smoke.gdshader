shader_type spatial;
// Bouffée de fumée (mélange alpha, pas additif) pour draw pass de GPUParticles3D : tache
// bruitée face caméra, couleur/alpha pilotés par le color_ramp via COLOR.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);

varying float v_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9, 78.2, 37.7))) * 43758.5);
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(
		vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float n = vnoise(p * 2.5 + vec2(v_seed * 17.0, TIME * 0.4)) * 0.6 + vnoise(p * 5.0 + v_seed * 31.0) * 0.4;
	float m = 1.0 - smoothstep(0.25, 1.0, length(p) + (n - 0.5) * 0.6);
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = clamp(m, 0.0, 1.0) * tint.a * COLOR.a;
}
