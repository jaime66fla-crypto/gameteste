const fs=require('fs'),vm=require('vm'),assert=require('assert');const THREE=require(process.cwd()+'/public/vendor/three-r128.min.js');
THREE.WebGLRenderer=class{constructor(){this.shadowMap={}}setPixelRatio(){}setSize(){}render(){}};
const ctx2d=new Proxy({createLinearGradient:()=>({addColorStop(){}}),createRadialGradient:()=>({addColorStop(){}}),measureText:()=>({width:30})},{get:(o,k)=>o[k]||(()=>{})});
const els=new Map();function element(){return {style:{},setAttribute(){},classList:{add(){},remove(){},contains(){return false}},addEventListener(){},appendChild(){},getContext:()=>ctx2d,getBoundingClientRect:()=>({left:0,top:0,width:1280,height:720})};}function el(id){if(!els.has(id))els.set(id,element());return els.get(id)}
const context={THREE,window:{addEventListener(){}},document:{getElementById:el,createElement:element,addEventListener(){}},addEventListener(){},devicePixelRatio:1,innerWidth:1280,innerHeight:720,requestAnimationFrame(){},console,setTimeout(){},clearTimeout(){},performance:{now:()=>1000},location:{host:'game.test',protocol:'https:'},WebSocket:class{},localStorage:{getItem(){return null},setItem(){}}};
vm.createContext(context);vm.runInContext(fs.readFileSync('public/operator-avatar.js','utf8'),context);vm.runInContext(fs.readFileSync('public/combat-bots.js','utf8'),context);vm.runInContext(fs.readFileSync('public/cover-controller.js','utf8'),context);vm.runInContext(fs.readFileSync('public/full3d.js','utf8')+'\nglobalThis.testApi={mainAvatar,pistolWeapon,scene,player,controller,combatBots,forestAudio,getStats:()=>({score,hitCount,shots}),houseParkour,thirdPersonCamera,frame:loop,start:()=>gameStarted=true};',context);
const a=context.testApi;assert(a.mainAvatar instanceof context.window.OperatorAvatar);assert.equal(a.pistolWeapon.pistol,a.mainAvatar.gun);assert.equal(a.mainAvatar.gun.visible,false);a.pistolWeapon.equip();assert.equal(a.mainAvatar.gun.visible,true);a.pistolWeapon.update(.016,true);a.mainAvatar.update(.016,{speed:2,armed:true});a.pistolWeapon.holster();assert.equal(a.mainAvatar.gun.visible,false);a.start();a.frame();a.player.updateMatrixWorld(true);console.log('PASS: full game boot, approved avatar mount, equip/holster and gameplay frame');

a.houseParkour.solidBoxes=[];a.player.position.set(0,0,0);a.controller._onKeyChange('ControlLeft',true);a.controller._onKeyChange('KeyW',true);a.controller._onKeyChange('ShiftLeft',true);
for(let i=0;i<80;i++)a.controller.update(1/60);
assert(a.controller.isCrouching);assert(a.controller.horizontalSpeed<a.controller.walkSpeed*.5,'Crouching must prevent sprinting');assert.equal(a.controller.stamina,a.controller.maxStamina);
assert(a.controller.collisionHeight<1.5);a.thirdPersonCamera.update(1/60);assert(a.thirdPersonCamera.offset.y<1.5,'Camera must lower with crouch');
a.controller._onKeyChange('KeyW',false);a.controller._onKeyChange('ControlLeft',false);
const p=a.player.position;
a.houseParkour.solidBoxes=[{minX:p.x-1,maxX:p.x+1,minZ:p.z-1,maxZ:p.z+1,minY:p.y+1.5,maxY:p.y+2}];
a.controller.update(1/60);assert(a.controller.isCrouching,'Low ceiling must block standing');
a.houseParkour.solidBoxes=[];for(let i=0;i<80;i++)a.controller.update(1/60);assert(!a.controller.isCrouching);assert(a.controller.collisionHeight>1.79);
a.controller._onKeyChange('ControlRight',true);a.controller.update(1/60);assert(a.controller.isCrouching);a.controller.clearInput();a.controller.update(1/60);assert(!a.controller.isCrouching,'Blur reset must not leave crouch stuck');
console.log('Crouch controller: speed, stamina, collider, camera, ceiling clearance and input reset pass');

