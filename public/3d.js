import * as THREE from 'https://cdn.jsdelivr.net/npm/three@0.187.0/build/three.module.js';
import { createMultiplayer3D } from '/multiplayer3d.js?v=2';
import { FBXLoader } from 'https://cdn.jsdelivr.net/npm/three@0.187.0/examples/jsm/loaders/FBXLoader.js';

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
const crosshairEl=document.getElementById('crosshair');
const hitmarkerEl=document.getElementById('hitmarker');
const aimLockBtn=document.getElementById('aimLockBtn');
const mobileMove={x:0,y:0,active:false};
const mobileAim={x:0,y:0,active:false,firing:false};
let cameraYaw=0;
let cameraPitch=.08;
let cameraRightDrag=false;
let adsBlend=0;
let desktopFiring=false;
let weaponReadyUntil=0;
let cameraLastX=0;
let cameraLastY=0;
const gameSettings=(()=>{
 try{
  const saved=typeof localStorage!=='undefined'?JSON.parse(localStorage.getItem('streetMenuSettings')||'{}'):{};
  return {
   volume:Number.isFinite(Number(saved.volume))?THREE.MathUtils.clamp(Number(saved.volume),0,100):70,
   sound:saved.sound!==false,
   performance:saved.performance!==false
  };
 }catch{return {volume:70,sound:true,performance:true}}
})();
const renderer=new THREE.WebGLRenderer({canvas,antialias:!gameSettings.performance,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio,gameSettings.performance?1.35:2));
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
sun.shadow.mapSize.set(gameSettings.performance?1024:2048,gameSettings.performance?1024:2048);
sun.shadow.camera.left=-60;sun.shadow.camera.right=60;sun.shadow.camera.top=60;sun.shadow.camera.bottom=-60;
scene.add(sun);

const world=new THREE.Group();scene.add(world);
const mat=(color,rough=.85,metal=.05)=>new THREE.MeshStandardMaterial({color,roughness:rough,metalness:metal});

// Procedural WebAudio SFX: lightweight and asset-free.
let audioCtx=null,masterGain=null,engineOsc=null,engineGain=null,engineFilter=null;
let nextStepAt=0,lastImpactSound=0,nextClimbSound=0;
function ensureAudio(){
 if(!audioCtx){
  const AC=window.AudioContext||window.webkitAudioContext;
  if(!AC)return null;
  audioCtx=new AC();
  masterGain=audioCtx.createGain();masterGain.gain.value=gameSettings.sound?.6*(gameSettings.volume/100):.0001;masterGain.connect(audioCtx.destination);
 }
 if(audioCtx.state==='suspended')audioCtx.resume();
 return audioCtx;
}
function noiseBuffer(duration=.18){
 const ctx=ensureAudio();if(!ctx)return null;
 const length=Math.max(1,Math.floor(ctx.sampleRate*duration));
 const buffer=ctx.createBuffer(1,length,ctx.sampleRate),data=buffer.getChannelData(0);
 for(let i=0;i<length;i++)data[i]=Math.random()*2-1;
 return buffer;
}
function tone(freq=220,duration=.08,volume=.08,type='sine',endFreq=null){
 const ctx=ensureAudio();if(!ctx)return;
 const osc=ctx.createOscillator(),gain=ctx.createGain();
 osc.type=type;osc.frequency.setValueAtTime(freq,ctx.currentTime);
 if(endFreq)osc.frequency.exponentialRampToValueAtTime(Math.max(20,endFreq),ctx.currentTime+duration);
 gain.gain.setValueAtTime(volume,ctx.currentTime);
 gain.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+duration);
 osc.connect(gain);gain.connect(masterGain);osc.start();osc.stop(ctx.currentTime+duration+.02);
}
function burst(duration=.08,volume=.08,low=180,high=5000){
 const ctx=ensureAudio();if(!ctx)return;
 const src=ctx.createBufferSource(),filter=ctx.createBiquadFilter(),gain=ctx.createGain();
 src.buffer=noiseBuffer(duration);filter.type='bandpass';filter.frequency.value=(low+high)/2;filter.Q.value=.65;
 gain.gain.setValueAtTime(volume,ctx.currentTime);gain.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+duration);
 src.connect(filter);filter.connect(gain);gain.connect(masterGain);src.start();
}
function playShot(kind){
 ensureAudio();
 if(kind==='pistol'){burst(.075,.24,500,5000);tone(150,.10,.11,'square',70)}
 else if(kind==='smg'){burst(.055,.18,650,6000);tone(190,.065,.07,'sawtooth',90)}
 else if(kind==='rifle'){burst(.105,.29,350,4800);tone(115,.15,.15,'square',48)}
 else {burst(.16,.34,180,3600);tone(82,.20,.18,'sawtooth',38)}
}
function playReload(){burst(.035,.045,1400,6000);tone(620,.045,.035,'square',390);setTimeout(()=>tone(760,.055,.04,'square',480),85)}
function playWeaponSwitch(){tone(520,.035,.025,'square',350)}
function playImpact(){
 const now=performance.now();if(now-lastImpactSound<45)return;lastImpactSound=now;
 burst(.045,.045,900,6500);tone(210,.045,.018,'triangle',120);
}
function playFootstep(run=false,metal=false){
 burst(run?.055:.045,run?.065:.045,metal?850:120,metal?4200:950);
 tone(metal?430:95,run?.055:.045,run?.035:.022,'triangle',metal?260:62);
}
function updateFootstepAudio(moving,run){
 if(!moving)return;
 const now=performance.now()/1000;
 const interval=run?.29:.46;
 if(now>=nextStepAt){playFootstep(run,false);nextStepAt=now+interval}
}
function ensureEngine(){
 const ctx=ensureAudio();if(!ctx||engineOsc)return;
 engineOsc=ctx.createOscillator();engineGain=ctx.createGain();engineFilter=ctx.createBiquadFilter();
 engineOsc.type='sawtooth';engineOsc.frequency.value=58;
 engineFilter.type='lowpass';engineFilter.frequency.value=260;engineFilter.Q.value=1.2;
 engineGain.gain.value=.0001;engineOsc.connect(engineFilter);engineFilter.connect(engineGain);engineGain.connect(masterGain);engineOsc.start();
}
function updateEngineSound(speed=0,throttle=0,broken=false){
 ensureEngine();if(!audioCtx||!engineGain)return;
 const now=audioCtx.currentTime;
 if(broken){engineGain.gain.setTargetAtTime(.0001,now,.05);return}
 const rpm=Math.min(1,Math.abs(speed)/18);
 engineOsc.frequency.setTargetAtTime(52+rpm*92+Math.abs(throttle)*18,now,.045);
 engineFilter.frequency.setTargetAtTime(190+rpm*520,now,.06);
 engineGain.gain.setTargetAtTime(.035+rpm*.095+Math.abs(throttle)*.035,now,.07);
}
function stopEngineSound(){
 if(audioCtx&&engineGain)engineGain.gain.setTargetAtTime(.0001,audioCtx.currentTime,.08);
}
['pointerdown','keydown','touchstart'].forEach(type=>addEventListener(type,ensureAudio,{once:true,passive:true}));

function box(w,h,d,color,x,y,z=0){
 const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),mat(color));
 m.position.set(x,z+h/2,y);m.castShadow=true;m.receiveShadow=true;world.add(m);return m;
}
function plane(w,d,color,x,y,z=.01){
 const m=new THREE.Mesh(new THREE.BoxGeometry(w,.08,d),mat(color));
 m.position.set(x,z,y);m.receiveShadow=true;world.add(m);return m;
}

// Lightweight procedural urban textures: no external image downloads.
function makeUrbanTexture(kind,size=256){
 const cv=document.createElement('canvas');cv.width=cv.height=size;
 const g=cv.getContext('2d');
 if(kind==='asphalt'){
  g.fillStyle='#303738';g.fillRect(0,0,size,size);
  for(let i=0;i<2400;i++){
   const v=38+Math.floor(Math.random()*34);
   g.fillStyle=`rgba(${v},${v+2},${v+3},${.035+Math.random()*.07})`;
   const r=Math.random()*1.6+.25;g.fillRect(Math.random()*size,Math.random()*size,r,r);
  }
  for(let i=0;i<12;i++){
   g.strokeStyle=`rgba(12,15,16,${.12+Math.random()*.16})`;g.lineWidth=.6+Math.random()*1.5;
   g.beginPath();let x=Math.random()*size,y=Math.random()*size;g.moveTo(x,y);
   for(let k=0;k<5;k++){x+=Math.random()*30-15;y+=Math.random()*28-14;g.lineTo(x,y)}g.stroke();
  }
  for(let i=0;i<5;i++){
   const x=Math.random()*size,y=Math.random()*size,w=18+Math.random()*42,h=8+Math.random()*25;
   g.fillStyle='rgba(18,22,23,.16)';g.fillRect(x,y,w,h);
   g.strokeStyle='rgba(112,118,116,.09)';g.strokeRect(x+.5,y+.5,w-1,h-1);
  }
 }else if(kind==='sidewalk'){
  g.fillStyle='#777c75';g.fillRect(0,0,size,size);
  g.strokeStyle='rgba(35,40,38,.30)';g.lineWidth=1;
  const tile=32;
  for(let x=0;x<=size;x+=tile){g.beginPath();g.moveTo(x,0);g.lineTo(x,size);g.stroke()}
  for(let y=0;y<=size;y+=tile){g.beginPath();g.moveTo(0,y);g.lineTo(size,y);g.stroke()}
  for(let i=0;i<700;i++){
   const a=.025+Math.random()*.05;g.fillStyle=`rgba(20,25,22,${a})`;
   g.fillRect(Math.random()*size,Math.random()*size,1+Math.random()*2,1+Math.random()*2);
  }
 }else{
  g.fillStyle='#3d493d';g.fillRect(0,0,size,size);
  for(let i=0;i<1800;i++){
   const green=52+Math.floor(Math.random()*34);
   g.fillStyle=`rgba(${green-10},${green},${green-12},${.035+Math.random()*.08})`;
   g.fillRect(Math.random()*size,Math.random()*size,1+Math.random()*2,1+Math.random()*2);
  }
  for(let i=0;i<30;i++){
   g.fillStyle='rgba(73,64,48,.06)';
   g.beginPath();g.arc(Math.random()*size,Math.random()*size,3+Math.random()*8,0,Math.PI*2);g.fill();
  }
 }
 const tex=new THREE.CanvasTexture(cv);
 tex.wrapS=tex.wrapT=THREE.RepeatWrapping;
 tex.colorSpace=THREE.SRGBColorSpace;
 tex.anisotropy=Math.min(8,renderer.capabilities.getMaxAnisotropy());
 return tex;
}
const urbanTextures={
 asphalt:makeUrbanTexture('asphalt'),
 sidewalk:makeUrbanTexture('sidewalk'),
 ground:makeUrbanTexture('ground')
};
function texturedPlane(w,d,texture,x,y,z=.01,repeatScale=6){
 const material=new THREE.MeshStandardMaterial({map:texture.clone(),roughness:.96,metalness:.01});
 material.map.needsUpdate=true;material.map.wrapS=material.map.wrapT=THREE.RepeatWrapping;
 material.map.repeat.set(Math.max(1,w/repeatScale),Math.max(1,d/repeatScale));
 const m=new THREE.Mesh(new THREE.BoxGeometry(w,.08,d),material);
 m.position.set(x,z,y);m.receiveShadow=true;world.add(m);return m;
}

