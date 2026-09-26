shader_type spatial;
// Halo posé en material_overlay sur une pièce d'équipement pendant son apparition/disparition
// (voir Character._play_mesh_effect) : liseré de Fresnel additif + scintillement qui défile
// le long de la pièce. `intensity` est animée par Tween (0 = invisible).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform float intensity = 0.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float shimmer = 0.5 + 0.5 * sin(TIME * 14.0 - world_pos.y * 30.0);
	ALBEDO = glow_color.rgb * intensity * (0.3 + 1.4 * fresnel) * (0.7 + 0.3 * shimmer);
}
