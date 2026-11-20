// Works with the Workshop's active construction Track or the same Track in the offline exporter.
import {TrainSim, findStation} from './js/sim.js';
export const rides = [
  {id:'orchard-breeze', theme:'classic', body:'#e7a321', trim:'#fff0bd', rail:'#a74436', style:'wood',
   x:56,z:43, turns:1, lift:9, liftEnd:.22, peaks:[[0,0],[.07,0],[.22,22],[.32,2],[.42,14],[.51,2],[.60,10],[.68,1],[.76,8],[.84,1],[.89,4],[.96,0],[1,0]]},
  {id:'comet-run', theme:'rocket', body:'#bf342e', trim:'#dce9eb', rail:'#3964a7', style:'truss',
   x:140,z:104, turns:1, launch:32, lift:12,liftEnd:.25, peaks:[[0,0],[.06,0],[.15,10],[.25,51],[.36,2],[.46,29],[.55,2],[.64,22],[.72,2],[.80,16],[.87,2],[.92,8],[.98,0],[1,0]]},
  {id:'copper-coil', theme:'dragon', body:'#218d78', trim:'#e9aa4a', rail:'#268a88', style:'box',
   x:41,z:41, turns:2,lift:12,liftEnd:.21, peaks:[[0,0],[.04,0],[.21,41],[.34,8],[.44,24],[.57,3],[.69,18],[.8,3],[.88,13],[.96,0],[1,0]]}
];
export function construct(track, r) {
  const {cos,sin,PI} = Math;
  track.nodes=[];
  Object.assign(track.opts,{style:r.style,railColor:r.rail,spineColor:r.body,liftSpeed:r.lift,launchSpeed:r.launch||32});
  for(let i=0;i<144;i++){
    const t=i/144, a=t*2*PI, b=a*r.turns;
    const radius=r.turns===2?1+.31*cos(a):1;
    const j=r.peaks.findIndex(([end])=>end>t);
    const [ta,lo]=r.peaks[j-1], [tb,hi]=r.peaks[j];
    const h=lo+(hi-lo)*(.5-.5*cos(PI*(t-ta)/(tb-ta)));
    const stationEnd=r.peaks[1][0];
    const kind=t<stationEnd?'station':t<r.liftEnd?(r.launch?(t<.18?'launch':'normal'):'lift'):t>.96?'brake':'normal';
    track.addNode(r.x*radius*cos(b),4+h,r.z*radius*sin(b),0,kind,true);
  }
}
export function bake(track,pitch=3) {
  track.compute();
  const sim=new TrainSim(track,3,pitch), timeline=[];
  sim.dispatch();
  for(let i=0;i<18000&&!sim.lap;i++){
    if(i%3===0)timeline.push([sim.s,sim.v]);
    sim.step(1/60);
  }
  if(!sim.lap)throw Error('Unfinished circuit');
  const stop=sim.stopS%track.length;
  timeline.push([stop,0]);
  const frames=Array.from({length:track.N},(_,i)=>[...track.P.slice(i*3,i*3+3),...track.T.slice(i*3,i*3+3),...track.U.slice(i*3,i*3+3),track.kind[i]]);
  return {frames,ds:track.ds,timeline,station:findStation(track),stop,pitch,halfWidth:track.opts.halfWidth};
}
export async function author(app) {
  if(!app.started)app.begin(false);
  app.setMode('pro');
  return rides.map(r=>{
    construct(app.track,r);
    Object.assign(app.state.train,{theme:r.theme,body:r.body,accent:r.trim,cars:3,seat:'sit'});
    app.rebuildTrack();
    const save=app.serialize();
    app.applyData(save);
    return {id:r.id,save,runtime:bake(app.track,app.train.pitch)};
  });
}
