const fs=require('fs'),vm=require('vm'),assert=require('assert');const THREE=require(process.cwd()+'/public/vendor/three-r128.min.js');
THREE.WebGLRenderer=class{constructor(){this.shadowMap={}}setPixelRatio(){}setSize(){}render(){}};
const ctx2d=new Proxy({createLinearGradient:()=>({addColorStop(){}}),createRadialGradient:()=>({addColorStop(){}}),measureText:()=>({width:30})},{get:(o,k)=>o[k]||(()=>{})});
const els=new Map();function element(){return {style:{},setAttribute(){},classList:{add(){},remove(){},contains(){return false}},addEventListener(){},appendChild(){},getContext:()=>ctx2d,getBoundingClientRect:()=>({left:0,top:0,width:1280,height:720})};}function el(id){if(!els.has(id))els.set(id,element());return els.get(id)}
const context={THREE,window:{addEventListener(){}},document:{getElementById:el,createElement:element,addEventListener(){}},addEventListener(){},devicePixelRatio:1,innerWidth:1280,innerHeight:720,requestAnimationFrame(){},console,setTimeout(){},clearTimeout(){},performance:{now:()=>1000},location:{host:'game.test',protocol:'https:'},WebSocket:class{},localStorage:{getItem(){return null},setItem(){}}};
vm.createContext(context);vm.runInContext(fs.readFileSync('public/operator-avatar.js','utf8'),context);vm.runInContext(fs.readFileSync('public/full3d.js','utf8')+'\nglobalThis.testApi={mainAvatar,pistolWeapon,scene,player,controller,houseParkour,thirdPersonCamera,frame:loop,start:()=>gameStarted=true};',context);
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
