window.addEventListener('error',e=>{const s=document.getElementById('state');if(s)s.textContent='ERRO: '+(e.message||'falha JS')});
window.addEventListener('unhandledrejection',e=>{const s=document.getElementById('state');if(s)s.textContent='ERRO: '+(e.reason?.message||e.reason||'promise')});

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
const camera=new THREE.PerspectiveCamera(58,innerWidth/innerHeight,.1,250);


function buildForestEnvironment(scene,options={}){
 const {
  mapSize=300,
  treeCount=180,
  rockCount=60,
  bushCount=90,
  safeZoneRadius=25,
  seed=42
 }=options;

 let currentSeed=seed;
 function random(){
  const x=Math.sin(currentSeed++)*10000;
  return x-Math.floor(x);
 }

 const skyColor=new THREE.Color(0xa8d5e5);
 const fogColor=new THREE.Color(0xc2e0d8);
 scene.background=skyColor;
 scene.fog=new THREE.FogExp2(fogColor,.0085);

 const hemiLight=new THREE.HemisphereLight(0xdff5ff,0x3b5233,.85);
 hemiLight.position.set(0,50,0);
 scene.add(hemiLight);

 const sunLight=new THREE.DirectionalLight(0xfff4d6,1.4);
 sunLight.position.set(60,100,40);
 sunLight.castShadow=true;
 sunLight.shadow.mapSize.width=2048;
 sunLight.shadow.mapSize.height=2048;
 sunLight.shadow.camera.near=10;
 sunLight.shadow.camera.far=250;
 const d=100;
 sunLight.shadow.camera.left=-d;
 sunLight.shadow.camera.right=d;
 sunLight.shadow.camera.top=d;
 sunLight.shadow.camera.bottom=-d;
 sunLight.shadow.bias=-.0005;
 scene.add(sunLight);

 const groundGeo=new THREE.PlaneGeometry(mapSize,mapSize,64,64);
 groundGeo.rotateX(-Math.PI/2);
 const posAttr=groundGeo.attributes.position;
 for(let i=0;i<posAttr.count;i++){
  const x=posAttr.getX(i);
  const z=posAttr.getZ(i);
  const distFromCenter=Math.hypot(x,z);
  if(distFromCenter>safeZoneRadius){
   const factor=Math.min((distFromCenter-safeZoneRadius)/40,1);
   const height=(Math.sin(x*.05)*Math.cos(z*.05)*2.5+Math.sin(x*.12+z*.1)*.8)*factor;
   posAttr.setY(i,height);
  }
 }
 groundGeo.computeVertexNormals();

 const groundMat=new THREE.MeshStandardMaterial({
  color:0x5c8a47,
  roughness:.9,
  metalness:.05,
  flatShading:true
 });
 const ground=new THREE.Mesh(groundGeo,groundMat);
 ground.receiveShadow=true;
 scene.add(ground);

 function getTerrainHeight(x,z){
  const distFromCenter=Math.hypot(x,z);
  if(distFromCenter<=safeZoneRadius)return 0;
  const factor=Math.min((distFromCenter-safeZoneRadius)/40,1);
  return (Math.sin(x*.05)*Math.cos(z*.05)*2.5+Math.sin(x*.12+z*.1)*.8)*factor;
 }

 const trunkMat=new THREE.MeshStandardMaterial({color:0x6e4f3a,roughness:.9,flatShading:true});
 const leafMaterials=[
  new THREE.MeshStandardMaterial({color:0x3d6e35,roughness:.8,flatShading:true}),
  new THREE.MeshStandardMaterial({color:0x4f8542,roughness:.8,flatShading:true}),
  new THREE.MeshStandardMaterial({color:0x2d5429,roughness:.8,flatShading:true})
 ];
 const rockMat=new THREE.MeshStandardMaterial({color:0x858a8c,roughness:.85,flatShading:true});

 const forestGroup=new THREE.Group();
 const colliders=[];

 function createPineTree(scale){
  const tree=new THREE.Group();
  const mat=leafMaterials[Math.floor(random()*leafMaterials.length)];

  const trunkGeo=new THREE.CylinderGeometry(.35*scale,.55*scale,2.5*scale,6);
  const trunk=new THREE.Mesh(trunkGeo,trunkMat);
  trunk.position.y=1.25*scale;
  trunk.castShadow=true;
  trunk.receiveShadow=true;
  tree.add(trunk);

  for(let i=0;i<3;i++){
   const radius=(2.4-i*.55)*scale;
   const height=2.8*scale;
   const coneGeo=new THREE.ConeGeometry(radius,height,7);
   const cone=new THREE.Mesh(coneGeo,mat);
   cone.position.y=(3+i*1.5)*scale;
   cone.rotation.y=random()*Math.PI;
   cone.castShadow=true;
   cone.receiveShadow=true;
   tree.add(cone);
  }
  return tree;
 }

 function createOakTree(scale){
  const tree=new THREE.Group();
  const mat=leafMaterials[Math.floor(random()*leafMaterials.length)];

  const trunkGeo=new THREE.CylinderGeometry(.4*scale,.65*scale,3.2*scale,6);
  const trunk=new THREE.Mesh(trunkGeo,trunkMat);
  trunk.position.y=1.6*scale;
  trunk.castShadow=true;
  trunk.receiveShadow=true;
  tree.add(trunk);

  const crownPositions=[
   {x:0,y:4.2,z:0,r:2.2},
   {x:1.1,y:3.6,z:.6,r:1.5},
   {x:-1,y:3.8,z:-.7,r:1.6}
  ];
  crownPositions.forEach(p=>{
   const crownGeo=new THREE.IcosahedronGeometry(p.r*scale,1);
   const crown=new THREE.Mesh(crownGeo,mat);
   crown.position.set(p.x*scale,p.y*scale,p.z*scale);
   crown.rotation.set(random(),random(),random());
   crown.castShadow=true;
   crown.receiveShadow=true;
   tree.add(crown);
  });
  return tree;
 }

 function createRock(scale){
  const rockGeo=new THREE.DodecahedronGeometry(scale,0);
  const pos=rockGeo.attributes.position;
  for(let i=0;i<pos.count;i++){
   pos.setXYZ(
    i,
    pos.getX(i)*(.8+random()*.4),
    pos.getY(i)*(.6+random()*.4),
    pos.getZ(i)*(.8+random()*.4)
   );
  }
  rockGeo.computeVertexNormals();
  const rock=new THREE.Mesh(rockGeo,rockMat);
  rock.castShadow=true;
  rock.receiveShadow=true;
  return rock;
 }

 function createBush(scale){
  const bush=new THREE.Group();
  const mat=leafMaterials[Math.floor(random()*leafMaterials.length)];
  for(let i=0;i<3;i++){
   const geo=new THREE.IcosahedronGeometry((.7+random()*.4)*scale,0);
   const part=new THREE.Mesh(geo,mat);
   part.position.set((random()-.5)*scale,.4*scale,(random()-.5)*scale);
   part.castShadow=true;
   part.receiveShadow=true;
   bush.add(part);
  }
  return bush;
 }

 function getValidPosition(minRadius){
  let x,z,dist,attempts=0;
  do{
   x=(random()-.5)*(mapSize-15);
   z=(random()-.5)*(mapSize-15);
   dist=Math.hypot(x,z);
   attempts++;
  }while(dist<minRadius&&attempts<30);
  return {x,z,y:getTerrainHeight(x,z)};
 }

 for(let i=0;i<treeCount;i++){
  const pos=getValidPosition(safeZoneRadius);
  const scale=.8+random()*.9;
  const tree=random()>.45?createPineTree(scale):createOakTree(scale);
  tree.position.set(pos.x,pos.y,pos.z);
  tree.rotation.y=random()*Math.PI*2;
  forestGroup.add(tree);
  colliders.push({type:'tree',x:pos.x,z:pos.z,radius:.6*scale});
 }

 for(let i=0;i<rockCount;i++){
  const pos=getValidPosition(safeZoneRadius*.7);
  const scale=.6+random()*1.4;
  const rock=createRock(scale);
  rock.position.set(pos.x,pos.y+scale*.3,pos.z);
  rock.rotation.set(random()*Math.PI,random()*Math.PI,0);
  forestGroup.add(rock);
  colliders.push({type:'rock',x:pos.x,z:pos.z,radius:scale*.9});
 }

 for(let i=0;i<bushCount;i++){
  const pos=getValidPosition(safeZoneRadius*.5);
  const scale=.7+random()*.8;
  const bush=createBush(scale);
  bush.position.set(pos.x,pos.y,pos.z);
  forestGroup.add(bush);
 }

 scene.add(forestGroup);
 return {forestGroup,colliders,getTerrainHeight,ground};
}

