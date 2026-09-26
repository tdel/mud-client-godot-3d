// Eau de la fontaine : surfaces calmes ridées (normales de bruit défilant dans deux sens,
// reflet spéculaire, bord plus clair par effet Fresnel) ou rideau d'eau qui tombe (stries
// défilant le long de UV.y, mousse blanche en bas). Transparente.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.08, 0.26, 0.34);
uniform vec3 shallow_color : source_color = vec3(0.30, 0.58, 0.62);
uniform float opacity = 0.78;
uniform float ripple_scale = 3.0;
uniform float ripple_speed = 0.35;
uniform bool falling = false;
uniform float fall_speed = 1.6;
// Luminosité de la lueur émise la nuit (pilotée par Fountain.gd selon le cycle jour/nuit).
uniform float night_glow = 0.0;
uniform vec3 glow_color : source_color = vec3(0.35, 0.7, 1.0);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float ripples(vec2 p) {
	return noise(p * ripple_scale + vec2(TIME * ripple_speed, TIME * ripple_speed * 0.6)) * 0.5
			+ noise(p * ripple_scale * 1.9 - vec2(TIME * ripple_speed * 0.8, -TIME * ripple_speed)) * 0.5;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (falling) {
		float streak = noise(vec2(UV.x * 18.0, UV.y * 2.5 - TIME * fall_speed * 2.0));
		streak = smoothstep(0.35, 0.9, streak);
		float foam = smoothstep(0.75, 1.0, UV.y);
		ALBEDO = mix(shallow_color * 1.4, vec3(0.9, 0.95, 1.0), streak * 0.6 + foam * 0.5);
		ALPHA = clamp(0.18 + streak * 0.45 + foam * 0.35, 0.0, 0.85);
		ROUGHNESS = 0.15;
		SPECULAR = 0.6;
		EMISSION = glow_color * night_glow * 0.3;
	} else {
		vec2 p = world_pos.xz;
		float e = 0.08;
		float h = ripples(p);
		float hx = ripples(p + vec2(e, 0.0));
		float hz = ripples(p + vec2(0.0, e));
		vec3 n = normalize(vec3((h - hx) * 1.2, 1.0, (h - hz) * 1.2));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		ALBEDO = mix(deep_color, shallow_color, 0.35 + h * 0.3);
		ALPHA = clamp(opacity + fresnel * 0.2, 0.0, 0.95);
		ROUGHNESS = 0.04;
		METALLIC = 0.0;
		SPECULAR = 0.7;
		EMISSION = glow_color * night_glow * (0.25 + h * 0.2);
	}
}
