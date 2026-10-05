shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.16, 0.16, 0.18, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.74;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float across = UV.x;
	vec3 tarmac = mix(vec3(0.12, 0.12, 0.13), albedo.rgb, 0.32);
	float shoulder = smoothstep(0.08, 0.0, across) + smoothstep(0.92, 1.0, across);
	vec3 col = tarmac * mix(1.0, 0.88, shoulder);
	col = mix(col, col * vec3(0.82, 0.86, 0.90), wet * 0.4);
	ALBEDO = col;
	ROUGHNESS = mix(roughness, 0.22, wet);
	METALLIC = metallic;
	SPECULAR = mix(0.15, 0.45, wet);
}
