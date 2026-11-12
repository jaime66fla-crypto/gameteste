/* Two-weapon floor-loot inventory and original stylized weapon models. */
(() => {
'use strict';
const DEFINITIONS=Object.freeze({
 pistol:{id:'pistol',name:'Pistola',ammoType:'light',magSize:12,damage:30,fireRate:60/340,reloadTime:1.15,spread:.0025,pellets:1,auto:false,range:65,muzzleZ:.2,color:0xd6c49a},
 smg:{id:'smg',name:'Submetralhadora',ammoType:'light',magSize:24,damage:18,fireRate:.095,reloadTime:1.7,spread:.009,pellets:1,auto:true,range:45,muzzleZ:.29,color:0x80c4de},
 rifle:{id:'rifle',name:'Rifle de assalto',ammoType:'rifle',magSize:30,damage:28,fireRate:.14,reloadTime:2,spread:.004,pellets:1,auto:true,range:85,muzzleZ:.47,color:0x91c388},
 shotgun:{id:'shotgun',name:'Escopeta',ammoType:'shells',magSize:6,damage:11,fireRate:.85,reloadTime:2.2,spread:.05,pellets:6,auto:false,range:28,muzzleZ:.5,color:0xe8b17f},
 sniper:{id:'sniper',name:'Sniper',ammoType:'rifle',magSize:5,damage:95,fireRate:1.05,reloadTime:2.7,spread:.0006,pellets:1,auto:false,range:220,muzzleZ:.68,color:0xc8d2a0}
});
const AMMO_NAMES={light:'Munição leve',rifle:'Munição de rifle',shells:'Cartuchos'};
const CAPS={light:240,rifle:180,shells:48};
function createModel(id){
 const group=new THREE.Group(),dark=new THREE.MeshStandardMaterial({color:0x232c30,roughness:.6,metalness:.35}),steel=new THREE.MeshStandardMaterial({color:0x59636a,roughness:.35,metalness:.75}),grip=new THREE.MeshStandardMaterial({color:id==='shotgun'?0x77583d:0x3c4845,roughness:.9});
 function box(w,h,d,material,x,y,z,angle=0){const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),material);m.position.set(x,y,z);m.rotation.x=angle;m.castShadow=true;group.add(m);return m;}
 if(id==='pistol'){
  box(.039,.049,.175,steel,0,.035,.037);box(.034,.034,.16,dark,0,-.005,.03);box(.035,.087,.045,grip,0,-.051,-.018,-.2);
  box(.05,.006,.043,dark,0,-.043,.025);box(.008,.008,.012,dark,0,.064,.103);
 }else{
  box(.055,.065,id==='smg'?.18:.23,dark,0,.02,.055);box(.041,.085,.05,grip,0,-.047,-.012,-.15);
  box(.045,.055,.14,grip,-.07,.085,-.12);box(.062,.1,.025,dark,-.07,.105,-.2);
  if(id==='shotgun'){
   box(.035,.035,.39,steel,0,.035,.285);box(.025,.025,.33,dark,0,-.007,.27);box(.07,.065,.12,grip,0,-.004,.21);
  }else if(id==='sniper'){
   box(.045,.055,.36,dark,0,.025,.12);box(.026,.026,.48,steel,0,.04,.47);box(.055,.065,.18,grip,0,.005,-.14);box(.04,.09,.055,grip,0,-.055,-.015,-.12);
   const scope=box(.11,.11,.27,dark,0,.13,.07);scope.geometry.dispose();scope.geometry=new THREE.CylinderGeometry(.055,.055,.27,14);scope.rotation.x=Math.PI/2;
   box(.018,.055,.02,steel,0,.09,.0);box(.018,.055,.02,steel,0,.09,.14);
  }else{
   box(.05,id==='smg'?.135:.12,.065,grip,0,-.062,.06,-.16);
   box(.06,.065,id==='smg'?.09:.14,grip,0,.02,id==='smg'?.16:.23);
   box(.023,.023,id==='smg'?.11:.18,steel,0,.035,id==='smg'?.23:.38);
   box(.035,.012,.19,steel,0,.062,.06);box(.014,.025,.02,dark,0,.075,.11);

   // Compact holographic sight physically mounted on SMG/rifle.
   // The HUD supplies the luminous reticle; this 3D housing makes the sight part of the weapon.
   const sightMat=new THREE.MeshStandardMaterial({color:0x171c1d,roughness:.42,metalness:.55});
   const glassMat=new THREE.MeshStandardMaterial({color:0x8fb8ad,transparent:true,opacity:.18,roughness:.08,metalness:.05,side:THREE.DoubleSide});
   const sy=.135,sz=id==='smg'?.085:.12;
   box(.065,.012,.055,sightMat,0,sy-.042,sz);
   box(.012,.085,.018,sightMat,-.033,sy,sz);
   box(.012,.085,.018,sightMat,.033,sy,sz);
   box(.065,.012,.018,sightMat,0,sy+.043,sz);
   const glass=box(.052,.062,.004,glassMat,0,sy,sz+.004);
   glass.castShadow=false;
  }
 }
 group.name='Weapon_'+id;return group;
}
function asBox(b){return b.isBox3?b:new THREE.Box3(new THREE.Vector3(b.minX,b.minY,b.minZ),new THREE.Vector3(b.maxX,b.maxY,b.maxZ));}
function rotateJoint(root,joint,tip,target){
 root.updateWorldMatrix(true,true);
 const origin=joint.getWorldPosition(new THREE.Vector3()),from=tip.getWorldPosition(new THREE.Vector3()).sub(origin).normalize(),to=target.clone().sub(origin).normalize();
 const world=joint.getWorldQuaternion(new THREE.Quaternion()).premultiply(new THREE.Quaternion().setFromUnitVectors(from,to));
 joint.quaternion.copy(joint.parent.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(world));root.updateWorldMatrix(true,true);
}
function solveArm(root,arm,target,pole){
 const upper=arm.shoulder,lower=arm.elbow,hand=arm.hand;root.updateWorldMatrix(true,true);
 const shoulder=upper.getWorldPosition(new THREE.Vector3()),elbow=lower.getWorldPosition(new THREE.Vector3()),wrist=hand.getWorldPosition(new THREE.Vector3());
 const a=shoulder.distanceTo(elbow),b=elbow.distanceTo(wrist),direction=target.clone().sub(shoulder);
 const distance=THREE.MathUtils.clamp(direction.length(),Math.abs(a-b)+.001,a+b-.001);direction.normalize();
 const bend=pole.clone().sub(shoulder);bend.addScaledVector(direction,-bend.dot(direction)).normalize();
 const along=(a*a-b*b+distance*distance)/(2*distance),height=Math.sqrt(Math.max(0,a*a-along*along));
 rotateJoint(root,upper,lower,shoulder.clone().addScaledVector(direction,along).addScaledVector(bend,height));
 rotateJoint(root,lower,hand,shoulder.clone().addScaledVector(direction,distance));
}
class WeaponLootSystem {
 constructor({scene,player,avatar,controller,terrainHeight=()=>0,solidBoxes=()=>[],random=Math.random,populate=true}){
  Object.assign(this,{scene,player,avatar,controller,terrainHeight,solidBoxes,random});
  this.slots=[{id:'pistol',ammo:12},null];this.reserves={light:60,rifle:0,shells:0};this.activeSlot=0;
  this.items=[];this.heldModels=new Map();this.time=0;this.nearest=null;this.message='';this.messageTime=0;
  scene.updateMatrixWorld(true);this.staticBoxes=[];this.staticMeshes=[];
  scene.traverse(o=>{if(!o.isMesh||o.geometry?.type==='PlaneGeometry')return;for(let p=o;p;p=p.parent)if(p===player||p.userData.ignoreCombat)return;this.staticBoxes.push(new THREE.Box3().setFromObject(o));this.staticMeshes.push(o);});
  controller.loot=this;
  for(const child of avatar.gun.children)if(child!==avatar.flash&&child!==controller.muzzlePoint)child.visible=false;
  this.applyActive(false);
  if(populate)this.populate();
 }
 get definition(){return DEFINITIONS[this.slots[this.activeSlot].id];}
 boxes(){return this.staticBoxes.concat(this.solidBoxes().map(asBox));}
 isSafePoint(p,radius=.65){
  return Number.isFinite(p.x)&&Number.isFinite(p.y)&&Number.isFinite(p.z)&&!this.boxes().some(b=>p.x+radius>b.min.x&&p.x-radius<b.max.x&&p.z+radius>b.min.z&&p.z-radius<b.max.z&&b.max.y>p.y+.08&&b.min.y<p.y+1);
 }
 surfaceBelow(x,z,ceiling){
  const ground=this.terrainHeight(x,z);
  const ray=new THREE.Raycaster(new THREE.Vector3(x,ceiling+.15,z),new THREE.Vector3(0,-1,0),0,Math.max(.2,ceiling-ground+1));
  const hit=ray.intersectObjects(this.staticMeshes,false).find(h=>h.point.y>=ground-.03&&h.point.y<=ceiling+.15);
  return hit?Math.max(ground,hit.point.y):ground;
 }
 safeDrop(position){
  for(const radius of [.9,1.4,2])for(let i=0;i<8;i++){
   const p=new THREE.Vector3(position.x+Math.cos(i*Math.PI/4)*radius,position.y,position.z+Math.sin(i*Math.PI/4)*radius);
   p.y=this.surfaceBelow(p.x,p.z,position.y);
   if(this.isSafePoint(p))return p;
  }
  return null;
 }
 saveActive(){
  const slot=this.slots[this.activeSlot];slot.ammo=this.controller.ammo;
  this.reserves[DEFINITIONS[slot.id].ammoType]=this.controller.reserveAmmo;
 }
 applyActive(equip){
  const spec=this.definition,gun=this.controller;
  this.avatar.setWeapon?.(spec.id);
  Object.assign(gun,{weaponSpec:spec,magSize:spec.magSize,ammo:this.slots[this.activeSlot].ammo,reserveAmmo:this.reserves[spec.ammoType],fireRate:spec.fireRate,reloadTime:spec.reloadTime,spread:spec.spread,isReloading:false,reloadTimer:0,triggerHeld:false});
  let model=this.heldModels.get(spec.id);
  if(!model){model=createModel(spec.id);this.heldModels.set(spec.id,model);this.avatar.gun.add(model);}
  for(const [id,m]of this.heldModels)m.visible=id===spec.id;
  gun.muzzlePoint.position.set(0,.035,spec.muzzleZ);this.avatar.flash.position.z=spec.muzzleZ+.04;
  if(equip){gun.fireCooldown=Math.max(gun.fireCooldown,.18);gun.equip();}
 }
 select(index){
  if(!Number.isInteger(index)||index<0||index>1||!this.slots[index]){this.notify('Espaço de arma vazio');return false;}
  this.saveActive();this.activeSlot=index;this.applyActive(true);return true;
 }
 notify(text){this.message=text;this.messageTime=2;}
 add(kind,id,amount,position,options={}){
  if(kind==='weapon'&&!DEFINITIONS[id]||kind==='ammo'&&!AMMO_NAMES[id])return null;
  if(!this.isSafePoint(position,kind==='weapon'?.65:.16))return null;
  const group=new THREE.Group();group.userData.ignoreCombat=true;group.userData.ignoreCamera=true;
  const spec=kind==='weapon'?DEFINITIONS[id]:null,color=spec?.color||({light:0x80c4de,rifle:0x91c388,shells:0xe8b17f})[id];
  if(spec){const model=createModel(id);model.scale.setScalar(1.3);model.rotation.y=this.random()*Math.PI*2;group.add(model);}
  else{const material=new THREE.MeshStandardMaterial({color,roughness:.9});const box=new THREE.Mesh(new THREE.BoxGeometry(.17,.12,.13),material);group.add(box);}
  const halo=new THREE.Mesh(new THREE.RingGeometry(.24,.29,24),new THREE.MeshBasicMaterial({color,side:THREE.DoubleSide,transparent:true,opacity:.5}));halo.rotation.x=-Math.PI/2;halo.position.y=-.19;group.add(halo);
  const item={kind,id,amount,group,position:position.clone(),ammo:options.ammo??spec?.magSize,bonusAmmo:options.bonusAmmo??spec?.magSize??0,drop:!!options.drop};
  group.position.copy(position).add(new THREE.Vector3(0,.22,0));this.scene.add(group);this.items.push(item);
  if(item.drop){const drops=this.items.filter(i=>i.drop);if(drops.length>32)this.remove(drops[0]);}
  return item;
 }
 addWeapon(id,position,options={}){return this.add('weapon',id,0,position,options);}
 addAmmo(type,amount,position,options={}){return this.add('ammo',type,amount,position,options);}
 remove(item){
  const index=this.items.indexOf(item);if(index<0)return;
  this.items.splice(index,1);this.scene.remove(item.group);
  item.group.traverse(o=>{if(o.isMesh){o.geometry.dispose();o.material.dispose();}});
  if(this.nearest===item)this.nearest=null;
 }
 canReach(item){
  if(!this.items.includes(item)||this.player.position.distanceTo(item.position)>1.8)return false;
  const from=this.player.position.clone().add(new THREE.Vector3(0,this.player.userData.crouching?.85:1.15,0));
  const to=item.position.clone().add(new THREE.Vector3(0,.22,0)),delta=to.sub(from),distance=delta.length();
  if(distance<.001)return true;
  const ray=new THREE.Ray(from,delta.normalize()),hit=new THREE.Vector3();
  return !this.boxes().some(box=>ray.intersectBox(box,hit)&&hit.distanceTo(from)<distance-.08);
 }
 pickup(item=this.nearest){
  if(!item||!this.canReach(item))return false;
  this.saveActive();
  if(item.kind==='ammo'){
   const before=this.reserves[item.id];this.reserves[item.id]=Math.min(CAPS[item.id],before+item.amount);
   if(this.reserves[item.id]===before){this.notify('Reserva de munição cheia');return false;}
   this.controller.reserveAmmo=this.reserves[this.definition.ammoType];
   this.notify(AMMO_NAMES[item.id]+' +'+(this.reserves[item.id]-before));this.remove(item);return true;
  }
  let slot=this.slots.findIndex(s=>!s);if(slot<0)slot=this.activeSlot;
  const previous=this.slots[slot];
  if(previous){
   const p=this.safeDrop(this.player.position);if(!p){this.notify('Sem espaço seguro para trocar a arma');return false;}
   this.addWeapon(previous.id,p,{ammo:previous.ammo,bonusAmmo:0,drop:true});
  }
  const spec=DEFINITIONS[item.id];this.slots[slot]={id:item.id,ammo:item.ammo};
  this.reserves[spec.ammoType]=Math.min(CAPS[spec.ammoType],this.reserves[spec.ammoType]+item.bonusAmmo);
  this.activeSlot=slot;this.remove(item);this.applyActive(true);this.notify(spec.name+' equipada');return true;
 }
 populate(){
  for(const [id,x,z]of [['smg',-2,-1],['rifle',2,-2],['shotgun',0,-5],['pistol',-3,-7],['sniper',4,-8]])this.addWeapon(id,new THREE.Vector3(x,this.terrainHeight(x,z),z));
  const ids=Object.keys(DEFINITIONS),types=Object.keys(AMMO_NAMES);
  for(let n=0;n<22;n++)for(let attempt=0;attempt<100;attempt++){
   const extent=n<4||n>=8&&n<14?62:220;
   const x=(this.random()-.5)*extent,z=(this.random()-.5)*extent,p=new THREE.Vector3(x,this.terrainHeight(x,z),z);
   if(Math.hypot(x,z)<3||!this.isSafePoint(p)||this.items.some(i=>i.position.distanceTo(p)<1.4))continue;
   if(n<8)this.addWeapon(ids[Math.floor(this.random()*ids.length)],p);
   else{const type=types[Math.floor(this.random()*types.length)];this.addAmmo(type,type==='shells'?8:30,p);}
   break;
  }
 }
 dropFromBot(position){
  if(this.random()>.8)return;
  const p=this.safeDrop(position);if(!p)return;
  const types=['light','rifle','shells'],type=types[Math.floor(this.random()*3)];this.addAmmo(type,type==='shells'?6:24,p,{drop:true});
 }
 refillForTraining(){
  this.reserves={light:60,rifle:60,shells:18};for(const slot of this.slots)if(slot)slot.ammo=DEFINITIONS[slot.id].magSize;
  this.applyActive(false);
 }
 updateHeldPose(){
  if(this.avatar.ownsWeaponPose)return;
  if(this.definition.id==='pistol'||!this.controller.isEquipped)return;
  const avatar=this.avatar,root=avatar.group,weight=avatar.aimBlend*(1-avatar.coverBlend);
  if(weight<.001)return;
  const joints=avatar.arms.flatMap(a=>[a.shoulder,a.elbow,a.hand]),before=joints.map(j=>j.quaternion.clone());
  const local=(x,y,z)=>root.localToWorld(new THREE.Vector3(x,y,z)),height=avatar.pelvis.position.y;
  solveArm(root,avatar.arms[1],local(.08,height+.4,.22),local(.44,height+.15,.13));
  const gripWorld=root.getWorldQuaternion(new THREE.Quaternion()).multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI/2,0,0)));
  const right=avatar.rightHand;right.quaternion.copy(right.parent.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(gripWorld));root.updateWorldMatrix(true,true);
  const support=avatar.gun.localToWorld(new THREE.Vector3(-.022,-.01,.13));
  solveArm(root,avatar.arms[0],support,local(-.45,height+.14,.22));
  const left=avatar.leftHand;left.quaternion.copy(left.parent.getWorldQuaternion(new THREE.Quaternion()).invert().multiply(gripWorld));
  for(let i=0;i<joints.length;i++)joints[i].quaternion.copy(before[i].slerp(joints[i].quaternion,weight));
  root.updateWorldMatrix(true,true);
 }
 update(dt){
  this.time+=dt;this.messageTime=Math.max(0,this.messageTime-dt);this.saveActive();this.nearest=null;let distance=Infinity;
  for(const item of this.items){
   item.group.position.y=item.position.y+.22+Math.sin(this.time*2+item.position.x)*.025;
   const d=this.player.position.distanceTo(item.position);if(d<distance&&d<=1.8&&this.canReach(item)){distance=d;this.nearest=item;}
  }
 }
 get prompt(){
  if(this.nearest){
   if(this.nearest.kind==='weapon'&&this.slots.every(Boolean))return 'E · trocar '+this.definition.name+' por '+DEFINITIONS[this.nearest.id].name;
   return 'E · pegar '+(this.nearest.kind==='weapon'?DEFINITIONS[this.nearest.id].name:AMMO_NAMES[this.nearest.id]+' ×'+this.nearest.amount);
  }
  return this.messageTime>0?this.message:'';
 }
}
WeaponLootSystem.DEFINITIONS=DEFINITIONS;WeaponLootSystem.AMMO_NAMES=AMMO_NAMES;WeaponLootSystem.createModel=createModel;
window.WeaponLootSystem=WeaponLootSystem;
})();

