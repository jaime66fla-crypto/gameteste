/* In-game weapon arsenal/customization UI. Uses WeaponLootSystem as the single source of truth. */
(() => {
'use strict';
if(!window.THREE||!window.WeaponLootSystem)return;

const defs=window.WeaponLootSystem.DEFINITIONS;
const accessories=window.WeaponLootSystem.ACCESSORIES;
const order=['optic','suppressor','extended','grip','stock'];
let open=false,renderer=null,scene=null,camera=null,preview=null,raf=0;

const style=document.createElement('style');
style.textContent=`
#arsenalBtn{position:fixed;right:14px;top:14px;z-index:24;border:1px solid #6f8792;background:#0b141bdd;color:#edf8fa;border-radius:8px;padding:8px 11px;font:800 11px system-ui;letter-spacing:.08em;cursor:pointer}
#arsenalBtn:hover{border-color:#7ee8ff}
#weaponArsenal[hidden]{display:none}
#weaponArsenal{position:fixed;inset:0;z-index:80;background:rgba(3,7,10,.91);backdrop-filter:blur(8px);display:flex;align-items:center;justify-content:center;padding:20px;font-family:Inter,system-ui,sans-serif;color:#edf6f8}
.arsenal-shell{width:min(1080px,96vw);max-height:94vh;overflow:auto;border:1px solid #4b606b;border-radius:16px;background:linear-gradient(145deg,#0d151c,#101b23 55%,#0b1117);box-shadow:0 24px 80px #000a}
.arsenal-head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px 18px;border-bottom:1px solid #34454f}
.arsenal-head small{display:block;color:#88a1aa;font-size:10px;letter-spacing:.16em}.arsenal-head h2{margin:2px 0 0;font-size:20px}
#arsenalClose{border:1px solid #526975;background:#111d25;color:white;border-radius:8px;width:42px;height:42px;font-size:20px;cursor:pointer}
.arsenal-body{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(300px,.75fr);gap:16px;padding:16px}
.arsenal-preview{min-height:360px;border:1px solid #31434d;border-radius:13px;background:radial-gradient(circle at 50% 45%,#22313a 0,#111a20 48%,#0a1015 100%);position:relative;overflow:hidden}
#arsenalCanvas{width:100%;height:360px;display:block}
.arsenal-weapon-title{position:absolute;left:14px;top:12px}.arsenal-weapon-title b{font-size:18px}.arsenal-weapon-title span{display:block;color:#8ba1aa;font-size:11px;margin-top:3px}
.arsenal-slots{display:flex;gap:8px;position:absolute;left:14px;bottom:12px}
.arsenal-slots button{border:1px solid #4a5f69;background:#0c151bdd;color:#dce8eb;border-radius:7px;padding:7px 10px;font:700 11px system-ui;cursor:pointer}.arsenal-slots button.active{border-color:#7ee8ff;background:#13313b}
.arsenal-panel{border:1px solid #31434d;border-radius:13px;padding:14px;background:#0b1319}
.arsenal-panel h3{margin:0 0 10px;font-size:13px;letter-spacing:.08em}
.attachment-list{display:grid;gap:7px}.attachment{display:grid;grid-template-columns:1fr auto;gap:10px;align-items:center;border:1px solid #293b44;border-radius:9px;padding:9px 10px;background:#111c23}.attachment.disabled{opacity:.42}.attachment b{display:block;font-size:12px}.attachment small{display:block;color:#88a0aa;margin-top:2px;font-size:10px}.attachment button{min-width:88px;border:1px solid #526a75;background:#101c23;color:#edf6f8;border-radius:7px;padding:7px 8px;font:800 10px system-ui;cursor:pointer}.attachment button.on{border-color:#7ee8ff;background:#17303a}.attachment button:disabled{cursor:not-allowed}
.stats{margin-top:14px;display:grid;gap:8px}.stat{display:grid;grid-template-columns:86px 1fr 42px;gap:8px;align-items:center;font-size:10px;color:#9fb1b8}.track{height:6px;background:#1b2930;border-radius:99px;overflow:hidden}.fill{height:100%;background:#7ee8ff;border-radius:99px}.stat strong{text-align:right;color:#dce9ec;font-size:10px}
.arsenal-help{padding:0 16px 16px;color:#81959e;font-size:10px}
@media(max-width:760px){.arsenal-body{grid-template-columns:1fr}.arsenal-preview{min-height:280px}#arsenalCanvas{height:280px}#arsenalBtn{top:auto;bottom:160px;right:12px}}
`;
document.head.appendChild(style);

const btn=document.createElement('button');
btn.id='arsenalBtn';btn.type='button';btn.textContent='ARSENAL · C';
document.body.appendChild(btn);

const root=document.createElement('div');
root.id='weaponArsenal';root.hidden=true;
root.innerHTML=`
<div class="arsenal-shell" role="dialog" aria-modal="true" aria-label="Personalização da arma">
  <div class="arsenal-head">
    <div><small>ARSENAL / PERSONALIZAÇÃO</small><h2>Configuração da arma</h2></div>
    <button id="arsenalClose" type="button" aria-label="Fechar">×</button>
  </div>
  <div class="arsenal-body">
    <section class="arsenal-preview">
      <canvas id="arsenalCanvas"></canvas>
      <div class="arsenal-weapon-title"><b id="arsenalWeaponName">—</b><span id="arsenalWeaponMeta">—</span></div>
      <div class="arsenal-slots"><button id="arsenalSlot0" type="button">1 · —</button><button id="arsenalSlot1" type="button">2 · —</button></div>
    </section>
    <section class="arsenal-panel">
      <h3>ACESSÓRIOS</h3>
      <div class="attachment-list" id="arsenalAttachmentList"></div>
      <div class="stats" id="arsenalStats"></div>
    </section>
  </div>
  <div class="arsenal-help">C abre/fecha · ESC fecha · as alterações são aplicadas imediatamente à arma equipada.</div>
</div>`;
document.body.appendChild(root);

function loot(){return window.weaponLoot;}
function allowed(weaponId,id){
 if(!accessories[id])return false;
 return !(weaponId==='pistol'&&(id==='grip'||id==='stock'))&&!(weaponId==='shotgun'&&id==='extended');
}
function statRows(spec,mods){
 const accuracy=Math.round(Math.min(100,(1/(spec.spread*mods.spreadMultiplier))*0.24));
 const recoil=Math.round(100*Math.max(.18,1-mods.recoilMultiplier*.62));
 const range=Math.round(Math.min(100,spec.range/2.2));
 const mobility=Math.round(72-(mods.extended?6:0)-(mods.suppressor?3:0)+(mods.stock?2:0));
 const ads=Math.round(Math.min(100,74/mods.adsMultiplier));
 return [['Dano',Math.min(100,spec.damage)],['Precisão',accuracy],['Controle',recoil],['Alcance',range],['Mobilidade',mobility],['Mira',ads]];
}
function rebuildPreview(){
 const wl=loot();if(!wl)return;
 const slot=wl.slots[wl.activeSlot];if(!slot)return;
 if(preview){scene.remove(preview);preview.traverse(o=>{if(o.geometry)o.geometry.dispose?.();if(o.material)o.material.dispose?.();});}
 preview=window.WeaponLootSystem.createModel(slot.id);
 window.WeaponLootSystem.applyAccessoryVisuals(preview,slot.id,slot.attachments||{});
 preview.rotation.set(.05,-.7,0);preview.scale.setScalar(slot.id==='pistol'?3.8:2.5);scene.add(preview);
}
function refresh(){
 const wl=loot();if(!wl)return;
 const slot=wl.slots[wl.activeSlot];if(!slot)return;
 const spec=defs[slot.id],mods=window.WeaponLootSystem.accessoryStats(spec,slot.attachments||{});
 document.getElementById('arsenalWeaponName').textContent=spec.name;
 document.getElementById('arsenalWeaponMeta').textContent=`${mods.magSize} munições · alcance ${spec.range}m · ${spec.auto?'automática':'semiautomática'}`;
 for(let i=0;i<2;i++){
  const b=document.getElementById('arsenalSlot'+i),s=wl.slots[i];
  b.textContent=(i+1)+' · '+(s?defs[s.id].name:'Vazio');b.disabled=!s;b.classList.toggle('active',i===wl.activeSlot);
 }
 const list=document.getElementById('arsenalAttachmentList');list.textContent='';
 for(const id of order){
  const a=accessories[id],ok=allowed(slot.id,id),on=!!slot.attachments?.[id];
  const row=document.createElement('div');row.className='attachment'+(ok?'':' disabled');
  row.innerHTML=`<div><b>${a.slot||a.name}</b><small>${a.name}</small></div><button type="button" ${ok?'':'disabled'} class="${on?'on':''}">${on?'REMOVER':'INSTALAR'}</button>`;
  row.querySelector('button').addEventListener('click',()=>{wl.setAccessory(id,!on);refresh();rebuildPreview();});
  list.appendChild(row);
 }
 const stats=document.getElementById('arsenalStats');stats.textContent='';
 for(const [name,val0] of statRows(spec,mods)){const val=Math.max(3,Math.min(100,val0));const el=document.createElement('div');el.className='stat';el.innerHTML=`<span>${name}</span><div class="track"><div class="fill" style="width:${val}%"></div></div><strong>${val}</strong>`;stats.appendChild(el);}
}
function initPreview(){
 if(renderer)return;
 const canvas=document.getElementById('arsenalCanvas');
 renderer=new THREE.WebGLRenderer({canvas,antialias:true,alpha:true});renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));
 scene=new THREE.Scene();camera=new THREE.PerspectiveCamera(38,1,.01,20);camera.position.set(0,.15,2.2);
 scene.add(new THREE.HemisphereLight(0xbfe7ff,0x283038,1.35));const key=new THREE.DirectionalLight(0xffffff,1.7);key.position.set(2,3,4);scene.add(key);
 const loop=()=>{if(!open){raf=0;return;}const w=canvas.clientWidth||500,h=canvas.clientHeight||360;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();if(preview)preview.rotation.y+=.004;renderer.render(scene,camera);raf=requestAnimationFrame(loop);};raf=requestAnimationFrame(loop);
}
function setOpen(value){
 if(!loot())return;open=!!value;root.hidden=!open;
 if(open){initPreview();refresh();rebuildPreview();if(!raf){const canvas=document.getElementById('arsenalCanvas');const loop=()=>{if(!open){raf=0;return;}const w=canvas.clientWidth||500,h=canvas.clientHeight||360;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();if(preview)preview.rotation.y+=.004;renderer.render(scene,camera);raf=requestAnimationFrame(loop);};raf=requestAnimationFrame(loop);}}
}
btn.addEventListener('click',()=>setOpen(!open));
document.getElementById('arsenalClose').addEventListener('click',()=>setOpen(false));
for(let i=0;i<2;i++)document.getElementById('arsenalSlot'+i).addEventListener('click',()=>{const wl=loot();if(wl?.slots[i]){wl.select(i);refresh();rebuildPreview();}});
addEventListener('keydown',e=>{if(e.repeat)return;if(e.code==='KeyC'&&!/INPUT|TEXTAREA|SELECT/.test(document.activeElement?.tagName||'')){e.preventDefault();setOpen(!open);}else if(e.code==='Escape'&&open)setOpen(false);});
window.WeaponArsenal={open:()=>setOpen(true),close:()=>setOpen(false),refresh};
})();
