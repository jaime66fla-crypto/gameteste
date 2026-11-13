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
const mat=(color,metalness=0,roughness=.78)=>new T.MeshStandardMaterial({color,metalness,roughness,emissive:color,emissiveIntensity:.11});
const dark=mat(0x34403d), rubber=mat(0x293331), steel=mat(0x82908a,.35,.56);
const buckle=mat(0xb9b199,.35,.52), glass=mat(0x4c7b80,.12,.26);
const indicator=new T.MeshBasicMaterial({color:0xb0d3bf});
function install(operator,team){
 if(operator.characterName==='Jaime')return;
 const armor=mat(team==='red'?0xa26055:0x718378);
 const webbing=mat(team==='red'?0x69433b:0x586c55);
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
  const chest=bones[3],hips=bones[1],head=bones[5];
 // Armor is attached to the existing spine rather than becoming another rig.
 box(chest,armor,[0,-.078,.174],[.37,.315,.054]);
 box(chest,webbing,[0,-.233,.144],[.37,.043,.072]);
 box(chest,rubber,[0,.078,.143],[.32,.027,.058]);
 for(const side of [-1,1]){
  box(chest,webbing,[side*.155,-.06,.168],[.045,.33,.05]);
  box(chest,armor,[side*.148,.045,.17],[.078,.052,.065]);
  // Offset chest pockets leave the center clear for the two-handed weapon.
  for(let i=0;i<2;i++){
   const x=side*(.068+i*.101);
   box(chest,webbing,[x,-.175,.215],[.064,.11,.033]);
   box(chest,armor,[x,-.220,.240],[.067,.029,.019]);
   box(chest,buckle,[x,-.207,.252],[.019,.012,.007]);
  }
  box(hips,webbing,[side*.22,-.005,.015],[.08,.15,.11]);
  box(hips,armor,[side*.219,-.10,.094],[.094,.12,.085]);
  // Articulated shoulder equipment follows the existing arm.
  const upper=bones[side<0?6:9],fore=bones[side<0?7:10];
  sphere(upper,armor,[side*.009,-.045,.012],[.083,.061,.082]);
  box(upper,webbing,[side*.01,-.088,.087],[.10,.058,.022]);
  box(fore,rubber,[0,-.025,.061],[.105,.058,.029]);
  box(fore,armor,[0,-.12,.075],[.094,.10,.032]);
  const hand=bones[side<0?8:11];
  box(hand,webbing,[0,.001,.055],[.089,.05,.028]);
  // Boots: overlays only, so the sole remains at the old foot position.
  const shin=bones[side<0?13:16],foot=bones[side<0?14:17];
  box(shin,armor,[0,-.19,.072],[.108,.13,.027]);
  box(shin,dark,[0,-.3,.078],[.105,.02,.028]);
  box(foot,rubber,[0,-.023,.07],[.158,.031,.20]);
  box(foot,steel,[0,.023,.16],[.113,.01,.041]);
 }
 // Raised protective helmet and frontal visor, skinned-head motion preserved.
 sphere(head,armor,[0,.112,-.012],[.128,.086,.128]);
 box(head,dark,[0,.06,.114],[.245,.022,.043]);
 box(head,glass,[0,.003,.127],[.17,.042,.014]);
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
 group.userData.visualVariant='operator-mk2-refined';
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