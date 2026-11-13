/* Gameteste - Skin Vault. Pure cosmetics; no stat changes or purchases. */
(()=>{
'use strict';
const SOLDIERS=[
 {id:'original',name:'Operador Original',desc:'Uniforme tático padrão',cloth:0xffffff,vest:0xffffff,trim:0xffffff,rarity:'COMUM'},
 {id:'arctic',name:'Operador Ártico',desc:'Camuflagem em tons de gelo',cloth:0xc1e7f4,vest:0xa2d1e2,trim:0xd9e5ec,rarity:'RARO'},
 {id:'desert',name:'Operador Deserto',desc:'Proteção areia e bronze',cloth:0xe5c48d,vest:0xc69b60,trim:0xc9b78d,rarity:'RARO'},
 {id:'shadow',name:'Operador Sombra',desc:'Equipamento preto e grafite',cloth:0x626a79,vest:0x454d61,trim:0x838ca0,rarity:'ÉPICO'}
];
const WEAPONS=[
 {id:'original',name:'Original',desc:'Acabamento padrão',color:null,rarity:'COMUM'},
 {id:'sand',name:'Areia Tática',desc:'Pintura areia fosca',color:0xc7a677,rarity:'RARO'},
 {id:'blue',name:'Azul Elétrico',desc:'Metal azul com contraste',color:0x458ad7,rarity:'RARO'},
 {id:'ember',name:'Brasa',desc:'Vermelho metálico',color:0xcb5246,rarity:'ÉPICO'}
];
const IDS=['pistol','smg','rifle','shotgun','sniper'];
const NAMES={pistol:'Pistola',smg:'SMG',rifle:'Rifle',shotgun:'Escopeta',sniper:'Sniper'};
const STORE='gameteste-skin-vault-v1';
let saved={};try{saved=JSON.parse(localStorage.getItem(STORE)||'{}')||{}}catch(_){}
const state={
 soldier:SOLDIERS.some(s=>s.id===saved.soldier)?saved.soldier:'original',
 weapons:Object.fromEntries(IDS.map(id=>[id,WEAPONS.some(s=>s.id===saved.weapons?.[id])?saved.weapons[id]:'original']))
};
function save(){try{localStorage.setItem(STORE,JSON.stringify(state))}catch(_){}}
function tintAvatar(avatar,skinId=state.soldier){
 const mats=avatar?.body?.material;if(!Array.isArray(mats))return;
 const skin=SOLDIERS.find(s=>s.id===skinId)||SOLDIERS[0];
 for(const [i,color] of [[0,skin.cloth],[1,skin.vest],[2,skin.trim]]){
  if(mats[i]?.color)mats[i].color.setHex(color);
 }
}
function paintWeapon(model,id,skinId=state.weapons[id]){
 if(!model?.traverse)return;
 const skin=WEAPONS.find(x=>x.id===skinId)||WEAPONS[0];
 model.userData.skinWeaponId=id;
 const visited=new Set();
 model.traverse(o=>{
  const mat=o.material;
  if(!mat||Array.isArray(mat)||visited.has(mat)||!mat.color||mat.transparent)return;
  visited.add(mat);
  if(!mat.userData)mat.userData={};
  if(mat.userData.skinOriginal===undefined)mat.userData.skinOriginal=mat.color.getHex();
  mat.color.setHex(mat.userData.skinOriginal);
  if(skin.color!==null){
   const base=new THREE.Color(mat.userData.skinOriginal);
   const mix=new THREE.Color(skin.color);
   base.lerp(mix,.66);mat.color.copy(base);
  }
 });
}
let playerAvatar=null,previewAvatar=null,previewRoot=null,previewRenderer=null,previewCamera=null,previewScene=null,previewActive=false;
function attachAvatar(avatar){playerAvatar=avatar;tintAvatar(avatar);if(previewAvatar)tintAvatar(previewAvatar)}
function refreshWeapons(){
 const loot=window.weaponLoot;
 if(loot){
  for(const [id,model] of loot.heldModels||[])paintWeapon(model,id);
  for(const item of loot.items||[]){
   if(item.kind==='weapon'){
    const model=item.group?.children?.find(child=>child.userData?.skinWeaponId===item.id);
    if(model)paintWeapon(model,item.id);
   }
  }
 }
 if(window.weaponController?.pistol)paintWeapon(window.weaponController.pistol,'pistol');
}
const css=document.createElement('style');
css.textContent=`
#skinVaultButton{display:block}
#skinVault[hidden]{display:none}
#skinVault{position:fixed;inset:0;z-index:24000;background:rgba(3,10,17,.95);backdrop-filter:blur(12px);color:#eaf6fc;font:14px system-ui,Arial;padding:18px;overflow:auto}
.skin-vault-shell{max-width:1050px;margin:2vh auto;border:1px solid #496b7d;border-radius:18px;background:linear-gradient(145deg,#152a36,#0a151f);box-shadow:0 30px 75px #0009;padding:22px}
.skin-vault-header{display:flex;gap:12px;align-items:center;justify-content:space-between}
.skin-vault-header h2{margin:0;font-size:29px;letter-spacing:.11em}
.skin-vault-header small{color:#9dbdcb}
.skin-vault-close{background:#273f4b;color:white;border:1px solid #7296a6;padding:11px 16px;border-radius:8px;cursor:pointer}
.skin-vault-tabs,.skin-vault-weapons{display:flex;gap:9px;flex-wrap:wrap;margin:20px 0 10px}
.skin-vault-tabs button,.skin-vault-weapons button{background:#1b3545;color:#e9f7ff;border:1px solid #49687a;border-radius:8px;padding:10px 15px;cursor:pointer}
.skin-vault-tabs button[aria-selected=true],.skin-vault-weapons button[aria-selected=true]{background:#216b87;border-color:#86dcf5}
.skin-vault-content{display:grid;grid-template-columns:minmax(220px,40%) 1fr;gap:20px;margin-top:10px}
.skin-vault-preview{background:radial-gradient(circle at 50% 40%,#294b59,#0a1620 70%);border:1px solid #466679;border-radius:12px;min-height:345px;position:relative;overflow:hidden}
#skinVaultPreview{width:100%;height:345px;display:block}
.skin-vault-preview figcaption{position:absolute;bottom:12px;left:12px;font-weight:800;color:#add0db}
.skin-vault-options{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;align-content:start}
.skin-vault-item{text-align:left;background:#162d3b;border:1px solid #476777;border-radius:12px;padding:14px;color:#e9f7fc;cursor:pointer;min-height:111px}
.skin-vault-item[data-selected=true]{border-color:#6ee4ff;box-shadow:inset 0 0 0 1px #6ee4ff}
.skin-vault-item .swatch{display:inline-block;width:30px;height:30px;border-radius:8px;border:1px solid #ffffff55;vertical-align:middle;margin-right:8px}
.skin-vault-item strong{display:block;margin:9px 0 3px}
.skin-vault-item small{color:#9bb9c7}
.skin-vault-footer{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:16px;flex-wrap:wrap}
#skinVaultEquip{background:#2386a7;color:white;border:1px solid #80e2fa;border-radius:9px;padding:12px 24px;font-weight:900;cursor:pointer}
#skinVaultEquip:disabled{opacity:.5;cursor:default}
#skinVaultStatus{color:#a2d3e3}
@media(max-width:670px){.skin-vault-content{grid-template-columns:1fr}.skin-vault-preview{min-height:200px}#skinVaultPreview{height:200px}.skin-vault-header h2{font-size:20px}}
`;
document.head.appendChild(css);
const root=document.createElement('div');root.id='skinVault';root.hidden=true;
root.innerHTML=`<section class="skin-vault-shell">
 <header class="skin-vault-header"><div><small>GAMETESTE • COLEÇÃO</small><h2>COFRE DE SKINS</h2></div><button type="button" id="skinVaultClose" class="skin-vault-close">FECHAR ✕</button></header>
 <nav class="skin-vault-tabs" aria-label="Categorias"><button type="button" data-tab="soldier" aria-selected="true">PERSONAGEM</button><button type="button" data-tab="weapon" aria-selected="false">ARMAS</button></nav>
 <nav class="skin-vault-weapons" id="skinVaultWeapons" aria-label="Escolher arma" hidden></nav>
 <div class="skin-vault-content"><figure class="skin-vault-preview" style="margin:0"><canvas id="skinVaultPreview"></canvas><figcaption id="skinVaultPreviewLabel">SOLDIER</figcaption></figure><div id="skinVaultOptions" class="skin-vault-options"></div></div>
 <footer class="skin-vault-footer"><span id="skinVaultStatus">Skins gratuitas • alterações apenas visuais</span><button type="button" id="skinVaultEquip">EQUIPAR</button></footer>
 </section>`;
document.body.appendChild(root);
let tab='soldier',weapon='rifle',selected=state.soldier;
const optionsEl=root.querySelector('#skinVaultOptions');
const weaponNav=root.querySelector('#skinVaultWeapons');
const button=root.querySelector('#skinVaultEquip'),status=root.querySelector('#skinVaultStatus');
for(const id of IDS){const btn=document.createElement('button');btn.textContent=NAMES[id];btn.dataset.weapon=id;btn.addEventListener('click',()=>{weapon=id;selected=state.weapons[weapon];render();});weaponNav.appendChild(btn)}
function render(){
 root.querySelectorAll('[data-tab]').forEach(btn=>btn.setAttribute('aria-selected',String(btn.dataset.tab===tab)));
 weaponNav.hidden=tab!=='weapon';
 weaponNav.querySelectorAll('button').forEach(btn=>btn.setAttribute('aria-selected',String(btn.dataset.weapon===weapon)));
 const items=tab==='soldier'?SOLDIERS:WEAPONS;
 const equipped=tab==='soldier'?state.soldier:state.weapons[weapon];
 optionsEl.textContent='';
 for(const item of items){
  const el=document.createElement('button');el.type='button';el.className='skin-vault-item';el.dataset.selected=String(item.id===selected);
  const color=tab==='soldier'?item.cloth:item.color;
  const swatch=document.createElement('span');swatch.className='swatch';swatch.style.background=color===null?'linear-gradient(135deg,#263941,#8e969c)':'#'+color.toString(16).padStart(6,'0');
  const badge=document.createElement('span');badge.textContent=item.rarity+' • GRÁTIS';badge.style.fontSize='10px';badge.style.color='#8dc8da';
  const title=document.createElement('strong');title.textContent=item.name;
  const desc=document.createElement('small');desc.textContent=item.desc+(item.id===equipped?' · EQUIPADA':'');
  el.append(swatch,badge,title,desc);el.addEventListener('click',()=>{selected=item.id;render();updatePreview();});optionsEl.append(el);
 }
 button.disabled=selected===equipped;
 button.textContent=selected===equipped?'EQUIPADA':'EQUIPAR SKIN';
 root.querySelector('#skinVaultPreviewLabel').textContent=tab==='soldier'?'SOLDIER':NAMES[weapon];
 status.textContent=tab==='soldier'?'Selecione a aparência do personagem':'Personalize a aparência de cada arma, sem mudar os atributos';
}
function initPreview(){
 if(previewRenderer)return;
 const canvas=root.querySelector('#skinVaultPreview');
 try{previewRenderer=new THREE.WebGLRenderer({canvas,alpha:true,antialias:false,powerPreference:'low-power'})}catch{return}
 previewRenderer.setPixelRatio(1);
 previewScene=new THREE.Scene();
 previewScene.add(new THREE.HemisphereLight(0xc0e6fa,0x243c4a,1.8));
 const light=new THREE.DirectionalLight(0xffe2b1,1.4);light.position.set(3,6,5);previewScene.add(light);
 previewCamera=new THREE.PerspectiveCamera(39,1,.1,30);previewCamera.position.set(0,1.3,5.3);previewCamera.lookAt(0,.6,0);
 if(window.OperatorAvatar){previewAvatar=new window.OperatorAvatar();previewAvatar.group.position.y=-.85;previewScene.add(previewAvatar.group)}
 updatePreview();
 let last=0;
 function frame(time){
  requestAnimationFrame(frame);
  if(!previewActive||time-last<80)return;
  last=time;
  const w=canvas.clientWidth||320,h=canvas.clientHeight||330;
  if(canvas.width!==w||canvas.height!==h){previewRenderer.setSize(w,h,false);previewCamera.aspect=w/h;previewCamera.updateProjectionMatrix();}
  if(previewRoot)previewRoot.rotation.y+=.012;
  previewRenderer.render(previewScene,previewCamera);
 }
 requestAnimationFrame(frame);
}
function updatePreview(){
 if(!previewScene)return;
 if(previewRoot){previewScene.remove(previewRoot);previewRoot=null}
 if(tab==='soldier'){
  if(previewAvatar){
   const previous=state.soldier;state.soldier=selected;tintAvatar(previewAvatar);state.soldier=previous;
   previewRoot=previewAvatar.group;previewScene.add(previewRoot);
   previewCamera.position.set(0,1.1,4.4);previewCamera.lookAt(0,.5,0);
  }
 }else if(window.WeaponLootSystem){
  previewRoot=new THREE.Group();previewRoot.name='SKIN_PREVIEW';
  const model=window.WeaponLootSystem.createModel(weapon);previewRoot.add(model);
  // Preview selection without writing it to storage.
  const previous=state.weapons[weapon];state.weapons[weapon]=selected;paintWeapon(model,weapon);state.weapons[weapon]=previous;
  previewRoot.scale.setScalar(4);previewScene.add(previewRoot);
  previewCamera.position.set(0,.45,2.3);previewCamera.lookAt(0,0,0);
 }
}
function openVault(){root.hidden=false;previewActive=true;selected=state.soldier;tab='soldier';initPreview();render();updatePreview()}
function closeVault(){root.hidden=true;previewActive=false}
root.querySelector('#skinVaultClose').addEventListener('click',closeVault);
root.querySelectorAll('[data-tab]').forEach(btn=>btn.addEventListener('click',()=>{tab=btn.dataset.tab;selected=tab==='soldier'?state.soldier:state.weapons[weapon];render();updatePreview()}));
button.addEventListener('click',()=>{
 if(tab==='soldier'){state.soldier=selected;tintAvatar(playerAvatar);window.dispatchEvent(new Event('gameteste-skin-change'))}
 else{state.weapons[weapon]=selected;refreshWeapons()}
 save();render();
});
document.getElementById('btn-lobby-skins')?.addEventListener('click',openVault);
addEventListener('keydown',e=>{if(e.code==='Escape'&&!root.hidden)closeVault()});
window.GameSkins={attachAvatar,paintWeapon,tintAvatar,getSoldier:()=>state.soldier,getWeapon:id=>state.weapons[id],open:openVault,close:closeVault,refreshWeapons};
})();