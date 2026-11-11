import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.187.0/build/three.module.js';

const canvas=document.getElementById('view');
const statusEl=document.getElementById('status');
const hpText=document.getElementById('hpText');
const hpFill=document.getElementById('hpFill');
const weaponHud=document.getElementById('weaponHud');
const ammoHud=document.getElementById('ammoHud');
const killsHud=document.getElementById('killsHud');
const bossHud=document.getElementById('bossHud');
const bossPhaseHud=document.getElementById('bossPhaseHud');
const bossHpFill=document.getElementById('bossHpFill');
const missileAlert=document.getElementById('missileAlert');
const moveStick=document.getElementById('moveStick');
const moveKnob=document.getElementById('moveKnob');
const aimStick=document.getElementById('aimStick');
const aimKnob=document.getElementById('aimKnob');
const actionBtn=document.getElementById('actionBtn');
const mobileMove={x:0,y:0,active:false};
const mobileAim={x:0,y:0,active:false,firing:false};
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

const camera=new THREE.PerspectiveCamera(58,innerWidth/innerHeight,.1,300);
camera.position.set(0,8,-11);
camera.lookAt(0,1.6,0);

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
 const gun=new THREE.Group();
 const receiver=new THREE.Mesh(new THREE.BoxGeometry(1.05,.18,.18),mat(0x11161a,.3,.65));receiver.position.set(.62,1.76,.35);gun.add(receiver);
 const barrel=new THREE.Mesh(new THREE.BoxGeometry(.72,.09,.09),mat(0x232a2f,.25,.75));barrel.position.set(1.45,1.77,.35);gun.add(barrel);
 g.add(gun);
 g.userData.legs=legs;g.userData.gun=gun;g.userData.weaponParts={receiver,barrel};return g;
}

const player=makeSoldier(0x344154);player.position.set(4,0,8);world.add(player);
player.userData.hp=100;player.userData.maxHp=100;
const enemies=[makeSoldier(0x4a3434),makeSoldier(0x3f4634)];
enemies[0].position.set(19,0,-8);world.add(enemies[0]);
enemies[1].position.set(-12,0,-13);world.add(enemies[1]);
enemies[0].userData.role='soldier';
enemies[1].userData.role='sniper';

const bossSpawns=[[-54,-30],[56,-25],[-52,28],[52,38],[0,-40],[38,8]];
const golias=makeSoldier(0x5b2525);
golias.scale.set(1.65,1.65,1.65);
const bossSpawn=bossSpawns[Math.floor(Math.random()*bossSpawns.length)];
golias.position.set(bossSpawn[0],0,bossSpawn[1]);
golias.userData.role='boss';
world.add(golias);
enemies.push(golias);

const bossMissiles=[];
const bossWarnings=[];
const bossDeathFx=[];
let bossCutscene={active:false,t:0,total:3.2,started:false};

