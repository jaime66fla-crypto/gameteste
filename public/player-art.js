/* Upright eight-direction player art. Physics stays on the XY plane. */
window.playerArt=(()=>{
 const image=new Image();
 let ready=false;
 image.onload=()=>{ready=true};
 image.onerror=()=>{ready=false};
 image.src='assets/player/operator-directions.png';

 const directionNames=[
  'east','south-east','south','south-west',
  'west','north-west','north','north-east'
 ];
 const animationSheets={walk:[],run:[]};
 const animationReady={walk:[],run:[]};

 for(const mode of ['walk','run']){
  for(let i=0;i<8;i++){
   const img=new Image();
   animationReady[mode][i]=false;
   img.onload=()=>{animationReady[mode][i]=true};
   img.onerror=()=>{animationReady[mode][i]=false};
   img.src='assets/player/animations/'+mode+'-'+directionNames[i]+'.png';
   animationSheets[mode][i]=img;
  }
 }

 // Tight alpha bounds, common pixels-per-unit scale: no direction is stretched.
 const frames=[
  [110,28,254,398,332,220], [547,32,244,390,711,244],
  [996,19,226,382,1109,240], [1427,32,239,390,1504,244],
  [119,471,246,397,151,667], [555,472,238,381,594,648],
  [990,470,238,373,1109,654], [1425,473,234,379,1608,645]
 ];
 const scale=57/398;

 const direction=angle=>{
  const a=(window.gameProjection?.angle(angle)??angle);
  return (Math.round(a/(Math.PI/4))+8)%8;
 };

 function pose(angle){
  const index=direction(angle),f=frames[index];
  return {
   index,
   x:(f[4]-f[0]-f[2]/2)*scale,
   y:10+(f[5]-f[1]-f[3])*scale
  };
 }

 function motion(opts){
  if(!opts.moving){
   const idle=Math.sin(performance.now()/700);
   return {lift:idle*.22,sway:idle*.18,lean:idle*.0025,squash:1,gunLag:idle*.004};
  }
  const phase=opts.phase||0;
  const s=Math.sin(phase),c=Math.cos(phase),double=Math.sin(phase*2);
  const run=opts.running?1:0;
  return {
   lift:Math.abs(s)*(run?1.4:.7),
   sway:c*(run?.65:.32),
   lean:double*(run?.010:.006),
   squash:1-Math.max(0,-double)*(run?.010:.006),
   gunLag:-c*(run?.016:.009)
  };
 }

 function animatedFrame(opts,index){
  if(!opts.moving)return null;
  const mode=opts.running?'run':'walk';
  if(!animationReady[mode][index])return null;
  const phase=opts.phase||0;
  const cycle=Math.PI*2;
  const normalized=((phase%cycle)+cycle)%cycle/cycle;
  const frame=Math.floor(normalized*8)%8;
  return {image:animationSheets[mode][index],frame,mode};
 }

 function draw(ctx,opts,weaponRenderer){
  if(!ready)return false;
  const p=pose(opts.angle),f=frames[p.index],m=motion(opts);
  const anim=animatedFrame(opts,p.index);

  ctx.save();
  ctx.translate(opts.x,opts.y);
  window.gameProjection?.undo(ctx);

  const shadowScale=1-Math.min(.10,Math.abs(m.lift)*.03);
  ctx.save();
  ctx.scale(shadowScale,shadowScale);
  ctx.fillStyle='rgba(0,0,0,.35)';
  ctx.beginPath();
  ctx.ellipse(0,10,14,4.5,0,0,Math.PI*2);
  ctx.fill();
  ctx.restore();

  ctx.translate(m.sway,-m.lift);
  ctx.rotate(m.lean);
  ctx.scale(1,m.squash);

  const gun=()=>{
   ctx.save();
   ctx.translate(p.x,p.y);
   ctx.rotate(opts.gunAngle+m.gunLag);
   weaponRenderer(opts.weapon,0,0,.32,opts.shooting);
   ctx.restore();
  };

  const behind=p.index>=5;
  if(behind)gun();

  ctx.save();
  ctx.imageSmoothingEnabled=true;
  if(opts.hit)ctx.filter='brightness(1.7) sepia(.45)';

  if(anim){
   const size=72;
   ctx.drawImage(
    anim.image,
    anim.frame*96,0,96,96,
    -size/2,-62,size,size
   );
  }else{
   ctx.drawImage(
    image,
    f[0],f[1],f[2],f[3],
    -f[2]*scale/2,
    10-f[3]*scale,
    f[2]*scale,
    f[3]*scale
   );
  }

  ctx.restore();

  if(!behind)gun();
  ctx.restore();
  return true;
 }

 return {
  get ready(){return ready},
  direction,
  pose,
  draw,
  get animationsReady(){
   return animationReady.walk.filter(Boolean).length+animationReady.run.filter(Boolean).length;
  }
 };
})();
