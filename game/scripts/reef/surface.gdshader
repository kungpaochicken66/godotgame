shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled;
varying vec2 pos;
void vertex(){pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xz;}
void fragment(){
 vec2 p=pos*.55;
 float a=dot(p,vec2(.65,1.27))+TIME*.54;
 float b=dot(p,vec2(-1.11,.37))-TIME*.43;
 vec2 slope=vec2(cos(a)*.16+cos(b*2.3+sin(a))*.091,cos(b)*.20+cos(a*3.71+sin(b))*.047);
 slope+=vec2(sin(p.y*6.1+sin(a*2.)+TIME)*.028,cos(p.x*4.7+cos(b*2.)-TIME*.7)*.025);
 vec2 sun=(pos-vec2(-1.,-14.))*vec2(.054,.043);
 float distance_to_sun=length(sun+slope*1.8);
 float glitter=exp(-7.*distance_to_sun)*(.4+.6*pow(max(0.,cos(a*2.+b*3.)),4.));
 float shafts=exp(-1.8*distance_to_sun);
 float clouds=.5+.5*sin(p.x*.30+sin(p.y*.41));
 vec3 base=mix(vec3(.018,.14,.23),vec3(.09,.47,.51),clouds*.5+shafts*.5);
 vec3 water=base+shafts*vec3(.32,.53,.50)+glitter*vec3(1.35,1.24,.89)+max(0.,slope.y)*vec3(.08,.15,.15);
 ALBEDO=water;
 ALPHA=1.-smoothstep(15.,48.,length(pos-CAMERA_POSITION_WORLD.xz));
}
