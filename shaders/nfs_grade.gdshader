shader_type canvas_item;
render_mode unshaded, blend_mul;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float vig = 1.0 - dot(d, d) * 0.30;
	vec3 grade = vec3(0.90, 0.91, 0.88) * vig;
	COLOR = vec4(grade, 1.0);
}
