shader_type canvas_item;

uniform vec4 top_colour : source_color = vec4(0.85, 0.15, 0.10, 1.0);
uniform vec4 bottom_colour : source_color = vec4(1.0, 0.72, 0.35, 1.0);
uniform float rect_top = 0.0;
uniform float rect_height = 40.0;

void fragment() {
    float a = texture(TEXTURE, UV).a;
    // Position within the Label's rect, derived from the vertex position
    // rather than UV, since UV is per-glyph on a Label.
    float y = (FRAGCOORD.y - rect_top) / rect_height;
    vec3 grad = mix(top_colour.rgb, bottom_colour.rgb, clamp(y, 0.0, 1.0));
    COLOR = vec4(grad, a);
}