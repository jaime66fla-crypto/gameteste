/* Server-owned tactical inventory and world. Persisted with the room's existing DO storage. */
(()=>{'use strict';
const R=globalThis.TacticalRules;
class TacticalRoom{
 constructor(room,ctx){
  this.room=room;this.ctx=ctx;this.grenades=new Map();this.walls=new Map();this.staticBoxes=R.mapBoxes();
  if(ctx.blockConcurrencyWhile)ctx.blockConcurrencyWhile(async()=>{const saved=await ctx.storage.get('tactical-world');if(saved){for(const g of saved.grenades||[])this.grenades.set(g.id,g);for(const w of saved.walls||[])this.walls.set(w.id,w);}});
 }
 snapshot(){return {grenades:[...this.grenades.values()],walls:[...this.walls.values()]};}
 save(){this.ctx.waitUntil(this.ctx.storage.put('tactical-world',this.snapshot()));}
 boxes(){return this.staticBoxes.concat(...[...this.walls.values()].map(w=>w.boxes));}
 inventory(player,message){try{this.room.sessions.get(player.id)?.send(JSON.stringify({type:'inventory3d',grenades:player.grenades??3,ice:player.iceCharges??3,...(message?{message}:{})}));}catch{}}
 use(ws,player,data){
  const now=Date.now(),d=data.direction,length=d&&Math.hypot(d.x,d.y,d.z);
  if(!d||![d.x,d.y,d.z].every(Number.isFinite)||length<.5||length>1.5)return;
  if(now-(player.lastGearAt||0)<450)return;
  const id=crypto.randomUUID().slice(0,24);let event;
  if(data.kind==='grenade'){
   if(player.grenades<=0||this.grenades.size>=32){this.inventory(player,'Sem granadas disponíveis');return;}
   const grenade=R.grenade(id,player.id,player,d,now);if(!grenade)return;this.grenades.set(id,grenade);player.grenades--;event={type:'grenade3d',grenade};
  }else if(data.kind==='ice'){
   if(player.iceCharges<=0||this.walls.size>=32){this.inventory(player,'Sem cargas de gelo disponíveis');return;}
   const wall=R.iceWall(id,player.id,player,d,now,this.boxes(),[...this.room.players.values()].filter(p=>!p.dead));
   if(!wall){this.inventory(player,'Sem espaço para criar o gelo');return;}
   this.walls.set(id,wall);player.iceCharges--;event={type:'icewall3d',wall};
  }else return;
  player.lastGearAt=now;this.room.save3D(player.id);this.save();this.inventory(player);this.room.broadcast3D(event);this.room.scheduleRespawns();
 }
 originBlocked(player,origin){return R.blocked({x:player.x,y:player.y+1.3,z:player.z},origin,this.boxes());}
 shoot(shot,spec){
  const stops=[];
  for(const ray of shot.rays){const hit=R.firstSolid(shot.origin,ray,this.boxes(),spec.range);stops.push(hit?hit.distance:null);if(hit?.box.iceWallId)this.damageWall(hit.box.iceWallId,spec.damage);}
  return stops;
 }
 damageWall(id,amount){
  const wall=this.walls.get(id);if(!wall)return;wall.health=Math.max(0,wall.health-amount);
  if(wall.health<=0){this.walls.delete(id);this.room.broadcast3D({type:'icewall-remove3d',id,destroyed:true});}
  else this.room.broadcast3D({type:'icewall3d',wall});this.save();
 }
 explode(grenade,now){
  this.grenades.delete(grenade.id);const blockers=this.boxes(),owner=this.room.players.get(grenade.ownerId);
  this.room.broadcast3D({type:'explosion3d',id:grenade.id,position:grenade.position});
  for(const target of this.room.players.values()){
   if(target.dead)continue;const damage=R.blastDamage(grenade.position,target,blockers);if(!damage)continue;
   target.health=Math.max(0,target.health-damage);const killed=target.health===0;
   if(killed){Object.assign(target,{dead:true,deadUntil:now+5000,moving:false,running:false,aiming:false,gear:'none',jetpack:false,jetpackActive:false});if(owner&&owner.id!==target.id){owner.kills++;this.room.save3D(owner.id);}}
   this.room.broadcast3D({type:'hit3d',kind:'grenade',shotId:'grenade-'+grenade.id,attackerId:grenade.ownerId,targetId:target.id,health:target.health,damage,killed,respawnIn:killed?5:0,kills:owner?.kills||0});this.room.save3D(target.id);this.room.broadcast3D(target);
  }
  for(const wall of [...this.walls.values()]){const damage=R.blastDamage(grenade.position,wall.position,blockers.filter(b=>b.iceWallId!==wall.id));if(damage)this.damageWall(wall.id,damage*2.5);}
  this.room.broadcastRanking();
 }
 nextAlarm(now){const times=[...this.walls.values()].map(w=>w.expiresAt);if(this.grenades.size)times.push(Math.min(now+75,...[...this.grenades.values()].map(g=>g.expiresAt)));return times.length?Math.min(...times):null;}
 async tick(now){
  let changed=false;const boxes=this.boxes();
  for(const grenade of [...this.grenades.values()]){R.advance(grenade,Math.max(0,(now-grenade.updatedAt)/1000),boxes);grenade.updatedAt=now;changed=true;if(now>=grenade.expiresAt||R.expired(grenade))this.explode(grenade,now);}
  for(const wall of [...this.walls.values()])if(now>=wall.expiresAt){this.walls.delete(wall.id);changed=true;this.room.broadcast3D({type:'icewall-remove3d',id:wall.id,destroyed:false});}
  if(changed)await this.ctx.storage.put('tactical-world',this.snapshot());
 }
}
globalThis.TacticalRoom=TacticalRoom;
})();
