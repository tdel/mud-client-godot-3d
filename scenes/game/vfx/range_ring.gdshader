shader_type spatial;
// Cercle de portée des skills (voir Game3D.show_skill_range) : seul le périmètre est dessiné,
// l'intérieur reste vide. Bande ornementale d'épaisseur constante en mètres quel que soit le
// rayon : filet extérieur épais doublé d'un filet fin, frise de runes qui défile lentement,
// filet intérieur, losanges sertis aux points cardinaux (plus petits aux diagonales) et deux
// reflets qui parcourent l'anneau. Posé à plat sur un PlaneMesh (UV 0..1), rendu additif.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float energy = 1.4;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// Rayon du filet extérieur et demi-côté du plan porteur, en mètres.
uniform float radius = 5.0;
uniform float half_size = 5.5;

// Géométrie de la bande (mètres, mesurés depuis le bord extérieur vers le centre).
const float BAND = 0.4;
const float LINE2_D = 0.07;
const float RUNE_D0 = 0.11;
const float RUNE_D1 = 0.33;
const float INNER_D = 0.38;
const float RUNE_CELL = 0.26;
// Vitesse de défilement de la frise (m/s le long du cercle) et des reflets (rad/s).
const float SCROLL_SPEED = 0.12;
const float SWEEP_SPEED = 0.45;

float hash11(float n) {
	return fract(sin(n * 127.1 + 11.7) * 43758.5453);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

// Pseudo-rune dans une cellule q ∈ [0,1]² (même famille de glyphes que magic_circle).
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

// Contour d'un losange de demi-diagonales (a tangentielle, b radiale), distance approchée.
float diamond(vec2 q, float a, float b) {
	float k = abs(q.x) / a + abs(q.y) / b - 1.0;
	return abs(k) * min(a, b) * 0.7;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * half_size;
	float r = length(p);
	// Petites portées : la bande rétrécit pour ne pas envahir le centre.
	float sc = clamp(radius / 2.5, 0.35, 1.0);
	float d = (radius - r) / sc;
	if (d < -0.12 || d > BAND + 0.12) {
		discard;
	}
	float aa = max(fwidth(d), 0.0005) * 1.2;
	float ang = atan(p.x, p.y);
	float circ = TAU * radius;

	float lines = 0.0;
	float dmin = 10.0;

	// Filets : extérieur épais, second filet fin juste dedans, filet intérieur.
	float d_out = abs(d);
	float d_l2 = abs(d - LINE2_D);
	float d_in = abs(d - INNER_D);
	lines = max(lines, stroke(d_out, 0.022, aa));
	lines = max(lines, stroke(d_l2, 0.007, aa) * 0.8);
	lines = max(lines, stroke(d_in, 0.011, aa));
	dmin = min(dmin, min(d_out, d_in));

	// Position le long du cercle (mètres) avec défilement lent de la frise et des sertis.
	float scroll = TIME * SCROLL_SPEED;
	float arc = fract((ang / TAU) + scroll / circ + 1.0) * circ;

	// Sertis : 8 losanges, les 4 cardinaux plus grands ; la frise s'interrompt autour.
	float slot = circ / 8.0;
	float idx = floor(arc / slot + 0.5);
	float s = (arc - idx * slot) * (1.0 / sc);
	float major = 1.0 - mod(idx, 2.0);
	float mid = (RUNE_D0 + RUNE_D1) * 0.5;
	vec2 q = vec2(s, d - mid);
	float ha = mix(0.17, 0.26, major);
	float hb = mix(0.13, 0.2, major);
	float gem = 0.0;
	gem = max(gem, stroke(diamond(q, ha, hb), 0.012, aa));
	gem = max(gem, stroke(diamond(q, ha * 0.5, hb * 0.5), 0.008, aa) * 0.9);
	gem = max(gem, stroke(length(q), 0.02 + 0.01 * major, aa));
	lines = max(lines, gem);
	dmin = min(dmin, diamond(q, ha, hb));
	float gap = smoothstep(ha + 0.02, ha + 0.1, abs(s));

	// Frise de runes entre le second filet et le filet intérieur.
	float runes = 0.0;
	float band = (d - RUNE_D0) / (RUNE_D1 - RUNE_D0);
	if (band > 0.0 && band < 1.0) {
		float count = max(floor(circ / (RUNE_CELL * sc)), 8.0);
		float u = arc / circ * count;
		float cell = floor(u);
		float gd = glyph(vec2(fract(u), 1.0 - band), cell) * (RUNE_D1 - RUNE_D0);
		float twinkle = 0.6 + 0.4 * sin(TIME * 1.3 + hash11(cell + 9.1) * TAU);
		runes = stroke(gd, 0.009, aa) * twinkle * gap;
		lines = max(lines, runes * 0.85);
	}

	// Deux reflets qui font le tour de l'anneau (largeur constante en mètres).
	float sweep_a = fract((ang - TIME * SWEEP_SPEED) / TAU + 1.0);
	float sweep_da = min(sweep_a, 1.0 - sweep_a);
	sweep_da = min(sweep_da, abs(sweep_a - 0.5));
	float sweep = exp(-pow(sweep_da * circ / 1.6, 2.0));

	float halo = exp(-max(dmin, 0.0) * 22.0) * 0.35;
	float m = lines * (0.85 + 0.6 * sweep) + halo * (1.0 + sweep);
	// Estompe les bords de la bande (le halo ne déborde pas vers l'intérieur).
	m *= 1.0 - smoothstep(0.0, 0.1, -d);
	m *= 1.0 - smoothstep(INNER_D, INNER_D + 0.1, d);

	vec3 col = mix(tint.rgb, vec3(1.0), clamp(lines * 0.15 + gem * 0.2 + sweep * lines * 0.35, 0.0, 1.0));
	ALBEDO = col * energy;
	ALPHA = clamp(m, 0.0, 1.0) * alpha * tint.a;
}
