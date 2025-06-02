shader_type canvas_item;

void fragment() {
    // Sample the texture.
    vec4 tex_color = texture(TEXTURE, UV);

    // Calculate a transparency value (here using smoothstep on distance)
    float d = distance(UV, vec2(0.5, 0.5));
    float alpha_factor = smoothstep(0.0, 0.5, d);

    // Combine the original texture alpha with our computed factor.
    // (If your texture is black, the RGB channels are zero,
    // so the color must come from the tint itself.)
    float final_alpha = tex_color.a * alpha_factor;

    // Hard-code the green tint.
    vec3 green_tint = vec3(0.9, 0.9, 0.9);

    // Use the final alpha as an intensity to apply the tint.
    // Since the texture is black, you’re effectively drawing green
    // with an opacity given by final_alpha.
    vec3 tinted_color = green_tint * final_alpha;

    COLOR = vec4(tinted_color, final_alpha);
}
