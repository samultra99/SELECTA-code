shader_type canvas_item;

// Original shimmer parameters
uniform float speed : hint_range(0.0, 2.0) = 1.0;
uniform float width : hint_range(0.0, 0.2) = 0.1;
uniform float intensity : hint_range(0.0, 1.0) = 0.9;
uniform vec4 base_color : source_color = vec4(0.1, 0.7, 0.1, 1.0);
uniform vec4 line_color : source_color = vec4(0.3, 1.0, 0.3, 1.0);

// New opacity pulse parameters
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.0; // Control the speed of the opacity change
uniform float min_opacity : hint_range(0.0, 1.0) = 0.5; // Minimum opacity
uniform float max_opacity : hint_range(0.0, 1.0) = 1.0; // Maximum opacity

void fragment() {
    // Get UV coords
    vec2 uv = UV;

    // Compute a looping position [0..1)
    float pos = fract(TIME * speed);

    // Use only the x coordinate for horizontal movement
    float proj = uv.x;

    // Distance from the moving vertical line
    float d = abs(proj - pos);

    // Soft-edge band: 1 at center, 0 at 'width'
    float band = smoothstep(width, 0.0, d);

    // Apply overall intensity
    float a = band * intensity;

    // Mix base color with the shimmer line color
    vec3 color = mix(base_color.rgb, line_color.rgb, a);

    // Get original texture alpha
    vec4 texture_color = texture(TEXTURE, UV);

    // Calculate pulsing opacity
    float opacity_range = max_opacity - min_opacity;
    float pulse_opacity = min_opacity + opacity_range * (sin(TIME * pulse_speed) * 0.5 + 0.5);

    // Apply pulsing opacity to the original texture alpha
    float final_alpha = texture_color.a * pulse_opacity;

    // Set final color with pulsing opacity
    COLOR = vec4(color, final_alpha);
}