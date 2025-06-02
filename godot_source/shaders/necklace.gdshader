shader_type canvas_item;

// Wind strength and speed parameters
uniform float wind_strength : hint_range(0.0, 0.1) = 0.1;
uniform float wind_speed : hint_range(0.1, 5.0) = 5.0;
uniform float swing_amplitude : hint_range(0.0, 0.1) = 0.1;
uniform float swing_frequency : hint_range(0.5, 5.0) = 5;

// Pivot point (relative to texture, 0,0 is top-left, 1,1 is bottom-right)
uniform vec2 pivot_point = vec2(0.5, 0.0); // Default to top center

void vertex() {
    // Calculate time-based oscillation for natural swinging effect
    float swing = sin(TIME * swing_frequency) * swing_amplitude;
    float wind_effect = sin(TIME * wind_speed) * wind_strength;

    // Combine swing and wind for a more natural motion
    float total_effect = swing + wind_effect;

    // Calculate distance from pivot point
    vec2 relative_pos = UV - pivot_point;

    // Apply rotation around pivot point
    // The further from the pivot, the more effect
    float distance_factor = length(relative_pos);
    float angle = total_effect * distance_factor * 5.0;

    // Rotation matrix application
    mat2 rotation_matrix = mat2(
        vec2(cos(angle), -sin(angle)),
        vec2(sin(angle), cos(angle))
    );

    // Apply the rotation and move back to original position
    VERTEX += (rotation_matrix * relative_pos - relative_pos) * TEXTURE_PIXEL_SIZE * 100.0;
}