/* First drivable vehicle — local prototype, inspired by the supplied 3D arcade driving demo.
   No multiplayer authority is claimed; vehicle interaction is disabled in network rooms. */
(()=>{
'use strict';
class FirstVehicleSystem {
 constructor({THREE,scene,camera,player,controller,terrainHeight,solidBoxes,isTraining,isMultiplayer,isActive,isDead}){
  Object.assign(this,{T:THREE,scene,camera,player,controller,terrainHeight,solidBoxes,isTraining,isMultiplayer,isActive,isDead});
  this.driving=false;this.speed=0;this.steer=0;this.yaw=0;this.wasTraining=false;
  this.keys=new Set();this.wheels=[];this.root=new THREE.Group();
  this.root.name='Jaime_First_Drivable_SUV';scene.add(this.root);
  this.build();
  this.root.position.set(-7,terrainHeight(-7,-12),-12);this.root.rotation.y=0;
  this.hud=document.createElement('div');this.hud.id='jaimeVehicleHud';
  this.hud.hidden=true;
  this.hud.style.cssText='position:fixed;right:14px;bottom:110px;z-index:35;padding:12px 17px;border:1px solid #f3ca7c88;background:#101d29ed;border-radius:12px;color:#e7f4ff;font:700 12px system-ui;box-shadow:0 10px 26px #0008;pointer-events:none';
  this.hud.innerHTML='<strong style="color:#ffd28a">SUV · PRIMEIRO CARRO</strong><div style="font-size:24px;margin:4px 0"><span id="vehicleSpeed">0</span> <small style="font-size:11px">km/h</small></div><small>W/S acelerar / ré · A/D direção<br>ESPAÇO freio · E sair</small>';
  document.body.append(this.hud);
  this.action=document.createElement('button');this.action.id='vehicleAction';this.action.hidden=true;
  this.action.style.cssText='position:fixed;z-index:36;bottom:175px;right:15px;background:#133b49ec;color:#ffe7b0;border:1px solid #ebc581;border-radius:10px;padding:12px 16px;font:800 12px system-ui;cursor:pointer;touch-action:manipulation';
  this.action.textContent='E · ENTRAR NO CARRO';document.body.append(this.action);
  this.action.addEventListener('click',()=>this.toggle());
  addEventListener('keydown',e=>{
   if(['KeyW','KeyS','KeyA','KeyD','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space'].includes(e.code)){
    this.keys.add(e.code);if(this.driving)e.preventDefault();
   }
   if(e.code==='KeyE'&&!e.repeat&&this.available()){
    if(this.driving||this.distance()<3.4){e.preventDefault();this.toggle();}
   }
  },true);
  addEventListener('keyup',e=>this.keys.delete(e.code),true);
  addEventListener('blur',()=>{this.keys.clear();this.speed=0});
 }
 build(){
  const T=this.T,metal=new T.MeshStandardMaterial({color:0x222a33,metalness:.65,roughness:.32}),
   glass=new T.MeshStandardMaterial({color:0x172b36,metalness:.27,roughness:.13}),
   trim=new T.MeshStandardMaterial({color:0x171c21,roughness:.8}),
   chrome=new T.MeshStandardMaterial({color:0xc1cbd0,metalness:.8,roughness:.21}),
   front=new T.MeshBasicMaterial({color:0xd9f3ff}),rear=new T.MeshBasicMaterial({color:0xed4945});
  const box=(w,h,d,x,y,z,mat,parent=this.root)=>{
   const o=new T.Mesh(new T.BoxGeometry(w,h,d),mat);o.position.set(x,y,z);o.castShadow=true;o.receiveShadow=true;parent.add(o);return o;
  };
  // Full-size five-door SUV proportions, wheels nested in individual steering pivots.
  box(2.13,.64,4.9,0,.81,0,metal);
  box(1.94,.53,2.76,0,1.40,-.24,metal);
  box(1.91,.09,2.40,0,1.73,-.28,metal);
  const frontGlass=box(1.78,.56,.07,0,1.41,1.06,glass);frontGlass.rotation.x=.30;
  const rearGlass=box(1.73,.47,.07,0,1.42,-1.55,glass);rearGlass.rotation.x=-.24;
  for(const x of [-.99,.99]){
   const side=box(.08,.42,2.35,x,1.40,-.25,glass);
   for(const z of [-.18,-1.28])box(.12,.55,.09,x,1.44,z,metal);
   box(.31,.17,.45,x*1.13,1.33,.60,metal);
   box(.47,.16,.10,x*.72,.95,2.48,front);
   box(.44,.20,.11,x*.72,.94,-2.48,rear);
   box(.14,.11,4.8,x,.50,0,trim);
  }
  box(1.20,.44,.12,0,.67,2.50,trim);
  for(const x of [-.38,-.19,0,.19,.38])box(.07,.35,.13,x,.70,2.58,chrome);
  box(2.10,.18,.25,0,.50,2.45,trim);box(2.10,.18,.25,0,.49,-2.45,trim);
  const wheelMat=new T.MeshStandardMaterial({color:0x141619,roughness:.95});
  for(const x of [-1.12,1.12])for(const z of [-1.62,1.60]){
   const steerPivot=new T.Group();steerPivot.position.set(x,.50,z);this.root.add(steerPivot);
   const spin=new T.Group();steerPivot.add(spin);
   const tire=new T.Mesh(new T.CylinderGeometry(.51,.51,.34,20),wheelMat);
   tire.rotation.z=Math.PI/2;spin.add(tire);tire.castShadow=true;
   const rim=new T.Mesh(new T.CylinderGeometry(.28,.28,.35,12),chrome);
   rim.rotation.z=Math.PI/2;spin.add(rim);
   this.wheels.push({steerPivot,spin,front:z>0});
  }
  const groundShadow=new T.Mesh(new T.PlaneGeometry(2.4,5.3),new T.MeshBasicMaterial({color:0x000000,transparent:true,opacity:.18,depthWrite:false}));
  groundShadow.rotation.x=-Math.PI/2;groundShadow.position.y=.025;this.root.add(groundShadow);
 }
 available(){return this.isActive()&&!this.isDead()&&!this.isMultiplayer();}
 distance(){return Math.hypot(this.player.position.x-this.root.position.x,this.player.position.z-this.root.position.z)}
 ground(x,z){
  if(this.isTraining()&&x>81&&x<129&&z>81&&z<129)return this.terrainHeight(105,105)+6;
  return this.terrainHeight(x,z);
 }
 relocate(){
  const training=this.isTraining();
  if(training!==this.wasTraining){
   if(this.driving)this.exit();
   this.wasTraining=training;this.speed=0;this.yaw=0;
   const x=training?91:-7,z=training?120:-12;
   this.root.position.set(x,this.ground(x,z),z);
   this.root.rotation.y=0;
  }
 }
 blocked(x,z){
  if(Math.abs(x)>145||Math.abs(z)>145)return true;
  if(this.isTraining()&&x>81&&x<129&&z>81&&z<129)return false;
  const p={x,z},radius=1.15;
  return this.solidBoxes.some(b=>p.x+radius>b.minX&&p.x-radius<b.maxX&&p.z+radius>b.minZ&&p.z-radius<b.maxZ&&b.maxY>this.ground(x,z)+.4);
 }
 toggle(){if(this.driving)this.exit();else this.enter()}
 enter(){
  if(!this.available()||this.distance()>3.4)return;
  this.driving=true;this.speed=0;this.steer=0;this.yaw=this.root.rotation.y;
  this.controller.cover.exit();this.controller.clearInput();
  this.controller.velocity.set(0,0,0);this.controller.moveVelocity.set(0,0,0);
  this.player.visible=false;this.hud.hidden=false;this.action.textContent='E · SAIR DO CARRO';
 }
 exit(){
  if(!this.driving)return;
  this.driving=false;this.speed=0;this.keys.clear();
  const yaw=this.root.rotation.y;
  let x=this.root.position.x+Math.cos(yaw)*3.3,z=this.root.position.z-Math.sin(yaw)*3.3;
  if(this.blocked(x,z)){x=this.root.position.x-Math.cos(yaw)*3.3;z=this.root.position.z+Math.sin(yaw)*3.3;}
  this.player.position.set(x,this.ground(x,z),z);
  this.player.visible=true;this.controller.clearInput();this.controller.velocity.set(0,0,0);this.controller.moveVelocity.set(0,0,0);this.controller.isGrounded=true;
  this.hud.hidden=true;this.action.textContent='E · ENTRAR NO CARRO';
 }
 update(dt){
  this.relocate();
  if(!this.available()&&!this.driving){this.action.hidden=true;return false;}
  if(!this.driving){
   this.action.hidden=this.distance()>=3.4;
   return false;
  }
  const k=(...codes)=>codes.some(code=>this.keys.has(code)),d=Math.min(dt,.05),factor=d*60;
  if(k('KeyW','ArrowUp'))this.speed+=.023*factor;
  else if(k('KeyS','ArrowDown'))this.speed-=this.speed>.04?.045*factor:.017*factor;
  else this.speed*=Math.pow(.984,factor);
  this.speed=this.T.MathUtils.clamp(this.speed,-.34,.82);
  if(k('Space'))this.speed*=Math.pow(.91,factor);
  const turn=(k('KeyA','ArrowLeft')?1:0)-(k('KeyD','ArrowRight')?1:0);
  this.steer=this.T.MathUtils.lerp(this.steer,turn*.50,1-Math.exp(-6*d));
  if(Math.abs(this.speed)>.015)this.yaw+=this.steer*this.speed*.045*factor;
  const nx=this.root.position.x+Math.sin(this.yaw)*this.speed*factor,nz=this.root.position.z+Math.cos(this.yaw)*this.speed*factor;
  if(this.blocked(nx,nz)){this.speed=0}else{this.root.position.x=nx;this.root.position.z=nz}
  this.root.position.y=this.ground(this.root.position.x,this.root.position.z);
  this.root.rotation.y=this.yaw;
  for(const w of this.wheels){if(w.front)w.steerPivot.rotation.y=this.steer;w.spin.rotation.x+=this.speed*factor/.5}
  this.player.position.set(this.root.position.x,this.root.position.y,this.root.position.z);
  this.controller.velocity.set(0,0,0);this.controller.moveVelocity.set(0,0,0);
  const cp=new this.T.Vector3(this.root.position.x-Math.sin(this.yaw)*9,this.root.position.y+4.4,this.root.position.z-Math.cos(this.yaw)*9);
  this.camera.position.lerp(cp,1-Math.exp(-7*d));
  this.camera.lookAt(this.root.position.x,this.root.position.y+1.4,this.root.position.z);
  this.hud.querySelector('#vehicleSpeed').textContent=String(Math.round(Math.abs(this.speed)*145));
  this.action.hidden=false;
  return true;
 }
 reset(){
  if(this.driving)this.exit();
  this.wasTraining=!this.isTraining();this.relocate();
 }
}
window.FirstVehicleSystem=FirstVehicleSystem;
})();