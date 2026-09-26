shader_type canvas_item;
// Fond de la carte du monde (voir WorldMapWindow.gd) : parchemin vieilli aux bords brûlés,
// puis le terrain à l'encre sépia façon carte de Tolkien — lavis + trait de contour, forêts
// en petits arbres, routes pavées cernées d'un double trait, chemins de terre en trait
// pointillé. Tout est calculé en pixels écran à partir de masques à une texel par case :
// les traits gardent la même épaisseur quelle que soit la taille de la fenêtre.

// R pavés, G chemins de terre, B forêt, A bâti (remparts, auberge, forge...).
uniform sampler2D mask_a : filter_linear, repeat_disable;
// R eau, G roche/éboulis.
uniform sampler2D mask_b : filter_linear, repeat_disable;
uniform vec2 canvas_size = vec2(720.0, 460.0);
// Rectangle (px) occupé par la carte dans le parchemin : x, y, largeur, hauteur.
uniform vec4 map_rect = vec4(20.0, 40.0, 680.0, 400.0);
uniform vec2 map_tiles = vec2(100.0, 60.0);
uniform float px_per_tile = 6.0;
// Pas (en cases) de la grille des petits arbres de forêt.
uniform float tree_cell = 2.0;

const vec3 INK = vec3(0.24, 0.15, 0.08);
const vec3 PAPER_LIGHT = vec3(0.93, 0.86, 0.69);
const vec3 PAPER_DARK = vec3(0.80, 0.69, 0.49);
const float THRESHOLD = 0.42;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.7));
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Trait d'épaisseur `width` px centré sur la distance signée `d` (px).
float stroke(float d, float width) {
	return 1.0 - smoothstep(width * 0.5 - 0.6, width * 0.5 + 0.6, abs(d));
}

