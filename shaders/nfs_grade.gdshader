shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(luma), 0.34);
	c *= vec3(1.02, 1.01, 0.98);
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.08);
	c = (c - 0.5) * 1.02 + 0.50;
	vec2 d = SCREEN_UV - vec2(0.5);
	c *= 1.0 - dot(d, d) * 0.28;
	c += vec3(flash);
	COLOR = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}
