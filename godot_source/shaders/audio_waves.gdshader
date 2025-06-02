shader_type canvas_item;
// Audio-reactive shader by Samuel Shipp, part adapted from Balatro Card Foil on Godot Shaders.
// Created with debug support from Claude 3.7 Sonnet by Anthropic
// Added flicking line with animation
// Connects with audio_waves_bg.gd to have animate_flick (line flick) and offset (record spin) change in time with the music,
// as well as for colour intensity to increase over course of a song

// Parameters you can adjust in Godot Inspector
uniform vec4 line_color: source_color = vec4(0.7, 0.0, 1.0, 1.0); // colour
uniform float line_thickness: hint_range(0.001, 1.0) = 0.01;    // Line thickness
uniform float glow_intensity: hint_range(0.0, 2.0) = 1.0;       // Glow intensity
uniform float glow_size: hint_range(0.0, 0.2) = 0.05;           // Glow size
uniform vec4 line2_color: source_color = vec4(0.7, 0.0, 1.0, 1.0); // colour
uniform float line2_thickness: hint_range(0.0, 1.0) = 0.01;    // Line thickness
uniform float glow2_intensity: hint_range(0.0, 2.0) = 1.0;       // Glow intensity
uniform float glow2_size: hint_range(0.0, 0.2) = 0.1;           // Glow size
// Animation control - set to true to trigger the flick animation
uniform bool animate_flick = false;
// Animation duration in seconds
uniform float anim_duration = 0.1;
// Animation progress (0.0 to 1.0)
uniform float anim_progress = 0.0;
// Line position parameters
uniform float line_y_position: hint_range(0.0, 1.0) = 0.5;      // Vertical position of the line

// Record spin effect controls
uniform vec3 highlightColor = vec3(0.3, 0.3, 1.9);  // Controls the highlight colour blend
uniform vec3 baseColor = vec3(0.3, 0.3, 0.3);       // Controls the base colour blend
uniform vec2 circle1Center = vec2(0.5, 0.5);        // Centre of first circle pattern
uniform vec2 circle2Center = vec2(0.5, 0.5);        // Centre of second circle pattern
uniform float record_effect_blend = 0.8;            // How strongly to blend the record effect (0-1)

// Function to create a smooth line with glow
float line_with_glow(float position, float target, float thickness, float glow_sz, float intensity) {
    float half_thickness = thickness * 0.5;
    // Core line (sharp)
    float line = smoothstep(target - half_thickness, target, position) -
                 smoothstep(target, target + half_thickness, position);
    // Glow effect (more diffuse)
    float glow = smoothstep(target - half_thickness - glow_sz, target, position) -
                 smoothstep(target, target + half_thickness + glow_sz, position);
    return line + glow * intensity * 0.5;
}

// Function to apply a flicking animation to a point on the line
vec2 apply_flick_animation(vec2 uv, float progress) {
    // No animation if not triggered
    if (!animate_flick) return uv;
    float distortion_amount = 0.0;
    // Create a flicking animation curve
    if (progress < 0.3) {
        // Pull back phase
        distortion_amount = progress * 3.33 * 0.2; // Max distortion = 0.2
    } else if (progress < 0.6) {
        // Release/snap phase
        float t = (progress - 0.3) * 3.33;
        distortion_amount = 0.2 * (1.0 - t * 2.0); // Overshoot
    } else {
        // Settle phase
        float t = (progress - 0.6) * 2.5;
        distortion_amount = -0.2 * pow(1.0 - t, 2.0) * sin(t * 15.0);
    }
    // Apply vertical distortion based on horizontal position
    // Centre has more distortion, edges have less
    float x_factor = sin(uv.x * 3.14159); // Max at centre (x=0.5)
    float y_offset = distortion_amount * x_factor;
    return vec2(uv.x, uv.y + y_offset);
}

uniform highp vec2 offset;
uniform highp float speed : hint_range(0, 1) = 1.;

vec4 record_effect(vec2 texture_coords) {
    vec2 uv = texture_coords;

    // Use the custom circle centres
    vec2 adjusted_uv1 = uv - circle1Center;
    vec2 adjusted_uv2 = uv - circle2Center;

    vec2 foil = vec2(TIME / (1. / speed) + offset.x, offset.y);

    // First circle pattern - using adjusted_uv1
    float fac = max(min(2. * sin((length(90. * adjusted_uv1) + foil.r * 2.) + 3. * (1. + 0.8 * cos(length(113.1121 * adjusted_uv1) - foil.r * 3.121))) - 1. - max(5. - length(90. * adjusted_uv1), 0.), 1.), 0.);

    vec2 rotater = vec2(cos(foil.r * 0.1221), sin(foil.r * 0.3512));
    float angle = dot(rotater, adjusted_uv2) / (length(rotater) * length(adjusted_uv2));

    // Second circle pattern - using adjusted_uv2
    float fac2 = max(min(5. * cos(foil.g * 0.3 + angle * 3.14*(2.2 + 0.9*sin(foil.r * 1.65 + 0.2 * foil.g))) - 4. - max(2.-length(20.*adjusted_uv2), 0.), 1.), 0.);

    float fac3 = 0.3 * max(min(2. * sin(foil.r * 5. + uv.x * 3. + 3. * (1. + 0.5 * cos(foil.r * 7.))) - 1., 1.), -1.);
    float fac4 = 0.3 * max(min(2. * sin(foil.r * 6.66 + uv.y * 3.8 + 3. * (1. + 0.5 * cos(foil.r * 3.414))) - 1., 1.), -1.);

    float maxfac = max(max(fac, max(fac2, max(fac3, max(fac4, 0.0)))) + 2.2 * (fac + fac2 + fac3 + fac4), 0.);

    // Base colour
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0);

    // Apply custom colour blending using the uniform color variables
    color.r = baseColor.r * maxfac;
    color.g = baseColor.g * maxfac;
    color.b = highlightColor.b * maxfac;

    color.a = min(1.0, 0.3 + 0.9 * min(0.5, maxfac * 0.1));

    return color;
}

void fragment() {
    // Start with black background
    vec4 color = vec4(0.0, 0.0, 0.0, 1.0);

    // Get UV coordinates and apply animation
    vec2 animated_uv = apply_flick_animation(UV, anim_progress);

    // Draw the horizontal lines with glow
    float line_value = line_with_glow(animated_uv.y, line_y_position, line_thickness, glow_size, glow_intensity);
    float line2_value = line_with_glow(animated_uv.y, line_y_position, line2_thickness, glow2_size, glow2_intensity);

    // Apply line colors with intensity
    vec4 line_glow = line_color * line_value;
    vec4 line2_glow = line2_color * line2_value;

    // Add some variation based on x position to make the glow more interesting
    float x_variation = sin(animated_uv.x * 15.0 + TIME * 2.0) * 0.1 + 0.9;
    line_glow *= x_variation;
    line2_glow *= x_variation;

    // Combine with background
    color = mix(color, line_glow, line_glow.a);
    color = mix(color, line2_glow, line2_glow.a);

    // Generate the record effect
    vec4 record = record_effect(UV.xy);

    // Mix the record effect with the line effect based on record_effect_blend
    COLOR = mix(color, record, record_effect_blend);
}