/* Standalone practice zone: no modifications to battle royale maps or net protocol. */
(()=>{
'use strict';
const T=window.THREE;
if(!T||typeof scene==='undefined'||typeof player==='undefined')return;
const button=document.createElement('button');
button.id='btn-training-ground';
button.className='menu-btn';
button.textContent='ÁREA DE TESTES • SOLO';
document.getElementById('btn-menu-settings')?.before(button);
const panel=document.createElement('div');
panel.id='training-hud';
panel.hidden=true;
panel.style.cssText='position:fixed;right:14px;top:145px;z-index:40;background:#091c24ed;border:1px solid #61c9d1;color:#eaffff;border-radius:12px;padding:12px;font:12px/1.6 system-ui;min-width:170px;box-shadow:0 8px 30px #0006';
panel.innerHTML='<strong>TESTE SOLO · MAPA NORMAL</strong><div>Treino livre no mapa original</div><div>WASD · Shift · Espaço · F · Q</div><div id="training-arsenal" style="margin-top:9px;border-top:1px solid #61c9d155;padding-top:7px"><strong>ARSENAL DE TESTES</strong><div id="training-weapons" style="display:grid;grid-template-columns:1fr 1fr;gap:5px;margin:7px 0"></div><div id="training-current" role="status">Escolha uma arma</div><button id="training-refill" type="button">RECARREGAR MUNIÇÃO</button></div><button id="training-reset" type="button">REINICIAR POSIÇÃO</button> <button id="training-exit" type="button">SAIR</button>';
document.body.append(panel);
panel.querySelectorAll('button').forEach(b=>b.style.cssText='background:#21444d;color:white;border:1px solid #6cbdc3;border-radius:5px;padding:5px;margin-top:7px;cursor:pointer');
let active=false,created=false,score=0;
let savedLoadout=null;
const weaponNames={pistol:'PISTOLA',smg:'SMG',rifle:'RIFLE',shotgun:'ESCOPETA',sniper:'SNIPER'};
const weaponGrid=panel.querySelector('#training-weapons');
const currentWeapon=panel.querySelector('#training-current');
function copySlots(slots){return slots.map(slot=>slot?{id:slot.id,ammo:slot.ammo,attachments:{...(slot.attachments||{})}}:null);}
function refillTrainingAmmo(){
 const defs=window.WeaponLootSystem.DEFINITIONS;
 weaponLoot.reserves={light:999,rifle:999,shells:999};
 for(const slot of weaponLoot.slots)if(slot)slot.ammo=defs[slot.id].magSize;
 // Keep the currently held magazine in sync with the slot.
 weaponLoot.applyActive(false);
 currentWeapon.textContent='Munição reabastecida';
}
function equipTrainingWeapon(id){
 if(!active||!window.WeaponLootSystem.DEFINITIONS[id])return;
 const defs=window.WeaponLootSystem.DEFINITIONS;
 if(weaponLoot.slots[weaponLoot.activeSlot])weaponLoot.saveActive();
 // Keep the pistol in slot 1 and switch the second slot through the test arsenal.
 const slotIndex=id==='pistol'?0:1;
 weaponLoot.slots[slotIndex]={id,ammo:defs[id].magSize,attachments:{}};
 weaponLoot.activeSlot=slotIndex;
 weaponLoot.reserves[defs[id].ammoType]=999;
 weaponLoot.applyActive(true);
 currentWeapon.textContent=defs[id].name+' equipada · munição de testes';
 for(const b of weaponGrid.querySelectorAll('button'))b.setAttribute('aria-pressed',String(b.dataset.weapon===id));
}
function restoreLoadout(){
 if(!savedLoadout)return;
 weaponLoot.slots=copySlots(savedLoadout.slots);
 weaponLoot.reserves={...savedLoadout.reserves};
 weaponLoot.activeSlot=savedLoadout.activeSlot;
 if(!weaponLoot.slots[weaponLoot.activeSlot])weaponLoot.activeSlot=weaponLoot.slots[0]?0:1;
 if(weaponLoot.slots[weaponLoot.activeSlot]){
  weaponLoot.applyActive(false);
  if(savedLoadout.equipped)pistolWeapon.equip();else pistolWeapon.holster();
 }else pistolWeapon.holster();
 savedLoadout=null;
}
for(const id of Object.keys(window.WeaponLootSystem.DEFINITIONS)){
 const b=document.createElement('button');
 b.type='button';b.dataset.weapon=id;b.textContent=weaponNames[id]||id.toUpperCase();
 b.style.cssText='background:#21444d;color:#fff;border:1px solid #6cbdc3;border-radius:5px;padding:7px 4px;cursor:pointer;font:700 10px system-ui';
 b.setAttribute('aria-pressed','false');b.title='Equipar '+window.WeaponLootSystem.DEFINITIONS[id].name;
 b.addEventListener('click',()=>equipTrainingWeapon(id));
 weaponGrid.appendChild(b);
}
panel.querySelector('#training-refill').addEventListener('click',()=>{if(active)refillTrainingAmmo();});
// Solo practice now uses the original world terrain and map props.
// No elevated base, fences, road markings, target stands or extra colliders.
function create(){} 
function spawn(){
 player.position.set(0,forestEnvironment.getTerrainHeight(0,8)+.04,8);
 player.rotation.y=Math.PI;
 controller.velocity.set(0,0,0);
 controller.moveVelocity?.set(0,0,0);
 controller.cover.exit();controller.clearInput();
 controller.isGrounded=true;
 thirdPersonCamera.yaw=0;thirdPersonCamera.pitch=.22;
}
button.addEventListener('click',()=>{
 if(multiplayer.active||multiplayer.pending)return;
 create();
 // Save the actual inventory so training selections never leak into Battle Royale.
 if(weaponLoot.slots[weaponLoot.activeSlot])weaponLoot.saveActive();
 savedLoadout={slots:copySlots(weaponLoot.slots),reserves:{...weaponLoot.reserves},activeSlot:weaponLoot.activeSlot,equipped:pistolWeapon.isEquipped};
 active=true;score=0;
 document.getElementById('training-score').textContent='0';
 hideGameMenu();
 deployment.phase='idle';
 if(deployment.button)deployment.button.hidden=true;
 if(deployment.plane)deployment.plane.visible=false;
 if(deployment.chute)deployment.chute.visible=false;
 playerLife.reset();player.userData.dead=false;combatBots.health=100;
 setMultiplayerBots(false);panel.hidden=false;spawn();
 equipTrainingWeapon('pistol');
});
function exit(){
 if(!active)return;active=false;panel.hidden=true;
 restoreLoadout();setMultiplayerBots(true);
 showGameMenu();
}
panel.querySelector('#training-reset').addEventListener('click',()=>{if(active)spawn();});
panel.querySelector('#training-exit').addEventListener('click',exit);
addEventListener('keydown',e=>{if(active&&e.code==='KeyM'){active=false;panel.hidden=true;restoreLoadout();setMultiplayerBots(true);}},true);
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