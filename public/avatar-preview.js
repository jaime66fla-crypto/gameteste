/* Original articulated evaluation model. Three.js is distributed under MIT. */
(() => {
'use strict';
const canvas=document.querySelector('#view'),status=document.querySelector('#status');
if(!window.THREE){showError('Não foi possível carregar o motor 3D. Recarregue a página.');return;}
function showError(message){const el=document.querySelector('#error');el.style.display='block';el.textContent=message;}
let renderer;
try{renderer=new THREE.WebGLRenderer({canvas,antialias:true});}catch(e){showError('Este navegador não disponibilizou WebGL. Tente abrir no Chrome com aceleração gráfica.');return;}
renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.outputEncoding=THREE.sRGBEncoding;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.15;
const scene=new THREE.Scene();scene.background=new THREE.Color('#26343c');scene.fog=new THREE.Fog('#26343c',14,40);
scene.add(new THREE.HemisphereLight(0xd9ebff,0x3d4432,1.05));
const sun=new THREE.DirectionalLight(0xffe8cb,2.2);sun.position.set(4,9,5);sun.castShadow=true;sun.shadow.mapSize.set(2048,2048);Object.assign(sun.shadow.camera,{left:-9,right:9,top:9,bottom:-9,near:.1,far:30});sun.shadow.bias=-.0004;scene.add(sun);
const rim=new THREE.DirectionalLight(0x8cbedb,.9);rim.position.set(-4,3,-4);scene.add(rim);
const camera=new THREE.PerspectiveCamera(43,1,.05,70);
const mat=(color,roughness=.85,metalness=0)=>new THREE.MeshStandardMaterial({color,roughness,metalness});
const fabric=mat('#59634d'),vest=mat('#363e32'),trim=mat('#242c28'),rubber=mat('#171e20'),skin=mat('#b68b6d'),glass=mat('#243b40',.22,.4),metal=mat('#333d40',.35,.65),patch=mat('#a9b99a');
function mesh(parent,geo,material,x=0,y=0,z=0){const m=new THREE.Mesh(geo,material);m.position.set(x,y,z);m.castShadow=true;m.receiveShadow=true;parent.add(m);return m;}
function box(p,w,h,d,m,x=0,y=0,z=0){return mesh(p,new THREE.BoxGeometry(w,h,d),m,x,y,z);}
function ball(p,r,m,x=0,y=0,z=0,sx=1,sy=1,sz=1){const o=mesh(p,new THREE.SphereGeometry(r,20,14),m,x,y,z);o.scale.set(sx,sy,sz);return o;}
function joint(p,x,y,z){const g=new THREE.Group();g.position.set(x,y,z);p.add(g);return g;}
function segment(p,length,top,bottom,material){return mesh(p,new THREE.CylinderGeometry(top,bottom,length,12),material,0,-length/2,0);}
const floor=mesh(scene,new THREE.PlaneGeometry(120,120),mat('#454f4b'));floor.rotation.x=-Math.PI/2;floor.castShadow=false;
const lines=new THREE.GridHelper(32,32,0x788178,0x535f58);lines.position.y=.002;lines.material.transparent=true;lines.material.opacity=.27;scene.add(lines);
// A quiet shooting range gives the shoulder camera a readable aim reference.
for(let i=-2;i<=2;i++){const p=joint(scene,i*2.4,0,9);box(p,.13,1.1,.13,trim,0,.55,0);const target=box(p,.72,1.05,.09,mat('#a29b87'),0,1.3,0);for(let r=3;r>0;r--){const ring=mesh(p,new THREE.RingGeometry(r*.085-.013,r*.085,32),new THREE.MeshBasicMaterial({color:0x373e3b,side:THREE.DoubleSide}),0,1.38,-.051);ring.rotation.y=Math.PI;}}
box(scene,18,1,.4,mat('#343f3d'),0,.5,11);
const root=joint(scene,0,0,0),pelvis=joint(root,0,.91,0),torso=joint(pelvis,0,.06,0);
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
const keys=new Set(),clock=new THREE.Clock();let motion='idle',aiming=false,phase=0,speed=0,jumpY=0,jumpV=0,recoil=0,shot=0,yaw=.55,pitch=.12,distance=3.8,behind=false,dragging=false,lastX=0,lastY=0,aimBlend=0;
let time=0;const cameraTarget=new THREE.Vector3(),desiredCamera=new THREE.Vector3();
function setMotion(value){motion=value;document.querySelectorAll('[data-motion]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.motion===value)));}
function setAim(value){aiming=value;document.querySelector('#aim').setAttribute('aria-pressed',String(value));}
function fire(){setAim(true);shot=.065;recoil=.11;}
function jump(){if(jumpY===0){jumpV=3.9;}}
document.querySelectorAll('[data-motion]').forEach(b=>b.onclick=()=>setMotion(b.dataset.motion));
document.querySelector('#aim').onclick=()=>setAim(!aiming);document.querySelector('#fire').onclick=fire;document.querySelector('#jump').onclick=jump;
document.querySelector('#camera').onclick=()=>{behind=!behind;yaw=behind?Math.PI:0;document.querySelector('#camera').textContent=behind?'Ver de frente':'Ver pelas costas';};
document.querySelector('#uniform').onchange=e=>{const colors={olive:['#59634d','#363e32'],slate:['#4a5965','#28343d'],sand:['#9c8e72','#615b48']};fabric.color.set(colors[e.target.value][0]);vest.color.set(colors[e.target.value][1]);};
addEventListener('keydown',e=>{if(/^(INPUT|SELECT|BUTTON)$/.test(e.target.tagName))return;const k=e.key.toLowerCase();keys.add(k);if([' ','arrowup','arrowdown','arrowleft','arrowright'].includes(k))e.preventDefault();if(k===' '&&!e.repeat)jump();});
addEventListener('keyup',e=>keys.delete(e.key.toLowerCase()));addEventListener('blur',()=>{keys.clear();dragging=false;});
document.querySelectorAll('[data-key]').forEach(b=>{b.onpointerdown=e=>{e.preventDefault();b.setPointerCapture(e.pointerId);keys.add(b.dataset.key);};b.onpointerup=b.onpointercancel=()=>keys.delete(b.dataset.key);b.onlostpointercapture=()=>keys.delete(b.dataset.key);});
canvas.oncontextmenu=e=>e.preventDefault();canvas.onpointerdown=e=>{canvas.setPointerCapture(e.pointerId);dragging=true;lastX=e.clientX;lastY=e.clientY;};canvas.onpointerup=canvas.onpointercancel=canvas.onlostpointercapture=()=>dragging=false;
canvas.onpointermove=e=>{if(!dragging)return;yaw-=(e.clientX-lastX)*.008;pitch=THREE.MathUtils.clamp(pitch+(e.clientY-lastY)*.004,-.2,.7);lastX=e.clientX;lastY=e.clientY;};
canvas.onwheel=e=>{e.preventDefault();distance=THREE.MathUtils.clamp(distance+e.deltaY*.003,2.2,6);};
function resize(){renderer.setSize(innerWidth,innerHeight);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();}addEventListener('resize',resize);resize();
// Exposed read-only measurements support browser verification of movement and aiming.
window.avatarPreview={getState:()=>({motion,speed,aiming,aimBlend,jumpY,x:root.position.x,z:root.position.z,drawCalls:renderer.info.render.calls})};
function frame(){requestAnimationFrame(frame);const dt=Math.min(clock.getDelta(),.04);time+=dt;
 const inputX=Number(keys.has('d'))-Number(keys.has('a')),inputZ=Number(keys.has('w'))-Number(keys.has('s'));const moving=!!(inputX||inputZ);
 const target=moving?(keys.has('shift')?3.8:1.55):motion==='run'?3.8:motion==='walk'?1.55:0;
 const smooth=1-Math.exp(-dt*9);speed=THREE.MathUtils.lerp(speed,target,smooth);aimBlend=THREE.MathUtils.lerp(aimBlend,aiming?1:0,1-Math.exp(-dt*12));
 phase+=dt*(speed>2.4?10.5:6.5);const weight=Math.min(1,speed/1.5),running=THREE.MathUtils.smoothstep(speed,2,3.8);let yawTarget=root.rotation.y;
 if(moving){const len=Math.hypot(inputX,inputZ);const dx=inputX/len,dz=inputZ/len;root.position.x=THREE.MathUtils.clamp(root.position.x+dx*speed*dt,-7,7);root.position.z=THREE.MathUtils.clamp(root.position.z+dz*speed*dt,-5,6);yawTarget=Math.atan2(dx,dz);}
 if(aiming)yawTarget=0;root.rotation.y+=Math.atan2(Math.sin(yawTarget-root.rotation.y),Math.cos(yawTarget-root.rotation.y))*smooth;
 if(jumpV!==0||jumpY>0){jumpV-=9.8*dt;jumpY=Math.max(0,jumpY+jumpV*dt);if(jumpY===0)jumpV=0;}
 const airborne=jumpY>0,cycle=Math.sin(phase);pelvis.position.y=.91+jumpY+(!airborne?Math.cos(phase*2)*.013*weight:0);pelvis.rotation.y=cycle*.055*weight;pelvis.rotation.z=cycle*.023*weight;
 torso.rotation.x=.055+running*.11+Math.sin(time*1.6)*.007-aimBlend*.025;torso.rotation.y=-cycle*.065*weight*(1-aimBlend*.65);head.rotation.y=-torso.rotation.y*.65;
 legs.forEach(({hip,knee,ankle,s})=>{const p=phase+(s<0?Math.PI:0),stride=Math.sin(p);hip.rotation.x=airborne?-.34:stride*(.48+running*.28)*weight;hip.rotation.z=s*.025;knee.rotation.x=airborne?.85:Math.max(0,-Math.cos(p))*(.65+running*.65)*weight+.055;ankle.rotation.x=-knee.rotation.x*.32;});
 arms.forEach(({shoulder,elbow,hand,s})=>{const swing=Math.sin(phase+(s<0?0:Math.PI))*.43*weight;const right=s>0;shoulder.rotation.x=THREE.MathUtils.lerp(swing,-1.25+(right?0:.17),aimBlend);shoulder.rotation.z=THREE.MathUtils.lerp(s*-.055,right?.20:-.53,aimBlend);shoulder.rotation.y=THREE.MathUtils.lerp(0,right?-.18:.31,aimBlend);elbow.rotation.x=THREE.MathUtils.lerp(-.14-running*.6,right?-.32:-1.02,aimBlend);hand.rotation.x=THREE.MathUtils.lerp(0,-.12,aimBlend);});
 recoil=Math.max(0,recoil-dt*.6);gun.rotation.x=Math.PI/2-recoil;shot=Math.max(0,shot-dt);flash.visible=shot>0;
 const aimCamera=new THREE.Vector3(.46,1.55,-1.7);const inspectCamera=new THREE.Vector3(Math.sin(yaw)*distance,1.15+Math.sin(pitch)*distance,Math.cos(yaw)*distance);
 desiredCamera.copy(inspectCamera).lerp(aimCamera,aimBlend).add(root.position);camera.position.lerp(desiredCamera,1-Math.exp(-dt*7));cameraTarget.set(root.position.x,1.03+jumpY*.3,root.position.z).lerp(new THREE.Vector3(root.position.x+.1,1.48,root.position.z+7),aimBlend);camera.lookAt(cameraTarget);
 status.textContent=airborne?'NO AR':aiming?(speed>.2?'MIRANDO EM MOVIMENTO':'MIRANDO'):speed>2.4?'CORRENDO':speed>.2?'CAMINHANDO':'EM REPOUSO';
 renderer.render(scene,camera);
}
camera.position.set(2,1.8,3.5);frame();
})();
