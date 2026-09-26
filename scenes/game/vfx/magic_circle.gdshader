shader_type spatial;
// Cercle d'incantation procédural (voir CastCircle.gd) : double anneau extérieur, couronne de
// runes générées par hachage, cercle intérieur, pentagramme tracé d'un seul trait avec médaillons
// aux pointes. Posé à plat sur un PlaneMesh (UV 0..1), rendu additif.
//   reveal : tracé progressif (anneaux d'abord, puis runes, puis pentagramme) — intro du cast ;
//   charge : progression de l'incantation, remplit l'anneau extérieur avec une tête de comète ;
//   crack  : brisure par fragments (interruption) ; flash : surbrillance ponctuelle ;
//   show_star = 0 : couronne de runes seule (anneau flottant qui monte pendant le cast).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float energy = 2.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 0.0;
uniform float star_spin = 0.0;
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform float flash = 0.0;
uniform float show_star : hint_range(0.0, 1.0) = 1.0;

const float RUNE_COUNT = 44.0;
const float STAR_RADIUS = 0.6;

float hash11(float n) {
	return fract(sin(n * 127.1 + 11.7) * 43758.5453);
}

float seg_t(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

float seg(vec2 p, vec2 a, vec2 b) {
	float t;
	return seg_t(p, a, b, t);
}

// Angle normalisé 0..1, 0 en haut du disque, sens horaire.
float angle01(vec2 p) {
	return fract(atan(p.x, p.y) / TAU + 1.0);
}

// Pseudo-rune dans une cellule q ∈ [0,1]² : combinaison de traits tirés au hasard.
float glyph(vec2 q, float seed) {
	float d = 10.0;
	float h1 = hash11(seed);
	float h2 = hash11(seed + 1.3);
	float h3 = hash11(seed + 2.7);
	float h4 = hash11(seed + 4.1);
	if (h1 > 0.2) {
		d = min(d, seg(q, vec2(0.5, 0.14), vec2(0.5, 0.86)));
	}
	if (h2 > 0.5) {
		d = min(d, seg(q, vec2(0.2, 0.8), vec2(0.8, 0.8)));
	} else {
		d = min(d, seg(q, vec2(0.2, 0.5), vec2(0.5, 0.86)));
	}
	if (h3 > 0.66) {
		d = min(d, seg(q, vec2(0.2, 0.22), vec2(0.8, 0.56)));
	} else if (h3 > 0.33) {
		d = min(d, seg(q, vec2(0.2, 0.56), vec2(0.8, 0.22)));
	} else {
		d = min(d, abs(length(q - vec2(0.5, 0.45)) - 0.2));
	}
	if (h4 > 0.55) {
		d = min(d, seg(q, vec2(0.26, 0.14), vec2(0.74, 0.14)));
	}
	return d;
}

float stroke(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float aa = max(fwidth(r), 0.0005) * 1.2;
	float a = angle01(p);

	float ring_rev = clamp(reveal * 1.8, 0.0, 1.0);
	float rune_rev = clamp(reveal * 1.8 - 0.25, 0.0, 1.0);
	float inner_rev = clamp(reveal * 1.8 - 0.4, 0.0, 1.0);
	float star_rev = clamp((reveal - 0.4) / 0.6, 0.0, 1.0);

	float lines = 0.0;
	float dmin = 10.0;

	// Anneaux extérieurs (tracés en balayage angulaire).
	float ring_vis = step(a, ring_rev);
	float d_outer = abs(r - 0.95);
	float d_outer2 = abs(r - 0.8);
	lines = max(lines, stroke(d_outer, 0.014, aa) * ring_vis);
	lines = max(lines, stroke(d_outer2, 0.008, aa) * ring_vis);
	dmin = min(dmin, min(d_outer, d_outer2) + (1.0 - ring_vis) * 10.0);

	// Couronne de runes (tourne avec `spin`).
	float band = (r - 0.82) / 0.11;
	if (band > 0.0 && band < 1.0) {
		float ar = fract(atan(p.x, p.y) / TAU + spin / TAU + 1.0);
		float cell = floor(ar * RUNE_COUNT);
		vec2 q = vec2(fract(ar * RUNE_COUNT), band);
		float gd = glyph(q, cell) * 0.11;
		lines = max(lines, stroke(gd, 0.0065, aa) * step(a, rune_rev) * 0.85);
	}

	// Cercle intérieur et petit cercle central.
	float in_vis = step(a, inner_rev) * show_star;
	float d_in = abs(r - STAR_RADIUS);
	float d_c = abs(r - 0.15);
	lines = max(lines, stroke(d_in, 0.01, aa) * in_vis);
	lines = max(lines, stroke(d_c, 0.007, aa) * in_vis);
	dmin = min(dmin, min(d_in, d_c) + (1.0 - in_vis) * 10.0);

	// Pentagramme tracé d'un seul trait (sommets 0 -> 2 -> 4 -> 1 -> 3 -> 0).
	if (show_star > 0.5) {
		for (int k = 0; k < 5; k++) {
			float fk = float(k);
			float a0 = star_spin + PI * 0.5 + fk * 2.0 * TAU / 5.0;
			float a1 = a0 + 2.0 * TAU / 5.0;
			vec2 v0 = STAR_RADIUS * vec2(cos(a0), sin(a0));
			vec2 v1 = STAR_RADIUS * vec2(cos(a1), sin(a1));
			float t;
			float d = seg_t(p, v0, v1, t);
			float shown = clamp(star_rev * 5.0 - fk, 0.0, 1.0);
			float vis = step(t, shown) * step(0.001, shown);
			lines = max(lines, stroke(d, 0.011, aa) * vis);
			dmin = min(dmin, d + (1.0 - vis) * 10.0);
			float am = star_spin + PI * 0.5 + fk * TAU / 5.0;
			vec2 vm = STAR_RADIUS * vec2(cos(am), sin(am));
			float d_med = abs(length(p - vm) - 0.065);
			float med_vis = step(fk + 0.5, star_rev * 5.0);
			lines = max(lines, stroke(d_med, 0.007, aa) * med_vis);
		}
	}

	// Remplissage de l'anneau extérieur selon la progression du cast + tête de comète.
	float charged = step(a, charge) * ring_vis;
	float charge_glow = exp(-d_outer * 40.0) * charged;
	float head_da = abs(a - charge);
	head_da = min(head_da, 1.0 - head_da);
	float head = exp(-head_da * 70.0) * exp(-d_outer * 25.0) * step(0.001, charge) * step(charge, 0.999);

	float halo = exp(-dmin * 26.0) * 0.4;
	float fill = (1.0 - smoothstep(0.0, 1.0, r)) * 0.07 * show_star * (0.6 + charge);
	float m = lines + halo + charge_glow * 0.8 + head * 1.6 + fill;

	// Brisure : fragments (secteur angulaire x bande radiale) qui s'éteignent un à un.
	float shard = hash11(floor(a * 16.0) * 7.0 + floor(r * 6.0) * 31.0);
	m *= step(crack, shard);

	float core = clamp(lines + head, 0.0, 1.0);
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(core * 0.12 + head * 0.45, 0.0, 1.0));
	col *= 1.0 + charge_glow * 0.8;
	ALBEDO = col * energy * (1.0 + flash);
	ALPHA = clamp(m, 0.0, 1.0) * alpha * tint.a;
}
