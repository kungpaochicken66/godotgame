shader_type spatial;
render_mode cull_disabled;
uniform vec4 pigment : source_color = vec4(0.16,0.38,0.39,1.);
uniform float glimmer = 0.1;
uniform int motion = 0;
uniform int finish = 0;
varying vec3 wp;
varying vec3 local;
varying float variety;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*4375.5453);}
float noise2(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){
 local=VERTEX;
 vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 if(motion==1){float h=max(VERTEX.y,0.);VERTEX.x+=h*.054*sin(TIME*.72+p.z*.27+h*.37);VERTEX.z+=h*.032*cos(TIME*.65+p.x*.23+h*.33);}
 if(motion==2){VERTEX.y+=.39*pow(abs(COLOR.r*2.-1.),1.5)*sin(TIME*2.1+p.z*.10-abs(VERTEX.x));}
 if(motion==3){VERTEX.z+=.10*sin(TIME*5.+VERTEX.x*5.+p.x)*max(.15,-VERTEX.x);}
 wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 variety=fract(sin(dot(MODEL_MATRIX[3].xz,vec2(2.35,3.71)))*826.31);
}
void fragment(){
 vec2 q=wp.xz+wp.y*vec2(.42,.21);
 float broad=noise2(q*.56);
 float fleck=noise2(q*4.4+wp.y);
 vec2 w=q*2.05+vec2(TIME*.29,-TIME*.24);
 w+=vec2(sin(w.y*1.17+sin(w.x*.5)),cos(w.x*.89+w.y*.27));
 float lines=abs(sin(w.x+sin(w.y))+cos(w.y+sin(w.x*.74)));
 float caustic=exp(-lines*12.)*(.28+.72*broad);
 vec3 col=pigment.rgb*(.72+.25*variety);
 if(finish==1){
  float layer=sin(wp.y*3.8+2.6*broad+fleck*.45);
  col=mix(col*.44,col*1.38+.018, smoothstep(-.88,.35,layer))*(.55+.61*fleck);
  col=mix(col,vec3(.055,.093,.058),smoothstep(.57,.76,broad)*.68);
 }else if(finish==2){
  float ripple=sin(q.x*8.+q.y*2.2+3.2*broad);
  col=mix(vec3(.069,.14,.135),col,smoothstep(.15,.68,broad))*(.74+.20*ripple+.20*fleck);
 }else if(finish==3){
  col*=.54+.42*noise2(local.xz*vec2(.7,7.)+local.y*2.)+.27*sin(local.x*.93+local.y*18.+broad);
 }else if(motion==1){
  col*=mix(vec3(.39,.68,.61),vec3(1.31,1.15,.67),UV.y);
  col*=.69+.5*pow(abs(2.*UV.x-1.),.5)+.18*sin(UV.y*38.+abs(UV.x-.5)*14.);
 }else{ col*=.65+.4*fleck+.18*broad; }
 float depth=clamp((wp.y+4.)/19.,0.,1.);
 ROUGHNESS=.84;
 ALBEDO=col*mix(vec3(.68,.85,1.),vec3(1.1,1.04,.87),depth);
 EMISSION=col*(glimmer+caustic*(finish==1?.45:1.5))+caustic*vec3(.035,.125,.10)*(finish==1?.4:1.);
}
