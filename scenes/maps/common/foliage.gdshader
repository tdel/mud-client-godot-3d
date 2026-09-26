// Cartes de feuillage (arbres, buissons, herbe) : alpha scissor (ombres découpées), deux
// faces sans inverser la normale (normales "sphériques" cuites par
// tools/env_gen/build_environment.py : éclairage doux, volumique), translucidité, balancement
// au vent croissant avec la hauteur, variation de teinte par instance (MultiMesh).
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

#include "res://scenes/maps/common/occlusion_fade.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.45;
uniform vec3 tint : source_color = vec3(1.0);
// Amplitude de la variation de luminosité/teinte d'une instance à l'autre.
uniform float tint_variation : hint_range(0.0, 0.5) = 0.14;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.1;
// Hauteur (m, repère du modèle) à laquelle le balancement atteint son amplitude pleine.
uniform float sway_height = 6.0;
uniform float translucency : hint_range(0.0, 1.0) = 0.35;
uniform float occlusion_radius = 3.2;
uniform bool occlusion_fade = true;

varying vec3 world_pos;
varying float variation;

void vertex() {
	vec3 instance_origin = MODEL_MATRIX[3].xyz;
	variation = fract(sin(dot(instance_origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float h = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float weight = h * h;
	float t = TIME * wind_speed + variation * 6.2831 + (instance_origin.x + instance_origin.z) * 0.07;
	vec3 offset = vec3(sin(t), 0.0, cos(t * 0.83)) * wind_strength * weight;
	offset += vec3(sin(t * 3.7 + VERTEX.x * 1.7), sin(t * 4.3 + VERTEX.z) * 0.3, cos(t * 3.1 + VERTEX.z * 1.9))
			* wind_strength * 0.22 * weight;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * offset;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	float v = mix(1.0 - tint_variation, 1.0 + tint_variation, variation);
	vec3 color = tex.rgb * tint * v;
	color.r *= mix(0.94, 1.06, fract(variation * 7.31));
	ALBEDO = color;
	ALPHA = tex.a;
	if (occlusion_fade) {
		ALPHA *= occlusion_keep(world_pos, CAMERA_DIRECTION_WORLD, FRAGCOORD.xy, occlusion_radius);
	}
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = color * translucency;
}