float fill(float d) {
	return clamp(d + 0.5, 0.0, 1.0);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Échantillon adouci (4 prises décalées d'un tiers de case) : arrondit les escaliers case par case.
vec4 soft_sample(sampler2D tex, vec2 uv, vec2 texel) {
	vec2 o = texel * 0.35;
	return (texture(tex, uv + vec2(o.x, o.y)) + texture(tex, uv + vec2(-o.x, o.y))
			+ texture(tex, uv + vec2(o.x, -o.y)) + texture(tex, uv + vec2(-o.x, -o.y))) * 0.25;
}

void fragment() {
	vec2 px = UV * canvas_size;

	// --- Parchemin ---------------------------------------------------------
	float grain = fbm(px / 85.0);
	vec3 col = mix(PAPER_LIGHT, PAPER_DARK, grain * 0.85);
	col *= 0.965 + 0.07 * value_noise(px / 2.5) * fbm(px / 14.0 + 3.0);
	float stain = smoothstep(0.58, 0.78, fbm(px / 150.0 + vec2(3.1, 7.4)));
	col = mix(col, col * vec3(0.86, 0.76, 0.60), stain * 0.55);
	// Bords brûlés : liseré brun sombre irrégulier, puis dégradé vers l'intérieur.
	float edge = min(min(px.x, px.y), min(canvas_size.x - px.x, canvas_size.y - px.y));
	float e = edge - fbm(px / 22.0) * 10.0;
	col = mix(col * vec3(0.78, 0.66, 0.50), col, smoothstep(0.0, 34.0, e));
	col = mix(vec3(0.30, 0.18, 0.08), col, smoothstep(-1.5, 3.5, e));
	vec3 paper = col;

	// --- Terrain -----------------------------------------------------------
	vec2 t = (px - map_rect.xy) / map_rect.zw * map_tiles;
	if (t.x >= 0.0 && t.y >= 0.0 && t.x <= map_tiles.x && t.y <= map_tiles.y) {
		vec2 texel = 1.0 / map_tiles;
		vec2 uv = t * texel;
		vec4 a = soft_sample(mask_a, uv, texel);
		vec4 b = soft_sample(mask_b, uv, texel);
		// Distance signée approchée (px) au contour de chaque masque, positive à l'intérieur.
		vec4 da = (a - THRESHOLD) / max(fwidth(a), vec4(1e-4));
		vec2 db = (b.rg - THRESHOLD) / max(fwidth(b.rg), vec2(1e-4));
		float ink_var = 0.8 + 0.2 * value_noise(px / 3.0);

		// Eau : lavis bleu-gris, contour et trait d'écho intérieur.
		col = mix(col, mix(paper, vec3(0.55, 0.67, 0.72), 0.75), fill(db.x));
		col = mix(col, INK, stroke(db.x, 1.2) * 0.9);
		col = mix(col, INK, stroke(db.x - 3.5, 0.7) * 0.4 * step(0.0, db.x));

		// Forêt : lavis léger puis petits arbres qui se chevauchent (rangée du bas devant).
		float forest = fill(da.b);
		col = mix(col, mix(paper, vec3(0.70, 0.68, 0.46), 0.45), forest);
		vec2 gc = t / tree_cell;
		vec2 base = floor(gc);
		float cell_px = tree_cell * px_per_tile;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 cell = base + vec2(float(i), float(j));
				vec2 rnd = hash2(cell);
				vec2 center = cell + 0.5 + (rnd - 0.5) * 0.5;
				vec2 center_uv = center * tree_cell * texel;
				vec4 at = textureLod(mask_a, center_uv, 0.0);
				if (at.b < 0.6 || at.r > 0.3 || at.g > 0.3 || at.a > 0.3
						|| textureLod(mask_b, center_uv, 0.0).r > 0.3 || center_uv.x > 1.0 || center_uv.y > 1.0) {
					continue;
				}
				vec2 q = (gc - center) * cell_px;
				float radius = (0.34 + 0.1 * rnd.y) * cell_px;
				vec2 crown_center = vec2(0.0, -0.1 * cell_px);
				float d = length(q - crown_center) - radius;
				vec2 rel = (q - crown_center) / radius;
				vec3 crown = mix(vec3(0.74, 0.70, 0.47), vec3(0.55, 0.52, 0.33),
						smoothstep(-0.2, 0.8, dot(rel, vec2(0.6, 0.8))));
				float trunk = seg_dist(q, crown_center + vec2(0.0, radius * 0.6),
						crown_center + vec2(0.0, radius + 0.16 * cell_px)) - 0.55;
				col = mix(col, INK, clamp(0.5 - trunk, 0.0, 1.0) * 0.85);
				col = mix(col, crown, clamp(0.5 - d, 0.0, 1.0));
				col = mix(col, INK, stroke(d, 1.0) * 0.85 * ink_var);
			}
		}
		col = mix(col, INK, stroke(da.b, 1.0) * 0.55);

		// Roche/éboulis : hachures serrées.
		float hatch_rock = step(0.55, fract((px.x - px.y) / 3.0));
		col = mix(col, mix(paper, vec3(0.50, 0.44, 0.36), 0.35 + 0.35 * hatch_rock), fill(db.y));
		col = mix(col, INK, stroke(db.y, 1.2) * 0.9);

		// Chemins de terre : lavis clair, contour fin et interrompu (trait pointillé).
		col = mix(col, mix(paper, vec3(0.86, 0.77, 0.58), 0.8), fill(da.g));
		float dash = step(0.42, value_noise(px / 3.2));
		col = mix(col, INK, stroke(da.g, 1.0) * 0.6 * dash);

		// Routes pavées : chaussée claire semée de petits pavés, double trait d'encre net.
		float cobble = smoothstep(0.72, 0.8, value_noise(px / 2.2));
		vec3 road = mix(paper, vec3(0.95, 0.89, 0.74), 0.7);
		road = mix(road, INK, cobble * 0.22 * smoothstep(3.0, 6.0, px_per_tile));
		col = mix(col, road, fill(da.r));
		col = mix(col, INK, stroke(da.r, 1.5) * ink_var);

		// Bâti : aplat hachuré sombre cerné d'encre.
		float hatch = step(0.5, fract((px.x + px.y) / 4.0));
		col = mix(col, mix(vec3(0.52, 0.39, 0.25), vec3(0.36, 0.25, 0.15), hatch), fill(da.a));
		col = mix(col, INK, stroke(da.a, 1.3));
	}

	// Vignettage général.
	vec2 centered = UV - 0.5;
	col *= 1.0 - dot(centered, centered) * 0.35;
	COLOR = vec4(col, 1.0);
}
