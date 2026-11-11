import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.187.0/build/three.module.js';

const canvas=document.getElementById('view');
const statusEl=document.getElementById('status');
const renderer=new THREE.WebGLRenderer({canvas,antialias:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,2));
renderer.shadowMap.enabled=true;
renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.outputColorSpace=THREE.SRGBColorSpace;
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=1.12;

const scene=new THREE.Scene();
scene.background=new THREE.Color(0x1d2927);
scene.fog=new THREE.Fog(0x1d2927,55,150);

const camera=new THREE.OrthographicCamera(-26,26,14.6,-14.6,0.1,300);
camera.position.set(42,52,42);
camera.lookAt(0,0,0);

scene.add(new THREE.HemisphereLight(0xbfd8e8,0x394236,1.55));
const sun=new THREE.DirectionalLight(0xffdfb5,3.2);
sun.position.set(-28,45,18);sun.castShadow=true;
sun.shadow.mapSize.set(2048,2048);
sun.shadow.camera.left=-60;sun.shadow.camera.right=60;sun.shadow.camera.top=60;sun.shadow.camera.bottom=-60;
scene.add(sun);

const world=new THREE.Group();scene.add(world);
const mat=(color,rough=.85,metal=.05)=>new THREE.MeshStandardMaterial({color,roughness:rough,metalness:metal});

function box(w,h,d,color,x,y,z=0){
 const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),mat(color));
 m.position.set(x,z+h/2,y);m.castShadow=true;m.receiveShadow=true;world.add(m);return m;
}
function plane(w,d,color,x,y,z=.01){
 const m=new THREE.Mesh(new THREE.BoxGeometry(w,.08,d),mat(color));
 m.position.set(x,z,y);m.receiveShadow=true;world.add(m);return m;
}

const MAP_W=146,MAP_H=104;
plane(MAP_W,MAP_H,0x3d493d,0,0,-.08);
const road=0x303738,sidewalk=0x777c75;
const mapScale=.035,mapOffsetX=2000,mapOffsetY=1400;
const mx=v=>(v-mapOffsetX)*mapScale;
const mz=v=>(v-mapOffsetY)*mapScale;
const mw=v=>v*mapScale;

const streetX=[580,1145,1705,2245,2900,3500].map(mx);
const streetZ=[440,950,1450,2050,2520].map(mz);
const roadW=mw(160),walkW=mw(24);
for(const z of streetZ){
 plane(MAP_W,roadW,road,0,z,.02);
 plane(MAP_W,walkW,sidewalk,0,z-roadW/2-walkW/2,.04);
 plane(MAP_W,walkW,sidewalk,0,z+roadW/2+walkW/2,.04);
}
for(const x of streetX){
 plane(roadW,MAP_H,road,x,0,.03);
 plane(walkW,MAP_H,sidewalk,x-roadW/2-walkW/2,0,.05);
 plane(walkW,MAP_H,sidewalk,x+roadW/2+walkW/2,0,.05);
}

const sourceBuildings=[
 [80,70,360,240],[700,70,300,250],[1280,60,300,270],[1840,80,270,235],[2380,70,320,250],
 [80,570,350,250],[710,570,300,240],[1270,570,300,250],[1840,570,270,245],[2380,570,320,250],
 [80,1070,350,230],[710,1070,300,230],[1270,1070,300,230],[1840,1070,270,230],[2380,1070,320,230],
 [80,1580,350,230],[710,1580,300,230],[1270,1580,300,230],
 [80,2180,350,230],[710,2180,300,230],[1270,2180,300,230],[1840,2180,270,230],
 [2380,120,330,260],[2380,570,330,250],[2380,1070,330,230],
 [3020,120,310,260],[3020,570,310,250],[3020,1070,310,230]
];
const buildingSpots=sourceBuildings.map(([x,y,w,d])=>[
 mx(x+w/2),mz(y+d/2),mw(w),mw(d)
]);

