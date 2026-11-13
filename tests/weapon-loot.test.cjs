const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const THREE=require('../public/vendor/three-r128.min.js'),context={THREE,window:{}};
assert(fs.existsSync('public/weapon-loot.js'),'Weapon and loot module must exist');
vm.createContext(context);for(const file of ['public/operator-motion.js','public/operator-avatar.js','public/weapon-loot.js'])vm.runInContext(fs.readFileSync(file,'utf8'),context);
const Loot=context.window.WeaponLootSystem,scene=new THREE.Scene(),player=new THREE.Group(),avatar=new context.window.OperatorAvatar();player.add(avatar.group);scene.add(player);
const gun={ammo:12,reserveAmmo:60,isEquipped:false,isReloading:false,fireCooldown:0,muzzlePoint:new THREE.Object3D(),equip(){this.isEquipped=true;this.isReloading=false}};avatar.gun.add(gun.muzzlePoint);
const loot=new Loot({scene,player,avatar,controller:gun,terrainHeight:()=>0,solidBoxes:()=>[],random:()=>.5,populate:false});
assert.equal(loot.slots.length,2);assert.equal(loot.slots[0].id,'pistol');assert.equal(loot.slots[1],null);
const smg=loot.addWeapon('smg',new THREE.Vector3(.5,0,0));assert(loot.pickup(smg));assert.equal(loot.activeSlot,1);assert.equal(gun.magSize,24);assert.equal(gun.weaponSpec.auto,true);
gun.ammo=7;gun.reserveAmmo=37;gun.isReloading=true;loot.select(0);assert(!gun.isReloading);assert.equal(gun.ammo,12);assert.equal(gun.reserveAmmo,37,'Pistol/SMG share light reserves');loot.select(1);assert.equal(gun.ammo,7);
const rifle=loot.addWeapon('rifle',new THREE.Vector3(.6,0,0));assert(loot.pickup(rifle));assert.equal(loot.slots[1].id,'rifle');const dropped=loot.items.find(i=>i.kind==='weapon'&&i.id==='smg');assert(dropped);assert.equal(dropped.ammo,7);assert.equal(dropped.bonusAmmo,0);
assert(loot.pickup(dropped));assert.equal(gun.ammo,7);assert.equal(gun.reserveAmmo,37,'Dropped weapon must not mint bonus ammo');
const shells=loot.addAmmo('shells',500,new THREE.Vector3(.5,0,0));loot.pickup(shells);assert.equal(loot.reserves.shells,48);assert.equal(loot.reserves.light,37);assert(!loot.select(2));
const far=loot.addAmmo('rifle',30,new THREE.Vector3(8,0,0));assert(!loot.pickup(far),'Far loot must not be picked up');
const wall={minX:-1,maxX:1,minY:0,maxY:3,minZ:-.2,maxZ:.2};const scene2=new THREE.Scene(),p2=new THREE.Group(),av2=new context.window.OperatorAvatar();p2.add(av2.group);p2.position.z=1;scene2.add(p2);
const l2=new Loot({scene:scene2,player:p2,avatar:av2,controller:{...gun,muzzlePoint:new THREE.Object3D()},terrainHeight:()=>0,solidBoxes:()=>[wall],populate:false});
const through=l2.addAmmo('light',10,new THREE.Vector3(0,0,-.7));assert(through);assert(!l2.pickup(through),'Loot cannot be collected through a wall');assert(!l2.isSafePoint(new THREE.Vector3(0,0,0)));
for(const id of ['pistol','smg','rifle','shotgun'])assert(Loot.createModel(id).children.length>2);
console.log('Weapons/loot: two slots, magazines, reserve types/caps, reload cancellation, replacement drops, no duplication, reach/cover and models pass');

for(const id of ['smg','rifle','shotgun']){
 loot.slots[1]={id,ammo:Loot.DEFINITIONS[id].magSize};loot.activeSlot=1;loot.applyActive(true);
 for(let i=0;i<100;i++){avatar.update(1/60,{armed:true});loot.updateHeldPose();}
 avatar.group.updateWorldMatrix(true,true);
 for(const grip of avatar.weaponGripTargets){const target=avatar.group.localToWorld(grip.point.clone());assert(avatar.bones[grip.bone].getWorldPosition(new THREE.Vector3()).distanceTo(target)<.035,'Hands must follow the approved weapon grip targets');}
 avatar.group.traverse(o=>assert(o.matrixWorld.elements.every(Number.isFinite)));
}
console.log('Long weapons: support-hand contact, forward barrel and finite transforms pass');
const airborneDrop=loot.safeDrop(new THREE.Vector3(0,2,0));assert(airborneDrop);assert.equal(airborneDrop.y,0,'Discarded weapons must land rather than retain jump height');
const raisedScene=new THREE.Scene(),raisedPlayer=new THREE.Group(),raisedAvatar=new context.window.OperatorAvatar();raisedPlayer.add(raisedAvatar.group);raisedScene.add(raisedPlayer);const platform=new THREE.Mesh(new THREE.BoxGeometry(2,1,2),new THREE.MeshBasicMaterial());platform.position.set(.9,.5,0);raisedScene.add(platform);
const raised=new Loot({scene:raisedScene,player:raisedPlayer,avatar:raisedAvatar,controller:{...gun,muzzlePoint:new THREE.Object3D()},terrainHeight:()=>0,solidBoxes:()=>[],populate:false});assert.equal(raised.safeDrop(new THREE.Vector3(0,2,0)).y,1,'A real platform top must support dropped weapons');
console.log('Dropped weapons resolve ground and platform support surfaces');
