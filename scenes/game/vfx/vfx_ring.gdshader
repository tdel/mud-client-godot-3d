shader_type spatial;
// Anneau lumineux au sol (onde de choc, ondulation, lueur) sur un PlaneMesh : profil gaussien
// autour de `radius` (0..1 du demi-côté), disque intérieur optionnel (`fill`), léger tremblé
// (`wobble`) pour les ondes moins géométriques.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float radius : hint_range(0.0, 1.0) = 0.6;
uniform float width = 0.06;
uniform float fill = 0.0;
uniform float wobble = 0.0;

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

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	float wob = (vnoise(dir * 3.0 + vec2(TIME * 1.7, -TIME)) - 0.5) * wobble;
	float d = (r + wob - radius) / max(width, 0.0001);
	float ring = exp(-d * d * 2.0);
	float disc = fill * (1.0 - smoothstep(0.0, max(radius, 0.001), r));
	float edge = 1.0 - smoothstep(0.92, 1.0, r);
	float m = (ring + disc) * edge;
	ALBEDO = mix(tint.rgb, vec3(1.0), ring * 0.3) * energy;
	ALPHA = clamp(m, 0.0, 1.0) * alpha * tint.a;
}