const buildings=[];
const ladders=[];
const buildingVisuals=[];
for(let i=0;i<buildingSpots.length;i++){
 const [x,y,w,d]=buildingSpots[i]; const h=5.5+(i%4)*.85;
 const facadeColor=i%4===0?0x626b68:i%4===1?0x737773:i%4===2?0x666c72:0x756d63;
 const b=box(w,h,d,facadeColor,x,y);b.userData={index:i,w,h,d};buildings.push(b);
 const visual={body:b,extras:[]};buildingVisuals.push(visual);

 const roof=box(w-.45,.35,d-.45,i%2?0x4a5353:0x55504a,x,y,h+.15);visual.extras.push(roof);

 // Rooftop props: HVAC, ducts, water tanks and vents vary per building.
 const propCount=1+(i%3);
 for(let k=0;k<propCount;k++){
  const px=x-w*.24+k*Math.max(2.2,w*.22),pz=y+(k%2?d*.16:-d*.14);
  const ac=box(1.7+.2*(k%2),.8+.15*(i%2),1.4,0x41494a,px,pz,h+.42);visual.extras.push(ac);
  const vent=new THREE.Mesh(new THREE.CylinderGeometry(.26,.32,1.05,10),mat(0x667071,.55,.2));vent.position.set(px+.65,h+1.25,pz-.45);vent.castShadow=true;world.add(vent);visual.extras.push(vent);
 }
 if(i%4===0){
  const tank=new THREE.Mesh(new THREE.CylinderGeometry(.85,.85,1.45,14),mat(0x555f61,.65,.18));
  tank.position.set(x+w*.22,h+1.25,y-d*.18);tank.castShadow=true;world.add(tank);visual.extras.push(tank);
 }
 if(i%3===0){
  const duct=box(Math.max(2.4,w*.28),.5,.75,0x596263,x-w*.08,y+d*.18,h+.5);visual.extras.push(duct);
 }

 // Doors and window bands on south/north facades.
 const doorMat=mat(i%2?0x38464e:0x4b3e36,.55,.08);
 const door=new THREE.Mesh(new THREE.BoxGeometry(1.45,2.35,.12),doorMat);
 door.position.set(x-w*.22,1.18,y+d/2+.07);door.castShadow=true;world.add(door);visual.extras.push(door);
 const doorTop=new THREE.Mesh(new THREE.BoxGeometry(1.8,.16,.18),mat(0x242b2f,.55,.15));
 doorTop.position.set(door.position.x,2.45,door.position.z+.02);world.add(doorTop);visual.extras.push(doorTop);

 const winMat=mat(0x2b6475,.32,.18);
 for(const side of [-1,1]){
  const z=y+side*(d/2+.06);
  const count=Math.max(2,Math.floor(w/3.2));
  for(let k=0;k<count;k++){
   const wx=x-w*.36+(count===1?0:k*(w*.72/(count-1)));
   const win=new THREE.Mesh(new THREE.BoxGeometry(Math.min(1.45,w/count*.58),1.05,.10),winMat);
   win.position.set(wx,3.0,z);world.add(win);visual.extras.push(win);
  }
 }
 for(const side of [-1,1]){
  const xx=x+side*(w/2+.055);
  const count=Math.max(2,Math.floor(d/3.3));
  for(let k=0;k<count;k++){
   const wz=y-d*.34+(count===1?0:k*(d*.68/(count-1)));
   const win=new THREE.Mesh(new THREE.BoxGeometry(.10,1.0,Math.min(1.35,d/count*.58)),winMat);
   win.position.set(xx,3.0,wz);world.add(win);visual.extras.push(win);
  }
 }

 const ladder=new THREE.Group();
 for(const sx of [-.42,.42]){const rail=new THREE.Mesh(new THREE.BoxGeometry(.11,h+1,.11),mat(0xaab0a7,.55,.15));rail.position.set(sx,(h+1)/2,0);ladder.add(rail)}
 for(let yy=.5;yy<h+.7;yy+=.55){const rung=new THREE.Mesh(new THREE.BoxGeometry(.98,.08,.09),mat(0xb8beb4,.5,.15));rung.position.set(0,yy,0);ladder.add(rung)}
 ladder.position.set(x,0,y+d/2+.16);world.add(ladder);ladders.push({building:i,group:ladder,x,z:y+d/2+.16,h});
}