const MAP_W=146,MAP_H=104;
texturedPlane(MAP_W,MAP_H,urbanTextures.ground,0,0,-.08,9);
const road=0x303738,sidewalk=0x777c75;
const mapScale=.035,mapOffsetX=2000,mapOffsetY=1400;
const mx=v=>(v-mapOffsetX)*mapScale;
const mz=v=>(v-mapOffsetY)*mapScale;
const mw=v=>v*mapScale;

const streetX=[580,1145,1705,2245,2900,3500].map(mx);
const streetZ=[440,950,1450,2050,2520].map(mz);
const roadW=mw(160),walkW=mw(24);
for(const z of streetZ){
 texturedPlane(MAP_W,roadW,urbanTextures.asphalt,0,z,.02,8);
 texturedPlane(MAP_W,walkW,urbanTextures.sidewalk,0,z-roadW/2-walkW/2,.04,4);
 texturedPlane(MAP_W,walkW,urbanTextures.sidewalk,0,z+roadW/2+walkW/2,.04,4);
}
for(const x of streetX){
 texturedPlane(roadW,MAP_H,urbanTextures.asphalt,x,0,.03,8);
 texturedPlane(walkW,MAP_H,urbanTextures.sidewalk,x-roadW/2-walkW/2,0,.05,4);
 texturedPlane(walkW,MAP_H,urbanTextures.sidewalk,x+roadW/2+walkW/2,0,.05,4);
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

function addZonePad(x,z,w,d,color){
 const p=plane(w,d,color,x,z,.08);p.material.roughness=.95;return p;
}

// Praça central
addZonePad(0,2.5,17,13,0x59675b);
for(const [dx,dz] of [[-5,-3],[5,-3],[-5,3],[5,3]])makeTree?.(dx,2.5+dz);
const fountain=new THREE.Mesh(new THREE.CylinderGeometry(2.2,2.5,.45,20),mat(0x657a80,.4,.15));fountain.position.set(0,.28,2.5);fountain.receiveShadow=true;world.add(fountain);

// Aeroporto / pista
addZonePad(49,-41,38,15,0x3b4143);
for(let x=34;x<65;x+=6){const s=new THREE.Mesh(new THREE.BoxGeometry(3,.10,.28),mat(0xe8e6ce,.75,0));s.position.set(x,.15,-41);world.add(s)}
box(11,4.2,6.5,0x59656a,61,-31);box(7,2.5,5,0x4c565b,45,-31);

// Porto com água e docas
addZonePad(-57,39,29,20,0x274e5c);
for(const x of [-67,-60,-53,-46]){const dock=box(2,.45,12,0x715844,x,34,.08);dock.receiveShadow=true}
for(let i=0;i<5;i++)box(3.2,1.6,2.2,i%2?0x7a4d3a:0x3f6674,-66+i*4.1,44,.05);

// Distrito industrial
addZonePad(45,24,31,22,0x4b504d);
box(13,5.8,8,0x555c5b,38,19);box(11,4.8,7,0x5e625d,52,27);
for(const x of [35,42,50,57]){const tank=new THREE.Mesh(new THREE.CylinderGeometry(1.6,1.6,4.2,16),mat(0x6a7070,.65,.25));tank.position.set(x,2.15,31);tank.castShadow=true;world.add(tank)}
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

const player=makeSoldier(0x344154);player.scale.setScalar(.68);player.position.set(4,0,8);world.add(player);
configurePlayerWeapon(player);
function configurePlayerWeapon(actor){
// Recenter this weapon at its grip before mounting it on the avatar.
actor.userData.weaponParts.receiver.position.set(.22,0,0);
actor.userData.weaponParts.barrel.position.set(.85,0,0);
actor.userData.gun.rotation.y=-Math.PI/2;
}
player.userData.hp=100;player.userData.maxHp=100;
const locomotion={velocity:new THREE.Vector3(),direction:new THREE.Vector3(0,0,1),speed:0,phase:0,blend:0,run:0,planted:{L:null,R:null}};

let avatarTemplate=null;
const remotePlayers=new Map();

// Avatar loader for Erika Archer
const fbxLoader=new FBXLoader();
fbxLoader.load('/assets/models/erika-archer.fbx',function(model){
 model.traverse(function(child){
  if(child.isMesh){child.castShadow=true;child.receiveShadow=true}
 });
 const bb=new THREE.Box3().setFromObject(model);
 const height=bb.max.y-bb.min.y;
 if(height>0){const s=2.05/(height*player.scale.y);model.scale.setScalar(s)}
 const center=new THREE.Vector3();bb.getCenter(center);
 model.position.set(-center.x*model.scale.x,-bb.min.y*model.scale.y,-center.z*model.scale.z);
 model.rotation.y=0; // Erika faces +Z, the same forward axis used by aiming.
 avatarTemplate=cloneSkinnedAvatar(model);
 player.add(model);
 player.userData.avatar=model;
 player.userData.avatarBaseY=model.position.y;
 registerAvatarBones(player,model);
 // Ignore bind-pose exports and empty takes: they contain no usable motion.
 const motionClips=(model.animations||[]).filter(clip=>{
  if(clip.duration<.1)return false;
  return clip.tracks.some(track=>{
   const size=track.getValueSize();
   return track.values.some((value,i)=>i>=size&&Math.abs(value-track.values[i%size])>1e-5);
  });
 });
 if(motionClips.length>0){
  const mixer=new THREE.AnimationMixer(model);
  player.userData.avatarMixer=mixer;
  player.userData.avatarActions={};
  motionClips.forEach(function(clip){
   const action=mixer.clipAction(clip);
   action.enabled=true;
   action.setLoop(THREE.LoopRepeat,Infinity);
   player.userData.avatarActions[clip.name.toLowerCase()]=action;
  });
 }
 player.userData.avatarAnimState='';
 setAvatarMotion('idle',true);
 updateWeaponPose();
 const clipCount=model.animations?.length||0;
 const boneCount=Object.keys(player.userData.avatarBones||{}).length;
 const clipInfo=motionClips.length?' • animações importadas':' • movimento procedural';
 statusEl.textContent='Erika Archer carregada • clips '+clipCount+' • ossos '+boneCount+clipInfo;
 player.children.forEach(function(child){
  if(child!==player.userData.avatar&&child.isMesh)child.visible=false;
 });
},undefined,function(){
 statusEl.textContent='Avatar externo indisponível • usando personagem padrão';
});

function registerAvatarBones(actor,model){
 actor.userData.avatarBones={};
 const mixamoMap={
  'mixamorig:hips':'hips',
  'mixamorig:leftfoot':'footL',
  'mixamorig:rightfoot':'footR',
  'mixamorig:leftarm':'upperArmL',
  'mixamorig:rightarm':'upperArmR',
  'mixamorig:leftforearm':'foreArmL',
  'mixamorig:rightforearm':'foreArmR',
  'mixamorig:lefthand':'handL',
  'mixamorig:righthand':'handR',
  'mixamorig:leftupleg':'thighL',
  'mixamorig:rightupleg':'thighR',
  'mixamorig:leftleg':'calfL',
  'mixamorig:rightleg':'calfR',
  'mixamorig:spine':'spine',
  'mixamorig:spine1':'spine1',
  'mixamorig:spine2':'spine2',
  'mixamorig:leftshoulder':'shoulderL',
  'mixamorig:rightshoulder':'shoulderR'
 };
 const registerBone=(bone)=>{
  // FBXLoader removes punctuation; duplicate skin bones inherit the real joint.
  const normalize=name=>(name||'').toLowerCase().replace(/[^a-z0-9]/g,'').replace(/^mixamorig/,'');
  while(bone?.parent?.isBone&&normalize(bone.parent.name)===normalize(bone.name))bone=bone.parent;
  const n='mixamorig:'+normalize(bone?.name);
  const key=mixamoMap[n];
  if(key&&!actor.userData.avatarBones[key]){
   actor.userData.avatarBones[key]={bone,base:bone.rotation.clone(),baseQuaternion:bone.quaternion.clone(),basePosition:bone.position.clone(),baseModelPosition:actor.worldToLocal(bone.getWorldPosition(new THREE.Vector3())),baseModelQuaternion:actor.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(bone.getWorldQuaternion(new THREE.Quaternion()))};
  }
 };
 model.traverse(function(child){
  if(child.isSkinnedMesh&&child.skeleton?.bones){
   for(const bone of child.skeleton.bones)registerBone(bone);
  }
  if(child.isBone)registerBone(child);
 });
}

function isADS(){
 return !climbState&&!activeCar&&cameraRightDrag;
}
function isWeaponReady(){
 return !climbState&&!activeCar&&(desktopFiring||isADS()||document.pointerLockElement===canvas||
  (mobileAim.active&&Math.hypot(mobileAim.x,mobileAim.y)>.12)||t<weaponReadyUntil);
}
function rotateJointToward(joint,tip,target,actor=player){
 actor.updateMatrixWorld(true);
 const origin=joint.getWorldPosition(new THREE.Vector3());
 const from=tip.getWorldPosition(new THREE.Vector3()).sub(origin).normalize();
 const to=target.clone().sub(origin).normalize();
 if(!from.lengthSq()||!to.lengthSq())return;
 const delta=new THREE.Quaternion().setFromUnitVectors(from,to);
 const worldRotation=joint.getWorldQuaternion(new THREE.Quaternion()).premultiply(delta);
 const parentRotation=joint.parent.getWorldQuaternion(new THREE.Quaternion()).invert();
 joint.quaternion.copy(parentRotation.multiply(worldRotation));
 actor.updateMatrixWorld(true);
}
function solveArm(side,target,pole,actor=player){return solveLimb('upperArm'+side,'foreArm'+side,'hand'+side,target,pole,actor)}
function solveLimb(upperKey,lowerKey,endKey,target,pole,actor=player){
 const bones=actor.userData.avatarBones;
 const upper=bones?.[upperKey]?.bone,lower=bones?.[lowerKey]?.bone,hand=bones?.[endKey]?.bone;
 if(!upper||!lower||!hand)return;
 actor.updateMatrixWorld(true);
 const shoulder=upper.getWorldPosition(new THREE.Vector3());
 const elbow=lower.getWorldPosition(new THREE.Vector3());
 const wrist=hand.getWorldPosition(new THREE.Vector3());
 const l1=elbow.distanceTo(shoulder),l2=wrist.distanceTo(elbow);
 if(l1<.001||l2<.001)return;
 const direction=target.clone().sub(shoulder);
 const distance=THREE.MathUtils.clamp(direction.length(),Math.abs(l1-l2)+.001,l1+l2-.001);
 direction.normalize();
 const bend=pole.clone().sub(shoulder);bend.addScaledVector(direction,-bend.dot(direction)).normalize();
 const along=(l1*l1-l2*l2+distance*distance)/(2*distance);
 const height=Math.sqrt(Math.max(0,l1*l1-along*along));
 const elbowTarget=shoulder.clone().addScaledVector(direction,along).addScaledVector(bend,height);
 const wristTarget=shoulder.clone().addScaledVector(direction,distance);
 rotateJointToward(upper,lower,elbowTarget,actor);
 rotateJointToward(lower,hand,wristTarget,actor);
}
function updateWeaponPose(actor=player,aimTarget=aimPoint,ready=isWeaponReady(),weaponName=currentWeapon){
 const gun=actor.userData.gun;if(!gun)return;
 const bones=actor.userData.avatarBones;
 // Weapon meshes use +X as the barrel axis, with the trigger at the mount origin.
 const weapon=weapons3D[weaponName]||weapons3D.pistol;
 const scale=new THREE.Vector3(...weapon.scale).multiplyScalar(.5);
 const rootRotation=actor.getWorldQuaternion(new THREE.Quaternion());
 let mount=actor,position,rotation;
 if(ready){
  const pitch=Math.atan2(aimTarget.y-actor.position.y-1.45,Math.hypot(aimTarget.x-actor.position.x,aimTarget.z-actor.position.z));
  const aimRotation=rootRotation.clone().multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(-pitch,0,0)));
  const rightTarget=actor.localToWorld(new THREE.Vector3(-.25,2.12,.3));
  const direction=new THREE.Vector3(0,0,1).applyQuaternion(aimRotation);
  const supportTarget=rightTarget.clone().addScaledVector(direction,.18*weapon.scale[0]);
  solveArm('R',rightTarget,actor.localToWorld(new THREE.Vector3(-.9,1.6,.1)),actor);
  solveArm('L',supportTarget,actor.localToWorld(new THREE.Vector3(.85,1.6,.2)),actor);
  mount=bones?.handR?.bone||actor;
  position=bones?.handR?mount.getWorldPosition(new THREE.Vector3()):rightTarget;
  rotation=aimRotation.multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(0,-Math.PI/2,0)));
 }else{
  mount=bones?.spine2?.bone||actor;
  position=actor.localToWorld(new THREE.Vector3(-.38,1.8,-.42));
  rotation=rootRotation.multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(.15,0,.95)));
 }
 if(gun.parent!==mount)mount.add(gun);
 mount.updateWorldMatrix(true,false);
 gun.position.copy(mount.worldToLocal(position));
 gun.quaternion.copy(mount.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(rotation));
 gun.scale.copy(scale).divide(mount.getWorldScale(new THREE.Vector3()));
 gun.visible=actor===player?!activeCar:!actor.userData.inCar;
 gun.updateMatrixWorld(true);
 actor.userData.weaponPose=ready?'aim':'rest';
}

