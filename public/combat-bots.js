/* Local training opponents. All damage is evaluated against visible geometry. */
(() => {
'use strict';
class CombatBotSystem {
 constructor({scene,player,terrainHeight=()=>0,solidBoxes=[],camera=null,random=Math.random,onKill=()=>{},onPlayerDeath=()=>{},onPlayerHit=()=>{}}){
  Object.assign(this,{scene,player,terrainHeight,solidBoxes,camera,random,onKill,onPlayerDeath,onPlayerHit});
  this.health=100;this.time=0;this.effects=[];
  this.bots=[[-6,-9],[2,-12],[7,-7]].map(([x,z],index)=>this.createBot(x,z,index));
 }
 static firstHit(scene,raycaster,ignoredRoot,includeHiddenAvatar=false){
  const meshes=[];
  scene.traverse(object=>{
   if(!object.isMesh)return;
   for(let p=object;p;p=p.parent)if((!p.visible&&!(includeHiddenAvatar&&p.userData.combatHitWhenHidden))||p===ignoredRoot||p.userData.ignoreCombat)return;
   meshes.push(object);
  });
  return raycaster.intersectObjects(meshes,false)[0]||null;
 }
 createBot(x,z,index){
  const avatar=new window.OperatorAvatar({team:'red'}),group=avatar.group;
  group.position.set(x,this.terrainHeight(x,z),z);this.scene.add(group);avatar.gun.visible=true;
  const bot={avatar,group,index,spawn:new THREE.Vector3(x,group.position.y,z),health:90,alive:true,respawn:0,cooldown:3+index*.8,hitTime:0,flashTime:0};
  bot.takeDamage=amount=>{
   if(!bot.alive||!Number.isFinite(amount)||amount<=0)return;
   bot.health=Math.max(0,bot.health-amount);bot.hitTime=.14;
   bot.bar.scale.x=bot.health/90;bot.bar.position.x=-(.55-.55*bot.health/90)/2;
   if(bot.health===0){bot.alive=false;bot.group.visible=false;bot.respawn=6;this.onKill(bot);}
  };
  group.traverse(o=>{if(o.isMesh)o.userData.enemyRef=bot;});
  const bars=new THREE.Group();bars.position.y=1.98;bars.userData.ignoreCombat=true;group.add(bars);bot.bars=bars;
  const background=new THREE.Mesh(new THREE.BoxGeometry(.59,.07,.02),new THREE.MeshBasicMaterial({color:0x281d1e}));bars.add(background);
  bot.bar=new THREE.Mesh(new THREE.BoxGeometry(.55,.035,.025),new THREE.MeshBasicMaterial({color:0xe5776e}));bot.bar.position.z=.01;bars.add(bot.bar);
  return bot;
 }
 canMove(x,z){
  return !this.solidBoxes.some(b=>x+.32>b.minX&&x-.32<b.maxX&&z+.32>b.minZ&&z-.32<b.maxZ&&b.maxY>this.terrainHeight(x,z)+.1);
 }
 tracer(start,end){
  const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints([start,end]),new THREE.LineBasicMaterial({color:0xffb7a1,transparent:true,opacity:.7}));
  this.scene.add(line);this.effects.push({line,life:.07});
 }
 damagePlayer(amount){
  if(this.health<=0)return;
  this.health=Math.max(0,this.health-amount);this.onPlayerHit(this.health,amount);
  if(this.health===0){for(const bot of this.bots)bot.cooldown=3+bot.index*.7;this.onPlayerDeath();}
 }
 shoot(bot){
  if(this.health<=0)return;
  this.scene.updateMatrixWorld(true);
  const start=bot.avatar.gun.localToWorld(new THREE.Vector3(0,.035,.2));
  const target=this.player.position.clone().add(new THREE.Vector3(0,this.player.userData.crouching?.9:1.2,0));
  // Training bots deliberately miss most shots, leaving time to aim and reload.
  if(this.random()>.35)target.x+=(this.random()>.5?1:-1)*1.15;
  const direction=target.sub(start),distance=direction.length();
  if(distance<.01)return;
  const ray=new THREE.Raycaster(start,direction.normalize(),0,distance+.5);
  const hit=CombatBotSystem.firstHit(this.scene,ray,bot.group,true);
  const end=hit?hit.point:start.clone().addScaledVector(direction,distance);
  this.tracer(start,end);bot.flashTime=.065;
  if(hit?.object?.userData?.iceWallId)this.onCoverHit?.(hit.object.userData.iceWallId,6);
  if(hit){for(let o=hit.object;o;o=o.parent){if(o===this.player){this.damagePlayer(6);break;}}}
 }
 update(dt){
  this.time+=dt;
  for(let i=this.effects.length-1;i>=0;i--){const effect=this.effects[i];effect.life-=dt;if(effect.life<=0){this.scene.remove(effect.line);effect.line.geometry.dispose();effect.line.material.dispose();this.effects.splice(i,1);}}
  for(const bot of this.bots){
   if(!bot.alive){
    bot.respawn-=dt;
    if(bot.respawn<=0){bot.alive=true;bot.health=90;bot.group.visible=true;bot.group.position.copy(bot.spawn);bot.bar.scale.x=1;bot.bar.position.x=0;bot.cooldown=2+bot.index*.4;bot.hitTime=0;}
    continue;
   }
   const previous=bot.group.position.clone();
   const x=bot.spawn.x+Math.sin(this.time*.6+bot.index)*1.8,z=bot.spawn.z+Math.sin(this.time*.43+bot.index*2)*1.3;
   const step=Math.min(1,dt*2);
   const nx=THREE.MathUtils.lerp(previous.x,x,step),nz=THREE.MathUtils.lerp(previous.z,z,step);
   if(this.canMove(nx,previous.z))bot.group.position.x=nx;
   if(this.canMove(bot.group.position.x,nz))bot.group.position.z=nz;
   bot.group.position.y=this.terrainHeight(bot.group.position.x,bot.group.position.z);
   const delta=this.player.position.clone().sub(bot.group.position),range=delta.length();
   const yaw=Math.atan2(delta.x,delta.z),angle=Math.atan2(Math.sin(yaw-bot.group.rotation.y),Math.cos(yaw-bot.group.rotation.y));
   bot.group.rotation.y+=angle*(1-Math.exp(-dt*7));
   bot.avatar.update(dt,{speed:dt>0?previous.distanceTo(bot.group.position)/dt:0,grounded:true,armed:true});
   bot.hitTime=Math.max(0,bot.hitTime-dt);bot.flashTime=Math.max(0,bot.flashTime-dt);
   bot.avatar.materials.fabric.emissive.setHex(bot.hitTime>0?0x6b1e17:0);bot.avatar.flash.visible=bot.flashTime>0;
   if(this.camera)bot.bars.lookAt(this.camera.position);
   bot.cooldown-=dt;
   if(bot.cooldown<=0&&range<24&&range>1){bot.cooldown=2.6+bot.index*.25;this.shoot(bot);}
  }
 }
}
window.CombatBotSystem=CombatBotSystem;
})();

