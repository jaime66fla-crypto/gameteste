/* Original procedural grenade/ice visuals and local/authoritative-online equipment. */
(()=>{'use strict';
const R=globalThis.TacticalRules,vector=p=>new THREE.Vector3(p.x,p.y,p.z),clone=x=>JSON.parse(JSON.stringify(x));
function dispose(root){const geometry=new Set(),materials=new Set();root.traverse(o=>{if(o.geometry)geometry.add(o.geometry);if(o.material)for(const m of Array.isArray(o.material)?o.material:[o.material])materials.add(m);});for(const g of geometry)g.dispose();for(const m of materials)m.dispose();}
function grenadeModel(){
 const g=new THREE.Group(),body=new THREE.MeshStandardMaterial({color:0x657649,roughness:.65,metalness:.35}),steel=new THREE.MeshStandardMaterial({color:0x343d3a,roughness:.36,metalness:.7});
 const shell=new THREE.Mesh(new THREE.SphereGeometry(.11,10,8),body);shell.scale.y=1.2;g.add(shell);
 const band=new THREE.Mesh(new THREE.CylinderGeometry(.113,.113,.045,10),steel);g.add(band);
 const cap=new THREE.Mesh(new THREE.BoxGeometry(.055,.06,.05),steel);cap.position.y=.14;g.add(cap);
 const lever=new THREE.Mesh(new THREE.BoxGeometry(.025,.16,.045),steel);lever.position.set(.07,.07,0);lever.rotation.z=.25;g.add(lever);
 const pin=new THREE.Mesh(new THREE.TorusGeometry(.035,.008,5,10),steel);pin.position.set(-.045,.15,0);g.add(pin);g.traverse(o=>{if(o.isMesh)o.castShadow=true;});return g;
}
class TacticalGear{
 constructor({scene,player,camera,hand,boxes=()=>[],terrainHeight=R.terrain,canAct=()=>true,online=()=>false,send=()=>false,targets=()=>[],onEquip=()=>{},onEffect=()=>{},notify=()=>{}}){
  Object.assign(this,{scene,player,camera,hand,boxes,terrainHeight,canAct,online,send,targets,onEquip,onEffect,notify});
  this.inventory={grenades:R.CONFIG.grenades,ice:R.CONFIG.ice};this.active=null;this.preparing=false;this.cooldown=0;this.serial=0;this.grenades=new Map();this.walls=new Map();this.effects=[];
  this.held=grenadeModel();this.held.position.set(.035,.015,.04);this.held.visible=false;hand.add(this.held);
  this.preview=new THREE.Line(new THREE.BufferGeometry(),new THREE.LineDashedMaterial({color:0x91f3e3,dashSize:.28,gapSize:.12,transparent:true,opacity:.9}));this.preview.visible=false;this.preview.userData.ignoreCombat=true;this.preview.userData.ignoreCamera=true;scene.add(this.preview);
 }
 direction(){return this.camera.getWorldDirection(new THREE.Vector3()).normalize();}
 equipGrenade(){if(!this.canAct())return false;if(this.inventory.grenades<=0){this.notify('Sem granadas');return false;}this.onEquip();this.active='grenade';this.held.visible=true;return true;}
 unequip(){this.active=null;this.cancelThrow();this.held.visible=false;}
 cancelThrow(){this.preparing=false;this.preview.visible=false;}
 beginThrow(){if(!this.canAct()||this.active!=='grenade'||this.inventory.grenades<=0||this.cooldown>0)return false;this.preparing=true;return true;}
 endThrow(){if(!this.preparing)return false;this.cancelThrow();if(!this.canAct()||this.active!=='grenade'||this.inventory.grenades<=0||this.cooldown>0)return false;
  const direction=this.direction();this.cooldown=.65;
  if(this.online())return this.send({type:'gear3d',kind:'grenade',direction:{x:direction.x,y:direction.y,z:direction.z}})!==false;
  const state=R.grenade('local-g-'+(++this.serial),'self',this.player.position,direction,Date.now());if(!state)return false;
  this.inventory.grenades--;this.addGrenade(state);if(!this.inventory.grenades)this.unequip();return true;
 }
 deployIce(){if(!this.canAct()||this.cooldown>0)return false;if(this.inventory.ice<=0){this.notify('Sem cargas de gelo');return false;}
  const direction=this.direction(),people=this.targets().map(t=>t.position);
  const state=R.iceWall('local-i-'+(++this.serial),'self',this.player.position,direction,Date.now(),this.boxes(),people,this.terrainHeight);
  if(!state){this.notify('Sem espaço para criar o gelo');return false;}
  this.cooldown=.45;if(this.online())return this.send({type:'gear3d',kind:'ice',direction:{x:direction.x,y:direction.y,z:direction.z}})!==false;
  this.inventory.ice--;this.addWall(state);return true;
 }
 addGrenade(state){if(this.grenades.has(state.id))return;const copy=clone(state),mesh=grenadeModel();mesh.userData.ignoreCombat=true;mesh.userData.ignoreCamera=true;mesh.position.copy(vector(copy.position));this.scene.add(mesh);this.grenades.set(state.id,{state:copy,mesh});}
 addWall(state){
  if(this.walls.has(state.id)){const wall=this.walls.get(state.id);wall.state.health=state.health;wall.bar.scale.x=Math.max(.01,state.health/R.CONFIG.iceHealth);for(const m of wall.iceMaterials)m.color.setHex(state.health<90?0x77bacb:0xb9ecf7);return;}
  const copy=clone(state),group=new THREE.Group(),iceMaterials=[];
  for(let i=0;i<copy.boxes.length;i++){
   const b=copy.boxes[i],h=b.maxY-b.minY,material=new THREE.MeshStandardMaterial({color:i%2?0x99d9ed:0xc2f0fa,roughness:.24,metalness:.12,flatShading:true,emissive:0x123943,emissiveIntensity:.24});iceMaterials.push(material);
   const block=new THREE.Mesh(new THREE.BoxGeometry(b.maxX-b.minX,h,b.maxZ-b.minZ),material);block.position.set((b.minX+b.maxX)/2,b.minY+h/2,(b.minZ+b.maxZ)/2);block.userData.iceWallId=copy.id;block.castShadow=true;block.receiveShadow=true;group.add(block);
   const edges=new THREE.LineSegments(new THREE.EdgesGeometry(block.geometry),new THREE.LineBasicMaterial({color:0xe8ffff,transparent:true,opacity:.65}));edges.position.copy(block.position);edges.userData.ignoreCombat=true;group.add(edges);
   const crystal=new THREE.Mesh(new THREE.ConeGeometry(.28,.5,5),material);crystal.position.set(block.position.x,b.maxY-.2,block.position.z);crystal.userData.iceWallId=copy.id;group.add(crystal);
  }
  const bar=new THREE.Mesh(new THREE.BoxGeometry(1.2,.045,.03),new THREE.MeshBasicMaterial({color:0x85f8ef}));bar.position.copy(vector(copy.position)).add(new THREE.Vector3(0,2.8,0));bar.userData.ignoreCombat=true;bar.userData.ignoreCamera=true;group.add(bar);
  const colliders=copy.boxes.map(b=>({...b}));this.boxes().push(...colliders);this.scene.add(group);this.walls.set(copy.id,{state:copy,group,colliders,iceMaterials,bar});this.onEffect('ice',copy.position);
 }
 removeWall(id){const wall=this.walls.get(id);if(!wall)return;this.walls.delete(id);const boxes=this.boxes();for(const b of wall.colliders){const i=boxes.indexOf(b);if(i>=0)boxes.splice(i,1);}this.scene.remove(wall.group);dispose(wall.group);}
 damageWall(id,damage){if(this.online())return;const wall=this.walls.get(id);if(!wall||!Number.isFinite(damage)||damage<=0)return;wall.state.health=Math.max(0,wall.state.health-damage);if(!wall.state.health){this.onEffect('icebreak',wall.state.position);this.removeWall(id);}else this.addWall(wall.state);}
 removeGrenade(id){const grenade=this.grenades.get(id);if(!grenade)return;this.scene.remove(grenade.mesh);dispose(grenade.mesh);this.grenades.delete(id);}
 explosion(id,position,applyDamage){
  this.removeGrenade(id);
  if(applyDamage){
   const blockers=[...this.boxes()];for(const target of this.targets()){const damage=R.blastDamage(position,target.position,blockers);if(damage>0)target.damage(damage);}
   for(const wall of [...this.walls.values()]){const damage=R.blastDamage(position,wall.state.position,blockers.filter(b=>b.iceWallId!==wall.state.id));this.damageWall(wall.state.id,damage*2.5);}
  }
  const group=new THREE.Group();group.userData.ignoreCombat=true;group.userData.ignoreCamera=true;group.position.copy(vector(position));
  const glow=new THREE.Mesh(new THREE.SphereGeometry(1,12,8),new THREE.MeshBasicMaterial({color:0xffb45c,transparent:true,opacity:.7,depthWrite:false}));group.add(glow);
  const ring=new THREE.Mesh(new THREE.TorusGeometry(1,.045,5,36),new THREE.MeshBasicMaterial({color:0xffdb92,transparent:true,opacity:.9,depthWrite:false}));ring.rotation.x=Math.PI/2;group.add(ring);
  this.scene.add(group);this.effects.push({group,age:0});this.onEffect('explosion',position);
 }
 receive(data){
  if(data.type==='grenade3d')this.addGrenade(data.grenade);
  else if(data.type==='icewall3d')this.addWall(data.wall);
  else if(data.type==='icewall-remove3d'){const wall=this.walls.get(data.id);if(wall&&data.destroyed)this.onEffect('icebreak',wall.state.position);this.removeWall(data.id);}
  else if(data.type==='explosion3d')this.explosion(data.id,data.position,false);
  else if(data.type==='inventory3d'){this.inventory={grenades:data.grenades,ice:data.ice};if(data.message)this.notify(data.message);if(!data.grenades)this.unequip();}
 }
 snapshot(data={}){this.clear();this.resetInventory();for(const g of data.grenades||[])this.addGrenade(g);for(const w of data.walls||[])this.addWall(w);}
 resetInventory(){this.inventory={grenades:R.CONFIG.grenades,ice:R.CONFIG.ice};this.cooldown=0;this.unequip();}
 update(dt){
  this.cooldown=Math.max(0,this.cooldown-dt);if(!this.canAct())this.cancelThrow();this.held.visible=this.active==='grenade'&&this.canAct();
  if(this.preparing){
   const g=R.grenade('preview','self',this.player.position,this.direction(),Date.now()),points=[vector(g.position)];for(let i=0;i<36;i++){R.advance(g,R.CONFIG.fuse/36,this.boxes(),this.terrainHeight);points.push(vector(g.position));}
   this.preview.geometry.dispose();this.preview.geometry=new THREE.BufferGeometry().setFromPoints(points);this.preview.computeLineDistances();this.preview.visible=true;
  }
  for(const g of [...this.grenades.values()]){R.advance(g.state,dt,this.boxes(),this.terrainHeight);g.mesh.position.copy(vector(g.state.position));g.mesh.rotation.x+=dt*7;g.mesh.rotation.z+=dt*4;if(R.expired(g.state)){if(!this.online())this.explosion(g.state.id,g.state.position,true);else g.mesh.visible=false;}}
  if(!this.online())for(const wall of [...this.walls.values()])if(Date.now()>=wall.state.expiresAt)this.removeWall(wall.state.id);
  for(let i=this.effects.length-1;i>=0;i--){const effect=this.effects[i];effect.age+=dt;if(effect.age>.6){this.scene.remove(effect.group);dispose(effect.group);this.effects.splice(i,1);}else{effect.group.scale.setScalar(.3+effect.age*8);effect.group.traverse(o=>{if(o.material)o.material.opacity=Math.max(0,1-effect.age/.6);});}}
 }
 clear(){this.unequip();for(const id of [...this.walls.keys()])this.removeWall(id);for(const id of [...this.grenades.keys()])this.removeGrenade(id);for(const e of this.effects){this.scene.remove(e.group);dispose(e.group);}this.effects=[];}
}
TacticalGear.grenadeModel=grenadeModel;window.TacticalGear=TacticalGear;
})();
