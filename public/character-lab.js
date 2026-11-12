import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.187.0/build/three.module.js';
import { FBXLoader } from 'https://cdn.jsdelivr.net/npm/three@0.187.0/examples/jsm/loaders/FBXLoader.js';

const canvas=document.getElementById('view');
const stateEl=document.getElementById('state');
const renderer=new THREE.WebGLRenderer({canvas,antialias:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio,1.8));
renderer.shadowMap.enabled=true;
renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.outputColorSpace=THREE.SRGBColorSpace;
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=1.15;

const scene=new THREE.Scene();
scene.background=new THREE.Color(0x151b1b);
scene.fog=new THREE.Fog(0x151b1b,35,90);
const camera=new THREE.PerspectiveCamera(56,innerWidth/innerHeight,.1,180);
scene.add(new THREE.HemisphereLight(0xc6d8e0,0x27302c,1.8));
const sun=new THREE.DirectionalLight(0xffe2bf,3.4);
sun.position.set(-12,24,-8);sun.castShadow=true;sun.shadow.mapSize.set(2048,2048);
sun.shadow.camera.left=-28;sun.shadow.camera.right=28;sun.shadow.camera.top=28;sun.shadow.camera.bottom=-28;scene.add(sun);

const floorMat=new THREE.MeshStandardMaterial({color:0x3d4542,roughness:.96});
const floor=new THREE.Mesh(new THREE.PlaneGeometry(80,80),floorMat);
floor.rotation.x=-Math.PI/2;floor.receiveShadow=true;scene.add(floor);
const grid=new THREE.GridHelper(80,80,0x65706c,0x4a514f);grid.position.y=.012;scene.add(grid);

const player=new THREE.Group();scene.add(player);
player.position.set(0,0,0);
const movement={
 velocity:new THREE.Vector3(),
 desired:new THREE.Vector3(),
 forward:new THREE.Vector3(0,0,1),
 speed:0,
 phase:0,
 grounded:true,
 vertical:0,
 crouch:0,
 run:0,
 lean:0,
 strafe:0
};
const keys=new Set();
let yaw=0,camYaw=Math.PI,camPitch=.2,drag=false,lastX=0,lastY=0;
let model=null,mixer=null,actions={},bones={},base={},activeAction=null;

addEventListener('keydown',e=>{keys.add(e.code);if(e.code==='Space'&&movement.grounded){movement.vertical=5.4;movement.grounded=false}});
addEventListener('keyup',e=>keys.delete(e.code));
canvas.addEventListener('contextmenu',e=>e.preventDefault());
canvas.addEventListener('pointerdown',e=>{if(e.button===2){drag=true;lastX=e.clientX;lastY=e.clientY;canvas.setPointerCapture?.(e.pointerId)}});
canvas.addEventListener('pointerup',e=>{if(e.button===2)drag=false});
canvas.addEventListener('pointermove',e=>{
 if(!drag)return;
 const dx=e.clientX-lastX,dy=e.clientY-lastY;lastX=e.clientX;lastY=e.clientY;
 camYaw-=dx*.006;camPitch=THREE.MathUtils.clamp(camPitch-dy*.004,-.05,.62);
});