const forestEnvironment=buildForestEnvironment(scene,{
 mapSize:300,
 treeCount:180,
 rockCount:60,
 bushCount:90,
 safeZoneRadius:25,
 seed:42
});

function box(x,y,z,sx,sy,sz,color=0x7f8a86){
 const m=new THREE.Mesh(new THREE.BoxGeometry(sx,sy,sz),new THREE.MeshStandardMaterial({color,roughness:.9}));
 m.position.set(x,y+sy/2,z); m.castShadow=true; m.receiveShadow=true; scene.add(m); return m;
}
const legacyBlocks=[
 box(0,0,14,12,5,8,0x59646b),
 box(-16,0,-4,9,7,10,0x6b5d55),
 box(17,0,-8,11,4,9,0x565f5b),
 box(0,0,-22,20,3,4,0x4d5558)
];
for(let i=-24;i<=24;i+=8) box(i,0,4,2,.35,8,0x484d50);

const houseParkour=new HouseParkourBuilder(scene,forestEnvironment.getTerrainHeight);
houseParkour.convertExistingBlocksToHouses(legacyBlocks);

const player=new THREE.Group(); scene.add(player);
player.position.set(0,0,0);

function makeCapsuleGeometry(radius,length,segments=8){
 const g=new THREE.Group();
 const matProxy=null;
 const cylinder=new THREE.CylinderGeometry(radius,radius,length,segments);
 const top=new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75)));
 const bottom=new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75)));
 return {cylinder,top,bottom,length,radius};
}

function makeCapsuleMesh(radius,length,material,segments=8){
 const group=new THREE.Group();
 const body=new THREE.Mesh(new THREE.CylinderGeometry(radius,radius,length,segments),material);
 body.castShadow=true;
 const top=new THREE.Mesh(new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75))),material);
 top.position.y=length/2;
 top.castShadow=true;
 const bottom=new THREE.Mesh(new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75))),material);
 bottom.position.y=-length/2;
 bottom.castShadow=true;
 group.add(body,top,bottom);
 return group;
}

class SimpleAvatar {
 constructor(options={}){
  this.group=new THREE.Group();
  const bodyColor=options.bodyColor||0x3b82f6;
  const skinColor=options.skinColor||0xf1f5f9;
  const visorColor=options.visorColor||0x0f172a;

  const bodyMat=new THREE.MeshStandardMaterial({color:bodyColor,roughness:.4});
  const skinMat=new THREE.MeshStandardMaterial({color:skinColor,roughness:.3});
  const visorMat=new THREE.MeshStandardMaterial({color:visorColor,roughness:.1,metalness:.8});

  this.leftLeg=new THREE.Group();
  this.leftLeg.position.set(-.18,.65,0);
  const leftLegMesh=makeCapsuleMesh(.11,.45,skinMat,8);
  leftLegMesh.position.y=-.32; this.leftLeg.add(leftLegMesh);

  this.rightLeg=new THREE.Group();
  this.rightLeg.position.set(.18,.65,0);
  const rightLegMesh=makeCapsuleMesh(.11,.45,skinMat,8);
  rightLegMesh.position.y=-.32; this.rightLeg.add(rightLegMesh);

  this.torso=makeCapsuleMesh(.32,.5,bodyMat,12);
  this.torso.position.y=1.05;

  this.head=new THREE.Group();
  this.head.position.y=1.75;
  const headMesh=new THREE.Mesh(new THREE.SphereGeometry(.28,16,16),skinMat);
  headMesh.castShadow=true; this.head.add(headMesh);

  const visorMesh=new THREE.Mesh(new THREE.BoxGeometry(.36,.14,.15),visorMat);
  visorMesh.position.set(0,.02,.22); this.head.add(visorMesh);

  this.leftArm=new THREE.Group();
  this.leftArm.position.set(-.44,1.32,0);
  const leftArmMesh=makeCapsuleMesh(.09,.45,skinMat,8);
  leftArmMesh.position.y=-.25; this.leftArm.add(leftArmMesh);

  this.rightArm=new THREE.Group();
  this.rightArm.position.set(.44,1.32,0);
  const rightArmMesh=makeCapsuleMesh(.09,.45,skinMat,8);
  rightArmMesh.position.y=-.25; this.rightArm.add(rightArmMesh);

  this.group.add(this.leftLeg,this.rightLeg,this.torso,this.head,this.leftArm,this.rightArm);
  this.walkTime=0;
 }
 animate(dt,isMoving,isSprinting=false){
  const safeLerp=Math.min(1,10*dt);
  if(isMoving){
   const speed=isSprinting?14:9;
   const swingAngle=isSprinting?.85:.55;
   this.walkTime+=dt*speed;
   const s=Math.sin(this.walkTime)*swingAngle;
   this.leftLeg.rotation.x=s;
   this.rightLeg.rotation.x=-s;
   this.leftArm.rotation.x=-s;
   this.rightArm.rotation.x=s;
   this.torso.position.y=1.05+Math.abs(Math.cos(this.walkTime))*.04;
  }else{
   this.leftLeg.rotation.x=THREE.MathUtils.lerp(this.leftLeg.rotation.x,0,safeLerp);
   this.rightLeg.rotation.x=THREE.MathUtils.lerp(this.rightLeg.rotation.x,0,safeLerp);
   this.leftArm.rotation.x=THREE.MathUtils.lerp(this.leftArm.rotation.x,0,safeLerp);
   this.rightArm.rotation.x=THREE.MathUtils.lerp(this.rightArm.rotation.x,0,safeLerp);
   this.torso.position.y=THREE.MathUtils.lerp(this.torso.position.y,1.05,safeLerp);
  }
 }
}

