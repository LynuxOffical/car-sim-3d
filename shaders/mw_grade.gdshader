shader_type canvas_item;
render_mode unshaded, blend_mix;

void fragment() {
	vec2 uv = UV;
	float scan = 0.018 * sin(uv.y * 720.0);
	float vig = clamp(1.0 - dot(uv - vec2(0.52, 0.48), uv - vec2(0.52, 0.48)) * 0.85, 0.28, 1.0);
	float top = smoothstep(0.10, 0.0, uv.y);
	float bot = smoothstep(0.90, 1.0, uv.y);
	float a = 0.10 + scan + top * 0.34 + bot * 0.26;
	vec3 col = mix(vec3(0.02, 0.03, 0.05), vec3(0.06, 0.05, 0.04), uv.y);
	col = mix(col, vec3(0.78, 0.58, 0.14), top * 0.22);
	col *= vig;
	COLOR = vec4(col, clamp(a, 0.0, 0.42));
}
