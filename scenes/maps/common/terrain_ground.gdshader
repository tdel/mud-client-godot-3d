// Sol d'une carte décorée (voir TerrainGround.gd) : mélange de 5 matériaux PBR ambientCG
// piloté par une "splat map" à une texel par case, construite depuis le GridMap Terrain :
//   R = sol forestier, G = chemin de terre, B = pavés, A = herbe sombre (sous-bois clair),
//   reste (1 - somme) = herbe.
// Les frontières entre cases sont cassées par un décalage de bruit de la lecture de la splat
// (bords organiques plutôt qu'en escalier) et un mélange par hauteur (les pavés dépassent de
// l'herbe entre leurs joints, la terre s'infiltre entre les brins). Chaque texture est lue à
// deux échelles/rotations mêlées par un bruit basse fréquence pour masquer la répétition.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(64.0, 64.0);

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paved_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paved_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paved_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;

// Mètres couverts par une répétition de chaque texture.
uniform float grass_tile = 3.0;
uniform float forest_tile = 4.0;
uniform float dirt_tile = 3.0;
uniform vec2 paved_tile = vec2(1.6, 3.2);
uniform vec3 grass_tint : source_color = vec3(0.7, 0.76, 0.62);
uniform vec3 dark_grass_tint : source_color = vec3(0.5, 0.58, 0.45);
uniform vec3 forest_tint : source_color = vec3(0.78, 0.76, 0.7);
uniform vec3 dirt_tint : source_color = vec3(0.82, 0.74, 0.66);
uniform vec3 paved_tint : source_color = vec3(0.66, 0.66, 0.68);
// Désaturation des pavés (la texture d'origine tire sur le jaune).
uniform float paved_desaturate : hint_range(0.0, 1.0) = 0.55;
// Amplitude (cases) du décalage de bruit appliqué à la lecture de la splat.
uniform float edge_warp = 0.85;
uniform float blend_sharpness = 6.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

vec2 rotate(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Couleur anti-répétition : deux lectures (échelle/rotation différentes) mêlées par `mask`.
vec3 untiled(sampler2D tex, vec2 uv, float mask) {
	vec3 a = texture(tex, uv).rgb;
	vec3 b = texture(tex, rotate(uv, 1.37) * 0.71 + vec2(0.31, 0.57)).rgb;
	return mix(a, b, mask);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 warp = vec2(fbm(p * 0.45), fbm(p * 0.45 + vec2(31.7, 12.3))) - 0.5;
	vec4 s = texture(splat_map, (p + warp * edge_warp * 2.0) / map_size);
	float w_grass = max(0.0, 1.0 - s.r - s.g - s.b - s.a);
	float macro = fbm(p * 0.06);
	float mask = smoothstep(0.35, 0.65, fbm(p * 0.13 + vec2(5.0)));

	vec2 uv_g = p / grass_tile;
	vec2 uv_f = p / forest_tile;
	vec2 uv_d = p / dirt_tile;
	vec2 uv_p = p / paved_tile;

	vec3 c_grass = untiled(grass_albedo, uv_g, mask) * grass_tint;
	vec3 c_dark = c_grass * dark_grass_tint / grass_tint;
	vec3 c_forest = untiled(forest_albedo, uv_f, mask) * forest_tint;
	vec3 c_dirt = untiled(dirt_albedo, uv_d, mask) * dirt_tint;
	vec3 c_paved = texture(paved_albedo, uv_p).rgb;
	c_paved = mix(c_paved, vec3(dot(c_paved, vec3(0.3, 0.59, 0.11))), paved_desaturate) * paved_tint;

	// Mélange par hauteur : chaque matériau a une "hauteur" propre (luminance des pavés =
	// pierres au-dessus des joints, bruit pour les autres) ajoutée à son poids.
	float h_grass = fbm(p * 1.7) * 0.5;
	float h_forest = fbm(p * 1.3 + 3.0) * 0.5;
	float h_dirt = fbm(p * 2.1 + 7.0) * 0.35;
	float h_paved = dot(c_paved, vec3(0.33)) * 0.9;
	vec4 wh = vec4(s.r + h_forest, s.g + h_dirt, s.b + h_paved, s.a + h_grass);
	float wh_grass = w_grass + h_grass;
	float top = max(max(max(wh.x, wh.y), max(wh.z, wh.w)), wh_grass);
	vec4 b = max(wh - top + 1.0 / blend_sharpness, 0.0) * vec4(step(0.001, s.r), step(0.001, s.g), step(0.001, s.b), step(0.001, s.a));
	float b_grass = max(wh_grass - top + 1.0 / blend_sharpness, 0.0) * step(0.001, w_grass);
	float total = b.x + b.y + b.z + b.w + b_grass + 1e-5;
	b /= total;
	b_grass /= total;

	vec3 albedo = c_forest * b.x + c_dirt * b.y + c_paved * b.z + c_dark * b.w + c_grass * b_grass;
	albedo *= mix(0.88, 1.08, macro);

	vec3 n_grass = texture(grass_normal, uv_g).rgb;
	vec3 n = texture(forest_normal, uv_f).rgb * b.x + texture(dirt_normal, uv_d).rgb * b.y
			+ texture(paved_normal, uv_p).rgb * b.z + n_grass * (b.w + b_grass);
	float r = texture(forest_rough, uv_f).g * b.x + texture(dirt_rough, uv_d).g * b.y
			+ texture(paved_rough, uv_p).g * b.z + texture(grass_rough, uv_g).g * (b.w + b_grass);

	ALBEDO = albedo;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = clamp(r, 0.4, 1.0);
	SPECULAR = 0.3;
}
