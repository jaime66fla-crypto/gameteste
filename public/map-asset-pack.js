/* Gameteste asset integration: stylized low-poly stand-ins for the uploaded
   wooden watch tower FBX and sniper ammunition FBX. Original meshes/textures are
   retained separately for later optimization to GLB. */
(()=>{
'use strict';
class MapAssetPack {
 constructor({THREE,scene,terrain,solidBoxes,weaponLoot,player,isActive,isMultiplayer}){
  Object.assign(this,{T:THREE,scene,terrain,solidBoxes,weaponLoot,player,isActive,isMultiplayer});
  this.group=new THREE.Group();this.group.name='WOOD_TOWER_AND_SNIPER_AMMO_ASSET_PACK';scene.add(this.group);
  this.crates=[];this.makeTower(-73,100);this.makeTower(74,-98);
 }
 box(parent,w,h,d,x,y,z,material,collider=false){
  const T=this.T,m=new T.Mesh(new T.BoxGeometry(w,h,d),material);m.position.set(x,y,z);
  m.castShadow=true;m.receiveShadow=true;parent.add(m);
  if(collider){
   m.updateMatrixWorld(true);const p=m.getWorldPosition(new T.Vector3());
   this.solidBoxes.push({minX:p.x-w/2,maxX:p.x+w/2,minY:p.y-h/2,maxY:p.y+h/2,minZ:p.z-d/2,maxZ:p.z+d/2});
  }
  return m;
 }
 makeTower(x,z){
  const T=this.T,y=this.terrain(x,z),root=new T.Group();root.position.set(x,y,z);root.name='Wood_Watch_Tower';this.group.add(root);
  const timber=new T.MeshStandardMaterial({color:0x76573a,roughness:.95});
  const dark=new T.MeshStandardMaterial({color:0x493927,roughness:.95});
  const planks=new T.MeshStandardMaterial({color:0x9e7952,roughness:.92});
  const metal=new T.MeshStandardMaterial({color:0x34383b,metalness:.4,roughness:.68});
  for(const px of [-2.1,2.1])for(const pz of [-2.1,2.1]){
   this.box(root,.47,8.5,.47,px,4.25,pz,timber);
   this.box(root,.60,.27,.60,px,.16,pz,dark);
  }
  // Braces and climbable staggered steps against the left support.
  for(let h=1.6;h<8;h+=2.1){
   for(const px of [-2,2])this.box(root,.17,.28,4.7,px,h,0,dark);
   for(const pz of [-2,2])this.box(root,4.7,.27,.17,0,h,pz,dark);
  }
  // Platform is solid; climbing onto it is handled by the existing climb system.
  const platform=this.box(root,5.3,.38,5.3,0,8.35,0,planks);
  this.solidBoxes.push({minX:x-2.65,maxX:x+2.65,minY:y+8.16,maxY:y+8.54,minZ:z-2.65,maxZ:z+2.65});
  // Four side railings leave an opening near the ladder.
  for(const side of [-1,1]){
   this.box(root,.17,1.15,5.2,side*2.50,9.02,0,timber);
   if(side===1)this.box(root,5.2,1.15,.17,0,9.02,side*2.50,timber);
  }
  this.box(root,2,1.15,.17,-1.65,9.02,-2.50,timber);
  this.box(root,1.10,1.15,.17,1.99,9.02,-2.50,timber);
  // Ladder, rungs, climb-through access along front side.
  for(const sx of [-.48,.48])this.box(root,.13,8.4,.13,sx,4.2,-2.7,timber);
  for(let h=.46;h<8.3;h+=.43)this.box(root,1.10,.105,.14,0,h,-2.7,planks);
  // Pitched roof with overhang.
  const roof=new T.Mesh(new T.ConeGeometry(4.7,2.1,4),dark);
  roof.position.set(0,10.55,0);roof.rotation.y=Math.PI/4;roof.castShadow=true;root.add(roof);
  this.box(root,.35,.65,.35,0,11.65,0,metal);
  this.makeAmmoCrate(x+6,z+3);
 }
 makeAmmoCrate(x,z){
  const T=this.T,y=this.terrain(x,z),root=new T.Group();root.position.set(x,y,z);root.name='Sniper_Ammo_Cache';this.group.add(root);
  const wood=new T.MeshStandardMaterial({color:0x5a6650,roughness:.9}),metal=new T.MeshStandardMaterial({color:0xc29a58,metalness:.72,roughness:.31}),tip=new T.MeshStandardMaterial({color:0x9d8b67,metalness:.6,roughness:.45});
  this.box(root,.95,.42,.70,0,.24,0,wood);
  this.box(root,1.00,.065,.75,0,.47,0,metal);
  for(let i=0;i<5;i++){
   const x0=(i-2)*.145;
   const casing=new T.Mesh(new T.CylinderGeometry(.053,.053,.25,10),metal);
   casing.position.set(x0,.65,0);root.add(casing);
   const bullet=new T.Mesh(new T.ConeGeometry(.052,.12,10),tip);
   bullet.position.set(x0,.83,0);root.add(bullet);
  }
  const glow=new T.PointLight(0xf2c86c,.32,5);glow.position.y=1.1;root.add(glow);
  this.crates.push({root,position:new T.Vector3(x,y,z),available:true,cooldown:0});
 }
 update(dt){
  // The cache is collected on proximity. Prevent duplicates when offline cache is on cooldown.
  const usable=this.isActive()&&!this.isMultiplayer();
  for(const item of this.crates){
   if(!item.available){
    item.cooldown=Math.max(0,item.cooldown-dt);
    if(item.cooldown===0){item.available=true;item.root.visible=true}
    continue;
   }
   if(!usable)continue;
   const distance=Math.hypot(this.player.position.x-item.position.x,this.player.position.z-item.position.z);
   if(distance>2.1||Math.abs(this.player.position.y-item.position.y)>2.7)continue;
   const before=this.weaponLoot.reserves.rifle||0;
   const after=Math.min(180,before+15);
   if(after<=before)continue;
   this.weaponLoot.reserves.rifle=after;
   if(this.weaponLoot.definition?.ammoType==='rifle')this.weaponLoot.controller.reserveAmmo=after;
   this.weaponLoot.notify?.('Munição sniper +'+(after-before));
   item.available=false;item.cooldown=75;item.root.visible=false;
  }
 }
}
window.GametesteMapAssetPack=MapAssetPack;
})();