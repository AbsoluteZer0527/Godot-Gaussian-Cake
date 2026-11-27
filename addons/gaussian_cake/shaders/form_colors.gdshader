shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D form_colors : filter_nearest, repeat_disable;
uniform int form_count = 2;
uniform float form_weights[128];
void fragment() {
    vec3 color = vec3(0.0);
    for (int i=0; i<form_count; i++) {
        if (form_weights[i] > 0.0) {
            color += texture(form_colors,vec2(UV.x,(UV.y+float(i))/float(form_count))).rgb * form_weights[i];
        }
    }
    if (OUTPUT_IS_SRGB) {
        color = mix(12.92*color,1.055*pow(max(color,vec3(0.0)),vec3(1.0/2.4))-0.055,step(vec3(0.0031308),color));
    }
    ALBEDO = color;
}
