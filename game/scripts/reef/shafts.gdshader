shader_type spatial;
render_mode unshaded,cull_disabled,blend_add,depth_draw_never;
varying float phase;
void vertex(){phase=MODEL_MATRIX[3].x;}
void fragment(){
 float edge=pow(max(0.,sin(UV.x*3.14159)),3.);
 ALBEDO=vec3(.34,.71,.63);
 ALPHA=edge*pow(1.-UV.y,1.5)*.12*(.82+.18*sin(TIME*.44+phase));
}