const cars=[];
const vehicleSmoke=[];
const smokeGeo=new THREE.SphereGeometry(.22,7,5);
function spawnVehicleSmoke(car,intensity=1){
 const forward=new THREE.Vector3(Math.sin(car.rotation.y),0,Math.cos(car.rotation.y));
 const pos=car.position.clone().addScaledVector(forward,1.15);
 pos.y=.9;
 const smoke=new THREE.Mesh(
  smokeGeo,
  new THREE.MeshBasicMaterial({color:intensity>1.4?0x202426:0x5a5f61,transparent:true,opacity:.34,depthWrite:false})
 );
 smoke.position.copy(pos);
 smoke.scale.setScalar(.65+Math.random()*.35);
 world.add(smoke);
 vehicleSmoke.push({
  mesh:smoke,
  life:.9+Math.random()*.55,
  maxLife:1.45,
  drift:new THREE.Vector3((Math.random()-.5)*.45,.75+Math.random()*.55,(Math.random()-.5)*.45),
  grow:.9+Math.random()*.55
 });
}
function updateVehicleSmoke(dt){
 for(const car of cars){
  const u=car.userData;
  if(u.health<60){
   u.smokeTimer=(u.smokeTimer||0)-dt;
   const severity=THREE.MathUtils.clamp((60-u.health)/60,0,1);
   const interval=u.broken?.08:THREE.MathUtils.lerp(.34,.13,severity);
   if(u.smokeTimer<=0){spawnVehicleSmoke(car,u.broken?1.8:1+severity);u.smokeTimer=interval}
  }
 }
 for(let i=vehicleSmoke.length-1;i>=0;i--){
  const p=vehicleSmoke[i];p.life-=dt;
  p.mesh.position.addScaledVector(p.drift,dt);
  const grow=1+p.grow*dt;p.mesh.scale.multiplyScalar(grow);
  p.mesh.material.opacity=Math.max(0,.34*(p.life/p.maxLife));
  if(p.life<=0){world.remove(p.mesh);p.mesh.material.dispose();vehicleSmoke.splice(i,1)}
 }
}
function makeCar(x,y,rot=0){
 const g=new THREE.Group();
 const body=new THREE.Mesh(new THREE.BoxGeometry(3.8,.75,1.9),mat(0x25384d,.3,.6));body.position.y=.65;body.castShadow=true;g.add(body);
 const top=new THREE.Mesh(new THREE.BoxGeometry(2.1,.65,1.55),mat(0x477185,.25,.45));top.position.set(-.25,1.28,0);top.castShadow=true;g.add(top);
 const wheels=[];
 for(const sx of [-1.25,1.25])for(const sz of [-.86,.86]){const wheel=new THREE.Mesh(new THREE.CylinderGeometry(.36,.36,.24,12),mat(0x111416));wheel.rotation.z=Math.PI/2;wheel.position.set(sx,.38,sz);g.add(wheel);wheels.push(wheel)}
 g.position.set(x,0,y);g.rotation.y=rot;g.userData={speed:0,health:100,broken:false,wheels,body,top,smokeTimer:0};world.add(g);cars.push(g);return g;
}
makeCar(-9,-33,0);makeCar(31,22,Math.PI/2);makeCar(51,-15,Math.PI/2);makeCar(-30,39,0);
let activeCar=null;
function nearestCar(){
 let best=null,bestD=Infinity;
 for(const car of cars){const d=Math.hypot(player.position.x-car.position.x,player.position.z-car.position.z);if(d<2.8&&d<bestD){best=car;bestD=d}}
 return best;
}
function toggleVehicle(){
 if(player.position.y>1||climbState)return false;
 if(activeCar){
  const side=new THREE.Vector3(Math.cos(activeCar.rotation.y),0,-Math.sin(activeCar.rotation.y)).multiplyScalar(2.2);
  player.position.copy(activeCar.position).add(side);player.position.y=0;player.visible=true;activeCar=null;
  statusEl.textContent='Protótipo 3D ativo • A PÉ • E veículo/escada';return true;
 }
 const car=nearestCar();
 if(car&&!car.userData.broken){activeCar=car;player.visible=false;statusEl.textContent='Protótipo 3D ativo • NO CARRO • WASD dirigir • SHIFT turbo • E sair';return true}
 return false;
}
function carBlocked(nx,nz){
 for(const b of buildings){const dx=Math.abs(nx-b.position.x),dz=Math.abs(nz-b.position.z);if(dx<b.userData.w/2+1.7&&dz<b.userData.d/2+1.15)return true}
 return false;
}
function damageCar(car,amount){
 const u=car.userData;
 u.health=Math.max(0,u.health-amount);
 if(u.health<=60&&!u.broken)statusEl.textContent='Veículo danificado • '+Math.ceil(u.health)+'% • fumaça no motor';
 if(u.health<=0){
  u.broken=true;u.speed=0;
  u.body.material.color.setHex(0x242628);u.top.material.color.setHex(0x303437);
  statusEl.textContent='Veículo destruído • motor desligado • E para sair';
 }
}
function updateVehicle(dt){
 if(!activeCar)return false;
 const car=activeCar,u=car.userData;
 if(u.broken){u.speed=0;player.position.copy(car.position);player.rotation.y=car.rotation.y;return true}
 const throttle=((keys.has('w')?1:0)-(keys.has('s')?1:0)) + (mobileMove.active?-mobileMove.y:0);
 const steer=((keys.has('d')?1:0)-(keys.has('a')?1:0)) + (mobileMove.active?mobileMove.x:0);
 const max=keys.has('shift')?20:14;
 u.speed+=throttle*22*dt;
 if(!throttle)u.speed*=Math.pow(.22,dt);
 u.speed=THREE.MathUtils.clamp(u.speed,-6,max);
 const turnFactor=THREE.MathUtils.clamp(Math.abs(u.speed)/7,0,1);
 car.rotation.y+=steer*1.7*turnFactor*dt*(u.speed>=0?1:-1);
 const fx=Math.sin(car.rotation.y),fz=Math.cos(car.rotation.y);
 const nx=car.position.x+fx*u.speed*dt,nz=car.position.z+fz*u.speed*dt;
 if(carBlocked(nx,nz)){
  if(Math.abs(u.speed)>7)damageCar(car,Math.min(38,Math.abs(u.speed)*2.2));
  u.speed*=-.22;
 }else{car.position.x=nx;car.position.z=nz}
 for(const wheel of u.wheels)wheel.rotation.x-=u.speed*dt*2.6;
 for(const e of enemies){
  if(!e.userData.alive||e.position.y>2)continue;
  const d=Math.hypot(e.position.x-car.position.x,e.position.z-car.position.z);
  if(d<2.1&&Math.abs(u.speed)>4){e.userData.hp=0;e.userData.alive=false;e.visible=false;kills3D++;u.speed*=.72;statusEl.textContent='Atropelamento • Kills '+kills3D}
 }
 player.position.copy(car.position);player.position.y=0;player.rotation.y=car.rotation.y;
 return true;
}

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
addEventListener('keydown',e=>{const k=e.key.toLowerCase();keys.add(k);if(k==='1')setWeapon('pistol');if(k==='2')setWeapon('smg');if(k==='3')setWeapon('rifle');if(k==='4')setWeapon('shotgun');if(k==='e'){if(!toggleVehicle()){if(player.position.y<1)startClimb('up');else startClimb('down')}}});
addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));
document.getElementById('resetBtn').addEventListener('click',()=>player.position.set(5,0,8));
function bindStick(el,knob,state,onMove){
 if(!el||!knob)return;
 let pid=null;
 const update=e=>{
  const r=el.getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height/2;
  let dx=e.clientX-cx,dy=e.clientY-cy;
  const max=r.width*.34,len=Math.hypot(dx,dy)||1,cl=Math.min(max,len);
  dx=dx/len*cl;dy=dy/len*cl;
  knob.style.transform=`translate(${dx}px,${dy}px)`;
  state.x=dx/max;state.y=dy/max;state.active=true;
  onMove?.(state);
 };
 el.addEventListener('pointerdown',e=>{pid=e.pointerId;el.setPointerCapture(pid);update(e)});
 el.addEventListener('pointermove',e=>{if(e.pointerId===pid)update(e)});
 const end=e=>{if(e.pointerId!==pid)return;pid=null;state.x=0;state.y=0;state.active=false;state.firing=false;knob.style.transform='translate(0,0)';onMove?.(state)};
 el.addEventListener('pointerup',end);el.addEventListener('pointercancel',end);
}
bindStick(moveStick,moveKnob,mobileMove);
bindStick(aimStick,aimKnob,mobileAim,state=>{
 const mag=Math.hypot(state.x,state.y);
 if(mag>.12){
  const ang=Math.atan2(state.x,-state.y);
  player.rotation.y=ang;
  const origin=player.position.clone();
  aimPoint.set(origin.x+Math.sin(ang)*20,origin.y+1.5,origin.z+Math.cos(ang)*20);
 }
 state.firing=mag>.58;
});
actionBtn?.addEventListener('pointerdown',e=>{
 e.preventDefault();
 if(!toggleVehicle()){if(player.position.y<1)startClimb('up');else startClimb('down')}
});

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
 camera.aspect=w/h;
 camera.updateProjectionMatrix();
}
addEventListener('resize',resize);resize();
statusEl.textContent='PISTOLA • 1-4 troca arma • clique atira • E veículo/escada';



