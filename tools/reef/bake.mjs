import fs from 'node:fs';
import path from 'node:path';
if (!process.argv[2]) throw new Error('Pass the Abyssal Garden source/src directory');
const base = path.resolve(process.argv[2]) + path.sep;
fs.mkdirSync('build/reef', { recursive: true });
const math=fs.readFileSync(base+'math.js','utf8'),world=fs.readFileSync(base+'world.js','utf8');
const bake=Function('save',math+'\nconst LV=1;\n'+world.slice(world.indexOf('function meshChunk'))+`
for(const [name,m] of Object.entries({wreck:meshShip().build(),fluke:meshFluke(),manta:meshManta().build(),fish:meshFish().build(),rock:meshChunk(5,2).build(),coral:meshCoral(1,true).build(),sponge:meshLathe([[0,0,.45],[.43,.08,.55],[.55,.26,.85],[.51,.8,1],[.41,1,1],[.32,1,.7],[.26,.68,.35],[0,.4,.05]],16,.32,9).build()}))save(name,m);`);
bake((name,m)=>{const head=Buffer.alloc(8);head.writeUInt32LE(m.nv);head.writeUInt32LE(m.ib.length,4);fs.writeFileSync('build/reef/'+name+'.bin',Buffer.concat([head,Buffer.from(m.vb),Buffer.from(m.ib.buffer,m.ib.byteOffset,m.ib.byteLength)]))});
