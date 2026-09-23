shader_type canvas_item;
// Full-screen horror post effect: vignette, film grain, chromatic aberration,
// desaturation, heartbeat pulse, eyelid blink and blur (wake-up).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float vignette : hint_range(0.0, 1.5) = 0.35;
uniform float grain : hint_range(0.0, 0.3) = 0.05;
uniform float aberration : hint_range(0.0, 0.02) = 0.0015;
uniform float desaturation : hint_range(0.0, 1.0) = 0.25;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float blink : hint_range(0.0, 1.0) = 0.0;
uniform float blur : hint_range(0.0, 6.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;

	float ab = aberration * (1.0 + pulse * 4.0);
	vec3 col;
	col.r = textureLod(screen_texture, uv + c * ab * 2.0, blur).r;
	col.g = textureLod(screen_texture, uv, blur).g;
	col.b = textureLod(screen_texture, uv - c * ab * 2.0, blur).b;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), desaturation) * tint.rgb;

	// Vignette tightens with every heartbeat.
	float d = length(c * vec2(1.4, 1.0));
	col *= 1.0 - smoothstep(0.2, 0.95, d * (0.6 + vignette + pulse * 0.4)) * 0.92;

	col += (hash(uv * 1000.0 + fract(TIME) * 100.0) - 0.5) * grain;

	// Eyelids: 0 = open, 1 = closed.
	float opening = (1.0 - blink) * 0.75;
	float lid = abs(c.y) + c.x * c.x * 0.8;
	col *= 1.0 - smoothstep(opening - 0.08, opening, lid);

	COLOR = vec4(col, 1.0);
}
