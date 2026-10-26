import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
const [root,refPath,perfPath,unrelatedPath]=process.argv.slice(2);
if(!unrelatedPath)throw new Error('Usage: node negative_control.mjs SCORE_FLIP REF.f32 PERF.f32 UNRELATED.f32');
const {extractAll}=await import(pathToFileURL(path.resolve(root,'src/audio/features.js')));
const {Follower}=await import(pathToFileURL(path.resolve(root,'src/audio/follower.js')));
const read=p=>{const b=fs.readFileSync(p);return new Float32Array(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));};
const ref=extractAll(read(refPath));
const reference={frames:Float32Array.from(ref.flatMap(v=>Array.from(v))),frameCount:ref.length,binCount:ref[0].length,
 turnPoints:[{page:0,frame:0},{page:1,frame:500},{page:2,frame:1000}]};
for(const [name,file] of [['second_performance',perfPath],['unrelated_piece',unrelatedPath]]){
 const f=new Follower(reference);const turns=[];let last=0;
 const features=extractAll(read(file).slice(0,Math.round(35*24000)));
 for(let i=0;i<features.length;i++){const r=f.step(features[i]);if(r.page!==last){turns.push({t:i*.02,page:r.page,confidence:r.confidence,smoothed:f.smoothed});last=r.page;}}
 console.log(JSON.stringify({name,marks_are_test_only:true,turns}));
}