const stripeMat=mat(0xc9b34f,.8,0);
for(const z of streetZ)for(let x=-MAP_W/2+3;x<MAP_W/2-2;x+=7){const s=new THREE.Mesh(new THREE.BoxGeometry(2.7,.09,.16),stripeMat);s.position.set(x,.11,z);world.add(s)}
for(const x of streetX)for(let z=-MAP_H/2+3;z<MAP_H/2-2;z+=7){const s=new THREE.Mesh(new THREE.BoxGeometry(.16,.09,2.7),stripeMat);s.position.set(x,.11,z);world.add(s)}

function zoneLabel(text,x,z){
 const cv=document.createElement('canvas');cv.width=512;cv.height=96;
 const g=cv.getContext('2d');g.fillStyle='rgba(4,10,15,.76)';g.fillRect(0,8,512,80);
 g.strokeStyle='rgba(101,255,139,.65)';g.lineWidth=3;g.strokeRect(3,11,506,74);
 g.fillStyle='#ecf8f2';g.font='800 38px system-ui';g.textAlign='center';g.textBaseline='middle';g.fillText(text,256,48);
 const tex=new THREE.CanvasTexture(cv);tex.colorSpace=THREE.SRGBColorSpace;
 const sp=new THREE.Sprite(new THREE.SpriteMaterial({map:tex,transparent:true,depthTest:false}));
 sp.position.set(x,8,z);sp.scale.set(12,2.25,1);scene.add(sp);
}
function addZonePad(x,z,w,d,color){
 const p=plane(w,d,color,x,z,.08);p.material.roughness=.95;return p;
}

// Praça central
addZonePad(0,2.5,17,13,0x59675b);
for(const [dx,dz] of [[-5,-3],[5,-3],[-5,3],[5,3]])makeTree?.(dx,2.5+dz);
const fountain=new THREE.Mesh(new THREE.CylinderGeometry(2.2,2.5,.45,20),mat(0x657a80,.4,.15));fountain.position.set(0,.28,2.5);fountain.receiveShadow=true;world.add(fountain);
zoneLabel('PRAÇA',0,2.5);

// Aeroporto / pista
addZonePad(49,-41,38,15,0x3b4143);
for(let x=34;x<65;x+=6){const s=new THREE.Mesh(new THREE.BoxGeometry(3,.10,.28),mat(0xe8e6ce,.75,0));s.position.set(x,.15,-41);world.add(s)}
box(11,4.2,6.5,0x59656a,61,-31);box(7,2.5,5,0x4c565b,45,-31);
zoneLabel('AEROPORTO',49,-41);

// Porto com água e docas
addZonePad(-57,39,29,20,0x274e5c);
for(const x of [-67,-60,-53,-46]){const dock=box(2,.45,12,0x715844,x,34,.08);dock.receiveShadow=true}
for(let i=0;i<5;i++)box(3.2,1.6,2.2,i%2?0x7a4d3a:0x3f6674,-66+i*4.1,44,.05);
zoneLabel('PORTO',-57,39);

// Distrito industrial
addZonePad(45,24,31,22,0x4b504d);
box(13,5.8,8,0x555c5b,38,19);box(11,4.8,7,0x5e625d,52,27);
for(const x of [35,42,50,57]){const tank=new THREE.Mesh(new THREE.CylinderGeometry(1.6,1.6,4.2,16),mat(0x6a7070,.65,.25));tank.position.set(x,2.15,31);tank.castShadow=true;world.add(tank)}
zoneLabel('INDUSTRIAL',45,24);
function makeTree(x,y){
 const g=new THREE.Group();
 const trunk=new THREE.Mesh(new THREE.CylinderGeometry(.35,.5,3.4,8),mat(0x60442e));trunk.position.y=1.7;trunk.castShadow=true;g.add(trunk);
 const crown=new THREE.Mesh(new THREE.SphereGeometry(2.25,10,8),mat(0x2e7545));crown.position.y=4.4;crown.scale.set(1,1.15,1);crown.castShadow=true;g.add(crown);
 g.position.set(x,0,y);world.add(g);
}
[[-24,-23],[23,-22],[-24,21],[24,19],[-63,8],[64,-8],[-8,38],[12,-38],[33,8],[-39,-7]].forEach(p=>makeTree(...p));

