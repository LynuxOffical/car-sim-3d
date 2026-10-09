shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float dust : hint_range(0.0, 1.0) = 0.0;
uniform float lightning : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float rain_layer(vec2 uv, float scale_x, float scale_y, float speed, float slant, float thresh) {
	vec2 ruv = uv * vec2(scale_x, scale_y);
	ruv.x += uv.y * slant;
	ruv.y -= TIME * speed;
	vec2 cell = floor(ruv);
	vec2 f = fract(ruv);
	float h = hash(cell);
	float drop = smoothstep(0.07, 0.0, abs(f.x - 0.48 - (h - 0.5) * 0.12));
	drop *= step(thresh, h);
	drop *= smoothstep(0.0, 0.12, f.y) * smoothstep(1.0, 0.35, f.y);
	return drop;
}

float snow_layer(vec2 uv, float scale, float speed, float wind) {
	vec2 suv = uv * scale;
	suv.x += TIME * wind;
	suv.y -= TIME * speed;
	vec2 cell = floor(suv);
	vec2 f = fract(suv) - 0.5;
	float h = hash(cell);
	float r = 0.018 + h * 0.04;
	return smoothstep(r, 0.0, length(f - vec2((h - 0.5) * 0.2, 0.0)));
}

void fragment() {
	vec2 uv = UV;
	vec3 col = vec3(0.0);
	float a = 0.0;

	if (rain > 0.001) {
		float dens = 0.42 + rain * 0.55 + storm * 0.35;
		float s1 = rain_layer(uv, 70.0, 14.0, 7.5 + storm * 3.0, 0.55 + storm * 0.45, 0.62 - rain * 0.22);
		float s2 = rain_layer(uv, 118.0, 22.0, 11.0 + storm * 4.0, 0.85 + storm * 0.5, 0.70 - rain * 0.18);
		float s3 = rain_layer(uv, 190.0, 34.0, 15.5, 1.15, 0.78 - rain * 0.12);
		float streaks = (s1 * 0.85 + s2 * 0.65 + s3 * 0.45) * dens;
		col += vec3(0.78, 0.86, 0.95) * streaks;
		a += streaks * (0.55 + storm * 0.2);
		float haze = (0.05 + storm * 0.08) * rain;
		float vig = dot(uv - vec2(0.5), uv - vec2(0.5));
		col += vec3(0.16, 0.20, 0.26) * haze;
		a += haze * 0.7 + vig * rain * (0.07 + storm * 0.08);
	}

	if (snow > 0.001) {
		float f1 = snow_layer(uv, 28.0, 0.22, 0.07);
		float f2 = snow_layer(uv, 48.0, 0.38, -0.05);
		float f3 = snow_layer(uv, 76.0, 0.55, 0.11);
		float flakes = (f1 * 0.9 + f2 * 0.7 + f3 * 0.5) * (0.75 + snow * 0.5);
		col += vec3(0.92, 0.95, 1.0) * flakes;
		a += flakes * 0.7;
		a += snow * 0.16;
		col += vec3(0.72, 0.80, 0.90) * snow * 0.12;
	}

	if (dust > 0.001) {
		float n = hash(floor(uv * 40.0 + TIME * 2.0));
		col += vec3(0.78, 0.55, 0.28) * (0.55 + n * 0.2);
		a += dust * (0.22 + n * 0.05);
	}

	if (lightning > 0.001) {
		col = mix(col, vec3(0.88, 0.92, 1.0), lightning);
		a = clamp(a + lightning * 0.62, 0.0, 0.9);
	}

	COLOR = vec4(col, clamp(a, 0.0, 0.82));
}
