import world from '../godot/data/survival_world.json' with {type:'json'};
export const smooth = (a,b,x) => {const t=Math.max(0,Math.min(1,(x-a)/(b-a)));return t*t*(3-2*t);};
export function weatherAt(elapsed) {
 const t=((elapsed/1000)%720+720)%720;
 const rain=t<90?0:t<120?smooth(90,120,t):t<300?1:t<360?1-smooth(300,360,t):0;
 const wet=t<90?0:t<360?smooth(90,360,t):1-smooth(360,720,t);
 return {elapsed:Math.max(0,elapsed),rain,wet};
}
export function coastHeight(x,z) {
 const a=Math.atan2(z,x),edge=Math.hypot(x,z);
 const shift=Math.sin(a*3)*7+Math.sin(a*7)*4;
 return -8*smooth(world.half_size-2+shift,world.half_size+75+shift,edge);
}
export function riverSample(x,z) {
 const pts=world.hydrology?.river.points||[];let best={distance:Infinity,level:-.45};
 for(let i=0;i<pts.length-1;i++){
  const a=pts[i],b=pts[i+1],dx=b[0]-a[0],dz=b[1]-a[1];
  const t=Math.max(0,Math.min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)));
  const d=Math.hypot(x-a[0]-dx*t,z-a[1]-dz*t);
  if(d<best.distance)best={distance:d,level:-.45-.65*(i+t)/(pts.length-1)};
 }
 return best;
}
export function basinState(b,wet) {
 const temporary=b.temporary===true;
 const level=temporary?-.95+wet*1.35:-.25+wet*.85;
 const threshold=temporary?-.65:-1.4;
 const radius=level<=threshold?0:b.r*Math.sqrt((level-threshold)/(1.55));
 return {surface:level,radius};
}
export function basinHeight(b,x,z) {
 const d=Math.hypot(x-b.x,z-b.z)/b.r;
 return d<1.4?(b.temporary?-.65:-1.4)+1.55*d*d:Infinity;
}
export function groundHeight(x,z,mountainHeight=0) {
 let h=mountainHeight+coastHeight(x,z)+relief(x,z);
 const river=riverSample(x,z),width=world.hydrology?.river.width||9;
 if(river.distance<width+13)h=Math.min(h,river.level-2.0+2*Math.pow(river.distance/width,2));
 for(const b of [...world.ponds,...(world.hydrology?.floodplains||[])])h=Math.min(h,basinHeight(b,x,z));
 return h;
}
/** Ondulações do terreno: mesma conta de relief() em hydrology.gd. */
export function reliefNoise(x,z) {
 return .45*Math.sin(.021*x+.7)*Math.cos(.017*z-1.3)
  +.4*Math.sin(.043*(.8*x+.6*z)+2.1)
  +.3*Math.cos(.061*(.8*z-.6*x)-.4)
  +.15*Math.sin(.11*x+.3)*Math.sin(.097*z+1.7);
}
const segDist=(x,z,a,b)=>{const dx=b[0]-a[0],dz=b[1]-a[1],l=dx*dx+dz*dz;const t=l?Math.max(0,Math.min(1,((x-a[0])*dx+(z-a[1])*dz)/l)):0;return Math.hypot(x-a[0]-dx*t,z-a[1]-dz*t);};
export function reliefMask(x,z) {
 const h=world.half_size,a=Math.atan2(z,x),shift=Math.sin(a*3)*7+Math.sin(a*7)*4;
 let m=1-smooth(h-40+shift,h-8+shift,Math.hypot(x,z));
 if(m<=0)return 0;
 for(const t of world.towns||[])m=Math.min(m,smooth(57,82,Math.hypot(x-t.center[0],z-t.center[1])));
 if(m<=0)return 0;
 for(const r of world.roads||[]){const half=(r.width??6)/2;m=Math.min(m,smooth(half+1.5,half+11,segDist(x,z,r.from,r.to)));}
 if(m<=0)return 0;
 const width=world.hydrology?.river.width||9;
 m=Math.min(m,smooth(width+8,width+24,riverSample(x,z).distance));
 for(const b of [...world.ponds,...(world.hydrology?.floodplains||[])]){const r=b.r*1.3;m=Math.min(m,smooth(r,r+12,Math.hypot(x-b.x,z-b.z)));}
 return m;
}
export function relief(x,z) {
 const m=reliefMask(x,z);
 if(m<=0)return 0;
 const n=reliefNoise(x,z)+.6;
 return m*(.7*n+(n>0?1.8*n*n:0));
}
export function waterAt(x,z,wet=0) {
 let result=null;
 if(coastHeight(x,z)<-1.1)result={surface:-1.1,fresh:false};
 const river=riverSample(x,z),width=world.hydrology?.river.width||9;
 const surface=river.level+wet*1.15;
 if(!result&&river.distance<width*Math.sqrt(1+wet*.575))result={surface,fresh:true};
 for(const b of [...world.ponds,...(world.hydrology?.floodplains||[])]){
  const state=basinState(b,wet);
  if(state.radius>0&&Math.hypot(x-b.x,z-b.z)<state.radius&&(!result||state.surface>result.surface))result={surface:state.surface,fresh:true};
 }
 return result;
}