a.controller._onKeyChange('KeyC',true);a.controller.update(1/60);assert(a.controller.isCrouching);a.controller._onKeyChange('KeyC',false);a.controller.update(1/60);assert(a.controller.isCrouching);a.controller._onKeyChange('KeyC',true);a.controller.update(1/60);assert(!a.controller.isCrouching);console.log('Crouch toggle: C persists after release and toggles off');
// Reproduce the reported front-facing avatar and centered-camera overlap.
const cam=a.thirdPersonCamera,view=cam.camera;
cam._cameraCollision=(focus,desired)=>desired;cam.getGroundHeight=()=>-100;
a.controller.crouchBlend=0;a.player.position.set(0,0,0);
for(const yaw of [0,.7,Math.PI/2,Math.PI,-1.4]){
 cam.yaw=yaw;cam.modeIndex=1;cam.pitch=.2;cam.isLookingBack=false;cam.update(1/60);a.player.updateMatrixWorld(true);view.updateMatrixWorld(true);
 const facing=new THREE.Vector3(0,0,1).applyQuaternion(a.mainAvatar.group.getWorldQuaternion(new THREE.Quaternion()));
 const viewing=view.getWorldDirection(new THREE.Vector3());facing.y=0;viewing.y=0;facing.normalize();viewing.normalize();
 assert(facing.dot(viewing)>.999,'Avatar must face away from camera and toward the crosshair for every yaw');
 const screen=a.player.position.clone().add(new THREE.Vector3(0,1.2,0)).project(view);
 assert(screen.x<-.08,'Shoulder camera must put the avatar to the left of the central crosshair');
 cam.modeIndex=3;cam.update(1/60);view.updateMatrixWorld(true);const firstView=view.getWorldDirection(new THREE.Vector3());firstView.y=0;firstView.normalize();assert(facing.dot(firstView)>.999,'First-person view must preserve the third-person facing direction');
}
console.log('TPS camera: correct back view, shoulder separation, all yaw angles and first-person direction pass');

// Exercise the real pistol handler against a bot and then the same bot behind cover.
a.forestAudio.init=()=>{};a.forestAudio.playShoot=()=>{};a.forestAudio.playHit=()=>{};
const trainingBot=a.combatBots.bots[0];a.combatBots.bots.forEach(b=>b.group.visible=false);
trainingBot.group.visible=true;trainingBot.alive=true;trainingBot.health=90;trainingBot.group.position.set(0,0,-8);trainingBot.group.rotation.y=0;
a.player.position.set(0,0,0);a.player.rotation.y=Math.PI;view.position.set(0,1.25,0);view.lookAt(0,1.25,-8);view.updateMatrixWorld(true);a.scene.updateMatrixWorld(true);
a.pistolWeapon.equip();a.pistolWeapon.spread=0;a.pistolWeapon.fireCooldown=0;const beforeHits=a.getStats().hitCount;
a.pistolWeapon.fire();assert.equal(trainingBot.health,60,'Pistol must damage the red bot');assert.equal(a.getStats().hitCount,beforeHits+1);
const cover=new THREE.Mesh(new THREE.BoxGeometry(5,4,.3),new THREE.MeshBasicMaterial());cover.position.set(0,2,-4);a.scene.add(cover);a.pistolWeapon.fireCooldown=0;a.pistolWeapon.fire();assert.equal(trainingBot.health,60,'Cover must block pistol damage');assert.equal(a.getStats().hitCount,beforeHits+1,'Walls must not count as enemy hits');
console.log('Pistol integration: red-bot damage, world cover and enemy-only hit counting pass');

// Test the actual player controller and firing gate, not just cover geometry.
a.controller.clearInput();a.player.position.set(0,0,1.2);a.controller.isGrounded=true;
const coverWall={minX:-3,maxX:3,minY:0,maxY:3,minZ:-.5,maxZ:.5};a.houseParkour.solidBoxes=[coverWall];
a.controller._onKeyChange('KeyQ',true);a.controller.update(1/60);assert(a.controller.cover.active,'Q must enter nearby cover');
a.pistolWeapon.fireCooldown=0;const coveredAmmo=a.pistolWeapon.ammo;a.pistolWeapon.fire();assert.equal(a.pistolWeapon.ammo,coveredAmmo,'Protected stance must not fire through a wall');
a.controller.keys.right=true;for(let i=0;i<180;i++)a.controller.update(1/60);a.controller.keys.right=false;
a.controller.keys.aiming=true;for(let i=0;i<40;i++)a.controller.update(1/60);assert(a.controller.cover.isPeeking&&a.controller.cover.canShoot);
cam.modeIndex=3;cam.update(1/60);assert(a.mainAvatar.group.visible,'Cover must remain readable in third person even with first-person mode selected');
a.controller.keys.aiming=false;for(let i=0;i<40;i++)a.controller.update(1/60);assert(!a.controller.cover.canShoot);assert(a.player.position.x<2.6);
a.controller._onKeyChange('KeyQ',true);assert(!a.controller.cover.active);
a.player.position.set(0,0,1.2);a.houseParkour.solidBoxes=[{...coverWall,maxY:1.3}];a.controller._onKeyChange('KeyQ',true);for(let i=0;i<50;i++)a.controller.update(1/60);assert(a.controller.isCrouching,'Low cover must automatically crouch');
a.controller._onKeyChange('ControlLeft',true);a.controller.keys.aiming=true;for(let i=0;i<50;i++)a.controller.update(1/60);assert(!a.controller.isCrouching,'Peeking above low cover must stand to expose the weapon');
a.combatBots.damagePlayer(1000);assert(!a.controller.cover.active,'Respawn must exit cover');
console.log('Cover integration: Q, lateral movement, fire gate, low-cover crouch, third-person camera, peek/retract and respawn pass');