function findAvatarAction(kind){
 const actions=player.userData.avatarActions||{};
 const entries=Object.entries(actions);
 const keys=kind==='run'?['run','running','sprint']:
  kind==='walk'?['walk','walking','locomotion']:
  kind==='climb'?['climb','ladder']:
  ['idle','breath','stand'];
 for(const key of keys){
  const hit=entries.find(([name])=>name.includes(key));
  if(hit)return hit[1];
 }
 return null;
}
function setAvatarMotion(kind,force=false){
 if(!player.userData.avatar)return;
 if(!force&&player.userData.avatarAnimState===kind)return;
 player.userData.avatarAnimState=kind;

 const actions=player.userData.avatarActions||{};
 const next=findAvatarAction(kind);
 player.userData.avatarActiveAction=next;
 if(next){
  for(const a of Object.values(actions))if(a!==next)a.stop();
  next.reset().fadeIn(.16).play();
 }else{
  for(const a of Object.values(actions))a.stop();
 }
}
function updateProceduralAvatar(dt,moving=false,running=false,actor=player,gait=locomotion){
 const avatar=actor.userData.avatar,bones=actor.userData.avatarBones;
 if(!avatar||!bones||actor.userData.avatarActiveAction)return;
 const climbing=!!actor.userData.climbing;
 const fade=1-Math.exp(-dt*10);
 gait.blend=THREE.MathUtils.lerp(gait.blend,moving?1:0,fade);
 // Let the sprint pose build with actual speed, including acceleration/stops.
 const sprint=running?THREE.MathUtils.smoothstep(gait.speed,2.6,5.2):0;
 gait.run=THREE.MathUtils.lerp(gait.run,sprint,fade);
 const stride=THREE.MathUtils.lerp(1.55,2.65,gait.run);
 // Advance only by measured travel, so feet stop cycling against a wall.
 if(!climbing)gait.phase=(gait.phase+gait.speed*dt/stride*Math.PI*2)%(Math.PI*2);
 const phase=climbing?t*11:gait.phase;
 const s=Math.sin(phase),double=Math.cos(phase*2),weight=gait.blend;
 const alpha=1-Math.exp(-dt*16);
 const tmpEuler=new THREE.Euler(),tmpQ=new THREE.Quaternion(),targetQ=new THREE.Quaternion();
 const pose=(key,rx=0,ry=0,rz=0)=>{
  const joint=bones[key];if(!joint)return;
  tmpQ.setFromEuler(tmpEuler.set(rx,ry,rz,'XYZ'));
  targetQ.copy(joint.baseQuaternion).multiply(tmpQ);
  joint.bone.quaternion.slerp(targetQ,alpha);
 };
 const localVelocity=gait.direction.clone().applyQuaternion(actor.quaternion.clone().invert());
 const armSwing=weight*THREE.MathUtils.lerp(.22,.42,gait.run);
 pose('shoulderL',0,0,-.06);pose('shoulderR',0,0,.06);
 pose('upperArmL',climbing?-1.2+s*.3:1.28,0,climbing?0:-s*armSwing);
 pose('upperArmR',climbing?-1.2-s*.3:1.28,0,climbing?0:s*armSwing);
 pose('foreArmL',climbing?-.6+s*.25:.16+Math.max(0,-s)*armSwing,0,-.1);
 pose('foreArmR',climbing?-.6-s*.25:.16+Math.max(0,s)*armSwing,0,.1);
 const hipTwist=Math.cos(phase)*(.065+gait.run*.035)*weight,hipSway=s*.025*weight;
 const lean=weight*(.035+gait.run*.085);
 pose('hips',lean*localVelocity.z,hipTwist,hipSway-lean*localVelocity.x);
 pose('spine',lean*.65*localVelocity.z,-hipTwist*.8,-hipSway*.75-lean*.45*localVelocity.x+Math.sin(t*2)*.008);
 pose('spine1',0,-hipTwist*.35,0);pose('spine2',0,-hipTwist*.2,0);
 if(bones.hips){
  const hip=bones.hips;
  hip.bone.position.copy(hip.basePosition);
  hip.bone.position.y-=(climbing?0:weight*(.145+gait.run*.035))/(actor.scale.y*avatar.scale.y);
 }
 avatar.position.y=(actor.userData.avatarBaseY||0)+(climbing?Math.abs(s)*.025:
  (1-double)*(.012+gait.run*.012)*weight+Math.sin(t*2)*.004*(1-weight));
 for(const [side,offset] of [['L',0],['R',.5]]){
  const cycle=(phase/(Math.PI*2)+offset)%1;
  const stance=THREE.MathUtils.lerp(.62,.46,gait.run);
  const swing=cycle>stance?(cycle-stance)/(1-stance):0;
  const hipAngle=cycle<=stance?THREE.MathUtils.lerp(.5,-.42,cycle/stance):THREE.MathUtils.lerp(-.42,.5,THREE.MathUtils.smoothstep(swing,0,1));
  const knee=cycle<=stance?.08+Math.sin(cycle/stance*Math.PI)*.12:.1+Math.sin(swing*Math.PI)*(.9+gait.run*.35);
  pose('thigh'+side,climbing?(side==='L'?s:-s)*.7:hipAngle*localVelocity.z*weight,0,climbing?0:hipAngle*localVelocity.x*weight);
  // Mixamo leg X points toward -world-X: negative rotation flexes the knee.
  pose('calf'+side,climbing?-Math.max(0,side==='L'?-s:s)*.65:-knee*weight);
  pose('foot'+side,0,0,0);
  const foot=bones['foot'+side];
  if(climbing||weight<.025||!foot){gait.planted[side]=null;continue}
  actor.updateMatrixWorld(true);
  const neutral=actor.localToWorld(foot.baseModelPosition.clone());
  const reach=stride*stance*.5;
  let target;
  if(cycle<=stance){
   if(!gait.planted[side]||gait.planted[side].distanceTo(neutral)>stride*.85){
    gait.planted[side]=neutral.clone().addScaledVector(gait.direction,reach-stride*cycle);
   }
   target=gait.planted[side].clone();target.y=neutral.y;
  }else{
   gait.planted[side]=null;
   target=neutral.clone().addScaledVector(gait.direction,THREE.MathUtils.lerp(-reach,reach,THREE.MathUtils.smoothstep(swing,0,1)));
   // More heel recovery in sprint, with a soft landing at either end.
   target.y+=Math.pow(Math.sin(swing*Math.PI),1.35)*(.15+gait.run*.18);
  }
  const current=foot.bone.getWorldPosition(new THREE.Vector3());
  target.lerpVectors(current,target,weight);
  const hip=bones['thigh'+side].bone.getWorldPosition(new THREE.Vector3());
  const pole=hip.clone().add(new THREE.Vector3(0,-.2,.7).applyQuaternion(actor.quaternion));
  solveLimb('thigh'+side,'calf'+side,'foot'+side,target,pole,actor);
  // Keep the sole level in stance; add a small toe lift during the swing.
  const rotation=actor.getWorldQuaternion(new THREE.Quaternion()).multiply(foot.baseModelQuaternion);
  rotation.multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(Math.sin(swing*Math.PI)*.18,0,0)));
  const local=foot.bone.parent.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(rotation);
  foot.bone.quaternion.slerp(local,weight);
 }
 // Resting arms need anatomical targets: rotating FBX local X alone leaves
 // the elbows stiff. Aim IK is applied afterwards by updateWeaponPose.
 const aiming=actor===player?isWeaponReady():!!actor.userData.aiming;
 if(!climbing&&!aiming){
  gait.armTargets??={};
  for(const [side,sign] of [['L',1],['R',-1]]){
   const upper=bones['upperArm'+side],fore=bones['foreArm'+side],hand=bones['hand'+side];
   if(!upper||!fore||!hand)continue;
   actor.updateMatrixWorld(true);
   const shoulder=upper.bone.getWorldPosition(new THREE.Vector3());
   const elbow=fore.bone.getWorldPosition(new THREE.Vector3());
   const wrist=hand.bone.getWorldPosition(new THREE.Vector3());
   const length=shoulder.distanceTo(elbow)+elbow.distanceTo(wrist);
   const swing=-sign*Math.cos(phase)*weight;
   const offset=new THREE.Vector3(sign*.07,-length*(.91-gait.run*.2),
    length*(.12+gait.run*.22+swing*(.28+gait.run*.16))).applyQuaternion(actor.quaternion);
   const target=shoulder.clone().add(offset);
   const smoothed=gait.armTargets[side]??(gait.armTargets[side]=target.clone());
   if(smoothed.distanceTo(target)>length*2)smoothed.copy(target);
   else smoothed.lerp(target,alpha);
   const pole=shoulder.clone().add(new THREE.Vector3(sign*.25,-.35,-.5).applyQuaternion(actor.quaternion));
   solveArm(side,smoothed,pole,actor);
  }
 }else gait.armTargets=null;
}

