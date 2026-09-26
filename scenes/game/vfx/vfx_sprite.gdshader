shader_type spatial;
// Sprite lumineux additif toujours face caméra : lueur ronde (shape 0) ou étincelle en croix
// (shape 1), cœur blanchi (`core_white`). `particles` = true pour un draw pass de GPUParticles3D
// (rotation par particule, couleur/alpha pilotés par le color_ramp via COLOR).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.5;
uniform float core_white = 0.5;
uniform int shape = 0;
uniform bool particles = false;
uniform float softness = 3.5;

void vertex() {
	if (particles) {
		mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		mat_world = mat_world * mat4(
			vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float m;
	if (shape == 1) {
		float rays = max(
			exp(-abs(p.x) * 16.0) * max(1.0 - abs(p.y), 0.0),
			exp(-abs(p.y) * 16.0) * max(1.0 - abs(p.x), 0.0));
		m = rays + exp(-r * r * 10.0);
	} else {
		m = exp(-r * r * softness);
	}
	m *= 1.0 - smoothstep(0.85, 1.0, r);
	vec3 base = tint.rgb * COLOR.rgb;
	vec3 col = mix(base, vec3(1.0), clamp(exp(-r * r * 14.0) * core_white, 0.0, 1.0));
	ALBEDO = col * energy;
	ALPHA = clamp(m, 0.0, 1.0) * tint.a * COLOR.a;
}