class ForestAudioSystem {
 constructor(){
  this.ctx=null;
  this.masterGain=null;
  this.windGain=null;
  this.enabled=true;
  this.isAmbiencePlaying=false;
  this.birdTimer=null;
  this.lastFootstepAt=0;
 }
 init(){
  if(!this.ctx){
   const AudioContext=window.AudioContext||window.webkitAudioContext;
   this.ctx=new AudioContext();
   this.masterGain=this.ctx.createGain();
   this.masterGain.gain.value=this.enabled?.8:0;
   this.masterGain.connect(this.ctx.destination);
  }
  if(this.ctx.state==='suspended')this.ctx.resume();
  if(!this.isAmbiencePlaying)this.startForestAmbience();
 }
 setEnabled(state){
  this.enabled=state;
  if(this.masterGain&&this.ctx){
   this.masterGain.gain.setTargetAtTime(state?.8:0,this.ctx.currentTime,.05);
  }
 }
 startForestAmbience(){
  if(!this.ctx||this.isAmbiencePlaying)return;
  this.isAmbiencePlaying=true;

  const bufferSize=this.ctx.sampleRate*4;
  const buffer=this.ctx.createBuffer(1,bufferSize,this.ctx.sampleRate);
  const data=buffer.getChannelData(0);
  let lastOut=0;
  for(let i=0;i<bufferSize;i++){
   const white=Math.random()*2-1;
   data[i]=(lastOut+.02*white)/1.02;
   lastOut=data[i];
   data[i]*=2.5;
  }

  const windSource=this.ctx.createBufferSource();
  windSource.buffer=buffer;
  windSource.loop=true;

  const windFilter=this.ctx.createBiquadFilter();
  windFilter.type='bandpass';
  windFilter.frequency.value=320;
  windFilter.Q.value=1.2;

  const lfo=this.ctx.createOscillator();
  lfo.frequency.value=.12;
  const lfoGain=this.ctx.createGain();
  lfoGain.gain.value=140;
  lfo.connect(lfoGain);
  lfoGain.connect(windFilter.frequency);

  this.windGain=this.ctx.createGain();
  this.windGain.gain.value=.12;

  windSource.connect(windFilter);
  windFilter.connect(this.windGain);
  this.windGain.connect(this.masterGain);

  windSource.start();
  lfo.start();
  this._scheduleBird();
 }
 _scheduleBird(){
  if(!this.ctx||!this.isAmbiencePlaying)return;
  const delay=2200+Math.random()*6500;
  clearTimeout(this.birdTimer);
  this.birdTimer=setTimeout(()=>{
   this.playBird();
   this._scheduleBird();
  },delay);
 }
 playBird(){
  if(!this.ctx||!this.enabled)return;
  const now=this.ctx.currentTime;
  const osc=this.ctx.createOscillator();
  const gain=this.ctx.createGain();
  const pan=this.ctx.createStereoPanner?this.ctx.createStereoPanner():null;

  osc.type='sine';
  const base=1500+Math.random()*900;
  osc.frequency.setValueAtTime(base,now);
  osc.frequency.linearRampToValueAtTime(base*1.25,now+.08);
  osc.frequency.linearRampToValueAtTime(base*.9,now+.18);
  osc.frequency.linearRampToValueAtTime(base*1.18,now+.28);

  gain.gain.setValueAtTime(.0001,now);
  gain.gain.exponentialRampToValueAtTime(.045,now+.03);
  gain.gain.exponentialRampToValueAtTime(.0001,now+.35);

  osc.connect(gain);
  if(pan){
   pan.pan.value=(Math.random()*2-1)*.8;
   gain.connect(pan);
   pan.connect(this.masterGain);
  }else{
   gain.connect(this.masterGain);
  }

  osc.start(now);
  osc.stop(now+.38);
 }
 playShoot(){
  if(!this.ctx||!this.enabled)return;
  const now=this.ctx.currentTime;
  const len=Math.floor(this.ctx.sampleRate*.09);
  const buffer=this.ctx.createBuffer(1,len,this.ctx.sampleRate);
  const data=buffer.getChannelData(0);
  for(let i=0;i<len;i++)data[i]=(Math.random()*2-1)*(1-i/len);
  const src=this.ctx.createBufferSource();
  src.buffer=buffer;
  const filter=this.ctx.createBiquadFilter();
  filter.type='bandpass';
  filter.frequency.value=1100;
  const gain=this.ctx.createGain();
  gain.gain.setValueAtTime(.28,now);
  gain.gain.exponentialRampToValueAtTime(.001,now+.09);
  src.connect(filter); filter.connect(gain); gain.connect(this.masterGain);
  src.start(now);
 }
 playHit(){
  if(!this.ctx||!this.enabled)return;
  const now=this.ctx.currentTime;
  const osc=this.ctx.createOscillator();
  const gain=this.ctx.createGain();
  osc.type='sine';
  osc.frequency.setValueAtTime(820,now);
  osc.frequency.exponentialRampToValueAtTime(380,now+.09);
  gain.gain.setValueAtTime(.18,now);
  gain.gain.exponentialRampToValueAtTime(.001,now+.1);
  osc.connect(gain); gain.connect(this.masterGain);
  osc.start(now); osc.stop(now+.1);
 }
 playFootstep(){
  if(!this.ctx||!this.enabled)return;
  const nowMs=performance.now();
  if(nowMs-this.lastFootstepAt<190)return;
  this.lastFootstepAt=nowMs;
  const now=this.ctx.currentTime;
  const osc=this.ctx.createOscillator();
  const gain=this.ctx.createGain();
  osc.type='triangle';
  osc.frequency.setValueAtTime(95,now);
  osc.frequency.exponentialRampToValueAtTime(38,now+.055);
  gain.gain.setValueAtTime(.08,now);
  gain.gain.exponentialRampToValueAtTime(.001,now+.055);
  osc.connect(gain); gain.connect(this.masterGain);
  osc.start(now); osc.stop(now+.06);
 }
}

const forestAudio=new ForestAudioSystem();
canvas.addEventListener('pointerdown',()=>forestAudio.init(),{once:true});

