import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
const [root, refPath, perfPath, slowPath, unrelatedPath, output] = process.argv.slice(2);
if (!output) throw new Error('Usage: node evaluate_reference.mjs SCORE_FLIP REF.f32 PERF.f32 SLOW.f32 UNRELATED.f32 OUTPUT.json');
const {extractAll}=await import(pathToFileURL(path.resolve(root,'src/audio/features.js')));
const {Tracker}=await import(pathToFileURL(path.resolve(root,'src/audio/tracker.js')));
const {measureContrast}=await import(pathToFileURL(path.resolve(root,'src/audio/reference.js')));
const read=p=>{const b=fs.readFileSync(p);return new Float32Array(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));};
const a=read(refPath),b=read(perfPath);
const flatten=frames=>({frames:Float32Array.from(frames.flatMap(v=>Array.from(v))),frameCount:frames.length,binCount:frames[0].length});
const featsA=extractAll(a),featsB=extractAll(b);
const cases=[];
for(const [name,samples,gtScale,groundTruth] of [
 ['self',a,1,true],
 ['same_recording_pitch_preserving_atempo_0.8',read(slowPath),0.8,true],
 ['second_performance',b,null,false],
 ['unrelated_piece',read(unrelatedPath).slice(0,a.length),null,false],
 ['silence',new Float32Array(a.length),null,false],
]){
 const features=extractAll(samples);const t=new Tracker(featsA);const rows=[];const started=performance.now();
 for(let i=0;i<features.length;i++){const r=t.step(features[i]);rows.push({t:i*.02,ref:r.position*.02,confidence:r.confidence,silent:r.silent});}
 const voiced=rows.filter(r=>!r.silent);const valid=voiced.filter(r=>r.t>2);
 const result={name,seconds:samples.length/24000,inference_ms:performance.now()-started,ground_truth:groundTruth,
  mean_confidence:voiced.length?voiced.reduce((a,b)=>a+b.confidence,0)/voiced.length:0,
  final_reference_s:rows.at(-1).ref,voiced_frames:voiced.length,rows};
 if(groundTruth){const errors=valid.map(r=>Math.abs(r.ref-r.t*gtScale)).sort((a,b)=>a-b);result.median_error_s=errors[Math.floor(errors.length*.5)];result.p90_error_s=errors[Math.floor(errors.length*.9)];}
 cases.push(result);
}
const result={source_commit:'fb0e5c166632a65e287f0e134e8656c09796a48c',contrast:[measureContrast(flatten(featsA)),measureContrast(flatten(featsB))],cases};
fs.writeFileSync(output,JSON.stringify(result));
console.log(JSON.stringify({...result,cases:cases.map(({rows,...rest})=>rest)},null,2));
