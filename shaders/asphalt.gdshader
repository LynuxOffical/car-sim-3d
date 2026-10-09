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
	float puddle = smoothstep(0.35, 0.85, fract(UV.y * 18.0 + sin(UV.x * 40.0) * 0.15));
	float wetness = clamp(wet * (0.72 + puddle * 0.45), 0.0, 1.0);
	col = mix(col, col * vec3(0.55, 0.60, 0.64), wetness);
	ALBEDO = col;
	ROUGHNESS = mix(roughness, 0.08, wetness);
	METALLIC = mix(metallic, 0.28, wetness);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	EMISSION = vec3(0.16, 0.20, 0.24) * fres * wetness;
}