const raycaster=new THREE.Raycaster();
const pointer=new THREE.Vector2();
const aimPoint=new THREE.Vector3();
const groundPlane=new THREE.Plane(new THREE.Vector3(0,1,0),0);
const bullets=[];
let shotCooldown=0;
let kills3D=0;
let currentWeapon='pistol';
const ammoState={
 pistol:{mag:12,reserve:72},
 smg:{mag:30,reserve:150},
 rifle:{mag:20,reserve:100},
 shotgun:{mag:8,reserve:40}
};
const weapons3D={
 pistol:{label:'PISTOLA',cooldown:.24,damage:1,speed:42,spread:.012,pellets:1,color:0xffdf78,recoil:.18,scale:[.72,.82,.72],impact:4},
 smg:{label:'SMG',cooldown:.085,damage:.55,speed:46,spread:.045,pellets:1,color:0xffc85a,recoil:.12,scale:[1.0,.92,.82],impact:4},
 rifle:{label:'RIFLE',cooldown:.19,damage:1.7,speed:58,spread:.009,pellets:1,color:0xffefad,recoil:.28,scale:[1.35,1,1],impact:6},
 shotgun:{label:'ESCOPETA',cooldown:.62,damage:.52,speed:38,spread:.12,pellets:7,color:0xffb85c,recoil:.42,scale:[1.48,1.12,1.05],impact:8}
};
const muzzleFx=[],impactFx=[];
let recoilKick=0;
function applyWeaponVisual(){
 const w=weapons3D[currentWeapon],gun=player.userData.gun;
 if(!gun||!w)return;
 gun.scale.set(...w.scale);
 const parts=player.userData.weaponParts;
 if(parts){
  if(currentWeapon==='pistol'){parts.receiver.material.color.setHex(0x1b2024);parts.barrel.material.color.setHex(0x2d3439)}
  if(currentWeapon==='smg'){parts.receiver.material.color.setHex(0x20272d);parts.barrel.material.color.setHex(0x11161a)}
  if(currentWeapon==='rifle'){parts.receiver.material.color.setHex(0x273037);parts.barrel.material.color.setHex(0x151a1d)}
  if(currentWeapon==='shotgun'){parts.receiver.material.color.setHex(0x3a2c22);parts.barrel.material.color.setHex(0x171b1e)}
 }
}
function updateHud(){
 const hpPct=Math.max(0,player.userData.hp/player.userData.maxHp*100);
 if(hpText)hpText.textContent=Math.ceil(player.userData.hp);
 if(hpFill)hpFill.style.width=hpPct+'%';
 if(weaponHud)weaponHud.textContent=weapons3D[currentWeapon].label;
 const ammo=ammoState[currentWeapon];
 if(ammoHud)ammoHud.textContent=ammo.mag+' / '+ammo.reserve;
 if(killsHud)killsHud.textContent=kills3D;
 if(golias?.userData?.maxHp){
  const pct=Math.max(0,golias.userData.hp/golias.userData.maxHp*100);
  if(bossHpFill)bossHpFill.style.width=pct+'%';
  if(bossPhaseHud)bossPhaseHud.textContent='FASE '+(golias.userData.phase||1);
  if(bossHud)bossHud.hidden=!golias.userData.alive;
 }
 if(missileAlert)missileAlert.hidden=bossWarnings.length===0;
}
function setWeapon(name){
 if(!weapons3D[name])return;
 currentWeapon=name;applyWeaponVisual();updateHud();
 statusEl.textContent='Arma: '+weapons3D[name].label+' • 1-4 troca • clique atira';
}
function spawnMuzzle(origin){
 const light=new THREE.PointLight(0xffc56a,8,5,2);light.position.copy(origin);scene.add(light);
 const flash=new THREE.Mesh(new THREE.SphereGeometry(.23,8,6),new THREE.MeshBasicMaterial({color:0xffe09a,transparent:true,opacity:.95}));
 flash.position.copy(origin);world.add(flash);muzzleFx.push({light,flash,t:.07});
}
function spawnImpact(pos,color=0xffd58a,count=5){
 for(let i=0;i<count;i++){
  const m=new THREE.Mesh(new THREE.SphereGeometry(.055,6,4),new THREE.MeshBasicMaterial({color,transparent:true,opacity:.9}));
  m.position.copy(pos);world.add(m);
  impactFx.push({m,v:new THREE.Vector3((Math.random()-.5)*4,Math.random()*3.5,(Math.random()-.5)*4),t:.28});
 }
}
function updateWeaponFx(dt){
 for(const f of muzzleFx){f.t-=dt;f.flash.scale.multiplyScalar(1.12);f.flash.material.opacity=Math.max(0,f.t/.07);f.light.intensity=8*Math.max(0,f.t/.07)}
 for(let i=muzzleFx.length-1;i>=0;i--)if(muzzleFx[i].t<=0){scene.remove(muzzleFx[i].light);world.remove(muzzleFx[i].flash);muzzleFx.splice(i,1)}
 for(const p of impactFx){p.t-=dt;p.v.y-=8*dt;p.m.position.addScaledVector(p.v,dt);p.m.material.opacity=Math.max(0,p.t/.28)}
 for(let i=impactFx.length-1;i>=0;i--)if(impactFx[i].t<=0){world.remove(impactFx[i].m);impactFx.splice(i,1)}
}