function makeLamp(x,y){
 const pole=new THREE.Mesh(new THREE.CylinderGeometry(.12,.15,4.8,8),mat(0x303536));pole.position.set(x,2.4,y);pole.castShadow=true;world.add(pole);
 const light=new THREE.PointLight(0xffc47c,18,14,2);light.position.set(x,4.8,y);light.castShadow=false;scene.add(light);
}
[[-24,-7],[-7,-24],[7,24],[24,7],[36,-7],[-36,7]].forEach(p=>makeLamp(...p));

function makeSoldier(color=0x28313a){
 const g=new THREE.Group();
 const legs=[];
 for(const sx of [-.32,.32]){const l=new THREE.Mesh(new THREE.CapsuleGeometry(.18,.7,4,7),mat(0x1d2429));l.position.set(sx,.65,0);l.castShadow=true;g.add(l);legs.push(l)}
 const torso=new THREE.Mesh(new THREE.CapsuleGeometry(.48,.85,5,8),mat(color));torso.position.y=1.65;torso.castShadow=true;g.add(torso);
 const head=new THREE.Mesh(new THREE.SphereGeometry(.38,12,10),mat(0xc39370));head.position.y=2.62;head.castShadow=true;g.add(head);
 const helm=new THREE.Mesh(new THREE.SphereGeometry(.43,12,8,0,Math.PI*2,0,Math.PI*.58),mat(0x242a30));helm.position.y=2.76;g.add(helm);
 const gun=new THREE.Mesh(new THREE.BoxGeometry(1.5,.14,.16),mat(0x11161a,.35,.55));gun.position.set(.72,1.75,.35);g.add(gun);
 g.userData.legs=legs;return g;
}

const player=makeSoldier(0x344154);player.position.set(4,0,8);world.add(player);
const enemies=[makeSoldier(0x4a3434),makeSoldier(0x3f4634)];
enemies[0].position.set(19,0,-8);world.add(enemies[0]);
enemies[1].position.set(-12,6.35,-13);world.add(enemies[1]);

function makeCar(x,y,rot=0){
 const g=new THREE.Group();
 const body=new THREE.Mesh(new THREE.BoxGeometry(3.8,.75,1.9),mat(0x25384d,.3,.6));body.position.y=.65;body.castShadow=true;g.add(body);
 const top=new THREE.Mesh(new THREE.BoxGeometry(2.1,.65,1.55),mat(0x477185,.25,.45));top.position.set(-.25,1.28,0);top.castShadow=true;g.add(top);
 for(const sx of [-1.25,1.25])for(const sz of [-.86,.86]){const wheel=new THREE.Mesh(new THREE.CylinderGeometry(.36,.36,.24,12),mat(0x111416));wheel.rotation.z=Math.PI/2;wheel.position.set(sx,.38,sz);g.add(wheel)}
 g.position.set(x,0,y);g.rotation.y=rot;world.add(g);
}
makeCar(-9,-33,0);makeCar(31,22,Math.PI/2);makeCar(51,-15,Math.PI/2);makeCar(-30,39,0);

