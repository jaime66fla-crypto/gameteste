/* Approved 18-bone motion, adapted without DOM or physics ownership. */
(()=>{
'use strict';
const I=()=>[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
const T=(x,y,z)=>{let m=I();m[12]=x;m[13]=y;m[14]=z;return m};
function mul(a,b){let o=Array(16).fill(0);for(let c=0;c<4;c++)for(let r=0;r<4;r++)for(let k=0;k<4;k++)o[c*4+r]+=a[k*4+r]*b[c*4+k];return o}
function RX(a){let c=Math.cos(a),s=Math.sin(a);return[1,0,0,0,0,c,s,0,0,-s,c,0,0,0,0,1]}
function RY(a){let c=Math.cos(a),s=Math.sin(a);return[c,0,-s,0,0,1,0,0,s,0,c,0,0,0,0,1]}
function RZ(a){let c=Math.cos(a),s=Math.sin(a);return[c,s,0,0,-s,c,0,0,0,0,1,0,0,0,0,1]}
const norm=v=>{let l=Math.hypot(...v)||1;return v.map(a=>a/l)};
const sub=(a,b)=>a.map((v,i)=>v-b[i]);
const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const sp=(v,e)=>Math.sign(v)*Math.pow(Math.abs(v),e);
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
// Pelvis, spine, chest, neck, head, arms, hands, legs and feet.
const parents=[-1,0,1,2,3,4,3,6,7,3,9,10,1,12,13,1,15,16];
const offsets=[
[0,0,0],[0,1.045,0],[0,.22,0],[0,.205,0],[0,.18,0],[0,.14,0],
[-.178,.020,0],[-.065,-.30,.012],[-.032,-.242,.036],
[.178,.020,0],[.065,-.30,.012],[.032,-.242,.036],
[-.101,-.02,0],[-.017,-.428,.012],[-.006,-.397,.035],
[.101,-.02,0],[.017,-.428,.012],[.006,-.397,.035]
];
const bind=[],inverseBind=[];
for(let i=0;i<18;i++){
 bind[i]=parents[i]<0?T(...offsets[i]):mul(bind[parents[i]],T(...offsets[i]));
 inverseBind[i]=T(-bind[i][12],-bind[i][13],-bind[i][14]);
}
// BEGIN BIOMECHANICS — angles in radians, translations in model units.
let rootBob=0;
const rootShift=[0,0,0];
const weaponAngles=[.38,0,0];
let currentWeaponMatrix=I();
let motionPose='idle',motionTime=0;
const TAU_MOTION=Math.PI*2;
const motionDuration={idle:4,walk:1.15,run:.84,jump:1.8,aim:4};
const fractMotion=x=>x-Math.floor(x);
const smoothMotion=x=>{x=clamp(x,0,1);return x*x*(3-2*x)};
const damp=(a,b,lambda,dt)=>a+(b-a)*(-Math.expm1(-lambda*dt));
function hermiteMotion(a,b,va,vb,t,span){
 const t2=t*t,t3=t2*t;
 return (2*t3-3*t2+1)*a+(t3-2*t2+t)*span*va+(-2*t3+3*t2)*b+(t3-t2)*span*vb;
}
// Zero endpoint tangents provide C1 continuity, including the loop seam.
function curveMotion(keys,p){
 for(let i=1;i<keys.length;i++)if(p<=keys[i][0]){
  let a=keys[i-1],b=keys[i],u=clamp((p-a[0])/(b[0]-a[0]),0,1);
  return a[1]+(b[1]-a[1])*smoothMotion(u);
 }
 return keys[keys.length-1][1];
}
function neutralMotion(){
 const r=Array.from({length:18},()=>[0,0,0]);
 r[6][2]=.045;r[9][2]=-.045;r[7][0]=r[10][0]=-.16;
 return {r,root:[0,0,0]};
}
function stabilizeMotion(r,strength){
 for(let axis=0;axis<3;axis++){
  const total=r[1][axis]+r[2][axis]+r[3][axis];
  r[4][axis]=-total*strength*.65;
  r[5][axis]=-total*strength*.35;
 }
}
// The rifle and both grip targets live in the chest's bind coordinate frame.
// Analytic two-bone IK uses the existing arm bones; no new bones are introduced.
function armUnit(v){const l=Math.hypot(...v)||1;return v.map(x=>x/l)}
function armDot(a,b){return a.reduce((s,v,i)=>s+v*b[i],0)}
function armCross(a,b){return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
function alignArm(from,to){
 const a=armUnit(from),b=armUnit(to),v=armCross(a,b),c=clamp(armDot(a,b),-1,1),k=1/Math.max(1+c,1e-6),[x,y,z]=v;
 return[1-(y*y+z*z)*k,z+x*y*k,-y+x*z*k,0,-z+x*y*k,1-(x*x+z*z)*k,x+y*z*k,0,y+x*z*k,-x+y*z*k,1-(x*x+y*y)*k,0,0,0,0,1];
}
function transposeArm(m){return[m[0],m[4],m[8],0,m[1],m[5],m[9],0,m[2],m[6],m[10],0,0,0,0,1]}
function armVector(m,v){return[0,1,2].map(i=>m[i]*v[0]+m[4+i]*v[1]+m[8+i]*v[2])}
function armEuler(m){
 const y=Math.asin(clamp(-m[2],-1,1));
 return Math.abs(Math.cos(y))>1e-6?[Math.atan2(m[6],m[10]),y,Math.atan2(m[1],m[0])]:[Math.atan2(-m[9],m[5]),y,0];
}
const rifleAnchor=[.055,1.36,.30];
// The visible face and chest point toward +Z: anatomical right is -X.
const rifleShift=[-.205,.085,.082];
// Negative-X trigger hand grips near the receiver; positive-X support hand grips\n // farther up the fore-end to avoid overlapping wrists during tactical ADS.
const rifleGrips=[[6,[.060,1.305,.255],-1],[9,[.125,1.315,.475],1]];
function weaponFrame(angles,weaponId='rifle',aimBlend=0){
 // ADS rifle posture: bring the stock to the right shoulder and sight line.
 // Both IK wrists and the weapon inherit exactly the same transform.
 const pistol=weaponId==='pistol';
 const longGun=!pistol;
 const ads=clamp(aimBlend,0,1);
 // Ready stance is already shouldered, at chest height, without looking down
 // the sights. ADS raises it the remaining distance to eye level.
 const lift=pistol?.15:(longGun?.082+.102*ads:0);
 const reach=pistol?.075:(longGun?.050+.026*ads:0);
 return mul(T(rifleAnchor[0]+rifleShift[0],rifleAnchor[1]+rifleShift[1]+lift,rifleAnchor[2]+rifleShift[2]+reach),
  mul(RZ(angles[2]),mul(RY(angles[1]),mul(RX(angles[0]),T(-rifleAnchor[0],-rifleAnchor[1],-rifleAnchor[2])))));
}
function pointArm(matrix,p){return armVector(matrix,p).map((v,i)=>v+matrix[12+i])}
function armedMotion(r,frame,grips=rifleGrips){
 for(const [upper,grip,side] of grips){
  const target=pointArm(frame,grip).map((v,i)=>v-bind[3][12+i]);
  const fore=upper+1,hand=upper+2,shoulder=offsets[upper];
  const delta=target.map((v,i)=>v-shoulder[i]),len=Math.hypot(...delta),d=armUnit(delta);
  const a=Math.hypot(...offsets[fore]),b=Math.hypot(...offsets[hand]);
  const distance=clamp(len,Math.abs(a-b)+.001,a+b-.001);
  const along=(a*a-b*b+distance*distance)/(2*distance),height=Math.sqrt(Math.max(0,a*a-along*along));
  const pole=[side*.32,-.74,-.12],projection=armDot(pole,d);
  const bend=armUnit(pole.map((v,i)=>v-d[i]*projection));
  const elbow=shoulder.map((v,i)=>v+d[i]*along+bend[i]*height);
  const upperMatrix=alignArm(offsets[fore],elbow.map((v,i)=>v-shoulder[i]));
  const foreDirection=armVector(transposeArm(upperMatrix),target.map((v,i)=>v-elbow[i]));
  const foreMatrix=alignArm(offsets[hand],foreDirection);
  r[upper]=armEuler(upperMatrix);r[fore]=armEuler(foreMatrix);
  // Keep the wrists oriented to the receiver and fore-end, rather than flapping.
  const rotation=frame.slice();rotation[12]=rotation[13]=rotation[14]=0;
  const wristFrame=mul(rotation,mul(RY(side===1?-.20:.25),RX(-1.35)));
  r[hand]=armEuler(mul(transposeArm(mul(upperMatrix,foreMatrix)),wristFrame));
 }
}
const pistolGrips=[[6,[.055,1.30,.24],-1],[9,[.105,1.30,.245],1]];
function sampleMotion(state,phase,armed=true,weaponId='rifle'){
 const p=fractMotion(phase),q=TAU_MOTION*p,m=neutralMotion(),r=m.r;
 if(state==='walk'){
  // Stance occupies 62% of a leg cycle; the remaining 38% is a faster swing.
  for(let side=0;side<2;side++){
   const f=fractMotion(p+side*.5),support=f<.62;
   const u=support?.5*f/.62:.5+.5*(f-.62)/.38;
   const a=TAU_MOTION*u,hip=side?15:12,knee=hip+1,ankle=hip+2;
   r[hip][0]=-.32*Math.cos(a)+.055*Math.pow(Math.sin(a),3);
   const load=.105*Math.exp(-Math.pow((f-.09)/.065,2));
   const swing=support?0:Math.pow(Math.sin(Math.PI*(f-.62)/.38),2);
   r[knee][0]=.055+load+.88*swing;
   r[ankle][0]=curveMotion([[0,-.20],[.12,0],[.38,0],[.54,.30],[.62,.35],[.76,-.10],[.91,-.25],[1,-.20]],f);
   r[hip][2]=(side?-1:1)*.012*Math.sin(a);
   const shoulder=side?9:6,elbow=shoulder+1,wrist=shoulder+2;
   const armPhase=q+side*Math.PI;
   r[shoulder][0]=.29*Math.cos(armPhase)+.035*Math.sin(2*armPhase);
   r[elbow][0]=-.24-.10*Math.sin(armPhase-.40)-.035*Math.sin(2*armPhase-.55);
   r[wrist][0]=.065*Math.sin(armPhase-.78);
   r[wrist][2]=.025*Math.cos(armPhase-.95);
  }
  m.root[0]=-.021*Math.cos(q-.25);
  m.root[1]=.008-.012*Math.cos(2*q-.25)-.004*Math.cos(4*q);
  r[1][2]=-.028*Math.cos(q-.15); // Hip drop on the swing side.
  r[1][1]=.065*Math.sin(q);
  r[2][0]=.035;r[2][2]=.014*Math.cos(q-.25);
  r[3][1]=-.115*Math.sin(q-.12);r[3][2]=.009*Math.cos(q-.3);
  stabilizeMotion(r,.88);
 }else if(state==='run'){
  // More human tactical run: longer stride, clearer weight transfer, softer vertical bounce.
  const step=fractMotion(p*2);
  m.root[1]=curveMotion([[0,-.018],[.10,-.042],[.32,-.015],[.58,.018],[.76,.030],[1,-.018]],step);
  m.root[0]=-.014*Math.cos(q-.18);
  m.root[2]=.010*Math.sin(q);

  for(let side=0;side<2;side++){
   const f=fractMotion(p+side*.5),hip=side?15:12,knee=hip+1,ankle=hip+2;
   const sideSign=side?1:-1;
   r[hip][0]=curveMotion([[0,-.42],[.16,.28],[.34,.44],[.55,.08],[.76,-.62],[1,-.42]],f);
   r[knee][0]=curveMotion([[0,.18],[.12,.36],[.30,.98],[.47,1.22],[.67,.88],[.84,.42],[1,.18]],f);
   r[ankle][0]=curveMotion([[0,-.16],[.12,-.10],[.27,.28],[.45,.18],[.67,-.06],[.84,-.18],[1,-.16]],f);
   r[hip][2]=sideSign*.018*Math.sin(q+side*Math.PI);
  }

  // Pelvis counter-rotation and forward lean make the run feel driven by the whole body.
  r[1][1]=.052*Math.sin(q);
  r[1][2]=-.022*Math.cos(q);
  r[2][0]=armed?.14:.12;
  r[3][0]=armed?.075:.055;
  r[3][1]=-.085*Math.sin(q-.12);
  r[3][2]=.015*Math.cos(q-.2);
  r[4][0]=armed?-.035:0;
  r[5][0]=armed?-.025:0;
  stabilizeMotion(r,.88);

  // Natural arm drive when unarmed. Armed runs are solved by the weapon IK below.
  if(!armed){
   for(let side=0;side<2;side++){
    const upper=side?9:6,a=q+side*Math.PI;
    r[upper][0]=.58*Math.cos(a)+.05*Math.sin(2*a);
    r[upper][2]=(side?-1:1)*.05;
    r[upper+1][0]=-1.08-.24*Math.sin(a-.30);
    r[upper+2][0]=.08*Math.sin(a-.72);
   }
  }

 }else if(state==='fall'){
  // Dedicated freefall silhouette: relaxed knees, slight asymmetric foot drag and balanced arms.
  // The actual descent speed stays entirely in PlayerController physics.
  const sway=Math.sin(q*1.3),flutter=Math.sin(q*2.1);
  r[1][0]=-.05+.018*sway;
  r[2][0]=-.075+.015*flutter;
  r[3][0]=-.08;
  r[5][0]=-.035;
  r[12][0]=-.36+.07*sway;r[13][0]=.76+.08*flutter;r[14][0]=-.16;
  r[15][0]=-.16-.06*sway;r[16][0]=.52-.06*flutter;r[17][0]=-.09;
  r[6][0]=-.43+.05*flutter;r[6][2]=.34;
  r[9][0]=-.37-.05*flutter;r[9][2]=-.32;
  r[7][0]=-.73;r[10][0]=-.81;
  m.root[0]=.012*sway;m.root[2]=.008*flutter;
 }else if(state==='jump'){
  // Percentages of one complete jump: anticipation / takeoff / flight / recovery.
  const key=(values)=>curveMotion(values,p);
  const knee=key([[0,.04],[.22,1.40],[.35,.09],[.54,.86],[.72,.22],[.80,1.60],[.91,.35],[1,.04]]);
  const hip=key([[0,-.02],[.22,-.70],[.35,-.025],[.54,-.58],[.72,-.12],[.80,-.81],[.91,-.17],[1,-.02]]);
  const ankle=key([[0,0],[.22,-.31],[.35,.54],[.54,.08],[.72,-.18],[.80,-.32],[.91,-.07],[1,0]]);
  const arm=key([[0,0],[.22,.72],[.35,-2.12],[.54,-1.35],[.72,-.82],[.80,-.30],[.90,.18],[1,0]]);
  const elbow=key([[0,-.16],[.22,-.45],[.35,-.25],[.54,-.70],[.72,-.42],[.82,-.64],[.93,-.24],[1,-.16]]);
  const spread=key([[0,.045],[.22,.08],[.35,.17],[.54,.43],[.72,.30],[.82,.18],[1,.045]]);
  const trunk=key([[0,0],[.22,.25],[.35,.08],[.54,-.07],[.72,.06],[.80,.27],[.93,.03],[1,0]]);
  for(let side=0;side<2;side++){
   let leg=side?15:12,armBone=side?9:6;
   r[leg][0]=hip;r[leg+1][0]=knee;r[leg+2][0]=ankle;
   r[armBone][0]=arm;r[armBone][2]=(side?-1:1)*spread;r[armBone+1][0]=elbow;
   r[armBone+2][0]=key([[0,0],[.22,.10],[.35,-.10],[.60,.08],[.80,.17],[1,0]]);
  }
  // Asymmetry exists only in flight, with zero value AND slope at either end.
  if(p>=.35&&p<=.72){
   const u=(p-.35)/.37,pulse=Math.pow(Math.sin(Math.PI*u),2);
   r[12][0]-=.075*pulse;r[15][0]+=.055*pulse;
   r[13][0]+=.16*pulse;r[16][0]-=.09*pulse;
   r[3][1]=.025*pulse;
  }
  r[2][0]=trunk*.65;r[3][0]=trunk*.35;
  stabilizeMotion(r,.65);
  // A delayed head dip and wrist response absorb the landing impulse.
  r[5][0]+=key([[0,0],[.72,0],[.825,.105],[.94,-.018],[1,0]]);
  const apexHeight=.55,flightSpan=.37,edgeVelocity=4*apexHeight/flightSpan;
  if(p<.22)m.root[1]=hermiteMotion(0,-.19,0,0,p/.22,.22);
  else if(p<.35)m.root[1]=hermiteMotion(-.19,.12,0,edgeVelocity,(p-.22)/.13,.13);
  else if(p<.72){let u=(p-.35)/flightSpan;m.root[1]=.12+4*apexHeight*u*(1-u)}
  else if(p<.80)m.root[1]=hermiteMotion(.12,-.22,-edgeVelocity,0,(p-.72)/.08,.08);
  else m.root[1]=curveMotion([[.80,-.22],[.94,-.018],[1,0]],p);
 }else if(state==='aim'){
  // User-supplied tactical pose. Bone rotations remain LOCAL to their parents.
  r[1][1]=-.04;r[2][1]=-.035;r[2][0]=.08;r[3][1]=-.025;
  r[4][0]=.14;r[4][1]=.05;
  r[5][0]=-.06;r[5][1]=.05;r[5][2]=.14;
  r[9]=[-.78,-.22,-.18];r[10]=[-1.42,.15,0];r[11]=[.08,-.25,.12];
  r[6]=[-1.05,-.48,.32];r[7]=[-.58,.35,0];r[8]=[.12,.42,-.28];
  r[12]=[-.14,-.08,-.05];r[13]=[.22,0,0];r[14]=[-.08,0,0];
  r[15]=[.18,.12,.05];r[16]=[.26,0,0];r[17]=[-.10,0,0];
  m.root[1]=-.025; // A target, never a direct assignment to the smoothed root.

 }else{
  // Subtle breathing and asymmetric weight shift keep idle from looking frozen.
  const breathe=Math.sin(q);
  r[2][0]=.010*breathe;
  r[3][0]=.012*Math.sin(q*2);
  r[3][2]=.008*Math.sin(q*.5);
  r[5][1]=.020*breathe;
  r[1][2]=.010*Math.sin(q*.5);
  m.root[1]=.004+.005*Math.sin(q);
 }
 if(armed){
  // Equipped long guns remain pointed forward at chest/shoulder height in
  // normal stance. Only sprint lowers them; ADS lifts them to the eye line.
  // Pistol carry keeps its separately calibrated two-handed posture.
  const pistol=weaponId==='pistol';
  const pitch=pistol
   ?(state==='aim'?-.05:state==='idle'?.34:state==='walk'?.18:state==='run'?.30:.27)
   :(state==='aim'?-.05:state==='idle'?.09:state==='walk'?.13:state==='run'?.30:.16+.025*Math.pow(Math.sin(Math.PI*p),2));
  const yawComp=-(r[1][1]+r[2][1]+r[3][1])*.90;
  const roll=state==='aim'?-.025:state==='run'?.018*Math.sin(q):state==='walk'?.010*Math.sin(q):0;
  m.weaponAngles=[pitch,yawComp,roll];
  m.weapon=weaponFrame(m.weaponAngles,weaponId,state==='aim'?1:0);
  armedMotion(r,m.weapon,weaponId==='pistol'?pistolGrips:rifleGrips);
 }else if(state==='aim'){
  // Empty-hand readiness has its own relaxed guard rather than an invisible rifle.
  r[6]=[-.38,-.10,.16];r[7]=[-.78,.08,0];r[8]=[0,0,0];
  r[9]=[-.38,.10,-.16];r[10]=[-.78,-.08,0];r[11]=[0,0,0];
 }
 return m;
}
window.OperatorMotion={parents,offsets,bind,inverseBind,I,T,mul,RX,RY,RZ,norm,sub,dot,cross,sp,clamp,damp,curveMotion,sampleMotion,weaponFrame,armedMotion,rifleGrips,pistolGrips,pointArm};
})();
