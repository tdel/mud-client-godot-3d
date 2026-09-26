// Voile gris posé sur tout ce qui est hors de la grille de la carte courante (voir
// Game3D._make_map_bounds_veil) : le décor déborde des bornes de la carte (sol, arbres de
// lisière...) alors que seul l'intérieur est cliquable/praticable — le voile rend la limite
// lisible. Quad plein écran rendu après l'opaque : la position monde de chaque pixel est
// reconstruite depuis la profondeur, donc un arbre posé hors carte est voilé en entier
// même s'il se projette par-dessus le sol intérieur.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

// Taille de la grille en tuiles (x, z monde), 0 = pas de carte chargée : voile coupé.
uniform vec2 map_size = vec2(0.0);
uniform vec3 veil_color : source_color = vec3(0.46, 0.47, 0.50);
// Part de couleur d'origine conservée hors carte (0 = gris pur).
uniform float saturation = 0.12;
uniform float darken = 0.62;
uniform float veil_amount = 0.3;
// Anticrénelage de la limite : fondu sur ~1.5 pixel, plafonné à edge_width tuile (les
// discontinuités de profondeur aux bords des objets gonflent fwidth).
uniform float edge_width = 0.1;
// Liseré sombre tracé juste à l'extérieur de la limite.
uniform float border_width = 0.12;
uniform float border_strength = 0.45;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 unproject(vec2 uv, float depth, mat4 inv_projection, mat4 inv_view) {
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	return (inv_view * vec4(view.xyz, 1.0)).xyz;
}

void fragment() {
	if (map_size.x <= 0.0 || map_size.y <= 0.0) {
		discard;
	}
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec3 world;
	if (depth <= 0.00001) {
		// Aucun décor (fond de ciel) : on prend le point du sol (y = 0) sous le pixel.
		vec3 near_point = unproject(SCREEN_UV, 1.0, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		vec3 far_point = unproject(SCREEN_UV, 0.0, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		vec3 ray = far_point - near_point;
		world = abs(ray.y) > 0.0001 ? near_point - ray * (near_point.y / ray.y) : far_point;
	} else {
		world = unproject(SCREEN_UV, depth, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	}

	// Distance (en tuiles) au rectangle [0, map_size] : <= 0 à l'intérieur.
	vec2 q = max(-world.xz, world.xz - map_size);
	float outside = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float aa = clamp(fwidth(outside) * 1.5, 0.0001, edge_width);
	if (outside <= 0.0) {
		discard;
	}

	vec3 color = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 veiled = mix(vec3(lum), color, saturation) * darken + veil_color * veil_amount * lum;
	veiled *= 1.0 - border_strength * (1.0 - smoothstep(0.0, border_width, outside));
	ALBEDO = veiled;
	ALPHA = smoothstep(0.0, aa, outside);
}