// Free exploration: no AI soldiers, snipers, or boss are spawned.
const enemies=[];
const golias=null;

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
  player.position.copy(activeCar.position).add(side);player.position.y=0;player.visible=true;activeCar=null;stopEngineSound();tone(105,.08,.045,'triangle',68);
  statusEl.textContent='Protótipo 3D ativo • A PÉ • E veículo/escada';return true;
 }
 const car=nearestCar();
 if(car&&!car.userData.broken){activeCar=car;player.visible=false;ensureEngine();tone(74,.18,.07,'sawtooth',105);statusEl.textContent='Protótipo 3D ativo • NO CARRO • WASD dirigir • SHIFT turbo • E sair';return true}
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
 const throttle=THREE.MathUtils.clamp(((keys.has('w')?1:0)-(keys.has('s')?1:0))+(mobileMove.active?-mobileMove.y:0),-1,1);
 const steer=THREE.MathUtils.clamp(((keys.has('d')?1:0)-(keys.has('a')?1:0))+(mobileMove.active?mobileMove.x:0),-1,1);
 const max=keys.has('shift')?20:14;
 updateEngineSound(u.speed,throttle,u.broken);
 u.speed+=throttle*22*dt;
 if(!throttle)u.speed*=Math.pow(.22,dt);
 u.speed=THREE.MathUtils.clamp(u.speed,-6,max);
 const turnFactor=THREE.MathUtils.clamp(Math.abs(u.speed)/7,0,1);
 car.rotation.y+=steer*1.7*turnFactor*dt*(u.speed>=0?1:-1);
 const fx=Math.sin(car.rotation.y),fz=Math.cos(car.rotation.y);
 const nx=car.position.x+fx*u.speed*dt,nz=car.position.z+fz*u.speed*dt;
 if(carBlocked(nx,nz)){
  if(Math.abs(u.speed)>2.5){burst(.11,Math.min(.18,.045+Math.abs(u.speed)*.008),90,1800);tone(72,.12,.05,'triangle',38)}
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
  const b=buildings[l.building];
  const onTop=player.position.y>1;
  const targetZ=onTop?l.z-.65:l.z+.75;
  const d=Math.hypot(player.position.x-l.x,player.position.z-targetZ);
  if(d<2.15&&d<bestD){best=l;bestD=d}
 }
 return best;
}
function setClimbAvatar(active){
 if(!player.userData.avatar)return;
 if(active){
  // Ladder motion is solved procedurally so hands and feet stay tied to the rungs.
  for(const action of Object.values(player.userData.avatarActions||{}))action.stop();
  player.userData.avatarActiveAction=null;
  player.userData.avatarAnimState='climb-procedural';
  locomotion.planted.L=null;locomotion.planted.R=null;
 }else{
  player.userData.climbIK=null;
  setAvatarMotion('idle',true);
 }
}

