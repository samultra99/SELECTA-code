shader_type canvas_item;

uniform float speed : hint_range(0.0, 10.0) = 1.0; // Controls animation speed

void fragment() {
    // UV is the built-in texture coordinate (ranging [0,1])
    vec2 pos = UV;

    // Compute horizontal gradient with a sine function that shifts with time.
    // The phase offsets for the R, G, and B channels create a multicolored effect.
    float r = sin(pos.x * 10.0 + TIME * speed);
    float g = sin(pos.x * 10.0 + TIME * speed + 2.094);    // +120° phase offset (approx 2.094 radians)
    float b = sin(pos.x * 10.0 + TIME * speed + 4.18879);  // +240° phase offset (approx 4.18879 radians)

    // Normalize sine output from [-1, 1] to [0, 1]
    vec3 gradient_color = vec3(r, g, b) * 0.5 + 0.5;

    // Multiply the computed color with the text texture’s alpha.
    // This preserves transparency in areas where text is not drawn.
    COLOR = vec4(gradient_color, texture(TEXTURE, UV).a);
}
