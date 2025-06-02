shader_type canvas_item;

uniform float speed : hint_range(0.1, 5.0) = 1.0; // Control the speed of the opacity change
uniform float min_opacity : hint_range(0.0, 1.0) = 0.5; // Minimum opacity
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0; // Maximum opacity

void fragment() {
    // Sample the texture
    vec4 tex_color = texture(TEXTURE, UV);

    // Calculate pulsing opacity (using cosine for smoother animation)
    float opacity_range = max_opacity - min_opacity;
    float pulse_opacity = min_opacity + opacity_range * (cos(TIME * speed) * 0.5 + 0.5);

    // Calculate distance-based transparency (radial gradient from center)
    float d = distance(UV, vec2(0.5, 0.5));
    float alpha_factor = smoothstep(0.5, 0.0, d); // Inverted to be more opaque in center

    // Hard-code the green tint
    vec3 green_tint = vec3(0.0, 1.0, 0.0);

    // Calculate final alpha combining texture alpha, distance factor, and pulsing effect
    float final_alpha = tex_color.a * alpha_factor * pulse_opacity;

    // Apply the tint with varying alpha
    COLOR.rgb = green_tint;
    COLOR.a = final_alpha;

    // COLOR = vec4(vec3(pulse_opacity), 1.0);
}