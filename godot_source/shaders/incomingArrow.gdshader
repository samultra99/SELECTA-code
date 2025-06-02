shader_type canvas_item;

uniform float speed : hint_range(0.1, 5.0) = 1.0; // Control the speed of the opacity change
uniform float min_opacity : hint_range(0.0, 1.0) = 0.5; // Minimum opacity
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0; // Maximum opacity

void fragment() {
    // Create a smooth sine wave between min_opacity and max_opacity
    float opacity_range = max_opacity - min_opacity;
    float opacity = min_opacity + opacity_range * (sin(TIME * speed) * 0.5 + 0.5);

    // Get the original texture color
    vec4 tex_color = texture(TEXTURE, UV);

    // Set the color to white but maintain the texture's alpha channel
    // multiplied by our animated opacity
    COLOR = vec4(1.0, 0.0, 0.0, tex_color.a * opacity);
}