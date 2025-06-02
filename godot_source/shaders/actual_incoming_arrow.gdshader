shader_type canvas_item;

// Opacity pulse parameters
uniform float pulse_speed : hint_range(0.1, 5.0) = 0.25; // Control the speed of the opacity change
uniform float min_opacity : hint_range(0.0, 1.0) = 0.5; // Minimum opacity
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0; // Maximum opacity

// Shimmer parameters
uniform float shimmer_speed : hint_range(0.0, 2.0) = 1.0; // Speed of the shimmer movement
uniform float shimmer_width : hint_range(0.0, 0.2) = 0.1; // Width of the shimmer band
uniform float shimmer_intensity : hint_range(0.0, 1.0) = 0.9; // Brightness of the shimmer
uniform vec4 shimmer_color : source_color = vec4(1.2, 1.2, 1.2, 1.0); // Colour of the shimmer (slightly brighter white)

void fragment() {
    // Get UV coords
    vec2 uv = UV;

    // Create a smooth sine wave between min_opacity and max_opacity
    float opacity_range = max_opacity - min_opacity;
    float opacity = min_opacity + opacity_range * (sin(TIME * pulse_speed) * 0.5 + 0.5);

    // Get the original texture color
    vec4 tex_color = texture(TEXTURE, UV);

    // Compute shimmer effect
    float pos = fract(TIME * shimmer_speed);
    float proj = uv.x; // Horizontal movement
    float d = abs(proj - pos);
    float band = smoothstep(shimmer_width, 0.0, d);
    float shimmer_amount = band * shimmer_intensity;

    // Base white color
    vec3 base_white = vec3(1.0, 1.0, 1.0);

    // Mix white base with shimmer effect
    vec3 final_color = mix(base_white, shimmer_color.rgb, shimmer_amount);

    // Apply the combined effect
    COLOR = vec4(final_color, tex_color.a * opacity);
}