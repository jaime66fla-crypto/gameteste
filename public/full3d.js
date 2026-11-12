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
scene.background=new THREE.Color(0x9fc7df);
scene.fog=new THREE.Fog(0x9fc7df,38,115);
const camera=new THREE.PerspectiveCamera(58,innerWidth/innerHeight,.1,250);

scene.add(new THREE.HemisphereLight(0xdce8f0,0x35513a,2.0));
const sun=new THREE.DirectionalLight(0xffe5bd,3.5);
sun.position.set(-18,28,-14); sun.castShadow=true; sun.shadow.mapSize.set(2048,2048);
sun.shadow.camera.left=-40; sun.shadow.camera.right=40; sun.shadow.camera.top=40; sun.shadow.camera.bottom=-40;
scene.add(sun);

const floor=new THREE.Mesh(new THREE.PlaneGeometry(120,120,1,1),new THREE.MeshStandardMaterial({color:0x5f7f4d,roughness:1}));

floor.rotation.x=-Math.PI/2; floor.receiveShadow=true; scene.add(floor);

// Nature ambience
const natureGroup=new THREE.Group(); scene.add(natureGroup);

function makeTree(x,z,s=1){
 const g=new THREE.Group();
 const trunk=new THREE.Mesh(
   new THREE.CylinderGeometry(.18*s,.24*s,2.1*s,8),
   new THREE.MeshStandardMaterial({color:0x6c4b2f,roughness:1})
 );
 trunk.position.y=1.05*s; trunk.castShadow=true; trunk.receiveShadow=true; g.add(trunk);
 const leafMat=new THREE.MeshStandardMaterial({color:0x3e6f38,roughness:.95});
 const crown1=new THREE.Mesh(new THREE.SphereGeometry(.95*s,8,7),leafMat);
 crown1.position.set(0,2.45*s,0); crown1.castShadow=true; crown1.receiveShadow=true; g.add(crown1);
 const crown2=new THREE.Mesh(new THREE.SphereGeometry(.72*s,8,7),new THREE.MeshStandardMaterial({color:0x4f8243,roughness:.95}));
 crown2.position.set(.25*s,3.05*s,.08*s); crown2.castShadow=true; g.add(crown2);
 g.position.set(x,0,z); natureGroup.add(g);
}
function makeBush(x,z,s=1){
 const g=new THREE.Group();
 const mat=new THREE.MeshStandardMaterial({color:0x4f7c43,roughness:1});
 for(const [ox,oz,sc] of [[0,0,1],[.45,.12,.78],[-.4,.1,.72],[.1,-.36,.66]]){
   const m=new THREE.Mesh(new THREE.SphereGeometry(.52*s*sc,7,6),mat);
   m.position.set(ox*s,.42*s,oz*s); m.castShadow=true; m.receiveShadow=true; g.add(m);
 }
 g.position.set(x,0,z); natureGroup.add(g);
}
function makeRock(x,z,s=1){
 const m=new THREE.Mesh(
   new THREE.DodecahedronGeometry(.55*s,0),
   new THREE.MeshStandardMaterial({color:0x737b70,roughness:1})
 );
 m.scale.set(1.25,.75,1); m.position.set(x,.32*s,z); m.rotation.set(.2,.5,.1);
 m.castShadow=true; m.receiveShadow=true; natureGroup.add(m);
}
function makeGrassPatch(x,z,w,d,color){
 const m=new THREE.Mesh(
   new THREE.PlaneGeometry(w,d),
   new THREE.MeshStandardMaterial({color,roughness:1,side:THREE.DoubleSide})
 );
 m.rotation.x=-Math.PI/2; m.position.set(x,.012,z); m.receiveShadow=true; natureGroup.add(m);
}

makeGrassPatch(-22,-18,22,15,0x557447);
makeGrassPatch(0,0,34,24,0x6f9259);
makeGrassPatch(24,18,26,18,0x6b8d55);
makeGrassPatch(-22,22,18,16,0x64824f);
makeGrassPatch(24,-22,20,15,0x58784a);

[
 [-26,-20,1.25],[-20,-26,1],[-30,6,1.15],[-24,20,1.05],[-12,28,.9],
 [14,27,1.15],[26,24,1.25],[31,8,1],[28,-18,1.2],[16,-28,1],
 [-4,-30,.9],[7,31,.95],
 [-8,8,.95],[8,10,1.05],[-11,-6,.9],[12,-4,.9]
].forEach(v=>makeTree(...v));

[
 [-18,-12,1],[-13,20,.85],[-29,14,.9],[22,13,1],[30,-7,.95],
 [18,-21,.85],[-6,27,.8],[10,-26,.8],
 [-5,5,.85],[5,6,.8],[-7,-3,.75],[7,-2,.8]
].forEach(v=>makeBush(...v));