function updateLadderAvatar(dt,state){
 const avatar=player.userData.avatar,bones=player.userData.avatarBones;
 if(!avatar||!bones)return;

 const goingUp=state.dir==='up';
 const dir=goingUp?1:-1;
 const progress=THREE.MathUtils.clamp(state.t/state.total,0,1);
 const cadence=1.34;
 const cycle=(state.t*cadence)%1;
 const support=Math.sin(cycle*Math.PI*2);
 const alpha=1-Math.exp(-dt*16);
 const topExit=goingUp?THREE.MathUtils.smoothstep(progress,.82,1):0;
 const bottomExit=!goingUp?THREE.MathUtils.smoothstep(progress,.84,1):0;
 const exitBlend=Math.max(topExit,bottomExit);
 const tmpEuler=new THREE.Euler(),tmpQ=new THREE.Quaternion(),targetQ=new THREE.Quaternion();

 const pose=(key,rx=0,ry=0,rz=0)=>{
  const joint=bones[key];if(!joint)return;
  tmpQ.setFromEuler(tmpEuler.set(rx,ry,rz,'XYZ'));
  targetQ.copy(joint.baseQuaternion).multiply(tmpQ);
  joint.bone.quaternion.slerp(targetQ,alpha);
 };

 // Three-point-contact posture: hips shift subtly toward the supporting side,
 // while chest stays close to the ladder instead of twisting away from it.
 pose('hips',-.06,0,support*.028*(1-exitBlend));
 pose('spine',-.16,-support*.018,-support*.022*(1-exitBlend));
 pose('spine1',-.09,0,-support*.012*(1-exitBlend));
 pose('spine2',-.035,0,support*.008*(1-exitBlend));
 pose('shoulderL',0,0,-.055);
 pose('shoulderR',0,0,.055);
 player.updateMatrixWorld(true);

 const rungStep=.55;
 const firstRung=.50;
 const ladderZ=state.ladder.z+.06;
 const bodyY=player.position.y;

 if(!state.ladderPose){
  const rungIndex=y=>Math.round((y-firstRung)/rungStep);
  state.ladderPose={
   handL:rungIndex(bodyY+1.92),
   handR:rungIndex(bodyY+1.62),
   footL:rungIndex(bodyY+.34),
   footR:rungIndex(bodyY+.06)
  };
 }

 const smooth01=v=>v<=0?0:v>=1?1:v*v*(3-2*v);
 const stepped=(key,offset)=>{
  const raw=state.t*cadence+offset;
  const whole=Math.floor(raw);
  const local=raw-whole;
  // Limb remains planted for most of the beat, then travels quickly to next rung.
  const swing=smooth01((local-.70)/.30);
  const rung=state.ladderPose[key]+dir*whole;
  return firstRung+(rung+dir*swing)*rungStep;
 };
 const lift=(offset,amount)=>{
  const local=(state.t*cadence+offset)%1;
  const p=local<0?local+1:local;
  if(p<.70)return 0;
  const u=(p-.70)/.30;
  return Math.sin(u*Math.PI)*amount*(1-exitBlend);
 };

 // Contralateral rhythm: left hand moves with right foot, then right hand with left foot.
 const handLY=stepped('handL',0);
 const footRY=stepped('footR',.06);
 const handRY=stepped('handR',.50);
 const footLY=stepped('footL',.56);

 const handL=new THREE.Vector3(state.ladder.x-.33,handLY,ladderZ-lift(0,.05));
 const handR=new THREE.Vector3(state.ladder.x+.33,handRY,ladderZ-lift(.50,.05));
 const poleL=new THREE.Vector3(state.ladder.x-.70,bodyY+1.48,ladderZ+.40);
 const poleR=new THREE.Vector3(state.ladder.x+.70,bodyY+1.48,ladderZ+.40);
 solveArm('L',handL,poleL,player);
 solveArm('R',handR,poleR,player);

 const footL=new THREE.Vector3(state.ladder.x-.21,footLY,ladderZ+.02+lift(.56,.13));
 const footR=new THREE.Vector3(state.ladder.x+.21,footRY,ladderZ+.02+lift(.06,.13));
 const hipL=bones.thighL?.bone?.getWorldPosition(new THREE.Vector3());
 const hipR=bones.thighR?.bone?.getWorldPosition(new THREE.Vector3());
 if(hipL){
  const kneePoleL=new THREE.Vector3(state.ladder.x-.31,bodyY+.68,ladderZ+.56);
  solveLimb('thighL','calfL','footL',footL,kneePoleL,player);
 }
 if(hipR){
  const kneePoleR=new THREE.Vector3(state.ladder.x+.31,bodyY+.68,ladderZ+.56);
  solveLimb('thighR','calfR','footR',footR,kneePoleR,player);
 }

 // Small compression on each weight transfer removes the robotic vertical glide.
 const compression=(1-Math.abs(Math.cos(cycle*Math.PI*2)))*.018*(1-exitBlend);
 avatar.position.y=(player.userData.avatarBaseY||0)-compression;
 avatar.position.x=support*.018*(1-exitBlend);
 avatar.rotation.x=-.025*(1-exitBlend);
 avatar.rotation.y=0;
 avatar.rotation.z=-support*.008*(1-exitBlend);
}
function startClimb(dir){
 const l=nearLadder();if(!l||climbState||activeCar)return false;
 locomotion.velocity.set(0,0,0);locomotion.speed=0;
 const b=buildings[l.building];
 const goingUp=dir==='up';
 if(goingUp&&player.position.y>1)return false;
 if(!goingUp&&player.position.y<1)return false;
 const height=b.userData.h+.45;
 climbState={
  ladder:l,dir,t:0,total:Math.max(1.8,height/3.1),
  startY:goingUp?0:height,endY:goingUp?height:0,
  startZ:goingUp?l.z+.72:l.z-.58,
  endZ:goingUp?l.z-.72:l.z+.78
 };
 player.position.x=l.x;
 player.position.z=climbState.startZ;
 player.position.y=climbState.startY;
 player.rotation.y=goingUp?Math.PI:0;
 player.userData.climbing=true;
 setClimbAvatar(true);
 statusEl.textContent=goingUp?'Subindo escada…':'Descendo escada…';
 return true;
}
function updateClimb(dt){
 if(!climbState)return false;
 const s=climbState;
 if(t>=nextClimbSound){playFootstep(false,true);nextClimbSound=t+.34;}
 s.t=Math.min(s.total,s.t+dt);
 const p=s.t/s.total;
 const travel=THREE.MathUtils.smoothstep(p,0,1);
 player.position.x=s.ladder.x;
 // Keep a steady climb for most of the ladder, then ease into the roof/floor transition.
 player.position.y=THREE.MathUtils.lerp(s.startY,s.endY,travel);
 // Going up: stay outside the facade until the final roof transition.
 // Going down: step over the roof edge immediately, then descend on the exterior side.
 const edgeBlend=s.dir==='up'
  ? THREE.MathUtils.smoothstep(p,.78,1)
  : THREE.MathUtils.smoothstep(p,0,.18);
 player.position.z=THREE.MathUtils.lerp(s.startZ,s.endZ,edgeBlend);
 // Going up stays facing the ladder. Going down starts facing the roof edge,
 // then turns toward the ladder as soon as the body moves onto the exterior side.
 if(s.dir==='up')player.rotation.y=Math.PI;
 else{
  const turn=THREE.MathUtils.smoothstep(p,.04,.22);
  player.rotation.y=THREE.MathUtils.lerp(0,Math.PI,turn);
 }

 const cycle=Math.sin(s.t*11);
 if(player.userData.legs?.length>=2){
  player.userData.legs[0].rotation.x=cycle*.82;
  player.userData.legs[1].rotation.x=-cycle*.82;
 }
 if(player.userData.gun)player.userData.gun.rotation.z=cycle*.05;
 if(player.userData.avatar){
  updateLadderAvatar(dt,s);
 }

 if(s.t>=s.total){
  player.position.y=s.endY;
  player.position.z=s.endZ;
  if(player.userData.legs?.length>=2){
   player.userData.legs[0].rotation.x=0;
   player.userData.legs[1].rotation.x=0;
  }
  if(player.userData.gun)player.userData.gun.rotation.z=0;
  if(player.userData.avatar){
   player.userData.avatar.position.set(0,player.userData.avatarBaseY||0,0);
   player.userData.avatar.rotation.set(0,0,0);
   locomotion.planted.L=null;locomotion.planted.R=null;
  }
  player.userData.climbing=false;
  setClimbAvatar(false);
  statusEl.textContent=s.dir==='up'?'Telhado alcançado • E na escada para descer':'No solo • E na escada para subir';
  climbState=null;
 }
 return true;
}


const keys=new Set();let t=0;
addEventListener('keydown',e=>{if(['INPUT','TEXTAREA','SELECT'].includes(e.target?.tagName))return;const k=e.key.toLowerCase();keys.add(k);if(k==='1')setWeapon('pistol');if(k==='2')setWeapon('smg');if(k==='3')setWeapon('rifle');if(k==='4')setWeapon('shotgun');if(k==='e'){if(!toggleVehicle()){if(player.position.y<1)startClimb('up');else startClimb('down')}}});
addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));
document.getElementById('resetBtn')?.addEventListener('click',()=>player.position.set(5,0,8));
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
 state.firing=Math.hypot(state.x,state.y)>.58;
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
 pistol:{label:'PISTOLA',cooldown:.24,damage:1,speed:56,spread:.012,pellets:1,color:0xffdf78,recoil:.18,scale:[.72,.82,.72],impact:4,tracerLength:1.15,tracerRadius:.022,tracerGlow:.055},
 smg:{label:'SMG',cooldown:.085,damage:.55,speed:64,spread:.045,pellets:1,color:0xffc85a,recoil:.12,scale:[1.0,.92,.82],impact:4,tracerLength:1.35,tracerRadius:.018,tracerGlow:.05},
 rifle:{label:'RIFLE',cooldown:.19,damage:1.7,speed:82,spread:.009,pellets:1,color:0xffefad,recoil:.28,scale:[1.35,1,1],impact:6,tracerLength:2.2,tracerRadius:.024,tracerGlow:.065},
 shotgun:{label:'ESCOPETA',cooldown:.62,damage:.52,speed:52,spread:.12,pellets:7,color:0xffb85c,recoil:.42,scale:[1.48,1.12,1.05],impact:8,tracerLength:.75,tracerRadius:.014,tracerGlow:.038}
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
 if(bossHud)bossHud.hidden=!golias?.userData?.alive;
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
 currentWeapon=name;playWeaponSwitch();applyWeaponVisual();updateHud();
 statusEl.textContent='Arma: '+weapons3D[name].label+' • 1-4 troca • clique atira';
}
function spawnMuzzle(origin){
 const light=new THREE.PointLight(0xffc56a,8,5,2);light.position.copy(origin);scene.add(light);
 const flash=new THREE.Mesh(new THREE.SphereGeometry(.23,8,6),new THREE.MeshBasicMaterial({color:0xffe09a,transparent:true,opacity:.95}));
 flash.position.copy(origin);world.add(flash);muzzleFx.push({light,flash,t:.07});
}
function spawnImpact(pos,color=0xffd58a,count=5){
 playImpact();
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
 dir.x+=(Math.random()-.5)*spread;
 dir.y+=(Math.random()-.5)*spread*.55;
 dir.z+=(Math.random()-.5)*spread;
 dir.normalize();

 const length=weapon.tracerLength||1.1;
 const radius=weapon.tracerRadius||.02;
 const glowRadius=weapon.tracerGlow||radius*2.4;
 const group=new THREE.Group();

 // Bright projectile core.
 const core=new THREE.Mesh(
  new THREE.CylinderGeometry(radius,radius*.72,length,6,1,true),
  new THREE.MeshBasicMaterial({color:weapon.color||0xffdd75,transparent:true,opacity:.98,depthWrite:false,blending:THREE.AdditiveBlending})
 );
 group.add(core);

 // Soft halo around the tracer gives speed without making the projectile look like a rod.
 const glow=new THREE.Mesh(
  new THREE.CylinderGeometry(glowRadius,glowRadius*.6,length*1.18,6,1,true),
  new THREE.MeshBasicMaterial({color:weapon.color||0xffdd75,transparent:true,opacity:.20,depthWrite:false,blending:THREE.AdditiveBlending})
 );
 group.add(glow);

 // Tiny hot tip, especially visible on pistol/rifle shots.
 const tip=new THREE.Mesh(
  new THREE.SphereGeometry(Math.max(radius*1.8,.028),6,4),
  new THREE.MeshBasicMaterial({color:0xffffff,transparent:true,opacity:.9,depthWrite:false,blending:THREE.AdditiveBlending})
 );
 tip.position.y=length*.5;
 group.add(tip);

 // Cylinder geometry points along +Y; rotate the whole tracer into its actual flight direction.
 group.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),dir);
 group.position.copy(origin).addScaledVector(dir,length*.5);
 world.add(group);

 const bullet={
  mesh:group,dir,speed:weapon.speed,life:1.15,damage:weapon.damage,color:weapon.color,
  tracerLength:length,core,glow,tip
 };
 bullets.push(bullet);return bullet;
}

