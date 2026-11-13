const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const THREE=require('../public/vendor/three-r128.min.js');
let cachedRuntime;
function runtime(){if(cachedRuntime)return cachedRuntime;const c={THREE,window:{},console};vm.createContext(c);for(const f of ['operator-motion','operator-avatar','weapon-loot','multiplayer-world'])vm.runInContext(fs.readFileSync('public/'+f+'.js','utf8'),c);cachedRuntime=c;return c;}
test('remote avatar crawls smoothly at replicated speed and displays/removes its jetpack',()=>{
 const c=runtime(),world=new c.window.MultiplayerWorld(new THREE.Scene());
 const state={id:'other',x:0,y:0,z:0,angle:0,weapon:'rifle',grounded:true,crouching:true,prone:1,proneSlope:.1,proneRoll:0,speed:1.15,moving:true,running:false,jetpack:true,jetpackActive:true};
 world.receive(state);const r=world.players.get('other');
 for(let i=0;i<120;i++)world.update(1/60);
 r.avatar.group.updateMatrixWorld(true);
 assert(r.avatar.bones[5].getWorldPosition(new THREE.Vector3()).y<.8,'remote head must lie near the floor');
 assert(Math.abs(r.avatar.speed-1.15)<.05,'crawl speed must not become a running animation');
 assert(r.jetpack&&r.jetpack.visible);assert(r.jetpack.parent===r.avatar.torso,'Jetpack follows the spine');assert(r.jetpack.getWorldPosition(new THREE.Vector3()).y<.95,'Jetpack rests on the prone back');assert(r.jetpack.userData.flames[0].material.opacity>.8);
 world.receive({...state,prone:0,crouching:false,speed:0,moving:false,jetpack:false,jetpackActive:false});
 for(let i=0;i<120;i++)world.update(1/60);
 r.avatar.group.updateMatrixWorld(true);assert(r.avatar.bones[5].getWorldPosition(new THREE.Vector3()).y>1.4);assert.equal(r.jetpack,null);
 world.clear();assert.equal(world.players.size,0);
});
test('prone hit envelope rotates, interpolates and respects airborne posture and range',()=>{
 const c=runtime();vm.runInContext(fs.readFileSync('public/tactical-rules.js','utf8'),c);const R=c.TacticalRules;
 assert.equal(typeof R.bodyHitDistance,'function');
 const p={x:0,y:0,z:0,angle:Math.PI/2,grounded:true,prone:1,crouching:true};
 assert.notEqual(R.bodyHitDistance({x:-3,y:.3,z:0},{x:1,y:0,z:0},p,10),null);
 assert.equal(R.bodyHitDistance({x:-3,y:1.5,z:0},{x:1,y:0,z:0},p,10),null);
 assert.equal(R.bodyHitDistance({x:-3,y:.3,z:0},{x:1,y:0,z:0},p,1),null);
 assert.notEqual(R.bodyHitDistance({x:-3,y:1.5,z:0},{x:1,y:0,z:0},{...p,grounded:false},10),null);
 assert.notEqual(R.bodyHitDistance({x:-3,y:.8,z:0},{x:1,y:0,z:0},{...p,prone:.3},10),null);
});

test('server envelope contains real skinned prone head hits throughout transitions',()=>{
 const c=runtime();vm.runInContext(fs.readFileSync('public/tactical-rules.js','utf8'),c);const avatar=new c.window.OperatorAvatar();
 for(const prone of [.25,.5,.75,1]){
  for(let i=0;i<120;i++)avatar.update(1/60,{armed:true,grounded:true,crouching:true,prone});
  avatar.group.updateMatrixWorld(true);avatar.skeleton.update();
  const head=avatar.bones[5].getWorldPosition(new THREE.Vector3());
  const ray=new THREE.Raycaster(new THREE.Vector3(-3,head.y,head.z),new THREE.Vector3(1,0,0),0,10);
  assert(ray.intersectObject(avatar.body,false).length>0,'Ray crosses actual head at blend '+prone);
  assert.notEqual(c.TacticalRules.bodyHitDistance(ray.ray.origin,ray.ray.direction,{x:0,y:0,z:0,angle:0,grounded:true,crouching:true,prone},10),null,'Server accepts mesh hit at blend '+prone);
 }
});

test('server accepts actual head impacts while crouching and standing transitions are in progress',()=>{
 const c=runtime(),avatar=new c.window.OperatorAvatar();
 for(let i=0;i<120;i++)avatar.update(1/60,{armed:true,grounded:true});
 for(const crouching of [true,false])for(let frame=0;frame<30;frame++){
  avatar.update(1/60,{armed:true,grounded:true,crouching});avatar.group.updateMatrixWorld(true);avatar.skeleton.update();
  const head=avatar.head.getWorldPosition(new THREE.Vector3());
  const ray=new THREE.Raycaster(new THREE.Vector3(-3,head.y,head.z),new THREE.Vector3(1,0,0),0,10);
  assert(ray.intersectObject(avatar.body,false).length>0);
  assert.notEqual(c.TacticalRules.bodyHitDistance(ray.ray.origin,ray.ray.direction,{x:0,y:0,z:0,angle:0,grounded:true,crouching,crouchBlend:avatar.crouchBlend},10),null,'Head stays hittable at crouch blend '+avatar.crouchBlend);
 }
});
