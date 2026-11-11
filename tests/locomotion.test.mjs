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
assert(Math.abs(a.locomotion.speed-2.6)<.01);assert(maxSlide<.025,`Planted-foot drift per frame is ${maxSlide}`);
a.keys.clear();const movingSpeed=a.locomotion.speed;step();assert(a.locomotion.speed>0&&a.locomotion.speed<movingSpeed,'Stopping must decelerate smoothly');
for(let i=0;i<75;i++)step();assert(a.locomotion.speed<.025&&a.locomotion.blend<.01,'Locomotion must settle to idle');
// A wall must stop both real motion and the distance-driven gait clock.
a.player.position.set(0,0,0);const wall=new THREE.Group();wall.position.set(0,0,-.7);wall.userData={w:100,h:5,d:1};a.buildings.push(wall);a.keys.add('w');const phase=a.locomotion.phase;
for(let i=0;i<30;i++)step();assert.equal(a.locomotion.speed,0);assert.equal(a.locomotion.phase,phase);
a.buildings.length=0;
// Running, walking backward, and strafing must not corrupt the real skeleton or weapon mount.
for(const key of ['w','s','a','d']){
 a.keys.clear();a.keys.add(key);a.keys.add('shift');elements.get('view').listeners.pointerdown({pointerType:'mouse',button:2,clientX:0,clientY:0});
 for(let i=0;i<50;i++)step();
 assert(a.locomotion.speed>5&&a.locomotion.speed<=5.21);
 assert.equal(a.player.userData.gun.parent,bones.handR.bone);
 for(const {bone}of Object.values(bones))assert(bone.quaternion.toArray().every(Number.isFinite));
}
globalListeners.pointerup({button:2});a.keys.clear();
console.log(`PASS: smooth acceleration/stopping; actual-distance gait; wall stop; foot support (max drift ${maxSlide.toFixed(4)} m/frame, plant error ${maxPlantError.toFixed(4)} m); run/backward/strafe; shooting hand mount retained.`);
