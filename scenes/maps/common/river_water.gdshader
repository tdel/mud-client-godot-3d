// Eau d'une rivière (surface plane à TerrainGround.water_level, posée sur tout un bloc de
// sol : le sol la cache hors du lit). Couleur et opacité selon l'épaisseur d'eau traversée
// (lue dans le tampon de profondeur) : claire et transparente contre les berges, sombre au
// milieu ; liseré d'écume là où l'eau touche une berge, une pile de pont ou un rocher. Rides
// de bruit défilant dans le sens du courant (flow), reflet spéculaire, Fresnel.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 deep_color : source_color = vec3(0.05, 0.15, 0.17);
uniform vec3 shallow_color : source_color = vec3(0.24, 0.38, 0.34);
uniform vec3 foam_color : source_color = vec3(0.82, 0.88, 0.86);
// Courant (m/s, repère carte : +Y = sud).
uniform vec2 flow = vec2(0.05, 0.45);
uniform float ripple_scale = 2.2;
// Épaisseur d'eau (m, le long du regard) pour atteindre la couleur profonde.
uniform float depth_fade = 2.2;
uniform float foam_width = 0.35;

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

// Rides étirées dans le sens du courant (stries de courant plutôt que taches rondes).
float ripples(vec2 p) {
	vec2 dir = normalize(flow);
	vec2 q = vec2(dot(p, vec2(dir.y, -dir.x)), dot(p, dir) * 0.3) * ripple_scale;
	float v = length(flow) * TIME * ripple_scale * 0.3;
	return noise(q - vec2(0.0, v)) * 0.55
			+ noise(q * 2.3 + vec2(7.3, 1.9) - vec2(0.0, v * 2.0)) * 0.3
			+ noise(q * 5.1 + vec2(2.1, 9.4) - vec2(v * 0.3, v * 3.1)) * 0.15;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(VERTEX.z - behind.z, 0.0);

	vec2 p = world_pos.xz;
	float e = 0.06;
	float h = ripples(p);
	float hx = ripples(p + vec2(e, 0.0));
	float hz = ripples(p + vec2(0.0, e));
	vec3 n = normalize(vec3((h - hx) * 0.35, 1.0, (h - hz) * 0.35));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);

	float t = smoothstep(0.0, depth_fade, thickness);
	vec3 col = mix(shallow_color, deep_color, t);
	float foam = 1.0 - smoothstep(0.0, foam_width, thickness);
	foam *= smoothstep(0.25, 0.75, noise(p * 3.0 - flow * TIME * 2.0) * 0.6 + h * 0.6);
	col = mix(col, foam_color, foam * 0.75);
	ALBEDO = col;
	ALPHA = clamp(mix(0.45, 0.93, t) + foam * 0.35 + fresnel * 0.2, 0.0, 0.97);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
