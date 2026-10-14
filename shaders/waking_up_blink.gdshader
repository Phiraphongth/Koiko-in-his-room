shader_type canvas_item;
// Waking up: curved eyelids closing / opening over a blurred screen, with a
// colour fade on top (white = the dream dissolving, black = eyes shut).
// Driven by TransitionOverlay (ui/transition_overlay.gd).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blink_progress : hint_range(0.0, 1.0) = 0.0; // 0 = open, 1 = shut
uniform float blur_amount : hint_range(0.0, 6.0) = 0.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 0.0); // alpha = amount
uniform vec4 lid_color : source_color = vec4(0.05, 0.012, 0.008, 1.0); // light through skin
uniform float lid_softness : hint_range(0.0, 0.3) = 0.09;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec3 col = textureLod(screen_texture, uv, blur_amount).rgb;

	// Soft dark edges, like the corners of half-open eyes.
	float d = length(c * vec2(1.3, 1.0));
	col *= 1.0 - vignette * smoothstep(0.3, 0.85, d);

	// Eyelids: an almond-shaped opening that shrinks to a slit. The corners
	// close first, the middle last.
	float opening = (1.0 - blink_progress) * 0.9;
	float lid = abs(c.y) * 1.15 + c.x * c.x * 0.9;
	float open_mask = 1.0 - smoothstep(opening - lid_softness, opening, lid);
	open_mask *= step(0.0001, 1.0 - blink_progress);
	// A warm glow bleeding in at the edge of the lids.
	vec3 rim = mix(lid_color.rgb, vec3(0.55, 0.32, 0.22), 0.35);
	vec3 lids = mix(lid_color.rgb, rim, smoothstep(opening - lid_softness * 2.5, opening, lid) * (1.0 - blink_progress));
	col = mix(lids, col, open_mask);

	col = mix(col, fade_color.rgb, fade_color.a);
	COLOR = vec4(col, 1.0);
}