function norm(n){return (n||'').toLowerCase().replace(/[^a-z0-9]/g,'').replace(/^mixamorig/,'')}
function rememberBone(k,b){if(!bones[k]&&b){bones[k]=b;base[k]={q:b.quaternion.clone(),p:b.position.clone()}}}
function mapBones(root){
 root.traverse(o=>{
  if(!o.isBone)return;
  const n=norm(o.name);
  if(n.includes('hips'))rememberBone('hips',o);
  else if(n==='spine')rememberBone('spine',o);
  else if(n.includes('spine1'))rememberBone('spine1',o);
  else if(n.includes('spine2'))rememberBone('spine2',o);
  else if(n.includes('leftupleg'))rememberBone('thighL',o);
  else if(n.includes('rightupleg'))rememberBone('thighR',o);
  else if(n==='leftleg')rememberBone('calfL',o);
  else if(n==='rightleg')rememberBone('calfR',o);
  else if(n.includes('leftfoot'))rememberBone('footL',o);
  else if(n.includes('rightfoot'))rememberBone('footR',o);
  else if(n.includes('leftarm'))rememberBone('armL',o);
  else if(n.includes('rightarm'))rememberBone('armR',o);
  else if(n.includes('leftforearm'))rememberBone('foreL',o);
  else if(n.includes('rightforearm'))rememberBone('foreR',o);
  else if(n.includes('leftshoulder'))rememberBone('shoulderL',o);
  else if(n.includes('rightshoulder'))rememberBone('shoulderR',o);
 });
}
function chooseAction(kind){
 const entries=Object.entries(actions);
 const names=kind==='run'?['run','sprint']:
  kind==='walk'?['walk','locomotion']:
  kind==='idle'?['idle','stand','breath']:
  kind==='jump'?['jump']:
  kind==='crouch'?['crouch']:['idle'];
 for(const n of names){const h=entries.find(([k])=>k.includes(n));if(h)return h[1]}
 return null;
}
function setAction(kind){
 const next=chooseAction(kind);
 if(activeAction===next)return;
 if(activeAction)activeAction.fadeOut(.16);
 activeAction=next;
 if(next)next.reset().fadeIn(.16).play();
}
function pose(key,x=0,y=0,z=0,alpha=.18){
 const b=bones[key],st=base[key];if(!b||!st)return;
 const q=new THREE.Quaternion().setFromEuler(new THREE.Euler(x,y,z,'XYZ'));
 const target=st.q.clone().multiply(q);
 b.quaternion.slerp(target,alpha);
}
function procedural(dt){
 if(!model||activeAction)return;
 const speed=movement.speed;
 const moving=speed>.08;
 const targetRun=keys.has('ShiftLeft')||keys.has('ShiftRight')?1:0;
 movement.run=THREE.MathUtils.lerp(movement.run,targetRun,1-Math.exp(-dt*8));
 movement.crouch=THREE.MathUtils.lerp(movement.crouch,keys.has('KeyC')?1:0,1-Math.exp(-dt*10));
 if(moving)movement.phase=(movement.phase+dt*(3.4+speed*1.35))%(Math.PI*2);
 const s=Math.sin(movement.phase),c=Math.cos(movement.phase),amp=THREE.MathUtils.clamp(speed/5.5,0,1);
 const a=.14;
 pose('thighL', s*(.48+.28*movement.run)*amp,0,0,a);
 pose('thighR',-s*(.48+.28*movement.run)*amp,0,0,a);
 pose('calfL',-Math.max(0,-s)*(.55+.35*movement.run)*amp,0,0,a);
 pose('calfR',-Math.max(0,s)*(.55+.35*movement.run)*amp,0,0,a);
 pose('footL',Math.max(0,s)*.12*amp,0,0,a);
 pose('footR',Math.max(0,-s)*.12*amp,0,0,a);
 pose('armL',-s*(.32+.22*movement.run)*amp,0,-.08,a);
 pose('armR', s*(.32+.22*movement.run)*amp,0,.08,a);
 pose('foreL',-.08-Math.max(0,s)*.22*amp,0,0,a);
 pose('foreR',-.08-Math.max(0,-s)*.22*amp,0,0,a);
 pose('hips',movement.crouch*.18, c*.055*amp, -movement.strafe*.08,a);
 pose('spine',-.08*movement.run*amp-movement.crouch*.18,-c*.035*amp,-movement.strafe*.12,a);
 pose('spine1',0,-c*.02*amp,0,a);
 pose('spine2',0,-c*.012*amp,0,a);
 if(bones.hips&&base.hips){
  const target=base.hips.p.clone();target.y-=movement.crouch*7.2+Math.abs(s)*.38*amp;
  bones.hips.position.lerp(target,1-Math.exp(-dt*12));
 }
}
function addRifle(){
 const gun=new THREE.Group();
 const m=new THREE.MeshStandardMaterial({color:0x202629,roughness:.35,metalness:.65});
 const r=new THREE.Mesh(new THREE.BoxGeometry(.9,.12,.16),m);r.position.x=.45;gun.add(r);
 const barrel=new THREE.Mesh(new THREE.BoxGeometry(.8,.055,.055),m);barrel.position.x=1.25;gun.add(barrel);
 const stock=new THREE.Mesh(new THREE.BoxGeometry(.32,.16,.19),m);stock.position.x=-.18;gun.add(stock);
 gun.rotation.set(0,-Math.PI/2,0);
 gun.position.set(-.22,1.62,-.22);
 player.add(gun);player.userData.gun=gun;
}
addRifle();

