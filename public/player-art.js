/* Upright eight-direction player art. Physics stays on the XY plane. */
window.playerArt=(()=>{
 const image=new Image();
 let ready=false;
 image.onload=()=>{ready=true};
 image.onerror=()=>{ready=false};
 image.src='assets/player/operator-directions.png';
 // Tight alpha bounds, common pixels-per-unit scale: no direction is stretched.
 const frames=[
  [110,28,254,398,332,220], [547,32,244,390,711,244],
  [996,19,226,382,1109,240], [1427,32,239,390,1504,244],
  [119,471,246,397,151,667], [555,472,238,381,594,648],
  [990,470,238,373,1109,654], [1425,473,234,379,1608,645]
 ];
 const scale=57/398;
 const clips={};
 // Activate a complete set atomically; loading errors keep the original character usable.
 const loadAtlas=(name,width,height)=>new Promise(resolve=>{
  if(!/^[-a-z]+\.png$/.test(name||''))return resolve(null);
  const sprite=new Image();sprite.onload=()=>resolve(sprite.naturalWidth===width&&sprite.naturalHeight===height?sprite:null);
  sprite.onerror=()=>resolve(null);sprite.src='assets/player/animations/'+name;
 });
 fetch('assets/player/animations/manifest.json?v=pixellab-1').then(r=>r.ok?r.json():null).then(async manifest=>{
  if(!manifest||manifest.frameSize!==96||manifest.frameCount!==8)return;
  for(const motion of ['walk','run']){
   const entries=manifest.animations?.[motion];
   if(!entries||Object.keys(entries).length!==8)return;
   for(let i=0;i<8;i++)if(entries[String(i)]?.row!==i+(motion==='run'?8:0))return;
  }
  const [motion,idle]=await Promise.all([loadAtlas(manifest.atlasFile,768,1536),loadAtlas(manifest.idleFile,768,96)]);
  if(!motion||!idle)return;
  clips.walk=Array.from({length:8},(_,row)=>({image:motion,row,x:0}));
  clips.run=Array.from({length:8},(_,i)=>({image:motion,row:8+i,x:0}));
  clips.idle=Array.from({length:8},(_,i)=>({image:idle,row:0,x:i*96}));
 }).catch(()=>{});
 const direction=angle=>{
  const a=(window.gameProjection?.angle(angle)??angle);
  return (Math.round(a/(Math.PI/4))+8)%8;
 };
 function pose(angle){
  const index=direction(angle),f=frames[index];
  return {index,x:(f[4]-f[0]-f[2]/2)*scale,y:10+(f[5]-f[1]-f[3])*scale};
 }
 function draw(ctx,opts,weaponRenderer){
  if(!ready)return false;
  const p=pose(opts.angle),f=frames[p.index],gait=opts.moving?Math.sin(opts.phase||0):0;
  const motion=opts.running?'run':'walk',clip=opts.moving?clips[motion]?.[p.index]:clips.idle?.[p.index];
  const bob=clip?(opts.moving?0:Math.sin(performance.now()/550)*.35):opts.moving?Math.abs(gait)*(opts.running?1.6:.85):Math.sin(performance.now()/550)*.35;
  ctx.save();ctx.translate(opts.x,opts.y);
  // Inverse world shear / tilt keeps the sprite upright and correctly proportioned.
  window.gameProjection?.undo(ctx);
  ctx.fillStyle='rgba(0,0,0,.35)';ctx.beginPath();ctx.ellipse(0,10,14,4.5,0,0,Math.PI*2);ctx.fill();
  const gun=()=>{
   ctx.save();ctx.translate(p.x,p.y);ctx.rotate(opts.gunAngle);
   weaponRenderer(opts.weapon,0,0,.32,opts.shooting);ctx.restore();
  };
  const behind=p.index>=5;
  if(behind)gun();
  ctx.save();ctx.imageSmoothingEnabled=true;
  if(opts.hit)ctx.filter='brightness(1.7) sepia(.45)';
  if(clip){
   const frame=opts.moving?((Math.floor((opts.phase||0)/9*(opts.running?9:10))%8)+8)%8:0;
   const animationScale=scale*512/96;
   ctx.imageSmoothingEnabled=false;
   ctx.drawImage(clip.image,clip.x+frame*96,clip.row*96,96,96,-48*animationScale,10-90.75*animationScale-bob,96*animationScale,96*animationScale);
  }else ctx.drawImage(image,f[0],f[1],f[2],f[3],-f[2]*scale/2,10-f[3]*scale-bob,f[2]*scale,f[3]*scale);
  ctx.restore();
  if(!behind)gun();
  ctx.restore();return true;
 }
 return {get ready(){return ready},direction,pose,draw};
})();
