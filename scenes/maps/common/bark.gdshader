// Écorce / bois des arbres instanciés en masse : PBR simple (couleur, normale, rugosité) +
// même balancement au vent que foliage.gdshader (le tronc ne bouge pas, les branches hautes
// suivent le feuillage) + transparence en damier quand l'arbre cache le joueur.
shader_type spatial;
render_mode specular_schlick_ggx;

#include "res://scenes/maps/common/occlusion_fade.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_map = true;
uniform bool use_roughness_map = true;
// Matériaux unis (vitres, toiles, runes) : teinte seule, sans texture.
uniform bool use_albedo_texture = true;
// Vitres éclairées la nuit, runes, braises (voir EnvMaterials.set_night_factor).
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.1;
uniform float sway_height = 6.0;
uniform float occlusion_radius = 3.2;
uniform bool occlusion_fade = true;

varying vec3 world_pos;

void vertex() {
	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	float variation = fract(sin(dot(instance_origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float weight = h * h;
	float t = TIME * wind_speed + variation * 6.2831 + (instance_origin.x + instance_origin.z) * 0.07;
	vec3 offset = vec3(sin(t), 0.0, cos(t * 0.83)) * wind_strength * weight;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	ALBEDO = use_albedo_texture ? texture(albedo_texture, uv).rgb * tint : tint;
	EMISSION = emission_color * emission_energy;
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_texture, uv).rgb;
	}
	ROUGHNESS = use_roughness_map ? texture(roughness_texture, uv).g : 0.9;
	SPECULAR = 0.3;
	if (occlusion_fade && occlusion_keep(world_pos, CAMERA_DIRECTION_WORLD, FRAGCOORD.xy, occlusion_radius) < 0.5) {
		discard;
	}
}