class BowAnimationSystem {
 constructor(scene,avatar){
  this.scene=scene;
  this.avatar=avatar;
  this.state='holstered';
  this.stateTimer=0;
  this.drawProgress=0;
  this.maxDrawTime=.65;
  this.fireDuration=.18;
  this.reloadDuration=.55;
  this.activeArrows=[];
  this.onArrowShot=null;
  this.buildBowAndArrow();
  this.bindControls();
  this.holster();
 }
 buildBowAndArrow(){
  this.bowGroup=new THREE.Group();
  const woodMat=new THREE.MeshStandardMaterial({color:0x5c3a21,roughness:.7,flatShading:true});
  const gripMat=new THREE.MeshStandardMaterial({color:0x1f2937,roughness:.9});
  const goldMat=new THREE.MeshStandardMaterial({color:0xd97706,metalness:.8,roughness:.3});
  const stringMat=new THREE.LineBasicMaterial({color:0x00ffcc});

  const grip=new THREE.Mesh(new THREE.CylinderGeometry(.032,.032,.32,8),gripMat);
  this.bowGroup.add(grip);

  this.upperLimbPivot=new THREE.Group();
  this.upperLimbPivot.position.set(0,.16,0);
  const upperLimb=new THREE.Mesh(new THREE.BoxGeometry(.025,.58,.045),woodMat);
  upperLimb.position.set(0,.28,.06);
  upperLimb.rotation.x=-.25;
  upperLimb.castShadow=true;
  this.upperLimbPivot.add(upperLimb);
  this.upperTip=new THREE.Object3D();
  this.upperTip.position.set(0,.56,.16);
  this.upperLimbPivot.add(this.upperTip);
  this.bowGroup.add(this.upperLimbPivot);

  this.lowerLimbPivot=new THREE.Group();
  this.lowerLimbPivot.position.set(0,-.16,0);
  const lowerLimb=new THREE.Mesh(new THREE.BoxGeometry(.025,.58,.045),woodMat);
  lowerLimb.position.set(0,-.28,.06);
  lowerLimb.rotation.x=.25;
  lowerLimb.castShadow=true;
  this.lowerLimbPivot.add(lowerLimb);
  this.lowerTip=new THREE.Object3D();
  this.lowerTip.position.set(0,-.56,.16);
  this.lowerLimbPivot.add(this.lowerTip);
  this.bowGroup.add(this.lowerLimbPivot);

  this.stringPoints=[
   new THREE.Vector3(0,.72,.16),
   new THREE.Vector3(0,0,.16),
   new THREE.Vector3(0,-.72,.16)
  ];
  const stringGeo=new THREE.BufferGeometry().setFromPoints(this.stringPoints);
  this.bowString=new THREE.Line(stringGeo,stringMat);
  this.bowGroup.add(this.bowString);

  this.handArrow=this.createArrowMesh();
  this.bowGroup.add(this.handArrow);

  this.muzzlePoint=new THREE.Object3D();
  this.muzzlePoint.position.set(0,0,-.4);
  this.bowGroup.add(this.muzzlePoint);
 }
 createArrowMesh(){
  const arrow=new THREE.Group();
  const shaft=new THREE.Mesh(
   new THREE.CylinderGeometry(.008,.008,.85,6),
   new THREE.MeshStandardMaterial({color:0x78350f})
  );
  shaft.rotation.x=Math.PI/2;
  arrow.add(shaft);

  const head=new THREE.Mesh(
   new THREE.ConeGeometry(.022,.08,4),
   new THREE.MeshStandardMaterial({color:0x00ffcc,emissive:0x005544})
  );
  head.rotation.x=-Math.PI/2;
  head.position.z=-.45;
  arrow.add(head);
  return arrow;
 }
 bindControls(){
  addEventListener('keydown',e=>{
   if(e.code==='Digit1'||e.code==='Numpad1'){
    if(this.state==='holstered')this.equip();
   }
   if(e.code==='KeyH'){
    if(this.state!=='holstered')this.holster();
   }
  });
  addEventListener('mousedown',e=>{
   if(e.button!==0)return;
   if(!gameStarted)return;
   if(this.state==='ready'){
    this.state='drawing';
    this.drawProgress=0;
   }
  });
  addEventListener('mouseup',e=>{
   if(e.button!==0)return;
   if(this.state==='drawing'){
    if(this.drawProgress>=.2)this.releaseArrow();
    else{
     this.state='ready';
     this.drawProgress=0;
    }
   }
  });
 }
 equip(){
  this.state='ready';
  this.drawProgress=0;
  this.avatar.group.add(this.bowGroup);
  this.bowGroup.position.set(-.38,1.15,-.42);
  this.bowGroup.rotation.set(0,0,.22);
  this.handArrow.visible=true;
  this.resetArrowNockedPose();
 }
 holster(){
  this.state='holstered';
  this.drawProgress=0;
  this.avatar.group.add(this.bowGroup);
  this.bowGroup.position.set(.24,1.22,-.58);
  this.bowGroup.rotation.set(.12,.08,.92);
  this.handArrow.visible=false;
  this.updateBowDeformation(0);
 }
 releaseArrow(){
  const power=Math.max(.35,this.drawProgress);
  this.state='firing';
  this.stateTimer=0;
  this.handArrow.visible=false;

  const startPos=new THREE.Vector3();
  this.muzzlePoint.getWorldPosition(startPos);

  const ray=new THREE.Raycaster();
  const hit=getAimRaycastHit(ray,camera,scene,player);
  const targetPoint=hit?.point || camera.position.clone().add(camera.getWorldDirection(new THREE.Vector3()).multiplyScalar(100));
  const direction=new THREE.Vector3().subVectors(targetPoint,startPos).normalize();

  const arrowProj=this.createArrowMesh();
  arrowProj.position.copy(startPos);
  arrowProj.lookAt(startPos.clone().add(direction));

  const speed=35+power*45;
  arrowProj.userData={velocity:direction.multiplyScalar(speed),life:2};
  this.scene.add(arrowProj);
  this.activeArrows.push(arrowProj);

  if(typeof this.onArrowShot==='function')this.onArrowShot(power,hit);
  this.drawProgress=0;
  this.updateBowDeformation(0);
 }
 resetArrowNockedPose(){
  this.handArrow.position.set(.03,0,-.18);
  this.handArrow.rotation.set(0,0,0);
 }
 updateBowDeformation(t){
  this.upperLimbPivot.rotation.x=t*.22;
  this.lowerLimbPivot.rotation.x=-t*.22;
  const tipY=.72-t*.04;
  const tipZ=.16+t*.11;
  const pullZ=.16+t*.42;
  this.stringPoints[0].set(0,tipY,tipZ);
  this.stringPoints[1].set(0,0,pullZ);
  this.stringPoints[2].set(0,-tipY,tipZ);
  this.bowString.geometry.setFromPoints(this.stringPoints);
 }
 update(delta,isMoving){
  this.updateFlyingArrows(delta);

  if(this.state==='holstered'){
   if(!isMoving){
    this.avatar.leftArm.rotation.z=THREE.MathUtils.lerp(this.avatar.leftArm.rotation.z,.15,.15);
    this.avatar.rightArm.rotation.z=THREE.MathUtils.lerp(this.avatar.rightArm.rotation.z,-.15,.15);
   }
   return;
  }

  const leftArm=this.avatar.leftArm;
  const rightArm=this.avatar.rightArm;

  if(this.state==='ready'){
   leftArm.rotation.x=THREE.MathUtils.lerp(leftArm.rotation.x,-1.35,.2);
   leftArm.rotation.z=THREE.MathUtils.lerp(leftArm.rotation.z,-.1,.2);
   rightArm.rotation.x=THREE.MathUtils.lerp(rightArm.rotation.x,-1.15,.2);
   rightArm.rotation.z=THREE.MathUtils.lerp(rightArm.rotation.z,.35,.2);
   rightArm.position.z=THREE.MathUtils.lerp(rightArm.position.z,0,.2);
   this.resetArrowNockedPose();
   this.updateBowDeformation(0);
  }else if(this.state==='drawing'){
   this.drawProgress=Math.min(1,this.drawProgress+delta/this.maxDrawTime);
   const easedPull=1-Math.pow(1-this.drawProgress,2);
   leftArm.rotation.x=THREE.MathUtils.lerp(leftArm.rotation.x,-1.42,.25);
   leftArm.rotation.z=THREE.MathUtils.lerp(leftArm.rotation.z,-.12,.25);
   rightArm.rotation.x=THREE.MathUtils.lerp(rightArm.rotation.x,-1.35+easedPull*.45,.25);
   rightArm.rotation.z=THREE.MathUtils.lerp(rightArm.rotation.z,.35-easedPull*.15,.25);
   rightArm.position.z=THREE.MathUtils.lerp(rightArm.position.z,easedPull*.18,.25);
   this.handArrow.position.set(.03,0,-.18+easedPull*.42);
   this.updateBowDeformation(easedPull);
  }else if(this.state==='firing'){
   this.stateTimer+=delta;
   const t=Math.min(1,this.stateTimer/this.fireDuration);
   const kick=Math.sin(t*Math.PI)*.22;
   leftArm.rotation.x=-1.42-kick;
   rightArm.rotation.x=-.85-kick;
   rightArm.position.z=THREE.MathUtils.lerp(rightArm.position.z,.1,.3);
   if(this.stateTimer>=this.fireDuration){
    this.state='reloading';
    this.stateTimer=0;
   }
  }else if(this.state==='reloading'){
   this.stateTimer+=delta;
   const t=Math.min(1,this.stateTimer/this.reloadDuration);
   if(t<.5){
    const reachPhase=t*2;
    rightArm.rotation.x=THREE.MathUtils.lerp(rightArm.rotation.x,-2.55,reachPhase);
    rightArm.rotation.z=THREE.MathUtils.lerp(rightArm.rotation.z,-.25,reachPhase);
    rightArm.position.z=THREE.MathUtils.lerp(rightArm.position.z,.12,reachPhase);
   }else{
    const nockPhase=(t-.5)*2;
    this.handArrow.visible=true;
    rightArm.rotation.x=THREE.MathUtils.lerp(-2.55,-1.15,nockPhase);
    rightArm.rotation.z=THREE.MathUtils.lerp(-.25,.35,nockPhase);
    rightArm.position.z=THREE.MathUtils.lerp(.12,0,nockPhase);
    this.handArrow.position.set(
     .03+(1-nockPhase)*.25,
     (1-nockPhase)*.45,
     -.18+(1-nockPhase)*.35
    );
    this.handArrow.rotation.x=(1-nockPhase)*.6;
   }
   leftArm.rotation.x=THREE.MathUtils.lerp(leftArm.rotation.x,-1.1,.15);
   if(this.stateTimer>=this.reloadDuration){
    this.state='ready';
    this.resetArrowNockedPose();
   }
  }
 }
 updateFlyingArrows(delta){
  for(let i=this.activeArrows.length-1;i>=0;i--){
   const arrow=this.activeArrows[i];
   arrow.position.addScaledVector(arrow.userData.velocity,delta);
   arrow.userData.velocity.y-=9.8*delta*.35;
   arrow.lookAt(arrow.position.clone().add(arrow.userData.velocity));
   arrow.userData.life-=delta;
   if(arrow.userData.life<=0){
    this.scene.remove(arrow);
    this.activeArrows.splice(i,1);
   }
  }
 }
}

