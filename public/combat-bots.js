/* Tactical local training opponents: sight, hearing, investigation, cover and combat states. */
(() => {
'use strict';

const STATES=Object.freeze({
 PATROL:'PATROL',
 INVESTIGATE:'INVESTIGATE',
 CHASE:'CHASE',
 TAKE_COVER:'TAKE_COVER',
 ATTACK:'ATTACK',
 FLANK:'FLANK',
 EVADE:'EVADE',
 RETREAT:'RETREAT'
});

class CombatBotSystem {
 constructor({scene,player,terrainHeight=()=>0,solidBoxes=[],camera=null,random=Math.random,onKill=()=>{},onPlayerDeath=()=>{},onPlayerHit=()=>{}}){
  Object.assign(this,{scene,player,terrainHeight,solidBoxes,camera,random,onKill,onPlayerDeath,onPlayerHit});
  this.health=100;
  this.time=0;
  this.effects=[];
  this.soundEvents=[];
  this.viewDistance=34;
  this.hearingDistance=30;
  this.squadLastKnown=null;
  this.squadMemory=0;
  this.squadTick=0;
  this.suppressorId=null;
  this.flankerId=null;
  this.botGrenades=new Map();
  this.getGrenades=()=>[];
  this.getWalls=()=>[];
  this.bots=[[-6,-9],[2,-12],[7,-7]].map(([x,z],index)=>this.createBot(x,z,index));
 }

 static firstHit(scene,raycaster,ignoredRoot,includeHiddenAvatar=false){
  const meshes=[];
  scene.traverse(object=>{
   if(!object.isMesh)return;
   for(let p=object;p;p=p.parent){
    if((!p.visible&&!(includeHiddenAvatar&&p.userData.combatHitWhenHidden))||p===ignoredRoot||p.userData.ignoreCombat)return;
   }
   meshes.push(object);
  });
  return raycaster.intersectObjects(meshes,false)[0]||null;
 }

 createBot(x,z,index){
  const avatar=new window.OperatorAvatar({team:'red'}),group=avatar.group;
  group.position.set(x,this.terrainHeight(x,z),z);
  this.scene.add(group);
  avatar.gun.visible=true;

  const bot={
   avatar,group,index,
   spawn:new THREE.Vector3(x,group.position.y,z),
   health:90,alive:true,respawn:0,cooldown:2.2+index*.45,hitTime:0,flashTime:0,
   state:STATES.PATROL,stateTime:0,
   patrolAngle:index*Math.PI*2/3,patrolRadius:3.5+index*.8,
   target:null,lastKnownTarget:null,investigatePoint:null,coverPoint:null,
   lostSightTime:0,reactionTimer:.22+index*.07,
   moveSpeed:2.6,sprintSpeed:4.1,retreatHealth:26,
   accuracy:.58-index*.04,burstShots:0,burstGap:0,
   inCover:false,coverAnchor:null,crouching:false,peekSide:index%2===0?1:-1,peekTimer:.7+index*.15,
   flankPoint:null,flankCooldown:2.5+index*.8,
   squadRole:'support',sharedIntelAge:999,lastKnownAge:999,
   grenades:1,grenadeCooldown:3.5+index*.8,evadePoint:null,evadeTimer:0,blockedWallId:null,
   preparingGrenade:false,grenadePrepTimer:0,grenadeTarget:null,grenadeDirection:null,heldGrenade:null
  };

  bot.takeDamage=amount=>{
   if(!bot.alive||!Number.isFinite(amount)||amount<=0)return;
   bot.health=Math.max(0,bot.health-amount);
   bot.hitTime=.14;
   bot.bar.scale.x=bot.health/90;
   bot.bar.position.x=-(.55-.55*bot.health/90)/2;

   if(bot.health===0){
    bot.alive=false;
    bot.group.visible=false;
    bot.respawn=6;
    bot.state=STATES.PATROL;
    bot.coverPoint=null;
    bot.preparingGrenade=false;
    bot.grenadePrepTimer=0;
    bot.grenadeTarget=null;
    bot.grenadeDirection=null;
    if(bot.heldGrenade)bot.heldGrenade.visible=false;
    bot.avatar.gun.visible=true;
    this.onKill(bot);
    return;
   }

   bot.lastKnownTarget=this.player.position.clone();
   bot.investigatePoint=bot.lastKnownTarget.clone();
   if(bot.health<=bot.retreatHealth)this.setState(bot,STATES.RETREAT);
   else this.setState(bot,STATES.TAKE_COVER);
  };

  group.traverse(o=>{if(o.isMesh)o.userData.enemyRef=bot;});

  const bars=new THREE.Group();
  bars.position.y=1.98;
  bars.userData.ignoreCombat=true;
  group.add(bars);
  bot.bars=bars;

  const background=new THREE.Mesh(new THREE.BoxGeometry(.59,.07,.02),new THREE.MeshBasicMaterial({color:0x281d1e}));
  bars.add(background);
  bot.bar=new THREE.Mesh(new THREE.BoxGeometry(.55,.035,.025),new THREE.MeshBasicMaterial({color:0xe5776e}));
  bot.bar.position.z=.01;
  bars.add(bot.bar);

  if(window.TacticalGear?.grenadeModel){
   bot.heldGrenade=window.TacticalGear.grenadeModel();
   bot.heldGrenade.scale.setScalar(.82);
   bot.heldGrenade.position.set(.02,-.035,.035);
   bot.heldGrenade.rotation.set(.25,.15,-.25);
   bot.heldGrenade.visible=false;
   bot.heldGrenade.userData.ignoreCombat=true;
   bot.avatar.rightHand.add(bot.heldGrenade);
  }

  return bot;
 }

 setState(bot,state){
  if(bot.state===state)return;
  bot.state=state;
  bot.stateTime=0;
  if(state!==STATES.TAKE_COVER&&state!==STATES.RETREAT)bot.coverPoint=null;
  if(state!==STATES.FLANK)bot.flankPoint=null;
  if(state!==STATES.EVADE)bot.evadePoint=null;
  if(state===STATES.ATTACK)bot.reactionTimer=.16+this.random()*.22;
  if(state===STATES.TAKE_COVER){bot.inCover=false;bot.crouching=false;}
  if(state===STATES.FLANK){bot.inCover=false;bot.crouching=false;}
 }

 shareTarget(position,sourceBot=null){
  if(!position)return;
  this.squadLastKnown=position.clone();
  this.squadMemory=4.5;
  for(const mate of this.bots){
   if(!mate.alive||mate===sourceBot)continue;
   mate.lastKnownTarget=this.squadLastKnown.clone();
   mate.sharedIntelAge=0;
   mate.lastKnownAge=0;
   if(mate.state===STATES.PATROL){
    mate.investigatePoint=this.squadLastKnown.clone();
    this.setState(mate,STATES.INVESTIGATE);
   }
  }
 }

 coordinateSquad(){
  const alive=this.bots.filter(bot=>bot.alive);
  if(alive.length<2||!this.squadLastKnown){
   this.suppressorId=null;
   this.flankerId=null;
   for(const bot of alive)bot.squadRole='support';
   return;
  }

  const candidates=alive.filter(bot=>bot.health>bot.retreatHealth);
  if(candidates.length<2)return;

  candidates.sort((a,b)=>a.group.position.distanceTo(this.squadLastKnown)-b.group.position.distanceTo(this.squadLastKnown));
  const suppressor=candidates[0];
  const flankers=candidates.filter(bot=>bot!==suppressor&&bot.flankCooldown<=0);
  const flanker=flankers.sort((a,b)=>b.health-a.health)[0]||candidates[1];

  this.suppressorId=suppressor.index;
  this.flankerId=flanker?.index??null;

  for(const bot of alive){
   bot.squadRole=bot.index===this.suppressorId?'suppress':bot.index===this.flankerId?'flank':'support';
  }

  if(suppressor.state!==STATES.RETREAT&&suppressor.state!==STATES.TAKE_COVER){
   suppressor.lastKnownTarget=this.squadLastKnown.clone();
   this.setState(suppressor,STATES.ATTACK);
  }

  if(flanker&&flanker.state!==STATES.RETREAT&&flanker.state!==STATES.TAKE_COVER){
   flanker.lastKnownTarget=this.squadLastKnown.clone();
   this.setState(flanker,STATES.FLANK);
  }
 }

 grenadeThreat(bot){
  let best=null,bestDistance=Infinity;
  const grenades=[...(this.getGrenades?.()||[]),...[...this.botGrenades.values()].map(entry=>entry.state)];
  for(const grenade of grenades){
   if(!grenade?.position)continue;
   const point=new THREE.Vector3(grenade.position.x,grenade.position.y||0,grenade.position.z);
   const distance=bot.group.position.distanceTo(point);
   const remaining=(window.TacticalRules?.CONFIG?.fuse||2.8)-(grenade.age||0);
   if(distance<7.5&&remaining<2.15&&distance<bestDistance){
    best={point,distance,remaining};
    bestDistance=distance;
   }
  }
  return best;
 }

 evadeGrenade(bot,threat){
  const away=bot.group.position.clone().sub(threat.point).setY(0);
  if(away.lengthSq()<.001)away.set(bot.peekSide,0,1);
  away.normalize();
  const lateral=new THREE.Vector3(-away.z,0,away.x).multiplyScalar(bot.peekSide*.65);
  for(const distance of [6.5,5,4]){
   const point=bot.group.position.clone().add(away.clone().multiplyScalar(distance)).add(lateral.clone().multiplyScalar(distance*.35));
   point.y=this.terrainHeight(point.x,point.z);
   if(this.canMove(point.x,point.z)){
    bot.evadePoint=point;
    bot.evadeTimer=Math.max(1.2,threat.remaining+.45);
    bot.inCover=false;
    bot.crouching=false;
    this.setState(bot,STATES.EVADE);
    return true;
   }
  }
  return false;
 }

 iceBlocker(bot,targetPos=this.player.position){
  const start=bot.avatar.gun.localToWorld(new THREE.Vector3(0,.035,.2));
  const target=targetPos.clone().add(new THREE.Vector3(0,this.player.userData.crouching?.9:1.2,0));
  const direction=target.sub(start),distance=direction.length();
  if(distance<.01)return null;
  const ray=new THREE.Raycaster(start,direction.normalize(),0,distance+.25);
  const hit=CombatBotSystem.firstHit(this.scene,ray,bot.group,true);
  return hit?.object?.userData?.iceWallId?{id:hit.object.userData.iceWallId,point:hit.point}:null;
 }

 chooseGrenadeDirection(bot,targetPos){
  const R=window.TacticalRules;
  if(!R)return null;
  const start=bot.group.position.clone();
  const toTarget=targetPos.clone().sub(start);
  const flatDistance=Math.hypot(toTarget.x,toTarget.z);
  if(flatDistance<7||flatDistance>20)return null;

  let best=null,bestScore=Infinity;
  const baseYaw=Math.atan2(toTarget.x,toTarget.z);
  for(const yawOffset of [0,-.08,.08,-.14,.14]){
   for(const lift of [.08,.15,.22,.30,.38]){
    const yaw=baseYaw+yawOffset;
    const dir=new THREE.Vector3(Math.sin(yaw),lift,Math.cos(yaw)).normalize();
    const sim=R.grenade('sim','bot-'+bot.index,start,dir,0);
    if(!sim)continue;

    let closest=Infinity;
    for(let t=0;t<R.CONFIG.fuse;t+=.08){
     R.advance(sim,.08,this.solidBoxes,this.terrainHeight);
     const dx=sim.position.x-targetPos.x,dz=sim.position.z-targetPos.z;
     const d=Math.hypot(dx,dz);
     if(d<closest)closest=d;
    }

    const selfDistance=Math.hypot(sim.position.x-start.x,sim.position.z-start.z);
    if(selfDistance<R.CONFIG.radius+1)continue;
    const score=closest+Math.abs(yawOffset)*1.5+Math.abs(lift-.22)*.45;
    if(score<bestScore){bestScore=score;best=dir;}
   }
  }
  return best;
 }

 beginGrenadeThrow(bot,targetPos=this.player.position){
  if(bot.preparingGrenade||bot.grenades<=0||bot.grenadeCooldown>0)return false;
  const direction=this.chooseGrenadeDirection(bot,targetPos);
  if(!direction)return false;

  bot.preparingGrenade=true;
  bot.grenadePrepTimer=.72+this.random()*.22;
  bot.grenadeTarget=targetPos.clone();
  bot.grenadeDirection=direction;
  bot.inCover=false;
  bot.crouching=false;
  bot.avatar.gun.visible=false;
  if(bot.heldGrenade)bot.heldGrenade.visible=true;
  return true;
 }

 releaseGrenade(bot){
  const R=window.TacticalRules;
  if(!R||!bot.preparingGrenade||!bot.grenadeDirection)return false;

  const start=bot.group.position.clone();
  const state=R.grenade('bot-g-'+bot.index+'-'+Math.floor(this.time*1000),'bot-'+bot.index,start,bot.grenadeDirection,Date.now());
  bot.preparingGrenade=false;
  bot.grenadePrepTimer=0;
  bot.grenadeTarget=null;
  bot.grenadeDirection=null;
  if(bot.heldGrenade)bot.heldGrenade.visible=false;
  bot.avatar.gun.visible=true;
  if(!state)return false;

  const mesh=window.TacticalGear?.grenadeModel?window.TacticalGear.grenadeModel():new THREE.Mesh(new THREE.SphereGeometry(.11,8,6),new THREE.MeshStandardMaterial({color:0x454545}));
  mesh.userData.ignoreCombat=true;
  mesh.userData.ignoreCamera=true;
  mesh.position.set(state.position.x,state.position.y,state.position.z);
  this.scene.add(mesh);
  this.botGrenades.set(state.id,{state,mesh,owner:bot.index});
  bot.grenades--;
  bot.grenadeCooldown=8+this.random()*4;
  return true;
 }

 updateGrenadePreparation(bot,dt){
  if(!bot.preparingGrenade)return false;
  bot.grenadePrepTimer-=dt;
  const target=bot.grenadeTarget||this.player.position;
  this.face(bot,target,dt);

  // Simple throw anticipation: pull the throwing shoulder back, then drive forward.
  const progress=THREE.MathUtils.clamp(1-bot.grenadePrepTimer/.85,0,1);
  const shoulder=bot.avatar.rightArm;
  const elbow=bot.avatar.bones?.[7];
  if(shoulder){
   shoulder.rotation.x=THREE.MathUtils.lerp(shoulder.rotation.x,progress<.55?-1.05:-.35,.24);
   shoulder.rotation.z=THREE.MathUtils.lerp(shoulder.rotation.z,-.45,.2);
  }
  if(elbow)elbow.rotation.x=THREE.MathUtils.lerp(elbow.rotation.x,progress<.55?-1.2:-.35,.24);

  if(bot.grenadePrepTimer<=0){
   this.releaseGrenade(bot);
   return false;
  }
  return true;
 }

 throwGrenade(bot,targetPos=this.player.position){
  return this.beginGrenadeThrow(bot,targetPos);
 }

 updateBotGrenades(dt){
  const R=window.TacticalRules;
  if(!R)return;
  for(const [id,entry] of [...this.botGrenades]){
   R.advance(entry.state,dt,this.solidBoxes,this.terrainHeight);
   entry.mesh.position.set(entry.state.position.x,entry.state.position.y,entry.state.position.z);
   entry.mesh.rotation.x+=dt*7;
   entry.mesh.rotation.z+=dt*4;
   if(!R.expired(entry.state))continue;

   const origin=entry.state.position;
   const damage=R.blastDamage(origin,this.player.position,this.solidBoxes);
   if(damage>0)this.damagePlayer(damage,new THREE.Vector3(origin.x,origin.y,origin.z));

   for(const wall of this.getWalls?.()||[]){
    const state=wall.state||wall;
    if(!state?.position||!state.id)continue;
    const wallDamage=R.blastDamage(origin,state.position,this.solidBoxes.filter(b=>b.iceWallId!==state.id));
    if(wallDamage>0)this.onCoverHit?.(state.id,wallDamage*2);
   }

   this.scene.remove(entry.mesh);
   entry.mesh.traverse?.(o=>{if(o.geometry)o.geometry.dispose?.();if(o.material)o.material.dispose?.();});
   this.botGrenades.delete(id);
   this.reportSound(new THREE.Vector3(origin.x,origin.y,origin.z),34,'explosion');
  }
 }

 reportSound(position,radius=this.hearingDistance,type='noise'){
  if(!position)return;
  const point=position.clone?position.clone():new THREE.Vector3(position.x||0,position.y||0,position.z||0);
  this.soundEvents.push({point,radius:Math.max(1,radius),type,life:.9});
 }

 canMove(x,z){
  return !this.solidBoxes.some(b=>
   x+.32>b.minX&&x-.32<b.maxX&&
   z+.32>b.minZ&&z-.32<b.maxZ&&
   b.maxY>this.terrainHeight(x,z)+.1
  );
 }

 hasLineOfSight(bot,targetPos=this.player.position){
  const start=bot.group.position.clone().add(new THREE.Vector3(0,1.35,0));
  const target=targetPos.clone().add(new THREE.Vector3(0,this.player.userData.crouching?.85:1.15,0));
  const direction=target.sub(start);
  const distance=direction.length();
  if(distance<.01||distance>this.viewDistance)return false;

  const forward=new THREE.Vector3(Math.sin(bot.group.rotation.y),0,Math.cos(bot.group.rotation.y));
  const flat=direction.clone().setY(0).normalize();
  if(forward.dot(flat)<-.15&&bot.state===STATES.PATROL)return false;

  const ray=new THREE.Raycaster(start,direction.normalize(),0,distance+.2);
  const hit=CombatBotSystem.firstHit(this.scene,ray,bot.group,true);
  if(!hit)return true;
  for(let o=hit.object;o;o=o.parent)if(o===this.player)return true;
  return false;
 }

 findCover(bot,threatPos=this.player.position){
  let best=null,bestScore=Infinity;
  const botPos=bot.group.position;

  for(const b of this.solidBoxes){
   if(b.maxY-b.minY<.8)continue;

   const cx=(b.minX+b.maxX)/2,cz=(b.minZ+b.maxZ)/2;
   const dx=cx-threatPos.x,dz=cz-threatPos.z;
   const len=Math.hypot(dx,dz)||1;
   const nx=dx/len,nz=dz/len;
   const padding=.55;
   const halfX=(b.maxX-b.minX)/2,halfZ=(b.maxZ-b.minZ)/2;
   const point=new THREE.Vector3(
    cx+nx*(halfX+padding),
    0,
    cz+nz*(halfZ+padding)
   );

   const dist=botPos.distanceTo(point);
   if(dist>18||dist<1.2||!this.canMove(point.x,point.z))continue;

   const threatDistance=point.distanceTo(threatPos);
   const score=dist-threatDistance*.08;
   if(score<bestScore){bestScore=score;best=point;}
  }
  if(best)best.y=this.terrainHeight(best.x,best.z);
  return best;
 }

 getPeekPoint(bot,threatPos=this.player.position){
  const anchor=bot.coverAnchor||bot.group.position;
  const toThreat=threatPos.clone().sub(anchor).setY(0);
  if(toThreat.lengthSq()<.001)toThreat.set(0,0,1);
  toThreat.normalize();
  const lateral=new THREE.Vector3(-toThreat.z,0,toThreat.x).multiplyScalar(bot.peekSide*.95);
  const point=anchor.clone().add(lateral);
  point.y=this.terrainHeight(point.x,point.z);
  if(this.canMove(point.x,point.z))return point;
  bot.peekSide*=-1;
  const other=anchor.clone().add(lateral.multiplyScalar(-1));
  other.y=this.terrainHeight(other.x,other.z);
  return this.canMove(other.x,other.z)?other:anchor.clone();
 }

 findFlankPoint(bot,threatPos=this.player.position){
  const fromThreat=bot.group.position.clone().sub(threatPos).setY(0);
  if(fromThreat.lengthSq()<.001)fromThreat.set(0,0,1);
  fromThreat.normalize();
  const lateral=new THREE.Vector3(-fromThreat.z,0,fromThreat.x).multiplyScalar(bot.peekSide);
  for(const radius of [8,6,10,5]){
   const candidate=threatPos.clone()
    .add(fromThreat.clone().multiplyScalar(5.5))
    .add(lateral.clone().multiplyScalar(radius));
   candidate.y=this.terrainHeight(candidate.x,candidate.z);
   if(this.canMove(candidate.x,candidate.z))return candidate;
  }
  return null;
 }

 moveToward(bot,target,speed,dt,stopDistance=.35){
  if(!target)return 0;
  const pos=bot.group.position;
  const delta=target.clone().sub(pos);
  delta.y=0;
  const distance=delta.length();
  if(distance<=stopDistance)return 0;

  delta.normalize();
  const step=Math.min(distance,speed*dt);
  const nx=pos.x+delta.x*step,nz=pos.z+delta.z*step;

  if(this.canMove(nx,pos.z))pos.x=nx;
  else if(this.canMove(pos.x+delta.z*step,pos.z))pos.x+=delta.z*step*.7;

  if(this.canMove(pos.x,nz))pos.z=nz;
  else if(this.canMove(pos.x,pos.z-delta.x*step))pos.z-=delta.x*step*.7;

  pos.y=this.terrainHeight(pos.x,pos.z);
  return step;
 }

 face(bot,target,dt){
  if(!target)return;
  const delta=target.clone().sub(bot.group.position);
  if(delta.lengthSq()<.0001)return;
  const yaw=Math.atan2(delta.x,delta.z);
  const angle=Math.atan2(Math.sin(yaw-bot.group.rotation.y),Math.cos(yaw-bot.group.rotation.y));
  bot.group.rotation.y+=angle*(1-Math.exp(-dt*7));
 }

 tracer(start,end){
  const line=new THREE.Line(
   new THREE.BufferGeometry().setFromPoints([start,end]),
   new THREE.LineBasicMaterial({color:0xffb7a1,transparent:true,opacity:.7})
  );
  this.scene.add(line);
  this.effects.push({line,life:.07});
 }

 damagePlayer(amount,source=null){
  if(this.health<=0)return;
  this.health=Math.max(0,this.health-amount);
  this.onPlayerHit(this.health,amount,source);
  if(this.health===0){
   for(const bot of this.bots)bot.cooldown=3+bot.index*.7;
   this.onPlayerDeath();
  }
 }

 shoot(bot){
  if(this.health<=0)return;

  this.scene.updateMatrixWorld(true);
  const start=bot.avatar.gun.localToWorld(new THREE.Vector3(0,.035,.2));
  const target=this.player.position.clone().add(new THREE.Vector3(0,this.player.userData.crouching?.9:1.2,0));

  const distance=start.distanceTo(target);
  const movementPenalty=bot.state===STATES.CHASE?.12:0;
  const rangePenalty=THREE.MathUtils.clamp((distance-10)/35,0,.22);
  const hitChance=THREE.MathUtils.clamp(bot.accuracy-movementPenalty-rangePenalty,.28,.72);

  if(this.random()>hitChance){
   const miss=.7+distance*.025;
   target.x+=(this.random()-.5)*miss*2;
   target.y+=(this.random()-.5)*miss*.55;
   target.z+=(this.random()-.5)*miss*2;
  }

  const direction=target.sub(start),rayDistance=direction.length();
  if(rayDistance<.01)return;

  const ray=new THREE.Raycaster(start,direction.normalize(),0,rayDistance+.5);
  const hit=CombatBotSystem.firstHit(this.scene,ray,bot.group,true);
  const end=hit?hit.point:start.clone().addScaledVector(direction,rayDistance);
  this.tracer(start,end);
  bot.flashTime=.065;

  if(hit?.object?.userData?.iceWallId)this.onCoverHit?.(hit.object.userData.iceWallId,6);
  if(hit){
   for(let o=hit.object;o;o=o.parent){
    if(o===this.player){this.damagePlayer(6,bot.group.position);break;}
   }
  }
 }

 updatePerception(bot,dt){
  const playerPos=this.player.position;
  bot.grenadeCooldown=Math.max(0,bot.grenadeCooldown-dt);
  const threat=this.grenadeThreat(bot);
  if(threat&&bot.state!==STATES.EVADE)this.evadeGrenade(bot,threat);
  const distance=bot.group.position.distanceTo(playerPos);
  const sees=distance<=this.viewDistance&&this.hasLineOfSight(bot,playerPos);

  if(sees){
   bot.target=this.player;
   bot.lastKnownTarget=playerPos.clone();
   bot.lostSightTime=0;
   bot.sharedIntelAge=0;
   bot.lastKnownAge=0;
   this.shareTarget(playerPos,bot);

   if(bot.health<=bot.retreatHealth)this.setState(bot,STATES.RETREAT);
   else if(bot.squadRole==='flank'&&bot.state===STATES.FLANK){/* keep flanking while teammates suppress */}
   else if(distance<22)this.setState(bot,STATES.ATTACK);
   else this.setState(bot,STATES.CHASE);
   return true;
  }

  bot.lostSightTime+=dt;
  bot.lastKnownAge+=dt;
  if(bot.target&&bot.lostSightTime<1.4){
   bot.lastKnownTarget=playerPos.clone();
   return false;
  }
  bot.target=null;

  if(this.squadLastKnown&&this.squadMemory>0&&bot.sharedIntelAge<4.5){
   bot.lastKnownTarget=this.squadLastKnown.clone();
   if(bot.state===STATES.PATROL){
    bot.investigatePoint=this.squadLastKnown.clone();
    this.setState(bot,STATES.INVESTIGATE);
   }
  }

  let heard=null,heardScore=Infinity;
  for(const event of this.soundEvents){
   const d=bot.group.position.distanceTo(event.point);
   if(d<=event.radius&&d<heardScore){heard=event;heardScore=d;}
  }
  if(heard){
   bot.investigatePoint=heard.point.clone();
   bot.lastKnownTarget=heard.point.clone();
   if(bot.state===STATES.PATROL||bot.state===STATES.INVESTIGATE)this.setState(bot,STATES.INVESTIGATE);
  }
  return false;
 }

 updateState(bot,dt){
  bot.stateTime+=dt;
  const playerPos=this.player.position;
  if(this.updateGrenadePreparation(bot,dt))return 0;
  const distance=bot.group.position.distanceTo(playerPos);
  let movementSpeed=0;

  switch(bot.state){
   case STATES.EVADE:{
    bot.evadeTimer-=dt;
    movementSpeed=this.moveToward(bot,bot.evadePoint,bot.sprintSpeed*1.12,dt,.45);
    this.face(bot,bot.evadePoint,dt);
    if(bot.evadeTimer<=0||!bot.evadePoint||bot.group.position.distanceTo(bot.evadePoint)<.7){
     bot.peekSide*=-1;
     if(bot.lastKnownTarget)this.setState(bot,STATES.ATTACK);
     else this.setState(bot,STATES.PATROL);
    }
    break;
   }
   case STATES.PATROL:{
    bot.patrolAngle+=dt*.22;
    const target=bot.spawn.clone().add(new THREE.Vector3(
     Math.cos(bot.patrolAngle)*bot.patrolRadius,0,
     Math.sin(bot.patrolAngle*.86)*bot.patrolRadius
    ));
    target.y=this.terrainHeight(target.x,target.z);
    movementSpeed=this.moveToward(bot,target,bot.moveSpeed*.55,dt,.45);
    this.face(bot,target,dt);
    break;
   }
   case STATES.INVESTIGATE:{
    const target=bot.investigatePoint||bot.lastKnownTarget;
    if(target&&bot.grenades>0&&bot.grenadeCooldown<=0&&bot.lastKnownAge>.55&&bot.lastKnownAge<3.6){
     const distanceToMemory=bot.group.position.distanceTo(target);
     const recentEnough=bot.sharedIntelAge<3.8||bot.lastKnownAge<2.6;
     if(recentEnough&&distanceToMemory>8&&distanceToMemory<18&&this.random()<dt*.28){
      if(this.throwGrenade(bot,target)){
       bot.cooldown=Math.max(bot.cooldown,1.1);
       break;
      }
     }
    }
    movementSpeed=this.moveToward(bot,target,bot.moveSpeed,dt,.8);
    this.face(bot,target,dt);
    if(!target||bot.group.position.distanceTo(target)<1||bot.stateTime>5){
     bot.investigatePoint=null;
     this.setState(bot,STATES.PATROL);
    }
    break;
   }
   case STATES.CHASE:{
    const target=bot.lastKnownTarget||playerPos;
    const seesPlayer=this.hasLineOfSight(bot,playerPos);
    if(!seesPlayer&&target&&bot.grenades>0&&bot.grenadeCooldown<=0&&bot.lastKnownAge>.45&&bot.lastKnownAge<3.2){
     const memoryDistance=bot.group.position.distanceTo(target);
     if(memoryDistance>8&&memoryDistance<19&&this.random()<dt*.18){
      if(this.throwGrenade(bot,target)){
       bot.cooldown=Math.max(bot.cooldown,1.05);
       break;
      }
     }
    }
    movementSpeed=this.moveToward(bot,target,bot.sprintSpeed,dt,7);
    this.face(bot,target,dt);
    if(distance<22&&seesPlayer)this.setState(bot,STATES.ATTACK);
    else if(bot.lostSightTime>2.4)this.setState(bot,STATES.INVESTIGATE);
    break;
   }
   case STATES.TAKE_COVER:{
    if(!bot.coverPoint)bot.coverPoint=this.findCover(bot,playerPos);
    if(!bot.coverPoint){this.setState(bot,STATES.ATTACK);break;}
    movementSpeed=this.moveToward(bot,bot.coverPoint,bot.sprintSpeed,dt,.45);
    this.face(bot,playerPos,dt);
    if(bot.group.position.distanceTo(bot.coverPoint)<.65){
     bot.coverAnchor=bot.coverPoint.clone();
     bot.inCover=true;
     bot.crouching=true;
     bot.peekTimer=.75+this.random()*.65;
     if(bot.health<=bot.retreatHealth)this.setState(bot,STATES.RETREAT);
     else this.setState(bot,STATES.ATTACK);
    }
    break;
   }
   case STATES.RETREAT:{
    if(!bot.coverPoint)bot.coverPoint=this.findCover(bot,playerPos);
    if(bot.coverPoint){
     movementSpeed=this.moveToward(bot,bot.coverPoint,bot.sprintSpeed,dt,.5);
     this.face(bot,playerPos,dt);
    }else{
     const away=bot.group.position.clone().sub(playerPos).setY(0);
     if(away.lengthSq()<.01)away.set(1,0,0);
     away.normalize().multiplyScalar(6).add(bot.group.position);
     movementSpeed=this.moveToward(bot,away,bot.sprintSpeed,dt,.4);
     this.face(bot,playerPos,dt);
    }
    if(bot.stateTime>3.2&&bot.health>18)this.setState(bot,STATES.ATTACK);
    break;
   }
   case STATES.FLANK:{
    if(!bot.flankPoint)bot.flankPoint=this.findFlankPoint(bot,playerPos);
    if(!bot.flankPoint){this.setState(bot,STATES.ATTACK);break;}
    movementSpeed=this.moveToward(bot,bot.flankPoint,bot.sprintSpeed,dt,.8);
    this.face(bot,playerPos,dt);
    if(bot.group.position.distanceTo(bot.flankPoint)<1||bot.stateTime>3.8){
     bot.flankCooldown=4+this.random()*3;
     bot.peekSide*=-1;
     this.setState(bot,STATES.ATTACK);
    }
    break;
   }
   case STATES.ATTACK:
   default:{
    this.face(bot,playerPos,dt);

    if(bot.inCover&&bot.coverAnchor){
     bot.peekTimer-=dt;
     const peeking=bot.peekTimer<=0;
     bot.crouching=!peeking;
     const coverTarget=peeking?this.getPeekPoint(bot,playerPos):bot.coverAnchor;
     movementSpeed=this.moveToward(bot,coverTarget,bot.moveSpeed*.72,dt,.18);
     if(peeking&&bot.peekTimer<-.72){
      bot.peekTimer=.7+this.random()*.8;
      bot.peekSide*=-1;
     }
    }else{
     bot.crouching=false;
    }

    const los=this.hasLineOfSight(bot,playerPos);

    if(!los){
     const ice=this.iceBlocker(bot,playerPos);
     if(ice){
      bot.blockedWallId=ice.id;
      bot.cooldown-=dt;
      if(bot.squadRole==='suppress'&&bot.cooldown<=0){
       this.face(bot,ice.point,dt);
       this.shoot(bot);
       bot.cooldown=.52+this.random()*.3;
       break;
      }
      if(bot.squadRole!=='suppress'&&bot.flankCooldown<=0){
       this.setState(bot,STATES.FLANK);
       break;
      }
     }
     if(bot.lastKnownTarget)this.setState(bot,STATES.CHASE);
     else this.setState(bot,STATES.INVESTIGATE);
     break;
    }
    bot.blockedWallId=null;

    if(!bot.inCover){
     if(distance<5){
      const away=bot.group.position.clone().sub(playerPos).setY(0).normalize().multiplyScalar(4).add(bot.group.position);
      movementSpeed=this.moveToward(bot,away,bot.moveSpeed,dt,.5);
     }else if(distance>19){
      movementSpeed=this.moveToward(bot,playerPos,bot.moveSpeed,dt,13);
     }
    }

    bot.reactionTimer-=dt;
    bot.cooldown-=dt;
    bot.burstGap-=dt;

    const suppressing=bot.squadRole==='suppress';
    if(suppressing)bot.cooldown=Math.min(bot.cooldown,.55);

    if(bot.squadRole==='support'&&bot.grenades>0&&bot.grenadeCooldown<=0&&distance>8&&distance<18&&this.random()<dt*.12){
     if(this.throwGrenade(bot,playerPos)){
      bot.cooldown=Math.max(bot.cooldown,1);
      break;
     }
    }
    if(bot.reactionTimer<=0&&bot.cooldown<=0&&distance<26){
     if(bot.burstShots<=0)bot.burstShots=2+Math.floor(this.random()*2);
     if(bot.burstGap<=0){
      this.shoot(bot);
      bot.burstShots--;
      bot.burstGap=.16+this.random()*.10;
      if(bot.burstShots<=0){
       bot.cooldown=(suppressing?.75:1.35)+this.random()*(suppressing?.35:.85)+bot.index*.08;
      }
     }
    }

    bot.flankCooldown=Math.max(0,bot.flankCooldown-dt);
    if(!bot.inCover&&bot.squadRole!=='suppress'&&bot.flankCooldown<=0&&distance>7&&distance<24&&this.random()<dt*.22){
     this.setState(bot,STATES.FLANK);
     break;
    }
    if(!bot.inCover&&bot.health<55&&this.random()<dt*.16)this.setState(bot,STATES.TAKE_COVER);
    break;
   }
  }

  return movementSpeed;
 }

 update(dt){
  this.time+=dt;
  this.updateBotGrenades(dt);
  this.squadMemory=Math.max(0,this.squadMemory-dt);
  this.squadTick-=dt;
  for(const bot of this.bots)bot.sharedIntelAge+=dt;
  if(this.squadMemory>0&&this.squadTick<=0){this.squadTick=.8;this.coordinateSquad();}

  for(let i=this.effects.length-1;i>=0;i--){
   const effect=this.effects[i];
   effect.life-=dt;
   if(effect.life<=0){
    this.scene.remove(effect.line);
    effect.line.geometry.dispose();
    effect.line.material.dispose();
    this.effects.splice(i,1);
   }
  }

  for(let i=this.soundEvents.length-1;i>=0;i--){
   this.soundEvents[i].life-=dt;
   if(this.soundEvents[i].life<=0)this.soundEvents.splice(i,1);
  }

  for(const bot of this.bots){
   if(!bot.alive){
    bot.respawn-=dt;
    if(bot.respawn<=0){
     bot.alive=true;
     bot.health=90;
     bot.group.visible=true;
     bot.group.position.copy(bot.spawn);
     bot.bar.scale.x=1;
     bot.bar.position.x=0;
     bot.cooldown=1.7+bot.index*.3;
     bot.hitTime=0;
     bot.state=STATES.PATROL;
     bot.stateTime=0;
     bot.target=null;
     bot.lastKnownTarget=null;
     bot.investigatePoint=null;
     bot.coverPoint=null;
     bot.coverAnchor=null;
     bot.inCover=false;
     bot.crouching=false;
     bot.flankPoint=null;
     bot.flankCooldown=2.5+bot.index*.8;
     bot.grenades=1;
     bot.grenadeCooldown=3.5+bot.index*.8;
     bot.evadePoint=null;
     bot.evadeTimer=0;
     bot.blockedWallId=null;
     bot.preparingGrenade=false;
     bot.grenadePrepTimer=0;
     bot.grenadeTarget=null;
     bot.grenadeDirection=null;
     if(bot.heldGrenade)bot.heldGrenade.visible=false;
     bot.avatar.gun.visible=true;
     bot.squadRole='support';
     bot.sharedIntelAge=999;
     bot.lastKnownAge=999;
     bot.lostSightTime=0;
    }
    continue;
   }

   this.updatePerception(bot,dt);
   const movementSpeed=this.updateState(bot,dt);

   bot.group.position.y=this.terrainHeight(bot.group.position.x,bot.group.position.z);
   bot.avatar.update(dt,{
    speed:movementSpeed,
    grounded:true,
    armed:!bot.preparingGrenade,
    aiming:!bot.preparingGrenade&&bot.state===STATES.ATTACK&&!bot.crouching,
    sprinting:movementSpeed>bot.moveSpeed*1.15,
    crouching:bot.crouching,
    covering:bot.inCover&&bot.crouching,
    coverSide:bot.peekSide
   });

   bot.hitTime=Math.max(0,bot.hitTime-dt);
   bot.flashTime=Math.max(0,bot.flashTime-dt);
   bot.avatar.materials.fabric.emissive.setHex(bot.hitTime>0?0x6b1e17:0);
   bot.avatar.flash.visible=bot.flashTime>0;
   if(this.camera)bot.bars.lookAt(this.camera.position);
  }
 }
}

CombatBotSystem.STATES=STATES;
window.CombatBotSystem=CombatBotSystem;
})();
