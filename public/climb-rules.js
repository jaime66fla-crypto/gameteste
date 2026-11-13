/* Climbing rules shared by game and Node tests. Coordinates use feet at y. */
(function(root,factory){
 const api=factory();
 if(typeof module==='object'&&module.exports)module.exports=api;
 root.ClimbRules=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
 'use strict';
 const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
 function findLedge(boxes,position,forward,options={}){
  const radius=options.radius??.45;
  const reach=options.reach??.90;
  const maxRise=options.maxRise??2.65;
  const minRise=options.minRise??.52;
  const fx=Number(forward.x)||0,fz=Number(forward.z)||0;
  const len=Math.hypot(fx,fz);
  if(len<.001)return null;
  const dx=fx/len,dz=fz/len;
  let best=null,bestScore=-Infinity;
  for(const box of boxes){
   const rise=box.maxY-position.y;
   if(rise<minRise||rise>maxRise)continue;
   // Detect the approaching face, never a top surface or a wall behind us.
   const faces=[
    {axis:'x',side:-1,at:box.minX,nx:-1,nz:0,otherMin:box.minZ,otherMax:box.maxZ},
    {axis:'x',side:1,at:box.maxX,nx:1,nz:0,otherMin:box.minZ,otherMax:box.maxZ},
    {axis:'z',side:-1,at:box.minZ,nx:0,nz:-1,otherMin:box.minX,otherMax:box.maxX},
    {axis:'z',side:1,at:box.maxZ,nx:0,nz:1,otherMin:box.minX,otherMax:box.maxX}
   ];
   for(const f of faces){
    const toward=-(dx*f.nx+dz*f.nz);
    if(toward<.55)continue;
    const along=f.axis==='x'?position.z:position.x;
    if(along<f.otherMin+radius||along>f.otherMax-radius)continue;
    const foot=f.axis==='x'?position.x:position.z;
    const signed=(foot-f.at)*f.side;
    if(signed < -radius*.25||signed>reach+radius)continue;
    const landing={
     x:f.axis==='x'?f.at-f.nx*(radius+.14):clamp(position.x+dx*.62,box.minX+radius,box.maxX-radius),
     y:box.maxY,
     z:f.axis==='z'?f.at-f.nz*(radius+.14):clamp(position.z+dz*.62,box.minZ+radius,box.maxZ-radius)
    };
    // The landing must be on the top, well inside the supporting box.
    landing.x=clamp(landing.x,box.minX+radius,box.maxX-radius);
    landing.z=clamp(landing.z,box.minZ+radius,box.maxZ-radius);
    if(box.maxX-box.minX<radius*2||box.maxZ-box.minZ<radius*2)continue;
    const blocked=boxes.some(other=>other!==box&&
      landing.x+radius>other.minX&&landing.x-radius<other.maxX&&
      landing.z+radius>other.minZ&&landing.z-radius<other.maxZ&&
      other.minY<landing.y+1.8&&other.maxY>landing.y+.18);
    if(blocked)continue;
    const score=toward*2-Math.max(0,signed)*.7-rise*.04;
    if(score>bestScore){bestScore=score;best={landing,rise,face:f.axis,normal:{x:f.nx,z:f.nz}};}
   }
  }
  return best;
 }
 function smoothstep(t){t=clamp(t,0,1);return t*t*(3-2*t);}
 function climbPosition(start,target,progress){
  const t=smoothstep(progress),lift=Math.sin(Math.PI*t)*.30;
  return {x:start.x+(target.x-start.x)*t,y:start.y+(target.y-start.y)*t+lift,z:start.z+(target.z-start.z)*t};
 }
 return {findLedge,climbPosition};
});
