/* Jaime: supplied avatar_editor.html mesh adapted to the existing 18-bone game rig. */
(()=>{
'use strict';
const M=window.OperatorMotion;
const {parents,offsets,bind,norm,sub,dot,cross,sp,clamp}=M;
let sharedGeometry=null,sharedHitGeometry=null,sharedTextures=null;
function buildGeometry(rings=16,sides=24){
 const low=rings<8;
 const V2=(x,y)=>new THREE.Vector2(x,y),V3=(x,y,z)=>new THREE.Vector3(x,y,z);
 const prof=(pts,seg)=>new THREE.LatheGeometry(new THREE.SplineCurve(pts.map(p=>V2(p[0],p[1]))).getPoints(low?6:24),low?8:(seg||24));
 const limbGeo=(r0,r1,len)=>prof([[.001,-len-r1*.1],[r1*.7,-len+r1*.3],[r1,-len+r1*.9],[(r0+r1)/2,-len/2],[r0,-r0*.7],[r0*.8,r0*.3],[.001,r0*.5]]);
class JaimeSourceAvatar{
  constructor(o={}){
    this.o=Object.assign({skin:'#c98f6b',eye:'#4a7a96',hair:'#2a1c14',hairStyle:'short',shirt:'#4a5a3a',pants:'#3b3f36',
      boots:'#1d1b19',gloves:'#1a1a1a',vest:false,vestColor:'#2f3329',backpack:false,weapon:false,accessory:'none',height:1,build:1.08},o);
    this.root=new THREE.Group();this.t=0;this.anim='idle';this.nb=2;this.bl=0;this.lk=[0,0];this.build();
  }
  set(p){Object.assign(this.o,p);this.build()}
  play(a){this.anim=a}
  look(x,y){this.lk=[x,y]}
  static textures(){return {skin:null,pore:null,fabric:null,hair:null};}
  build(){
    const o=this.o,B=o.build,T=JaimeSourceAvatar.textures();
    while(this.root.children.length){const c=this.root.children.pop();c.traverse(n=>{n.geometry&&n.geometry.dispose();n.material&&n.material.dispose&&n.material.dispose()})}
    this.root.scale.setScalar(o.height);
    const std=(c,r,m,ex)=>new THREE.MeshStandardMaterial(Object.assign({color:c,roughness:r,metalness:m||0},ex||{}));
    const skin=new THREE.MeshPhysicalMaterial({color:o.skin,map:T.skin,bumpMap:T.pore,bumpScale:.5,roughness:.52,clearcoat:.12,clearcoatRoughness:.55,
      emissive:new THREE.Color(o.skin).multiplyScalar(.1)});
    const cloth=c=>std(c,.95,0,{bumpMap:T.fabric,bumpScale:.8});
    const shirt=cloth(o.shirt),pants=cloth(o.pants),vestM=cloth(o.vestColor),boots=std(o.boots,.6,0,{bumpMap:T.pore,bumpScale:.6}),
          gloves=std(o.gloves,.7),hair=std(o.hair,.38,.15,{bumpMap:T.hair,bumpScale:.4}),metal=std('#2a2c30',.35,.8),dark=std('#0b0b0c',.9);
    const part=(g,m,p,x,y,z)=>{const s=new THREE.Mesh(g,m);s.position.set(x||0,y||0,z||0);s.castShadow=s.receiveShadow=true;p.add(s);return s};
    const grp=(p,x,y,z)=>{const g=new THREE.Group();g.position.set(x||0,y||0,z||0);p.add(g);return g};
    const J=this.J={};
    const hips=J.hips=grp(this.root,0,.97,0);
    const spine=J.spine=grp(hips);
    // pelve + cinto + torso
    const pel=part(new THREE.SphereGeometry(1,low?8:28,low?6:18),pants,hips,0,0,0);pel.scale.set(.193*B,.15,.139*B);
    const belt=part(new THREE.TorusGeometry(.17,.012,8,32),std('#15130f',.6,.3),spine,0,.13,0);belt.rotation.x=Math.PI/2;belt.scale.set(B,.72*B,1);
    // Human silhouette: defined waist, natural chest volume, gradual deltoid taper.
    const tg=prof([[.001,.10],[.159,.12],[.165,.19],[.172,.29],[.201,.43],[.224,.52],[.207,.57],[.157,.61],[.090,.65],[.001,.66]],32);tg.scale(B,1,.70*B);
    part(tg,shirt,spine);
    // pescoço e cabeça
    const neck=J.neck=grp(spine,0,.6,0);
    part(new THREE.CylinderGeometry(.045,.052,.12,20).translate(0,.06,0),skin,neck);
    const headP=J.head=grp(neck,0,.1,0);
    const face=grp(headP,0,.105,.012);
    const hg=new THREE.SphereGeometry(.096,low?8:56,low?6:40),pp=hg.attributes.position;
    for(let i=0;i<pp.count;i++){let x=pp.getX(i),y=pp.getY(i),z=pp.getZ(i);
      if(y<-.02){const t=Math.min(1,(-.02-y)/.08);x*=1-.3*Math.pow(t,1.4);z*=1-.12*t;if(z>0)z+=.012*t}
      pp.setXYZ(i,x*.9,y*1.2,z)}
    hg.computeVertexNormals();
    const headM=part(hg,skin,face);
    const rc=new THREE.Raycaster(),zs=(x,y)=>{rc.set(V3(x,y,.4),V3(0,0,-1));const h=rc.intersectObject(headM)[0];return h?h.point.z:.08};
    // olhos
    this.lids=[];
    for(const s of [-1,1]){
      const ex=s*.034,ey=.018,ez=zs(ex,ey)-.0065,eg=grp(face,ex,ey,ez);
      part(new THREE.SphereGeometry(.0125,low?8:24,low?6:16),new THREE.MeshPhysicalMaterial({color:'#f2eeea',roughness:.25}),eg);
      const iris=part(new THREE.CircleGeometry(.0068,24),std(o.eye,.35),eg,0,0,.0127);
      part(new THREE.CircleGeometry(.0031,16),dark,eg,0,0,.0129);
      part(new THREE.SphereGeometry(.0129,low?8:24,low?6:16),new THREE.MeshPhysicalMaterial({color:'#fff',transparent:true,opacity:.18,roughness:0,clearcoat:1,clearcoatRoughness:0}),eg);
      const lid=grp(eg);this.lids.push(lid);
      part(new THREE.SphereGeometry(.0137,low?8:20,low?6:10,0,Math.PI*2,0,Math.PI/2),skin,lid);lid.rotation.x=-.5;
      // sobrancelha
      const bp=[-.016,0,.016,.03].map((d,i)=>V3(ex+s*(d+.01),.06+[0,.006,.007,.001][i],zs(ex+s*(d+.01),.06)+.002));
      part(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(bp),10,.0042,6),hair,face);
      // orelha
      part(new THREE.SphereGeometry(1,low?8:14,low?6:10),skin,face,s*.091,-.005,-.012).scale.set(.009,.03,.02);
    }
    // nariz
    part(new THREE.SphereGeometry(1,low?8:16,low?6:12),skin,face,0,-.012,zs(0,-.012)-.002).scale.set(.011,.032,.014);
    part(new THREE.SphereGeometry(.0145,low?8:16,low?6:12),skin,face,0,-.043,zs(0,-.043)-.001);
    for(const s of [-1,1])part(new THREE.SphereGeometry(.0105,low?8:12,low?6:10),skin,face,s*.0125,-.045,zs(s*.0125,-.045)-.004);
    // boca
    const lip=std(new THREE.Color(o.skin).lerp(new THREE.Color('#a8454a'),.45),.45);
    part(new THREE.SphereGeometry(1,low?8:20,low?6:12),lip,face,0,-.073,zs(0,-.073)-.0035).scale.set(.022,.0055,.008);
    part(new THREE.SphereGeometry(1,low?8:20,low?6:12),lip,face,0,-.083,zs(0,-.083)-.0035).scale.set(.019,.0065,.008);
    // cabelo
    const hairG=grp(face),hs=(r,tl,ph0,phl)=>{const g=new THREE.SphereGeometry(r,low?8:36,low?6:24,ph0,phl,0,tl);g.scale(.9,1.2,1);return g};
    if(o.hairStyle!=='none'){
      const long=o.hairStyle==='long',buzz=o.hairStyle==='buzz';
      part(hs(.1035,1.0,0,Math.PI*2),hair,hairG);
      part(hs(.1035,long?2.0:1.45,Math.PI,Math.PI),hair,hairG);
      if(!buzz){
        let seed=7;const rnd=()=>(seed=(seed*16807)%2147483647)/2147483647;
        for(let i=0;i<(low?0:(long?170:70));i++){
          const th=rnd()*(long?1.9:1.25),ph=rnd()*Math.PI*2,front=Math.sin(ph)>.2&&th>.85;if(front)continue;
          const d=V3(-Math.cos(ph)*Math.sin(th),Math.cos(th),Math.sin(ph)*Math.sin(th)),R=.104;
          const P0=V3(d.x*R*.9,d.y*R*1.2,d.z*R),dn=d.clone().multiplyScalar(.014),L=long&&d.z<.3?.16+rnd()*.1:.02+rnd()*.02;
          const P1=P0.clone().add(dn),P2=P1.clone().add(dn).add(V3(0,-L*.4,0)),P3=P2.clone().add(V3(d.x*.01,-L,d.z*.01));
          part(new THREE.TubeGeometry(new THREE.CatmullRomCurve3([P0,P1,P2,P3]),6,.0065+rnd()*.003,4),hair,hairG);
        }
      }
    }
    // acessórios de cabeça
    const acc=o.accessory;
    if(acc==='glasses'){
      for(const s of [-1,1]){const r=part(new THREE.TorusGeometry(.021,.0025,8,24),metal,face,s*.034,.018,zs(s*.034,.018)+.012);
        part(new THREE.CircleGeometry(.0205,20),new THREE.MeshPhysicalMaterial({color:'#223',transparent:true,opacity:.35,roughness:0,metalness:.3}),face,s*.034,.018,zs(s*.034,.018)+.0122);
        part(new THREE.BoxGeometry(.003,.003,.1),metal,face,s*.087,.02,-.03)}
      part(new THREE.BoxGeometry(.02,.003,.003),metal,face,0,.024,zs(0,.024)+.012);
    }
    if(acc==='mask'){const g=new THREE.SphereGeometry(.104,low?8:36,low?6:24,0,Math.PI*2,Math.PI*.62,Math.PI*.38);g.scale(.9,1.2,1);part(g,cloth('#161616'),face)}
    if(acc==='helmet'){const hm=std('#4d5a3a',.55,.1,{bumpMap:T.fabric,bumpScale:.5}),g=new THREE.SphereGeometry(.125,low?8:36,low?6:20,0,Math.PI*2,0,Math.PI*.55);g.scale(.98,1.12,1.1);
      part(g,hm,face,0,.015,-.004);const r=part(new THREE.TorusGeometry(.125,.006,8,40),hm,face,0,.03,-.004);r.rotation.x=Math.PI/2;r.scale.set(1,1.1,1)}
    if(acc==='cap'){const g=new THREE.SphereGeometry(.108,low?8:36,low?6:20,0,Math.PI*2,0,Math.PI*.5);g.scale(.92,1.15,1.03);part(g,shirt,face,0,.012,-.004);
      const v=part(new THREE.BoxGeometry(.15,.004,.1),shirt,face,0,.045,.13);v.rotation.x=.18}
    // braços
    const arm=(S,s)=>{
      const sh=J['s'+S]=grp(spine,s*.178*B,.515,0);
      // Keep the rounded shoulder seated inside the sleeve and torso seam.
      part(new THREE.SphereGeometry(.077*B,low?8:20,low?6:14),shirt,sh);
      part(limbGeo(.061*B,.048*B,.3),shirt,sh);
      const el=J['e'+S]=grp(sh,0,-.3,0);
      part(limbGeo(.049*B,.035*B,.27),shirt,el);
      const wr=J['w'+S]=grp(el,0,-.27,0);
      // Detailed articulated fingers are now mounted to wrist bones at runtime.
       // Keep the editor's palm as a fallback only when that hand system is absent.
       if(!window.JaimeArticulatedHands){const hd=part(new THREE.SphereGeometry(1,low?8:16,low?6:12),o.gloves?gloves:skin,wr,0,-.045,0);hd.scale.set(.036,.055,.026);}
      return wr;
    };
    const wL=arm('L',1),wR=arm('R',-1);
    if(o.weapon){
      const w=grp(wR,0,-.05,0),gm=std('#222428',.4,.7);
      part(new THREE.BoxGeometry(.05,.34,.08),gm,w,0,-.12,0);
      part(new THREE.CylinderGeometry(.012,.012,.32,12),metal,w,0,-.46,.02);
      part(new THREE.BoxGeometry(.045,.22,.07),gm,w,0,.2,-.01);
      part(new THREE.BoxGeometry(.04,.13,.06),gm,w,0,-.06,-.09).rotation.x=.15;
      part(new THREE.BoxGeometry(.02,.05,.02),metal,w,0,-.3,.055);
    }
    // pernas
    const leg=(S,s)=>{
      const th=J['t'+S]=grp(hips,s*.101*B,-.02,0);
      part(limbGeo(.109*B,.076*B,.46),pants,th);
      const kn=J['k'+S]=grp(th,0,-.46,0);
      part(limbGeo(.078*B,.054*B,.45),pants,kn);
      const bt=part(new THREE.CylinderGeometry(.055,.05,.16,18),boots,kn,0,-.37,0);
      const ft=J['f'+S]=grp(kn,0,-.45,0);
      part(new THREE.SphereGeometry(1,low?8:20,low?6:14),boots,ft,0,-.035,.045).scale.set(.058,.045,.126);
    };
    leg('L',1);leg('R',-1);
    // colete e mochila
    if(o.vest){
      part(new THREE.BoxGeometry(.31*B,.3,.06),vestM,spine,0,.39,.125*B);
      part(new THREE.BoxGeometry(.31*B,.3,.06),vestM,spine,0,.39,-.125*B);
      for(const s of [-1,1]){part(new THREE.BoxGeometry(.05,.1,.26*B),vestM,spine,s*.1*B,.57,0);
        part(new THREE.BoxGeometry(.075,.1,.05),vestM,spine,s*.11,.27,.15*B)}
      part(new THREE.BoxGeometry(.075,.1,.05),vestM,spine,0,.27,.15*B);
    }
    if(o.backpack){part(new THREE.BoxGeometry(.28*B,.38,.15),cloth('#4a4034'),spine,0,.38,-.22*B);
      part(new THREE.BoxGeometry(.2,.1,.08),cloth('#3a322a'),spine,0,.28,-.32*B)}
    this.materialSlots=new Map([[shirt,0],[pants,0],[vestM,1],[boots,3],[gloves,3],[metal,4],[skin,5],[lip,5],[hair,7],[dark,7]]);
    this.names=Object.keys(J);
  }
}
 const source=new JaimeSourceAvatar();source.root.updateMatrixWorld(true);
 const joints=new Map(Object.entries({hips:1,spine:3,neck:4,head:5,sR:6,eR:7,wR:8,sL:9,eL:10,wL:11,tR:12,kR:13,fR:14,tL:15,kL:16,fL:17}).map(([key,bone])=>[source.J[key],bone]));
 const sourceByBone=new Map([...joints].map(([joint,bone])=>[bone,joint])),children={6:7,7:8,9:10,10:11,12:13,13:14,15:16,16:17};
 const buckets=Array.from({length:8},()=>[]),v=new THREE.Vector3(),n=new THREE.Vector3();
 const geometries=new Set(),sourceMaterials=new Set();
 source.root.traverse(mesh=>{
  if(!mesh.isMesh)return;
  geometries.add(mesh.geometry);sourceMaterials.add(mesh.material);
  // Transparent corneal shells cannot be baked into an opaque material group.
  if(mesh.material.transparent&&mesh.material.opacity<.5)return;
  let parent=mesh.parent;while(parent&&!joints.has(parent))parent=parent.parent;
  const bone=joints.get(parent)||3;
  let slot=source.materialSlots.get(mesh.material);if(slot===undefined)slot=bone===5?6:7;
  const g=mesh.geometry,positions=g.attributes.position,normals=g.attributes.normal,uv=g.attributes.uv,normalMatrix=new THREE.Matrix3().getNormalMatrix(mesh.matrixWorld);
  const count=g.index?g.index.count:positions.count,color=mesh.material.color;
  const sourceOrigin=parent.getWorldPosition(new THREE.Vector3()).multiplyScalar(1.035);sourceOrigin.y+=.045;
  const targetOrigin=new THREE.Vector3().fromArray(bind[bone].slice(12,15)),rotation=new THREE.Quaternion();
  let sourceDirection=null,lengthScale=1;
  if(children[bone]){
   const child=children[bone],sourceChild=sourceByBone.get(child).getWorldPosition(new THREE.Vector3()).multiplyScalar(1.035);sourceChild.y+=.045;
   sourceDirection=sourceChild.sub(sourceOrigin);const sourceLength=sourceDirection.length();sourceDirection.normalize();
   const targetDirection=new THREE.Vector3().fromArray(bind[child].slice(12,15)).sub(targetOrigin);
   lengthScale=targetDirection.length()/sourceLength;rotation.setFromUnitVectors(sourceDirection,targetDirection.normalize());
  }
  for(let i=0;i<count;i++){
   const k=g.index?g.index.getX(i):i;
   v.fromBufferAttribute(positions,k).applyMatrix4(mesh.matrixWorld).multiplyScalar(1.035);v.y+=.045;
   n.fromBufferAttribute(normals,k).applyMatrix3(normalMatrix).normalize();
   // Retarget the visible limb, not just its bone: editor wrists/legs have different bind positions.
   if(bone>=6){
    v.sub(sourceOrigin);
    if(sourceDirection){v.addScaledVector(sourceDirection,v.dot(sourceDirection)*(lengthScale-1));n.addScaledVector(sourceDirection,n.dot(sourceDirection)*(1/lengthScale-1));}
    v.applyQuaternion(rotation).add(targetOrigin);n.applyQuaternion(rotation).normalize();
    if(bone===8||bone===11)v.y+=.035; // Palm center meets the weapon's grip target.
    if(bone===14||bone===17)v.y-=.09; // Keep soles on the existing physics floor.
    if((bone===13||bone===16)&&slot===3)v.y-=.11; // Boot shaft overlaps the lowered shoe.
   }
   // Skin parts are independent in the editor. Blend only the seam at elbows/knees.
   let other=bone,w=1;
   if([7,10,13,16].includes(bone)){other=parents[bone];w=clamp((bind[bone][13]-v.y+.07)/.14,0,1);}
   buckets[slot].push(v.x,v.y,v.z,n.x,n.y,n.z,uv?uv.getX(k):0,uv?uv.getY(k):0,color.r,color.g,color.b,bone,other,w,1-w);
  }
 });
 const position=[],normal=[],uv=[],color=[],skinIndex=[],skinWeight=[],geometry=new THREE.BufferGeometry();
 let first=0;
 for(let slot=0;slot<8;slot++){
  const b=buckets[slot];for(let i=0;i<b.length;i+=15){position.push(...b.slice(i,i+3));normal.push(...b.slice(i+3,i+6));uv.push(...b.slice(i+6,i+8));color.push(...b.slice(i+8,i+11));skinIndex.push(b[i+11],b[i+12],0,0);skinWeight.push(b[i+13],b[i+14],0,0);}
  geometry.addGroup(first,b.length/15,slot);first+=b.length/15;
 }
 geometry.setAttribute('position',new THREE.Float32BufferAttribute(position,3));geometry.setAttribute('normal',new THREE.Float32BufferAttribute(normal,3));geometry.setAttribute('uv',new THREE.Float32BufferAttribute(uv,2));geometry.setAttribute('color',new THREE.Float32BufferAttribute(color,3));geometry.setAttribute('skinIndex',new THREE.Uint16BufferAttribute(skinIndex,4));geometry.setAttribute('skinWeight',new THREE.Float32BufferAttribute(skinWeight,4));
 geometry.computeBoundingBox();geometry.computeBoundingSphere();geometry.userData.source='avatar_editor.html';geometry.userData.character='Jaime';
 for(const g of geometries)g.dispose();for(const m of sourceMaterials)m.dispose();
 return geometry;
}
// Deterministic surface maps: camo cloth, woven vest, leather, skin pores and hair.
// Generated once and shared by every Jaime; per-player tint materials remain independent.
function textures2K(){
 if(sharedTextures)return sharedTextures;
 function surface(size,kind){
  const albedo=new Uint8Array(size*size*4),relief=new Uint8Array(size*size*4),patches=new Float32Array(64*64);let seed=9137;
  for(let py=0;py<64;py++)for(let px=0;px<64;px++)patches[py*64+px]=Math.sin(px*.61+Math.sin(py*.42)*3)+Math.cos(py*.8+Math.sin(px*.35)*2);
  for(let y=0;y<size;y++)for(let x=0;x<size;x++){
   seed=(seed*1664525+1013904223)|0;const random=(seed>>>0)/4294967296,k=(y*size+x)*4;
   const weave=((x%4)<2?1:-1)*((y%4)<2?1:-1);
   let shade=238,depth=128;
   if(kind==='cloth'){
    const patch=patches[(y>>5)*64+(x>>5)];
    shade=patch>.75?247:patch<-.5?174:214;shade+=weave*3+(random-.5)*10;depth+=weave*18+(random-.5)*12;
   }else if(kind==='vest'){shade=225+weave*7+(random-.5)*12;depth+=weave*29;}
   else if(kind==='skin'){shade=243+(random-.5)*11;depth+=(random-.5)*19;}
   else if(kind==='hair'){shade=210+Math.sin(x*.8+Math.sin(y*.025))*20;depth+=Math.sin(x*.8)*30;}
   else{shade=221+(random-.5)*22;depth+=(random-.5)*38;}
   const shadeByte=shade<0?0:shade>255?255:shade|0,depthByte=depth<0?0:depth>255?255:depth|0;
   albedo[k]=albedo[k+1]=albedo[k+2]=shadeByte;relief[k]=relief[k+1]=relief[k+2]=depthByte;albedo[k+3]=relief[k+3]=255;
  }
  const make=(data,srgb)=>{const t=new THREE.DataTexture(data,size,size,THREE.RGBAFormat);t.wrapS=t.wrapT=THREE.RepeatWrapping;t.magFilter=THREE.LinearFilter;t.minFilter=THREE.LinearMipmapLinearFilter;t.generateMipmaps=true;t.anisotropy=4;if(srgb)t.encoding=THREE.sRGBEncoding;t.needsUpdate=true;return t;};
  return {map:make(albedo,true),bump:make(relief,false)};
 }
 sharedTextures={cloth:surface(2048,'cloth'),vest:surface(512,'vest'),skin:surface(512,'skin'),leather:surface(256,'leather'),hair:surface(256,'hair')};return sharedTextures;
}
function materials(team){
 const t=textures2K(),rough=[.87,.85,.94,.66,.38,.57,.18,.8],metal=[0,0,0,0,.8,0,.15,0],surfaces=[t.cloth,t.vest,t.leather,t.leather,t.leather,t.skin,null,t.hair];
 const list=rough.map((r,i)=>new THREE.MeshStandardMaterial({color:0xffffff,vertexColors:true,roughness:r,metalness:metal[i],skinning:true,map:surfaces[i]?.map||null,bumpMap:surfaces[i]?.bump||null,bumpScale:i===5?.00065:.002}));
 if(team==='red'){list[0].color.setRGB(2.4,.65,.55);list[1].color.setRGB(1.8,.5,.45)}
 return list;
}
class OperatorAvatar{
 constructor({team='player'}={}){
  this.characterName='Jaime';this.proceduralRig=true;this.ownsWeaponPose=true;this.weaponId='pistol';this.group=new THREE.Group();this.group.name='JAIME_MAIN_CHARACTER';this.group.userData.visualVariant='jaime-textured';this.group.scale.setScalar(.90);
  const list=materials(team);this.materials={fabric:list[0],vest:list[1],trim:list[2]};
  this.body=new THREE.SkinnedMesh(sharedGeometry||(sharedGeometry=buildGeometry()),list);this.body.name='JaimeSkin';this.body.castShadow=true;this.body.receiveShadow=true;this.body.frustumCulled=false;
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
  this.phase=0;this.time=0;this.state='idle';this.speed=0;this.aimBlend=0;this.crouchBlend=0;this.coverBlend=0;this.sprintBlend=0;this.prevSprintBlend=0;this.prevCrouchBlend=0;this.prevCoverBlend=0;this.wasGrounded=true;this.airTime=0;this.landingTime=1;
  // Transition snapshot prevents abrupt jumps between locomotion, aiming and airborne poses.
  this.poseTransition=null;this.lastPoseState=null;this.lastDesiredPose=null;
  this.footPlant={left:0,right:0};this.crawlPhase=0;this.crawlBlend=0;this.stairBlend=0;this.directionChangeBlend=0;this.pivotDirection=0;
  this.fireReadyBlend=0;
  window.JaimeArticulatedHands?.attach(THREE,this);
  this.weaponSwapTime=0;this.weaponSwapDuration=.4;this.weaponSwapFrom='pistol';
  this.update(0,{armed:false});
 }
 mountBackpack(object){
  // Anchor to the chest bind frame so equipment follows crouch, crawl and turns.
  // Retain the existing standing placement and size despite the avatar's 0.9 scale.
  const scale=this.group.scale.y;
  object.position.set(-bind[3][12],1.28/scale-bind[3][13],-.34/scale-bind[3][14]);
  object.rotation.set(0,0,0);object.scale.multiplyScalar(1/scale);
  this.torso.add(object);return object;
 }
 setWeapon(id){
  if(!id||id===this.weaponId)return;
  this.weaponSwapFrom=this.weaponId;
  this.weaponId=id;
  this.weaponSwapDuration=id==='sniper'?.58:id==='shotgun'?.48:id==='rifle'?.42:id==='smg'?.34:.29;
  this.weaponSwapTime=this.weaponSwapDuration;
 }
 setRecoil(value){this.recoil=value;}
 update(dt,{dead=false,speed=0,grounded=true,armed=false,aiming=false,sprinting=speed>8,verticalVelocity=0,jumpPreparation=0,jumpForce=8.5,gravity=-22,recoil=this.recoil||0,crouching=false,prone=0,proneSlope=0,proneRoll=0,covering=false,coverSide=1,strafe=0,forward=0,braking=0,turn=0,turnSharpness=0,aimTransition=0,stepBlend=0,landingImpact=0,hardLanding=0,recovery=0,reload=0,equip=0,hitStrength=0,hitSide=0,hitFront=0,optic=false,stock=false,suppressed=false,footLeft=0,footRight=0,firing=false}={}){
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
  this.time+=dt;this.weaponSwapTime=Math.max(0,this.weaponSwapTime-dt);this.speed=M.damp(this.speed,speed,12,dt);this.aimBlend=M.damp(this.aimBlend,armed?1:0,12,dt);
  // Firing interrupts the lowered sprint carry; returning to sprint remains smooth.
  const activeFire=armed&&firing;
  const fireReadiness=activeFire?1:aiming&&armed?1:0;
  this.fireReadyBlend=M.damp(this.fireReadyBlend,fireReadiness,activeFire?22:10,dt);
  const sprintTarget=armed&&sprinting&&grounded&&!aiming&&!activeFire?1:0;
  const oldSprint=this.sprintBlend;
  this.sprintBlend=M.damp(this.sprintBlend,sprintTarget,activeFire?24:sprinting?13:11,dt);
  const sprintRate=dt>0?(this.sprintBlend-oldSprint)/dt:0;
  const oldCrouch=this.crouchBlend,oldCover=this.coverBlend;
  this.crouchBlend=M.damp(this.crouchBlend,crouching&&grounded?1:0,12,dt);this.coverBlend=M.damp(this.coverBlend,covering?1:0,12,dt);
  const crouchRate=dt>0?(this.crouchBlend-oldCrouch)/dt:0,coverRate=dt>0?(this.coverBlend-oldCover)/dt:0;
  if(!grounded){if(this.wasGrounded)this.airTime=0;this.airTime+=dt;this.landingTime=1}
  else if(!this.wasGrounded)this.landingTime=0;
  else this.landingTime=Math.min(1,this.landingTime+dt);
  let state=speed>.1?(sprinting?'run':'walk'):'idle';if(armed&&aiming&&speed<.1)state='aim';
  // Match stride cadence to actual velocity, avoiding the "running in place" impression.
  const runCadence=clamp(this.speed/10,.70,1.28);
  const walkCadence=clamp(this.speed/4,.65,1.3);
  const duration=state==='run'?.84/runCadence:state==='walk'?1.15/walkCadence:4;
  this.phase+=dt/duration*(1-this.crouchBlend*.45);
  let phase=this.phase;
  if(jumpPreparation>0){state='jump';phase=.22*clamp(1-jumpPreparation/.12,0,1)}
  else if(!grounded){
   // The descending section becomes a separate falling posture rather than freezing mid-jump.
   if(verticalVelocity< -3 && this.airTime>.24){
    state='fall';phase=this.time*.43;
   }else{
    state='jump';
    const flight=Math.max(.25,2*jumpForce/Math.abs(gravity));
    phase=this.airTime<.10?.22+.13*M.curveMotion([[0,0],[1,1]],this.airTime/.10):.35+.37*clamp((this.airTime-.10)/(flight-.10),0,1);
   }
  }
  else if(this.landingTime<.34){state='jump';phase=.72+.28*clamp(this.landingTime/.34,0,1)}
  this.wasGrounded=grounded;this.state=state;
  const pose=M.sampleMotion(state,phase,armed,this.weaponId),r=pose.r;
  const proneIntent=grounded&&prone>.5;
  const poseKey=state+'|'+(armed?'armed':'unarmed')+'|'+(aiming?'ads':'hip')+'|'+(proneIntent?'prone':crouching?'crouch':'stand');
  if(this.lastPoseState!==null&&this.lastPoseState!==poseKey){
   this.poseTransition={from:this.lastDesiredPose?this.lastDesiredPose.map(j=>j.slice()):this.rotations.map(j=>j.slice()),elapsed:0,duration:proneIntent?.40:state==='jump'?.16:state==='fall'?.21:state==='aim'?.13:.25};
  }
  this.lastPoseState=poseKey;
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

  if(armed&&grounded&&this.fireReadyBlend>.002&&speed>.3){
   // Combat gait stabilizes the weapon shoulder without freezing running legs.
   const moving=clamp(speed/9,0,1)*this.fireReadyBlend;
   const sideways=clamp(strafe,-1,1);
   r[2][0]-=.035*moving;
   r[3][0]-=.06*moving;
   r[1][1]+=sideways*.035*moving;
   r[3][1]-=sideways*.04*moving;
   r[12][0]*=1-.065*moving;
   r[15][0]*=1-.065*moving;
   r[13][0]+=.085*moving;
   r[16][0]+=.085*moving;
  }

  if(armed&&this.sprintBlend>.001){
   const s=clamp(this.sprintBlend,0,1);
   const q=this.phase*Math.PI*2;
   const heavy=this.weaponId==='sniper'?1.15:this.weaponId==='shotgun'?1.08:this.weaponId==='rifle'?1:.84;
   // Lower the weapon into a true sprint carry while keeping it clear of the legs.
   r[2][0]+=.08*s*heavy;
   r[3][0]+=.14*s*heavy;
   r[3][1]-=.07*Math.sin(q)*s;
   r[6][0]+=.20*s*heavy;
   r[9][0]+=.16*s*heavy;
   r[7][0]+=.10*s;
   r[10][0]+=.08*s;
   r[1][2]+=.018*Math.sin(q)*s;
   pose.root[1]-=.012*s;

   // When sprint ends, the upper body catches the gun before returning to ready.
   if(sprintRate<-.01){
    const recover=clamp(-sprintRate/6,0,1);
    r[2][0]+=.05*recover;
    r[3][0]-=.07*recover;
    r[6][0]-=.08*recover;
    r[9][0]-=.06*recover;
   }
  }

  if(hitStrength>.001){
   const h=clamp(hitStrength,0,1),side=clamp(hitSide,-1,1),front=clamp(hitFront,-1,1);
   const fromFront=Math.max(0,front),fromBack=Math.max(0,-front);
   r[1][2]-=side*.10*h;
   r[2][2]-=side*.14*h;
   r[3][2]-=side*.17*h;
   r[3][1]+=side*.08*h;
   r[5][2]-=side*.08*h;
   r[2][0]-=.10*fromFront*h;
   r[3][0]-=.14*fromFront*h;
   r[2][0]+=.10*fromBack*h;
   r[3][0]+=.12*fromBack*h;
   const hitArm=side>=0?6:9;
   const otherArm=side>=0?9:6;
   r[hitArm][0]+=.18*h;
   r[hitArm][2]-=Math.sign(side||1)*.12*h;
   r[otherArm][0]+=.05*h;
   if(grounded){
    const hitLeg=side>=0?12:15;
    r[hitLeg][0]-=.06*h;
    r[hitLeg+1][0]+=.10*h;
   }
   pose.root[0]-=side*.012*h;
   pose.root[2]-=.012*fromFront*h;
   pose.root[2]+=.010*fromBack*h;
  }

  if(armed&&recoil>.001){
   const id=this.weaponId||'pistol';
   const kick=id==='pistol'?.72:id==='smg'?.48:id==='rifle'?.78:id==='shotgun'?1.28:1.12;
   const torsoKick=recoil*kick;
   const shoulderKick=torsoKick*(id==='smg'?.55:.8);
   r[1][0]-=.045*torsoKick;
   r[2][0]-=.075*torsoKick;
   r[3][0]-=.095*torsoKick;
   r[3][2]+=(id==='shotgun'?.024:id==='sniper'?.018:.010)*torsoKick;
   r[6][0]+=.10*shoulderKick;
   r[9][0]+=.07*shoulderKick;
   r[7][0]+=.06*shoulderKick;
   r[10][0]+=.04*shoulderKick;
   pose.root[2]-=.010*torsoKick;
   if(id==='shotgun'||id==='sniper'){
    r[12][0]-=.025*torsoKick;
    r[15][0]+=.018*torsoKick;
    r[13][0]+=.045*torsoKick;
    r[16][0]+=.035*torsoKick;
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

  // Short lateral correction steps when changing direction, with shoulders counter-rotating
  // to keep the sight stable. Does not rotate the player's world-space facing.
  const wantedPivot=grounded?clamp(turnSharpness,0,1)*clamp(speed/5,0,1):0;
  this.directionChangeBlend=M.damp(this.directionChangeBlend,wantedPivot,wantedPivot>this.directionChangeBlend?16:9,dt);
  this.pivotDirection=M.damp(this.pivotDirection,clamp(turn,-1,1),13,dt);
  if(this.directionChangeBlend>.002){
   const strength=this.directionChangeBlend,side=this.pivotDirection;
   const lead=side>=0?15:12,trail=side>=0?12:15;
   const grip=aiming?0.52:1;
   r[lead][2]+=.19*side*strength;
   r[trail][2]-=.14*side*strength;
   r[lead+1][0]+=.32*strength;
   r[trail+1][0]+=.13*strength;
   r[1][1]+=side*.18*strength;
   r[2][1]-=side*.11*strength*grip;
   r[3][1]-=side*.12*strength*grip;
   r[1][2]+=side*.045*strength;
   r[2][2]-=side*.026*strength;
   pose.root[1]-=.020*strength;
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

  if(armed&&this.weaponSwapTime>0){
   // Two-stage visual swap; movement and shot availability remain in their controllers.
   const t=1-this.weaponSwapTime/this.weaponSwapDuration;
   const lower=t<.36?Math.sin(t/.36*Math.PI*.5):Math.max(0,1-(t-.36)/.64);
   const switchCurve=lower*lower*(3-2*lower);
   const running=grounded?clamp(speed/10,0,1):0;
   r[2][0]+=.12*switchCurve;
   r[3][0]+=.17*switchCurve;
   r[3][1]+=.11*switchCurve;
   r[6][0]+=.22*switchCurve;
   r[9][0]+=.19*switchCurve;
   r[7][0]+=.08*switchCurve;
   r[10][0]+=.07*switchCurve;
   r[1][0]+=.035*switchCurve*running;
   pose.root[1]-=.018*switchCurve;
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
   const accessoryAim=aiming?1:0;
   if(stock&&this.weaponId!=='pistol'){
    r[2][0]-=.025*accessoryAim;
    r[3][0]-=.035*accessoryAim;
    r[3][1]+=.018*accessoryAim;
    r[6][0]-=.045*accessoryAim;
    r[9][0]-=.025*accessoryAim;
   }
   if(optic&&aiming){
    r[5][0]-=.025;
    r[3][1]-=.018;
   }
   if(suppressed&&this.weaponId!=='pistol'){
    r[6][0]+=.018;
    r[9][0]+=.012;
   }
   const a=pose.weaponAngles.slice();
   if(this.weaponSwapTime>0){
    const t=1-this.weaponSwapTime/this.weaponSwapDuration;
    const lower=t<.36?Math.sin(t/.36*Math.PI*.5):Math.max(0,1-(t-.36)/.64);
    const switchCurve=lower*lower*(3-2*lower);
    a[0]+=.48*switchCurve;
    a[1]+=.14*switchCurve;
    a[2]+=.09*switchCurve;
   }
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
   if(this.sprintBlend>.001){
    const s=clamp(this.sprintBlend,0,1);
    const heavy=this.weaponId==='sniper'?1.15:this.weaponId==='shotgun'?1.08:this.weaponId==='rifle'?1:.84;
    a[0]+=.52*s*heavy;
    a[1]+=.10*s;
    a[2]+=.06*Math.sin(this.phase*Math.PI*2)*s;
   }
   // Raise the weapon from its sprint carry into a supported hip-fire position.
   const ready=this.fireReadyBlend*clamp(speed/8,0,1);
   a[0]-=.16*ready;
   a[1]-=clamp(strafe,-1,1)*.024*ready;
   const recoilScale=this.weaponId==='pistol'?.045:this.weaponId==='smg'?.030:this.weaponId==='rifle'?.050:this.weaponId==='shotgun'?.085:.072;
   a[0]+=.40*this.coverBlend-recoil*recoilScale;
   a[1]+=coverSide*.12*this.coverBlend;
   if(stock&&this.weaponId!=='pistol')a[0]-=.035*(aiming?1:.35);
   if(optic&&aiming){a[0]-=.025;a[1]-=.012;}
   if(suppressed&&this.weaponId!=='pistol')a[0]+=.012;
   if(aiming&&grounded&&speed>.08){
    a[0]-=.10*clamp(aimTransition,0,1);
    a[1]-=clamp(strafe,-1,1)*.035;
    a[2]+=clamp(strafe,-1,1)*.018;
   }
   for(let k=0;k<3;k++)this.weaponAngles[k]=M.damp(this.weaponAngles[k],a[k],22,dt);
   // Smooth transition between low-ready and eye-level ADS, including while walking.
   const longGun=this.weaponId!=='pistol';
   const tacticalAds=longGun&&armed?clamp(aimTransition,0,1)*(1-clamp(reload,0,1)):0;
   pose.weapon=M.weaponFrame(this.weaponAngles,this.weaponId,tacticalAds);
   // Shoulder-supported rifle: subtle forward chest lean and cheek weld.
   // Applied before IK so the hands remain attached to the receiver.
   if(tacticalAds>.001){
     // Reference posture: shoulder the stock, lean slightly into recoil,
     // bring cheek closer to the sights and keep the rifle square to target.
     r[2][0]+=.058*tacticalAds;
     r[3][0]+=.044*tacticalAds;
     r[3][1]-=.018*tacticalAds;
     r[5][0]+=.082*tacticalAds;
     r[5][1]-=.036*tacticalAds;
     a[0]-=.014*tacticalAds;
     a[1]-=.018*tacticalAds;
    }
   const grips=this.weaponId==='pistol'?M.pistolGrips:M.rifleGrips;M.armedMotion(r,pose.weapon,grips);
   this.gripBindPoints=grips.map(([upper,p])=>({bone:upper+2,point:new THREE.Vector3().fromArray(M.pointArm(pose.weapon,p))}));
   const matrix=new THREE.Matrix4().fromArray(pose.weapon).multiply(new THREE.Matrix4().makeTranslation(.055,1.34,.245));matrix.premultiply(new THREE.Matrix4().makeTranslation(-bind[3][12],-bind[3][13],-bind[3][14]));matrix.decompose(this.gun.position,this.gun.quaternion,this.gun.scale);
  }
  // Post-IK manipulation: the support hand must leave the weapon grip during reload.
  // Apply after armedMotion, which otherwise replaces shoulder/elbow rotations.
  if(armed&&reload>.001){
   const t=clamp(reload,0,1),id=this.weaponId||'pistol';
   const ease=u=>{u=clamp(u,0,1);return u*u*(3-2*u);};
   const windowPulse=(start,peak,end)=>Math.min(ease((t-start)/(peak-start)),ease((end-t)/(end-peak)));
   const mag=id==='shotgun'?0:windowPulse(.10,.38,.79);
   const shells=id==='shotgun'?Math.pow(Math.sin(Math.PI*clamp((t-.12)/.74,0,1)*3),2)*windowPulse(.08,.55,.9):0;
   const bolt=id==='sniper'?windowPulse(.58,.71,.91):0;
   const reach=Math.max(mag,shells,bolt);
   const speedBlend=grounded?clamp(speed/8,0,1):0;
   if(reach>.001){
    // The left hand manipulates the magazine/shells while the right holds the receiver.
    // M.armedMotion has already solved the normal two-hand grip; interpolate away from it.
    const leftShoulder=9,leftElbow=10,leftWrist=11;
    const targetShoulder=id==='pistol'?[-.63,.39,-.22]:id==='shotgun'?[-.91,.24,-.29]:id==='sniper'?[-.77,.31,-.17]:[-.82,.32,-.13];
    const targetElbow=id==='pistol'?-1.27:id==='shotgun'?-1.50:id==='sniper'?-1.32:-1.43;
    for(let k=0;k<3;k++)r[leftShoulder][k]=THREE.MathUtils.lerp(r[leftShoulder][k],targetShoulder[k],reach*.85);
    r[leftElbow][0]=THREE.MathUtils.lerp(r[leftElbow][0],targetElbow,reach*.85);
    r[leftWrist][0]+=reach*.16;
    if(bolt>.001){r[6][0]+=.09*bolt;r[7][0]+=.14*bolt;}
   }
   if(speedBlend>.001){
    // Keep the feet walking while the upper body steadies the receiver during reload.
    const stability=speedBlend*windowPulse(.03,.42,.97);
    r[1][0]+=.035*stability;
    r[2][0]+=.065*stability;
    r[3][0]+=.045*stability;
    r[3][1]-=clamp(strafe,-1,1)*.04*stability;
    r[12][0]*=1-.10*stability;r[15][0]*=1-.10*stability;
    r[13][0]+=.07*stability;r[16][0]+=.07*stability;
    pose.root[1]-=.012*stability;
   }
  }

  // Visual foot placement: ground probes affect only the lower body, never physics.
  // Reduce correction while running to preserve free, rhythmic leg swings.
  const footWeight=grounded?clamp((8-speed)/8,0,.95)*(1-this.crouchBlend*.35):0;
  const footTargets=[['left',15,footLeft],['right',12,footRight]];
  for(const [side,hip,height] of footTargets){
   const goal=clamp(Number.isFinite(height)?height:0,-.24,.24)*footWeight;
   this.footPlant[side]=M.damp(this.footPlant[side],goal,grounded?12:17,dt);
   const h=this.footPlant[side];
   // Positive ledge heights lift the thigh and flex the knee; downward slopes extend it.
   r[hip][0]-=h*.54;
   r[hip+1][0]+=h*1.16;
   r[hip+2][0]-=h*.68;
  }
  // Stair gait: alternating lift with a slight forward body lean and knee recovery.
  // StepBlend originates from the existing step-up collision controller.
  const footDifference=Math.abs(footLeft-footRight);
  const stairIntent=grounded&&speed>.12?clamp(Math.max(stepBlend*.9,footDifference*2.0),0,1):0;
  this.stairBlend=M.damp(this.stairBlend,stairIntent,stairIntent>this.stairBlend?10:6,dt);
  if(this.stairBlend>.001){
   const lift=this.stairBlend;
   const cadence=this.phase*Math.PI*2;
   const l=Math.max(0,Math.sin(cadence)),rStep=Math.max(0,-Math.sin(cadence));
   r[15][0]-=.25*l*lift;r[16][0]+=.53*l*lift;r[17][0]-=.16*l*lift;
   r[12][0]-=.25*rStep*lift;r[13][0]+=.53*rStep*lift;r[14][0]-=.16*rStep*lift;
   r[1][0]+=.055*lift;r[2][0]+=.085*lift;r[3][0]+=.04*lift;
   pose.root[1]-=.015*lift;
  }
  // Prone pose: the 18-bone rig folds forward without replacing the
  // Soldier, weapon inventory, hit mesh, or existing walk/crouch animations.
  const proneWeight=clamp(prone,0,1);
  // Distinct crawl locomotion layer: tied to actual ground speed rather than
  // input, so stationary prone aiming remains completely still.
  const crawlTarget=grounded&&proneWeight>.01?clamp((speed-.035)/.42,0,1)*proneWeight:0;
  this.crawlBlend=M.damp(this.crawlBlend,crawlTarget,crawlTarget>this.crawlBlend?8:10,dt);
  if(crawlTarget>.01)this.crawlPhase+=dt*Math.max(.45,speed)*4.6;
  if(proneWeight>.001&&grounded){
   const flat=Array.from({length:18},()=>[0,0,0]);
   flat[0][0]=Math.PI/2+clamp(proneSlope,-.25,.25)*.60;
   flat[0][2]=clamp(proneRoll,-.16,.16)*.65;
   flat[1][0]=-.045;
   flat[2][0]=.065;
   flat[3][0]=-.035;
   flat[4][0]=-.06;
   flat[5][0]=-.10;
   // Keep weapon-solving IK as the baseline: the wrists must stay on the gun.
   // Lean the upper arms toward the soil without breaking their hand grips.
   flat[6]=r[6].slice();flat[7]=r[7].slice();flat[8]=r[8].slice();
   flat[9]=r[9].slice();flat[10]=r[10].slice();flat[11]=r[11].slice();
   flat[6][2]+=.13;flat[9][2]-=.13;
   // Straight legs trail behind the pelvis, slightly separated at the boots.
   flat[12]=[-.10,0,-.06];flat[13]=[.16,0,.025];flat[14]=[-.08,0,0];
   flat[15]=[-.11,0,.07];flat[16]=[.18,0,-.025];flat[17]=[-.08,0,0];
   // Opposing elbow/leg pulls for crawling. Keep hands and weapon in their
   // IK grip; only tiny upper-arm movement while firing or aiming.
   const crawl=this.crawlBlend;
   if(crawl>.001){
    const wave=Math.sin(this.crawlPhase),opposite=Math.sin(this.crawlPhase+Math.PI);
    const armFactor=armed?(aiming?.20:.42):1;
    flat[6][0]+=.16*wave*crawl*armFactor;
    flat[9][0]+=.16*opposite*crawl*armFactor;
    flat[6][2]+=.065*wave*crawl*armFactor;
    flat[9][2]-=.065*opposite*crawl*armFactor;
    flat[12][0]+=.18*opposite*crawl;
    flat[15][0]+=.18*wave*crawl;
    flat[13][0]+=.32*Math.max(0,opposite)*crawl;
    flat[16][0]+=.32*Math.max(0,wave)*crawl;
    flat[14][0]-=.14*Math.max(0,opposite)*crawl;
    flat[17][0]-=.14*Math.max(0,wave)*crawl;
   }
   for(let bone=0;bone<18;bone++)for(let axis=0;axis<3;axis++){
    r[bone][axis]=THREE.MathUtils.lerp(r[bone][axis],flat[bone][axis],proneWeight);
   }
   // Keep the belly above ground and avoid root-height pops while going
   // from crouched to prone. The spine rotates gradually with proneWeight.
   pose.root[1]=THREE.MathUtils.lerp(pose.root[1],.21,proneWeight);
   // Damp idle rocking while the elbows are braced.
   pose.root[0]*=1-proneWeight;
   pose.root[2]*=1-proneWeight;
   if(armed){
    const counter=new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1,0,0),-Math.PI/2*proneWeight);
    // The weapon mount is freshly solved each frame in the armed branch.
    this.gun.quaternion.premultiply(counter);
    this.gun.position.y+=.09*proneWeight;
    this.gun.position.z+=.10*proneWeight;
   }
  }
  // Apply crossfade after procedural reactions and arm IK have been calculated.
  if(this.poseTransition){
   const transition=this.poseTransition;transition.elapsed+=dt;
   const t=clamp(transition.elapsed/transition.duration,0,1),smooth=t*t*(3-2*t);
   for(let bone=0;bone<18;bone++)for(let axis=0;axis<3;axis++){
    r[bone][axis]=transition.from[bone][axis]*(1-smooth)+r[bone][axis]*smooth;
   }
   if(t>=1)this.poseTransition=null;
  }
  // Keep the target for a future crossfade, including weapon IK and landing reactions.
  if(!this.lastDesiredPose)this.lastDesiredPose=Array.from({length:18},()=>[0,0,0]);
  for(let i=0;i<18;i++)for(let k=0;k<3;k++){
   this.lastDesiredPose[i][k]=r[i][k];
   this.rotations[i][k]=M.damp(this.rotations[i][k],r[i][k],22,dt);
  }
  for(let k=0;k<3;k++)this.shift[k]=M.damp(this.shift[k],pose.root[k],22,dt);
  for(let i=0;i<18;i++){this.bones[i].position.fromArray(offsets[i]);if(i===0)this.bones[i].position.add(new THREE.Vector3().fromArray(this.shift));this.bones[i].rotation.set(...this.rotations[i],'ZYX')}
  window.JaimeArticulatedHands?.update(this,THREE,dt,armed,aiming,reload);
   this.gun.visible=armed;this.group.updateMatrixWorld(true);this.skeleton.update();
  this.weaponGripTargets=(this.gripBindPoints||[]).map(g=>({bone:g.bone,point:this.group.worldToLocal(this.bones[3].localToWorld(g.point.clone().sub(new THREE.Vector3().fromArray(bind[3].slice(12,15)))))}));
 }
}
window.OperatorAvatar=OperatorAvatar;
})();