class HouseParkourBuilder {
 constructor(scene,getGroundHeight=()=>0){
  this.scene=scene;
  this.getGroundHeight=getGroundHeight;
  this.structuresGroup=new THREE.Group();
  this.scene.add(this.structuresGroup);
  this.solidBoxes=[];
  this.initMaterials();
 }
 initMaterials(){
  this.materials={
   stoneWall:new THREE.MeshStandardMaterial({color:0x7c858e,roughness:.85,flatShading:true}),
   woodWall:new THREE.MeshStandardMaterial({color:0x8b5a2b,roughness:.8,flatShading:true}),
   darkWood:new THREE.MeshStandardMaterial({color:0x4a3219,roughness:.9,flatShading:true}),
   roof:new THREE.MeshStandardMaterial({color:0x8f3a2b,roughness:.75,flatShading:true}),
   crate:new THREE.MeshStandardMaterial({color:0xb07d48,roughness:.8,flatShading:true}),
   windowGlow:new THREE.MeshStandardMaterial({color:0xffe49e,emissive:0xffb732,emissiveIntensity:.45})
  };
 }
 registerSolidBox(mesh,width,height,depth){
  mesh.updateMatrixWorld(true);
  const pos=new THREE.Vector3();
  mesh.getWorldPosition(pos);
  this.solidBoxes.push({
   minX:pos.x-width/2,maxX:pos.x+width/2,
   minY:pos.y-height/2,maxY:pos.y+height/2,
   minZ:pos.z-depth/2,maxZ:pos.z+depth/2
  });
 }
 buildHouseWithParkour(config={}){
  const {x=0,z=0,width=8,height=5.2,depth=7,rotationY=0}=config;
  const baseY=this.getGroundHeight(x,z);
  const houseContainer=new THREE.Group();
  houseContainer.position.set(x,baseY,z);
  houseContainer.rotation.y=rotationY;
  this.structuresGroup.add(houseContainer);

  const wallMesh=new THREE.Mesh(new THREE.BoxGeometry(width,height,depth),this.materials.stoneWall);
  wallMesh.position.y=height/2;
  wallMesh.castShadow=true; wallMesh.receiveShadow=true;
  houseContainer.add(wallMesh);

  const pillarGeo=new THREE.BoxGeometry(.45,height+.1,.45);
  [[-width/2,-depth/2],[width/2,-depth/2],[-width/2,depth/2],[width/2,depth/2]].forEach(([cx,cz])=>{
   const pillar=new THREE.Mesh(pillarGeo,this.materials.darkWood);
   pillar.position.set(cx,height/2,cz); pillar.castShadow=true; houseContainer.add(pillar);
  });

  const door=new THREE.Mesh(new THREE.BoxGeometry(1.4,2.4,.18),this.materials.darkWood);
  door.position.set(0,1.2,depth/2+.05); houseContainer.add(door);

  const winGeo=new THREE.BoxGeometry(1.1,1.1,.15);
  [-width*.28,width*.28].forEach(wx=>{
   const win=new THREE.Mesh(winGeo,this.materials.windowGlow);
   win.position.set(wx,height*.58,depth/2+.04); houseContainer.add(win);
  });

  const roofHeight=2.4;
  const roofGeo=new THREE.ConeGeometry(Math.max(width,depth)*.78,roofHeight,4);
  roofGeo.rotateY(Math.PI/4);
  const roofMesh=new THREE.Mesh(roofGeo,this.materials.roof);
  roofMesh.scale.set(width/Math.max(width,depth),1,depth/Math.max(width,depth));
  roofMesh.position.y=height+roofHeight/2-.1;
  roofMesh.castShadow=true; roofMesh.receiveShadow=true; houseContainer.add(roofMesh);

  const supports=[
   {px:width/2+1.1,py:.6,pz:depth*.25,w:1.5,h:1.2,d:1.5,mat:this.materials.crate},
   {px:width/2+1,py:1.25,pz:-depth*.15,w:1.5,h:2.5,d:1.5,mat:this.materials.crate},
   {px:width/2+.85,py:3.65,pz:-depth*.35,w:1.7,h:.35,d:2,mat:this.materials.woodWall},
   {px:width*.25,py:height-.15,pz:-depth/2-.75,w:2.2,h:.35,d:1.5,mat:this.materials.darkWood}
  ];

  houseContainer.updateMatrixWorld(true);
  const isRotated90=Math.abs(Math.sin(rotationY))>.7;
  const worldW=isRotated90?depth:width;
  const worldD=isRotated90?width:depth;
  this.registerSolidBox(wallMesh,worldW,height,worldD);

  const roofTopCollider=new THREE.Object3D();
  roofTopCollider.position.set(0,height+.45,0);
  houseContainer.add(roofTopCollider);
  this.registerSolidBox(roofTopCollider,worldW*.85,.9,worldD*.85);

  supports.forEach(s=>{
   const sup=new THREE.Mesh(new THREE.BoxGeometry(s.w,s.h,s.d),s.mat);
   sup.position.set(s.px,s.py,s.pz);
   sup.castShadow=true; sup.receiveShadow=true; houseContainer.add(sup);
   if(s.py>2.5){
    const bracket=new THREE.Mesh(new THREE.BoxGeometry(s.w*.7,.2,.2),this.materials.darkWood);
    bracket.position.set(s.px-.15,s.py-.35,s.pz);
    bracket.rotation.z=.55; houseContainer.add(bracket);
   }
   this.registerSolidBox(sup,isRotated90?s.d:s.w,s.h,isRotated90?s.w:s.d);
  });

  return houseContainer;
 }
 convertExistingBlocksToHouses(blockMeshes=[]){
  blockMeshes.forEach(oldMesh=>{
   if(!oldMesh||!oldMesh.geometry)return;
   oldMesh.geometry.computeBoundingBox();
   const box=oldMesh.geometry.boundingBox;
   const size=new THREE.Vector3(); box.getSize(size);
   const width=Math.max(5,size.x*oldMesh.scale.x);
   const height=Math.max(4.5,size.y*oldMesh.scale.y);
   const depth=Math.max(5,size.z*oldMesh.scale.z);
   this.buildHouseWithParkour({
    x:oldMesh.position.x,z:oldMesh.position.z,width,height,depth,rotationY:oldMesh.rotation.y
   });
   if(oldMesh.parent)oldMesh.parent.remove(oldMesh);
  });
 }
 resolvePlayerCollision(controller,playerRadius=.45,playerHeight=1.6){
  let highestPlatformY=-Infinity;
  const p=controller.mesh.position;
  for(const b of this.solidBoxes){
   const withinX=p.x+playerRadius>b.minX&&p.x-playerRadius<b.maxX;
   const withinZ=p.z+playerRadius>b.minZ&&p.z-playerRadius<b.maxZ;
   if(!withinX||!withinZ)continue;

   const footY=p.y;
   if(footY>=b.maxY-.35&&controller.velocity.y<=0){
    if(b.maxY>highestPlatformY)highestPlatformY=b.maxY;
    continue;
   }

   const headY=p.y+playerHeight;
   if(headY>b.minY+.1&&footY<b.maxY-.35){
    const overlapLeft=(p.x+playerRadius)-b.minX;
    const overlapRight=b.maxX-(p.x-playerRadius);
    const overlapFront=(p.z+playerRadius)-b.minZ;
    const overlapBack=b.maxZ-(p.z-playerRadius);
    const minOverlap=Math.min(overlapLeft,overlapRight,overlapFront,overlapBack);
    if(minOverlap===overlapLeft)p.x=b.minX-playerRadius;
    else if(minOverlap===overlapRight)p.x=b.maxX+playerRadius;
    else if(minOverlap===overlapFront)p.z=b.minZ-playerRadius;
    else if(minOverlap===overlapBack)p.z=b.maxZ+playerRadius;
   }
  }
  if(highestPlatformY>-Infinity&&p.y<=highestPlatformY+.05){
   p.y=highestPlatformY;
   controller.velocity.y=0;
   controller.isGrounded=true;
   return true;
  }
  return false;
 }
}