let climbState=null;
function nearLadder(){
 let best=null,bestD=Infinity;
 for(const l of ladders){
  const d=Math.hypot(player.position.x-l.x,player.position.z-l.z);
  if(d<1.6&&d<bestD){best=l;bestD=d}
 }
 return best;
}
function startClimb(dir){
 const l=nearLadder();if(!l||climbState)return false;
 const b=buildings[l.building];
 climbState={ladder:l,dir,t:0,total:1.35,startY:player.position.y,endY:dir==="up"?b.userData.h+.45:0};
 player.position.x=l.x;player.position.z=l.z+.35;
 return true;
}
function updateClimb(dt){
 if(!climbState)return false;
 const s=climbState;s.t=Math.min(s.total,s.t+dt);
 const p=s.t/s.total,ease=p*p*(3-2*p);
 player.position.y=THREE.MathUtils.lerp(s.startY,s.endY,ease);
 player.rotation.y=Math.PI;
 const gait=Math.sin(s.t*16);
 player.userData.legs[0].rotation.x=gait*.7;player.userData.legs[1].rotation.x=-gait*.7;
 if(s.t>=s.total){player.position.y=s.endY;climbState=null}
 return true;
}


const keys=new Set();let t=0;
addEventListener('keydown',e=>{const k=e.key.toLowerCase();keys.add(k);if(k==='e'){if(player.position.y<1)startClimb('up');else startClimb('down')}});
addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));
document.getElementById('resetBtn').addEventListener('click',()=>player.position.set(5,0,8));

function onRoof(){
 if(player.position.y<1)return null;
 for(const b of buildings){
  const dx=Math.abs(player.position.x-b.position.x),dz=Math.abs(player.position.z-b.position.z);
  if(dx<b.userData.w/2-.45&&dz<b.userData.d/2-.45&&Math.abs(player.position.y-(b.userData.h+.45))<1)return b;
 }
 return null;
}
function blocked(nx,nz){
 const roof=onRoof();
 if(roof){
  const dx=Math.abs(nx-roof.position.x),dz=Math.abs(nz-roof.position.z);
  return dx>roof.userData.w/2-.6||dz>roof.userData.d/2-.6;
 }
 for(const b of buildings){const dx=Math.abs(nx-b.position.x),dz=Math.abs(nz-b.position.z);if(dx<b.userData.w/2+.55&&dz<b.userData.d/2+.55)return true}
 return false;
}
function updateBuildingVisibility(){
 for(let i=0;i<buildings.length;i++){
  const b=buildings[i],v=buildingVisuals[i];
  const toPlayer=new THREE.Vector3(player.position.x-b.position.x,0,player.position.z-b.position.z);
  const toCamera=new THREE.Vector3(camera.position.x-b.position.x,0,camera.position.z-b.position.z);
  const playerBehind=toPlayer.dot(toCamera)<0;
  const near=Math.hypot(toPlayer.x,toPlayer.z)<Math.max(b.userData.w,b.userData.d)*1.15;
  const fade=playerBehind&&near&&player.position.y<1.5;
  const all=[v.body,...v.extras];
  for(const obj of all){
   if(!obj.material)continue;
   const mats=Array.isArray(obj.material)?obj.material:[obj.material];
   for(const m of mats){m.transparent=fade;m.opacity=fade?.34:1;m.depthWrite=!fade}
  }
 }
}
function bulletHitsBuilding(pos){
 for(const b of buildings){
  const dx=Math.abs(pos.x-b.position.x),dz=Math.abs(pos.z-b.position.z);
  if(dx<b.userData.w/2&&dz<b.userData.d/2&&pos.y>=0&&pos.y<=b.userData.h+.6)return true;
 }
 return false;
}

function resize(){
 const w=innerWidth,h=innerHeight;renderer.setSize(w,h,false);
 const aspect=w/h,span=25;
 camera.left=-span*aspect;camera.right=span*aspect;camera.top=span;camera.bottom=-span;camera.updateProjectionMatrix();
}
addEventListener('resize',resize);resize();
statusEl.textContent='Protótipo 3D ativo • Combate vertical • Clique atira • E escadas';



const raycaster=new THREE.Raycaster();
const pointer=new THREE.Vector2();
const aimPoint=new THREE.Vector3();
const groundPlane=new THREE.Plane(new THREE.Vector3(0,1,0),0);
const bullets=[];
let shotCooldown=0;
let kills3D=0;

