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

plane(120,100,0x3d493d,0,0,-.08);
const road=0x303738,sidewalk=0x777c75;
for(const y of [-30,0,30]){plane(120,12,road,0,y,.02);plane(120,2.2,sidewalk,0,y-7.1,.04);plane(120,2.2,sidewalk,0,y+7.1,.04)}
for(const x of [-30,0,30]){plane(12,100,road,x,0,.03);plane(2.2,100,sidewalk,x-7.1,0,.05);plane(2.2,100,sidewalk,x+7.1,0,.05)}

const buildingSpots=[
 [-45,-45,18,15],[-15,-45,17,15],[15,-45,17,15],[45,-45,18,15],
 [-45,-15,18,15],[-15,-15,17,15],[15,-15,17,15],[45,-15,18,15],
 [-45,15,18,15],[-15,15,17,15],[15,15,17,15],[45,15,18,15],
 [-45,45,18,15],[-15,45,17,15],[15,45,17,15],[45,45,18,15]
];
const buildings=[];
const ladders=[];
for(let i=0;i<buildingSpots.length;i++){
 const [x,y,w,d]=buildingSpots[i]; const h=6+(i%4)*.8;
 const b=box(w,h,d,i%3===0?0x626b68:0x707773,x,y);b.userData={index:i,w,h,d};buildings.push(b);
 const roof=box(w-.6,.35,d-.6,0x4c5553,x,y,h+.15);
 const ladder=new THREE.Group();
 for(const sx of [-.45,.45]){const rail=new THREE.Mesh(new THREE.BoxGeometry(.12,h+1,.12),mat(0xaab0a7,.55,.15));rail.position.set(sx,(h+1)/2,0);ladder.add(rail)}
 for(let yy=.5;yy<h+.7;yy+=.55){const rung=new THREE.Mesh(new THREE.BoxGeometry(1.05,.09,.10),mat(0xb8beb4,.5,.15));rung.position.set(0,yy,0);ladder.add(rung)}
 ladder.position.set(x,0,y+d/2+.18);world.add(ladder);ladders.push({building:i,group:ladder,x,z:y+d/2+.18,h});
 for(let k=0;k<2;k++)box(2.4,1.2,2.2,0x424a49,x-3+k*6,y,h+.9);
 const winMat=mat(0x2b6475,.4,.15);
 for(const sx of [-1,1]){
  const win=new THREE.Mesh(new THREE.BoxGeometry(.12,1.4,d*.55),winMat);
  win.position.set(x+sx*(w/2+.07),3.0,y);world.add(win);
 }
}

const stripeMat=mat(0xc9b34f,.8,0);
for(const y of [-30,0,30])for(let x=-56;x<58;x+=8){const s=new THREE.Mesh(new THREE.BoxGeometry(3,.09,.18),stripeMat);s.position.set(x,.11,y);world.add(s)}
for(const x of [-30,0,30])for(let y=-46;y<48;y+=8){const s=new THREE.Mesh(new THREE.BoxGeometry(.18,.09,3),stripeMat);s.position.set(x,.11,y);world.add(s)}

function makeTree(x,y){
 const g=new THREE.Group();
 const trunk=new THREE.Mesh(new THREE.CylinderGeometry(.35,.5,3.4,8),mat(0x60442e));trunk.position.y=1.7;trunk.castShadow=true;g.add(trunk);
 const crown=new THREE.Mesh(new THREE.SphereGeometry(2.25,10,8),mat(0x2e7545));crown.position.y=4.4;crown.scale.set(1,1.15,1);crown.castShadow=true;g.add(crown);
 g.position.set(x,0,y);world.add(g);
}
[[-22,-22],[22,-22],[-22,22],[22,22],[-52,8],[52,-8]].forEach(p=>makeTree(...p));

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

const player=makeSoldier(0x344154);player.position.set(5,0,8);world.add(player);
const enemies=[makeSoldier(0x4a3434),makeSoldier(0x3f4634)];
enemies[0].position.set(18,0,-7);world.add(enemies[0]);
enemies[1].position.set(-15,7.7,-15);world.add(enemies[1]);

function makeCar(x,y,rot=0){
 const g=new THREE.Group();
 const body=new THREE.Mesh(new THREE.BoxGeometry(3.8,.75,1.9),mat(0x25384d,.3,.6));body.position.y=.65;body.castShadow=true;g.add(body);
 const top=new THREE.Mesh(new THREE.BoxGeometry(2.1,.65,1.55),mat(0x477185,.25,.45));top.position.set(-.25,1.28,0);top.castShadow=true;g.add(top);
 for(const sx of [-1.25,1.25])for(const sz of [-.86,.86]){const wheel=new THREE.Mesh(new THREE.CylinderGeometry(.36,.36,.24,12),mat(0x111416));wheel.rotation.z=Math.PI/2;wheel.position.set(sx,.38,sz);g.add(wheel)}
 g.position.set(x,0,y);g.rotation.y=rot;world.add(g);
}
makeCar(-8,-30,0);makeCar(30,18,Math.PI/2);

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
statusEl.textContent='Protótipo 3D ativo • Clique para atirar • E sobe/desce escadas';



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

function updateAimFromPointer(){
 raycaster.setFromCamera(pointer,camera);
 if(raycaster.ray.intersectPlane(groundPlane,aimPoint)){
  const dx=aimPoint.x-player.position.x,dz=aimPoint.z-player.position.z;
  if(Math.hypot(dx,dz)>.01)player.rotation.y=Math.atan2(dx,dz);
 }
}

function fire(){
 if(shotCooldown>0)return;
 shotCooldown=.18;
 const origin=new THREE.Vector3();
 player.getWorldPosition(origin);origin.y+=1.75;
 const target=aimPoint.clone();target.y=1.15;
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

function updateBullets3D(dt){
 for(const b of bullets){
  const old=b.mesh.position.clone();
  b.mesh.position.addScaledVector(b.dir,b.speed*dt);b.life-=dt;
  if(bulletHitsBuilding(b.mesh.position)){b.life=0;continue}
  for(const e of enemies){
   if(!e.userData.alive)continue;
   const p=e.position.clone();p.y+=1.5;
   if(b.mesh.position.distanceTo(p)<1.05){
    e.userData.hp--;b.life=0;
    if(e.userData.hp<=0){e.userData.alive=false;e.visible=false;kills3D++;statusEl.textContent='Protótipo 3D ativo • Kills '+kills3D}
    break;
   }
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
 renderer.render(scene,camera);requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
