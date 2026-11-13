/* Gameteste map builder: local custom objects only. Multiplayer server layouts are unchanged. */
(()=>{
'use strict';
const KEY='gameteste-map-editor-v1', TYPES=['house','tower','tree','rock','crate','wall','road'];
const LIMIT=220,BOUND=140;
function validate(input){
 if(!Array.isArray(input))return [];
 return input.slice(0,LIMIT).map((o,i)=>{
  if(!o||!TYPES.includes(o.type))return null;
  const x=Number(o.x),z=Number(o.z),rotation=Number(o.rotation)||0,scale=Number(o.scale)||1;
  if(!Number.isFinite(x)||!Number.isFinite(z)||Math.abs(x)>BOUND||Math.abs(z)>BOUND)return null;
  return {id:String(o.id||'item-'+i).slice(0,64),type:o.type,x:Math.round(x*10)/10,z:Math.round(z*10)/10,rotation:Math.max(-180,Math.min(180,rotation)),scale:Math.max(.5,Math.min(3,scale))};
 }).filter(Boolean);
}
function read(){try{return validate(JSON.parse(localStorage.getItem(KEY)||'[]'));}catch(_){return []}}
function save(items){const cleaned=validate(items);localStorage.setItem(KEY,JSON.stringify(cleaned));return cleaned}
function mount(scene,terrain,register){
 if(!scene||!window.THREE)return 0;
 const THREE=window.THREE, group=new THREE.Group();group.name='USER_MAP_EDITOR_OBJECTS';scene.add(group);
 const materials={
  house:new THREE.MeshStandardMaterial({color:0x9c9387,roughness:.87}),
  tower:new THREE.MeshStandardMaterial({color:0x617682,roughness:.86}),
  tree:new THREE.MeshStandardMaterial({color:0x45643e,roughness:.93,flatShading:true}),
  trunk:new THREE.MeshStandardMaterial({color:0x695036,roughness:.95}),
  rock:new THREE.MeshStandardMaterial({color:0x85877b,flatShading:true}),
  crate:new THREE.MeshStandardMaterial({color:0x937251,roughness:.9}),
  wall:new THREE.MeshStandardMaterial({color:0x616d71,roughness:.9}),
  road:new THREE.MeshStandardMaterial({color:0x3a4249,roughness:.96}),
  roof:new THREE.MeshStandardMaterial({color:0x784f45,roughness:.92})
 };
 function mesh(geometry,material,x,y,z){
  const m=new THREE.Mesh(geometry,material);m.position.set(x,y,z);m.receiveShadow=true;m.castShadow=true;m.userData.impactMaterial=material===materials.trunk||material===materials.crate?'wood':'concrete';group.add(m);return m;
 }
 const items=read();
 for(const o of items){
  const y=terrain(o.x,o.z),s=o.scale;
  if(o.type==='tree'){
   mesh(new THREE.CylinderGeometry(.38*s,.52*s,2.4*s,6),materials.trunk,o.x,y+1.2*s,o.z);
   mesh(new THREE.ConeGeometry(2*s,4.5*s,7),materials.tree,o.x,y+4.2*s,o.z);
  }else if(o.type==='rock'){
   const m=mesh(new THREE.DodecahedronGeometry(1.45*s,0),materials.rock,o.x,y+.85*s,o.z);m.scale.set(1,.65,1);
  }else if(o.type==='road'){
   const m=mesh(new THREE.BoxGeometry(12*s,.05,4*s),materials.road,o.x,y+.026,o.z);m.rotation.y=o.rotation*Math.PI/180;
  }else{
   const sizes={house:[8,5,7],tower:[7,13,7],crate:[2,1.7,2],wall:[8,2.6,.7]};
   const [w,h,d]=sizes[o.type].map(v=>v*s);
   const m=mesh(new THREE.BoxGeometry(w,h,d),materials[o.type],o.x,y+h/2,o.z);
   m.rotation.y=o.rotation*Math.PI/180;
   if(typeof register==='function'){
    // Rotated geometry receives a conservative axis-aligned collision box.
    const rad=o.rotation*Math.PI/180,W=Math.abs(Math.cos(rad))*w+Math.abs(Math.sin(rad))*d,D=Math.abs(Math.sin(rad))*w+Math.abs(Math.cos(rad))*d;
    register(m,W,h,D);
   }
   if(o.type==='house'){
    const roof=mesh(new THREE.ConeGeometry(6.5*s,2.2*s,4),materials.roof,o.x,y+h+1*s,o.z);
    roof.rotation.y=Math.PI/4+o.rotation*Math.PI/180;
   }
  }
 }
 return items.length;
}
window.GametesteMapEditor={KEY,TYPES,BOUND,LIMIT,validate,read,save,mount};
})();