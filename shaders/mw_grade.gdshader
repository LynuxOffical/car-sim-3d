shader_type canvas_item;
render_mode unshaded, blend_mix;

void fragment() {
	vec2 uv = UV;
	float left = 1.0 - smoothstep(0.26, 0.58, uv.x);
	float scan = 0.035 * sin(uv.y * 900.0);
	float vig = clamp(1.0 - dot(uv - vec2(0.5), uv - vec2(0.5)) * 0.72, 0.35, 1.0);
	float top = smoothstep(0.08, 0.0, uv.y);
	float bot = smoothstep(0.92, 1.0, uv.y);
	float a = 0.62 * left + 0.10 + scan + top * 0.28 + bot * 0.22;
	vec3 col = mix(vec3(0.01, 0.02, 0.04), vec3(0.04, 0.07, 0.10), 1.0 - left);
	col = mix(col, vec3(0.72, 0.55, 0.12), top * 0.18);
	col *= vig;
	COLOR = vec4(col, clamp(a, 0.0, 0.78));
}
