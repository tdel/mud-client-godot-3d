// Transparence "en damier" des éléments de décor qui cachent le joueur (arbres, props hauts)
// à la caméra isométrique. Game3D pousse chaque frame la position du joueur et la direction
// de la caméra principale (voir Game3D._update_occlusion_globals) ; la passe d'ombre (dont la
// "caméra" est la lumière, donc de direction différente) n'est pas touchée : les ombres des
// arbres restent pleines.

global uniform vec3 player_world_position;
global uniform vec3 main_camera_direction;

// Renvoie 0.0 si le fragment doit disparaître (au-dessus du motif de tramage), 1.0 sinon.
float occlusion_keep(vec3 world_pos, vec3 camera_dir_world, vec2 frag_coord, float radius) {
	// Valeur absolue : seule compte l'égalité de l'axe (la convention de signe de
	// CAMERA_DIRECTION_WORLD n'importe pas, la lumière n'est jamais alignée sur la caméra).
	if (abs(dot(camera_dir_world, main_camera_direction)) < 0.999) {
		return 1.0;
	}
	vec3 to_frag = world_pos - (player_world_position + vec3(0.0, 0.9, 0.0));
	// Vers la caméra = -main_camera_direction. Le fragment doit être devant le joueur.
	float along = dot(to_frag, -main_camera_direction);
	if (along < 0.6) {
		return 1.0;
	}
	float perp = length(to_frag + main_camera_direction * along);
	float strength = smoothstep(radius, radius * 0.55, perp) * smoothstep(0.6, 2.0, along);
	// Matrice de Bayer 4x4 : tramage stable, lisible même en ombrage avec alpha scissor.
	int x = int(mod(frag_coord.x, 4.0));
	int y = int(mod(frag_coord.y, 4.0));
	const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
			3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	float threshold = (bayer[y * 4 + x] + 0.5) / 16.0;
	return strength > threshold ? 0.0 : 1.0;
}