class PlayerController {
 constructor(mesh,camera){
  this.mesh=mesh;
  this.camera=camera;
  this.walkSpeed=6.0;
  this.sprintSpeed=11.0;
  this.jumpForce=8.5;
  this.gravity=-22.0;
  this.rotationSpeed=10.0;
  this.velocity=new THREE.Vector3();
  this.isGrounded=true;
  this.horizontalSpeed=0;
  this.keys={forward:false,backward:false,left:false,right:false,sprint:false};
  this.stamina=100;
  this.maxStamina=100;
  this._initListeners();
 }
 _initListeners(){
  addEventListener('keydown',e=>this._onKeyChange(e.code,true));
  addEventListener('keyup',e=>this._onKeyChange(e.code,false));
 }
 _onKeyChange(code,isPressed){
  switch(code){
   case 'KeyW': case 'ArrowUp': this.keys.forward=isPressed; break;
   case 'KeyS': case 'ArrowDown': this.keys.backward=isPressed; break;
   case 'KeyA': case 'ArrowLeft': this.keys.left=isPressed; break;
   case 'KeyD': case 'ArrowRight': this.keys.right=isPressed; break;
   case 'ShiftLeft': case 'ShiftRight': this.keys.sprint=isPressed; break;
   case 'Space':
    if(isPressed&&this.isGrounded){
     this.velocity.y=this.jumpForce;
     this.isGrounded=false;
    }
    break;
  }
 }
 update(dt){
  const inputDir=new THREE.Vector3();
  if(this.keys.forward)inputDir.z-=1;
  if(this.keys.backward)inputDir.z+=1;
  if(this.keys.left)inputDir.x-=1;
  if(this.keys.right)inputDir.x+=1;

  let moving=false;
  if(inputDir.lengthSq()>0){
   moving=true;
   inputDir.normalize();

   const cameraDirection=new THREE.Vector3();
   this.camera.getWorldDirection(cameraDirection);
   cameraDirection.y=0;
   cameraDirection.normalize();

   const cameraAngle=Math.atan2(cameraDirection.x,cameraDirection.z);
   const moveAngle=Math.atan2(inputDir.x,inputDir.z)+cameraAngle+Math.PI;
   const moveDir=new THREE.Vector3(Math.sin(moveAngle),0,Math.cos(moveAngle));

   const canSprint=this.keys.sprint&&this.stamina>0;
   const currentSpeed=canSprint?this.sprintSpeed:this.walkSpeed;
   if(canSprint)this.stamina=Math.max(0,this.stamina-dt*24);
   else this.stamina=Math.min(this.maxStamina,this.stamina+dt*16);
   this.mesh.position.addScaledVector(moveDir,currentSpeed*dt);
   this.horizontalSpeed=currentSpeed;

   // Facing is controlled by the over-the-shoulder camera yaw.
  }else{
   this.horizontalSpeed=0;
   this.stamina=Math.min(this.maxStamina,this.stamina+dt*18);
  }

  const terrainY=forestEnvironment.getTerrainHeight(this.mesh.position.x,this.mesh.position.z);

  this.velocity.y+=this.gravity*dt;
  this.mesh.position.y+=this.velocity.y*dt;

  if(this.mesh.position.y<=terrainY){
   this.mesh.position.y=terrainY;
   this.velocity.y=0;
   this.isGrounded=true;
  }

  houseParkour.resolvePlayerCollision(this);

  const actionKind=!this.isGrounded?'jump':moving?((this.keys.sprint&&this.stamina>0)?'run':'walk'):'idle';
  setAction(actionKind);
  if(mixer)mixer.update(dt);
  return actionKind;
 }
}

