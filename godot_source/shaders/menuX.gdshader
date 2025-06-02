shader_type canvas_item;

uniform vec4 tint_color : source_color;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);

    // Calculate distance from the center of the texture (UV coordinate (0.5, 0.5))
    float d = distance(UV, vec2(0.5, 0.5));

    // smoothstep: values below 0.2 yield 0 (transparent) and above 0.5 yield 1 (opaque)
    // Adjust these values as needed.
    float alpha_factor = smoothstep(1.0, 0.2, d);

    // Modulate the alpha channel by the computed factor.
    tex_color.a *= alpha_factor;

    // Multiply the RGB by the tint color and the updated alpha.
    tex_color.rgb = tint_color.rgb * tex_color.a;

    COLOR = tex_color;
}
