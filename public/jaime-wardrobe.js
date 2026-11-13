/* Jaime Wardrobe — modular removable cosmetics, no gameplay stats. */
(()=>{
'use strict';
const KEY='gameteste-jaime-wardrobe-v1';
const CATALOG={
 head:[['none','Sem boné',null],['cap','Boné preto',0x20252b]],
 face:[['none','Sem máscara',null],['mask','Máscara escura',0x23282c]],
 torso:[['none','Uniforme padrão',null],['jacket','Jaqueta preta',0x242d34],['vest','Colete militar',0x455943]],
 hands:[['none','Luvas padrão',null],['gloves','Luvas pretas',0x15191c]],
 legs:[['none','Calça padrão',null],['pants','Calça tática preta',0x262b31]],
 feet:[['none','Botas padrão',null],['boots','Botas de combate',0x171b1d]],
 back:[['none','Sem mochila',null],['pack','Mochila verde',0x4b6044]]
};
const LABEL={head:'Cabeça',face:'Rosto',torso:'Tronco',hands:'Mãos',legs:'Pernas',feet:'Pés',back:'Costas'};
let previous={};try{previous=JSON.parse(localStorage.getItem(KEY)||'{}')||{}}catch(_){}
const equipped=Object.fromEntries(Object.entries(CATALOG).map(([slot,items])=>[slot,items.some(i=>i[0]===previous[slot])?previous[slot]:'none']));
let avatar=null,preview=null,renderer=null,scene=null,camera=null,raf=0,selectedSlot='torso',selectedId=equipped.torso;
function persist(){try{localStorage.setItem(KEY,JSON.stringify(equipped))}catch(_){}}
function piece(bone,geo,color,xyz,scale){
 const mesh=new THREE.Mesh(geo,new THREE.MeshStandardMaterial({color,roughness:.88}));
 mesh.position.set(...xyz);mesh.scale.set(...scale);mesh.userData.jaimeClothing=true;mesh.castShadow=true;mesh.receiveShadow=true;bone.add(mesh);
}
function clear(a){
 if(!a?.bones)return;
 for(const bone of a.bones)for(const child of [...bone.children])if(child.userData?.jaimeClothing){
  bone.remove(child);child.geometry.dispose();child.material.dispose();
 }
}
function apply(a,gear=equipped){
 if(!a?.bones)return;clear(a);
 const b=a.bones;
 const box=(i,c,p,s)=>piece(b[i],new THREE.BoxGeometry(1,1,1),c,p,s);
 const sphere=(i,c,p,s)=>piece(b[i],new THREE.SphereGeometry(1,12,8),c,p,s);
 if(gear.head==='cap'){sphere(5,0x20252b,[0,.14,0],[.118,.052,.11]);box(5,0x20252b,[0,.118,.12],[.19,.02,.12]);}
 if(gear.face==='mask')sphere(5,0x23282c,[0,-.014,.102],[.078,.06,.028]);
 if(gear.torso==='jacket'){
  box(3,0x242d34,[0,-.04,0],[.37,.39,.24]);
  for(const i of [6,9])sphere(i,0x242d34,[0,-.14,0],[.072,.18,.074]);
  for(const i of [7,10])sphere(i,0x242d34,[0,-.12,0],[.056,.16,.06]);
 }else if(gear.torso==='vest'){
  box(3,0x455943,[0,-.03,.155],[.33,.33,.08]);box(3,0x394c38,[0,-.03,-.15],[.33,.33,.075]);
  for(const x of [-.11,.11])box(3,0x31432e,[x,.06,.215],[.09,.11,.04]);
 }
 if(gear.hands==='gloves')for(const i of [8,11])sphere(i,0x15191c,[0,-.04,0],[.046,.064,.037]);
 if(gear.legs==='pants'){
  for(const i of [12,15])sphere(i,0x262b31,[0,-.21,0],[.108,.26,.112]);
  for(const i of [13,16])sphere(i,0x262b31,[0,-.2,0],[.078,.23,.088]);
 }
 if(gear.feet==='boots')for(const i of [14,17])box(i,0x171b1d,[0,-.02,.055],[.13,.11,.24]);
 if(gear.back==='pack'){
  box(3,0x4b6044,[0,-.07,-.235],[.31,.4,.15]);
  for(const x of [-.13,.13])box(3,0x27382d,[x,-.04,-.15],[.034,.38,.035]);
 }
}
function equip(slot,id){
 if(!CATALOG[slot]?.some(x=>x[0]===id))return false;
 equipped[slot]=id;persist();apply(avatar);renderOptions();syncPreview();
 window.dispatchEvent(new CustomEvent('gameteste-clothing-change',{detail:{slot,id}}));return true;
}
const style=document.createElement('style');
style.textContent='#jaimeWardrobe[hidden]{display:none}#jaimeWardrobe{position:fixed;inset:0;z-index:25000;background:#061019f5;color:#e9f8ff;font:14px system-ui;overflow:auto;padding:16px}.jw-shell{max-width:990px;margin:2vh auto;padding:18px;background:#142936;border:1px solid #416879;border-radius:16px}.jw-head,.jw-footer{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}.jw-head h2{margin:0;font-size:25px}.jw-grid{display:grid;grid-template-columns:minmax(220px,42%) 1fr;gap:16px;margin:18px 0}.jw-preview{width:100%;height:380px;background:radial-gradient(#345263,#08131c);border-radius:12px}.jw-slots{display:flex;flex-wrap:wrap;gap:7px;margin:16px 0}.jw-slots button,.jw-item,.jw-action{background:#1c3d4e;color:#edfaff;border:1px solid #518198;border-radius:8px;padding:10px;cursor:pointer}.jw-slots button[aria-pressed=true],.jw-item[aria-pressed=true]{border-color:#9bebff;background:#245e79}.jw-options{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px;align-content:start}.jw-item{text-align:left;min-height:95px}.jw-item strong{display:block;margin:7px 0}.jw-swatch{display:inline-block;width:24px;height:24px;border-radius:5px;border:1px solid #8da4af}.jw-action{font-weight:800;background:#197b9d}.jw-item small{color:#b4d1dc}@media(max-width:650px){.jw-grid{grid-template-columns:1fr}.jw-preview{height:250px}.jw-head h2{font-size:19px}}';
document.head.append(style);
const panel=document.createElement('section');panel.id='jaimeWardrobe';panel.hidden=true;
panel.innerHTML='<div class="jw-shell"><header class="jw-head"><div><small>GAMETESTE · JAIME</small><h2>GUARDA-ROUPA</h2></div><button class="jw-action" id="jwClose" type="button">FECHAR ✕</button></header><nav class="jw-slots" id="jwSlots" aria-label="Peças do Jaime"></nav><div class="jw-grid"><canvas class="jw-preview" id="jwPreview"></canvas><div class="jw-options" id="jwOptions"></div></div><footer class="jw-footer"><span id="jwStatus">As roupas são apenas visuais.</span><div><button class="jw-action" id="jwRemove" type="button">TIRAR PEÇA</button> <button class="jw-action" id="jwEquip" type="button">EQUIPAR</button></div></footer></div>';
document.body.append(panel);
const slots=panel.querySelector('#jwSlots'),options=panel.querySelector('#jwOptions'),status=panel.querySelector('#jwStatus');
for(const slot of Object.keys(CATALOG)){
 const button=document.createElement('button');button.type='button';button.dataset.slot=slot;button.textContent=LABEL[slot];
 button.addEventListener('click',()=>{selectedSlot=slot;selectedId=equipped[slot];renderOptions();syncPreview()});slots.append(button);
}
function renderOptions(){
 for(const button of slots.children)button.setAttribute('aria-pressed',String(button.dataset.slot===selectedSlot));
 options.textContent='';
 for(const [id,name,color] of CATALOG[selectedSlot]){
  const button=document.createElement('button');button.type='button';button.className='jw-item';button.setAttribute('aria-pressed',String(id===selectedId));
  const swatch=document.createElement('span');swatch.className='jw-swatch';swatch.style.background=color===null?'linear-gradient(135deg,#233d48,#63727b)':'#'+color.toString(16).padStart(6,'0');
  const title=document.createElement('strong');title.textContent=name;
  const description=document.createElement('small');description.textContent=id===equipped[selectedSlot]?'EQUIPADO':'GRÁTIS · VISUAL';
  button.append(swatch,title,description);button.addEventListener('click',()=>{selectedId=id;renderOptions();syncPreview()});options.append(button);
 }
 status.textContent=LABEL[selectedSlot]+' · '+(equipped[selectedSlot]==='none'?'padrão':CATALOG[selectedSlot].find(x=>x[0]===equipped[selectedSlot])[1]);
 panel.querySelector('#jwEquip').disabled=selectedId===equipped[selectedSlot];
 panel.querySelector('#jwRemove').disabled=equipped[selectedSlot]==='none';
}
function initPreview(){
 if(renderer||!window.OperatorAvatar)return;
 try{renderer=new THREE.WebGLRenderer({canvas:panel.querySelector('#jwPreview'),alpha:true,antialias:false,powerPreference:'low-power'})}catch(_){return}
 renderer.setPixelRatio(1);scene=new THREE.Scene();scene.add(new THREE.HemisphereLight(0xd2e6fd,0x283d4b,2));
 const light=new THREE.DirectionalLight(0xffe7c3,1.4);light.position.set(3,5,5);scene.add(light);
 camera=new THREE.PerspectiveCamera(36,1,.1,30);camera.position.set(0,1.1,4.5);camera.lookAt(0,.5,0);
 preview=new window.OperatorAvatar();preview.group.position.y=-.8;scene.add(preview.group);
 syncPreview();let previousFrame=0;
 function frame(now){raf=requestAnimationFrame(frame);if(panel.hidden||now-previousFrame<65)return;previousFrame=now;
  const canvas=renderer.domElement,w=canvas.clientWidth||320,h=canvas.clientHeight||360;
  if(canvas.width!==w||canvas.height!==h){renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix()}
  preview.group.rotation.y+=.012;renderer.render(scene,camera);
 }raf=requestAnimationFrame(frame);
}
function syncPreview(){if(preview)apply(preview,{...equipped,[selectedSlot]:selectedId})}
function open(){panel.hidden=false;renderOptions();initPreview();syncPreview()}
function close(){panel.hidden=true}
panel.querySelector('#jwEquip').addEventListener('click',()=>equip(selectedSlot,selectedId));
panel.querySelector('#jwRemove').addEventListener('click',()=>{selectedId='none';equip(selectedSlot,'none')});
panel.querySelector('#jwClose').addEventListener('click',close);
addEventListener('keydown',e=>{if(e.code==='Escape'&&!panel.hidden)close()});
function addMenuButton(){
 const original=document.getElementById('btn-lobby-skins');if(!original||document.getElementById('btn-lobby-clothes'))return;
 const button=document.createElement('button');button.id='btn-lobby-clothes';button.className=original.className;button.textContent='ROUPAS DO JAIME';
 original.insertAdjacentElement('afterend',button);button.addEventListener('click',open);
}
addMenuButton();
if(window.GameSkins){
 const prevAttach=window.GameSkins.attachAvatar;
 window.GameSkins.attachAvatar=function(a){prevAttach(a);avatar=a;apply(avatar)};
}
window.JaimeWardrobe={open,close,equip,remove:slot=>equip(slot,'none'),getEquipped:()=>({...equipped}),attach:a=>{avatar=a;apply(a)},apply};
})();