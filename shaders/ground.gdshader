shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform vec4 albedo : source_color = vec4(0.29, 0.50, 0.23, 1.0);

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
