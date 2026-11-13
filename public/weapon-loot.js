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
const ACCESSORIES=Object.freeze({
 optic:{name:'Mira tática',slot:'Mira',color:0x74bade},
 suppressor:{name:'Silenciador',slot:'Bocal',color:0x566672},
 extended:{name:'Carregador estendido',slot:'Pente',color:0xc7a85b},
 grip:{name:'Empunhadura',slot:'Empunhadura',color:0x8cc49b},
 stock:{name:'Coronha tática',slot:'Coronha',color:0x87929a}
});
function accessoryAllowed(weaponId,id){
 return ACCESSORIES[id]&&!(weaponId==='pistol'&&(id==='grip'||id==='stock'))&&!(weaponId==='shotgun'&&id==='extended');
}
function accessoryStats(spec,attachments={}){
 const extended=!!attachments.extended&&accessoryAllowed(spec.id,'extended');
 const grip=!!attachments.grip&&accessoryAllowed(spec.id,'grip');
 const stock=!!attachments.stock&&accessoryAllowed(spec.id,'stock');
 const optic=!!attachments.optic;
 const suppressor=!!attachments.suppressor;
 return {
  magSize:spec.magSize+(extended?Math.max(4,Math.floor(spec.magSize*.40)):0),
  spreadMultiplier:(grip?.82:1)*(optic?.88:1)*(stock?.96:1),
  recoilMultiplier:(grip?.80:1)*(stock?.84:1),
  soundMultiplier:suppressor?.40:1,
  muzzleFlashMultiplier:suppressor?.18:1,
  adsMultiplier:(optic?.88:1)*(stock?.96:1),
  suppressor,grip,stock,optic,extended
 };
}
function applyAccessoryVisuals(model,id,attachments={}){
 if(!model)return;
 let rig=model.userData.accessoryRig;
 if(!rig){
  rig=new THREE.Group();rig.name='WeaponAccessories';rig.userData.ignoreCombat=true;rig.userData.ignoreCamera=true;
  model.add(rig);model.userData.accessoryRig=rig;
  const dark=new THREE.MeshStandardMaterial({color:0x20282b,metalness:.55,roughness:.4});
  const glass=new THREE.MeshStandardMaterial({color:0x80c9cb,emissive:0x113e49,metalness:.1,roughness:.2});
  const add=(key,w,h,d,x,y,z,mat=dark)=>{
   const mesh=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),mat);
   mesh.position.set(x,y,z);mesh.castShadow=true;rig.add(mesh);mesh.userData.accessoryKey=key;return mesh;
  };
  const muzzle=DEFINITIONS[id].muzzleZ;
  add('suppressor',.047,.047,id==='pistol'?.14:.24,0,.035,muzzle+.10);
  add('extended',.055,.065,.07,0,id==='pistol'?-.15:-.16,id==='pistol'?-.020:.045);
  add('grip',.035,.11,.043,0,-.089,Math.max(.14,muzzle*.55));
  add('optic',.072,.077,.055,0,id==='pistol'?.098:.175,id==='pistol'?.020:.06);
  add('optic',.048,.033,.007,0,id==='pistol'?.11:.18,id==='pistol'?.05:.09,glass);
  if(id!=='pistol'){
   add('stock',.07,.085,.16,0,.01,-.17);
   add('stock',.045,.055,.12,0,.025,-.29);
  }
 }
 for(const mesh of rig.children)mesh.visible=!!attachments[mesh.userData.accessoryKey]&&accessoryAllowed(id,mesh.userData.accessoryKey);
}
function createModel(id){
 const group=new THREE.Group(),dark=new THREE.MeshStandardMaterial({color:0x232c30,roughness:.6,metalness:.35}),steel=new THREE.MeshStandardMaterial({color:0x59636a,roughness:.35,metalness:.75}),grip=new THREE.MeshStandardMaterial({color:id==='shotgun'?0x77583d:0x3c4845,roughness:.9});
 function box(w,h,d,material,x,y,z,angle=0){const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),material);m.position.set(x,y,z);m.rotation.x=angle;m.castShadow=true;group.add(m);return m;}
 const parts={};
 function movingBox(key,w,h,d,material,x,y,z,angle=0){
  const m=box(w,h,d,material,x,y,z,angle);
  parts[key]=m;return m;
 }
 if(id==='pistol'){
  movingBox('slide',.039,.049,.175,steel,0,.035,.037);box(.034,.034,.16,dark,0,-.005,.03);box(.035,.087,.045,grip,0,-.051,-.018,-.2);
  box(.05,.006,.043,dark,0,-.043,.025);box(.008,.008,.012,dark,0,.064,.103);
 }else{
  box(.055,.065,id==='smg'?.18:.23,dark,0,.02,.055);box(.041,.085,.05,grip,0,-.047,-.012,-.15);
  box(.045,.055,.14,grip,-.07,.085,-.12);box(.062,.1,.025,dark,-.07,.105,-.2);
  if(id==='shotgun'){
   box(.035,.035,.39,steel,0,.035,.285);box(.025,.025,.33,dark,0,-.007,.27);movingBox('pump',.07,.065,.12,grip,0,-.004,.21);
  }else if(id==='sniper'){
   box(.045,.055,.36,dark,0,.025,.12);box(.026,.026,.48,steel,0,.04,.47);box(.055,.065,.18,grip,0,.005,-.14);movingBox('magazine',.04,.09,.055,grip,0,-.055,-.015,-.12);
   const scope=box(.11,.11,.27,dark,0,.13,.07);scope.geometry.dispose();scope.geometry=new THREE.CylinderGeometry(.055,.055,.27,14);scope.rotation.x=Math.PI/2;
   box(.018,.055,.02,steel,0,.09,.0);box(.018,.055,.02,steel,0,.09,.14);
  }else{
   movingBox('magazine',.05,id==='smg'?.135:.12,.065,grip,0,-.062,.06,-.16);
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
 // Readable mechanical details at third-person distance; preserve original grip coordinates.
 const trim=new THREE.MeshStandardMaterial({color:0x111719,metalness:.58,roughness:.43});
 const highlight=new THREE.MeshStandardMaterial({color:0x869096,metalness:.8,roughness:.3});
 const rubber=new THREE.MeshStandardMaterial({color:0x283231,roughness:.96});
 function tube(radius,length,x,y,z,material=steel){
  const mesh=new THREE.Mesh(new THREE.CylinderGeometry(radius,radius,length,10),material);
  mesh.rotation.x=Math.PI/2;mesh.position.set(x,y,z);mesh.castShadow=true;group.add(mesh);return mesh;
 }
 // Muzzle rim and concentric bore show which end of the weapon is forward (+Z).
 const tip=DEFINITIONS[id].muzzleZ;
 tube(id==='shotgun'?.030:.019,.028,0,.035,tip-.012,highlight);
 tube(id==='shotgun'?.018:.010,.030,0,.035,tip+.005,trim);
 if(id==='pistol'){
  // Slide serrations, ejection port, magazine floor and separate rear sight.
  for(let i=0;i<4;i++)box(.043,.013,.006,trim,0,.053,-.020+i*.018);
  movingBox('ejectionPort',.028,.006,.034,trim,.006,.060,.058);
  movingBox('magazine',.045,.010,.037,trim,0,-.104,-.020);
  box(.031,.008,.011,highlight,0,.064,-.038);
 }else{
  // Receiver pins, magazine base, rail sections and sling anchor.
  box(.012,.010,.017,highlight,.031,.018,.004);
  box(.012,.010,.017,highlight,-.031,.018,.004);
  box(.062,.010,.026,trim,0,-.102,-.023);
  for(let i=0;i<4;i++)box(.041,.007,.010,highlight,0,.071,.012+i*.035);
  box(.009,.035,.014,trim,-.062,.020,-.090);
  if(id==='shotgun'){
   // Pump ribs and brass-colored shell loading gate.
   for(let i=0;i<4;i++)box(.073,.007,.012,trim,0,.035,.155+i*.027);
   box(.039,.009,.057,highlight,0,-.033,.085);
  }else if(id==='sniper'){
   // Scope adjustment turrets, bolt handle and barrel band.
   tube(.025,.046,0,.19,.064,trim);
   movingBox('bolt',.052,.020,.013,highlight,.041,.038,-.003);
   box(.015,.047,.018,trim,.059,.002,-.003);
   box(.057,.022,.024,trim,0,.040,.39);
  }else{
   // Charging handle and grooved handguard.
   movingBox('bolt',.042,.013,.020,highlight,-.014,.073,-.033);
   for(let i=0;i<3;i++)box(.059,.008,.012,trim,0,.003,.155+i*.026);
   box(.065,.010,.020,rubber,0,-.014,.19);
  }
 }
 // Per-model mechanism controls. Models used as loot remain in their rest pose.
 const rest=Object.fromEntries(Object.entries(parts).map(([key,mesh])=>[key,mesh.position.clone()]));
 group.userData.weaponMechanics={id,parts,rest};
 group.name='Weapon_'+id;
 if(window.GameSkins)window.GameSkins.paintWeapon(group,id);
 return group;
}
function animateMechanics(model,{reload=0,reloading=false,recoil=0,shot=0}={}){
 const setup=model?.userData?.weaponMechanics;
 if(!setup)return;
 const {id,parts,rest}=setup;
 for(const [key,part] of Object.entries(parts))part.position.copy(rest[key]);
 const t=THREE.MathUtils.clamp(reload,0,1);
 const impulse=THREE.MathUtils.clamp(shot,0,1);
 // Magazine drop / insertion / return, driven by the real reload progress.
 const magOut=reloading?THREE.MathUtils.smoothstep(t,.08,.29):0;
 const magIn=reloading?1-THREE.MathUtils.smoothstep(t,.43,.72):0;
 const magTravel=magOut*magIn;
 if(parts.magazine)parts.magazine.position.y-=.07*magTravel;
 if(parts.magazine)parts.magazine.position.z-=.025*magTravel;
 if(parts.slide){
  const rack=reloading?Math.max(0,1-Math.abs(t-.82)/.13):0;
  parts.slide.position.z-=.055*Math.max(impulse,rack);
 }
 if(parts.ejectionPort)parts.ejectionPort.position.z-=.04*impulse;
 if(parts.bolt){
  const bolt=reloading?Math.max(0,1-Math.abs(t-(id==='sniper'?.76:.83))/.14):0;
  parts.bolt.position.z-=.08*Math.max(bolt,impulse*.6);
 }
 if(parts.pump){
  const pump=reloading?Math.pow(Math.sin(t*Math.PI*3),2)*.04:0;
  parts.pump.position.z-=Math.max(pump,impulse*.06);
 }
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
  this.slots=[{id:'pistol',ammo:12,attachments:{}},null];this.reserves={light:60,rifle:0,shells:0};this.activeSlot=0;
  this.items=[];this.heldModels=new Map();this.time=0;this.nearest=null;this.message='';this.messageTime=0;
  scene.updateMatrixWorld(true);this.staticBoxes=[];this.staticMeshes=[];
  scene.traverse(o=>{if(!o.isMesh||o.geometry?.type==='PlaneGeometry')return;for(let p=o;p;p=p.parent)if(p===player||p.userData.ignoreCombat)return;this.staticBoxes.push(new THREE.Box3().setFromObject(o));this.staticMeshes.push(o);});
  controller.loot=this;
  for(const child of avatar.gun.children)if(child!==avatar.flash&&child!==controller.muzzlePoint)child.visible=false;
  this.applyActive(false);
  if(populate)this.populate();
 }
 get definition(){return DEFINITIONS[this.slots[this.activeSlot]?.id]||DEFINITIONS.pistol;}
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
  const slot=this.slots[this.activeSlot];if(!slot)return;slot.ammo=this.controller.ammo;slot.attachments=slot.attachments||{};
  this.reserves[DEFINITIONS[slot.id].ammoType]=this.controller.reserveAmmo;
 }
 applyActive(equip){
  const spec=this.definition,gun=this.controller,slot=this.slots[this.activeSlot];
  slot.attachments=slot.attachments||{};
  const mods=accessoryStats(spec,slot.attachments);
  this.avatar.setWeapon?.(spec.id);
  Object.assign(gun,{weaponSpec:spec,attachments:slot.attachments,attachmentMods:mods,magSize:mods.magSize,ammo:Math.min(slot.ammo,mods.magSize),reserveAmmo:this.reserves[spec.ammoType],fireRate:spec.fireRate,reloadTime:spec.reloadTime,spread:spec.spread,isReloading:false,reloadTimer:0,triggerHeld:false});
  let model=this.heldModels.get(spec.id);
  if(!model){model=createModel(spec.id);this.heldModels.set(spec.id,model);this.avatar.gun.add(model);}
  applyAccessoryVisuals(model,spec.id,slot.attachments);
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
  if(kind==='weapon'&&!DEFINITIONS[id]||kind==='ammo'&&!AMMO_NAMES[id]||kind==='accessory'&&!ACCESSORIES[id])return null;
  if(!this.isSafePoint(position,kind==='weapon'?.65:.16))return null;
  const group=new THREE.Group();group.userData.ignoreCombat=true;group.userData.ignoreCamera=true;
  const spec=kind==='weapon'?DEFINITIONS[id]:null,color=spec?.color||ACCESSORIES[id]?.color||({light:0x80c4de,rifle:0x91c388,shells:0xe8b17f})[id];
  if(spec){const model=createModel(id);model.scale.setScalar(1.3);model.rotation.y=this.random()*Math.PI*2;group.add(model);}
  else{const material=new THREE.MeshStandardMaterial({color,roughness:.9});const box=new THREE.Mesh(new THREE.BoxGeometry(.17,.12,.13),material);group.add(box);}
  const halo=new THREE.Mesh(new THREE.RingGeometry(.24,.29,24),new THREE.MeshBasicMaterial({color,side:THREE.DoubleSide,transparent:true,opacity:.5}));halo.rotation.x=-Math.PI/2;halo.position.y=-.19;group.add(halo);
  const item={kind,id,amount,group,position:position.clone(),ammo:options.ammo??spec?.magSize,attachments:{...(options.attachments||{})},bonusAmmo:options.bonusAmmo??spec?.magSize??0,drop:!!options.drop};
  group.position.copy(position).add(new THREE.Vector3(0,.22,0));this.scene.add(group);this.items.push(item);
  if(item.drop){const drops=this.items.filter(i=>i.drop);if(drops.length>32)this.remove(drops[0]);}
  return item;
 }
 addWeapon(id,position,options={}){return this.add('weapon',id,0,position,options);}
 addAmmo(type,amount,position,options={}){return this.add('ammo',type,amount,position,options);}
 addAccessory(id,position,options={}){return this.add('accessory',id,1,position,options);}
 setAccessory(id,enabled=true){
  const slot=this.slots[this.activeSlot];
  if(!slot||!ACCESSORIES[id])return false;
  if(enabled&&!accessoryAllowed(slot.id,id)){this.notify('Acessório incompatível com esta arma');return false;}
  this.saveActive();slot.attachments=slot.attachments||{};
  if(enabled)slot.attachments[id]=true;else delete slot.attachments[id];
  this.applyActive(false);
  this.notify(ACCESSORIES[id].name+(enabled?' instalado':' removido'));return true;
 }
 equipAccessory(id){
  const slot=this.slots[this.activeSlot];
  if(!slot||!accessoryAllowed(slot.id,id)){this.notify('Acessório incompatível com esta arma');return false;}
  slot.attachments=slot.attachments||{};
  if(slot.attachments[id]){this.notify(ACCESSORIES[id].name+' já instalado');return false;}
  return this.setAccessory(id,true);
 }
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
  if(item.kind==='accessory'){
   if(!this.equipAccessory(item.id))return false;
   this.remove(item);return true;
  }
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
   this.addWeapon(previous.id,p,{ammo:previous.ammo,attachments:previous.attachments,bonusAmmo:0,drop:true});
  }
  const spec=DEFINITIONS[item.id];this.slots[slot]={id:item.id,ammo:item.ammo,attachments:{...(item.attachments||{})}};
  this.reserves[spec.ammoType]=Math.min(CAPS[spec.ammoType],this.reserves[spec.ammoType]+item.bonusAmmo);
  this.activeSlot=slot;this.remove(item);this.applyActive(true);this.notify(spec.name+' equipada');return true;
 }
 populate(){
  for(const [id,x,z]of [['smg',-2,-1],['rifle',2,-2],['shotgun',0,-5],['pistol',-3,-7],['sniper',4,-8]])this.addWeapon(id,new THREE.Vector3(x,this.terrainHeight(x,z),z));
  for(const [id,x,z]of [['optic',-1,-4],['suppressor',2,-5],['extended',-4,-4],['grip',4,-3],['stock',-5,-2]]){
   this.addAccessory(id,new THREE.Vector3(x,this.terrainHeight(x,z),z));
  }
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
 dropOnDeath(position){
  this.saveActive();
  const carried=this.slots.filter(Boolean);
  for(let n=0;n<carried.length;n++){
   const slot=carried[n],origin=position.clone();origin.z+=n*.65;
   const p=this.safeDrop(origin);
   if(p)this.addWeapon(slot.id,p,{ammo:slot.ammo,bonusAmmo:0,drop:true});
  }
  for(const [type,amount]of Object.entries(this.reserves))if(amount>0){
   const p=this.safeDrop(position);if(p)this.addAmmo(type,amount,p,{drop:true});
  }
  this.slots=[null,null];this.reserves={light:0,rifle:0,shells:0};this.activeSlot=0;
  this.controller.holster();this.controller.ammo=0;this.controller.reserveAmmo=0;
  this.controller.isReloading=false;this.controller.reloadTimer=0;this.controller.triggerHeld=false;
  this.avatar.gun.visible=false;this.avatar.flash.visible=false;this.nearest=null;this.messageTime=0;
 }
 resetAfterDeath(){
  this.slots=[{id:'pistol',ammo:12},null];this.reserves={light:60,rifle:0,shells:0};this.activeSlot=0;
  this.applyActive(false);this.controller.holster();
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
   return 'E · pegar '+(this.nearest.kind==='weapon'?DEFINITIONS[this.nearest.id].name:this.nearest.kind==='accessory'?ACCESSORIES[this.nearest.id].name:AMMO_NAMES[this.nearest.id]+' ×'+this.nearest.amount);
  }
  return this.messageTime>0?this.message:'';
 }
}
WeaponLootSystem.ACCESSORIES=ACCESSORIES;WeaponLootSystem.accessoryStats=accessoryStats;WeaponLootSystem.applyAccessoryVisuals=applyAccessoryVisuals;WeaponLootSystem.DEFINITIONS=DEFINITIONS;WeaponLootSystem.AMMO_NAMES=AMMO_NAMES;WeaponLootSystem.createModel=createModel;WeaponLootSystem.animateMechanics=animateMechanics;
window.WeaponLootSystem=WeaponLootSystem;
})();

