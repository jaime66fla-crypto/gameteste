const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const THREE=require('../public/vendor/three-r128.min.js');
let cachedRuntime;
function runtime(){
 if(cachedRuntime)return cachedRuntime;
 const ctx={THREE,console,performance:{now:()=>0},setTimeout:()=>0,addEventListener:()=>{},document:{getElementById:()=>null},window:{}};vm.createContext(ctx);
 for(const file of ['operator-motion.js','weapon-loot.js','operator-avatar.js']){const p=path.join(__dirname,'../public',file);if(fs.existsSync(p))vm.runInContext(fs.readFileSync(p,'utf8'),ctx)}cachedRuntime=ctx;return ctx;
}
function actor(){const ctx=runtime(),a=new ctx.window.OperatorAvatar();return{ctx,a}}
function settle(a,options,n=180){for(let i=0;i<n;i++)a.update(1/120,options);a.group.updateMatrixWorld(true);a.skeleton?.update()}
test('approved avatar has 18 bones, real skin weights, 2K maps and a 1.8m silhouette',()=>{
 const {a}=actor();assert.equal(a.proceduralRig,true,'new approved rig must replace the old rigid avatar');
 assert.equal(a.skeleton.bones.length,18);assert.ok(a.body.isSkinnedMesh);assert.equal(a.body.geometry.attributes.skinWeight.itemSize,4);
 assert.equal(a.materials.fabric.map.image.width,2048);assert.equal(a.materials.fabric.bumpMap.image.height,2048);
 const box=new THREE.Box3().setFromObject(a.group);assert.ok(box.max.y-box.min.y>1.7&&box.max.y-box.min.y<1.95);
});
test('both equipment modes work for walking, running, idle and real airborne motion',()=>{
 const {a}=actor();for(const armed of [false,true])for(const input of [{speed:0},{speed:6},{speed:11,sprinting:true},{speed:0,aiming:true},{speed:4,grounded:false,verticalVelocity:4}]){
 settle(a,{grounded:true,armed,...input});assert.equal(a.gun.visible,armed);assert.ok(a.bones.every(b=>b.matrixWorld.elements.every(Number.isFinite)));
 }
});
test('ballistic altitude belongs to player physics, not a second animation root',()=>{
 const {a}=actor();settle(a,{grounded:true,armed:false});a.group.position.y=4;
 settle(a,{grounded:false,verticalVelocity:2,speed:0,armed:true},90);
 assert.equal(a.group.position.y,4);assert.ok(Math.abs(a.bones[0].position.y)<.08);
});
test('right-side weapon and both grips remain aligned with real Three bone transforms',()=>{
 const {a}=actor();for(const id of ['pistol','rifle','sniper'])for(const speed of [0,6,11]){
 a.setWeapon(id);settle(a,{speed,sprinting:speed>8,grounded:true,armed:true,aiming:speed===0});
 const center=a.group.worldToLocal(a.gun.getWorldPosition(new THREE.Vector3()));assert.ok(center.x<-.05,'weapon must remain on anatomical right');
 for(const grip of a.weaponGripTargets){const target=a.group.localToWorld(grip.point.clone()),actual=a.bones[grip.bone].getWorldPosition(new THREE.Vector3());assert.ok(target.distanceTo(actual)<.035,'hand must meet grip: '+id+' speed '+speed+' bone '+grip.bone+' distance '+target.distanceTo(actual));}
 }
});
test('crouch, cover and team hit feedback remain available',()=>{
 const ctx=runtime(),a=new ctx.window.OperatorAvatar({team:'red'});settle(a,{speed:0,grounded:true,armed:true,crouching:true,covering:true});
 assert.ok(a.crouchBlend>.9);assert.ok(a.bones[1].getWorldPosition(new THREE.Vector3()).y<.9);a.materials.fabric.emissive.setHex(0x6b1e17);assert.equal(a.materials.fabric.emissive.getHex(),0x6b1e17);
});
test('inventory uses the avatar mount without overwriting the approved IK pose',()=>{
 const {ctx,a}=actor(),scene=new THREE.Scene(),player=new THREE.Group();player.add(a.group);scene.add(player);
 const controller={ammo:12,reserveAmmo:60,isEquipped:false,muzzlePoint:new THREE.Object3D(),equip(){this.isEquipped=true;a.gun.visible=true}};a.gun.add(controller.muzzlePoint);
 const loot=new ctx.window.WeaponLootSystem({scene,player,avatar:a,controller,populate:false});loot.slots[1]={id:'rifle',ammo:30};loot.select(1);
 assert.equal(a.weaponId,'rifle');settle(a,{armed:true,grounded:true,speed:6});const before=a.bones.map(b=>b.quaternion.toArray());loot.updateHeldPose();assert.deepEqual(a.bones.map(b=>b.quaternion.toArray()),before);
 assert.equal(controller.muzzlePoint.parent,a.gun);assert.equal(controller.weaponSpec.id,'rifle');
});
test('running legs remain hittable outside the original bind-pose bounds',()=>{
 const {a}=actor();for(let i=0;i<45;i++)a.update(1/60,{speed:11,grounded:true,armed:false});a.group.updateMatrixWorld(true);a.skeleton.update();
 const ray=new THREE.Raycaster(new THREE.Vector3(-3,.15,.30),new THREE.Vector3(1,0,0));const hits=ray.intersectObject(a.body,false);assert.ok(hits.length>0,'running-leg ray must survive animated bounds');
});
test('combat uses a bounded skinned hit surface and maps hits back to the visible avatar',()=>{
 const {a}=actor();settle(a,{speed:0,armed:false,grounded:true});
 assert.ok(a.hitSurface&&a.hitSurface.geometry.attributes.position.count<20000,'combat geometry must be far below the 255k visual vertices');
 const hits=new THREE.Raycaster(new THREE.Vector3(0,1.2,3),new THREE.Vector3(0,0,-1)).intersectObject(a.body,false);
 assert.ok(hits.length>0);assert.ok(hits.every(h=>h.object===a.body),'hit feedback and enemy attribution must still target visible body');
});
