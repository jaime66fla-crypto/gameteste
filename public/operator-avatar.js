/* Original operator approved in avatar-preview; no remote character asset required. */
(function(){
'use strict';
window.OperatorAvatar=class OperatorAvatar{
constructor(){
const mat=(color,roughness=.85,metalness=0)=>new THREE.MeshStandardMaterial({color,roughness,metalness});
const fabric=mat('#59634d'),vest=mat('#363e32'),trim=mat('#242c28'),rubber=mat('#171e20'),skin=mat('#b68b6d'),glass=mat('#243b40',.22,.4),metal=mat('#333d40',.35,.65),patch=mat('#a9b99a');
function mesh(parent,geo,material,x=0,y=0,z=0){const m=new THREE.Mesh(geo,material);m.position.set(x,y,z);m.castShadow=true;m.receiveShadow=true;parent.add(m);return m;}
function box(p,w,h,d,m,x=0,y=0,z=0){return mesh(p,new THREE.BoxGeometry(w,h,d),m,x,y,z);}
function ball(p,r,m,x=0,y=0,z=0,sx=1,sy=1,sz=1){const o=mesh(p,new THREE.SphereGeometry(r,20,14),m,x,y,z);o.scale.set(sx,sy,sz);return o;}
function joint(p,x,y,z){const g=new THREE.Group();g.position.set(x,y,z);p.add(g);return g;}
function segment(p,length,top,bottom,material){return mesh(p,new THREE.CylinderGeometry(top,bottom,length,12),material,0,-length/2,0);}
const root=new THREE.Group(),pelvis=joint(root,0,.91,0),torso=joint(pelvis,0,.06,0);
ball(pelvis,.2,fabric,0,0,0,1.05,.6,.7);
const body=mesh(torso,new THREE.CylinderGeometry(.205,.165,.47,12),fabric,0,.235,0);body.scale.z=.65;
const armor=box(torso,.395,.34,.22,vest,0,.265,.035);ball(torso,.18,vest,0,.415,.035,1,.25,.6);
for(const s of [-1,1]){box(torso,.065,.43,.035,trim,s*.143,.25,.17);box(torso,.055,.055,.043,metal,s*.143,.38,.18);}
for(let y=0;y<5;y++)for(let x=0;x<5;x++)box(torso,.052,.009,.013,patch,(x-2)*.061,.18+y*.033,.157);
for(let i=-1;i<=1;i++){box(torso,.082,.125,.065,vest,i*.1,.12,.184);box(torso,.087,.025,.07,trim,i*.1,.175,.19);}
box(torso,.17,.28,.1,vest,0,.26,-.14);box(torso,.12,.018,.013,patch,0,.35,-.197);
const belt=mesh(pelvis,new THREE.CylinderGeometry(.218,.218,.065,16),trim,0,.015,0);belt.scale.z=.69;box(pelvis,.07,.05,.025,metal,0,.016,.153);
box(pelvis,.09,.15,.07,trim,.235,-.07,0);box(pelvis,.08,.11,.065,vest,-.225,-.04,-.03);
const neck=joint(torso,0,.51,0);segment(neck,.06,.058,.06,skin);const head=joint(neck,0,.065,0);
ball(head,.122,skin,0,.05,.005,.8,1.16,.87);ball(head,.117,trim,0,.027,.025,.87,.63,.99);
const helmet=ball(head,.137,vest,0,.115,-.012,1,.73,1.07);box(head,.245,.027,.245,trim,0,.125,.008);box(head,.08,.035,.055,trim,0,.15,.142);
for(const s of [-1,1]){ball(head,.045,trim,s*.12,.04,-.01,.3,1,1);box(head,.097,.056,.032,glass,s*.052,.09,.113);box(head,.028,.04,.03,trim,s*.11,.09,.09);}
box(head,.024,.019,.033,trim,0,.09,.122);box(head,.056,.037,.029,trim,0,.016,.124);
const legs=[],arms=[];
for(const s of [-1,1]){
 const hip=joint(pelvis,s*.112,-.06,0);ball(hip,.095,fabric,0,-.08,0,1,1.25,1);segment(hip,.39,.095,.071,fabric);
 box(hip,.07,.145,.108,vest,s*.065,-.18,-.015);box(hip,.075,.027,.115,trim,s*.065,-.115,-.015);
 const knee=joint(hip,0,-.39,0);ball(knee,.071,trim);ball(knee,.075,vest,0,-.018,.045,.84,1,.5);segment(knee,.38,.068,.046,fabric);
 const ankle=joint(knee,0,-.36,0);ball(ankle,.05,rubber);box(ankle,.112,.14,.15,rubber,0,-.008,.012);const boot=ball(ankle,.08,rubber,0,-.065,.058,.76,.6,1.45);box(ankle,.12,.027,.23,trim,0,-.103,.044);
 for(let j=0;j<4;j++)box(ankle,.063,.009,.007,patch,0,-.005+j*.022,.09);
 legs.push({hip,knee,ankle,s});
 const shoulder=joint(torso,s*.236,.438,0);ball(shoulder,.085,fabric,0,-.035,0);segment(shoulder,.265,.075,.056,fabric);box(shoulder,.018,.08,.064,patch,s*.072,-.105,0);
 const elbow=joint(shoulder,0,-.265,0);ball(elbow,.054,trim);segment(elbow,.245,.06,.041,fabric);
 const hand=joint(elbow,0,-.245,0);ball(hand,.046,rubber,0,-.023,.006,.8,1.25,.6);box(elbow,.072,.043,.073,trim,0,-.206,0);
 arms.push({shoulder,elbow,hand,s});
}
// Pistol points along local +Z and is anchored to the right hand.
const gun=joint(arms[1].hand,0,-.018,.035);gun.rotation.x=Math.PI/2;
box(gun,.039,.049,.175,metal,0,.035,.037);box(gun,.034,.034,.16,rubber,0,-.005,.03);const grip=box(gun,.035,.087,.045,rubber,0,-.051,-.018);grip.rotation.x=-.2;
box(gun,.006,.024,.043,metal,-.024,-.031,.025);box(gun,.006,.024,.043,metal,.024,-.031,.025);box(gun,.05,.006,.043,metal,0,-.043,.025);
box(gun,.008,.008,.012,trim,0,.064,.103);box(gun,.035,.008,.014,trim,0,.064,-.03);
const flash=mesh(gun,new THREE.ConeGeometry(.045,.16,7),new THREE.MeshBasicMaterial({color:0xffe5a2}),0,.035,.2);flash.rotation.x=Math.PI/2;flash.visible=false;

Object.assign(this,{group:root,pelvis,torso,head,legs,arms,gun,flash,leftArm:arms[0].shoulder,rightArm:arms[1].shoulder,leftHand:arms[0].hand,rightHand:arms[1].hand,leftLeg:legs[0].hip,rightLeg:legs[1].hip});
this.phase=0;this.time=0;this.speed=0;this.aimBlend=0;this.crouchBlend=0;this.gun.visible=false;
}
update(dt,{speed=0,grounded=true,armed=false,recoil=0,crouching=false}={}){
const {pelvis,torso,head,legs,arms,gun}=this;
this.crouchBlend=THREE.MathUtils.lerp(this.crouchBlend,crouching&&grounded?1:0,1-Math.exp(-12*dt));
const crouch=this.crouchBlend;
this.time+=dt;this.speed=THREE.MathUtils.lerp(this.speed,speed,1-Math.exp(-dt*9));this.aimBlend=THREE.MathUtils.lerp(this.aimBlend,armed?1:0,1-Math.exp(-dt*12));
this.phase+=dt*(this.speed>2.4?10.5:6.5)*(1-crouch*.35);const phase=this.phase,weight=Math.min(1,this.speed/1.5),running=THREE.MathUtils.smoothstep(this.speed,2,3.8),cycle=Math.sin(phase),aimBlend=this.aimBlend;
pelvis.position.y=.91+(grounded?Math.cos(phase*2)*.013*weight:0);pelvis.rotation.y=cycle*.055*weight;pelvis.rotation.z=cycle*.023*weight;
torso.rotation.x=.055+running*.11+crouch*.18+Math.sin(this.time*1.6)*.007-aimBlend*.025;torso.rotation.y=-cycle*.065*weight*(1-aimBlend*.65);head.rotation.y=-torso.rotation.y*.65;
legs.forEach(({hip,knee,ankle,s})=>{const p=phase+(s<0?Math.PI:0);hip.rotation.x=!grounded?-.34:Math.sin(p)*(.48+running*.28)*weight;hip.rotation.z=s*.025;knee.rotation.x=!grounded?.85:Math.max(0,-Math.cos(p))*(.65+running*.65)*weight+.055;hip.rotation.x=THREE.MathUtils.lerp(hip.rotation.x,-1.1+Math.sin(p)*.14*weight,crouch);knee.rotation.x=THREE.MathUtils.lerp(knee.rotation.x,1.95-Math.sin(p)*.12*weight,crouch);ankle.rotation.x=THREE.MathUtils.lerp(-knee.rotation.x*.32,-hip.rotation.x-knee.rotation.x,crouch);});
// Keep the lowest supporting foot planted while bending the articulated legs.
if(grounded&&crouch>.001){const support=.06+Math.max(...legs.map(l=>.39*Math.cos(l.hip.rotation.x)+.36*Math.cos(l.hip.rotation.x+l.knee.rotation.x)))+.116;pelvis.position.y=support;}

arms.forEach(({shoulder,elbow,hand,s})=>{const swing=Math.sin(phase+(s<0?0:Math.PI))*.43*weight,right=s>0;shoulder.rotation.x=THREE.MathUtils.lerp(swing,-1.25+(right?0:.17)-crouch*.18,aimBlend);shoulder.rotation.z=THREE.MathUtils.lerp(s*-.055,right?.20:-.53,aimBlend);shoulder.rotation.y=THREE.MathUtils.lerp(0,right?-.18:.31,aimBlend);elbow.rotation.x=THREE.MathUtils.lerp(-.14-running*.6,right?-.32:-1.02,aimBlend);hand.rotation.x=THREE.MathUtils.lerp(0,-.12,aimBlend);});
gun.rotation.x=Math.PI/2-recoil;
}
};
})();