[
 [-10,-18,.9],[-28,-4,.75],[-18,28,.8],[24,28,.95],[31,17,.7],
 [20,-29,.85],[6,-31,.65]
].forEach(v=>makeRock(...v));


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

class SimpleAvatar {
 constructor(options={}){
  this.group=new THREE.Group();
  const bodyColor=options.bodyColor||0x3b82f6;
  const skinColor=options.skinColor||0xf1f5f9;
  const visorColor=options.visorColor||0x0f172a;

  const bodyMat=new THREE.MeshStandardMaterial({color:bodyColor,roughness:.4});
  const skinMat=new THREE.MeshStandardMaterial({color:skinColor,roughness:.3});
  const visorMat=new THREE.MeshStandardMaterial({color:visorColor,roughness:.1,metalness:.8});

  const legGeo=new THREE.CapsuleGeometry(.11,.45,4,8);
  this.leftLeg=new THREE.Group();
  this.leftLeg.position.set(-.18,.65,0);
  const leftLegMesh=new THREE.Mesh(legGeo,skinMat);
  leftLegMesh.position.y=-.32; leftLegMesh.castShadow=true; this.leftLeg.add(leftLegMesh);

  this.rightLeg=new THREE.Group();
  this.rightLeg.position.set(.18,.65,0);
  const rightLegMesh=new THREE.Mesh(legGeo,skinMat);
  rightLegMesh.position.y=-.32; rightLegMesh.castShadow=true; this.rightLeg.add(rightLegMesh);

  const torsoGeo=new THREE.CapsuleGeometry(.32,.5,4,12);
  this.torso=new THREE.Mesh(torsoGeo,bodyMat);
  this.torso.position.y=1.05; this.torso.castShadow=true;

  this.head=new THREE.Group();
  this.head.position.y=1.75;
  const headMesh=new THREE.Mesh(new THREE.SphereGeometry(.28,16,16),skinMat);
  headMesh.castShadow=true; this.head.add(headMesh);

  const visorMesh=new THREE.Mesh(new THREE.BoxGeometry(.36,.14,.15),visorMat);
  visorMesh.position.set(0,.02,.22); this.head.add(visorMesh);

  const armGeo=new THREE.CapsuleGeometry(.09,.45,4,8);
  this.leftArm=new THREE.Group();
  this.leftArm.position.set(-.44,1.32,0);
  const leftArmMesh=new THREE.Mesh(armGeo,skinMat);
  leftArmMesh.position.y=-.25; leftArmMesh.castShadow=true; this.leftArm.add(leftArmMesh);

  this.rightArm=new THREE.Group();
  this.rightArm.position.set(.44,1.32,0);
  const rightArmMesh=new THREE.Mesh(armGeo,skinMat);
  rightArmMesh.position.y=-.25; rightArmMesh.castShadow=true; this.rightArm.add(rightArmMesh);

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

   const currentSpeed=this.keys.sprint?this.sprintSpeed:this.walkSpeed;
   this.mesh.position.addScaledVector(moveDir,currentSpeed*dt);
   this.horizontalSpeed=currentSpeed;

   const targetQuaternion=new THREE.Quaternion();
   targetQuaternion.setFromAxisAngle(new THREE.Vector3(0,1,0),moveAngle);
   this.mesh.quaternion.slerp(targetQuaternion,Math.min(1,this.rotationSpeed*dt));
  }else{
   this.horizontalSpeed=0;
  }

  this.velocity.y+=this.gravity*dt;
  this.mesh.position.y+=this.velocity.y*dt;

  if(this.mesh.position.y<=0){
   this.mesh.position.y=0;
   this.velocity.y=0;
   this.isGrounded=true;
  }

  const actionKind=!this.isGrounded?'jump':moving?(this.keys.sprint?'run':'walk'):'idle';
  setAction(actionKind);
  if(mixer)mixer.update(dt);
  return actionKind;
 }
}

let model=null,mixer=null,actions={},active=null;
let firingCooldown=0;

