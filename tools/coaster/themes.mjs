import {THEME_PRESETS,generateTrack,autoScenes} from './js/generator.js';
import {bake} from './author.mjs';
export const additions=[
  ['crystal-mine','mine',0,'minetrain',0],
  ['neon-wings','neon',2,'launch',2],
  ['phantom-castle','castle',2,'thrill',0]
];
export async function buildThemes(app){
  app.setMode('pro');
  return additions.map(([id,theme,trainIndex,layout,trackIndex])=>{
    const preset=THEME_PRESETS.find(p=>p.id===theme);
    Object.assign(app.state.train,preset.trains[trainIndex],{cars:3});
    Object.assign(app.state.scene,{env:preset.envs[0],time:preset.time[0],weather:'clear'});
    Object.assign(app.track.opts,preset.tracks[trackIndex],{liftSpeed:10});
    app.buildTrain(false);
    for(let seed=1;seed<=300;seed++){
      generateTrack(app.track,layout,seed,{layout:'organic'});
      if(app.track.analysis.warnings.length)continue;
      const tr=app.track;
      const flat=tr.T.filter((v,i)=>i%3===1&&Math.abs(v)<Math.sin(Math.PI*8/180)).length/tr.N;
      if(flat>=.30 || !autoScenes(tr,theme,.32))continue;
      app.rebuildTrack();
      const save=app.serialize();
      app.applyData(save);
      if(app.track.analysis.warnings.length)continue;
      const runtime=bake(app.track,app.train.pitch);
      runtime.seat=save.train.seat;
      runtime.eye=app.train.eye.position.toArray();
      runtime.railColor=save.track.opts.railColor;
      runtime.supportColor=save.track.opts.supportColor;
      runtime.scenes=Array.from(app.track.scene);
      console.log(id,seed,flat,runtime.eye,app.track.analysis.maxDrop);
      return {id,save,runtime,analysis:{
        seed,drop:tr.analysis.maxDrop,inversions:tr.analysis.inversions,
        topSpeed:Math.max(...runtime.timeline.map(pair=>pair[1])),
        lapTime:(runtime.timeline.length-1)/20,warnings:tr.analysis.warnings
      }};
    }
    throw Error('Missing suitable circuit '+id);
  });
}
