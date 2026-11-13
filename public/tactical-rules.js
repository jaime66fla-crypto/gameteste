/* Deterministic combat geometry shared by the browser and the room Worker. */
(()=>{'use strict';
const CONFIG=Object.freeze({fuse:2.8,radius:6,damage:120,gravity:16,speed:15,iceHealth:260,iceSeconds:25,grenades:3,ice:3});
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
function terrain(x,z){const d=Math.hypot(x,z);return d<=25?0:(Math.sin(x*.05)*Math.cos(z*.05)*2.5+Math.sin(x*.12+z*.1)*.8)*Math.min((d-25)/40,1);}
function mapBoxes(){
 const boxes=[],add=(x,y,z,w,h,d)=>boxes.push({minX:x-w/2,maxX:x+w/2,minY:y-h/2,maxY:y+h/2,minZ:z-d/2,maxZ:z+d/2});
 for(const [x,z,w,h,d]of[[0,14,12,5,8],[-16,-4,9,7,10],[17,-8,11,4.5,9],[0,-22,20,4.5,5]]){
  const y=terrain(x,z);add(x,y+h/2,z,w,h,d);add(x,y+h+.45,z,w*.85,.9,d*.85);
  for(const [dx,dy,dz,sw,sh,sd]of[[w/2+1.1,.6,d*.25,1.5,1.2,1.5],[w/2+1,1.25,-d*.15,1.5,2.5,1.5],[w/2+.85,3.65,-d*.35,1.7,.35,2],[w*.25,h-.15,-d/2-.75,2.2,.35,1.5]])add(x+dx,y+dy,z+dz,sw,sh,sd);
 }
 for(const [x,z]of[[-4,-3],[4,-5]])add(x,terrain(x,z)+.65,z,4,1.3,.75);
 return boxes;
}
function rayBox(origin,direction,box,max=Infinity,padding=0){
 let near=0,far=max;
 for(const a of ['x','y','z']){const lo=box['min'+a.toUpperCase()]-padding,hi=box['max'+a.toUpperCase()]+padding;
  if(Math.abs(direction[a])<1e-9){if(origin[a]<lo||origin[a]>hi)return null;continue;}
  let a0=(lo-origin[a])/direction[a],a1=(hi-origin[a])/direction[a];if(a0>a1)[a0,a1]=[a1,a0];near=Math.max(near,a0);far=Math.min(far,a1);if(near>far)return null;
 }
 return near;
}
function firstSolid(origin,direction,boxes,max=Infinity,padding=0){let found=null;for(const box of boxes){const distance=rayBox(origin,direction,box,max,padding);if(distance!==null&&(!found||distance<found.distance))found={box,distance};}return found;}
function blocked(from,to,boxes){const d={x:to.x-from.x,y:to.y-from.y,z:to.z-from.z},length=Math.hypot(d.x,d.y,d.z);if(length<.001)return false;for(const a of ['x','y','z'])d[a]/=length;return !!firstSolid(from,d,boxes,Math.max(0,length-.04));}
function surface(x,z,ceiling,boxes=[],height=terrain){let y=height(x,z);for(const b of boxes)if(x>=b.minX&&x<=b.maxX&&z>=b.minZ&&z<=b.maxZ&&b.maxY<=ceiling+.15)y=Math.max(y,b.maxY);return y;}
function grenade(id,ownerId,p,direction,now){
 const length=Math.hypot(direction.x,direction.y,direction.z);if(!Number.isFinite(length)||length<.5||length>1.5)return null;
 const d={x:direction.x/length,y:clamp(direction.y/length,-.6,.8),z:direction.z/length};
 return {id,ownerId,position:{x:p.x,y:p.y+1.35,z:p.z},velocity:{x:d.x*CONFIG.speed,y:d.y*CONFIG.speed+5,z:d.z*CONFIG.speed},age:0,createdAt:now,updatedAt:now,expiresAt:now+CONFIG.fuse*1000};
}
function advance(g,dt,boxes=[],height=terrain){
 let remaining=Math.min(Math.max(0,dt),CONFIG.fuse-g.age);
 while(remaining>1e-8){const step=Math.min(.0125,remaining),p=g.position,v=g.velocity,previous={...p};v.y-=CONFIG.gravity*step;
  const speed=Math.hypot(v.x,v.y,v.z),direction={x:v.x/(speed||1),y:v.y/(speed||1),z:v.z/(speed||1)};
  const hit=firstSolid(p,direction,boxes,speed*step,.12);
  if(hit){
   const travel=Math.max(0,hit.distance-.002);p.x+=direction.x*travel;p.y+=direction.y*travel;p.z+=direction.z*travel;
   const b=hit.box,distances=[['x',Math.min(Math.abs(p.x-(b.minX-.12)),Math.abs(p.x-(b.maxX+.12)))],['y',Math.min(Math.abs(p.y-(b.minY-.12)),Math.abs(p.y-(b.maxY+.12)))],['z',Math.min(Math.abs(p.z-(b.minZ-.12)),Math.abs(p.z-(b.maxZ+.12)))]];
   distances.sort((a,b)=>a[1]-b[1]);v[distances[0][0]]*=-.45;v.x*=.82;v.z*=.82;
   if(hit.distance===0){p.x=previous.x;p.y=previous.y;p.z=previous.z;v.x*=.5;v.z*=.5;}
  }else{p.x+=v.x*step;p.y+=v.y*step;p.z+=v.z*step;}
  const floor=height(p.x,p.z)+.12;
  if(p.y<floor){p.y=floor;v.y=Math.abs(v.y)>.9?Math.abs(v.y)*.34:0;v.x*=.76;v.z*=.76;}
  g.age+=step;remaining-=step;
 }
 return g;
}
function blastDamage(origin,target,boxes=[]){const p={x:target.x,y:target.y+.9,z:target.z},distance=Math.hypot(p.x-origin.x,p.y-origin.y,p.z-origin.z);if(distance>=CONFIG.radius||blocked(origin,p,boxes))return 0;return Math.ceil(CONFIG.damage*(1-distance/CONFIG.radius));}
function overlaps(a,b){return a.minX<b.maxX&&a.maxX>b.minX&&a.minY<b.maxY&&a.maxY>b.minY&&a.minZ<b.maxZ&&a.maxZ>b.minZ;}
function iceWall(id,ownerId,p,direction,now,boxes=[],players=[],height=terrain){
 const length=Math.hypot(direction.x,direction.z);if(!Number.isFinite(length)||length<.1)return null;
 const nx=direction.x/length,nz=direction.z/length,center={x:p.x+nx*3,y:0,z:p.z+nz*3};
 center.y=surface(center.x,center.z,p.y+.2,boxes,height);if(Math.abs(center.y-p.y)>.65)return null;
 if(blocked({x:p.x,y:p.y+1,z:p.z},{x:center.x,y:center.y+1,z:center.z},boxes))return null;
 const wall={id,ownerId,position:center,health:CONFIG.iceHealth,createdAt:now,expiresAt:now+CONFIG.iceSeconds*1000,boxes:[]};
 for(let i=-2;i<=2;i++){
  const x=center.x+nz*i*.75+nx*i*i*.04,z=center.z-nx*i*.75+nz*i*i*.04,h=2.55-Math.abs(i)*.2;
  if(Math.abs(surface(x,z,p.y+.2,boxes,height)-center.y)>.65)return null;
  const b={minX:x-.46,maxX:x+.46,minY:center.y,maxY:center.y+h,minZ:z-.46,maxZ:z+.46,iceWallId:id};
  if(boxes.some(old=>overlaps(b,old))||players.some(person=>overlaps(b,{minX:person.x-.5,maxX:person.x+.5,minY:person.y,maxY:person.y+1.85,minZ:person.z-.5,maxZ:person.z+.5})))return null;
  wall.boxes.push(b);
 }
 return wall;
}
globalThis.TacticalRules={CONFIG,terrain,mapBoxes,rayBox,firstSolid,blocked,surface,grenade,advance,expired:g=>g.age>=CONFIG.fuse-1e-6,blastDamage,iceWall,overlaps};
})();