new FBXLoader().load('/assets/models/erika-archer.fbx',fbx=>{
 model=fbx;
 model.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true}});
 const box=new THREE.Box3().setFromObject(model),h=box.max.y-box.min.y;
 const scale=h>0?1.9/h:1;model.scale.setScalar(scale);
 const box2=new THREE.Box3().setFromObject(model);
 model.position.y=-box2.min.y;
 player.add(model);mapBones(model);
 const usable=(model.animations||[]).filter(c=>c.duration>.12&&c.tracks.length>0);
 if(usable.length){
  mixer=new THREE.AnimationMixer(model);
  for(const clip of usable){const a=mixer.clipAction(clip);actions[clip.name.toLowerCase()]=a}
 }
 stateEl.textContent='ERIKA READY • '+Object.keys(bones).length+' ossos';
},undefined,err=>{stateEl.textContent='erro ao carregar avatar';console.error(err)});

function resize(){
 renderer.setSize(innerWidth,innerHeight,false);
 camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();
}
addEventListener('resize',resize);resize();

const clock=new THREE.Clock();
function updateMovement(dt){
 const fwd=new THREE.Vector3(Math.sin(camYaw),0,Math.cos(camYaw));
 const right=new THREE.Vector3(fwd.z,0,-fwd.x);
 let x=(keys.has('KeyD')?1:0)-(keys.has('KeyA')?1:0);
 let z=(keys.has('KeyW')?1:0)-(keys.has('KeyS')?1:0);
 const len=Math.hypot(x,z);if(len>1){x/=len;z/=len}
 movement.desired.set(0,0,0).addScaledVector(fwd,z).addScaledVector(right,x);
 const run=(keys.has('ShiftLeft')||keys.has('ShiftRight'))&&!keys.has('KeyC');
 const maxSpeed=keys.has('KeyC')?1.7:run?5.6:3.15;
 const accel=len? (run?14:18):20;
 const target=movement.desired.multiplyScalar(maxSpeed);
 const k=1-Math.exp(-dt*accel);
 movement.velocity.lerp(target,k);
 movement.speed=movement.velocity.length();
 movement.strafe=THREE.MathUtils.lerp(movement.strafe,x,1-Math.exp(-dt*8));
 player.position.addScaledVector(movement.velocity,dt);

 if(movement.speed>.12){
  const dir=movement.velocity.clone().normalize();
  movement.forward.lerp(dir,1-Math.exp(-dt*8)).normalize();
  const targetYaw=Math.atan2(movement.forward.x,movement.forward.z);
  let d=THREE.MathUtils.euclideanModulo(targetYaw-yaw+Math.PI,Math.PI*2)-Math.PI;
  yaw+=d*(1-Math.exp(-dt*12));
  player.rotation.y=yaw;
 }
 movement.vertical-=12.5*dt;player.position.y+=movement.vertical*dt;
 if(player.position.y<=0){player.position.y=0;movement.vertical=0;movement.grounded=true}
 const actionKind=!movement.grounded?'jump':keys.has('KeyC')?'crouch':movement.speed>4?'run':movement.speed>.15?'walk':'idle';
 setAction(actionKind);
 if(mixer)mixer.update(dt);
 procedural(dt);
}
function updateCamera(dt){
 const target=player.position.clone().add(new THREE.Vector3(0,1.35,0));
 const dist=6.3,h=2.2;
 const pos=target.clone().add(new THREE.Vector3(Math.sin(camYaw)*Math.cos(camPitch)*dist,h+Math.sin(camPitch)*dist,Math.cos(camYaw)*Math.cos(camPitch)*dist));
 camera.position.lerp(pos,1-Math.exp(-dt*10));
 camera.lookAt(target);
}
function animate(){
 requestAnimationFrame(animate);
 const dt=Math.min(clock.getDelta(),.033);
 updateMovement(dt);updateCamera(dt);
 stateEl.textContent='vel '+movement.speed.toFixed(1)+' m/s • '+(movement.grounded?'chão':'ar')+' • '+(keys.has('KeyC')?'agachado':movement.speed>4?'correndo':movement.speed>.15?'andando':'idle');
 renderer.render(scene,camera);
}
animate();
