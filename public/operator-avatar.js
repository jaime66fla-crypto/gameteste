/* Approved 2K operator: real Three.js skinning, existing 18 bones, +Z forward. */
(()=>{
'use strict';
const M=window.OperatorMotion;
const {parents,offsets,bind,norm,sub,dot,cross,sp,clamp}=M;
let sharedGeometry=null,sharedHitGeometry=null,sharedTextures=null;
function buildGeometry(rings=16,sides=24){
const palettes={
cloth:{c:[.105,.135,.15],m:[.87,0,0]},nylon:{c:[.20,.235,.12],m:[.80,0,0]},
rubber:{c:[.033,.043,.039],m:[.94,0,1]},leather:{c:[.075,.067,.049],m:[.66,0,1]},
metal:{c:[.20,.23,.20],m:[.38,.8,1]},skin:{c:[.44,.285,.18],m:[.72,0,1]},
glass:{c:[.028,.065,.075],m:[.14,.5,1]},dark:{c:[.022,.03,.029],m:[.8,0,1]}
};
const vertices=[],segments=[],keys=Object.keys(palettes);
// Two bone weights per vertex. Only the joint region blends into its parent.
function weights(p,bone,blend){
 if(!blend||parents[bone]<0)return[bone,bone,1];
 let joint=bind[bone][13],t=clamp((p[1]-joint+.075)/.15,0,1);
 t=t*t*(3-2*t);
 return[bone,parents[bone],1-t*blend];
}
function S(x,y,z,rx,ry,rz,mat,bone,exp=1,angle=0,blend=0){
 const first=vertices.length/20;
 const points=[],faces=[],normals=[],material=palettes[mat];
 for(let j=0;j<=rings;j++){
 let v=-Math.PI/2+Math.PI*(j+.000001)/(rings+.000002);
 for(let i=0;i<=sides;i++){
 let u=i/sides*Math.PI*2,a=rx*sp(Math.cos(v),exp)*sp(Math.cos(u),exp),b=ry*sp(Math.sin(v),exp),c=rz*sp(Math.cos(v),exp)*sp(Math.sin(u),exp);
 points.push([x+a*Math.cos(angle)-b*Math.sin(angle),y+a*Math.sin(angle)+b*Math.cos(angle),z+c]);normals.push([0,0,0]);
 }
 }
 for(let j=0;j<rings;j++)for(let i=0;i<sides;i++){
 let a=j*(sides+1)+i,f=[a,a+1,a+sides+2,a+sides+1];
 let n=cross(sub(points[f[1]],points[f[0]]),sub(points[f[2]],points[f[0]]));
 let center=f.reduce((s,k)=>s.map((v,q)=>v+points[k][q]/4),[0,0,0]);
 if(dot(n,sub(center,[x,y,z]))<0){f.reverse();n=n.map(v=>-v)}
 faces.push(f);for(let k of f)for(let q=0;q<3;q++)normals[k][q]+=n[q];
 }
 for(let j=0;j<=rings;j++){
 let a=j*(sides+1),b=a+sides,n=normals[a].map((v,k)=>v+normals[b][k]);normals[a]=n.slice();normals[b]=n.slice();
 }
 for(let f of faces){
 let tri=[f[0],f[1],f[2],f[0],f[2],f[3]];
 for(let n=0;n<6;n++){
 let idx=tri[n],j=Math.floor(idx/(sides+1)),i=idx%(sides+1),w=weights(points[idx],bone,blend);
 let bary=n%3===0?[1,0,0]:n%3===1?[0,1,0]:[0,0,1];
 vertices.push(...points[idx],...norm(normals[idx]),i/sides,j/rings,...material.c,...material.m,w[0],w[1],w[2],...bary);
 }
 }
 segments.push({first,count:vertices.length/20-first,material:keys.indexOf(mat)});
}
S(0,1.045,0,.235,.155,.148,'cloth',1,.7);
for(let s of [-1,1]){
 let thigh=s<0?12:15,shin=thigh+1,foot=thigh+2;
 S(s*.132,.822,-.009,.111,.246,.13,'cloth',thigh,.87,-s*.065,.42);
 S(s*.149,.597,.012,.087,.094,.102,'cloth',shin,.9,0,.5);
 S(s*.154,.405,-.02,.085,.195,.103,'cloth',shin,.95,0,.45);
 S(s*.156,.218,.005,.066,.107,.071,'leather',foot,.7,0,.35);
 S(s*.155,.112,.067,.102,.094,.178,'leather',foot,.64);
 S(s*.155,.043,.074,.108,.028,.187,'rubber',foot,.45);
 S(s*.148,.591,.107,.069,.088,.032,'rubber',shin,.64,0,.35);
 S(s*.238,.814,.005,.035,.105,.079,'nylon',thigh,.5);
 S(s*.239,.891,.013,.037,.024,.083,'nylon',thigh,.5);
 for(let i=0;i<5;i++)S(s*.155,.14+i*.012,.15-i*.012,.035,.0035,.0035,'dark',foot,.55);
 for(let i=0;i<3;i++)S(s*.156,.34+i*.045,.08,.065,.006,.009,'cloth',shin,.6,s*.09);
}
S(0,1.35,-.014,.218,.266,.143,'cloth',2,.88,0,.3);
S(0,1.477,-.003,.248,.144,.145,'cloth',3,.88,0,.35);
S(0,1.18,0,.188,.116,.127,'cloth',2,.9,0,.4);
S(0,1.375,.13,.21,.19,.062,'nylon',3,.46,0,.25);
S(0,1.398,-.19,.176,.211,.083,'nylon',3,.54);
S(0,1.431,-.267,.144,.095,.031,'nylon',3,.5);
S(0,1.258,-.26,.142,.06,.031,'nylon',3,.5);
for(let s of [-1,1]){
 let arm=s<0?6:9,fore=arm+1,hand=arm+2;
 S(s*.258,1.505,-.003,.091,.114,.103,'cloth',arm,.96,0,.45);
 S(s*.303,1.348,-.002,.078,.171,.088,'cloth',arm,.98,s*.18,.3);
 S(s*.333,1.204,.012,.07,.072,.078,'rubber',fore,.95,0,.45);
 S(s*.351,1.096,.032,.067,.137,.078,'cloth',fore,.98,s*.095,.4);
 S(s*.365,.963,.048,.061,.075,.064,'leather',hand,.81,0,.3);
 S(s*.366,.975,.104,.045,.035,.019,'rubber',hand,.65);
 S(s*.32,.965,.072,.02,.042,.032,'leather',hand);
 for(let i=0;i<4;i++)S(s*.365+(i-1.5)*.023,.925,.066,.011,.037,.027,'leather',hand,.8);
 S(s*.156,1.538,.147,.034,.112,.021,'nylon',3,.45,s*.10);
 S(s*.157,1.487,.17,.025,.024,.009,'metal',3,.4);
}
for(let row=0;row<3;row++)for(let col=-2;col<=2;col++)S(col*.073,1.443-row*.039,.192,.031,.006,.007,'nylon',3,.45);
for(let i=-1;i<=1;i++){
 S(i*.124,1.264,.208,.054,.079,.041,'nylon',3,.46);
 S(i*.124,1.321,.241,.056,.022,.012,'nylon',3,.46);
 S(i*.124,1.284,.252,.009,.024,.005,'rubber',3,.45);
}
S(0,1.084,.008,.226,.027,.144,'rubber',1,.5);
S(0,1.083,.153,.037,.027,.01,'metal',1,.4);
for(let s of [-1,1])S(s*.207,1.073,.066,.038,.052,.06,'nylon',1,.5);
S(0,1.652,-.012,.067,.083,.067,'skin',4,1,0,.3);
S(0,1.798,-.004,.117,.155,.116,'skin',5,.96,0,.25);
S(0,1.731,.086,.087,.065,.039,'cloth',5,.7);
S(0,1.89,-.02,.143,.104,.134,'nylon',5,.88);
S(0,1.85,-.009,.146,.022,.135,'rubber',5,.62);
S(0,1.813,.103,.121,.035,.026,'rubber',5,.5);
for(let s of [-1,1]){
 S(s*.061,1.815,.127,.046,.023,.006,'glass',5,.48);
 S(s*.128,1.783,-.012,.028,.053,.052,'rubber',5,.66);
 S(s*.135,1.82,-.056,.013,.018,.035,'metal',5,.65);
 S(s*.1,1.744,.047,.01,.067,.012,'nylon',5,.55,-s*.22);
}
S(0,1.917,.089,.027,.03,.026,'metal',5,.45);


const count=vertices.length/20,position=new Float32Array(count*3),normal=new Float32Array(count*3),uv=new Float32Array(count*2),color=new Float32Array(count*3),indices=new Uint16Array(count*4),skinWeights=new Float32Array(count*4),geometry=new THREE.BufferGeometry();
let out=0;
for(let material=0;material<keys.length;material++){
 const first=out;
 for(const segment of segments)if(segment.material===material)for(let i=segment.first;i<segment.first+segment.count;i++){
  const k=i*20;position.set(vertices.slice(k,k+3),out*3);normal.set(vertices.slice(k+3,k+6),out*3);uv.set(vertices.slice(k+6,k+8),out*2);color.set(vertices.slice(k+8,k+11),out*3);
  indices.set([vertices[k+14],vertices[k+15],0,0],out*4);skinWeights.set([vertices[k+16],1-vertices[k+16],0,0],out*4);out++;
 }
 geometry.addGroup(first,out-first,material);
}
geometry.setAttribute('position',new THREE.BufferAttribute(position,3));geometry.setAttribute('normal',new THREE.BufferAttribute(normal,3));geometry.setAttribute('uv',new THREE.BufferAttribute(uv,2));geometry.setAttribute('color',new THREE.BufferAttribute(color,3));geometry.setAttribute('skinIndex',new THREE.BufferAttribute(indices,4));geometry.setAttribute('skinWeight',new THREE.BufferAttribute(skinWeights,4));geometry.computeBoundingBox();geometry.computeBoundingSphere();
return geometry;
}
function textures2K(){
 if(sharedTextures)return sharedTextures;
 const size=2048,albedo=new Uint8Array(size*size*4),relief=new Uint8Array(size*size*4);let seed=9137;
 for(let y=0;y<size;y++)for(let x=0;x<size;x++){
  seed=(Math.imul(seed,1664525)+1013904223)|0;const random=(seed>>>0)/4294967296,k=(y*size+x)*4,weave=((x%4)<2?1:-1)*((y%4)<2?1:-1);
  const c=clamp(Math.round(238+(random-.5)*18+weave*3),0,255),b=clamp(Math.round(128+weave*27+(random-.5)*30),0,255);
  albedo[k]=albedo[k+1]=albedo[k+2]=c;albedo[k+3]=255;relief[k]=relief[k+1]=relief[k+2]=b;relief[k+3]=255;
 }
 const make=data=>{const map=new THREE.DataTexture(data,size,size,THREE.RGBAFormat);map.wrapS=map.wrapT=THREE.RepeatWrapping;map.magFilter=THREE.LinearFilter;map.minFilter=THREE.LinearMipmapLinearFilter;map.generateMipmaps=true;map.needsUpdate=true;return map};
 sharedTextures={map:make(albedo),bump:make(relief)};return sharedTextures;
}
function materials(team){
 const maps=textures2K(),rough=[.87,.80,.94,.66,.38,.72,.14,.8],metal=[0,0,0,0,.8,0,.5,0];
 const list=rough.map((r,i)=>new THREE.MeshStandardMaterial({color:0xffffff,vertexColors:true,roughness:r,metalness:metal[i],skinning:true,map:i<2?maps.map:null,bumpMap:i<2?maps.bump:null,bumpScale:.006}));
 if(team==='red'){list[0].color.setRGB(2.4,.65,.55);list[1].color.setRGB(1.8,.5,.45)}
 return list;
}
class OperatorAvatar{
 constructor({team='player'}={}){
  this.proceduralRig=true;this.ownsWeaponPose=true;this.weaponId='pistol';this.group=new THREE.Group();this.group.name='APPROVED_OPERATOR_2K';this.group.scale.setScalar(.90);
  const list=materials(team);this.materials={fabric:list[0],vest:list[1],trim:list[2]};
  this.body=new THREE.SkinnedMesh(sharedGeometry||(sharedGeometry=buildGeometry()),list);this.body.name='OperatorSkin';this.body.castShadow=true;this.body.receiveShadow=true;this.body.frustumCulled=false;
  this.group.add(this.body);this.bones=offsets.map((off,i)=>{const bone=new THREE.Bone();bone.name='OperatorBone_'+i;bone.position.fromArray(off);bone.rotation.order='ZYX';return bone});
  for(let i=0;i<18;i++)if(parents[i]<0)this.group.add(this.bones[i]);else this.bones[parents[i]].add(this.bones[i]);
  this.group.updateMatrixWorld(true);this.skeleton=new THREE.Skeleton(this.bones);this.body.bind(this.skeleton);
  // Combat uses the same articulated shapes at reduced tessellation. The visible
  // 2K mesh is unchanged; hits still identify it for damage and team feedback.
  if(!sharedHitGeometry){sharedHitGeometry=buildGeometry(4,6);sharedHitGeometry.boundingBox=null;sharedHitGeometry.boundingSphere=new THREE.Sphere(new THREE.Vector3(0,1,0),2.4)}
  this.hitSurface=new THREE.SkinnedMesh(sharedHitGeometry,new THREE.MeshBasicMaterial({skinning:true}));this.hitSurface.bind(this.skeleton,this.body.bindMatrix);
  this.body.raycast=(raycaster,hits)=>{
   this.hitSurface.matrixWorld.copy(this.body.matrixWorld);this.hitSurface.bindMatrix.copy(this.body.bindMatrix);this.hitSurface.bindMatrixInverse.copy(this.body.bindMatrixInverse);
   const found=[];this.hitSurface.raycast(raycaster,found);for(const hit of found){hit.object=this.body;hits.push(hit)}
  };
  this.gun=new THREE.Group();this.gun.name='OperatorWeaponMount';this.bones[3].add(this.gun);
  this.flash=new THREE.Mesh(new THREE.ConeGeometry(.045,.16,7),new THREE.MeshBasicMaterial({color:0xffe5a2}));this.flash.rotation.x=Math.PI/2;this.flash.position.set(0,.035,.24);this.flash.visible=false;this.gun.add(this.flash);
  if(window.WeaponLootSystem)this.gun.add(window.WeaponLootSystem.createModel('pistol'));
  this.gun.visible=false;
  this.pelvis=this.bones[1];this.torso=this.bones[3];this.head=this.bones[5];
  this.rightHand=this.bones[8];this.leftHand=this.bones[11];this.rightArm=this.bones[6];this.leftArm=this.bones[9];this.rightLeg=this.bones[12];this.leftLeg=this.bones[15];
  this.arms=[{shoulder:this.bones[9],elbow:this.bones[10],hand:this.bones[11],s:1},{shoulder:this.bones[6],elbow:this.bones[7],hand:this.bones[8],s:-1}];
  this.legs=[{hip:this.bones[15],knee:this.bones[16],ankle:this.bones[17],s:1},{hip:this.bones[12],knee:this.bones[13],ankle:this.bones[14],s:-1}];
  this.rotations=Array.from({length:18},()=>[0,0,0]);this.shift=[0,0,0];this.weaponAngles=[.38,0,0];this.weaponGripTargets=[];
  this.phase=0;this.time=0;this.state='idle';this.speed=0;this.aimBlend=0;this.crouchBlend=0;this.coverBlend=0;this.prevCrouchBlend=0;this.prevCoverBlend=0;this.wasGrounded=true;this.airTime=0;this.landingTime=1;
  this.update(0,{armed:false});
 }
 setWeapon(id){this.weaponId=id;}
 setRecoil(value){this.recoil=value;}
 update(dt,{dead=false,speed=0,grounded=true,armed=false,aiming=false,sprinting=speed>8,verticalVelocity=0,jumpPreparation=0,jumpForce=8.5,gravity=-22,recoil=this.recoil||0,crouching=false,covering=false,coverSide=1,strafe=0,forward=0,braking=0,turn=0,turnSharpness=0,aimTransition=0,stepBlend=0,landingImpact=0,hardLanding=0,recovery=0,reload=0,equip=0}={}){
  dt=clamp(Number.isFinite(dt)?dt:0,0,.05);
  if(dead){
   this.state='dead';this.gun.visible=false;this.flash.visible=false;
   const fallen=Array.from({length:18},()=>[0,0,0]);fallen[0]=[Math.PI/2,0,.07];fallen[1]=[-.12,0,0];fallen[5]=[.08,0,.12];
   fallen[6]=[-.18,0,.52];fallen[9]=[-.30,0,-.65];fallen[7]=[-.35,0,0];fallen[10]=[-.60,0,0];fallen[12]=[-.16,0,-.09];fallen[13]=[.25,0,0];fallen[15]=[-.3,0,.12];fallen[16]=[.5,0,0];
   for(let i=0;i<18;i++)for(let k=0;k<3;k++)this.rotations[i][k]=M.damp(this.rotations[i][k],fallen[i][k],8,dt);
   for(let k=0;k<3;k++)this.shift[k]=M.damp(this.shift[k],k===1?.17:0,8,dt);
   for(let i=0;i<18;i++){this.bones[i].position.fromArray(offsets[i]);if(i===0)this.bones[i].position.add(new THREE.Vector3().fromArray(this.shift));this.bones[i].rotation.set(...this.rotations[i],'ZYX')}
   this.group.updateMatrixWorld(true);this.skeleton.update();return;
  }
  this.time+=dt;this.speed=M.damp(this.speed,speed,12,dt);this.aimBlend=M.damp(this.aimBlend,armed?1:0,12,dt);
  const oldCrouch=this.crouchBlend,oldCover=this.coverBlend;
  this.crouchBlend=M.damp(this.crouchBlend,crouching&&grounded?1:0,12,dt);this.coverBlend=M.damp(this.coverBlend,covering?1:0,12,dt);
  const crouchRate=dt>0?(this.crouchBlend-oldCrouch)/dt:0,coverRate=dt>0?(this.coverBlend-oldCover)/dt:0;
  if(!grounded){if(this.wasGrounded)this.airTime=0;this.airTime+=dt;this.landingTime=1}
  else if(!this.wasGrounded)this.landingTime=0;
  else this.landingTime=Math.min(1,this.landingTime+dt);
  let state=speed>.1?(sprinting?'run':'walk'):'idle';if(armed&&aiming&&speed<.1)state='aim';
  const duration=state==='run'?.84:state==='walk'?1.15:4;this.phase+=dt/duration*(1-this.crouchBlend*.45);
  let phase=this.phase;
  if(jumpPreparation>0){state='jump';phase=.22*clamp(1-jumpPreparation/.12,0,1)}
  else if(!grounded){state='jump';const flight=Math.max(.25,2*jumpForce/Math.abs(gravity));phase=this.airTime<.10?.22+.13*M.curveMotion([[0,0],[1,1]],this.airTime/.10):.35+.37*clamp((this.airTime-.10)/(flight-.10),0,1)}
  else if(this.landingTime<.34){state='jump';phase=.72+.28*clamp(this.landingTime/.34,0,1)}
  this.wasGrounded=grounded;this.state=state;
  const pose=M.sampleMotion(state,phase,armed,this.weaponId),r=pose.r;
  // PlayerController owns the physical jump. Never add the preview's parabola.
  if(!grounded)pose.root[1]=0;
  const crouch=this.crouchBlend;

  // Directional body response: lean into strafes and absorb hard stops/reversals.
  if(grounded&&speed>.08){
   const moveBlend=clamp(speed/6,0,1);
   const sideLean=clamp(strafe,-1,1)*moveBlend;
   const forwardLean=clamp(forward,-1,1)*moveBlend;
   const stopBlend=clamp(braking,0,1);

   r[1][2]+=sideLean*(armed?.08:.11);
   r[2][2]+=sideLean*(armed?.05:.075);
   r[3][2]-=sideLean*(armed?.035:.055);
   r[1][0]+=Math.max(0,forwardLean)*(sprinting?.035:.018);
   r[2][0]+=Math.max(0,forwardLean)*(sprinting?.045:.022);

   if(Math.abs(sideLean)>.08){
    const outsideLeg=sideLean>0?12:15;
    const insideLeg=sideLean>0?15:12;
    r[outsideLeg][2]+=-Math.sign(sideLean)*.055*moveBlend;
    r[insideLeg][2]+=Math.sign(sideLean)*.035*moveBlend;
    r[outsideLeg+1][0]+=.06*moveBlend;
   }

   if(stopBlend>.01){
    r[1][0]-=.16*stopBlend;
    r[2][0]-=.10*stopBlend;
    r[12][0]-=.08*stopBlend;
    r[15][0]+=.05*stopBlend;
    r[13][0]+=.24*stopBlend;
    r[16][0]+=.18*stopBlend;
    pose.root[1]-=.035*stopBlend;
   }
  }

  if(grounded&&turnSharpness>.03){
   const t=clamp(turn,-1,1),sharp=clamp(turnSharpness,0,1);
   const pivot=Math.abs(t)*sharp;
   r[1][1]+=t*.22*sharp;
   r[2][1]-=t*.10*sharp;
   r[3][1]-=t*.14*sharp;
   r[12][1]+=t*.10*sharp;
   r[15][1]+=t*.10*sharp;
   r[13][0]+=.16*pivot;
   r[16][0]+=.16*pivot;
   r[14][2]-=t*.10*sharp;
   r[17][2]-=t*.10*sharp;
   pose.root[1]-=.025*pivot;
  }

  if(armed&&aimTransition>.001){
   const a=clamp(aimTransition,0,1);
   r[2][0]+=a*.035;
   r[3][0]+=a*.025;
   r[5][0]-=a*.018;
   if(speed>1.5){
    r[12][0]*=1-.08*a;
    r[15][0]*=1-.08*a;
    r[13][0]+=a*.04;
    r[16][0]+=a*.04;
   }

   // Combat locomotion: keep the weapon platform quiet while the legs strafe/backpedal.
   if(aiming&&grounded&&speed>.08){
    const move=clamp(speed/5,0,1);
    const side=clamp(strafe,-1,1);
    const fwd=clamp(forward,-1,1);
    const back=Math.max(0,-fwd);
    const lateral=Math.abs(side);

    // Chest counters pelvis movement so the sight remains stable.
    r[1][1]+=side*.055*move;
    r[2][1]-=side*.040*move;
    r[3][1]-=side*.030*move;
    r[2][2]+=side*.028*move;
    r[3][2]-=side*.020*move;

    // Shorter, wider steps for lateral movement.
    if(lateral>.08){
     const phaseSide=Math.sin(this.phase*Math.PI*2);
     r[12][2]+=-side*(.11+.035*phaseSide)*move;
     r[15][2]+=-side*(.11-.035*phaseSide)*move;
     r[13][0]+=(.20+.08*Math.max(0,phaseSide))*lateral*move;
     r[16][0]+=(.20+.08*Math.max(0,-phaseSide))*lateral*move;
     r[14][2]+=side*.08*move;
     r[17][2]+=side*.08*move;
     pose.root[0]+=side*.018*move;
    }

    // Backpedal uses shorter steps, bent knees and a slight rearward balance.
    if(back>.05){
     r[1][0]-=.055*back*move;
     r[2][0]-=.035*back*move;
     r[12][0]*=.62;
     r[15][0]*=.62;
     r[13][0]+=.16*back*move;
     r[16][0]+=.16*back*move;
     r[14][0]-=.055*back*move;
     r[17][0]-=.055*back*move;
     pose.root[2]-=.012*back*move;
    }
   }
  }

  if(grounded&&this.landingTime<.34){
   const u=clamp(this.landingTime/.34,0,1);
   const pulse=1-Math.abs(u*2-1);
   const settle=1-u;
   const force=THREE.MathUtils.lerp(.35,1,clamp(landingImpact,0,1));
   const heavy=clamp(hardLanding,0,1);
   r[12][0]-=(.08+.10*heavy)*settle*force;
   r[15][0]-=(.08+.10*heavy)*settle*force;
   r[13][0]+=(.22+.42*heavy)*pulse*force;
   r[16][0]+=(.22+.42*heavy)*pulse*force;
   r[14][0]-=(.07+.12*heavy)*pulse*force;
   r[17][0]-=(.07+.12*heavy)*pulse*force;
   r[2][0]+=(.07+.15*heavy)*pulse*force;
   r[3][0]+=(.035+.09*heavy)*pulse*force;
   r[5][0]+=(.025+.07*heavy)*pulse*force;
   r[6][0]+=.08*heavy*pulse;
   r[9][0]+=.08*heavy*pulse;
   pose.root[1]-=(.028+.075*heavy)*pulse*force;

   if(heavy>.15){
    const stagger=Math.sin(u*Math.PI)*heavy;
    r[1][2]+=.035*stagger;
    r[2][2]-=.025*stagger;
    r[13][0]+=.08*stagger;
    r[16][0]+=.05*stagger;
   }
  }

  if(grounded&&recovery>.01){
   const rec=clamp(recovery,0,1);
   const roll=Math.sin(this.time*11)*.12*rec;
   r[1][0]-=.24*rec;
   r[2][0]-=.18*rec;
   r[3][0]+=.10*rec;
   r[1][2]+=roll*.35;
   r[12][0]-=.20*rec;
   r[15][0]-=.08*rec;
   r[13][0]+=.52*rec;
   r[16][0]+=.34*rec;
   r[6][0]+=.20*rec;
   r[9][0]+=.12*rec;
   pose.root[1]-=.08*rec;
   pose.root[2]+=.035*rec;
  }

  if(grounded&&stepBlend>.01){
   const step=clamp(stepBlend,0,1);
   const lead=forward>=0?12:15;
   const trail=lead===12?15:12;
   r[lead][0]-=.34*step;
   r[lead+1][0]+=.72*step;
   r[lead+2][0]-=.34*step;
   r[trail][0]-=.12*step;
   r[trail+1][0]+=.22*step;
   r[2][0]+=.07*step;
   pose.root[1]-=.025*step;
  }

  if(crouch>.001){
   const crouchMove=clamp(speed/3,0,1);
   for(const [leg,s] of [[12,0],[15,1]]){
    const cycle=Math.sin(this.phase*Math.PI*2+s*Math.PI);
    const stride=THREE.MathUtils.lerp(.10,.18,crouchMove);
    r[leg][0]=THREE.MathUtils.lerp(r[leg][0],-.90+cycle*stride,crouch);
    r[leg+1][0]=THREE.MathUtils.lerp(r[leg+1][0],1.70-cycle*stride*.9,crouch);
    r[leg+2][0]=THREE.MathUtils.lerp(r[leg+2][0],-.80-cycle*.05*crouchMove,crouch);
   }
   const support=.22+Math.max(...[12,15].map(i=>.428*Math.cos(r[i][0])+.397*Math.cos(r[i][0]+r[i+1][0])));
   pose.root[1]=THREE.MathUtils.lerp(pose.root[1],support-1.045,crouch);
   r[2][0]+=.12*crouch;
   r[3][0]+=.055*crouch;
   r[1][2]+=clamp(strafe,-1,1)*.045*crouch*crouchMove;

   // Entry/exit impulse removes the robotic pop when crouching or standing.
   const transition=clamp(Math.abs(crouchRate)/6,0,1);
   if(crouchRate>0){
    r[2][0]+=.07*transition;
    r[13][0]+=.14*transition;
    r[16][0]+=.14*transition;
    pose.root[1]-=.025*transition;
   }else if(crouchRate<0){
    r[2][0]-=.04*transition;
    r[13][0]+=.08*transition;
    r[16][0]+=.08*transition;
    pose.root[1]+=.018*transition;
   }
  }

  if(armed&&reload>.001){
   const t=clamp(reload,0,1);
   const down=1-Math.abs(t*2-1);
   const settle=clamp((t-.72)/.28,0,1);
   const id=this.weaponId||'pistol';

   if(id==='pistol'){
    const mag=clamp((t-.12)/.56,0,1);
    r[2][0]+=.10*down;r[3][0]+=.07*down;r[3][1]+=.18*down;
    r[6][0]+=.14*down;r[7][0]+=.16*down;
    r[9][0]=THREE.MathUtils.lerp(r[9][0],-.62+.22*settle,mag);
    r[9][1]=THREE.MathUtils.lerp(r[9][1],.42-.20*settle,mag);
    r[9][2]=THREE.MathUtils.lerp(r[9][2],-.30+.18*settle,mag);
    r[10][0]=THREE.MathUtils.lerp(r[10][0],-1.28+.32*settle,mag);
    r[11][0]=THREE.MathUtils.lerp(r[11][0],.28-.16*settle,mag);
   }else if(id==='smg'||id==='rifle'){
    const mag=clamp((t-.14)/.50,0,1);
    r[2][0]+=.14*down;r[3][0]+=.09*down;r[3][1]+=.12*down;
    r[6][0]+=.10*down;r[7][0]+=.10*down;
    r[9][0]=THREE.MathUtils.lerp(r[9][0],-.78+.30*settle,mag);
    r[9][1]=THREE.MathUtils.lerp(r[9][1],.28-.12*settle,mag);
    r[9][2]=THREE.MathUtils.lerp(r[9][2],-.12+.10*settle,mag);
    r[10][0]=THREE.MathUtils.lerp(r[10][0],-1.42+.34*settle,mag);
    r[11][2]=THREE.MathUtils.lerp(r[11][2],-.20+.12*settle,mag);
   }else if(id==='shotgun'){
    // Repeated shell-loading gesture while the shotgun stays tucked to the shoulder.
    const pulse=Math.pow(Math.sin(Math.PI*clamp((t-.12)/.72,0,1)*3),2);
    r[2][0]+=.16*down;r[3][0]+=.10*down;r[3][1]+=.08*down;
    r[9][0]=THREE.MathUtils.lerp(r[9][0],-.90+.22*settle,pulse);
    r[9][1]=THREE.MathUtils.lerp(r[9][1],.20,pulse);
    r[9][2]=THREE.MathUtils.lerp(r[9][2],-.34+.18*settle,pulse);
    r[10][0]=THREE.MathUtils.lerp(r[10][0],-1.55+.36*settle,pulse);
    r[11][0]=THREE.MathUtils.lerp(r[11][0],.34-.18*settle,pulse);
   }else if(id==='sniper'){
    // Magazine change followed by a distinct bolt/receiver manipulation.
    const mag=clamp((t-.10)/.44,0,1),bolt=clamp((t-.58)/.22,0,1)*(1-clamp((t-.82)/.18,0,1));
    r[2][0]+=.12*down;r[3][0]+=.07*down;r[3][1]+=.10*down;
    r[9][0]=THREE.MathUtils.lerp(r[9][0],-.72+.26*settle,mag);
    r[9][1]=THREE.MathUtils.lerp(r[9][1],.26-.10*settle,mag);
    r[10][0]=THREE.MathUtils.lerp(r[10][0],-1.36+.30*settle,mag);
    r[6][0]+=.26*bolt;r[6][1]-=.18*bolt;r[7][0]+=.34*bolt;r[8][1]+=.22*bolt;
   }
   pose.root[1]-=.018*down;
  }

  if(armed&&equip>.001){
   const e=clamp(equip,0,1);
   const progress=1-e;
   const raise=progress*progress*(3-2*progress);
   const id=this.weaponId||'pistol';

   const weight=id==='pistol'?.45:id==='smg'?.65:id==='rifle'?.82:id==='shotgun'?.88:1;
   const bodyDip=THREE.MathUtils.lerp(.10,.24,weight);
   const chestDip=THREE.MathUtils.lerp(.07,.16,weight);
   const yawSet=THREE.MathUtils.lerp(.05,.14,weight);
   const armDrop=THREE.MathUtils.lerp(.12,.28,weight);

   r[2][0]+=THREE.MathUtils.lerp(bodyDip,0,raise);
   r[3][0]+=THREE.MathUtils.lerp(chestDip,0,raise);
   r[3][1]+=THREE.MathUtils.lerp(yawSet,0,raise);
   r[6][0]+=THREE.MathUtils.lerp(armDrop,0,raise);
   r[9][0]+=THREE.MathUtils.lerp(armDrop*.78,0,raise);

   if(id==='shotgun'||id==='sniper'){
    r[1][0]+=THREE.MathUtils.lerp(.06,0,raise);
    r[13][0]+=THREE.MathUtils.lerp(.10,0,raise);
    r[16][0]+=THREE.MathUtils.lerp(.08,0,raise);
   }
   if(id==='sniper'){
    r[3][2]+=THREE.MathUtils.lerp(.05,0,raise);
    r[6][1]-=THREE.MathUtils.lerp(.08,0,raise);
    r[9][1]+=THREE.MathUtils.lerp(.05,0,raise);
   }
   pose.root[1]-=THREE.MathUtils.lerp(.010,.032,weight)*(1-raise);
  }

  if(this.coverBlend>.001){
   const cover=this.coverBlend,entry=clamp(Math.abs(coverRate)/6,0,1);
   const side=coverSide>=0?1:-1;
   r[1][1]+=side*.10*cover;
   r[2][1]-=side*.06*cover;
   r[3][1]-=side*.05*cover;
   r[1][2]+=side*.045*cover;
   r[12][1]-=side*.05*cover;
   r[15][1]-=side*.05*cover;
   if(entry>.01){
    r[13][0]+=.10*entry;
    r[16][0]+=.10*entry;
    pose.root[1]-=.018*entry;
   }
  }
  if(armed){
   const a=pose.weaponAngles.slice();
   if(reload>.001){
    const t=clamp(reload,0,1),down=1-Math.abs(t*2-1),id=this.weaponId||'pistol';
    const pitch=id==='shotgun'?.32:id==='sniper'?.38:id==='pistol'?.50:.44;
    const yaw=id==='pistol'?.20:id==='sniper'?.10:.14;
    const roll=id==='shotgun'?.04:.10;
    a[0]+=pitch*down;
    a[1]+=yaw*down;
    a[2]+=roll*down;
   }
   if(equip>.001){
    const e=clamp(equip,0,1),id=this.weaponId||'pistol';
    const pitch=id==='pistol'?.28:id==='smg'?.34:id==='rifle'?.44:id==='shotgun'?.48:.58;
    const yaw=id==='pistol'?.06:id==='smg'?.08:id==='rifle'?.11:id==='shotgun'?.12:.16;
    const roll=id==='pistol'?.04:id==='smg'?.05:id==='rifle'?.07:id==='shotgun'?.09:.12;
    a[0]+=pitch*e;
    a[1]+=yaw*e;
    a[2]+=roll*e;
   }
   a[0]+=.40*this.coverBlend-recoil*.04;
   a[1]+=coverSide*.12*this.coverBlend;
   if(aiming&&grounded&&speed>.08){
    a[0]-=.10*clamp(aimTransition,0,1);
    a[1]-=clamp(strafe,-1,1)*.035;
    a[2]+=clamp(strafe,-1,1)*.018;
   }
   for(let k=0;k<3;k++)this.weaponAngles[k]=M.damp(this.weaponAngles[k],a[k],22,dt);
   pose.weapon=M.weaponFrame(this.weaponAngles);
   const grips=this.weaponId==='pistol'?M.pistolGrips:M.rifleGrips;M.armedMotion(r,pose.weapon,grips);
   this.gripBindPoints=grips.map(([upper,p])=>({bone:upper+2,point:new THREE.Vector3().fromArray(M.pointArm(pose.weapon,p))}));
   const matrix=new THREE.Matrix4().fromArray(pose.weapon).multiply(new THREE.Matrix4().makeTranslation(.055,1.34,.245));matrix.premultiply(new THREE.Matrix4().makeTranslation(-bind[3][12],-bind[3][13],-bind[3][14]));matrix.decompose(this.gun.position,this.gun.quaternion,this.gun.scale);
  }
  for(let i=0;i<18;i++)for(let k=0;k<3;k++)this.rotations[i][k]=M.damp(this.rotations[i][k],r[i][k],22,dt);
  for(let k=0;k<3;k++)this.shift[k]=M.damp(this.shift[k],pose.root[k],22,dt);
  for(let i=0;i<18;i++){this.bones[i].position.fromArray(offsets[i]);if(i===0)this.bones[i].position.add(new THREE.Vector3().fromArray(this.shift));this.bones[i].rotation.set(...this.rotations[i],'ZYX')}
  this.gun.visible=armed;this.group.updateMatrixWorld(true);this.skeleton.update();
  this.weaponGripTargets=(this.gripBindPoints||[]).map(g=>({bone:g.bone,point:this.group.worldToLocal(this.bones[3].localToWorld(g.point.clone().sub(new THREE.Vector3().fromArray(bind[3].slice(12,15)))))}));
 }
}
window.OperatorAvatar=OperatorAvatar;
})();
