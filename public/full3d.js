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
box(0,0,14,12,5,8,0x59646b);
box(-16,0,-4,9,7,10,0x6b5d55);
box(17,0,-8,11,4,9,0x565f5b);
box(0,0,-22,20,3,4,0x4d5558);
for(let i=-24;i<=24;i+=8) box(i,0,4,2,.35,8,0x484d50);

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
   this.pitch+=deltaY*this.sensitivity;
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
  this.target.rotation.y=this.yaw;
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

addEventListener('mousedown',e=>{if(e.button===0)shoot()});

const mainAvatar=new SimpleAvatar({bodyColor:0x304b78,skinColor:0xd9c2aa,visorColor:0x111827});
player.add(mainAvatar.group);

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
 if(firingCooldown>0)return;
 firingCooldown=.13;
 shots++;

 const ray=new THREE.Raycaster();
 const firstHit=getAimRaycastHit(ray,camera,scene,player);
 const dir=new THREE.Vector3();
 camera.getWorldDirection(dir);
 const origin=camera.position.clone();
 const end=firstHit?.point || origin.clone().add(dir.multiplyScalar(90));

 if(firstHit){
  hitCount++;
  score+=10;
  flashHitmarker();
 }

 const geo=new THREE.BufferGeometry().setFromPoints([
  player.position.clone().add(new THREE.Vector3(0,1.45,0)),
  end
 ]);
 const line=new THREE.Line(geo,new THREE.LineBasicMaterial({color:0xffe48b}));
 scene.add(line);
 setTimeout(()=>scene.remove(line),55);
}

const controller=new PlayerController(player,camera);
const thirdPersonCamera=new ThirdPersonCamera(camera,player,canvas,forestEnvironment.getTerrainHeight);

function updateCamera(dt){
 thirdPersonCamera.update(dt);
}
function resize(){renderer.setSize(innerWidth,innerHeight,false);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix()}
addEventListener('resize',resize);resize();

const clock=new THREE.Clock();
function loop(){
 requestAnimationFrame(loop); const dt=Math.min(clock.getDelta(),.033);
 controller.update(dt);
 mainAvatar.animate(dt,controller.horizontalSpeed>0.01,controller.keys.sprint);
 updateCamera(dt);
 firingCooldown=Math.max(0,firingCooldown-dt);
 const moving=controller.horizontalSpeed>0.01;
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