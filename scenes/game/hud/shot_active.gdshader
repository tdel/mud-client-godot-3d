shader_type canvas_item;
// Icône de soulshot/spiritshot armé en auto-use (voir IconFactory.active_shot_material) :
// icône éclaircie qui respire, liseré lumineux intérieur et reflet diagonal qui balaie
// l'icône à intervalle régulier. Retiré (material = null) quand la charge est éteinte.

uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.28, 1.0);
// Durée d'un cycle du reflet (passage + pause), en secondes.
uniform float sweep_period = 2.4;

void fragment() {
	// COLOR = texture de l'icône déjà multipliée par la couleur de sommet/modulate.
	vec4 base = COLOR;
	float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
	vec3 col = base.rgb * (1.15 + 0.15 * pulse);

	vec2 d = min(UV, 1.0 - UV);
	float rim = 1.0 - smoothstep(0.0, 0.17, min(d.x, d.y));
	col += glow_color.rgb * rim * rim * (0.6 + 0.4 * pulse);

	// Reflet : bande diagonale qui traverse l'icône pendant ~40 % du cycle, puis pause.
	float phase = fract(TIME / sweep_period) * 2.5 - 0.5;
	float band = 1.0 - smoothstep(0.0, 0.1, abs((UV.x + UV.y) * 0.5 - phase));
	col += mix(vec3(1.0), glow_color.rgb, 0.35) * band * 0.6;

	COLOR = vec4(col, base.a);
}