function makeTracer(origin,target,weapon){
 const dir=target.clone().sub(origin).normalize();
 const spread=weapon.spread||0;
 dir.x+=(Math.random()-.5)*spread;dir.y+=(Math.random()-.5)*spread*.55;dir.z+=(Math.random()-.5)*spread;dir.normalize();
 const mesh=new THREE.Mesh(new THREE.CylinderGeometry(.035,.035,.9,6),new THREE.MeshBasicMaterial({color:weapon.color||0xffdd75,transparent:true,opacity:.95}));
 mesh.rotation.x=Math.PI/2;
 mesh.position.copy(origin);mesh.castShadow=false;world.add(mesh);
 bullets.push({mesh,dir,speed:weapon.speed,life:1.15,damage:weapon.damage,color:weapon.color});
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
 if(shotCooldown>0||climbState||activeCar)return;
 const weapon=weapons3D[currentWeapon];
 const ammo=ammoState[currentWeapon];
 if(ammo.mag<=0){
  if(ammo.reserve<=0){statusEl.textContent='Sem munição • troque de arma';return}
  const size=currentWeapon==='pistol'?12:currentWeapon==='smg'?30:currentWeapon==='rifle'?20:8;
  const load=Math.min(size,ammo.reserve);ammo.mag=load;ammo.reserve-=load;updateHud();
  statusEl.textContent='Recarregado • '+weapon.label;
  return;
 }
 ammo.mag--;
 shotCooldown=weapon.cooldown;
 const origin=new THREE.Vector3();
 player.getWorldPosition(origin);origin.y+=1.78;
 const forward=new THREE.Vector3(Math.sin(player.rotation.y),0,Math.cos(player.rotation.y));
 origin.addScaledVector(forward,1.05);
 const target=aimPoint.clone();
 spawnMuzzle(origin);
 recoilKick=Math.min(.55,recoilKick+weapon.recoil);
 for(let i=0;i<weapon.pellets;i++)makeTracer(origin,target,weapon);
 updateHud();
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
for(const e of enemies){
 e.userData.hp=e.userData.role==='boss'?18:(e.userData.role==='sniper'?2.4:3);
 e.userData.maxHp=e.userData.hp;
 e.userData.alive=true;
 e.userData.state='patrol';
 e.userData.alertTimer=0;
 e.userData.fireCd=e.userData.role==='boss'?1.2:Math.random()*.8;
 e.userData.missileCd=e.userData.role==='boss'?3.5:0;
 e.userData.phase=1;
 e.userData.patrolAngle=Math.random()*Math.PI*2;
 e.userData.home=e.position.clone();
 e.userData.climb=null;
 e.userData.targetLadder=null;
 addHealthBar(e);
}

function enemyLineOfSight(e){
 const a=e.position.clone();a.y+=1.55;
 const b=player.position.clone();b.y+=1.5;
 return !segmentHitsBuilding(a,b);
}
function moveEnemyGround(e,tx,tz,speed,dt){
 const dx=tx-e.position.x,dz=tz-e.position.z,d=Math.hypot(dx,dz)||1;
 const mx=dx/d,mz=dz/d;
 const nx=e.position.x+mx*speed*dt,nz=e.position.z+mz*speed*dt;
 let blockedMove=false;
 for(const b of buildings){
  const bx=Math.abs(nx-b.position.x),bz=Math.abs(nz-b.position.z);
  if(bx<b.userData.w/2+.55&&bz<b.userData.d/2+.55){blockedMove=true;break}
 }
 if(!blockedMove){e.position.x=nx;e.position.z=nz}
 e.rotation.y=Math.atan2(dx,dz);
 const gait=Math.sin(t*9+e.position.x);
 e.userData.legs[0].rotation.x=gait*.45;e.userData.legs[1].rotation.x=-gait*.45;
}
function nearestLadderForEnemy(e){
 let best=null,bestD=Infinity;
 for(const l of ladders){
  const d=Math.hypot(e.position.x-l.x,e.position.z-l.z);
  if(d<bestD){best=l;bestD=d}
 }
 return best;
}
function beginEnemyClimb(e,l){
 e.userData.climb={ladder:l,t:0,total:1.55,startY:e.position.y,endY:buildings[l.building].userData.h+.45};
 e.position.x=l.x;e.position.z=l.z+.25;e.userData.state='climb';
}
function updateEnemyClimb(e,dt){
 const c=e.userData.climb;if(!c)return false;
 c.t=Math.min(c.total,c.t+dt);
 const p=c.t/c.total,ease=p*p*(3-2*p);
 e.position.y=THREE.MathUtils.lerp(c.startY,c.endY,ease);
 e.rotation.y=Math.PI;
 const gait=Math.sin(c.t*15);
 e.userData.legs[0].rotation.x=gait*.7;e.userData.legs[1].rotation.x=-gait*.7;
 if(c.t>=c.total){e.position.y=c.endY;e.userData.climb=null;e.userData.state='attack'}
 return true;
}
function bossPhase(e){
 return e.userData.hp<=e.userData.maxHp*.5?2:1;
}
function spawnBossMissile(e){
 const angle=Math.random()*Math.PI*2;
 const radius=2.5+Math.random()*6;
 const tx=THREE.MathUtils.clamp(player.position.x+Math.cos(angle)*radius,-MAP_W/2+4,MAP_W/2-4);
 const tz=THREE.MathUtils.clamp(player.position.z+Math.sin(angle)*radius,-MAP_H/2+4,MAP_H/2-4);

 const ring=new THREE.Mesh(
  new THREE.RingGeometry(1.25,1.55,28),
  new THREE.MeshBasicMaterial({color:0xff352f,transparent:true,opacity:.75,side:THREE.DoubleSide,depthWrite:false})
 );
 ring.rotation.x=-Math.PI/2;ring.position.set(tx,.13,tz);world.add(ring);

 const missile=new THREE.Group();
 const body=new THREE.Mesh(new THREE.CylinderGeometry(.16,.2,1.1,8),mat(0x33383c,.35,.7));
 body.rotation.z=Math.PI/2;missile.add(body);
 const tip=new THREE.Mesh(new THREE.ConeGeometry(.2,.45,8),mat(0x6b2525,.4,.55));
 tip.rotation.z=-Math.PI/2;tip.position.x=.75;missile.add(tip);
 missile.position.set(e.position.x,10,e.position.z);world.add(missile);

 bossWarnings.push({mesh:ring,t:1.25,max:1.25,target:new THREE.Vector3(tx,0,tz),missile});
 bossMissiles.push({mesh:missile,start:missile.position.clone(),target:new THREE.Vector3(tx,.25,tz),t:0,total:1.25,armed:true});
}
function bossHitkillAt(pos){
 const target=activeCar?activeCar.position:player.position;
 if(Math.hypot(target.x-pos.x,target.z-pos.z)<=2.35){
  if(activeCar){damageCar(activeCar,999);activeCar=null;player.visible=true}
  player.userData.hp=100;
  player.position.set(4,0,8);
  updateHud();
  statusEl.textContent='GOLIAS • Míssil acertou em cheio • HITKILL';
 }
}
function spawnExplosionBurst(pos,scale=1){
 for(let i=0;i<24;i++){
  const m=new THREE.Mesh(
   new THREE.SphereGeometry(.08+Math.random()*.08,6,4),
   new THREE.MeshBasicMaterial({color:i%3===0?0xfff0a8:(i%2?0xff8a33:0xff3d20),transparent:true,opacity:.95})
  );
  m.position.copy(pos);world.add(m);
  bossDeathFx.push({
   mesh:m,
   v:new THREE.Vector3((Math.random()-.5)*7*scale,Math.random()*6*scale,(Math.random()-.5)*7*scale),
   t:.7+Math.random()*.5,
   max:1.2,
   grow:1.2+Math.random()*.8
  });
 }
 const light=new THREE.PointLight(0xff6b2b,18*scale,18*scale,2);
 light.position.copy(pos).add(new THREE.Vector3(0,2,0));scene.add(light);
 bossDeathFx.push({light,t:.45,max:.45});
}
function startBossDeathCutscene(){
 if(bossCutscene.active||bossCutscene.started)return;
 bossCutscene={active:true,t:0,total:3.2,started:true};
 const p=golias.position.clone();
 spawnExplosionBurst(p.clone().add(new THREE.Vector3(0,1.6,0)),1.2);
 setTimeout?.(()=>{},0);
 statusEl.textContent='GOLIAS DERROTADO • explosão final';
}
function updateBossDeathFx(dt){
 for(let i=bossDeathFx.length-1;i>=0;i--){
  const f=bossDeathFx[i];f.t-=dt;
  if(f.mesh){
   f.v.y-=7*dt;f.mesh.position.addScaledVector(f.v,dt);
   f.mesh.scale.multiplyScalar(1+f.grow*dt);
   f.mesh.material.opacity=Math.max(0,f.t/f.max);
   if(f.t<=0){world.remove(f.mesh);f.mesh.material.dispose();bossDeathFx.splice(i,1)}
  }else if(f.light){
   f.light.intensity=18*Math.max(0,f.t/f.max);
   if(f.t<=0){scene.remove(f.light);bossDeathFx.splice(i,1)}
  }
 }
}
function updateBossCutscene(dt){
 if(!bossCutscene.active)return false;
 bossCutscene.t+=dt;
 const p=Math.min(1,bossCutscene.t/bossCutscene.total);
 const focus=golias.position.clone();focus.y=1.5;
 const radius=18-6*Math.sin(Math.min(1,p)*Math.PI);
 const ang=p*Math.PI*.8;
 camera.position.set(focus.x+Math.cos(ang)*radius,focus.y+14,focus.z+Math.sin(ang)*radius);
 camera.lookAt(focus);
 if(bossCutscene.t>.55&&bossCutscene.t<.62)spawnExplosionBurst(focus.clone().add(new THREE.Vector3(1.5,1.0,-.8)),.8);
 if(bossCutscene.t>1.1&&bossCutscene.t<1.17)spawnExplosionBurst(focus.clone().add(new THREE.Vector3(-1.2,1.4,.9)),.9);
 if(bossCutscene.t>1.7&&bossCutscene.t<1.77)spawnExplosionBurst(focus.clone().add(new THREE.Vector3(0,2.0,0)),1.5);
 if(p>=1){
  bossCutscene.active=false;
  golias.visible=false;
  statusEl.textContent='GOLIAS DERROTADO • área liberada';
 }
 return true;
}
function updateBossMissiles(dt){
 for(let i=bossWarnings.length-1;i>=0;i--){
  const w=bossWarnings[i];w.t-=dt;
  w.mesh.material.opacity=.35+.4*Math.abs(Math.sin(t*10));
  const p=1-Math.max(0,w.t)/w.max;
  w.missile.position.lerpVectors(w.missile.position,w.target,Math.min(1,p*.09));
  if(w.t<=0){
   bossHitkillAt(w.target);
   spawnImpact(w.target.clone().add(new THREE.Vector3(0,.25,0)),0xff4b2b,18);
   world.remove(w.mesh);
   world.remove(w.missile);
   bossWarnings.splice(i,1);
  }
 }
}
function enemyFire(e){
 const origin=e.position.clone();origin.y+=1.75;
 const target=player.position.clone();target.y+=1.4;
 if(segmentHitsBuilding(origin,target))return;
 const dir=target.sub(origin).normalize();
 const mesh=new THREE.Mesh(new THREE.CylinderGeometry(.028,.028,.7,6),new THREE.MeshBasicMaterial({color:e.userData.role==='sniper'?0xff5c5c:0xff9b5c,transparent:true,opacity:.9}));
 mesh.rotation.x=Math.PI/2;mesh.position.copy(origin);world.add(mesh);
 bullets.push({mesh,dir,speed:e.userData.role==='sniper'?48:35,life:1.2,damage:0,color:0xff6b5c,enemyShot:true,sniperShot:e.userData.role==='sniper'});
 spawnMuzzle(origin);
}
function updateEnemies3D(dt){
 for(const e of enemies){
  if(!e.userData.alive)continue;
  if(updateEnemyClimb(e,dt))continue;

  const dx=player.position.x-e.position.x,dz=player.position.z-e.position.z,d=Math.hypot(dx,dz)||1;
  const los=enemyLineOfSight(e);
  e.userData.fireCd=Math.max(0,e.userData.fireCd-dt);

  if(los&&d<34){e.userData.alertTimer=4;e.userData.state='alert'}
  else e.userData.alertTimer=Math.max(0,e.userData.alertTimer-dt);

  if(e.userData.role==='boss'){
   e.userData.phase=bossPhase(e);
   e.rotation.y=Math.atan2(dx,dz);
   if(d>12)moveEnemyGround(e,player.position.x,player.position.z,e.userData.phase===2?2.0:1.45,dt);
   if(los&&d<30&&e.userData.fireCd<=0){
    enemyFire(e);
    e.userData.fireCd=e.userData.phase===2?.65:.9;
   }
   if(e.userData.phase===2){
    e.userData.missileCd=Math.max(0,e.userData.missileCd-dt);
    if(e.userData.missileCd<=0){
     spawnBossMissile(e);
     if(Math.random()>.45)spawnBossMissile(e);
     e.userData.missileCd=3.2+Math.random()*1.6;
     statusEl.textContent='GOLIAS • FASE 2 • MÍSSEIS INCOMING';
    }
   }
  }else if(e.userData.role==='sniper'){
   if(e.position.y<2){
    if(!e.userData.targetLadder)e.userData.targetLadder=nearestLadderForEnemy(e);
    const l=e.userData.targetLadder;
    if(l){
     const ld=Math.hypot(e.position.x-l.x,e.position.z-l.z);
     if(ld>1.1)moveEnemyGround(e,l.x,l.z,2.25,dt);
     else beginEnemyClimb(e,l);
    }
   }else{
    e.rotation.y=Math.atan2(dx,dz);
    if(los&&d<42&&e.userData.fireCd<=0){enemyFire(e);e.userData.fireCd=1.65+Math.random()*.8}
   }
  }else{
   if(e.userData.alertTimer>0){
    if(los&&d<11){
     e.rotation.y=Math.atan2(dx,dz);
     if(e.userData.fireCd<=0){enemyFire(e);e.userData.fireCd=.75+Math.random()*.45}
    }else{
     moveEnemyGround(e,player.position.x,player.position.z,2.4,dt);
    }
   }else{
    const r=5.5;
    const tx=e.userData.home.x+Math.cos(t*.32+e.userData.patrolAngle)*r;
    const tz=e.userData.home.z+Math.sin(t*.32+e.userData.patrolAngle)*r;
    moveEnemyGround(e,tx,tz,1.15,dt);
    e.userData.state='patrol';
   }
  }
  if(e.userData.hpBar)e.userData.hpBar.scale.x=Math.max(0,e.userData.hp/e.userData.maxHp);
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

  if(b.enemyShot){
   const center=player.position.clone();center.y+=1.4;
   const seg=next.clone().sub(old),len2=seg.lengthSq();
   let q=old.clone();
   if(len2>0){const th=THREE.MathUtils.clamp(center.clone().sub(old).dot(seg)/len2,0,1);q=old.clone().addScaledVector(seg,th)}
   if(q.distanceTo(center)<.9){
    spawnImpact(center,0xff5544,5);b.life=0;
    player.userData.hp=Math.max(0,player.userData.hp-(b.sniperShot?35:14));
    if(player.userData.hp<=0){player.userData.hp=100;player.position.set(4,0,8);statusEl.textContent='Você morreu • respawn';}
    else statusEl.textContent='Você foi atingido';
    updateHud();continue
   }
   if(segmentHitsBuilding(old,next)){b.mesh.position.copy(next);spawnImpact(next,b.color,4);b.life=0;continue}
   b.mesh.position.copy(next);continue;
  }

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
   b.mesh.position.copy(next);spawnImpact(next,b.color,weapons3D[currentWeapon]?.impact||5);b.life=0;continue;
  }

  b.mesh.position.copy(next);
  if(enemyHit){
   enemyHit.userData.hp-=b.damage;spawnImpact(enemyHit.position.clone().add(new THREE.Vector3(0,1.4,0)),0xff6b6b,weapons3D[currentWeapon]?.impact||5);b.life=0;
   if(enemyHit.userData.hp<=0){
    enemyHit.userData.alive=false;enemyHit.visible=false;kills3D++;
    if(enemyHit.userData.role==='boss'){startBossDeathCutscene();statusEl.textContent='GOLIAS DERROTADO • Boss eliminado';}
    else statusEl.textContent='Protótipo 3D ativo • Kills '+kills3D;
   }
  }
 }
 for(let i=bullets.length-1;i>=0;i--){if(bullets[i].life<=0){world.remove(bullets[i].mesh);bullets.splice(i,1)}}
}

