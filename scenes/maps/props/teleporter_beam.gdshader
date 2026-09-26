shader_type spatial;
// Rayon d'énergie entre un cristal d'obélisque et la colonne du portail (voir Teleporter.gd) :
// CylinderMesh de hauteur 1 (UV.y le long du rayon), impulsions qui filent vers le centre,
// extrémités adoucies, rendu additif.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.35, 0.65, 1.0, 1.0);
uniform float energy = 1.6;
uniform float speed = 0.9;

void fragment() {
	float along = UV.y;
	float pulse = pow(0.5 + 0.5 * sin((along + TIME * speed) * 18.0), 6.0);
	float ends = smoothstep(0.0, 0.12, along) * smoothstep(1.0, 0.8, along);
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float m = (0.35 + pulse * 0.9) * ends * (0.5 + rim * 0.5);
	ALBEDO = mix(tint.rgb, vec3(1.0), pulse * 0.4) * energy;
	ALPHA = clamp(m, 0.0, 1.0) * tint.a;
}