let model=null,mixer=null,actions={},active=null;
let firingCooldown=0;
let score=0,shots=0,hitCount=0;
const scoreEl=document.getElementById('score');
const hitsEl=document.getElementById('hits');
const playerStateEl=document.getElementById('playerState');
const speedEl=document.getElementById('speed');
const staminaBarEl=document.getElementById('staminaBar');
const altitudeEl=document.getElementById('altitude');
const hitmarkerEl=document.getElementById('hitmarker');

function flashHitmarker(){
 if(!hitmarkerEl)return;
 hitmarkerEl.classList.remove('active');
 void hitmarkerEl.offsetWidth;
 hitmarkerEl.classList.add('active');
}

class ThirdPersonCamera {
 constructor(camera,target,domElement,getGroundHeight){
  this.camera=camera;
  this.target=target;
  this.domElement=domElement;
  this.getGroundHeight=getGroundHeight;
  this.sensitivity=.005;
  this.smoothness=12.0;
  this.yaw=0;
  this.pitch=.18;
  this.minPitch=-.3;
  this.maxPitch=.85;
  this.isRightMouseDown=false;
  this.previousMouseX=0;
  this.previousMouseY=0;
  this.shoulderOffset=new THREE.Vector3(.85,.35,3.2);
  this.lookAheadOffset=new THREE.Vector3(.65,.1,-15);
  this.currentPosition=new THREE.Vector3(target.position.x+.85,target.position.y+1.8,target.position.z+3.2);
  this.currentLookAt=target.position.clone().add(new THREE.Vector3(0,1.45,-10));
  this._initListeners();
 }
 _initListeners(){
  this.domElement.addEventListener('contextmenu',e=>e.preventDefault());

  this.domElement.addEventListener('mousedown',e=>{
   if(e.button===2){
    this.isRightMouseDown=true;
    this.previousMouseX=e.clientX;
    this.previousMouseY=e.clientY;
   }
  });

  window.addEventListener('mouseup',e=>{
   if(e.button===2)this.isRightMouseDown=false;
  });

  window.addEventListener('mousemove',e=>{
   if(!this.isRightMouseDown)return;
   const deltaX=e.clientX-this.previousMouseX;
   const deltaY=e.clientY-this.previousMouseY;
   this.previousMouseX=e.clientX;
   this.previousMouseY=e.clientY;
   this.yaw-=deltaX*this.sensitivity;
   this.pitch-=deltaY*this.sensitivity;
   this.pitch=Math.max(this.minPitch,Math.min(this.maxPitch,this.pitch));
  });
 }
 update(dt){
  if(!this.target)return;
  const pivotPos=new THREE.Vector3(this.target.position.x,this.target.position.y+1.45,this.target.position.z);
  const euler=new THREE.Euler(this.pitch,this.yaw,0,'YXZ');

  const desiredCamPos=pivotPos.clone().add(this.shoulderOffset.clone().applyEuler(euler));
  if(typeof this.getGroundHeight==='function'){
   const minCamY=this.getGroundHeight(desiredCamPos.x,desiredCamPos.z)+.35;
   if(desiredCamPos.y<minCamY)desiredCamPos.y=minCamY;
  }

  const targetPoint=pivotPos.clone().add(this.lookAheadOffset.clone().applyEuler(euler));
  const t=1-Math.exp(-this.smoothness*dt);
  this.currentPosition.lerp(desiredCamPos,t);
  this.currentLookAt.lerp(targetPoint,t);
  this.camera.position.copy(this.currentPosition);
  this.camera.lookAt(this.currentLookAt);

  // Shooter behavior: avatar follows aim yaw, independent from movement direction.
  this.target.rotation.y=this.yaw+Math.PI;
 }
}

function getAimRaycastHit(raycaster,camera,scene,avatarGroup,ignoredObjects=[]){
 raycaster.setFromCamera(new THREE.Vector2(0,0),camera);

 const avatarMeshes=[];
 avatarGroup.traverse(child=>{
  if(child.isMesh)avatarMeshes.push(child);
 });
 const allIgnored=new Set([...avatarMeshes,...ignoredObjects]);

 const validTargets=scene.children.filter(obj=>!allIgnored.has(obj)&&obj!==avatarGroup);
 const intersects=raycaster.intersectObjects(validTargets,true);
 return intersects.find(hit=>!allIgnored.has(hit.object))||null;
}

addEventListener('mousedown',e=>{
 if(e.button!==0)return;
 // Sem arma equipada, não dispara.
 if(bowWeapon?.state==='holstered')return;
});

const mainAvatar=new SimpleAvatar({bodyColor:0x304b78,skinColor:0xd9c2aa,visorColor:0x111827});
player.add(mainAvatar.group);
const bowWeapon=new BowAnimationSystem(scene,mainAvatar);
bowWeapon.onArrowShot=(power,hit)=>{
 shots++;
 forestAudio.init();
 forestAudio.playShoot();
 if(hit){
  hitCount++;
  score+=Math.round(10+power*10);
  flashHitmarker();
  forestAudio.playHit();
 }
};

// Erika preservada no projeto, mas desativada nesta build.
const useErika=false;
if(useErika)new THREE.FBXLoader().load('/assets/models/erika-archer.fbx',fbx=>{
 model=fbx;
 model.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true}});
 const box3=new THREE.Box3().setFromObject(model),h=box3.max.y-box3.min.y;
 model.scale.setScalar(h>0?1.85/h:1);
 const b2=new THREE.Box3().setFromObject(model); model.position.y=-b2.min.y;
 player.add(model);
 mainAvatar.group.visible=false;
 if(model.animations?.length){
   mixer=new THREE.AnimationMixer(model);
   for(const clip of model.animations) actions[clip.name.toLowerCase()]=mixer.clipAction(clip);
 }
 stateEl.textContent='ERIKA READY';
},undefined,()=>{
 mainAvatar.group.visible=true;
 stateEl.textContent='AVATAR PROCEDURAL';
});

function pickAction(kind){
 const names=kind==='run'?['run','sprint']:kind==='walk'?['walk','locomotion']:kind==='jump'?['jump']:['idle','stand'];
 for(const n of names){const k=Object.keys(actions).find(k=>k.includes(n)); if(k)return actions[k]}
 return null;
}
function setAction(kind){
 const next=pickAction(kind); if(next===active)return;
 if(active)active.fadeOut(.14);
 active=next;
 if(active)active.reset().fadeIn(.14).play();
}

function shoot(){
 if(!bowWeapon||bowWeapon.state==='holstered')return;
 if(firingCooldown>0)return;
 firingCooldown=.13;
 shots++;
 forestAudio.init();

 const ray=new THREE.Raycaster();
 const firstHit=getAimRaycastHit(ray,camera,scene,player);
 const dir=new THREE.Vector3();
 camera.getWorldDirection(dir);
 const origin=camera.position.clone();
 const targetPoint=firstHit?.point || origin.clone().add(dir.multiplyScalar(90));

 if(bowWeapon.isEquipped){
  bowWeapon.triggerShot(targetPoint);
 }else{
  forestAudio.playShoot();
  const geo=new THREE.BufferGeometry().setFromPoints([
   player.position.clone().add(new THREE.Vector3(0,1.45,0)),
   targetPoint
  ]);
  const line=new THREE.Line(geo,new THREE.LineBasicMaterial({color:0xffe48b}));
  scene.add(line);
  setTimeout(()=>scene.remove(line),55);
 }

 if(firstHit){
  hitCount++;
  score+=10;
  flashHitmarker();
  forestAudio.playHit();
 }
}

