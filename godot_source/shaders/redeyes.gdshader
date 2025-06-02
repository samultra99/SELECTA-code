shader_type canvas_item;

// How far (in pixels) the glow reaches from the sprite’s opaque edges
uniform float glow_size : hint_range(0.0, 20.0) = 4.0;

// The color of the glow (red by default)
uniform vec4 glow_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

// How many pulses per second
uniform float glow_speed : hint_range(0.1, 5.0) = 1.0;

// Number of sample taps (max 8)
uniform int glow_samples : hint_range(1, 8) = 8;

void fragment() {
    // Base sprite color/alpha
    vec4 base = texture(TEXTURE, UV);

    // Pulse factor: 0 → 1 → 0 at glow_speed Hz
    float pulse = sin(TIME * glow_speed * 2.0 * PI) * 0.5 + 0.5;

    // Compute a simple outline by sampling neighbor alphas
    float outline = 0.0;
    vec2 offs = glow_size * TEXTURE_PIXEL_SIZE;
    vec2 dirs[8] = vec2[](
        vec2( 1,  0), vec2(-1,  0),
        vec2( 0,  1), vec2( 0, -1),
        vec2( 1,  1), vec2( 1, -1),
        vec2(-1,  1), vec2(-1, -1)
    );
    // Accumulate alpha from up to glow_samples neighbors
    for (int i = 0; i < glow_samples; i++) {
        outline += texture(TEXTURE, UV + dirs[i] * offs).a;
    }
    outline /= float(glow_samples);

    // Final glow color = red * outline * pulse
    vec4 glow = glow_color * outline * pulse;

    // Additively blend glow onto sprite, keep proper alpha
    vec3  rgb   = base.rgb + glow.rgb;
    float alpha = max(base.a, glow.a);

    COLOR = vec4(rgb, alpha);
}
