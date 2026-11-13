import assert from 'node:assert/strict';
import {a,model,bones} from './erika-combat.test.mjs';
import {THREE,elements,globalListeners} from './aim.test.mjs';
let clock=10000;
const step=()=>{clock+=1000/60;a.frame(clock)};
a.setTime(1000);a.enemies.length=0;a.buildings.length=0;a.player.position.set(0,0,0);a.setYaw(0);a.setPitch(0);
a.locomotion.velocity.set(0,0,0);a.locomotion.phase=0;a.locomotion.blend=0;a.locomotion.planted.L=null;a.locomotion.planted.R=null;
a.keys.add('w');step();assert(a.locomotion.speed>0&&a.locomotion.speed<1,'Acceleration must be gradual');
let maxSlide=0,maxPlantError=0,previous=null;
for(let i=0;i<100;i++){
 step();const foot=bones.footL.bone.getWorldPosition(new THREE.Vector3());
 const cycle=a.locomotion.phase/(Math.PI*2),stance=cycle<.62;
 if(stance&&previous?.stance&&a.locomotion.blend>.99)maxSlide=Math.max(maxSlide,foot.distanceTo(previous.foot));
 if(stance&&a.locomotion.blend>.99&&a.locomotion.planted.L)maxPlantError=Math.max(maxPlantError,foot.distanceTo(a.locomotion.planted.L));
 previous={foot,stance};
 assert(foot.y>a.player.position.y-.025,'Feet must stay above the floor');
}
assert(maxPlantError<.06,'Support-foot reach must stay within six centimetres');
assert(Math.abs(a.locomotion.speed-4.2)<.01);assert(maxSlide<.025,`Planted-foot drift per frame is ${maxSlide}`);
a.keys.clear();const movingSpeed=a.locomotion.speed;step();assert(a.locomotion.speed>0&&a.locomotion.speed<movingSpeed,'Stopping must decelerate smoothly');
for(let i=0;i<75;i++)step();assert(a.locomotion.speed<.025&&a.locomotion.blend<.01,'Locomotion must settle to idle');
// A wall must stop both real motion and the distance-driven gait clock.
a.player.position.set(0,0,0);const wall=new THREE.Group();wall.position.set(0,0,-.7);wall.userData={w:100,h:5,d:1};a.buildings.push(wall);a.keys.add('w');const phase=a.locomotion.phase;
for(let i=0;i<30;i++)step();assert.equal(a.locomotion.speed,0);assert.equal(a.locomotion.phase,phase);
a.buildings.length=0;
// Running, walking backward, and strafing must not corrupt the real skeleton or weapon mount.
for(const key of ['w','s','a','d']){
 a.keys.clear();a.keys.add(key);a.keys.add('shift');elements.get('view').listeners.mousedown({pointerType:'mouse',button:2,clientX:0,clientY:0,preventDefault(){}});
 for(let i=0;i<50;i++)step();
 const expectedSpeed=key==='s'?2.34:key==='w'?3:2.7;assert(Math.abs(a.locomotion.speed-expectedSpeed)<.1,'Aimed movement respects directional speed');
 assert.equal(a.player.userData.gun.parent,bones.handR.bone);
 for(const {bone}of Object.values(bones))assert(bone.quaternion.toArray().every(Number.isFinite));
}
globalListeners.mouseup({button:2});a.keys.clear();
// Exercise the reference-inspired free sprint on the actual FBX, rather than
// only the aimed stride above: the hands must swing in opposite directions.
a.setTime(2000);a.keys.add('w');a.keys.add('shift');
const armSamples=[];let minArm=Infinity,maxArm=-Infinity;
for(let i=0;i<180;i++){
 step();
 const local=side=>a.player.worldToLocal(bones['hand'+side].bone.getWorldPosition(new THREE.Vector3()));
 const l=local('L'),r=local('R');
 if(i>60){
  const swing=l.z-r.z;minArm=Math.min(minArm,swing);maxArm=Math.max(maxArm,swing);
  for(const side of ['L','R']){
   const u=bones['upperArm'+side].bone.getWorldPosition(new THREE.Vector3());
   const e=bones['foreArm'+side].bone.getWorldPosition(new THREE.Vector3());
   const h=bones['hand'+side].bone.getWorldPosition(new THREE.Vector3());
   const straight=h.distanceTo(u)/(e.distanceTo(u)+h.distanceTo(e));
   assert(straight<.99&&straight>.4,'Sprint elbows must bend without folding shut');
  }
  armSamples.push([l.z,r.z]);
 }
 assert.equal(a.player.userData.gun.parent,bones.spine2.bone,'Free sprint keeps the gun on the back');
 for(const side of ['L','R'])assert(bones['foot'+side].bone.getWorldPosition(new THREE.Vector3()).y>-.025,'Sprint foot must clear the floor');
}
assert(maxArm-minArm>.6,'Free sprint must have visible alternating arm travel');
const means=[0,1].map(k=>armSamples.reduce((sum,p)=>sum+p[k],0)/armSamples.length);
const covariance=armSamples.reduce((sum,p)=>sum+(p[0]-means[0])*(p[1]-means[1]),0)/armSamples.length;
assert(covariance<-.01,'Arms must counter-swing during sprint');
a.keys.clear();
console.log(`PASS: smooth acceleration/stopping; actual-distance gait; wall stop; foot support (max drift ${maxSlide.toFixed(4)} m/frame, plant error ${maxPlantError.toFixed(4)} m); run/backward/strafe; shooting hand mount retained.`);
console.log('PASS: free sprint on real Erika skeleton; bent elbows; opposing arm swing; floor clearance; back-mounted weapon.');
