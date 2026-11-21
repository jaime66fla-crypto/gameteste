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
 let h=mountainHeight+coastHeight(x,z);
 const river=riverSample(x,z),width=world.hydrology?.river.width||9;
 if(river.distance<width+13)h=Math.min(h,river.level-2.0+2*Math.pow(river.distance/width,2));
 for(const b of [...world.ponds,...(world.hydrology?.floodplains||[])])h=Math.min(h,basinHeight(b,x,z));
 return h;
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
