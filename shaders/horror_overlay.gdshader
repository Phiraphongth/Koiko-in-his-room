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
// Dark gradients quantise into visible diagonal bands: the game runs on the
// Compatibility renderer, which has no debanding pass of its own, so the fog
// in the distance steps instead of fading. A per-pixel offset of roughly one
// 8-bit level dissolves the steps without reading as noise.
uniform float dither : hint_range(0.0, 4.0) = 1.6;

// Hash31 from Dave Hoskins' "Hash without Sine": the usual sin-based hash
// breaks into diagonal streaks at low float precision, which is exactly the
// artefact this shader is meant to hide.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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

	vec2 noise_uv = FRAGCOORD.xy + fract(TIME) * 371.0;
	col += (hash(noise_uv) - 0.5) * grain;
	// Dither last, so it survives into the 8-bit frame buffer.
	col += (hash(noise_uv * 1.7 + 19.3) - 0.5) * (dither / 255.0);

	// Eyelids: 0 = open, 1 = closed.
	float opening = (1.0 - blink) * 0.75;
	float lid = abs(c.y) + c.x * c.x * 0.8;
	col *= 1.0 - smoothstep(opening - 0.08, opening, lid);

	COLOR = vec4(col, 1.0);
}
