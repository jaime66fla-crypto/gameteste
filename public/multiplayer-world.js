/* Visible remote operators. Shared rig geometry/textures stay owned by OperatorAvatar. */
(()=>{'use strict';
class MultiplayerWorld{
 constructor(scene,terrainHeight=()=>0,audio=null){this.scene=scene;this.terrainHeight=terrainHeight;this.audio=audio;this.players=new Map();this.effects=[];this._position=new THREE.Vector3();this._listener=new THREE.Vector3();}
 _buildRemoteJetpack(){
  const g=new THREE.Group();g.name='REMOTE_SPECIAL_JETPACK';
  const dark=new THREE.MeshStandardMaterial({color:0x22282a,metalness:.55,roughness:.42});
  const panel=new THREE.MeshStandardMaterial({color:0x3c4243,metalness:.35,roughness:.5});
  const gold=new THREE.MeshStandardMaterial({color:0xe59b21,emissive:0x5b2a00,emissiveIntensity:.45,metalness:.5,roughness:.35});
  const body=new THREE.Mesh(new THREE.BoxGeometry(.52,.58,.22),panel);body.castShadow=true;g.add(body);
  const handle=new THREE.Mesh(new THREE.TorusGeometry(.16,.035,6,16,Math.PI),dark);handle.rotation.z=Math.PI;handle.position.set(0,.37,0);g.add(handle);
  g.userData.flames=[];
  for(const sx of [-.38,.38]){
   const tank=new THREE.Mesh(new THREE.CylinderGeometry(.13,.16,.58,12),dark);tank.position.set(sx,0,0);tank.castShadow=true;g.add(tank);
   const band=new THREE.Mesh(new THREE.CylinderGeometry(.145,.145,.08,12),gold);band.position.set(sx,.10,0);g.add(band);
   const nozzle=new THREE.Mesh(new THREE.CylinderGeometry(.11,.075,.18,12),dark);nozzle.position.set(sx,-.36,0);g.add(nozzle);
   const flame=new THREE.Mesh(new THREE.ConeGeometry(.09,.46,10),new THREE.MeshBasicMaterial({color:0xffb12b,transparent:true,opacity:0}));
   flame.position.set(sx,-.66,0);flame.rotation.z=Math.PI;g.add(flame);g.userData.flames.push(flame);
  }
  const emblem=new THREE.Mesh(new THREE.BoxGeometry(.26,.07,.235),gold);emblem.position.set(0,.02,.02);g.add(emblem);
  g.scale.setScalar(.72);g.position.set(0,1.28,-.34);
  return g;
 }
 receive(state){
  if(!state?.id||![state.x,state.y,state.z,state.angle].every(Number.isFinite))return;
  let remote=this.players.get(state.id);
  if(!remote){const avatar=new window.OperatorAvatar({team:'red'});remote={avatar,state,weapon:null,gear:null,attachmentsKey:'',jetpack:null,flashTime:0};avatar.group.position.set(state.x,state.y,state.z);avatar.group.rotation.y=state.angle;avatar.body.userData.remoteId=state.id;this.scene.add(avatar.group);this.players.set(state.id,remote);}
  remote.state=state;
  const soldierSkin=state.soldierSkin||'original';
  if(remote.soldierSkin!==soldierSkin){
   window.GameSkins?.tintAvatar(remote.avatar,soldierSkin);
   remote.soldierSkin=soldierSkin;
  }
  const attachments=state.attachments&&typeof state.attachments==='object'?state.attachments:{};
  const attachmentsKey=['optic','suppressor','extended','grip','stock'].filter(key=>attachments[key]).join(',');
  if(remote.weapon!==state.weapon||remote.gear!==state.gear||remote.attachmentsKey!==attachmentsKey||remote.weaponSkin!==state.weaponSkin){
   for(const child of [...remote.avatar.gun.children])if(child!==remote.avatar.flash){remote.avatar.gun.remove(child);this.disposeObject(child,true);}
   if(state.gear==='grenade')remote.avatar.gun.add(window.TacticalGear.grenadeModel());
   else if(state.weapon!=='none'){
    const model=window.WeaponLootSystem.createModel(state.weapon);
    window.WeaponLootSystem.applyAccessoryVisuals?.(model,state.weapon,attachments);
    window.GameSkins?.paintWeapon(model,state.weapon,state.weaponSkin||'original');
    remote.avatar.gun.add(model);
   }
   remote.avatar.setWeapon(state.weapon==='none'?'pistol':state.weapon);remote.weapon=state.weapon;remote.gear=state.gear;remote.attachmentsKey=attachmentsKey;remote.weaponSkin=state.weaponSkin;
  }
  if(!!state.jetpack!==!!remote.jetpack){
   if(state.jetpack){remote.jetpack=this._buildRemoteJetpack();remote.avatar.group.add(remote.jetpack);}
   else if(remote.jetpack){remote.avatar.group.remove(remote.jetpack);this.disposeObject(remote.jetpack,true);remote.jetpack=null;}
  }
 }
 update(dt){for(const remote of this.players.values()){
  const a=remote.avatar,s=remote.state,k=1-Math.exp(-16*dt);
  const y=s.dead?this.terrainHeight(s.x,s.z,s.y):s.y;
  this._position.set(s.x,y,s.z);
  if(a.group.position.distanceToSquared(this._position)>64)a.group.position.copy(this._position);
  else a.group.position.lerp(this._position,k);
  a.group.rotation.y+=Math.atan2(Math.sin(s.angle-a.group.rotation.y),Math.cos(s.angle-a.group.rotation.y))*k;
  remote.flashTime=Math.max(0,remote.flashTime-dt);a.flash.visible=remote.flashTime>0;a.setRecoil((a.recoil||0)*Math.exp(-15*dt));
  if(remote.jetpack){
   remote.jetpack.visible=!s.dead;
   for(const flame of remote.jetpack.userData.flames||[]){
    const active=!!s.jetpackActive&&!s.dead;
    flame.material.opacity=THREE.MathUtils.lerp(flame.material.opacity,active?.95:0,1-Math.exp(-dt*16));
    flame.scale.y=active?.75+Math.random()*.45:.2;
   }
  }
  const att=s.attachments&&typeof s.attachments==='object'?s.attachments:{};
  // Distant characters retain smooth movement but update their skeletal pose at a lower rate.
  const listener=this.audio?.listenerPosition?.();
  const far=listener&&a.group.position.distanceToSquared(listener)>55*55;
  remote.poseTime=(remote.poseTime||0)+dt;
  if(far&&remote.poseTime<.045)continue;
  const poseDt=Math.min(remote.poseTime,.05);remote.poseTime=0;
  a.update(poseDt,{dead:!!s.dead,speed:s.moving?(s.running?11:5):0,armed:s.weapon!=='none'||s.gear==='grenade',aiming:s.aiming,sprinting:s.running,grounded:s.grounded,verticalVelocity:s.verticalVelocity,crouching:s.crouching,optic:!!att.optic,stock:!!att.stock,suppressed:!!att.suppressor});
 }
 for(let i=this.effects.length-1;i>=0;i--){const e=this.effects[i];e.life-=dt;if(e.life<=0){this.scene.remove(e.line);e.line.geometry.dispose();e.line.material.dispose();this.effects.splice(i,1);}}
 }
 shot(data){
  const remote=this.players.get(data.ownerId);
  const attachments=data.attachments&&typeof data.attachments==='object'?data.attachments:(remote?.state?.attachments||{});
  const suppressed=!!attachments.suppressor;
  const stock=!!attachments.stock;
  if(remote){
   remote.avatar.setRecoil(stock?.36:.5);
   remote.avatar.flash.visible=!suppressed;
   remote.flashTime=suppressed?0:.06;
  }
  if(this.audio?.playShoot){
   const distance=remote?.avatar?.group?.position?.distanceTo?.(this.audio.listenerPosition?.()||new THREE.Vector3())??0;
   const attenuation=Math.max(.18,1/(1+distance*.055));
   this.audio.playShoot(data.weapon,(suppressed?.26:1)*attenuation);
  }
  for(const ray of (data.rays||[]).slice(0,6)){
   const start=new THREE.Vector3(data.origin.x,data.origin.y,data.origin.z),direction=new THREE.Vector3(ray.x,ray.y,ray.z);
   const range=window.WeaponLootSystem.DEFINITIONS[data.weapon]?.range||65;
   const caster=new THREE.Raycaster(start,direction,0,range);const hit=window.CombatBotSystem.firstHit(this.scene,caster,remote?.avatar.group);
   const end=hit?.point||start.clone().addScaledVector(direction,range);
   const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints([start,end]),new THREE.LineBasicMaterial({color:suppressed?0xd8c38a:0xffb56a,transparent:true,opacity:suppressed?.45:1}));line.userData.ignoreCombat=true;this.scene.add(line);this.effects.push({line,life:suppressed?.04:.07});
   if(this.effects.length>36){const old=this.effects.shift();this.scene.remove(old.line);old.line.geometry.dispose();old.line.material.dispose();}
  }
 }
 remove(id){const remote=this.players.get(id);if(!remote)return;const a=remote.avatar;this.scene.remove(a.group);this.disposeObject(a.gun,true);for(const material of a.body.material)material.dispose();a.hitSurface.material.dispose();a.skeleton.dispose();this.players.delete(id);}
 disposeObject(object,geometry){const mats=new Set(),geos=new Set();object.traverse(o=>{if(o.geometry)geos.add(o.geometry);for(const m of (Array.isArray(o.material)?o.material:[o.material]))if(m)mats.add(m)});for(const m of mats)m.dispose();if(geometry)for(const g of geos)g.dispose();}
 clear(){for(const id of [...this.players.keys()])this.remove(id);for(const e of this.effects){this.scene.remove(e.line);e.line.geometry.dispose();e.line.material.dispose()}this.effects=[];}
}
window.MultiplayerWorld=MultiplayerWorld;
})();