function makeTracer(origin,target){
 const dir=target.clone().sub(origin).normalize();
 const mesh=new THREE.Mesh(new THREE.SphereGeometry(.12,8,6),mat(0xffdd75,.25,.2));
 mesh.position.copy(origin);mesh.castShadow=true;world.add(mesh);
 bullets.push({mesh,dir,speed:38,life:1.1});
}

function topSurfaceAt(x,z){
 let y=0;
 for(const b of buildings){
  const dx=Math.abs(x-b.position.x),dz=Math.abs(z-b.position.z);
  if(dx<=b.userData.w/2&&dz<=b.userData.d/2)y=Math.max(y,b.userData.h+.45);
 }
 return y;
}
function nearestAliveEnemyToRay(){
 let best=null,bestD=.95;
 for(const e of enemies){
  if(!e.userData.alive)continue;
  const p=e.position.clone();p.y+=1.55;
  const d=raycaster.ray.distanceToPoint(p);
  if(d<bestD){best=e;bestD=d}
 }
 return best;
}
function updateAimFromPointer(){
 raycaster.setFromCamera(pointer,camera);
 const enemy=nearestAliveEnemyToRay();
 if(enemy){
  aimPoint.copy(enemy.position);aimPoint.y+=1.55;
 }else{
  const roof=onRoof();
  const aimPlane=new THREE.Plane(new THREE.Vector3(0,1,0),-(roof?roof.userData.h+.45:0));
  if(raycaster.ray.intersectPlane(aimPlane,aimPoint)){
   const surface=topSurfaceAt(aimPoint.x,aimPoint.z);
   if(surface>aimPoint.y+.2)aimPoint.y=surface+.05;
  }
 }
 const dx=aimPoint.x-player.position.x,dz=aimPoint.z-player.position.z;
 if(Math.hypot(dx,dz)>.01)player.rotation.y=Math.atan2(dx,dz);
}

function fire(){
 if(shotCooldown>0||climbState)return;
 shotCooldown=.18;
 const origin=new THREE.Vector3();
 player.getWorldPosition(origin);origin.y+=1.78;
 const target=aimPoint.clone();
 makeTracer(origin,target);
}

addEventListener('pointermove',e=>{
 pointer.x=e.clientX/innerWidth*2-1;
 pointer.y=-(e.clientY/innerHeight)*2+1;
 updateAimFromPointer();
});
addEventListener('pointerdown',e=>{if(e.button===0){updateAimFromPointer();fire()}});

function addHealthBar(enemy){
 const bg=new THREE.Mesh(new THREE.PlaneGeometry(1.8,.16),new THREE.MeshBasicMaterial({color:0x301318,side:THREE.DoubleSide}));
 const hp=new THREE.Mesh(new THREE.PlaneGeometry(1.7,.10),new THREE.MeshBasicMaterial({color:0xff5264,side:THREE.DoubleSide}));
 bg.position.y=3.5;hp.position.set(0,3.5,.012);enemy.add(bg);enemy.add(hp);enemy.userData.hpBar=hp;
}
for(const e of enemies){e.userData.hp=3;e.userData.alive=true;addHealthBar(e)}

function updateEnemies3D(dt){
 for(const e of enemies){
  if(!e.userData.alive)continue;
  const dx=player.position.x-e.position.x,dz=player.position.z-e.position.z,d=Math.hypot(dx,dz)||1;
  e.rotation.y=Math.atan2(dx,dz);
  if(d>8&&e.position.y<2){
   const side=Math.sin(t*1.8+e.position.x)*.55;
   const fx=dx/d,fz=dz/d,sx=-fz,sz=fx;
   const mx=fx*.7+sx*side,mz=fz*.7+sz*side;
   const nx=e.position.x+mx*2.1*dt,nz=e.position.z+mz*2.1*dt;
   if(!blocked(nx,nz)){e.position.x=nx;e.position.z=nz}
   const gait=Math.sin(t*8+e.position.x);
   e.userData.legs[0].rotation.x=gait*.4;e.userData.legs[1].rotation.x=-gait*.4;
  }
  if(e.userData.hpBar)e.userData.hpBar.scale.x=Math.max(0,e.userData.hp/3);
 }
}

