/* Sprite rendering only: collision, aiming and damage stay in game.js. */
window.worldArt=(()=>{
 const images={},ready={};
 for(const name of ['units','equipment']){
  const img=images[name]=new Image();
  img.onload=()=>{ready[name]=true;if(name==='equipment')paintGallery()};
  img.onerror=()=>{ready[name]=false};
  img.src='assets/world/'+name+'.png';
 }
 const data=()=>window.worldArtFrames;
 const direction=a=>(Math.round((window.gameProjection?.angle(a)??a)/(Math.PI/2))+4)%4;
 function blit(ctx,sheet,f,x,y,w,h){
  ctx.drawImage(images[sheet],...f,x,y,w,h);
 }
 function upright(ctx,x,y){ctx.translate(x,y);window.gameProjection?.undo(ctx)}
 function entity(ctx,kind,o){
  if(!ready.units||!data())return false;
  const row={enemy:0,sniper:1,jeep:2,boss:3}[kind];
  if(row===undefined)return false;
  const f=data().units[row*4+direction(o.angle||0)];
  const scale=(o.size||58)/data().unitHeights[row];
  const w=f[2]*scale,h=f[3]*scale;
  const bob=o.moving?Math.abs(Math.sin(o.phase||0))*.9:0;
  ctx.save();upright(ctx,o.x,o.y);
  ctx.fillStyle='rgba(0,0,0,.38)';ctx.beginPath();ctx.ellipse(3,7,w*.43,kind==='boss'?12:kind==='jeep'?9:4.5,0,0,Math.PI*2);ctx.fill();
  if(o.damaged)ctx.filter='brightness(.65) saturate(.5)';
  if(o.hit)ctx.filter='brightness(1.6) sepia(.4)';
  const baseline=kind==='jeep'||kind==='boss'?h*.62:h-8;
  blit(ctx,'units',f,-w/2,-baseline-bob,w,h);ctx.restore();
  return true;
 }
 const names=['pistol','smg','shotgun','rifle','lmg','sawedoff'];
 function effect(ctx,name,x,y,size,alpha=1){
  if(!ready.equipment||!data())return false;
  const index={muzzle:6,explosion:7,wreck:8}[name],f=data().equipment[index];
  if(!f)return false;
  const scale=size/Math.max(f[2],f[3]);
  ctx.save();upright(ctx,x,y);ctx.globalAlpha*=Math.max(0,Math.min(1,alpha));
  blit(ctx,'equipment',f,-f[2]*scale/2,-f[3]*scale*.65,f[2]*scale,f[3]*scale);ctx.restore();return true;
 }
 function weapon(ctx,type,x,y,scale,muzzle){
  if(!ready.equipment||!data())return false;
  const index=names.indexOf(type);if(index<0)return false;
  const f=data().equipment[index],tip=type==='pistol'?27:type==='smg'?50:56;
  const width=type==='pistol'?54:type==='smg'?100:112;
  const h=f[3]*width/f[2];
  ctx.save();ctx.translate(x,y);ctx.scale(scale,scale);
  blit(ctx,'equipment',f,tip-width,-h*.32,width,h);
  if(muzzle){
   const flash=data().equipment[6],s=34/flash[2];
   blit(ctx,'equipment',flash,tip,-flash[3]*s/2,34,flash[3]*s);
  }
  ctx.restore();return true;
 }
 function paintGallery(){
  if(!data())return;
  document.querySelectorAll('.weapon-card .weapon-art').forEach((el,index)=>{
   const f=data().equipment[index];if(!f)return;
   const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg'),img=document.createElementNS(ns,'image');
   svg.setAttribute('viewBox',f.join(' '));svg.setAttribute('class','weapon-svg');
   svg.setAttribute('role','img');svg.setAttribute('aria-label',el.closest('.weapon-card').querySelector('h3').textContent);
   img.setAttribute('href',images.equipment.src);img.setAttribute('width',images.equipment.naturalWidth);img.setAttribute('height',images.equipment.naturalHeight);
   svg.append(img);el.replaceChildren(svg);
  });
 }
 return {entity,weapon,effect,direction,get ready(){return !!(ready.units&&ready.equipment&&data())}};
})();
