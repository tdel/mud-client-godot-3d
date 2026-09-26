shader_type spatial;
// Sphère d'énergie (explosion, éclaboussure, orbe d'eau) : cœur `core_tint` qui vire à `tint`
// vers les bords (fresnel), turbulence fbm animée, dissolution par le bruit (`dissolve` 0..1.2).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform vec4 core_tint : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float energy = 2.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float noise_scale = 3.0;
uniform float noise_speed = 1.0;
uniform float dissolve : hint_range(0.0, 1.2) = 0.0;
uniform float rim_power = 1.5;
uniform float core_amount = 0.8;

varying vec3 v_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float fbm(vec3 p) {
	return noise3(p) * 0.55 + noise3(p * 2.1 + 7.0) * 0.3 + noise3(p * 4.3 + 13.0) * 0.15;
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float fres = 1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float n = fbm(v_pos * noise_scale + vec3(0.0, -TIME * noise_speed, TIME * noise_speed * 0.5));
	vec3 col = mix(core_tint.rgb, tint.rgb, clamp(fres * 1.3 + (1.0 - n) * 0.35, 0.0, 1.0));
	float m = pow(fres, rim_power) + (1.0 - fres) * core_amount * (0.4 + n);
	m *= smoothstep(dissolve - 0.2, dissolve, n);
	ALBEDO = col * energy;
	ALPHA = clamp(m, 0.0, 1.0) * alpha * tint.a;
}