function segmentHitsBuilding(a,bp){
 const steps=Math.max(1,Math.ceil(a.distanceTo(bp)/.45));
 for(let i=1;i<=steps;i++){
  const p=a.clone().lerp(bp,i/steps);
  for(const building of buildings){
   const dx=Math.abs(p.x-building.position.x),dz=Math.abs(p.z-building.position.z);
   if(dx<building.userData.w/2&&dz<building.userData.d/2&&p.y>=0&&p.y<=building.userData.h+.6)return true;
  }
 }
 return false;
}
function updateBullets3D(dt){
 for(const b of bullets){
  const old=b.mesh.position.clone();
  const next=old.clone().addScaledVector(b.dir,b.speed*dt);
  b.life-=dt;

  let enemyHit=null,enemyHitDist=Infinity;
  for(const e of enemies){
   if(!e.userData.alive)continue;
   const center=e.position.clone();center.y+=1.5;
   const seg=next.clone().sub(old),len2=seg.lengthSq();
   let q=old.clone();
   if(len2>0){
    const tHit=THREE.MathUtils.clamp(center.clone().sub(old).dot(seg)/len2,0,1);
    q=old.clone().addScaledVector(seg,tHit);
   }
   const d=q.distanceTo(center);
   if(d<1.0){
    const along=old.distanceTo(q);
    if(along<enemyHitDist){enemyHit=e;enemyHitDist=along}
   }
  }

  const buildingBlocked=segmentHitsBuilding(old,next);
  if(buildingBlocked){
   b.mesh.position.copy(next);b.life=0;continue;
  }

  b.mesh.position.copy(next);
  if(enemyHit){
   enemyHit.userData.hp--;b.life=0;
   if(enemyHit.userData.hp<=0){enemyHit.userData.alive=false;enemyHit.visible=false;kills3D++;statusEl.textContent='Protótipo 3D ativo • Kills '+kills3D}
  }
 }
 for(let i=bullets.length-1;i>=0;i--){if(bullets[i].life<=0){world.remove(bullets[i].mesh);bullets.splice(i,1)}}
}

let last=performance.now();
function frame(now){
 const dt=Math.min(.033,(now-last)/1000);last=now;t+=dt;
 if(updateClimb(dt)){shotCooldown=Math.max(0,shotCooldown-dt);updateAimFromPointer();updateEnemies3D(dt);updateBullets3D(dt);const target=new THREE.Vector3(player.position.x,player.position.y*.35,player.position.z);camera.position.lerp(new THREE.Vector3(target.x+42,target.y+52,target.z+42),1-Math.exp(-dt*4.5));camera.lookAt(target);renderer.render(scene,camera);requestAnimationFrame(frame);return}
 let dx=(keys.has('d')?1:0)-(keys.has('a')?1:0),dz=(keys.has('s')?1:0)-(keys.has('w')?1:0);
 const len=Math.hypot(dx,dz);
 if(len){dx/=len;dz/=len;const speed=keys.has('shift')?10:6;const nx=player.position.x+dx*speed*dt,nz=player.position.z+dz*speed*dt;if(!blocked(nx,player.position.z))player.position.x=nx;if(!blocked(player.position.x,nz))player.position.z=nz;player.rotation.y=Math.atan2(dx,dz);const gait=Math.sin(t*(keys.has('shift')?14:10));player.userData.legs[0].rotation.x=gait*.55;player.userData.legs[1].rotation.x=-gait*.55}else{player.userData.legs[0].rotation.x*=.8;player.userData.legs[1].rotation.x*=.8}
 shotCooldown=Math.max(0,shotCooldown-dt);updateAimFromPointer();updateEnemies3D(dt);updateBullets3D(dt);
 const target=new THREE.Vector3(player.position.x,player.position.y*.35,player.position.z);
 camera.position.lerp(new THREE.Vector3(target.x+42,target.y+52,target.z+42),1-Math.exp(-dt*4.5));camera.lookAt(target);
 updateBuildingVisibility();renderer.render(scene,camera);requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