function topSurfaceAt(x,z){
 let y=0;
 for(const b of buildings){
  const dx=Math.abs(x-b.position.x),dz=Math.abs(z-b.position.z);
  if(dx<=b.userData.w/2&&dz<=b.userData.d/2)y=Math.max(y,b.userData.h+.45);
 }
 return y;
}
// The same volumes resolve the reticle and each projectile segment.
function traceAimRay(ray,maxDistance=100,includeGround=false,excludedId=null){
 let best=null;
 const consider=(point,kind,object=null)=>{
  if(!point)return;
  const distance=point.distanceTo(ray.origin);
  if(distance<=maxDistance&&(!best||distance<best.distance))best={point:point.clone(),distance,kind,object};
 };
 for(const b of buildings){
  const {w,h,d}=b.userData;
  const volume=new THREE.Box3(new THREE.Vector3(b.position.x-w/2,0,b.position.z-d/2),new THREE.Vector3(b.position.x+w/2,h+.6,b.position.z+d/2));
  if(volume.containsPoint(ray.origin))consider(ray.origin,'wall',b);
  else consider(ray.intersectBox(volume,new THREE.Vector3()),'wall',b);
 }
 for(const e of [...enemies,...[...remotePlayers.values()].map(remote=>remote.actor)]){
  if(!e.userData.alive||(excludedId&&e.userData.networkId===excludedId))continue;
  const center=e.position.clone().add(new THREE.Vector3(0,1.5,0));
  const volume=new THREE.Sphere(center,1);
  if(volume.containsPoint(ray.origin))consider(ray.origin,'enemy',e);
  else consider(ray.intersectSphere(volume,new THREE.Vector3()),'enemy',e);
 }
 if(includeGround)consider(ray.intersectPlane(groundPlane,new THREE.Vector3()),'ground');
 return best;
}
function mobileAimDirection(x,y){
 const forward=new THREE.Vector3(-Math.sin(cameraYaw),0,-Math.cos(cameraYaw));
 const right=new THREE.Vector3(Math.cos(cameraYaw),0,-Math.sin(cameraYaw));
 return forward.multiplyScalar(-y).addScaledVector(right,x).normalize();
}
function placeReticle(point=null){
 let x=50,y=50,visible=true;
 if(point){
  const projected=point.clone().project(camera);
  visible=projected.z>=-1&&projected.z<=1&&Math.abs(projected.x)<=1&&Math.abs(projected.y)<=1;
  x=(projected.x+1)*50;y=(1-projected.y)*50;
 }
 for(const el of [crosshairEl,hitmarkerEl])if(el){el.style.left=x+'%';el.style.top=y+'%';el.style.visibility=visible?'visible':'hidden'}
}
function updateAimFromPointer(){
 camera.updateMatrixWorld(true);
 if(mobileAim.active&&Math.hypot(mobileAim.x,mobileAim.y)>.12){
  const origin=player.position.clone().add(new THREE.Vector3(0,1.45,0));
  const direction=mobileAimDirection(mobileAim.x,mobileAim.y);
  raycaster.ray.set(origin,direction);
 }else raycaster.setFromCamera(pointer,camera); // NDC (0,0): the visible center dot.
 const hit=traceAimRay(raycaster.ray,100,true);
 aimPoint.copy(hit?hit.point:raycaster.ray.at(100,new THREE.Vector3()));
 placeReticle(mobileAim.active?aimPoint:null);
 crosshairEl?.classList.toggle('on-target',hit?.kind==='enemy');
 const dx=aimPoint.x-player.position.x,dz=aimPoint.z-player.position.z;
 if(isWeaponReady()&&Math.hypot(dx,dz)>.01)player.rotation.y=Math.atan2(dx,dz);
}
function showHitmarker(killed=false){
 if(!hitmarkerEl)return;
 hitmarkerEl.classList.toggle('kill',killed);
 hitmarkerEl.classList.remove('active');
 void hitmarkerEl.offsetWidth;
 hitmarkerEl.classList.add('active');
}

function fire(){
 if(shotCooldown>0||climbState||activeCar)return;
 const weapon=weapons3D[currentWeapon];
 const ammo=ammoState[currentWeapon];
 if(ammo.mag<=0){
  if(ammo.reserve<=0){statusEl.textContent='Sem munição • troque de arma';return}
  const size=currentWeapon==='pistol'?12:currentWeapon==='smg'?30:currentWeapon==='rifle'?20:8;
  const load=Math.min(size,ammo.reserve);ammo.mag=load;ammo.reserve-=load;updateHud();playReload();
  statusEl.textContent='Recarregado • '+weapon.label;
  return;
 }
 ammo.mag--;
 playShot(currentWeapon);
 shotCooldown=weapon.cooldown;
 weaponReadyUntil=t+2.5;
 updateAimFromPointer();
 updateWeaponPose();
 player.updateMatrixWorld(true);
 const barrel=player.userData.weaponParts?.barrel;
 const origin=barrel?barrel.localToWorld(new THREE.Vector3(.36,0,0)):player.position.clone().add(new THREE.Vector3(0,1.45,0));
 // A muzzle beyond a close wall must not shoot through it.
 const shoulder=player.position.clone().add(new THREE.Vector3(0,1.45,0));
 const clearance=origin.clone().sub(shoulder);
 const obstruction=traceAimRay(new THREE.Ray(shoulder,clearance.clone().normalize()),clearance.length());
 if(obstruction?.kind==='wall'){spawnImpact(obstruction.point,weapon.color,weapon.impact);updateHud();return}
 const target=aimPoint.clone();
 spawnMuzzle(origin);
 recoilKick=Math.min(.55,recoilKick+weapon.recoil);
 const fired=[];for(let i=0;i<weapon.pellets;i++)fired.push(makeTracer(origin,target,weapon));
 const shotId=multiplayer.shoot({weapon:currentWeapon,origin:{x:origin.x,y:origin.y,z:origin.z},rays:fired.map(b=>({x:b.dir.x,y:b.dir.y,z:b.dir.z}))});
 fired.forEach((bullet,pellet)=>{bullet.networkShotId=shotId;bullet.pellet=pellet});
 updateHud();
}

canvas.addEventListener('contextmenu',e=>e.preventDefault());
// Mouse uses mousedown/mouseup instead of pointerdown so a second button
// still fires while another mouse button is already held (RMB aim + LMB shoot).
canvas.addEventListener('mousedown',e=>{
 if(e.button===2){
  cameraRightDrag=true;
  cameraLastX=e.clientX;cameraLastY=e.clientY;
  e.preventDefault();
 }
 if(e.button===0){
  desktopFiring=true;
  fire();
  e.preventDefault();
 }
});
addEventListener('mouseup',e=>{
 if(e.button===2)cameraRightDrag=false;
 if(e.button===0)desktopFiring=false;
});
// Touch aiming/firing remains handled by the on-screen sticks.
canvas.addEventListener('pointercancel',()=>{desktopFiring=false;cameraRightDrag=false});
addEventListener('blur',()=>{keys.clear();cameraRightDrag=false;desktopFiring=false;mobileMove.active=false;mobileAim.active=false;mobileAim.firing=false});
aimLockBtn?.addEventListener('click',()=>{
 if(document.pointerLockElement===canvas){document.exitPointerLock();return}
 try{const request=canvas.requestPointerLock?.();request?.catch(()=>{statusEl.textContent='Use o botão direito para girar a câmera'})}
 catch{statusEl.textContent='Use o botão direito para girar a câmera'}
});
document.addEventListener('pointerlockchange',()=>{
 cameraRightDrag=false;
 desktopFiring=false;
 if(aimLockBtn)aimLockBtn.textContent=document.pointerLockElement===canvas?'Soltar mouse (ESC)':'Travar mouse';
});
document.addEventListener('pointerlockerror',()=>{statusEl.textContent='Use o botão direito para girar a câmera'});
addEventListener('pointermove',e=>{
 if(e.pointerType==='touch')return;
 const locked=document.pointerLockElement===canvas;
 if(!locked&&!cameraRightDrag)return;
 const dx=locked?e.movementX:e.clientX-cameraLastX,dy=locked?e.movementY:e.clientY-cameraLastY;
 cameraLastX=e.clientX;cameraLastY=e.clientY;
 const aimSensitivity=isADS()?.68:1;
 cameraYaw-=dx*.004*aimSensitivity;
 cameraPitch=THREE.MathUtils.clamp(cameraPitch+dy*.003*aimSensitivity,-.65,.95);
});

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
 if(!golias||bossCutscene.active||bossCutscene.started)return;
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
 if(!golias||!bossCutscene.active)return false;
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
 const target=player.position.clone();target.y+=1.15;
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
    e.userData.fireCd=e.userData.phase===2 ? .65 : .9;
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
  const center=b.mesh.position.clone();
  const half=b.tracerLength*.5;
  const old=center.clone().addScaledVector(b.dir,-half);
  const next=center.clone().addScaledVector(b.dir,b.speed*dt);
  const nextHead=next.clone().addScaledVector(b.dir,half);
  b.life-=dt;
  const fade=THREE.MathUtils.clamp(b.life/.18,0,1);
  if(b.core)b.core.material.opacity=.98*fade;
  if(b.glow)b.glow.material.opacity=.20*fade;
  if(b.tip)b.tip.material.opacity=.9*fade;

  if(b.enemyShot){
   const center=player.position.clone();center.y+=1.15;
   const seg=next.clone().sub(old),len2=seg.lengthSq();
   let q=old.clone();
   if(len2>0){const th=THREE.MathUtils.clamp(center.clone().sub(old).dot(seg)/len2,0,1);q=old.clone().addScaledVector(seg,th)}
   if(q.distanceTo(center)<.9){
    spawnImpact(center,0xff5544,5);b.life=0;
    player.userData.hp=Math.max(0,player.userData.hp-(b.sniperShot?35:14));
    if(player.userData.hp<=0){player.userData.hp=100;player.position.set(4,0,8);statusEl.textContent='Você morreu • respawn'}
    else statusEl.textContent='Você foi atingido';
    updateHud();continue
   }
   if(segmentHitsBuilding(old,nextHead)){b.mesh.position.copy(next);spawnImpact(nextHead,b.color,4);b.life=0;continue}
   b.mesh.position.copy(next);continue;
  }

  const segment=nextHead.clone().sub(old);
  const hit=traceAimRay(new THREE.Ray(old,segment.clone().normalize()),segment.length(),true,b.ownerId||null);
  b.mesh.position.copy(hit?hit.point.clone().addScaledVector(b.dir,-half):next);
  if(hit){
   b.life=0;
   spawnImpact(hit.point,hit.kind==='enemy'?0xff6b6b:b.color,5);
   if(hit.kind==='enemy'){
    const enemyHit=hit.object;
    if(b.remoteShot)continue;
    if(enemyHit.userData.networkId){if(b.networkShotId)multiplayer.hit(b.networkShotId,b.pellet,enemyHit.userData.networkId);continue}
    enemyHit.userData.hp-=b.damage;
    const killed=enemyHit.userData.hp<=0;
    showHitmarker(killed);
    if(killed){
     enemyHit.userData.alive=false;enemyHit.visible=false;kills3D++;
     if(enemyHit.userData.role==='boss'){startBossDeathCutscene();statusEl.textContent='GOLIAS DERROTADO • Boss eliminado'}
     else statusEl.textContent='Protótipo 3D ativo • Kills '+kills3D;
    }
   }
  }
 }
 for(let i=bullets.length-1;i>=0;i--){if(bullets[i].life<=0){world.remove(bullets[i].mesh);bullets.splice(i,1)}}
}