class ThirdPersonCamera {
 constructor(camera,target,domElement){
  this.camera=camera;
  this.target=target;
  this.domElement=domElement;
  this.distance=6.0;
  this.minDistance=2.5;
  this.maxDistance=12.0;
  this.sensitivity=.0025;
  this.smoothness=12.0;
  this.targetOffset=new THREE.Vector3(0,1.5,0);
  this.yaw=0;
  this.pitch=.3;
  this.minPitch=-.3;
  this.maxPitch=1.2;
  this.currentPosition=new THREE.Vector3(
   target.position.x,
   target.position.y+2.5,
   target.position.z+this.distance
  );
  this.currentLookAt=target.position.clone().add(this.targetOffset);
  this._initListeners();
 }
 _initListeners(){
  this.domElement.addEventListener('click',()=>{
   if(document.pointerLockElement!==this.domElement){
    this.domElement.requestPointerLock?.();
   }
  });
  document.addEventListener('mousemove',e=>{
   if(document.pointerLockElement===this.domElement){
    this.yaw-=e.movementX*this.sensitivity;
    this.pitch+=e.movementY*this.sensitivity;
    this.pitch=Math.max(this.minPitch,Math.min(this.maxPitch,this.pitch));
   }
  });
  document.addEventListener('wheel',e=>{
   this.distance+=e.deltaY*.005;
   this.distance=Math.max(this.minDistance,Math.min(this.maxDistance,this.distance));
  },{passive:true});
 }
 update(dt){
  if(!this.target)return;
  const focusPoint=this.target.position.clone().add(this.targetOffset);
  const horizontalDistance=this.distance*Math.cos(this.pitch);
  const verticalDistance=this.distance*Math.sin(this.pitch);
  const idealPosition=new THREE.Vector3(
   focusPoint.x+horizontalDistance*Math.sin(this.yaw),
   focusPoint.y+verticalDistance,
   focusPoint.z+horizontalDistance*Math.cos(this.yaw)
  );
  const t=1-Math.exp(-this.smoothness*dt);
  this.currentPosition.lerp(idealPosition,t);
  this.currentLookAt.lerp(focusPoint,t);
  this.camera.position.copy(this.currentPosition);
  this.camera.lookAt(this.currentLookAt);
 }
}

addEventListener('mousedown',e=>{if(e.button===0)shoot()});

function makeGun(){
 const g=new THREE.Group();
 const mat=new THREE.MeshStandardMaterial({color:0x24292d,metalness:.65,roughness:.35});
 const body=new THREE.Mesh(new THREE.BoxGeometry(.72,.12,.18),mat); body.position.z=-.32; g.add(body);
 const barrel=new THREE.Mesh(new THREE.BoxGeometry(.08,.08,.52),mat); barrel.position.z=-.9; g.add(barrel);
 const stock=new THREE.Mesh(new THREE.BoxGeometry(.18,.18,.28),mat); stock.position.z=.1; g.add(stock);
 g.position.set(.28,1.43,-.26); g.rotation.x=-.08; player.add(g); player.userData.gun=g;
}
makeGun();

const fallbackAvatar=new SimpleAvatar({bodyColor:0x304b78,skinColor:0xd9c2aa,visorColor:0x111827});
player.add(fallbackAvatar.group);

new THREE.FBXLoader().load('/assets/models/erika-archer.fbx',fbx=>{
 model=fbx;
 model.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true}});
 const box3=new THREE.Box3().setFromObject(model),h=box3.max.y-box3.min.y;
 model.scale.setScalar(h>0?1.85/h:1);
 const b2=new THREE.Box3().setFromObject(model); model.position.y=-b2.min.y;
 player.add(model);
 fallbackAvatar.group.visible=false;
 if(model.animations?.length){
   mixer=new THREE.AnimationMixer(model);
   for(const clip of model.animations) actions[clip.name.toLowerCase()]=mixer.clipAction(clip);
 }
 stateEl.textContent='ERIKA READY';
},undefined,()=>{
 fallbackAvatar.group.visible=true;
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
 const dir=new THREE.Vector3(); camera.getWorldDirection(dir);
 const origin=camera.position.clone();
 const ray=new THREE.Raycaster(origin,dir,0,100);
 const hits=ray.intersectObjects(scene.children.filter(o=>o!==player),true);
 const end=hits[0]?.point || origin.clone().add(dir.multiplyScalar(90));
 const geo=new THREE.BufferGeometry().setFromPoints([player.position.clone().add(new THREE.Vector3(0,1.45,0)),end]);
 const line=new THREE.Line(geo,new THREE.LineBasicMaterial({color:0xffe48b}));
 scene.add(line); setTimeout(()=>scene.remove(line),55);
}

const controller=new PlayerController(player,camera);
const thirdPersonCamera=new ThirdPersonCamera(camera,player,canvas);

function updateCamera(dt){
 thirdPersonCamera.update(dt);
}
function resize(){renderer.setSize(innerWidth,innerHeight,false);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix()}
addEventListener('resize',resize);resize();

const clock=new THREE.Clock();
function loop(){
 requestAnimationFrame(loop); const dt=Math.min(clock.getDelta(),.033);
 controller.update(dt);
 fallbackAvatar.animate(dt,controller.horizontalSpeed>0.01,controller.keys.sprint);
 updateCamera(dt);
 firingCooldown=Math.max(0,firingCooldown-dt);
 stateEl.textContent=(controller.isGrounded?'CHÃO':'AR')+' • '+controller.horizontalSpeed.toFixed(1)+' m/s';
 renderer.render(scene,camera);
}
loop();