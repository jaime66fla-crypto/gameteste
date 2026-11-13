/* Standalone practice zone: no modifications to battle royale maps or net protocol. */
(()=>{
'use strict';
const T=window.THREE;
if(!T||typeof scene==='undefined'||typeof player==='undefined')return;
const button=document.createElement('button');
button.id='btn-training-ground';
button.className='menu-btn';
button.textContent='ÁREA DE TESTES • SOLO';
document.getElementById('btn-menu-play')?.before(button);
const panel=document.createElement('div');
panel.id='training-hud';
panel.hidden=true;
panel.style.cssText='position:fixed;right:14px;top:145px;z-index:40;background:#091c24ed;border:1px solid #61c9d1;color:#eaffff;border-radius:12px;padding:12px;font:12px/1.6 system-ui;min-width:170px;box-shadow:0 8px 30px #0006';
panel.innerHTML='<strong>CAMPO DE TESTES MK-II</strong><div>Alvos acertados: <b id="training-score">0</b></div><div>WASD · Shift · Espaço · F · Q</div><button id="training-reset" type="button">REINICIAR POSIÇÃO</button> <button id="training-exit" type="button">SAIR</button>';
document.body.append(panel);
panel.querySelectorAll('button').forEach(b=>b.style.cssText='background:#21444d;color:white;border:1px solid #6cbdc3;border-radius:5px;padding:5px;margin-top:7px;cursor:pointer');
let active=false,created=false,score=0;
const x=105,z=105,half=22, floor=forestEnvironment.getTerrainHeight(x,z)+6;
const objects=[],targets=[];
const material=(color,metalness=0)=>new T.MeshStandardMaterial({color,roughness:.79,metalness});
const asphalt=material(0x293d42),yellow=material(0xfacb61),blue=material(0x4d7780),red=material(0xbd5452),white=material(0xcdd9d5),dark=material(0x1f3036);
function place(px,pz,w,h,d,y=0,m=blue,collide=false){
 const mesh=new T.Mesh(new T.BoxGeometry(w,h,d),m);
 mesh.position.set(x+px,floor+y+h/2,z+pz);
 mesh.castShadow=true;mesh.receiveShadow=true;
 scene.add(mesh);objects.push(mesh);
 if(collide)houseParkour.registerSolidBox(mesh,w,h,d);
 return mesh;
}
function label(text,px,pz,y=2.6){
 const c=document.createElement('canvas');c.width=512;c.height=96;
 const ctx=c.getContext('2d');
 ctx.fillStyle='#11282de8';ctx.fillRect(0,0,512,96);
 ctx.fillStyle='#b9f2ee';ctx.font='bold 40px Arial';ctx.textAlign='center';
 ctx.fillText(text,256,61);
 const tex=new T.CanvasTexture(c),mesh=new T.Mesh(new T.PlaneGeometry(5.8,1.1),new T.MeshBasicMaterial({map:tex,transparent:true,side:T.DoubleSide,depthWrite:false}));
 mesh.position.set(x+px,floor+y,z+pz);scene.add(mesh);objects.push(mesh);
}
function create(){
 if(created)return;created=true;
 // Separate raised platform creates a predictable, level test environment.
 place(0,0,46,.36,46,-.36,asphalt,true);
 for(const edge of [-22,22]){
  place(edge,0,.22,1,46,0,dark,true);
  place(0,edge,46,1,.22,0,dark,true);
 }
 // Centered walk/run strip with distance marks.
 for(let i=-18;i<=18;i+=3)place(-5,i,.12,.018,1.1,.01,yellow);
 for(const zz of [-15,-5,5,15])place(-5,zz,2.4,.018,.12,.01,white);
 label('MOVIMENTO / CORRIDA',-11,-20,3.1);
 label('TIRO / PRECISÃO',9,-20,3.1);
 // Obstacles sized for step, jump and climb; real box colliders.
 place(-11,-10,4,.32,2,0,blue,true);
 place(-11,-3,4,.74,2,0,blue,true);
 place(-11,5,4,1.3,2,0,blue,true);
 place(-11,13,4,2.0,2,0,blue,true);
 for(let i=0;i<4;i++)place(-3,13+i*1.25,3,.23*(i+1),1.15,0,blue,true);
 // Shooting lanes: head and chest targets. Their own hits stay local to practice.
 for(let lane=0;lane<4;lane++){
  const px=3+lane*5;
  for(const d of [4,11,18]){
   const pole=place(px,-d,.12,1.35,.12,0,dark);
   const target=new T.Mesh(new T.CylinderGeometry(.42,.42,.09,24),red);
   target.rotation.x=Math.PI/2;
   target.position.set(x+px,floor+1.45,z-d);
   target.castShadow=true;
   target.userData.trainingTarget=true;
   scene.add(target);objects.push(target);targets.push(target);
   const center=new T.Mesh(new T.CylinderGeometry(.14,.14,.10,24),white);
   center.rotation.x=Math.PI/2;target.add(center);
  }
 }
 label('ALVOS 4 / 11 / 18m',11,1,2.7);
 // Dedicated visual jetpack launch pad, no scripted jetpack pickup.
 place(15,14,7,.08,7,0,blue);
 label('JETPACK / QUEDA',15,20,3);
}
function spawn(){
 player.position.set(x-16,floor+.04,z+16);
 player.rotation.y=Math.PI;
 controller.velocity.set(0,0,0);
 controller.moveVelocity?.set(0,0,0);
 controller.cover.exit();controller.clearInput();
 controller.isGrounded=true;
 thirdPersonCamera.yaw=0;thirdPersonCamera.pitch=.22;
}
button.addEventListener('click',()=>{
 if(multiplayer.active||multiplayer.pending)return;
 create();active=true;score=0;
 document.getElementById('training-score').textContent='0';
 hideGameMenu();
 deployment.phase='idle';
 if(deployment.button)deployment.button.hidden=true;
 if(deployment.plane)deployment.plane.visible=false;
 if(deployment.chute)deployment.chute.visible=false;
 playerLife.reset();player.userData.dead=false;combatBots.health=100;
 setMultiplayerBots(false);panel.hidden=false;spawn();
});
function exit(){
 if(!active)return;active=false;panel.hidden=true;
 setMultiplayerBots(true);
 showGameMenu();
}
panel.querySelector('#training-reset').addEventListener('click',()=>{if(active)spawn();});
panel.querySelector('#training-exit').addEventListener('click',exit);
addEventListener('keydown',e=>{if(active&&e.code==='KeyM') {active=false;panel.hidden=true;setMultiplayerBots(true);}},true);
const raycaster=new T.Raycaster();
addEventListener('pointerdown',e=>{
 if(!active||e.button!==0||!gameStarted||player.userData.dead||e.target!==document.getElementById('view'))return;
 raycaster.setFromCamera(new T.Vector2(0,0),camera);
 const hits=raycaster.intersectObjects(targets,false);
 if(!hits.length||hits[0].distance>90)return;
 const hit=hits[0].object;
 score++;document.getElementById('training-score').textContent=String(score);
 hit.material=yellow;
 setTimeout(()=>{hit.material=red;},140);
});
window.GametesteTraining={isActive:()=>active,spawn,exit};
})();