function updateThirdPersonCamera(dt,targetObj){
 const focus=targetObj||player;
 const isCar=targetObj&&targetObj!==player;

 // RMB ADS: smooth over-the-shoulder zoom instead of an instant camera snap.
 const adsTarget=!isCar&&isADS()?1:0;
 adsBlend=THREE.MathUtils.lerp(adsBlend,adsTarget,1-Math.exp(-dt*(adsTarget?14:10)));
 const dist=isCar?12.5:THREE.MathUtils.lerp(5.8,3.15,adsBlend);
 const lookHeight=isCar?2.4:THREE.MathUtils.lerp(1.8,1.72,adsBlend);
 const shoulder=isCar?0:THREE.MathUtils.lerp(.85,1.05,adsBlend);
 const targetFov=isCar?58:THREE.MathUtils.lerp(58,49,adsBlend);
 if(Math.abs(camera.fov-targetFov)>.01){
  camera.fov=THREE.MathUtils.lerp(camera.fov,targetFov,1-Math.exp(-dt*14));
  camera.updateProjectionMatrix();
 }

 const horizontal=Math.cos(cameraPitch)*dist;
 const right=new THREE.Vector3(Math.cos(cameraYaw),0,-Math.sin(cameraYaw));
 const desired=focus.position.clone().add(new THREE.Vector3(
  Math.sin(cameraYaw)*horizontal,
  lookHeight+Math.sin(cameraPitch)*dist,
  Math.cos(cameraYaw)*horizontal
 )).addScaledVector(right,shoulder);
 // Keep the camera outside solid buildings while orbiting near a facade.
 const anchor=focus.position.clone().add(new THREE.Vector3(0,lookHeight,0));
 const offset=desired.clone().sub(anchor),length=offset.length();
 const cameraRay=new THREE.Ray(anchor,offset.clone().normalize());
 let distance=length;
 for(const b of buildings){
  const {w,h,d}=b.userData;
  const volume=new THREE.Box3(new THREE.Vector3(b.position.x-w/2-.2,-.2,b.position.z-d/2-.2),new THREE.Vector3(b.position.x+w/2+.2,h+.8,b.position.z+d/2+.2));
  const hit=cameraRay.intersectBox(volume,new THREE.Vector3());
  if(hit)distance=Math.min(distance,Math.max(.35,hit.distanceTo(anchor)-.2));
 }
 desired.copy(cameraRay.at(distance,new THREE.Vector3()));
 camera.position.lerp(desired,1-Math.exp(-dt*12));
 const viewDirection=new THREE.Vector3(-Math.sin(cameraYaw)*Math.cos(cameraPitch),-Math.sin(cameraPitch),-Math.cos(cameraYaw)*Math.cos(cameraPitch));
 camera.lookAt(camera.position.clone().add(viewDirection));
 camera.updateMatrixWorld(true);
}
function cloneSkinnedAvatar(source){
 const clone=source.clone(true),originals=[],copies=[],lookup=new Map();
 source.traverse(node=>originals.push(node));clone.traverse(node=>copies.push(node));
 originals.forEach((node,i)=>lookup.set(node,copies[i]));
 for(let i=0;i<copies.length;i++)if(originals[i].isSkinnedMesh){
  const mesh=copies[i],original=originals[i];
  mesh.skeleton=original.skeleton.clone();mesh.skeleton.bones=original.skeleton.bones.map(bone=>lookup.get(bone));
  mesh.bind(mesh.skeleton,original.bindMatrix);
 }
 return clone;
}
function attachNetworkAvatar(actor){
 if(!avatarTemplate||actor.userData.avatar)return;
 const model=cloneSkinnedAvatar(avatarTemplate);actor.add(model);
 actor.userData.avatar=model;actor.userData.avatarBaseY=model.position.y;
 registerAvatarBones(actor,model);
 actor.children.forEach(child=>{if(child.isMesh)child.visible=false});
}
function remoteState(state){
 if(!state?.id||![state.x,state.y,state.z,state.angle].every(Number.isFinite))return;
 let remote=remotePlayers.get(state.id);
 if(!remote){
  const actor=makeSoldier(0x385778);actor.scale.setScalar(.68);configurePlayerWeapon(actor);
  actor.position.set(state.x,state.y,state.z);actor.userData.networkId=state.id;actor.userData.alive=true;
  const labelCanvas=document.createElement('canvas');labelCanvas.width=256;labelCanvas.height=48;
  const texture=new THREE.CanvasTexture(labelCanvas);texture.colorSpace=THREE.SRGBColorSpace;
  const label=new THREE.Sprite(new THREE.SpriteMaterial({map:texture,transparent:true,depthTest:false}));label.position.y=3.7;label.scale.set(3.6,.68,1);actor.add(label);
  remote={actor,target:new THREE.Vector3(),state,label,labelCanvas,texture,labelName:'',nextAnimAt:0,motion:{velocity:new THREE.Vector3(),direction:new THREE.Vector3(0,0,1),speed:0,phase:0,blend:0,run:0,planted:{L:null,R:null}}};
  remotePlayers.set(state.id,remote);world.add(actor);attachNetworkAvatar(actor);
 }
 remote.state=state;remote.target.set(state.x,state.y,state.z);remote.actor.userData.hp=state.health;remote.actor.userData.alive=state.health>0;
 const nextName=String(state.name||'Jogador').slice(0,18);
 if(remote.labelName!==nextName){
  remote.labelName=nextName;
  const ctx=remote.labelCanvas.getContext('2d');ctx.clearRect(0,0,256,48);ctx.fillStyle='#071019dd';ctx.fillRect(0,0,256,48);ctx.fillStyle='#8edaff';ctx.font='bold 24px system-ui';ctx.textAlign='center';ctx.fillText(nextName,128,32);remote.texture.needsUpdate=true;
 }
}
function removeRemote(id){
 const remove=remote=>{world.remove(remote.actor);if(remote.car)world.remove(remote.car);remote.texture.dispose()};
 if(id===null){for(const remote of remotePlayers.values())remove(remote);remotePlayers.clear();return}
 const remote=remotePlayers.get(id);if(remote)remove(remote);remotePlayers.delete(id);
}
function localNetworkState(){
 return {x:player.position.x,y:player.position.y,z:player.position.z,angle:player.rotation.y,weapon:currentWeapon,
  moving:locomotion.speed>.05,running:locomotion.run>.5,climbing:!!climbState,aiming:isWeaponReady(),inCar:!!activeCar,
  pitch:Math.atan2(aimPoint.y-player.position.y-1.45,Math.hypot(aimPoint.x-player.position.x,aimPoint.z-player.position.z))};
}
function updateMultiplayer(dt){
 multiplayer.update(dt,localNetworkState());
 const now=performance.now();
 for(const remote of remotePlayers.values()){
  const {actor,state,motion}=remote,before=actor.position.clone();
  const distToLocal=actor.position.distanceTo(player.position);
  if(actor.position.distanceTo(remote.target)>8){actor.position.copy(remote.target);motion.planted.L=null;motion.planted.R=null}
  else actor.position.lerp(remote.target,1-Math.exp(-dt*20));
  const turn=Math.atan2(Math.sin(state.angle-actor.rotation.y),Math.cos(state.angle-actor.rotation.y));actor.rotation.y+=turn*(1-Math.exp(-dt*20));
  const travel=actor.position.clone().sub(before);travel.y=0;motion.speed=Math.min(6,travel.length()/Math.max(dt,.001));
  if(travel.lengthSq()>.00001)motion.direction.copy(travel).normalize();
  actor.userData.climbing=state.climbing;actor.userData.inCar=state.inCar;actor.userData.aiming=state.aiming;

  // Keep movement interpolation every frame, but throttle expensive skeleton IK/weapon posing.
  const animInterval=distToLocal>35?100:distToLocal>18?66:33;
  if(!remote.nextAnimAt||now>=remote.nextAnimAt){
   remote.nextAnimAt=now+animInterval;
   attachNetworkAvatar(actor);
   updateProceduralAvatar(animInterval/1000,motion.speed>.05,state.running,actor,motion);
   const target=actor.position.clone().add(new THREE.Vector3(Math.sin(state.angle)*20,1.45+Math.tan(state.pitch||0)*20,Math.cos(state.angle)*20));
   updateWeaponPose(actor,target,state.aiming&&!state.climbing,state.weapon);
  }
  if(!actor.userData.avatar){const gait=Math.sin(t*(state.running?12:8))*(state.moving?.5:0);actor.userData.legs[0].rotation.x=gait;actor.userData.legs[1].rotation.x=-gait}
  if(state.inCar&&!remote.car&&cars[0]){remote.car=cars[0].clone(true);world.add(remote.car)}
  if(remote.car){remote.car.visible=state.inCar;remote.car.position.copy(actor.position);remote.car.rotation.y=actor.rotation.y}
  actor.visible=state.health>0;
  if(remote.label)remote.label.visible=distToLocal<45&&!state.inCar&&state.health>0;
  if(actor.userData.avatar)actor.userData.avatar.visible=!state.inCar;
 }
}
const multiplayer=createMultiplayer3D({
 url:room=>(location.protocol==='https:'?'wss:':'ws:')+'//'+location.host+'/ws?mode=3d&room='+encodeURIComponent(room),
 onState:remoteState,onLeave:removeRemote,
 onStatus:(status,room)=>{
  const labels={solo:'Solo • sem bots',connecting:'Conectando à sala '+room+'…',connected:'Online • sala '+room,offline:'Desconectado • tentando reconectar',error:'Falha na conexão • tentando reconectar'};
  const label=document.getElementById('onlineStatus');if(label)label.textContent=labels[status]||status;
  if(status==='connected'){document.getElementById('onlinePanel').hidden=true;multiplayer.update(1,localNetworkState())}
 },
 onRanking:players=>{
  const roster=document.getElementById('onlineRoster');if(roster)roster.textContent=players.length?players.length+' jogador(es)\n'+players.slice(0,5).map((p,i)=>(i+1)+'. '+p.name+' — '+p.kills).join('\n'):'';
  const me=players.find(p=>p.id===multiplayer.id);if(me)kills3D=me.kills;
 },
 onShot:shot=>{
  const weapon=weapons3D[shot.weapon];if(!weapon)return;
  const origin=new THREE.Vector3(shot.origin.x,shot.origin.y,shot.origin.z);spawnMuzzle(origin);
  for(const direction of shot.rays){const dir=new THREE.Vector3(direction.x,direction.y,direction.z);const bullet=makeTracer(origin,origin.clone().add(dir),{...weapon,spread:0});bullet.remoteShot=true;bullet.ownerId=shot.ownerId}
 },
 onHit:(hit,id)=>{
  if(hit.attackerId===id){showHitmarker(hit.killed);kills3D=hit.kills}
  if(hit.targetId===id){player.userData.hp=hit.health;statusEl.textContent=hit.killed?'Você foi eliminado • retornando ao mapa':'Você foi atingido';updateHud()}
  else{const remote=remotePlayers.get(hit.targetId);if(remote){remote.actor.userData.hp=hit.health;remote.actor.userData.alive=hit.health>0;remote.actor.visible=hit.health>0}}
 },
 onRespawn:(state,id)=>{
  if(state.id===id){
   if(activeCar){activeCar=null;player.visible=true}climbState=null;player.userData.climbing=false;
   player.position.set(state.x,state.y,state.z);player.userData.hp=100;locomotion.velocity.set(0,0,0);locomotion.planted.L=null;locomotion.planted.R=null;
   desktopFiring=false;mobileAim.firing=false;updateHud();multiplayer.update(1,localNetworkState());
  }else{const remote=remotePlayers.get(state.id);if(remote){remote.actor.position.set(state.x,state.y,state.z);remote.target.copy(remote.actor.position);remote.state.health=100;remote.actor.userData.alive=true;remote.actor.userData.hp=100}}
 }
});
document.getElementById('multiplayerBtn')?.addEventListener('click',()=>{const panel=document.getElementById('onlinePanel');panel.hidden=!panel.hidden;keys.clear();desktopFiring=false;document.exitPointerLock?.()});
document.getElementById('onlineForm')?.addEventListener('submit',event=>{
 event.preventDefault();desktopFiring=false;
 multiplayer.connect(document.getElementById('onlineName').value,document.getElementById('onlineRoom').value);
});
document.getElementById('offlineBtn')?.addEventListener('click',()=>{multiplayer.disconnect();kills3D=0;player.userData.hp=100;updateHud();document.getElementById('onlinePanel').hidden=true});
if(typeof location!=='undefined'){
 const params=new URLSearchParams(location.search);
 if(params.get('multiplayer')==='1'){
  const name=(params.get('name')||'').trim().slice(0,18);
  const room=(params.get('room')||'').toLowerCase().replace(/[^a-z0-9-]/g,'').slice(0,24);
  const nameInput=document.getElementById('onlineName'),roomInput=document.getElementById('onlineRoom');
  if(name&&nameInput)nameInput.value=name;
  if(room&&roomInput)roomInput.value=room;
  if(name&&room)multiplayer.connect(name,room);
  else document.getElementById('onlinePanel').hidden=false;
 }
}

