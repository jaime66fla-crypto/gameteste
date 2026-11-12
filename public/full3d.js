import * as THREE from 'three';
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';

const canvas=document.getElementById('view');
const stateEl=document.getElementById('state');
const renderer=new THREE.WebGLRenderer({canvas,antialias:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio,1.75));
renderer.shadowMap.enabled=true;
renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.outputColorSpace=THREE.SRGBColorSpace;
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=1.1;

const scene=new THREE.Scene();
scene.background=new THREE.Color(0x9fb4c6);
scene.fog=new THREE.Fog(0x9fb4c6,45,120);
const camera=new THREE.PerspectiveCamera(58,innerWidth/innerHeight,.1,250);

scene.add(new THREE.HemisphereLight(0xdce8f0,0x374238,1.9));
const sun=new THREE.DirectionalLight(0xffe5bd,3.5);
sun.position.set(-18,28,-14); sun.castShadow=true; sun.shadow.mapSize.set(2048,2048);
sun.shadow.camera.left=-40; sun.shadow.camera.right=40; sun.shadow.camera.top=40; sun.shadow.camera.bottom=-40;
scene.add(sun);

const floor=new THREE.Mesh(new THREE.PlaneGeometry(120,120),new THREE.MeshStandardMaterial({color:0x67736c,roughness:1}));
floor.rotation.x=-Math.PI/2; floor.receiveShadow=true; scene.add(floor);

function box(x,y,z,sx,sy,sz,color=0x7f8a86){
 const m=new THREE.Mesh(new THREE.BoxGeometry(sx,sy,sz),new THREE.MeshStandardMaterial({color,roughness:.9}));
 m.position.set(x,y+sy/2,z); m.castShadow=true; m.receiveShadow=true; scene.add(m); return m;
}
box(0,0,14,12,5,8,0x59646b);
box(-16,0,-4,9,7,10,0x6b5d55);
box(17,0,-8,11,4,9,0x565f5b);
box(0,0,-22,20,3,4,0x4d5558);
for(let i=-24;i<=24;i+=8) box(i,0,4,2,.35,8,0x484d50);

const player=new THREE.Group(); scene.add(player);
player.position.set(0,0,0);
const velocity=new THREE.Vector3();
const desired=new THREE.Vector3();
const keys=new Set();
let yaw=0,camYaw=Math.PI,camPitch=.22,vertical=0,grounded=true;
let model=null,mixer=null,actions={},active=null;
let firingCooldown=0;

addEventListener('keydown',e=>{keys.add(e.code); if(e.code==='Space'&&grounded){vertical=6; grounded=false}});
addEventListener('keyup',e=>keys.delete(e.code));
canvas.addEventListener('click',()=>canvas.requestPointerLock?.());
addEventListener('mousemove',e=>{
 if(document.pointerLockElement!==canvas)return;
 camYaw-=e.movementX*.0026; camPitch=THREE.MathUtils.clamp(camPitch-e.movementY*.0022,-.15,.62);
});
addEventListener('mousedown',e=>{ if(e.button===0) shoot(); });

function makeGun(){
 const g=new THREE.Group();
 const mat=new THREE.MeshStandardMaterial({color:0x24292d,metalness:.65,roughness:.35});
 const body=new THREE.Mesh(new THREE.BoxGeometry(.72,.12,.18),mat); body.position.z=-.32; g.add(body);
 const barrel=new THREE.Mesh(new THREE.BoxGeometry(.08,.08,.52),mat); barrel.position.z=-.9; g.add(barrel);
 const stock=new THREE.Mesh(new THREE.BoxGeometry(.18,.18,.28),mat); stock.position.z=.1; g.add(stock);
 g.position.set(.28,1.43,-.26); g.rotation.x=-.08; player.add(g); player.userData.gun=g;
}
makeGun();

new FBXLoader().load('/assets/models/erika-archer.fbx',fbx=>{
 model=fbx;
 model.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true}});
 const box3=new THREE.Box3().setFromObject(model),h=box3.max.y-box3.min.y;
 model.scale.setScalar(h>0?1.85/h:1);
 const b2=new THREE.Box3().setFromObject(model); model.position.y=-b2.min.y;
 player.add(model);
 if(model.animations?.length){
   mixer=new THREE.AnimationMixer(model);
   for(const clip of model.animations) actions[clip.name.toLowerCase()]=mixer.clipAction(clip);
 }
 stateEl.textContent='ERIKA READY';
},undefined,()=>stateEl.textContent='avatar não carregou');

