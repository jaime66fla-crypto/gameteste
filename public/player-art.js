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
  return {index,x:(f[4]-f[0]-f[2]/2)*scale,y:10+(f[5]-f[1]-f[3])*scale};
 }
 function draw(ctx,opts,weaponRenderer){
  if(!ready)return false;
  const p=pose(opts.angle),f=frames[p.index],gait=opts.moving?Math.sin(opts.phase||0):0;
  const bob=opts.moving?Math.abs(gait)*(opts.running?1.6:.85):0;
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
  ctx.drawImage(image,f[0],f[1],f[2],f[3],-f[2]*scale/2,10-f[3]*scale-bob,f[2]*scale,f[3]*scale);
  ctx.restore();
  if(!behind)gun();
  ctx.restore();return true;
 }
 return {get ready(){return ready},direction,pose,draw};
})();
