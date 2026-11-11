// Run with Three.js 0.187 installed, or set THREE_TEST_MODULE to its module path.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const math=await import(process.env.THREE_TEST_MODULE||'three');
class Renderer{constructor(){this.shadowMap={}}setPixelRatio(){}setSize(){}render(){}}
const THREE={...math,WebGLRenderer:Renderer};
const elements=new Map(),globalListeners={};
function element(){
 const classes=new Set(),listeners={};
 return {style:{},listeners,offsetWidth:24,addEventListener:(type,fn)=>{listeners[type]=fn},classList:{toggle:(name,value)=>{value?classes.add(name):classes.delete(name)},add:name=>classes.add(name),remove:name=>classes.delete(name),contains:name=>classes.has(name)},getBoundingClientRect:()=>({left:0,top:0,width:132,height:132}),setPointerCapture(){}};
}
let avatarLoaded;
const context={THREE,FBXLoader:class{load(_url,onLoad){avatarLoaded=onLoad}},document:{getElementById:id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id)},createElement:()=>({getContext:()=>({fillRect(){},strokeRect(){},fillText(){}})}),addEventListener(){}},addEventListener(type,fn){globalListeners[type]=fn},innerWidth:1280,innerHeight:720,devicePixelRatio:1,performance:{now:()=>0},requestAnimationFrame(){},console};
vm.createContext(context);
const source=fs.readFileSync(new URL('../public/3d.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
vm.runInContext(source+`\nglobalThis.api={traceAimRay,mobileAimDirection,updateAimFromPointer,updateThirdPersonCamera,fire,updateBullets3D,frame,buildings,enemies,bullets,player,camera,pointer,mobileAim,ammoState,get aimPoint(){return aimPoint},setYaw:y=>cameraYaw=y,setPitch:p=>cameraPitch=p,get keys(){return keys},get locomotion(){return locomotion},get ready(){return isWeaponReady()},updateWeaponPose,updateProceduralAvatar,setTime:time=>t=time,resetShot:()=>shotCooldown=0};`,context);
const a=context.api,V=THREE.Vector3;
a.buildings.length=0;a.enemies.length=0;
const enemy=(z,x=0)=>{const e=new THREE.Group();e.position.set(x,0,z);e.userData={alive:true,hp:3};a.enemies.push(e);return e};
const wall=z=>{const b=new THREE.Group();b.position.set(0,0,z);b.userData={w:4,h:5,d:1};a.buildings.push(b);return b};
const ray=()=>new THREE.Ray(new V(0,1.5,0),new V(0,0,-1));
const target=enemy(-12);wall(-6);
assert.equal(a.traceAimRay(ray(),30).kind,'wall','A wall must hide an enemy');
a.buildings.length=0;assert.equal(a.traceAimRay(ray(),30).object,target);
assert.equal(a.traceAimRay(ray(),5),null,'Hits outside the segment must be excluded');
enemy(6);a.enemies.shift();assert.equal(a.traceAimRay(ray(),30),null,'Enemies behind the camera cannot be selected');
a.enemies.length=0;
const nearEnemy=enemy(-2);wall(-3.5);assert.equal(a.traceAimRay(ray(),10).object,nearEnemy,'Nearest enemy must win before a farther wall in the same frame');
a.enemies.length=0;a.buildings.length=0;
for(const yaw of [0,Math.PI/2,Math.PI,-Math.PI/2]){
 a.setYaw(yaw);
 const up=a.mobileAimDirection(0,-1),right=a.mobileAimDirection(1,0);
 assert(Math.abs(up.dot(right))<1e-10);assert(Math.abs(up.length()-1)<1e-10);
 assert(up.distanceTo(new V(-Math.sin(yaw),0,-Math.cos(yaw)))<1e-10);
}
a.setYaw(0);a.setPitch(0);a.player.position.set(0,0,0);a.updateThirdPersonCamera(1,a.player);a.updateAimFromPointer();
assert.equal(elements.get('crosshair').style.left,'50%');assert.equal(elements.get('crosshair').style.top,'50%');
const projection=a.aimPoint.clone().project(a.camera);assert(Math.abs(projection.x)<1e-8&&Math.abs(projection.y)<1e-8,'Desktop aim must coincide with center reticle');
const gunTarget=enemy(-12,.85);a.updateAimFromPointer();
const initialAmmo=a.ammoState.pistol.mag;
a.fire();assert.equal(a.ammoState.pistol.mag,initialAmmo-1);assert.equal(a.bullets.length,1);
for(let i=0;i<30;i++)a.updateBullets3D(1/60);
assert.equal(gunTarget.userData.hp,2,'Projectile from actual muzzle must reach the center-ray target');
assert(elements.get('hitmarker').classList.contains('active'),'Only confirmed impact must show the hitmarker');
assert.equal(a.bullets.length,0);
// Continuous segment collision prevents tunneling even in a slow frame.
a.resetShot();a.fire();const blocker=wall(-6);blocker.position.x=.85;
a.updateBullets3D(.5);assert.equal(gunTarget.userData.hp,2,'A wall must block a fast projectile');
// UI buttons have no global pointerdown shooting handler; touch canvas cannot fire.
const before=a.ammoState.pistol.mag;a.resetShot();elements.get('view').listeners.pointerdown({pointerType:'touch',button:0});assert.equal(a.ammoState.pistol.mag,before);
a.mobileAim.active=true;a.mobileAim.x=1;a.mobileAim.y=0;a.updateAimFromPointer();assert(a.aimPoint.x>a.player.position.x);
// Pulling the mobile stick fires; centering/releasing it stops firing.
a.enemies.length=0;a.buildings.length=0;
const stick=elements.get('aimStick');
stick.listeners.pointerdown({pointerId:1,clientX:100,clientY:66});assert(a.mobileAim.firing);
a.resetShot();const mobileAmmo=a.ammoState.pistol.mag;a.frame(16);assert.equal(a.ammoState.pistol.mag,mobileAmmo-1);
stick.listeners.pointerup({pointerId:1});assert(!a.mobileAim.firing&&!a.mobileAim.active);
// A held mouse button must continue firing while WASD moves the player.
a.mobileAim.active=false;a.resetShot();a.player.position.set(0,0,0);
a.keys.add('w');const walkingAmmo=a.ammoState.pistol.mag;
elements.get('view').listeners.pointerdown({pointerType:'mouse',button:0});
for(let i=1;i<=45;i++)a.frame(16+i*16);
assert(a.player.position.z<-.5,'W must keep moving while firing');
assert(a.ammoState.pistol.mag<=walkingAmmo-3,'Holding fire must shoot more than once while moving');
globalListeners.pointerup({button:0});a.keys.clear();const stoppedAmmo=a.ammoState.pistol.mag;
for(let i=46;i<=70;i++)a.frame(16+i*16);
assert.equal(a.ammoState.pistol.mag,stoppedAmmo,'Mouse release must stop firing');
a.setTime(100);a.updateWeaponPose();assert.equal(a.player.userData.weaponPose,'rest');
console.log('PASS: full game startup; centered ray; front/back and range selection; wall occlusion; nearest impact ordering; rotated mobile aim; muzzle trajectory; damage; hitmarker; UI/touch isolation.');

export {context,elements,globalListeners,THREE};
export const api=a;
export const loadAvatar=model=>avatarLoaded(model);
