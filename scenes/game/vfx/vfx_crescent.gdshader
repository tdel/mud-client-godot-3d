shader_type spatial;
// Lame de vent en croissant sur un PlaneMesh (projectile de vent, entailles) : arc effilé aux
// deux bouts, traînée diffuse côté intérieur, bord d'attaque (t > 0) plus lumineux.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform float energy = 2.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float span = 2.2;
uniform float thickness = 0.14;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float t = atan(p.y, p.x) / span;
	float shape = max(1.0 - t * t, 0.0);
	float th = thickness * shape;
	float d = abs(r - 0.72);
	float blade = (1.0 - smoothstep(th * 0.3, th + 0.001, d)) * step(abs(t), 1.0);
	float smear = exp(-max(0.72 - r, 0.0) * 5.0) * step(r, 0.72) * shape * 0.3;
	float lead = smoothstep(-1.0, 1.0, t);
	float m = (blade + smear) * mix(0.3, 1.0, lead);
	ALBEDO = mix(tint.rgb, vec3(1.0), blade * 0.5) * energy;
	ALPHA = clamp(m, 0.0, 1.0) * alpha * tint.a;
}