function updateThirdPersonCamera(dt,targetObj){
 const focus=targetObj||player;
 const yaw=focus.rotation.y||0;
 const isCar=targetObj&&targetObj!==player;
 const dist=isCar?12.5:9.2;
 const height=isCar?6.8:5.6;
 const lookHeight=isCar?1.3:1.8;

 const forward=new THREE.Vector3(Math.sin(yaw),0,Math.cos(yaw));
 const desired=focus.position.clone()
   .add(new THREE.Vector3(0,height,0))
   .addScaledVector(forward,-dist);

 // leve deslocamento lateral para dar sensação mais GTA
 const right=new THREE.Vector3(forward.z,0,-forward.x);
 desired.addScaledVector(right,isCar?.8:.55);

 camera.position.lerp(desired,1-Math.exp(-dt*6.5));
 const lookAt=focus.position.clone()
   .add(new THREE.Vector3(0,lookHeight,0))
   .addScaledVector(forward,isCar?3.8:2.8);
 camera.lookAt(lookAt);
}
let last=performance.now();
function frame(now){
 const dt=Math.min(.033,(now-last)/1000);last=now;t+=dt;
 if(updateClimb(dt)){shotCooldown=Math.max(0,shotCooldown-dt);updateAimFromPointer();updateEnemies3D(dt);updateBullets3D(dt);updateVehicleSmoke(dt);updateBossMissiles(dt);updateBossDeathFx(dt);if(updateBossCutscene(dt)){renderer.render(scene,camera);requestAnimationFrame(frame);return}updateThirdPersonCamera(dt,player);updateHud();renderer.render(scene,camera);requestAnimationFrame(frame);return}
 if(updateVehicle(dt)){shotCooldown=Math.max(0,shotCooldown-dt);updateEnemies3D(dt);updateBullets3D(dt);updateWeaponFx(dt);updateVehicleSmoke(dt);updateBossMissiles(dt);updateBossDeathFx(dt);if(updateBossCutscene(dt)){renderer.render(scene,camera);requestAnimationFrame(frame);return}updateThirdPersonCamera(dt,activeCar);updateBuildingVisibility();updateHud();renderer.render(scene,camera);requestAnimationFrame(frame);return}
 let dx=((keys.has('d')?1:0)-(keys.has('a')?1:0))+(mobileMove.active?mobileMove.x:0),
     dz=((keys.has('s')?1:0)-(keys.has('w')?1:0))+(mobileMove.active?mobileMove.y:0);
 const len=Math.hypot(dx,dz);
 if(len){dx/=len;dz/=len;const speed=keys.has('shift')?10:6;const nx=player.position.x+dx*speed*dt,nz=player.position.z+dz*speed*dt;if(!blocked(nx,player.position.z))player.position.x=nx;if(!blocked(player.position.x,nz))player.position.z=nz;player.rotation.y=Math.atan2(dx,dz);const gait=Math.sin(t*(keys.has('shift')?14:10));player.userData.legs[0].rotation.x=gait*.55;player.userData.legs[1].rotation.x=-gait*.55}else{player.userData.legs[0].rotation.x*=.8;player.userData.legs[1].rotation.x*=.8}
 shotCooldown=Math.max(0,shotCooldown-dt);
 if(mobileAim.active){const mag=Math.hypot(mobileAim.x,mobileAim.y);if(mag>.12){const ang=Math.atan2(mobileAim.x,-mobileAim.y);player.rotation.y=ang;aimPoint.set(player.position.x+Math.sin(ang)*20,player.position.y+1.5,player.position.z+Math.cos(ang)*20)}if(mobileAim.firing)fire()}else updateAimFromPointer();
 updateEnemies3D(dt);updateBullets3D(dt);updateWeaponFx(dt);updateVehicleSmoke(dt);updateBossMissiles(dt);updateBossDeathFx(dt);if(updateBossCutscene(dt)){renderer.render(scene,camera);requestAnimationFrame(frame);return}
 recoilKick=Math.max(0,recoilKick-dt*2.8);
 if(player.userData.gun)player.userData.gun.position.z=-recoilKick;
 updateThirdPersonCamera(dt,player);
 updateBuildingVisibility();updateHud();renderer.render(scene,camera);requestAnimationFrame(frame);
}
applyWeaponVisual();updateHud();
requestAnimationFrame(frame);
