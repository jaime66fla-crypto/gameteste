/* Visible remote operators. Shared rig geometry/textures stay owned by OperatorAvatar. */
(()=>{'use strict';
class MultiplayerWorld{
 constructor(scene){this.scene=scene;this.players=new Map();this.effects=[];}
 receive(state){
  if(!state?.id||![state.x,state.y,state.z,state.angle].every(Number.isFinite))return;
  let remote=this.players.get(state.id);
  if(!remote){const avatar=new window.OperatorAvatar({team:'red'});remote={avatar,state,weapon:null,flashTime:0};avatar.group.position.set(state.x,state.y,state.z);avatar.group.rotation.y=state.angle;avatar.body.userData.remoteId=state.id;this.scene.add(avatar.group);this.players.set(state.id,remote);}
  remote.state=state;
  if(remote.weapon!==state.weapon){
   for(const child of [...remote.avatar.gun.children])if(child!==remote.avatar.flash){remote.avatar.gun.remove(child);this.disposeObject(child,true);}
   if(state.weapon!=='none')remote.avatar.gun.add(window.WeaponLootSystem.createModel(state.weapon));
   remote.avatar.setWeapon(state.weapon==='none'?'pistol':state.weapon);remote.weapon=state.weapon;
  }
 }
 update(dt){for(const remote of this.players.values()){
  const a=remote.avatar,s=remote.state,k=1-Math.exp(-16*dt);
  if(a.group.position.distanceTo(new THREE.Vector3(s.x,s.y,s.z))>8)a.group.position.set(s.x,s.y,s.z);
  else a.group.position.lerp(new THREE.Vector3(s.x,s.y,s.z),k);
  a.group.rotation.y+=Math.atan2(Math.sin(s.angle-a.group.rotation.y),Math.cos(s.angle-a.group.rotation.y))*k;
  remote.flashTime=Math.max(0,remote.flashTime-dt);a.flash.visible=remote.flashTime>0;a.setRecoil((a.recoil||0)*Math.exp(-15*dt));
  a.update(dt,{speed:s.moving?(s.running?11:5):0,armed:s.weapon!=='none',aiming:s.aiming,sprinting:s.running,grounded:s.grounded,verticalVelocity:s.verticalVelocity,crouching:s.crouching});
 }
 for(let i=this.effects.length-1;i>=0;i--){const e=this.effects[i];e.life-=dt;if(e.life<=0){this.scene.remove(e.line);e.line.geometry.dispose();e.line.material.dispose();this.effects.splice(i,1);}}
 }
 shot(data){
  const remote=this.players.get(data.ownerId);if(remote){remote.avatar.setRecoil(.5);remote.avatar.flash.visible=true;remote.flashTime=.06;}
  for(const ray of data.rays||[]){
   const start=new THREE.Vector3(data.origin.x,data.origin.y,data.origin.z),direction=new THREE.Vector3(ray.x,ray.y,ray.z);
   const range=window.WeaponLootSystem.DEFINITIONS[data.weapon]?.range||65;
   const caster=new THREE.Raycaster(start,direction,0,range);const hit=window.CombatBotSystem.firstHit(this.scene,caster,remote?.avatar.group);
   const end=hit?.point||start.clone().addScaledVector(direction,range);
   const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints([start,end]),new THREE.LineBasicMaterial({color:0xffb56a}));line.userData.ignoreCombat=true;this.scene.add(line);this.effects.push({line,life:.07});
  }
 }
 remove(id){const remote=this.players.get(id);if(!remote)return;const a=remote.avatar;this.scene.remove(a.group);this.disposeObject(a.gun,true);for(const material of a.body.material)material.dispose();a.hitSurface.material.dispose();a.skeleton.dispose();this.players.delete(id);}
 disposeObject(object,geometry){const mats=new Set(),geos=new Set();object.traverse(o=>{if(o.geometry)geos.add(o.geometry);for(const m of (Array.isArray(o.material)?o.material:[o.material]))if(m)mats.add(m)});for(const m of mats)m.dispose();if(geometry)for(const g of geos)g.dispose();}
 clear(){for(const id of [...this.players.keys()])this.remove(id);for(const e of this.effects){this.scene.remove(e.line);e.line.geometry.dispose();e.line.material.dispose()}this.effects=[];}
}
window.MultiplayerWorld=MultiplayerWorld;
})();
