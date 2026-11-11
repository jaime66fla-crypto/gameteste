const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('public/player-art.js','utf8');
async function renderer(missing=false){
 const manifest={frameSize:96,frameCount:8,atlasFile:'operator-motion.png',idleFile:'operator-idle.png',directions:['east','southeast','south','southwest','west','northwest','north','northeast'],animations:{}};
 for(const motion of ['walk','run']){
  manifest.animations[motion]={};
  for(let n=0;n<(missing?7:8);n++)manifest.animations[motion][n]={row:n+(motion==='run'?8:0)};
 }
 class FakeImage{
  set src(value){this.path=value;this.naturalWidth=value.includes('animations/')?768:1800;this.naturalHeight=value.includes('operator-motion')?1536:value.includes('operator-idle')?96:900;queueMicrotask(()=>this.onload?.())}
 }
 const world={window:{gameProjection:{angle:a=>a,undo:()=>{}}},Image:FakeImage,performance:{now:()=>0},fetch:async()=>({ok:true,json:async()=>manifest})};
 vm.runInNewContext(source,world);
 await new Promise(r=>setImmediate(r));await new Promise(r=>setImmediate(r));
 return world.window.playerArt;
}
(async()=>{
 const art=await renderer();
 const calls=[];
 const ctx=new Proxy({drawImage(...args){calls.push(args)}},{get:(target,key)=>target[key]||(()=>{})});
 const opts={x:100,y:100,angle:0,gunAngle:0,weapon:'pistol',moving:true,running:false,phase:0};
 assert(art.draw(ctx,opts,()=>{}));const first=calls.at(-1);
 art.draw(ctx,{...opts,phase:1.8},()=>{});const next=calls.at(-1);
 assert(first[0].path.includes('operator-motion.png'));assert.equal(first[2],0);assert.notEqual(first[1],next[1]);
 assert.equal(first[6],next[6],'Feet anchor drifts between animation frames');
 art.draw(ctx,{...opts,running:true},()=>{});assert.equal(calls.at(-1)[2],8*96);
 art.draw(ctx,{...opts,moving:false},()=>{});assert(calls.at(-1)[0].path.includes('operator-idle.png'));
 const incomplete=await renderer(true);incomplete.draw(ctx,opts,()=>{});
 assert(calls.at(-1)[0].path.includes('operator-directions.png'),'Incomplete eight-direction sets must use safe fallback');
 console.log('Player animation frame playback, running, idle fallback, fixed anchor and incomplete asset fallback passed.');
})().catch(e=>{console.error(e);process.exitCode=1});