function pickAction(kind){
 const names=kind==='run'?['run','sprint']:kind==='walk'?['walk','locomotion']:kind==='jump'?['jump']:['idle','stand'];
 for(const n of names){const k=Object.keys(actions).find(k=>k.includes(n)); if(k)return actions[k]}
 return null;
}
function setAction(kind){
 const next=pickAction(kind); if(next===active)return;
 if(active)active.fadeOut(.14); active=next; if(active)active.reset().fadeIn(.14).play();
}

function shoot(){
 if(firingCooldown>0)return;
 firingCooldown=.13;
 const dir=new THREE.Vector3(); camera.getWorldDirection(dir);
 const origin=camera.position.clone();
 const ray=new THREE.Raycaster(origin,dir,0,100);
 const hits=ray.intersectObjects(scene.children.filter(o=>o!==player),true);
 const end=hits[0]?.point || origin.clone().add(dir.multiplyScalar(90));
 const geo=new THREE.BufferGeometry().setFromPoints([player.position.clone().add(new THREE.Vector3(0,1.45,0)),end]);
 const line=new THREE.Line(geo,new THREE.LineBasicMaterial({color:0xffe48b}));
 scene.add(line); setTimeout(()=>scene.remove(line),55);
}

function updateMovement(dt){
 const forward=new THREE.Vector3(Math.sin(camYaw),0,Math.cos(camYaw));
 const right=new THREE.Vector3(forward.z,0,-forward.x);
 let x=(keys.has('KeyD')?1:0)-(keys.has('KeyA')?1:0);
 let z=(keys.has('KeyW')?1:0)-(keys.has('KeyS')?1:0);
 const len=Math.hypot(x,z); if(len>1){x/=len;z/=len}
 desired.set(0,0,0).addScaledVector(forward,z).addScaledVector(right,x);
 const run=keys.has('ShiftLeft')||keys.has('ShiftRight'); const max=run?6.3:3.4;
 const target=desired.multiplyScalar(max); velocity.lerp(target,1-Math.exp(-dt*16));
 player.position.addScaledVector(velocity,dt);
 if(velocity.lengthSq()>.04){
   const ty=Math.atan2(velocity.x,velocity.z);
   let d=THREE.MathUtils.euclideanModulo(ty-yaw+Math.PI,Math.PI*2)-Math.PI;
   yaw+=d*(1-Math.exp(-dt*12)); player.rotation.y=yaw;
 }
 vertical-=14*dt; player.position.y+=vertical*dt; if(player.position.y<=0){player.position.y=0;vertical=0;grounded=true}
 setAction(!grounded?'jump':velocity.length()>4?'run':velocity.length()>.15?'walk':'idle');
 if(mixer)mixer.update(dt);
 firingCooldown=Math.max(0,firingCooldown-dt);
}
function updateCamera(dt){
 const target=player.position.clone().add(new THREE.Vector3(0,1.45,0));
 const dist=5.2;
 const pos=target.clone().add(new THREE.Vector3(Math.sin(camYaw)*Math.cos(camPitch)*dist,1.5+Math.sin(camPitch)*dist,Math.cos(camYaw)*Math.cos(camPitch)*dist));
 camera.position.lerp(pos,1-Math.exp(-dt*10)); camera.lookAt(target.clone().add(new THREE.Vector3(0,.15,0)));
}
function resize(){renderer.setSize(innerWidth,innerHeight,false);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix()}
addEventListener('resize',resize);resize();

const clock=new THREE.Clock();
function loop(){
 requestAnimationFrame(loop); const dt=Math.min(clock.getDelta(),.033);
 updateMovement(dt); updateCamera(dt);
 stateEl.textContent=(grounded?'CHÃO':'AR')+' • '+velocity.length().toFixed(1)+' m/s';
 renderer.render(scene,camera);
}
loop();