let last=performance.now();
function frame(now){
 const dt=Math.min(.033,(now-last)/1000);last=now;t+=dt;
 updateMultiplayer(dt);
 if(player.userData.avatarMixer)player.userData.avatarMixer.update(dt);
 if(updateClimb(dt)){shotCooldown=Math.max(0,shotCooldown-dt);updateAimFromPointer();updateEnemies3D(dt);updateBullets3D(dt);updateVehicleSmoke(dt);updateBossMissiles(dt);updateBossDeathFx(dt);if(updateBossCutscene(dt)){renderer.render(scene,camera);requestAnimationFrame(frame);return}updateThirdPersonCamera(dt,player);updateAimFromPointer();updateWeaponPose();updateHud();renderer.render(scene,camera);requestAnimationFrame(frame);return}
 if(updateVehicle(dt)){shotCooldown=Math.max(0,shotCooldown-dt);updateEnemies3D(dt);updateBullets3D(dt);updateWeaponFx(dt);updateVehicleSmoke(dt);updateBossMissiles(dt);updateBossDeathFx(dt);if(updateBossCutscene(dt)){renderer.render(scene,camera);requestAnimationFrame(frame);return}updateThirdPersonCamera(dt,activeCar);updateBuildingVisibility();updateHud();renderer.render(scene,camera);requestAnimationFrame(frame);return}
 let inputX=((keys.has('d')?1:0)-(keys.has('a')?1:0))+(mobileMove.active?mobileMove.x:0),
     inputY=((keys.has('w')?1:0)-(keys.has('s')?1:0))+(mobileMove.active?-mobileMove.y:0);
 const len=Math.hypot(inputX,inputY);
 const startPosition=player.position.clone();
 const inputMagnitude=Math.min(1,len);
 const aiming=isADS()||(mobileAim.active&&Math.hypot(mobileAim.x,mobileAim.y)>.12);
 const crouching=keys.has('c')||keys.has('control');
 const requestedRun=inputMagnitude>0&&keys.has('shift')&&!aiming&&!crouching;
 const targetVelocity=new THREE.Vector3();

 // Battle-royale style locomotion: forward movement is fastest, strafing/backpedal
 // are deliberately slower, and acceleration/deceleration are not instantaneous.
 if(inputMagnitude>.08){
  const forward=new THREE.Vector3(-Math.sin(cameraYaw),0,-Math.cos(cameraYaw));
  const right=new THREE.Vector3(Math.cos(cameraYaw),0,-Math.sin(cameraYaw));
  const normalizedX=inputX/len,normalizedY=inputY/len;
  targetVelocity.copy(forward.multiplyScalar(normalizedY).addScaledVector(right,normalizedX));

  let maxSpeed=requestedRun?6.0:(crouching?1.6:(aiming?3.0:4.2));
  if(aiming){
   const backwardPenalty=normalizedY<0?THREE.MathUtils.lerp(1,.78,-normalizedY):1;
   const strafePenalty=THREE.MathUtils.lerp(1,.9,Math.abs(normalizedX));
   maxSpeed*=backwardPenalty*strafePenalty;
  }
  targetVelocity.multiplyScalar(maxSpeed*inputMagnitude);
 }

 const currentSpeed=locomotion.velocity.length();
 const desiredSpeed=targetVelocity.length();
 const reversing=currentSpeed>.2&&desiredSpeed>.2&&locomotion.velocity.dot(targetVelocity)<0;
 const response=inputMagnitude>.08
  ? (reversing?5.2:(desiredSpeed>currentSpeed?6.5:8.5))
  : 10.5;
 locomotion.velocity.lerp(targetVelocity,1-Math.exp(-dt*response));
 if(locomotion.velocity.length()<.025)locomotion.velocity.set(0,0,0);

 const nx=player.position.x+locomotion.velocity.x*dt,nz=player.position.z+locomotion.velocity.z*dt;
 if(!blocked(nx,player.position.z))player.position.x=nx;else locomotion.velocity.x=0;
 if(!blocked(player.position.x,nz))player.position.z=nz;else locomotion.velocity.z=0;

 const actual=player.position.clone().sub(startPosition);actual.y=0;
 locomotion.speed=dt>0?actual.length()/dt:0;
 const moved=locomotion.speed>.025;
 if(moved){
  locomotion.direction.copy(actual).normalize();

  // Without aiming, hips follow travel direction with weighted turning.
  // While aiming, keep the torso/weapon facing the crosshair so legs can strafe independently.
  if(!aiming){
   const targetYaw=Math.atan2(actual.x,actual.z);
   const difference=Math.atan2(Math.sin(targetYaw-player.rotation.y),Math.cos(targetYaw-player.rotation.y));
   const turnRate=requestedRun?9.5:11.5;
   player.rotation.y+=difference*(1-Math.exp(-dt*turnRate));
  }
 }

 // Small body lean gives direction changes visual weight instead of a rigid glide.
 const localVel=locomotion.velocity.clone();
 const invYaw=-player.rotation.y;
 const sideSpeed=localVel.x*Math.cos(invYaw)-localVel.z*Math.sin(invYaw);
 const forwardSpeed=localVel.x*Math.sin(invYaw)+localVel.z*Math.cos(invYaw);
 const leanTarget=THREE.MathUtils.clamp(-sideSpeed*.028,-.12,.12);
 const pitchTarget=THREE.MathUtils.clamp(-forwardSpeed*.014,-.10,.06);
 if(player.userData.avatar&&!player.userData.climbing){
  player.userData.avatar.rotation.z=THREE.MathUtils.lerp(player.userData.avatar.rotation.z,leanTarget,1-Math.exp(-dt*8));
  player.userData.avatar.rotation.x=THREE.MathUtils.lerp(player.userData.avatar.rotation.x,pitchTarget,1-Math.exp(-dt*8));
 }

 const avatarRunning=moved&&requestedRun;
 updateFootstepAudio(moved,avatarRunning);
 setAvatarMotion(moved?(avatarRunning?'run':'walk'):'idle');
 const fallbackStep=Math.sin(locomotion.phase);
 player.userData.legs[0].rotation.x=moved?fallbackStep*.5:player.userData.legs[0].rotation.x*Math.exp(-dt*12);
 player.userData.legs[1].rotation.x=moved?-fallbackStep*.5:player.userData.legs[1].rotation.x*Math.exp(-dt*12);
 updateProceduralAvatar(dt,moved,avatarRunning);
 shotCooldown=Math.max(0,shotCooldown-dt);
 updateThirdPersonCamera(dt,player);
 updateAimFromPointer();
 updateWeaponPose();
 if(mobileAim.firing||desktopFiring)fire();
 updateEnemies3D(dt);updateBullets3D(dt);updateWeaponFx(dt);updateVehicleSmoke(dt);updateBossMissiles(dt);updateBossDeathFx(dt);if(updateBossCutscene(dt)){renderer.render(scene,camera);requestAnimationFrame(frame);return}
 recoilKick=Math.max(0,recoilKick-dt*2.8);
 updateAimFromPointer();
 updateBuildingVisibility();updateHud();renderer.render(scene,camera);requestAnimationFrame(frame);
}
applyWeaponVisual();updateHud();updateThirdPersonCamera(1,player);updateAimFromPointer();updateWeaponPose();
requestAnimationFrame(frame);
