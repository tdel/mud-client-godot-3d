shader_type spatial;
// Colonne de lumière / entonnoir (voir VfxLib.beam) : CylinderMesh de hauteur 1 sans bouchons,
// stries de bruit qui défilent le long de l'axe, bords plus lumineux (fresnel).
//   head/tail : fenêtre visible le long de la colonne (0 = base, 1 = sommet ; inversé si
//               downward = 1) — animer head puis tail fait "jaillir" puis "s'envoler" la colonne ;
//   twist     : torsion des stries (tornade).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float head : hint_range(0.0, 1.5) = 1.0;
uniform float tail : hint_range(0.0, 1.5) = 0.0;
uniform float downward : hint_range(0.0, 1.0) = 0.0;
uniform float scroll = 1.2;
uniform float twist = 0.0;
uniform float density = 8.0;
uniform float soft = 0.15;
uniform float top_fade = 0.3;

varying float v_h;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Bruit de valeur périodique en x (période `period`) pour ne pas avoir de couture autour du cylindre.
float noise_px(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(vec2(mod(i.x, period), i.y));
	float b = hash(vec2(mod(i.x + 1.0, period), i.y));
	float c = hash(vec2(mod(i.x, period), i.y + 1.0));
	float d = hash(vec2(mod(i.x + 1.0, period), i.y + 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	v_h = VERTEX.y + 0.5;
}

void fragment() {
	float h = v_h;
	float along = mix(h, 1.0 - h, downward);
	float win = smoothstep(tail, tail + soft, along) * (1.0 - smoothstep(head - soft, head, along));
	float dir = 1.0 - 2.0 * downward;
	float u = fract(UV.x + h * twist);
	float n1 = noise_px(vec2(u * density, h * 3.0 - TIME * scroll * dir), density);
	float n2 = noise_px(vec2(u * density * 2.0 + 3.0, h * 6.0 - TIME * scroll * 1.8 * dir), density * 2.0);
	float streak = pow(clamp(n1 * 0.6 + n2 * 0.4, 0.0, 1.0), 2.2) * 2.2;
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float ends = smoothstep(0.0, 0.06, h) * (1.0 - smoothstep(1.0 - top_fade, 1.0, h));
	float m = (0.07 + streak * 1.1) * (0.3 + rim * 0.9) * win * ends;
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(streak * 0.35, 0.0, 0.6));
	ALBEDO = col * energy;
	ALPHA = clamp(m, 0.0, 1.0) * alpha * tint.a;
}
