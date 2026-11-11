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
   // Feet contact feels heavier: most vertical motion happens between steps.
   lift:Math.abs(s)*(run?2.25:1.2),
   // Small side-to-side weight transfer makes the torso stop looking pinned.
   sway:c*(run?1.45:.78),
   // Torso lean follows the stride, intentionally very subtle.
   lean:double*(run?.018:.010),
   // Tiny squash on impact gives the static source art some step cadence.
   squash:1-Math.max(0,-double)*(run?.018:.010),
   // Weapon trails the shoulder a fraction instead of feeling welded to the body.
   gunLag:-c*(run?.020:.011)
  };
 }

 function draw(ctx,opts,weaponRenderer){
  if(!ready)return false;
  const p=pose(opts.angle),f=frames[p.index],m=motion(opts);

  ctx.save();
  ctx.translate(opts.x,opts.y);

  // Inverse world shear / tilt keeps the sprite upright and correctly proportioned.
  window.gameProjection?.undo(ctx);

  // Ground shadow reacts to the step height.
  const shadowScale=1-Math.min(.14,Math.abs(m.lift)*.035);
  ctx.save();
  ctx.scale(shadowScale,shadowScale);
  ctx.fillStyle='rgba(0,0,0,.35)';
  ctx.beginPath();
  ctx.ellipse(0,10,14,4.5,0,0,Math.PI*2);
  ctx.fill();
  ctx.restore();

  // Whole-body movement layer. This is visual-only; collisions stay untouched.
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
  ctx.drawImage(
   image,
   f[0],f[1],f[2],f[3],
   -f[2]*scale/2,
   10-f[3]*scale,
   f[2]*scale,
   f[3]*scale
  );
  ctx.restore();

  if(!behind)gun();
  ctx.restore();
  return true;
 }

 return {get ready(){return ready},direction,pose,draw};
})();
