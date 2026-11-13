/* Operator MK-II visual upgrade. Keeps the original 18-bone animation, hitbox,
   weapon mount and network state; adds only low-cost, bone-parented details. */
(()=>{
'use strict';
if(!window.THREE||!window.OperatorAvatar)return;
const T=THREE, Base=window.OperatorAvatar;
const geom={
 box:new T.BoxGeometry(1,1,1),
 cylinder:new T.CylinderGeometry(1,1,1,10),
 sphere:new T.SphereGeometry(1,12,8)
};
const mat=(color,metalness=0,roughness=.78)=>new T.MeshStandardMaterial({color,metalness,roughness});
const dark=mat(0x171f22), rubber=mat(0x101617), steel=mat(0x697476,.64,.42);
const buckle=mat(0x9f9c83,.55,.44), glass=mat(0x304d54,.18,.19);
const indicator=new T.MeshBasicMaterial({color:0xb0d3bf});
function install(operator,team){
 const cloth=mat(team==='red'?0x783f3b:0x343f3a);
 const armor=mat(team==='red'?0x91534c:0x56635b);
 const webbing=mat(team==='red'?0x4e302c:0x414d3e);
 const group=operator.group, bones=operator.bones;
 const part=(parent,geometry,material,p,s,r)=>{
  const mesh=new T.Mesh(geometry,material);
  mesh.position.set(...p);mesh.scale.set(...s);
  if(r)mesh.rotation.set(...r);
  mesh.castShadow=true;mesh.receiveShadow=true;
  mesh.userData.operatorDetail=true;parent.add(mesh);return mesh;
 };
 const box=(b,m,p,s,r)=>part(b,geom.box,m,p,s,r);
 const sphere=(b,m,p,s)=>part(b,geom.sphere,m,p,s);
 const cylinder=(b,m,p,s,r)=>part(b,geom.cylinder,m,p,s,r);
 const chest=bones[3],hips=bones[1],head=bones[5];
 // Armor is attached to the existing spine rather than becoming another rig.
 box(chest,armor,[0,-.078,.177],[.43,.36,.075]);
 box(chest,webbing,[0,-.255,.14],[.43,.055,.10]);
 box(chest,rubber,[0,.102,.132],[.37,.038,.075]);
 for(const side of [-1,1]){
  box(chest,webbing,[side*.19,-.06,.184],[.067,.43,.072]);
  box(chest,armor,[side*.167,.045,.184],[.104,.07,.085]);
  // Offset chest pockets leave the center clear for the two-handed weapon.
  for(let i=0;i<2;i++){
   const x=side*(.068+i*.101);
   box(chest,webbing,[x,-.182,.243],[.079,.15,.052]);
   box(chest,armor,[x,-.235,.279],[.079,.037,.031]);
   box(chest,buckle,[x,-.214,.303],[.028,.018,.008]);
  }
  box(hips,webbing,[side*.22,-.005,.015],[.08,.15,.11]);
  box(hips,armor,[side*.219,-.10,.094],[.094,.12,.085]);
  // Articulated shoulder equipment follows the existing arm.
  const upper=bones[side<0?6:9],fore=bones[side<0?7:10];
  sphere(upper,armor,[side*.009,-.058,.015],[.124,.10,.114]);
  box(upper,webbing,[side*.01,-.105,.101],[.145,.09,.029]);
  box(fore,rubber,[0,-.012,.062],[.137,.09,.041]);
  box(fore,armor,[0,-.13,.09],[.116,.13,.048]);
  const hand=bones[side<0?8:11];
  box(hand,webbing,[0,.001,.065],[.112,.073,.044]);
  // Boots: overlays only, so the sole remains at the old foot position.
  const shin=bones[side<0?13:16],foot=bones[side<0?14:17];
  box(shin,armor,[0,-.22,.082],[.14,.15,.04]);
  box(shin,dark,[0,-.322,.09],[.125,.024,.05]);
  box(foot,rubber,[0,-.031,.095],[.195,.052,.28]);
  box(foot,steel,[0,.029,.205],[.142,.016,.078]);
 }
 // Raised protective helmet and frontal visor, skinned-head motion preserved.
 sphere(head,armor,[0,.115,-.012],[.153,.115,.153]);
 box(head,dark,[0,.066,.132],[.285,.037,.062]);
 box(head,glass,[0,.008,.145],[.205,.060,.019]);
 box(head,rubber,[0,-.073,.115],[.18,.055,.029]);
 for(const side of [-1,1]){
  box(head,steel,[side*.129,.095,-.014],[.027,.045,.16]);
  box(head,dark,[side*.14,.012,-.03],[.037,.094,.077]);
  box(head,buckle,[side*.121,-.091,.057],[.029,.018,.019]);
 }
 box(head,dark,[0,.207,-.006],[.16,.014,.082]);
 // Lightweight radio/utility details. No rear backpack: jetpack stays unobstructed.
 box(chest,dark,[-.23,-.045,-.034],[.053,.123,.083]);
 box(chest,steel,[-.23,.033,-.034],[.015,.073,.018]);
 box(chest,indicator,[-.23,.072,-.084],[.015,.015,.009]);
 box(chest,webbing,[.20,-.18,-.12],[.083,.145,.065]);
 // Visible service tag and reflective details.
 box(chest,buckle,[.085,.048,.223],[.095,.022,.008]);
 box(chest,steel,[-.08,.046,.226],[.045,.021,.009]);
 group.userData.visualVariant='operator-mk2';
 group.userData.visualDetailCount=group.children.length;
}
class DetailedOperator extends Base{
 constructor(options={}){
  super(options);
  try{install(this,options.team||'player');}
  catch(err){console.warn('Operator detail fallback:',err);}
 }
}
window.OperatorAvatar=DetailedOperator;
window.OperatorDetail={version:'mk2',rigBones:18,install};
})();