const controller=new PlayerController(player,camera);
const thirdPersonCamera=new ThirdPersonCamera(camera,player,canvas,forestEnvironment.getTerrainHeight);

function updateCamera(dt){
 thirdPersonCamera.update(dt);
}
function resize(){renderer.setSize(innerWidth,innerHeight,false);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix()}
addEventListener('resize',resize);resize();

let gameStarted=false;
const menuOverlay=document.getElementById('aventura-menu-overlay');
const menuSettings={soundEnabled:true,sensitivity:1,shadows:true};
const menuViews=['view-main','view-modes','view-multiplayer','view-settings'];
function switchMenuView(id){
 menuViews.forEach(v=>document.getElementById(v)?.classList.add('hidden-view'));
 document.getElementById(id)?.classList.remove('hidden-view');
}
function hideGameMenu(){
 menuOverlay?.classList.add('hidden-menu');
 gameStarted=true;
 forestAudio.init();
}
function showGameMenu(){
 gameStarted=false;
 switchMenuView('view-main');
 menuOverlay?.classList.remove('hidden-menu');
}

const nickname='Arqueiro_'+Math.floor(100+Math.random()*900);
const nameInput=document.getElementById('input-player-name');
if(nameInput)nameInput.value=nickname;
document.getElementById('btn-menu-play')?.addEventListener('click',()=>switchMenuView('view-modes'));
document.getElementById('btn-menu-settings')?.addEventListener('click',()=>switchMenuView('view-settings'));
document.getElementById('btn-menu-exit')?.addEventListener('click',()=>{ try{window.close()}catch(_){} });
document.getElementById('btn-modes-back')?.addEventListener('click',()=>switchMenuView('view-main'));
document.getElementById('btn-mode-solo')?.addEventListener('click',hideGameMenu);
document.getElementById('btn-mode-multi')?.addEventListener('click',()=>switchMenuView('view-multiplayer'));
document.getElementById('btn-multi-back')?.addEventListener('click',()=>switchMenuView('view-modes'));
document.getElementById('btn-create-room')?.addEventListener('click',()=>{
 const code='FLR-'+Math.floor(100+Math.random()*899);
 const s=document.getElementById('multi-status-msg');
 if(s)s.textContent='Sala '+code+' criada. Multiplayer ainda em preparação.';
});
document.getElementById('btn-join-room')?.addEventListener('click',()=>{
 const code=(document.getElementById('input-room-code')?.value||'').trim().toUpperCase();
 const s=document.getElementById('multi-status-msg');
 if(s)s.textContent=code?'Sala '+code+' selecionada. Multiplayer ainda em preparação.':'Digite um código de sala.';
});
document.getElementById('btn-toggle-audio')?.addEventListener('click',e=>{
 menuSettings.soundEnabled=!menuSettings.soundEnabled;
 forestAudio.setEnabled(menuSettings.soundEnabled);
 e.currentTarget.textContent='SOM: '+(menuSettings.soundEnabled?'ATIVADO':'DESATIVADO');
});
document.getElementById('range-sens')?.addEventListener('input',e=>{
 menuSettings.sensitivity=parseFloat(e.target.value);
 document.getElementById('lbl-sens').textContent=menuSettings.sensitivity.toFixed(1);
 thirdPersonCamera.sensitivity=.005*menuSettings.sensitivity;
});
document.getElementById('btn-toggle-shadows')?.addEventListener('click',e=>{
 menuSettings.shadows=!menuSettings.shadows;
 renderer.shadowMap.enabled=menuSettings.shadows;
 e.currentTarget.textContent='SOMBRAS: '+(menuSettings.shadows?'ATIVADAS':'DESATIVADAS');
});
document.getElementById('btn-settings-back')?.addEventListener('click',()=>switchMenuView('view-main'));
addEventListener('keydown',e=>{if(e.code==='KeyM')showGameMenu()});

(function initMenuParticles(){
 const c=document.getElementById('menu-particles-canvas'); if(!c)return;
 const ctx=c.getContext('2d'); let w,h;
 const particles=[];
 function resizeP(){w=c.width=innerWidth;h=c.height=innerHeight}
 resizeP(); addEventListener('resize',resizeP);
 for(let i=0;i<45;i++)particles.push({x:Math.random()*innerWidth,y:Math.random()*innerHeight,r:Math.random()*2.2+.8,vx:(Math.random()-.5)*.35,vy:-Math.random()*.4-.1,a:Math.random()*.8+.2,p:Math.random()*Math.PI*2});
 function draw(){
  requestAnimationFrame(draw);
  if(menuOverlay?.classList.contains('hidden-menu'))return;
  ctx.clearRect(0,0,w,h);
  for(const p of particles){
   p.x+=p.vx;p.y+=p.vy;p.p+=.03;
   if(p.y<-10)p.y=h+10;if(p.x<-10)p.x=w+10;if(p.x>w+10)p.x=-10;
   const a=p.a*(.6+.4*Math.sin(p.p));
   ctx.beginPath();ctx.arc(p.x,p.y,p.r,0,Math.PI*2);ctx.fillStyle='rgba(255,223,150,'+a+')';ctx.shadowBlur=10;ctx.shadowColor='#ffd27d';ctx.fill();
  }
 }
 draw();
})();

const clock=new THREE.Clock();
function loop(){
 requestAnimationFrame(loop); const dt=Math.min(clock.getDelta(),.033);
 if(!gameStarted){ renderer.render(scene,camera); return; }
 controller.update(dt);
 mainAvatar.animate(dt,controller.horizontalSpeed>0.01,controller.keys.sprint);
 bowWeapon.update(dt,controller.horizontalSpeed>0.01);
 updateCamera(dt);
 firingCooldown=Math.max(0,firingCooldown-dt);
 const moving=controller.horizontalSpeed>0.01;
 if(moving&&controller.isGrounded)forestAudio.playFootstep();
 const stateLabel=!controller.isGrounded?'Pulando':moving?((controller.keys.sprint&&controller.stamina>0)?'Correndo':'Andando'):'Parado';
 if(scoreEl)scoreEl.textContent=String(score);
 if(hitsEl)hitsEl.textContent=hitCount+' / '+shots;
 if(playerStateEl)playerStateEl.textContent=stateLabel;
 if(speedEl)speedEl.textContent=controller.horizontalSpeed.toFixed(1)+' m/s';
 if(staminaBarEl)staminaBarEl.style.width=(controller.stamina/controller.maxStamina*100).toFixed(0)+'%';
 if(altitudeEl)altitudeEl.textContent=player.position.y.toFixed(1)+' m';
 stateEl.textContent=(controller.isGrounded?'CHÃO':'AR')+' • '+controller.horizontalSpeed.toFixed(1)+' m/s • Y '+player.position.y.toFixed(1)+' m';
 renderer.render(scene,camera);
}
loop();