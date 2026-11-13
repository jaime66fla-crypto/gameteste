window.addEventListener('error',e=>{const s=document.getElementById('state');if(s)s.textContent='ERRO: '+(e.message||'falha JS')});
window.addEventListener('unhandledrejection',e=>{const s=document.getElementById('state');if(s)s.textContent='ERRO: '+(e.reason?.message||e.reason||'promise')});

const canvas=document.getElementById('view');
const stateEl=document.getElementById('state');
const renderer=new THREE.WebGLRenderer({canvas,antialias:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio,1.35));
renderer.shadowMap.enabled=true;
renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.outputColorSpace=THREE.SRGBColorSpace;
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=.95;

// Lightweight in-game performance monitor. F8 toggles expanded metrics.
const performancePanel=(()=>{
 const root=document.createElement('section');
 root.id='gameteste-performance';
 root.setAttribute('aria-label','Monitor de desempenho');
 root.style.cssText='position:fixed;left:12px;bottom:12px;z-index:35;pointer-events:none;min-width:112px;max-width:235px;color:#eaf7ff;font:600 11px/1.5 system-ui,Arial;background:rgba(6,17,24,.84);border:1px solid rgba(133,187,209,.5);border-radius:9px;padding:8px 10px;box-shadow:0 5px 20px #0005;font-variant-numeric:tabular-nums';
 const header=document.createElement('div');header.style.cssText='display:flex;align-items:center;justify-content:space-between;gap:8px';
 const headline=document.createElement('strong');headline.textContent='FPS --';headline.style.cssText='color:#85e8ac;font-size:16px;white-space:nowrap';
 const toggle=document.createElement('button');toggle.type='button';toggle.textContent='DETALHES';toggle.title='Alternar detalhes (F8)';
 toggle.style.cssText='pointer-events:auto;cursor:pointer;background:#244454;color:#dff5ff;border:1px solid #527688;border-radius:5px;font:700 9px system-ui;padding:3px 5px';
 header.append(headline,toggle);
 const details=document.createElement('div');details.hidden=true;details.style.cssText='margin-top:5px;border-top:1px solid #ffffff24;padding-top:5px;white-space:pre-line;font-size:10px;color:#c8dfe9';
 root.append(header,details);document.body.appendChild(root);
 let expanded=false,frames=0,elapsed=0,lastFrameTime=0,lastSample=performance.now();
 let durations=[],snapshot=null;
 function togglePanel(){expanded=!expanded;details.hidden=!expanded;toggle.textContent=expanded?'OCULTAR':'DETALHES';}
 toggle.addEventListener('click',togglePanel);
 addEventListener('keydown',e=>{if(e.code==='F8'){e.preventDefault();togglePanel();}});
 function frame(deltaMs){
  if(!Number.isFinite(deltaMs)||deltaMs<=0)return;
  frames++;elapsed+=deltaMs;lastFrameTime=deltaMs;durations.push(deltaMs);
  if(durations.length>180)durations.shift();
  if(elapsed<1000)return;
  const fps=Math.round(frames*1000/elapsed);
  const ordered=durations.slice().sort((a,b)=>a-b);
  const p99=ordered[Math.min(ordered.length-1,Math.floor(ordered.length*.99))]||0;
  const low1=p99>0?Math.round(1000/p99):0;
  const avgMs=elapsed/Math.max(1,frames);
  const info=renderer.info;
  snapshot={
   fps,frameMs:Number(avgMs.toFixed(1)),fpsLow1:low1,
   drawCalls:info.render.calls,triangulos:info.render.triangles,
   geometriasNaMemoria:info.memory.geometries,texturasNaMemoria:info.memory.textures,
   memoriaJS:performance.memory?Number((performance.memory.usedJSHeapSize/1048576).toFixed(1)):null
  };
  headline.textContent='FPS '+fps+'  |  '+avgMs.toFixed(1)+' ms';
  headline.style.color=fps>=55?'#85e8ac':fps>=30?'#ffd57c':'#ff8e88';
  if(expanded)details.textContent='1% baixo (estim.): '+low1+' FPS\\nDraw calls: '+snapshot.drawCalls+'\\nTriângulos: '+snapshot.triangulos.toLocaleString('pt-BR')+'\\nGeometrias: '+snapshot.geometriasNaMemoria+'  • Texturas: '+snapshot.texturasNaMemoria+(snapshot.memoriaJS===null?'':'\\nMemória JS: '+snapshot.memoriaJS+' MB');
  elapsed=0;frames=0;lastSample=performance.now();
 }
 return {frame,getSnapshot:()=>snapshot,toggle:togglePanel};
})();
window.gametesteRenderStats=()=>{
 const stats=performancePanel.getSnapshot();
 if(stats)console.log('[Gameteste 3D] Desempenho',stats);
 return stats;
};

const scene=new THREE.Scene();
const camera=new THREE.PerspectiveCamera(58,innerWidth/innerHeight,.1,250);


function buildForestEnvironment(scene,options={}){
 const {
  mapSize=300,
  treeCount=180,
  rockCount=60,
  bushCount=90,
  safeZoneRadius=25,
  seed=42
 }=options;

 let currentSeed=seed;
 function random(){
  const x=Math.sin(currentSeed++)*10000;
  return x-Math.floor(x);
 }

 const skyColor=new THREE.Color(0x91b5c9);
 const fogColor=new THREE.Color(0x9eaf9e);
 scene.background=skyColor;
 scene.fog=new THREE.FogExp2(fogColor,.0038);

 const hemiLight=new THREE.HemisphereLight(0xc3d5e1,0x394431,.55);
 hemiLight.position.set(0,50,0);
 scene.add(hemiLight);

 const sunLight=new THREE.DirectionalLight(0xffd3a1,1.1);
 sunLight.position.set(60,75,40);
 sunLight.castShadow=true;
 sunLight.shadow.mapSize.width=1024;
 sunLight.shadow.mapSize.height=1024;
 sunLight.shadow.camera.near=10;
 sunLight.shadow.camera.far=250;
 const d=100;
 sunLight.shadow.camera.left=-d;
 sunLight.shadow.camera.right=d;
 sunLight.shadow.camera.top=d;
 sunLight.shadow.camera.bottom=-d;
 sunLight.shadow.bias=-.0005;
 scene.add(sunLight);

 const groundGeo=new THREE.PlaneGeometry(mapSize,mapSize,64,64);
 groundGeo.rotateX(-Math.PI/2);
 const posAttr=groundGeo.attributes.position;
 for(let i=0;i<posAttr.count;i++){
  const x=posAttr.getX(i);
  const z=posAttr.getZ(i);
  const distFromCenter=Math.hypot(x,z);
  if(distFromCenter>safeZoneRadius){
   const factor=Math.min((distFromCenter-safeZoneRadius)/40,1);
   const height=(Math.sin(x*.05)*Math.cos(z*.05)*2.5+Math.sin(x*.12+z*.1)*.8)*factor;
   posAttr.setY(i,height);
  }
 }
 groundGeo.computeVertexNormals();
 // Broad, continuous color patches give the terrain variation without adding
 // textures, extra draw calls, or consuming the seeded object-placement RNG.
 const terrainColors=new Float32Array(posAttr.count*3);
 const grassDark=new THREE.Color(0x606f43),grassLight=new THREE.Color(0x81905c);
 const earth=new THREE.Color(0x8b7658),terrainColor=new THREE.Color();
 for(let i=0;i<posAttr.count;i++){
  const x=posAttr.getX(i),z=posAttr.getZ(i);
  const patch=.5+.25*Math.sin(x*.08+Math.cos(z*.06))+.25*Math.cos(z*.095-x*.03);
  terrainColor.copy(grassDark).lerp(grassLight,patch);
  const dry=THREE.MathUtils.clamp((Math.sin(x*.027)+Math.cos(z*.041))*.5-.42,0,.15);
  terrainColor.lerp(earth,dry).toArray(terrainColors,i*3);
 }
 groundGeo.setAttribute('color',new THREE.BufferAttribute(terrainColors,3));

 const groundMat=new THREE.MeshStandardMaterial({
  color:0xffffff,
  vertexColors:true,
  roughness:.9,
  metalness:0,
  flatShading:true
 });
 const ground=new THREE.Mesh(groundGeo,groundMat);
 ground.userData.impactMaterial='dirt';ground.receiveShadow=true;
 scene.add(ground);

 function getTerrainHeight(x,z){
  const distFromCenter=Math.hypot(x,z);
  if(distFromCenter<=safeZoneRadius)return 0;
  const factor=Math.min((distFromCenter-safeZoneRadius)/40,1);
  return (Math.sin(x*.05)*Math.cos(z*.05)*2.5+Math.sin(x*.12+z*.1)*.8)*factor;
 }

 const trunkMat=new THREE.MeshStandardMaterial({color:0x614a36,roughness:.9,flatShading:true});
 const leafMaterials=[
  new THREE.MeshStandardMaterial({color:0x35543a,roughness:.8,flatShading:true}),
  new THREE.MeshStandardMaterial({color:0x617a43,roughness:.8,flatShading:true}),
  new THREE.MeshStandardMaterial({color:0x456442,roughness:.8,flatShading:true})
 ];
 const rockMat=new THREE.MeshStandardMaterial({color:0x777b73,roughness:.85,flatShading:true});

 const forestGroup=new THREE.Group();
 const colliders=[];

 function createPineTree(scale){
  const tree=new THREE.Group();
  const mat=leafMaterials[Math.floor(random()*leafMaterials.length)];

  const trunkGeo=new THREE.CylinderGeometry(.35*scale,.55*scale,2.5*scale,6);
  const trunk=new THREE.Mesh(trunkGeo,trunkMat);
  trunk.position.y=1.25*scale;
  trunk.castShadow=false;
  trunk.receiveShadow=true;
  tree.add(trunk);

  for(let i=0;i<3;i++){
   const radius=(2.4-i*.55)*scale;
   const height=2.8*scale;
   const coneGeo=new THREE.ConeGeometry(radius,height,7);
   const cone=new THREE.Mesh(coneGeo,mat);
   cone.position.y=(3+i*1.5)*scale;
   cone.rotation.y=random()*Math.PI;
   cone.castShadow=false;
   cone.receiveShadow=true;
   tree.add(cone);
  }
  return tree;
 }

 function createOakTree(scale){
  const tree=new THREE.Group();
  const mat=leafMaterials[Math.floor(random()*leafMaterials.length)];

  const trunkGeo=new THREE.CylinderGeometry(.4*scale,.65*scale,3.2*scale,6);
  const trunk=new THREE.Mesh(trunkGeo,trunkMat);
  trunk.position.y=1.6*scale;
  trunk.castShadow=false;
  trunk.receiveShadow=true;
  tree.add(trunk);

  const crownPositions=[
   {x:0,y:4.2,z:0,r:2.2},
   {x:1.1,y:3.6,z:.6,r:1.5},
   {x:-1,y:3.8,z:-.7,r:1.6}
  ];
  crownPositions.forEach(p=>{
   const crownGeo=new THREE.IcosahedronGeometry(p.r*scale,1);
   const crown=new THREE.Mesh(crownGeo,mat);
   crown.position.set(p.x*scale,p.y*scale,p.z*scale);
   crown.rotation.set(random(),random(),random());
   crown.castShadow=false;
   crown.receiveShadow=true;
   tree.add(crown);
  });
  return tree;
 }

 function createRock(scale){
  const rockGeo=new THREE.DodecahedronGeometry(scale,0);
  const pos=rockGeo.attributes.position;
  for(let i=0;i<pos.count;i++){
   pos.setXYZ(
    i,
    pos.getX(i)*(.8+random()*.4),
    pos.getY(i)*(.6+random()*.4),
    pos.getZ(i)*(.8+random()*.4)
   );
  }
  rockGeo.computeVertexNormals();
  const rock=new THREE.Mesh(rockGeo,rockMat);
  rock.userData.impactMaterial='concrete';rock.castShadow=false;
  rock.receiveShadow=true;
  return rock;
 }

 function createBush(scale){
  const bush=new THREE.Group();
  const mat=leafMaterials[Math.floor(random()*leafMaterials.length)];
  for(let i=0;i<3;i++){
   const geo=new THREE.IcosahedronGeometry((.7+random()*.4)*scale,0);
   const part=new THREE.Mesh(geo,mat);
   part.position.set((random()-.5)*scale,.4*scale,(random()-.5)*scale);
   part.castShadow=false;
   part.receiveShadow=true;
   bush.add(part);
  }
  return bush;
 }

 function getValidPosition(minRadius){
  let x,z,dist,attempts=0;
  do{
   x=(random()-.5)*(mapSize-15);
   z=(random()-.5)*(mapSize-15);
   dist=Math.hypot(x,z);
   attempts++;
  }while(dist<minRadius&&attempts<30);
  return {x,z,y:getTerrainHeight(x,z)};
 }

 for(let i=0;i<treeCount;i++){
  const pos=getValidPosition(safeZoneRadius);
  const scale=.8+random()*.9;
  const tree=random()>.45?createPineTree(scale):createOakTree(scale);
  tree.position.set(pos.x,pos.y,pos.z);
  tree.rotation.y=random()*Math.PI*2;
  forestGroup.add(tree);
  colliders.push({type:'tree',x:pos.x,z:pos.z,radius:.6*scale});
 }

 for(let i=0;i<rockCount;i++){
  const pos=getValidPosition(safeZoneRadius*.7);
  const scale=.6+random()*1.4;
  const rock=createRock(scale);
  rock.position.set(pos.x,pos.y+scale*.3,pos.z);
  rock.rotation.set(random()*Math.PI,random()*Math.PI,0);
  forestGroup.add(rock);
  colliders.push({type:'rock',x:pos.x,z:pos.z,radius:scale*.9});
 }

 for(let i=0;i<bushCount;i++){
  const pos=getValidPosition(safeZoneRadius*.5);
  const scale=.7+random()*.8;
  const bush=createBush(scale);
  bush.position.set(pos.x,pos.y,pos.z);
  forestGroup.add(bush);
 }

 scene.add(forestGroup);
 return {forestGroup,colliders,getTerrainHeight,ground};
}

const forestEnvironment=buildForestEnvironment(scene,{
 mapSize:300,
 treeCount:180,
 rockCount:60,
 bushCount:90,
 safeZoneRadius:25,
 seed:42
});

class HouseParkourBuilder {
 constructor(scene,getGroundHeight=()=>0){
  this.scene=scene;
  this.getGroundHeight=getGroundHeight;
  this.structuresGroup=new THREE.Group();
  this.scene.add(this.structuresGroup);
  this.solidBoxes=[];
  this.initMaterials();
 }
 initMaterials(){
  this.materials={
   stoneWall:new THREE.MeshStandardMaterial({color:0x85877d,roughness:.85,flatShading:true}),
   woodWall:new THREE.MeshStandardMaterial({color:0x806346,roughness:.8,flatShading:true}),
   darkWood:new THREE.MeshStandardMaterial({color:0x453b2b,roughness:.9,flatShading:true}),
   roof:new THREE.MeshStandardMaterial({color:0x955e49,roughness:.75,flatShading:true}),
   crate:new THREE.MeshStandardMaterial({color:0x9c7c53,roughness:.8,flatShading:true}),
   windowGlow:new THREE.MeshStandardMaterial({color:0xffe49e,emissive:0xffb732,emissiveIntensity:.18})
  };
 }
 registerSolidBox(mesh,width,height,depth){
  mesh.updateMatrixWorld(true);
  const pos=new THREE.Vector3();
  mesh.getWorldPosition(pos);
  this.solidBoxes.push({
   minX:pos.x-width/2,maxX:pos.x+width/2,
   minY:pos.y-height/2,maxY:pos.y+height/2,
   minZ:pos.z-depth/2,maxZ:pos.z+depth/2
  });
 }
 buildHouseWithParkour(config={}){
  const {x=0,z=0,width=8,height=5.2,depth=7,rotationY=0}=config;
  const baseY=this.getGroundHeight(x,z);
  const houseContainer=new THREE.Group();
  houseContainer.position.set(x,baseY,z);
  houseContainer.rotation.y=rotationY;
  this.structuresGroup.add(houseContainer);

  const wallMesh=new THREE.Mesh(new THREE.BoxGeometry(width,height,depth),this.materials.stoneWall);
  wallMesh.userData.impactMaterial='concrete';wallMesh.position.y=height/2;
  wallMesh.castShadow=true; wallMesh.receiveShadow=true;
  houseContainer.add(wallMesh);

  const pillarGeo=new THREE.BoxGeometry(.45,height+.1,.45);
  [[-width/2,-depth/2],[width/2,-depth/2],[-width/2,depth/2],[width/2,depth/2]].forEach(([cx,cz])=>{
   const pillar=new THREE.Mesh(pillarGeo,this.materials.darkWood);
   pillar.position.set(cx,height/2,cz); pillar.castShadow=true; houseContainer.add(pillar);
  });

  const door=new THREE.Mesh(new THREE.BoxGeometry(1.4,2.4,.18),this.materials.darkWood);
  door.userData.impactMaterial='wood';door.position.set(0,1.2,depth/2+.05); houseContainer.add(door);

  const winGeo=new THREE.BoxGeometry(1.1,1.1,.15);
  [-width*.28,width*.28].forEach(wx=>{
   const win=new THREE.Mesh(winGeo,this.materials.windowGlow);
   win.position.set(wx,height*.58,depth/2+.04); houseContainer.add(win);
  });

  const roofHeight=2.4;
  const roofGeo=new THREE.ConeGeometry(Math.max(width,depth)*.78,roofHeight,4);
  roofGeo.rotateY(Math.PI/4);
  const roofMesh=new THREE.Mesh(roofGeo,this.materials.roof);
  roofMesh.scale.set(width/Math.max(width,depth),1,depth/Math.max(width,depth));
  roofMesh.position.y=height+roofHeight/2-.1;
  roofMesh.castShadow=true; roofMesh.receiveShadow=true; houseContainer.add(roofMesh);

  const supports=[
   {px:width/2+1.1,py:.6,pz:depth*.25,w:1.5,h:1.2,d:1.5,mat:this.materials.crate},
   {px:width/2+1,py:1.25,pz:-depth*.15,w:1.5,h:2.5,d:1.5,mat:this.materials.crate},
   {px:width/2+.85,py:3.65,pz:-depth*.35,w:1.7,h:.35,d:2,mat:this.materials.woodWall},
   {px:width*.25,py:height-.15,pz:-depth/2-.75,w:2.2,h:.35,d:1.5,mat:this.materials.darkWood}
  ];

  houseContainer.updateMatrixWorld(true);
  const isRotated90=Math.abs(Math.sin(rotationY))>.7;
  const worldW=isRotated90?depth:width;
  const worldD=isRotated90?width:depth;
  this.registerSolidBox(wallMesh,worldW,height,worldD);

  const roofTopCollider=new THREE.Object3D();
  roofTopCollider.position.set(0,height+.45,0);
  houseContainer.add(roofTopCollider);
  this.registerSolidBox(roofTopCollider,worldW*.85,.9,worldD*.85);

  supports.forEach(s=>{
   const sup=new THREE.Mesh(new THREE.BoxGeometry(s.w,s.h,s.d),s.mat);
   sup.userData.impactMaterial=s.mat===this.materials.crate||s.mat===this.materials.woodWall||s.mat===this.materials.darkWood?'wood':'concrete';sup.position.set(s.px,s.py,s.pz);
   sup.castShadow=true; sup.receiveShadow=true; houseContainer.add(sup);
   if(s.py>2.5){
    const bracket=new THREE.Mesh(new THREE.BoxGeometry(s.w*.7,.2,.2),this.materials.darkWood);
    bracket.position.set(s.px-.15,s.py-.35,s.pz);
    bracket.rotation.z=.55; houseContainer.add(bracket);
   }
   this.registerSolidBox(sup,isRotated90?s.d:s.w,s.h,isRotated90?s.w:s.d);
  });

  return houseContainer;
 }
 convertExistingBlocksToHouses(blockMeshes=[]){
  blockMeshes.forEach(oldMesh=>{
   if(!oldMesh||!oldMesh.geometry)return;
   oldMesh.geometry.computeBoundingBox();
   const box=oldMesh.geometry.boundingBox;
   const size=new THREE.Vector3(); box.getSize(size);
   const width=Math.max(5,size.x*oldMesh.scale.x);
   const height=Math.max(4.5,size.y*oldMesh.scale.y);
   const depth=Math.max(5,size.z*oldMesh.scale.z);
   this.buildHouseWithParkour({
    x:oldMesh.position.x,z:oldMesh.position.z,width,height,depth,rotationY:oldMesh.rotation.y
   });
   if(oldMesh.parent)oldMesh.parent.remove(oldMesh);
  });
 }
 resolvePlayerCollision(controller,playerRadius=.45,playerHeight=1.6){
  let highestPlatformY=-Infinity;
  const p=controller.mesh.position;
  for(const b of this.solidBoxes){
   const withinX=p.x+playerRadius>b.minX&&p.x-playerRadius<b.maxX;
   const withinZ=p.z+playerRadius>b.minZ&&p.z-playerRadius<b.maxZ;
   if(!withinX||!withinZ)continue;

   const footY=p.y;
   if(footY>=b.maxY-.35&&controller.velocity.y<=0){
    if(b.maxY>highestPlatformY)highestPlatformY=b.maxY;
    continue;
   }

   const stepUp=b.maxY-footY;
   if(controller.isGrounded&&controller.horizontalSpeed>.05&&stepUp>0&&stepUp<=controller.stepHeight){
    p.y=b.maxY;
    controller.velocity.y=0;
    controller.isGrounded=true;
    controller.stepBlend=Math.max(controller.stepBlend,THREE.MathUtils.clamp(stepUp/controller.stepHeight,0,1));
    if(b.maxY>highestPlatformY)highestPlatformY=b.maxY;
    continue;
   }

   const headY=p.y+playerHeight;
   if(headY>b.minY+.1&&footY<b.maxY-.35){
    const overlapLeft=(p.x+playerRadius)-b.minX;
    const overlapRight=b.maxX-(p.x-playerRadius);
    const overlapFront=(p.z+playerRadius)-b.minZ;
    const overlapBack=b.maxZ-(p.z-playerRadius);
    const minOverlap=Math.min(overlapLeft,overlapRight,overlapFront,overlapBack);
    if(minOverlap===overlapLeft)p.x=b.minX-playerRadius;
    else if(minOverlap===overlapRight)p.x=b.maxX+playerRadius;
    else if(minOverlap===overlapFront)p.z=b.minZ-playerRadius;
    else if(minOverlap===overlapBack)p.z=b.maxZ+playerRadius;
   }
  }
  if(highestPlatformY>-Infinity&&p.y<=highestPlatformY+.05){
   if(!controller.isGrounded||controller.velocity.y<-.5)controller.recordLanding?.(controller.velocity.y);
   p.y=highestPlatformY;
   controller.velocity.y=0;
   controller.isGrounded=true;
   return true;
  }
  return false;
 }
}

function box(x,y,z,sx,sy,sz,color=0x7f8a86){
 const m=new THREE.Mesh(new THREE.BoxGeometry(sx,sy,sz),new THREE.MeshStandardMaterial({color,roughness:.9}));
 m.position.set(x,y+sy/2,z); m.castShadow=true; m.receiveShadow=true; scene.add(m); return m;
}
const legacyBlocks=[
 box(0,0,14,12,5,8,0x59646b),
 box(-16,0,-4,9,7,10,0x6b5d55),
 box(17,0,-8,11,4,9,0x565f5b),
 box(0,0,-22,20,3,4,0x4d5558)
];
for(let i=-24;i<=24;i+=8) box(i,0,4,2,.35,8,0x484d50);

const houseParkour=new HouseParkourBuilder(scene,forestEnvironment.getTerrainHeight);
houseParkour.convertExistingBlocksToHouses(legacyBlocks);
// Walkable practice stairs near the central district; steps use real platform colliders.
// Each riser is a short standalone solid so existing step-up physics can traverse it.
function createWalkableStairs(x,z,count=6){
 const width=2.5,rise=.19,run=.55;
 const material=new THREE.MeshStandardMaterial({color:0x808a86,roughness:.92});
 const edgeMaterial=new THREE.MeshStandardMaterial({color:0xa5aba0,roughness:.78});
 const base=forestEnvironment.getTerrainHeight(x,z);
 for(let i=0;i<count;i++){
  const height=(i+1)*rise;
  const step=new THREE.Mesh(new THREE.BoxGeometry(width,height,run),material);
  step.name='WALKABLE_STAIR_'+i;
  step.position.set(x,base+height/2,z+(i-count/2)*run);
  step.castShadow=true;step.receiveShadow=true;step.userData.impactMaterial='concrete';
  scene.add(step);
  houseParkour.registerSolidBox(step,width,height,run);
  const stripe=new THREE.Mesh(new THREE.BoxGeometry(width,.016,.055),edgeMaterial);
  stripe.position.set(x,base+height+.012,step.position.z+run*.38);
  stripe.userData.ignoreCombat=true;stripe.castShadow=false;
  scene.add(stripe);
 }
}
createWalkableStairs(10,26);

/* Migrated urban expansion: standalone 3D houses and tower cover, registered in the
   same collision/cover/loot system as original parkour buildings. */
const urbanLayout=[
 [-58,-57,10,9,5.5],[-42,-57,12,10,8],[-25,-57,10,10,5.5],
 [27,-57,12,10,10],[49,-57,12,10,16],[68,-57,11,11,6],
 [-61,-31,11,11,6],[-40,-30,13,11,15],[40,-30,13,12,20],[63,-30,12,10,6],
 [-65,33,12,10,5.5],[-43,35,13,11,17],[-24,38,10,11,6],
 [28,37,14,12,19],[51,36,13,10,7]
];
const urbanTowers=[];
const urbanWindowGeometry=new THREE.PlaneGeometry(1.35,1.35);
const urbanWindowMaterial=new THREE.MeshStandardMaterial({color:0x456779,emissive:0x13222a,emissiveIntensity:.16,side:THREE.DoubleSide,roughness:.85});
const urbanWallMaterials=[
 new THREE.MeshStandardMaterial({color:0x627b85,roughness:.86}),
 new THREE.MeshStandardMaterial({color:0xb49c83,roughness:.86})
];
const urbanTrimMaterial=new THREE.MeshStandardMaterial({color:0x48555b,roughness:.88});
const urbanWindows=[];
for(const [x,z,w,d,h] of urbanLayout){
 const floor=forestEnvironment.getTerrainHeight(x,z);
 const tall=h>=10;
 const g=new THREE.Group();g.position.set(x,floor,z);scene.add(g);
 const wall=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),urbanWallMaterials[tall?0:1]);
 wall.position.y=h/2;wall.castShadow=true;wall.receiveShadow=true;wall.userData.impactMaterial='concrete';g.add(wall);
 // Window instances share ONE geometry/material and ONE draw call instead of hundreds.
 for(const side of [-1,1])for(let level=1;level<=Math.floor((h-1)/2.8);level++){
  for(let dx=-w/2+1.7;dx<w/2-1;dx+=2.7){
   urbanWindows.push({x:x+dx,y:floor+level*2.8,z:z+side*(d/2+.015),flip:side<0});
  }
 }
 const trim=new THREE.Mesh(new THREE.BoxGeometry(w+.25,.3,d+.25),urbanTrimMaterial);
 trim.position.y=h;g.add(trim);
 g.updateMatrixWorld(true);
 houseParkour.registerSolidBox(wall,w,h,d);
 if(tall)urbanTowers.push({x,z,height:h});
}
if(urbanWindows.length){
 const windows=new THREE.InstancedMesh(urbanWindowGeometry,urbanWindowMaterial,urbanWindows.length);
 const dummy=new THREE.Object3D();
 urbanWindows.forEach((w,i)=>{
  dummy.position.set(w.x,w.y,w.z);dummy.rotation.set(0,w.flip?Math.PI:0,0);dummy.updateMatrix();
  windows.setMatrixAt(i,dummy.matrix);
 });
 windows.instanceMatrix.needsUpdate=true;windows.frustumCulled=false;
 windows.castShadow=false;windows.receiveShadow=false;
 scene.add(windows);
}

// Waist-high training cover in the existing combat area.
for(const [x,z] of [[-4,-3],[4,-5]]){
 const barrier=box(x,forestEnvironment.getTerrainHeight(x,z),z,4,1.3,.75,0x826e56);
 barrier.userData.impactMaterial='wood';houseParkour.registerSolidBox(barrier,4,1.3,.75);
}

const player=new THREE.Group(); scene.add(player);
player.position.set(0,0,0);

function makeCapsuleGeometry(radius,length,segments=8){
 const g=new THREE.Group();
 const matProxy=null;
 const cylinder=new THREE.CylinderGeometry(radius,radius,length,segments);
 const top=new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75)));
 const bottom=new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75)));
 return {cylinder,top,bottom,length,radius};
}

function makeCapsuleMesh(radius,length,material,segments=8){
 const group=new THREE.Group();
 const body=new THREE.Mesh(new THREE.CylinderGeometry(radius,radius,length,segments),material);
 body.castShadow=true;
 const top=new THREE.Mesh(new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75))),material);
 top.position.y=length/2;
 top.castShadow=true;
 const bottom=new THREE.Mesh(new THREE.SphereGeometry(radius,segments,Math.max(6,Math.floor(segments*.75))),material);
 bottom.position.y=-length/2;
 bottom.castShadow=true;
 group.add(body,top,bottom);
 return group;
}

class SimpleAvatar {
 constructor(options={}){
  this.group=new THREE.Group();
  const bodyColor=options.bodyColor||0x3b82f6;
  const skinColor=options.skinColor||0xf1f5f9;
  const visorColor=options.visorColor||0x0f172a;

  const bodyMat=new THREE.MeshStandardMaterial({color:bodyColor,roughness:.4});
  const skinMat=new THREE.MeshStandardMaterial({color:skinColor,roughness:.3});
  const visorMat=new THREE.MeshStandardMaterial({color:visorColor,roughness:.1,metalness:.8});

  this.leftLeg=new THREE.Group();
  this.leftLeg.position.set(-.18,.65,0);
  const leftLegMesh=makeCapsuleMesh(.11,.45,skinMat,8);
  leftLegMesh.position.y=-.32; this.leftLeg.add(leftLegMesh);

  this.rightLeg=new THREE.Group();
  this.rightLeg.position.set(.18,.65,0);
  const rightLegMesh=makeCapsuleMesh(.11,.45,skinMat,8);
  rightLegMesh.position.y=-.32; this.rightLeg.add(rightLegMesh);

  this.torso=makeCapsuleMesh(.32,.5,bodyMat,12);
  this.torso.position.y=1.05;

  this.head=new THREE.Group();
  this.head.position.y=1.75;
  const headMesh=new THREE.Mesh(new THREE.SphereGeometry(.28,16,16),skinMat);
  headMesh.castShadow=true; this.head.add(headMesh);

  const visorMesh=new THREE.Mesh(new THREE.BoxGeometry(.36,.14,.15),visorMat);
  visorMesh.position.set(0,.02,.22); this.head.add(visorMesh);

  this.leftArm=new THREE.Group();
  this.leftArm.position.set(-.44,1.32,0);
  const leftArmMesh=makeCapsuleMesh(.09,.45,skinMat,8);
  leftArmMesh.position.y=-.25; this.leftArm.add(leftArmMesh);

  this.rightArm=new THREE.Group();
  this.rightArm.position.set(.44,1.32,0);
  const rightArmMesh=makeCapsuleMesh(.09,.45,skinMat,8);
  rightArmMesh.position.y=-.25; this.rightArm.add(rightArmMesh);

  this.group.add(this.leftLeg,this.rightLeg,this.torso,this.head,this.leftArm,this.rightArm);
  this.walkTime=0;
 }
 animate(dt,isMoving,isSprinting=false){
  const safeLerp=Math.min(1,10*dt);
  if(isMoving){
   const speed=isSprinting?14:9;
   const swingAngle=isSprinting?.85:.55;
   this.walkTime+=dt*speed;
   const s=Math.sin(this.walkTime)*swingAngle;
   this.leftLeg.rotation.x=s;
   this.rightLeg.rotation.x=-s;
   this.leftArm.rotation.x=-s;
   this.rightArm.rotation.x=s;
   this.torso.position.y=1.05+Math.abs(Math.cos(this.walkTime))*.04;
  }else{
   this.leftLeg.rotation.x=THREE.MathUtils.lerp(this.leftLeg.rotation.x,0,safeLerp);
   this.rightLeg.rotation.x=THREE.MathUtils.lerp(this.rightLeg.rotation.x,0,safeLerp);
   this.leftArm.rotation.x=THREE.MathUtils.lerp(this.leftArm.rotation.x,0,safeLerp);
   this.rightArm.rotation.x=THREE.MathUtils.lerp(this.rightArm.rotation.x,0,safeLerp);
   this.torso.position.y=THREE.MathUtils.lerp(this.torso.position.y,1.05,safeLerp);
  }
 }
}

class ForestAudioSystem {
 constructor(){
  this.ctx=null;
  this.masterGain=null;
  this.windGain=null;
  this.enabled=true;
  this.isAmbiencePlaying=false;
  this.birdTimer=null;
  this.lastFootstepAt=0;
  this.lastImpactAt=-Infinity;
 }
 init(){
  if(!this.ctx){
   const AudioContext=window.AudioContext||window.webkitAudioContext;
   this.ctx=new AudioContext();
   this.masterGain=this.ctx.createGain();
   this.masterGain.gain.value=this.enabled?.8:0;
   this.masterGain.connect(this.ctx.destination);
  }
  if(this.ctx.state==='suspended')this.ctx.resume();
  if(!this.isAmbiencePlaying)this.startForestAmbience();
 }
 playPlayerHit(){
  if(!this.ctx||!this.masterGain||!this.enabled)return;
  const t=this.ctx.currentTime,osc=this.ctx.createOscillator(),gain=this.ctx.createGain();
  osc.type='triangle';osc.frequency.setValueAtTime(155,t);osc.frequency.exponentialRampToValueAtTime(48,t+.13);
  gain.gain.setValueAtTime(.0001,t);gain.gain.exponentialRampToValueAtTime(.65,t+.008);gain.gain.exponentialRampToValueAtTime(.0001,t+.18);
  osc.connect(gain);gain.connect(this.masterGain);osc.start(t);osc.stop(t+.19);osc.onended=()=>{osc.disconnect();gain.disconnect();};
 }
 setEnabled(state){
  this.enabled=state;
  if(this.masterGain&&this.ctx){
   this.masterGain.gain.setTargetAtTime(state?.8:0,this.ctx.currentTime,.05);
  }
 }
 startForestAmbience(){
  if(!this.ctx||this.isAmbiencePlaying)return;
  this.isAmbiencePlaying=true;

  const bufferSize=this.ctx.sampleRate*4;
  const buffer=this.ctx.createBuffer(1,bufferSize,this.ctx.sampleRate);
  const data=buffer.getChannelData(0);
  let lastOut=0;
  for(let i=0;i<bufferSize;i++){
   const white=Math.random()*2-1;
   data[i]=(lastOut+.02*white)/1.02;
   lastOut=data[i];
   data[i]*=2.5;
  }

  const windSource=this.ctx.createBufferSource();
  windSource.buffer=buffer;
  windSource.loop=true;

  const windFilter=this.ctx.createBiquadFilter();
  windFilter.type='bandpass';
  windFilter.frequency.value=320;
  windFilter.Q.value=1.2;

  const lfo=this.ctx.createOscillator();
  lfo.frequency.value=.12;
  const lfoGain=this.ctx.createGain();
  lfoGain.gain.value=140;
  lfo.connect(lfoGain);
  lfoGain.connect(windFilter.frequency);

  this.windGain=this.ctx.createGain();
  this.windGain.gain.value=.12;

  windSource.connect(windFilter);
  windFilter.connect(this.windGain);
  this.windGain.connect(this.masterGain);

  windSource.start();
  lfo.start();
  this._scheduleBird();
 }
 _scheduleBird(){
  if(!this.ctx||!this.isAmbiencePlaying)return;
  const delay=2200+Math.random()*6500;
  clearTimeout(this.birdTimer);
  this.birdTimer=setTimeout(()=>{
   this.playBird();
   this._scheduleBird();
  },delay);
 }
 playBird(){
  if(!this.ctx||!this.enabled)return;
  const now=this.ctx.currentTime;
  const osc=this.ctx.createOscillator();
  const gain=this.ctx.createGain();
  const pan=this.ctx.createStereoPanner?this.ctx.createStereoPanner():null;

  osc.type='sine';
  const base=1500+Math.random()*900;
  osc.frequency.setValueAtTime(base,now);
  osc.frequency.linearRampToValueAtTime(base*1.25,now+.08);
  osc.frequency.linearRampToValueAtTime(base*.9,now+.18);
  osc.frequency.linearRampToValueAtTime(base*1.18,now+.28);

  gain.gain.setValueAtTime(.0001,now);
  gain.gain.exponentialRampToValueAtTime(.045,now+.03);
  gain.gain.exponentialRampToValueAtTime(.0001,now+.35);

  osc.connect(gain);
  if(pan){
   pan.pan.value=(Math.random()*2-1)*.8;
   gain.connect(pan);
   pan.connect(this.masterGain);
  }else{
   gain.connect(this.masterGain);
  }

  osc.start(now);
  osc.stop(now+.38);
 }
 _noiseBuffer(duration=.1){
  const len=Math.max(1,Math.floor(this.ctx.sampleRate*duration));
  const buffer=this.ctx.createBuffer(1,len,this.ctx.sampleRate);
  const data=buffer.getChannelData(0);
  for(let i=0;i<len;i++)data[i]=Math.random()*2-1;
  return buffer;
 }
 _shotNoise(when,duration,volume,low,high){
  const src=this.ctx.createBufferSource(),filter=this.ctx.createBiquadFilter(),gain=this.ctx.createGain();
  src.buffer=this._noiseBuffer(duration);
  filter.type='bandpass';filter.frequency.value=(low+high)/2;filter.Q.value=.65;
  gain.gain.setValueAtTime(Math.max(.0001,volume),when);
  gain.gain.exponentialRampToValueAtTime(.0001,when+duration);
  src.connect(filter);filter.connect(gain);gain.connect(this.masterGain);
  src.start(when);src.stop(when+duration+.02);
 }
 _shotTone(when,freq,duration,volume,type='sine',endFreq=null){
  const osc=this.ctx.createOscillator(),gain=this.ctx.createGain();
  osc.type=type;osc.frequency.setValueAtTime(Math.max(20,freq),when);
  if(endFreq)osc.frequency.exponentialRampToValueAtTime(Math.max(20,endFreq),when+duration);
  gain.gain.setValueAtTime(Math.max(.0001,volume),when);
  gain.gain.exponentialRampToValueAtTime(.0001,when+duration);
  osc.connect(gain);gain.connect(this.masterGain);osc.start(when);osc.stop(when+duration+.02);
 }
 _shotTail(when,duration,volume){
  const src=this.ctx.createBufferSource(),filter=this.ctx.createBiquadFilter(),gain=this.ctx.createGain(),delay=this.ctx.createDelay(),feedback=this.ctx.createGain();
  src.buffer=this._noiseBuffer(duration);
  filter.type='lowpass';filter.frequency.value=2500;
  gain.gain.setValueAtTime(Math.max(.0001,volume),when);
  gain.gain.exponentialRampToValueAtTime(.0001,when+duration);
  delay.delayTime.value=.10;feedback.gain.value=.16;
  src.connect(filter);filter.connect(gain);gain.connect(this.masterGain);
  gain.connect(delay);delay.connect(feedback);feedback.connect(delay);delay.connect(this.masterGain);
  src.start(when);src.stop(when+duration+.05);
 }
 playShoot(kind='pistol',volumeScale=1){
  if(!this.ctx||!this.enabled)return;
  const specs={
   pistol:{body:150,sub:72,mech:1150,tail:.24,transient:.31,bodyVol:.25,lfe:.08,crack:.12},
   smg:{body:175,sub:88,mech:1450,tail:.20,transient:.26,bodyVol:.21,lfe:.06,crack:.10},
   rifle:{body:115,sub:58,mech:980,tail:.34,transient:.35,bodyVol:.29,lfe:.11,crack:.16},
   shotgun:{body:76,sub:42,mech:720,tail:.48,transient:.40,bodyVol:.34,lfe:.14,crack:.09}
  };
  const spec=specs[kind]||specs.pistol,now=this.ctx.currentTime+.005;
  const variation=1+(Math.random()-.5)*.08;
  const loudness=THREE.MathUtils.clamp(volumeScale,.15,1);

  // Layer 1: sharp muzzle transient.
  this._shotNoise(now,.028,spec.transient*variation*loudness,950,6500);
  // Layer 2: mid/low body that gives the weapon its weight.
  this._shotNoise(now+.005,.115,spec.bodyVol*variation*loudness,120,1750);
  this._shotTone(now,spec.body*variation,.12,spec.bodyVol*.42*loudness,'sawtooth',spec.body*.56);
  // Layer 3: short LFE thump.
  this._shotTone(now,spec.sub,.16,spec.lfe*loudness,'sine',spec.sub*.62);
  // Layer 4: slide/bolt/mechanism.
  this._shotTone(now+.026,spec.mech*variation,.026,.030*loudness,'square',spec.mech*.72);
  this._shotTone(now+.055,spec.mech*.62*variation,.038,.020*loudness,'triangle',spec.mech*.43);
  // Layer 5: projectile crack + outdoor reflection tail.
  this._shotNoise(now+.010,.018,spec.crack*loudness,2300,7600);
  this._shotTail(now+.035,spec.tail,.055*loudness);
 }
 playWeaponMechanic(kind='pistol',action='equip'){
  if(!this.ctx||!this.enabled||!this.masterGain)return;
  const profiles={
   pistol:{pitch:1320,weight:.75},
   smg:{pitch:1520,weight:.75},
   rifle:{pitch:1030,weight:1},
   shotgun:{pitch:650,weight:1.25},
   sniper:{pitch:780,weight:1.18}
  };
  const p=profiles[kind]||profiles.pistol;
  const event={
   equip:{duration:.075,volume:.046,factor:.9},
   holster:{duration:.08,volume:.033,factor:.72},
   magOut:{duration:.11,volume:.065,factor:.70},
   magIn:{duration:.09,volume:.09,factor:1.2},
   bolt:{duration:.13,volume:.105,factor:1.45},
   shell:{duration:.075,volume:.074,factor:1.05},
   ready:{duration:.06,volume:.045,factor:1.1},
   empty:{duration:.045,volume:.058,factor:1.6}
  }[action];
  if(!event)return;
  const t=this.ctx.currentTime+.003;
  const pitch=p.pitch*event.factor*(.95+Math.random()*.1);
  this._shotTone(t,pitch,event.duration,event.volume*p.weight,'triangle',pitch*.58);
  this._shotNoise(t+.002,event.duration*.62,event.volume*.7*p.weight,pitch*.5,pitch*2.6);
  if(action==='bolt'||action==='magIn'||action==='shell')
   this._shotTone(t+.035,pitch*.54,.043,event.volume*.45*p.weight,'square',pitch*.32);
 }
 playMaterialImpact(kind,position,listenerCamera){
  if(!this.ctx||!this.enabled||!this.masterGain||!position||!listenerCamera)return;
  const now=this.ctx.currentTime;
  // Prevent pellet bursts/automatic fire from creating too many sound nodes.
  if(now-this.lastImpactAt<.045)return;
  const distance=position.distanceTo(listenerCamera.position);
  if(distance>85)return;
  this.lastImpactAt=now;
  const profiles={
   concrete:{low:180,high:2200,volume:.21,duration:.12,tone:170},
   wood:{low:120,high:1100,volume:.23,duration:.10,tone:120},
   metal:{low:900,high:6500,volume:.24,duration:.15,tone:1850},
   dirt:{low:85,high:750,volume:.16,duration:.14,tone:95},
   ice:{low:800,high:4600,volume:.20,duration:.18,tone:910}
  };
  const p=profiles[kind]||profiles.concrete;
  const attenuation=1/(1+distance*.09+distance*distance*.004);
  const local=position.clone().sub(listenerCamera.position);
  const cameraRight=new THREE.Vector3(1,0,0).applyQuaternion(listenerCamera.quaternion);
  const panValue=THREE.MathUtils.clamp(local.normalize().dot(cameraRight),-1,1);
  const gain=this.ctx.createGain(),filter=this.ctx.createBiquadFilter();
  const panner=this.ctx.createStereoPanner?.();
  gain.gain.value=Math.max(.001,p.volume*attenuation);
  filter.type='bandpass';
  filter.frequency.value=Math.sqrt(p.low*p.high)*THREE.MathUtils.clamp(1-distance/145,.35,1);
  filter.Q.value=.6;
  const noise=this.ctx.createBufferSource();
  noise.buffer=this._noiseBuffer(p.duration);
  const envelope=this.ctx.createGain();
  envelope.gain.setValueAtTime(.0001,now);
  envelope.gain.exponentialRampToValueAtTime(.85,now+.004);
  envelope.gain.exponentialRampToValueAtTime(.0001,now+p.duration);
  noise.connect(filter);filter.connect(envelope);envelope.connect(gain);
  if(panner){panner.pan.value=panValue;gain.connect(panner);panner.connect(this.masterGain);}
  else gain.connect(this.masterGain);
  noise.start(now);noise.stop(now+p.duration+.01);
  // Short pitched ring for ricochet, brittle ice, and wood/stone knocks.
  const oscillator=this.ctx.createOscillator(),ringGain=this.ctx.createGain();
  oscillator.type=kind==='metal'?'sine':'triangle';
  const pitch=p.tone*(.88+Math.random()*.24);
  oscillator.frequency.setValueAtTime(pitch,now);
  oscillator.frequency.exponentialRampToValueAtTime(Math.max(35,pitch*(kind==='metal'?.48:.72)),now+p.duration);
  ringGain.gain.setValueAtTime(.0001,now);
  ringGain.gain.exponentialRampToValueAtTime(kind==='metal'?.22:.08,now+.004);
  ringGain.gain.exponentialRampToValueAtTime(.0001,now+p.duration);
  oscillator.connect(ringGain);ringGain.connect(gain);
  oscillator.start(now);oscillator.stop(now+p.duration+.01);
  noise.onended=()=>{
   noise.disconnect();filter.disconnect();envelope.disconnect();
   oscillator.disconnect();ringGain.disconnect();gain.disconnect();
   if(panner)panner.disconnect();
  };
 }
 playTactical(kind,distance=0){
  if(!this.ctx||!this.enabled)return;const now=this.ctx.currentTime,volume=Math.max(.025,1/(1+distance*.1));
  if(kind==='explosion'){this._shotNoise(now,.25,.5*volume,80,2200);this._shotTone(now,65,.5,.3*volume,'sine',22);this._shotTail(now+.04,.65,.13*volume);}
  else{this._shotNoise(now,.18,.18*volume,1800,6500);this._shotTone(now,kind==='icebreak'?410:950,.22,.1*volume,'triangle',kind==='icebreak'?140:250);}
 }
  playHit(){
  if(!this.ctx||!this.enabled)return;
  const now=this.ctx.currentTime;
  const osc=this.ctx.createOscillator();
  const gain=this.ctx.createGain();
  osc.type='sine';
  osc.frequency.setValueAtTime(820,now);
  osc.frequency.exponentialRampToValueAtTime(380,now+.09);
  gain.gain.setValueAtTime(.18,now);
  gain.gain.exponentialRampToValueAtTime(.001,now+.1);
  osc.connect(gain); gain.connect(this.masterGain);
  osc.start(now); osc.stop(now+.1);
 }
 playFootstep(){
  if(!this.ctx||!this.enabled)return;
  const nowMs=performance.now();
  if(nowMs-this.lastFootstepAt<190)return;
  this.lastFootstepAt=nowMs;
  const now=this.ctx.currentTime;
  const osc=this.ctx.createOscillator();
  const gain=this.ctx.createGain();
  osc.type='triangle';
  osc.frequency.setValueAtTime(95,now);
  osc.frequency.exponentialRampToValueAtTime(38,now+.055);
  gain.gain.setValueAtTime(.08,now);
  gain.gain.exponentialRampToValueAtTime(.001,now+.055);
  osc.connect(gain); gain.connect(this.masterGain);
  osc.start(now); osc.stop(now+.06);
 }
}

const forestAudio=new ForestAudioSystem();
canvas.addEventListener('pointerdown',()=>forestAudio.init(),{once:true});

class HumanCharacter {
 constructor(scene,camera){
  this.scene=scene;
  this.camera=camera;
  this.model=null;
  this.mixer=null;
  this.skeleton=null;
  this.actions={};
  this.activeAction=null;
  this.previousAction=null;
  this.state='idle';
  this.velocity=new THREE.Vector3();
  this.direction=new THREE.Vector3();
  this.neckBone=null;
  this.spineBone=null;
  this.hipsBone=null;
  this.leftUpLegBone=null;
  this.rightUpLegBone=null;
  this.leftLegBone=null;
  this.rightLegBone=null;
  this.rightHandBone=null;
  this.leftHandBone=null;
  this.rightArmBone=null;
  this.leftArmBone=null;
  this.rightForeArmBone=null;
  this.leftForeArmBone=null;
  this.jumpPhase='grounded';
  this.jumpBlend=0;
  this.landBlend=0;
  this.wasGrounded=true;
  this.airborneBaseAction=null;
 }
 load(url){
  // Current runtime is classic Three.js r128. Use GLTFLoader only if available globally.
  if(!THREE.GLTFLoader){
   return Promise.reject(new Error('GLTFLoader indisponivel nesta build'));
  }
  const loader=new THREE.GLTFLoader();
  return new Promise((resolve,reject)=>{
   loader.load(url,gltf=>{
    this.model=gltf.scene;
    this.scene.add(this.model);
    this.model.traverse(object=>{
     if(object.isMesh){
      object.castShadow=true;
      object.receiveShadow=true;
     }
     if(object.isBone){
      const name=object.name.toLowerCase();
      if(name.includes('neck'))this.neckBone=object;
      if(name.includes('spine1')||name==='spine')this.spineBone=object;
      if(name.includes('hips'))this.hipsBone=object;
      if(name.includes('leftupleg')||name.includes('left_up_leg'))this.leftUpLegBone=object;
      if(name.includes('rightupleg')||name.includes('right_up_leg'))this.rightUpLegBone=object;
      if((name.includes('leftleg')||name.includes('left_leg'))&&!name.includes('upleg'))this.leftLegBone=object;
      if((name.includes('rightleg')||name.includes('right_leg'))&&!name.includes('upleg'))this.rightLegBone=object;
      if(name.includes('righthand')||name.includes('right_hand'))this.rightHandBone=object;
      if(name.includes('lefthand')||name.includes('left_hand'))this.leftHandBone=object;
      if((name.includes('rightarm')||name.includes('right_arm'))&&!name.includes('fore'))this.rightArmBone=object;
      if((name.includes('leftarm')||name.includes('left_arm'))&&!name.includes('fore'))this.leftArmBone=object;
      if(name.includes('rightforearm')||name.includes('right_forearm'))this.rightForeArmBone=object;
      if(name.includes('leftforearm')||name.includes('left_forearm'))this.leftForeArmBone=object;
     }
    });
    this.jumpRestPose={};
    [
     ['hips',this.hipsBone],
     ['spine',this.spineBone],
     ['leftUpLeg',this.leftUpLegBone],
     ['rightUpLeg',this.rightUpLegBone],
     ['leftLeg',this.leftLegBone],
     ['rightLeg',this.rightLegBone]
    ].forEach(([key,bone])=>{
     if(bone)this.jumpRestPose[key]=bone.rotation.clone();
    });

    this.mixer=new THREE.AnimationMixer(this.model);
    console.table((gltf.animations||[]).map((clip,index)=>({
     indice:index,
     nomeOriginal:clip.name,
     duracaoSegundos:Number(clip.duration.toFixed(2))
    })));
    (gltf.animations||[]).forEach(clip=>{
     const action=this.mixer.clipAction(clip);
     const cleanName=clip.name.toLowerCase();
     this.actions[cleanName]=action;
     if(cleanName.includes('jump')||cleanName.includes('land')||cleanName.includes('attack')||cleanName.includes('slash')){
      action.setLoop(THREE.LoopOnce);
      action.clampWhenFinished=true;
     }
    });
    const idleKey=this.findActionKey(['idle','stand']);
    if(idleKey){
     this.activeAction=this.actions[idleKey];
     this.activeAction.play();
     this.state='idle';
    }
    this.mixer.addEventListener('finished',e=>{
     const jumpKey=this.findActionKey(['jump']);
     if(jumpKey&&e.action===this.actions[jumpKey])this.fadeToAction('idle',.2);
    });
    resolve(this.model);
   },undefined,reject);
  });
 }
 findActionKey(names){
  return Object.keys(this.actions).find(k=>names.some(n=>k.includes(n)))||null;
 }
 fadeToAction(name,duration=.25){
  let key=this.actions[name.toLowerCase()]?name.toLowerCase():null;
  if(!key){
   const aliases={
    idle:['idle','stand'],
    walk:['walk','walking'],
    run:['run','sprint','running'],
    jump:['jump']
   };
   key=this.findActionKey(aliases[name.toLowerCase()]||[name.toLowerCase()]);
  }
  const nextAction=key?this.actions[key]:null;
  if(!nextAction||nextAction===this.activeAction)return;
  this.previousAction=this.activeAction;
  this.activeAction=nextAction;
  if(this.previousAction)this.previousAction.fadeOut(duration);
  this.activeAction.reset().setEffectiveTimeScale(1).setEffectiveWeight(1).fadeIn(duration).play();
  this.state=name.toLowerCase();
 }
 updateLocomotion(speed,isGrounded=true){
  if(!isGrounded){
   const jumpKey=this.findActionKey(['jump']);
   if(jumpKey){
    this.fadeToAction('jump',.12);
   }else{
    // Soldier has no jump clip. Use a stable neutral pose in the air.
    const idleKey=this.findActionKey(['idle','stand']);
    const idleAction=idleKey?this.actions[idleKey]:null;

    if(idleAction){
     if(this.activeAction!==idleAction){
      if(this.activeAction)this.activeAction.fadeOut(.08);
      this.activeAction=idleAction;
      idleAction.reset().setEffectiveWeight(1).fadeIn(.08).play();
     }
     // Freeze a neutral idle frame instead of a run frame.
     idleAction.time=Math.min(.12,idleAction.getClip().duration*.1);
     idleAction.paused=true;
    }

    this.previousAction=null;
    this.airborneBaseAction=idleAction;
    this.state='jump';
   }
   return;
  }

  // Resume the frozen neutral pose when the character lands.
  if(this.airborneBaseAction&&this.airborneBaseAction.paused){
   this.airborneBaseAction.paused=false;
   this.airborneBaseAction=null;
  }
  if(this.state==='jump'&&isGrounded)this.state='idle';
  if(speed>4.5){
   this.fadeToAction('run',.2);
   if(this.activeAction)this.activeAction.setEffectiveTimeScale(Math.max(.7,speed/6));
  }else if(speed>.2){
   this.fadeToAction('walk',.25);
   if(this.activeAction)this.activeAction.setEffectiveTimeScale(Math.max(.65,speed/2));
  }else{
   this.fadeToAction('idle',.3);
  }
 }
 lookAtTarget(targetPoint){
  if(!this.neckBone||!this.model)return;
  const localTarget=this.model.worldToLocal(targetPoint.clone());
  const angleY=Math.atan2(localTarget.x,localTarget.z);
  const clampedY=THREE.MathUtils.clamp(angleY,-.8,.8);
  this.neckBone.rotation.y=THREE.MathUtils.lerp(this.neckBone.rotation.y,clampedY,.1);
 }
 updateJumpPose(delta,verticalVelocity,isGrounded){
  if(!this.model)return;

  // Do not rotate Soldier bones here. The official Soldier rig uses its own
  // bone axes, and forcing generic leg/hip rotations can fold the mesh.
  const t=1-Math.exp(-12*delta);

  this.model.rotation.x=THREE.MathUtils.lerp(this.model.rotation.x,0,t);
  this.model.rotation.z=THREE.MathUtils.lerp(this.model.rotation.z,0,t);

  if(this.wasGrounded&&!isGrounded){
   this.jumpPhase='air';
  }

  if(!this.wasGrounded&&isGrounded){
   this.jumpPhase='landing';
   this.landBlend=1;
  }

  this.wasGrounded=isGrounded;

  if(isGrounded&&this.jumpPhase==='landing'){
   this.landBlend=Math.max(0,this.landBlend-delta*8);
   if(this.landBlend<=.01){
    this.jumpPhase='grounded';
    this.landBlend=0;
   }
  }
 }

 update(delta){
  if(this.mixer)this.mixer.update(delta);
 }
}

class RealisticCombatAnimator {
 constructor(player,avatar){
  this.player=player;
  this.avatar=avatar;
  this.weapon='none';
  this.state='idle';
  this.stateTime=0;
  this.attackType=null;
  this.comboStep=0;
  this.breathTime=0;
 }
 setWeapon(type){this.weapon=type;}
 smooth(current,target,speed,dt){return THREE.MathUtils.lerp(current,target,1-Math.exp(-speed*dt));}
 bell(t){return Math.sin(THREE.MathUtils.clamp(t,0,1)*Math.PI);}
 update(dt,movement){
  this.stateTime+=dt;
  this.breathTime+=dt;
  this.updateLowerBody(dt,movement);
  if(this.weapon==='pistol')this.updatePistolPose(dt,movement);
  else this.updateUnarmedPose(dt,movement);
  this.updateBodyInertia(dt,movement);
 }
 updateLowerBody(dt,movement){
  const {leftLeg,rightLeg,torso}=this.avatar;
  if(!movement.grounded){
   leftLeg.rotation.x=this.smooth(leftLeg.rotation.x,-.25,8,dt);
   rightLeg.rotation.x=this.smooth(rightLeg.rotation.x,.35,8,dt);
   return;
  }
  if(!movement.moving){
   leftLeg.rotation.x=this.smooth(leftLeg.rotation.x,0,10,dt);
   rightLeg.rotation.x=this.smooth(rightLeg.rotation.x,0,10,dt);
   torso.position.y=this.smooth(torso.position.y,1.05,8,dt);
   return;
  }
  const cycleSpeed=movement.sprinting?13:8;
  const stride=Math.sin(this.breathTime*cycleSpeed);
  const amplitude=movement.sprinting?.75:.48;
  leftLeg.rotation.x=this.smooth(leftLeg.rotation.x,stride*amplitude,14,dt);
  rightLeg.rotation.x=this.smooth(rightLeg.rotation.x,-stride*amplitude,14,dt);
  const bob=Math.abs(Math.cos(this.breathTime*cycleSpeed))*(movement.sprinting?.055:.028);
  torso.position.y=this.smooth(torso.position.y,1.05+bob,14,dt);
 }
 updateUnarmedPose(dt,movement){
  const {leftArm,rightArm}=this.avatar;
  if(movement.moving){
   const speed=movement.sprinting?13:8;
   const swing=Math.sin(this.breathTime*speed)*(movement.sprinting?.55:.35);
   leftArm.rotation.x=this.smooth(leftArm.rotation.x,-swing,12,dt);
   rightArm.rotation.x=this.smooth(rightArm.rotation.x,swing,12,dt);
  }else{
   leftArm.rotation.x=this.smooth(leftArm.rotation.x,.05,8,dt);
   rightArm.rotation.x=this.smooth(rightArm.rotation.x,-.05,8,dt);
  }
 }
 updateBodyInertia(dt,movement){
  const torso=this.avatar.torso;
  if(this.state==='attack')return;
  const targetLean=movement.moving?(movement.sprinting?.09:.035):0;
  torso.rotation.x=this.smooth(torso.rotation.x,targetLean,7,dt);
 }
}

class PistolController {
 constructor(scene,player,avatar,camera){
  this.scene=scene;
  this.player=player;
  this.avatar=avatar;
  this.camera=camera;

  this.isEquipped=false;
  this.isReloading=false;
  this.isAiming=true;

  this.magSize=12;
  this.ammo=this.magSize;
  this.reserveAmmo=60;

  this.fireRate=.22;
  this.fireCooldown=0;
  this.reloadTime=1.15;
  this.reloadTimer=0;
  this.reloadBlend=0;
  this.equipBlend=0;
  this.equipTimer=0;
  this.equipDuration=.34;

  this.recoil=0;
  this.recoilVelocity=0;
  // Recoil preset validated in the Soldier test app.
  this.recoilPreset=Object.freeze({
   weaponKick:1.15,
   bodyKick:.28,
   aimKickDeg:1.60,
   cameraShake:.46,
   recovery:16,
   cadenceRpm:340
  });
  this.spread=.0025;
  this.weaponSpec=window.WeaponLootSystem.DEFINITIONS.pistol;
  this.triggerHeld=false;
  this.casings=[];
  this.tracerPool=[];
  this.tracerCursor=0;
  this.tracerMaterial=new THREE.LineBasicMaterial({color:0xffe8a3,transparent:true,opacity:.8,depthWrite:false});
  this.casingGeometry={small:new THREE.CylinderGeometry(.009,.009,.039,8),shotgun:new THREE.CylinderGeometry(.019,.019,.065,8)};
  this.casingMaterial={small:new THREE.MeshStandardMaterial({color:0xc9a15c,metalness:.72,roughness:.3}),shotgun:new THREE.MeshStandardMaterial({color:0xb96d36,metalness:.72,roughness:.3})};
  this.muzzleBursts=[];
  this.impactEffects=[];
  this.reloadSoundStage=0;
  this.emptyClickCooldown=0;
  this.mechanismShot=0;
  this.shotHeat=0;
  this.burstShots=0;
  this.timeSinceShot=10;
  this.spreadKick=0;
  this.lastHandlingWeapon='pistol';

  this.pistol=this.createPistolMesh();
  this.soldierAttached=false;
  this.rightHandBone=null;
  this.leftHandBone=null;
  this.rightArmBone=null;
  this.leftArmBone=null;
  this.spineBone=null;
  this.rightForeArmBone=null;
  this.leftForeArmBone=null;
  this.shootingPoseBase=null;

  // Fallback: attach to player root until Soldier bones are available.
  this.player.add(this.pistol);
  this.holster();

  this.bindInputs();
 }

 createPistolMesh(){
  const g=new THREE.Group();
  g.name='Glock17';

  const slideMat=new THREE.MeshStandardMaterial({
   color:0x25292d,
   metalness:.72,
   roughness:.26
  });
  const frameMat=new THREE.MeshStandardMaterial({
   color:0x15181a,
   metalness:.08,
   roughness:.72
  });
  const detailMat=new THREE.MeshStandardMaterial({
   color:0x0b0d0e,
   metalness:.45,
   roughness:.4
  });

  // Glock-style slide.
  const slide=new THREE.Mesh(new THREE.BoxGeometry(.20,.16,.56),slideMat);
  slide.position.set(0,.055,-.18);
  slide.castShadow=true;
  g.add(slide);

  // Slightly narrower lower frame.
  const frame=new THREE.Mesh(new THREE.BoxGeometry(.18,.105,.39),frameMat);
  frame.position.set(0,-.055,-.12);
  frame.castShadow=true;
  g.add(frame);

  // Exposed muzzle/barrel.
  const barrel=new THREE.Mesh(new THREE.CylinderGeometry(.032,.032,.09,14),detailMat);
  barrel.rotation.x=Math.PI/2;
  barrel.position.set(0,.045,-.50);
  barrel.castShadow=true;
  g.add(barrel);

  // Angled polymer grip.
  const grip=new THREE.Mesh(new THREE.BoxGeometry(.17,.34,.18),frameMat);
  grip.position.set(0,-.235,.02);
  grip.rotation.x=-.16;
  grip.castShadow=true;
  g.add(grip);

  // Magazine base plate.
  const magazineBase=new THREE.Mesh(new THREE.BoxGeometry(.18,.035,.20),detailMat);
  magazineBase.position.set(0,-.405,.045);
  magazineBase.rotation.x=-.16;
  g.add(magazineBase);

  // Trigger guard.
  const triggerGuard=new THREE.Mesh(new THREE.TorusGeometry(.072,.014,7,18,Math.PI*1.45),frameMat);
  triggerGuard.rotation.set(Math.PI/2,0,Math.PI*.76);
  triggerGuard.position.set(0,-.115,-.13);
  g.add(triggerGuard);

  // Trigger.
  const trigger=new THREE.Mesh(new THREE.BoxGeometry(.025,.085,.025),detailMat);
  trigger.position.set(0,-.12,-.13);
  trigger.rotation.x=-.35;
  g.add(trigger);

  // Front and rear sights.
  const frontSight=new THREE.Mesh(new THREE.BoxGeometry(.035,.035,.045),detailMat);
  frontSight.position.set(0,.155,-.42);
  g.add(frontSight);
  const rearSight=new THREE.Mesh(new THREE.BoxGeometry(.09,.045,.045),detailMat);
  rearSight.position.set(0,.16,.035);
  g.add(rearSight);
  this.frontSight=frontSight;
  this.rearSight=rearSight;

  // Slide serrations.
  for(let i=0;i<5;i++){
   const serr=new THREE.Mesh(new THREE.BoxGeometry(.205,.075,.012),detailMat);
   serr.position.set(0,.055,.005+i*.035);
   g.add(serr);
  }

  // Small takedown/slide-stop details.
  const stop=new THREE.Mesh(new THREE.BoxGeometry(.012,.04,.09),detailMat);
  stop.position.set(.106,-.005,-.03);
  g.add(stop);

  // Make the pistol easier to read at gameplay camera distance.
  g.scale.setScalar(1.18);

  this.muzzlePoint=new THREE.Object3D();
  this.muzzlePoint.position.set(0,.045,-.56);
  g.add(this.muzzlePoint);

  return g;
 }
 attachToSoldier(human){
  if(!human||!human.model||!human.rightHandBone)return false;

  this.rightHandBone=human.rightHandBone;
  this.leftHandBone=human.leftHandBone;
  this.rightArmBone=human.rightArmBone;
  this.leftArmBone=human.leftArmBone;
  this.spineBone=human.spineBone;
  this.rightForeArmBone=human.rightForeArmBone;
  this.leftForeArmBone=human.leftForeArmBone;

  this.rightHandBone.add(this.pistol);
  this.soldierAttached=true;

  // Exact shooting-pose calibration exported from Soldier Pose Editor.
  this.pistol.position.set(.055,.010,-.010);
  this.pistol.rotation.set(
   THREE.MathUtils.degToRad(92),
   THREE.MathUtils.degToRad(-2),
   THREE.MathUtils.degToRad(-115)
  );
  this.pistol.scale.setScalar(.40);

  // Capture the neutral upper-body pose as the reference used by editor offsets.
  this.shootingPoseBase={
   rightArm:this.rightArmBone?this.rightArmBone.rotation.clone():null,
   leftArm:this.leftArmBone?this.leftArmBone.rotation.clone():null,
   spine:this.spineBone?this.spineBone.rotation.clone():null
  };

  return true;
 }
 updateSoldierGrip(dt){
  if(!this.soldierAttached||!this.isEquipped)return;

  const pose={
   gunPosition:[.055,.010,-.010],
   gunRotationDeg:[92,-2,-115],
   gunScale:.40,
   rightArmDeg:[34,-9,39],
   leftArmDeg:[-49,-39,-4],
   spineDeg:[0,-13,0],
   blendSpeed:.13
  };

  // Convert the editor's blend factor to a stable frame-rate-independent blend.
  const blend=1-Math.pow(1-pose.blendSpeed,dt*60);
  const lerpRot=(bone,base,deg)=>{
   if(!bone||!base)return;
   bone.rotation.x=THREE.MathUtils.lerp(
    bone.rotation.x,
    base.x+THREE.MathUtils.degToRad(deg[0]),
    blend
   );
   bone.rotation.y=THREE.MathUtils.lerp(
    bone.rotation.y,
    base.y+THREE.MathUtils.degToRad(deg[1]),
    blend
   );
   bone.rotation.z=THREE.MathUtils.lerp(
    bone.rotation.z,
    base.z+THREE.MathUtils.degToRad(deg[2]),
    blend
   );
  };

  if(this.shootingPoseBase){
   lerpRot(this.rightArmBone,this.shootingPoseBase.rightArm,pose.rightArmDeg);
   lerpRot(this.leftArmBone,this.shootingPoseBase.leftArm,pose.leftArmDeg);
   lerpRot(this.spineBone,this.shootingPoseBase.spine,pose.spineDeg);
   // The torso absorbs a smaller part of the shot than the hands/weapon.
   if(this.spineBone)this.spineBone.rotation.x-=this.recoil*this.recoilPreset.bodyKick;
  }

  // Glock pose from the editor, with recoil layered on top.
  this.pistol.position.x=THREE.MathUtils.lerp(this.pistol.position.x,pose.gunPosition[0],blend);
  this.pistol.position.y=THREE.MathUtils.lerp(this.pistol.position.y,pose.gunPosition[1],blend);
  this.pistol.position.z=THREE.MathUtils.lerp(
   this.pistol.position.z,
   pose.gunPosition[2]+this.recoil*.025*this.recoilPreset.weaponKick,
   blend
  );

  this.pistol.rotation.x=THREE.MathUtils.lerp(
   this.pistol.rotation.x,
   THREE.MathUtils.degToRad(pose.gunRotationDeg[0])-this.recoil*.14*this.recoilPreset.weaponKick,
   blend
  );
  this.pistol.rotation.y=THREE.MathUtils.lerp(
   this.pistol.rotation.y,
   THREE.MathUtils.degToRad(pose.gunRotationDeg[1]),
   blend
  );
  this.pistol.rotation.z=THREE.MathUtils.lerp(
   this.pistol.rotation.z,
   THREE.MathUtils.degToRad(pose.gunRotationDeg[2]),
   blend
  );
  this.pistol.scale.setScalar(pose.gunScale);
 }
 bindInputs(){
  addEventListener('keydown',e=>{
   if(!gameStarted||player.userData.dead||e.repeat)return;
   if(e.code==='Digit1'||e.code==='Numpad1')this.loot?.select(0);
   if(e.code==='Digit2'||e.code==='Numpad2')this.loot?.select(1);
   if(e.code==='Digit4'||e.code==='Numpad4')tacticalGear.equipGrenade();
   if(e.code==='Digit3'||e.code==='Numpad3'){this.triggerHeld=false;this.toggle();}
   if(e.code==='KeyR'&&this.isEquipped)this.reload();
  });
  addEventListener('mousedown',e=>{
   if(e.target!==canvas||!gameStarted||this.player.userData.dead||!this.isEquipped||this.isReloading)return;
   if(e.button===0){this.triggerHeld=true;this.fire();}
  });
  addEventListener('mouseup',e=>{if(e.button===0)this.triggerHeld=false;});
  addEventListener('blur',()=>{this.triggerHeld=false;});
 }

 toggle(){
  if(this.isEquipped)this.holster();
  else this.equip();
 }

 equip(){
  if(typeof tacticalGear!=='undefined')tacticalGear.unequip();
  this.isEquipped=true;
  this.isReloading=false;
  const id=this.weaponSpec?.id||'pistol';
  this.equipDuration=id==='pistol'?.22:id==='smg'?.28:id==='rifle'?.38:id==='shotgun'?.42:id==='sniper'?.58:.34;
  this.equipTimer=this.equipDuration;
  this.equipBlend=1;
  this.reloadSoundStage=0;
  this.shotHeat=0;
  this.burstShots=0;
  this.timeSinceShot=10;
  this.spreadKick=0;
  this.lastHandlingWeapon=id;
  forestAudio.playWeaponMechanic(id,'equip');
  this.pistol.visible=true;

  // Right-hand / two-handed TPS posture.
  if(!this.soldierAttached&&!this.operatorAttached){
   this.pistol.position.set(.38,1.28,-.52);
   this.pistol.rotation.set(-.08,0,0);
  }

  if(typeof combatAnimator!=='undefined'){
   combatAnimator.setWeapon('pistol');
  }
 }

 holster(){
  if(this.isEquipped)forestAudio.playWeaponMechanic(this.weaponSpec?.id||'pistol','holster');
  this.isEquipped=false;
  this.isReloading=false;
  this.triggerHeld=false;
  this.equipTimer=0;
  this.equipBlend=0;
  this.pistol.visible=true;

  // Holster on right hip/back side, not inside torso.
  if(this.soldierAttached||this.operatorAttached){
   // Holstered pistol stays attached to hand but hidden for now.
   this.pistol.visible=false;
  }else{
   this.pistol.position.set(.34,.92,.12);
   this.pistol.rotation.set(.08,.12,-.28);
  }

  if(typeof combatAnimator!=='undefined'&&combatAnimator.weapon==='pistol'){
   combatAnimator.setWeapon('none');
  }
 }

 reload(){
  if(!this.isEquipped||this.equipTimer>0||this.isReloading||this.ammo>=this.magSize||this.reserveAmmo<=0)return;
  this.isReloading=true;
  this.burstShots=0;
  this.reloadTimer=0;
  this.reloadBlend=0;
  this.reloadSoundStage=0;
  this.triggerHeld=false;
  forestAudio.playWeaponMechanic(this.weaponSpec?.id||'pistol','magOut');
 }

 finishReload(){
  const needed=this.magSize-this.ammo;
  const loaded=Math.min(needed,this.reserveAmmo);
  this.ammo+=loaded;
  this.reserveAmmo-=loaded;
  this.isReloading=false;
  this.reloadBlend=0;
  this.reloadSoundStage=0;
  forestAudio.playWeaponMechanic(this.weaponSpec?.id||'pistol','ready');
  this.loot?.saveActive();
 }

 impactMaterial(hit){
  if(!hit?.object)return null;
  const mesh=hit.object;
  if(mesh.userData?.enemyRef||mesh.userData?.remoteId)return null;
  if(mesh.userData?.iceWallId)return 'ice';
  if(mesh.userData?.impactMaterial)return mesh.userData.impactMaterial;
  if(mesh.geometry?.type==='PlaneGeometry')return 'dirt';
  const mat=Array.isArray(mesh.material)?mesh.material[0]:mesh.material;
  if((mat?.metalness||0)>.52)return 'metal';
  const hex=mat?.color?.getHex?.();
  if([0x806346,0x453b2b,0x9c7c53,0x826e56,0x614a36,0x35543a,0x617a43,0x456442].includes(hex))return 'wood';
  return 'concrete';
 }
 emitImpact(hit,spec){
  const material=this.impactMaterial(hit);if(!material||!hit?.point)return;
  forestAudio.playMaterialImpact(material,hit.point,this.camera);
  const config={
   concrete:{mark:0x454646,dust:0xa5a29a,count:5},
   wood:{mark:0x493321,dust:0xa67e53,count:6},
   metal:{mark:0x292e32,dust:0xffd17e,count:7},
   dirt:{mark:0x655742,dust:0x8e8061,count:7},
   ice:{mark:0x9bdbea,dust:0xb9f3ff,count:8}
  }[material];
  const normal=hit.face?.normal?.clone().transformDirection(hit.object.matrixWorld)||new THREE.Vector3(0,1,0);
  if(normal.lengthSq()<.01)normal.set(0,1,0);normal.normalize();
  const point=hit.point.clone().addScaledVector(normal,.016);
  const mark=new THREE.Mesh(new THREE.CircleGeometry(material==='metal'?.027:.038,10),
   new THREE.MeshBasicMaterial({color:config.mark,transparent:true,opacity:.78,depthWrite:false,side:THREE.DoubleSide,polygonOffset:true,polygonOffsetFactor:-2}));
  mark.position.copy(point);mark.quaternion.setFromUnitVectors(new THREE.Vector3(0,0,1),normal);
  mark.userData.ignoreCombat=true;mark.userData.ignoreCamera=true;this.scene.add(mark);
  const life=material==='ice'?1.2:5.5;
  this.impactEffects.push({mesh:mark,life,maxLife:life,velocity:null});
  const tangent=new THREE.Vector3(1,0,0);
  if(Math.abs(normal.x)>.85)tangent.set(0,0,1);
  tangent.addScaledVector(normal,-tangent.dot(normal)).normalize();
  const binormal=new THREE.Vector3().crossVectors(normal,tangent).normalize();
  const count=spec.id==='shotgun'?2:Math.min(3,config.count);
  for(let i=0;i<count;i++){
   const size=(material==='metal'?.009:.016)*(.65+Math.random()*.7);
   const part=new THREE.Mesh(new THREE.TetrahedronGeometry(size,0),
    new THREE.MeshBasicMaterial({color:config.dust,transparent:true,opacity:.85,depthWrite:false}));
   part.position.copy(point);part.userData.ignoreCombat=true;part.userData.ignoreCamera=true;
   this.scene.add(part);
   const velocity=normal.clone().multiplyScalar(.6+Math.random()*1.6)
     .addScaledVector(tangent,(Math.random()-.5)*2.4)
     .addScaledVector(binormal,(Math.random()-.5)*2.4);
   const particleLife=.22+Math.random()*.38;
   this.impactEffects.push({mesh:part,velocity,life:particleLife,maxLife:particleLife});
  }
  while(this.impactEffects.length>64){
   const old=this.impactEffects.shift();
   this.scene.remove(old.mesh);old.mesh.geometry.dispose();old.mesh.material.dispose();
  }
 }
 updateImpactEffects(dt){
  for(let i=this.impactEffects.length-1;i>=0;i--){
   const effect=this.impactEffects[i];effect.life-=dt;
   if(effect.velocity){
    effect.velocity.y-=6.5*dt;effect.mesh.position.addScaledVector(effect.velocity,dt);
    effect.mesh.rotation.x+=dt*9;effect.mesh.rotation.z+=dt*11;
   }
   effect.mesh.material.opacity=Math.max(0,effect.life/effect.maxLife)*(effect.velocity?.85:.78);
   if(effect.life<=0){
    this.scene.remove(effect.mesh);effect.mesh.geometry.dispose();effect.mesh.material.dispose();
    this.impactEffects.splice(i,1);
   }
  }
 }
 emitShotEffects(start,spec,flashScale=1){
  const isShotgun=spec.id==='shotgun';
  const casingMaterial=this.casingMaterial[isShotgun?'shotgun':'small'];
  // Cases eject from the right of the receiver, not from the muzzle itself.
  const side=new THREE.Vector3(1,0,0).applyQuaternion(this.player.getWorldQuaternion(new THREE.Quaternion()));
  const back=new THREE.Vector3(0,0,-1).applyQuaternion(this.player.getWorldQuaternion(new THREE.Quaternion()));
  const receiver=start.clone().addScaledVector(back,Math.max(.10,spec.muzzleZ*.65)).addScaledVector(side,.12);
  const capsule=new THREE.Mesh(this.casingGeometry[isShotgun?'shotgun':'small'],casingMaterial);
  capsule.position.copy(receiver);
  capsule.rotation.set(Math.random()*3,Math.random()*3,Math.random()*3);
  capsule.castShadow=false;capsule.userData.ignoreCombat=true;capsule.userData.ignoreCamera=true;
  this.scene.add(capsule);
  this.casings.push({mesh:capsule,velocity:side.multiplyScalar(1.3+Math.random()*1.2).add(new THREE.Vector3(0,1.5+Math.random()*.8,0)).addScaledVector(back,.45),life:1.35});
  if(this.casings.length>12){
   const old=this.casings.shift();this.scene.remove(old.mesh);
  }
  const burst=new THREE.Group();
  burst.position.copy(start);
  burst.scale.setScalar(Math.max(.02,flashScale));
  const direction=new THREE.Vector3(0,0,1).applyQuaternion(this.player.getWorldQuaternion(new THREE.Quaternion()));
  burst.quaternion.setFromUnitVectors(new THREE.Vector3(0,0,1),direction);
  const flame=new THREE.Mesh(new THREE.ConeGeometry(isShotgun?.095:.054,isShotgun?.36:.22,7),new THREE.MeshBasicMaterial({color:0xffe39a,transparent:true,opacity:.9,depthWrite:false}));
  flame.rotation.x=Math.PI/2;flame.position.z=.105;burst.add(flame);
  const core=new THREE.Mesh(new THREE.SphereGeometry(isShotgun?.065:.04,7,5),new THREE.MeshBasicMaterial({color:0xffffff,transparent:true,opacity:.95,depthWrite:false}));
  burst.add(core);burst.userData.ignoreCombat=true;burst.userData.ignoreCamera=true;
  this.scene.add(burst);
  this.muzzleBursts.push({mesh:burst,life:.065});
 }
 emitTracer(start,end){
  let tracer=this.tracerPool[this.tracerCursor];
  if(!tracer){
   const geometry=new THREE.BufferGeometry();
   geometry.setAttribute('position',new THREE.BufferAttribute(new Float32Array(6),3));
   tracer=new THREE.Line(geometry,this.tracerMaterial);
   tracer.userData.ignoreCombat=true;tracer.userData.ignoreCamera=true;
   this.scene.add(tracer);this.tracerPool[this.tracerCursor]=tracer;
  }
  const a=tracer.geometry.attributes.position;
  a.setXYZ(0,start.x,start.y,start.z);a.setXYZ(1,end.x,end.y,end.z);
  a.needsUpdate=true;tracer.geometry.computeBoundingSphere();
  tracer.visible=true;tracer.userData.expiresAt=performance.now()+45;
  this.tracerCursor=(this.tracerCursor+1)%24;
 }
 updateShotEffects(dt){
  const now=performance.now();
  for(const tracer of this.tracerPool)if(tracer.visible&&now>=tracer.userData.expiresAt)tracer.visible=false;
  for(let i=this.casings.length-1;i>=0;i--){
   const c=this.casings[i];c.life-=dt;
   c.velocity.y-=12*dt;
   c.mesh.position.addScaledVector(c.velocity,dt);
   c.mesh.rotation.x+=dt*13;c.mesh.rotation.z+=dt*9;
   if(c.life<=0){
    this.scene.remove(c.mesh);this.casings.splice(i,1);
   }
  }
  for(let i=this.muzzleBursts.length-1;i>=0;i--){
   const b=this.muzzleBursts[i];b.life-=dt;
   b.mesh.scale.setScalar(Math.max(.05,b.life/.065));
   if(b.life<=0){
    this.scene.remove(b.mesh);b.mesh.traverse(o=>{o.geometry?.dispose?.();o.material?.dispose?.()});this.muzzleBursts.splice(i,1);
   }
  }
 }
 fire(){
  if((typeof deployment!=='undefined'&&deployment.phase!=='idle'&&deployment.phase!=='landed')||!gameStarted||this.player.userData.dead||!this.isEquipped||this.isReloading||this.equipTimer>0)return;
  if(controller.cover.active){
   this.player.updateMatrixWorld(true);
   if(!controller.cover.canFireFrom(this.muzzlePoint.getWorldPosition(new THREE.Vector3())))return;
  }
  if(this.fireCooldown>0)return;
  if(this.ammo<=0){
   if(this.reserveAmmo>0){this.reload();}
   else if(this.emptyClickCooldown<=0){
    forestAudio.playWeaponMechanic(this.weaponSpec?.id||'pistol','empty');
    this.emptyClickCooldown=.27;
   }
   return;
  }
  const spec=this.weaponSpec;
  const mods=this.attachmentMods||{spreadMultiplier:1,recoilMultiplier:1,soundMultiplier:1,muzzleFlashMultiplier:1};
  if(this.lastHandlingWeapon!==spec.id){
   this.lastHandlingWeapon=spec.id;this.shotHeat=0;this.spreadKick=0;this.burstShots=0;this.timeSinceShot=10;
  }
  const handling={
   pistol:{heat:.17,maxHeat:.46,recovery:1.45,spread:1.0,kick:.90,camera:.85},
   smg:{heat:.105,maxHeat:1.0,recovery:.88,spread:1.65,kick:.72,camera:.70},
   rifle:{heat:.14,maxHeat:.85,recovery:1.10,spread:1.32,kick:1.0,camera:1.0},
   shotgun:{heat:.28,maxHeat:.44,recovery:1.8,spread:.42,kick:1.55,camera:1.36},
   sniper:{heat:.38,maxHeat:.45,recovery:2.0,spread:.25,kick:1.70,camera:1.48}
  }[spec.id]||{heat:.15,maxHeat:.8,recovery:1,spread:1,kick:1,camera:1};
  if(this.timeSinceShot>Math.max(.30,spec.fireRate*2.8))this.burstShots=0;
  const burstFactor=Math.min(1,this.burstShots/7);
  this.shotHeat=Math.min(handling.maxHeat,this.shotHeat+handling.heat);
  this.spreadKick=Math.min(1.2,this.spreadKick+handling.heat*.7);
  this.burstShots=Math.min(20,this.burstShots+1);
  this.timeSinceShot=0;
  const ads=controller.keys.aiming&&this.isEquipped;
  const locomotion=THREE.MathUtils.clamp(controller.horizontalSpeed/Math.max(1,controller.sprintSpeed),0,1);
  const movementPenalty=1+locomotion*(ads?.6:1.9);
  const airbornePenalty=controller.isGrounded?1:2.3;
  const crouchBonus=controller.isCrouching?.82:1;
  const baseSpread=spec.spread*mods.spreadMultiplier*(ads?.67:1.35)*movementPenalty*airbornePenalty*crouchBonus;
  // Heat increases sustained-fire bloom; pause firing to recover accuracy.
  const effectiveSpread=baseSpread*(1+handling.spread*(this.shotHeat+this.spreadKick*.35));
  const yawDrift=(this.burstShots%6<3?1:-1)*burstFactor*baseSpread*.13;
  this.fireCooldown=spec.fireRate;this.ammo--;
  this.mechanismShot=1;
  forestAudio.init();forestAudio.playShoot(spec.id,mods.soundMultiplier);combatBots?.reportSound?.(this.player.position,mods.suppressor?18:34,'gunshot');
  this.scene.updateMatrixWorld(true);
  const start=this.muzzlePoint.getWorldPosition(new THREE.Vector3()),damageByTarget=new Map(),damageByWall=new Map(),networkRays=[],networkHits=[];
  this.emitShotEffects(start,spec,mods.muzzleFlashMultiplier);
  for(let pellet=0;pellet<spec.pellets;pellet++){
   const centered=spec.pellets>1&&pellet===0;
   const raycaster=new THREE.Raycaster();raycaster.far=spec.range;
   raycaster.setFromCamera(new THREE.Vector2(centered?0:(Math.random()-.5)*effectiveSpread+yawDrift,centered?0:(Math.random()-.5)*effectiveSpread),this.camera);
   let hit=window.CombatBotSystem.firstHit(this.scene,raycaster,this.player);
   let end=hit?.point||raycaster.ray.at(spec.range,new THREE.Vector3());
   const muzzleDirection=end.clone().sub(start),distance=muzzleDirection.length();
   if(distance>.001){
    const muzzleRay=new THREE.Raycaster(start,muzzleDirection.normalize(),0,distance+.01);
    const obstruction=window.CombatBotSystem.firstHit(this.scene,muzzleRay,this.player);
    if(obstruction){hit=obstruction;end=obstruction.point;}
   }
   networkRays.push(end.clone().sub(start).normalize());
   if(hit&&(spec.pellets===1||pellet<3))this.emitImpact(hit,spec);
   const iceId=hit?.object?.userData?.iceWallId;if(iceId)damageByWall.set(iceId,(damageByWall.get(iceId)||0)+spec.damage);
   if(hit?.object?.userData?.remoteId)networkHits.push({targetId:hit.object.userData.remoteId,pellet});
   this.emitTracer(start,end);
   const target=hit?.object?.userData?.enemyRef;
   if(target?.alive){
    const falloff=spec.id==='shotgun'?THREE.MathUtils.clamp(1-Math.max(0,start.distanceTo(end)-8)/25,.25,1):1;
    damageByTarget.set(target,(damageByTarget.get(target)||0)+spec.damage*falloff);
   }
  }
  for(const [id,damage]of damageByWall)tacticalGear.damageWall(id,damage);
  if(multiplayer.active){
   const shotId=Date.now().toString(36)+'-'+(++multiplayerShotSequence).toString(36);
   multiplayer.send({type:'shot3d',shotId,weapon:spec.id,origin:{x:start.x,y:start.y,z:start.z},rays:networkRays.map(r=>({x:r.x,y:r.y,z:r.z}))});
   for(const hit of networkHits)multiplayer.send({type:'hit3d',shotId,...hit});
  }
  // Existing muzzle burst provides the flash without one dynamic point light per shot.
  const weaponScale=handling.kick*mods.recoilMultiplier*(1+burstFactor*.22);
  this.recoil=Math.min(2.4,this.recoil+this.recoilPreset.weaponKick*weaponScale);
  this.recoilVelocity=0;
  if(typeof thirdPersonCamera!=='undefined')thirdPersonCamera.addShotRecoil(
   this.recoilPreset.aimKickDeg*handling.camera*mods.recoilMultiplier*(1+burstFactor*.40)*(ads?.78:1),
   this.recoilPreset.cameraShake*handling.camera*mods.recoilMultiplier*(1+burstFactor*.25),
   this.recoilPreset.recovery
  );
  shots++;
  if(damageByTarget.size){hitCount++;score+=12;flashHitmarker();forestAudio.playHit();for(const [target,damage]of damageByTarget)target.takeDamage(damage);}
  this.loot?.saveActive();
 }

 update(dt,isMoving){
  this.updateShotEffects(dt);
  this.updateImpactEffects(dt);
  this.mechanismShot=Math.max(0,this.mechanismShot-dt*16);
  this.fireCooldown=Math.max(0,this.fireCooldown-dt);
  this.emptyClickCooldown=Math.max(0,this.emptyClickCooldown-dt);
  this.timeSinceShot+=dt;
  const handlingRecovery={pistol:1.45,smg:.88,rifle:1.10,shotgun:1.8,sniper:2}[this.weaponSpec?.id]||1;
  this.shotHeat=Math.max(0,this.shotHeat-handlingRecovery*dt*.45);
  this.spreadKick=Math.max(0,this.spreadKick-handlingRecovery*dt*.75);
  if(this.timeSinceShot>.36)this.burstShots=0;
  this.equipTimer=Math.max(0,this.equipTimer-dt);
  this.equipBlend=this.equipTimer>0?THREE.MathUtils.clamp(this.equipTimer/Math.max(.01,this.equipDuration),0,1):0;

  if(this.isReloading){
   this.reloadTimer+=dt;
   this.reloadBlend=THREE.MathUtils.clamp(this.reloadTimer/Math.max(.01,this.reloadTime),0,1);
   const id=this.weaponSpec?.id||'pistol';
   const shotgun=id==='shotgun',sniper=id==='sniper';
   // Trigger one mechanical cue per normalized animation phase, independent of FPS.
   if(shotgun){
    for(const threshold of [.32,.55,.78]){
     const stage=Math.round(threshold*100);
     if(this.reloadBlend>=threshold&&this.reloadSoundStage<stage){
      forestAudio.playWeaponMechanic(id,'shell');this.reloadSoundStage=stage;
     }
    }
   }else{
    if(this.reloadBlend>=.47&&this.reloadSoundStage<1){
     forestAudio.playWeaponMechanic(id,'magIn');this.reloadSoundStage=1;
    }
    if(this.reloadBlend>=(sniper?.76:.83)&&this.reloadSoundStage<2){
     forestAudio.playWeaponMechanic(id,'bolt');this.reloadSoundStage=2;
    }
   }
   if(this.reloadTimer>=this.reloadTime){
    this.finishReload();
   }
  }else{
   this.reloadBlend=THREE.MathUtils.lerp(this.reloadBlend,0,1-Math.exp(-14*dt));
  }

  if(this.triggerHeld&&this.weaponSpec.auto&&!this.isReloading&&this.isEquipped&&this.equipTimer<=0)this.fire();

  // Fast kick, controlled spring-like recovery. The shot impulse is applied instantly in fire().
  this.recoil*=Math.exp(-this.recoilPreset.recovery*dt);
  if(this.recoil<.001)this.recoil=0;

  if(this.loot?.heldModels&&window.WeaponLootSystem?.animateMechanics){
   const model=this.loot.heldModels.get(this.weaponSpec?.id);
   window.WeaponLootSystem.animateMechanics(model,{reload:this.reloadBlend,reloading:this.isReloading,recoil:this.recoil,shot:this.mechanismShot});
  }
  if(!this.isEquipped)return;

  if(this.avatar.proceduralRig){
   this.avatar.setRecoil(this.recoil*.55);
   return;
  }

  if(this.operatorAttached){
   this.pistol.rotation.x=Math.PI/2-this.recoil*.55;
   return;
  }

  if(useHumanCharacter&&this.soldierAttached){
   this.updateSoldierGrip(dt);
   return;
  }

  const leftArm=this.avatar.leftArm;
  const rightArm=this.avatar.rightArm;
  const torso=this.avatar.torso;

  if(this.isReloading){
   // Bring pistol slightly inward/down during reload.
   rightArm.rotation.x=THREE.MathUtils.lerp(rightArm.rotation.x,-.75,.2);
   rightArm.rotation.z=THREE.MathUtils.lerp(rightArm.rotation.z,-.05,.2);
   leftArm.rotation.x=THREE.MathUtils.lerp(leftArm.rotation.x,-.55,.2);
   leftArm.rotation.z=THREE.MathUtils.lerp(leftArm.rotation.z,.18,.2);
   this.pistol.position.y=THREE.MathUtils.lerp(this.pistol.position.y,1.04,.2);
   this.pistol.position.z=THREE.MathUtils.lerp(this.pistol.position.z,-.28,.2);
   return;
  }

  // Two-handed shooting stance.
  const breath=Math.sin(performance.now()*.0022)*.018;

  rightArm.rotation.x=THREE.MathUtils.lerp(
   rightArm.rotation.x,
   -1.28-this.recoil*.55+breath,
   .24
  );
  rightArm.rotation.z=THREE.MathUtils.lerp(
   rightArm.rotation.z,
   -.12,
   .2
  );

  leftArm.rotation.x=THREE.MathUtils.lerp(
   leftArm.rotation.x,
   -1.18-this.recoil*.25+breath,
   .22
  );
  leftArm.rotation.z=THREE.MathUtils.lerp(
   leftArm.rotation.z,
   .18,
   .2
  );

  torso.rotation.y=THREE.MathUtils.lerp(
   torso.rotation.y,
   -.06,
   .16
  );

  // Recoil affects weapon, not whole player.
  this.pistol.position.set(
   .36,
   1.18+this.recoil*.035,
   -.48+this.recoil*.10
  );
  this.pistol.rotation.x=-.05-this.recoil*.22;

  if(isMoving){
   // Slight gun sway while walking.
   const sway=Math.sin(performance.now()*.009)*.018;
   this.pistol.rotation.z=sway;
  }else{
   this.pistol.rotation.z=THREE.MathUtils.lerp(this.pistol.rotation.z,0,.18);
  }
 }
}

class PlayerController {
 constructor(mesh,camera){
  this.mesh=mesh;
  this.camera=camera;
  this.walkSpeed=6.0;
  this.sprintSpeed=11.0;
  this.crouchSpeed=2.1;
  this.standingHeight=1.8;this.crouchingHeight=1.45;
  this.isCrouching=false;this.crouchBlend=0;this.collisionHeight=this.standingHeight;
  this.crouchInputs=new Set();
  this.cover=new window.CoverController({player:mesh,boxes:()=>houseParkour.solidBoxes,terrainHeight:forestEnvironment.getTerrainHeight});
  this.climb=null;this.climbCooldown=0;
  this.jumpForce=8.5;
  this.jumpPreparation=0;
  this.stepHeight=.42;
  this.stepBlend=0;
  this.landingImpact=0;
  this.hardLanding=0;
  this.recoveryTimer=0;
  this.recoveryStrength=0;
  this.gravity=-22.0;
  this.rotationSpeed=10.0;
  this.velocity=new THREE.Vector3();
  this.isGrounded=true;
  this.horizontalSpeed=0;
  this.moveVelocity=new THREE.Vector3();
  this.strafeAmount=0;
  this.forwardAmount=0;
  this.braking=0;
  this.previousMoveDir=new THREE.Vector3(0,0,1);
  this.turnAmount=0;
  this.turnSharpness=0;
  this.aimTransition=0;
  this.keys={forward:false,backward:false,left:false,right:false,sprint:false,crouch:false,aiming:false,jetpack:false};
  this.stamina=100;
  this.maxStamina=100;
  this._initListeners();
 }
 _initListeners(){
  addEventListener('keydown',e=>{
   if(!gameStarted||player.userData.dead)return;
   if(typeof deployment!=='undefined'&&deployment.phase!=='idle'&&deployment.phase!=='landed')return;
   if((e.code==='KeyC'||e.code==='KeyQ'||e.code==='Space')&&e.repeat)return;
   if(e.code==='ControlLeft'||e.code==='ControlRight'||(e.ctrlKey&&['KeyW','KeyA','KeyS','KeyD'].includes(e.code)))e.preventDefault?.();
   this._onKeyChange(e.code,true);
  });
  addEventListener('keyup',e=>this._onKeyChange(e.code,false));
  addEventListener('blur',()=>this.clearInput());
  addEventListener('mousedown',e=>{if(e.button===2&&e.target===canvas&&gameStarted&&!player.userData.dead)this.keys.aiming=true;});
  addEventListener('mouseup',e=>{if(e.button===2)this.keys.aiming=false;});
  canvas.addEventListener('contextmenu',e=>e.preventDefault());
  document.getElementById('coverBtn')?.addEventListener('click',()=>{if(gameStarted&&!player.userData.dead&&this.isGrounded)this.cover.toggle();});
  document.getElementById('climbBtn')?.addEventListener('click',()=>{if(gameStarted&&!player.userData.dead)this.jumpOrClimb();});
  const peekButton=document.getElementById('peekBtn');
  peekButton?.addEventListener('pointerdown',e=>{e.preventDefault();e.stopPropagation();peekButton.setPointerCapture?.(e.pointerId);if(gameStarted&&!player.userData.dead)this.keys.aiming=true;});
  for(const type of ['pointerup','pointercancel','lostpointercapture'])peekButton?.addEventListener(type,()=>{this.keys.aiming=false;});
  const button=document.getElementById('crouchBtn');
  button?.addEventListener('click',()=>{if(gameStarted&&!player.userData.dead)this.keys.crouch=!this.keys.crouch;});
 }
 clearInput(){for(const key of Object.keys(this.keys))this.keys[key]=false;this.crouchInputs.clear();this.jumpPreparation=0;this.climb=null;}
  jumpOrClimb(){
   if(this.startClimb())return 'climb';
   if(this.climb)return 'climb';
   if(this.isGrounded&&!this.isCrouching&&this.jumpPreparation<=0){this.cover.exit();this.jumpPreparation=.12;return 'jump';}
   return null;
  }
  startClimb(){
   if(this.climb||this.climbCooldown>0||!this.isGrounded||this.isCrouching||this.cover.active||this.mesh.userData.dead||!gameStarted)return false;
   const direction=new THREE.Vector3();this.camera.getWorldDirection(direction);
   const ledge=window.ClimbRules?.findLedge(houseParkour.solidBoxes,this.mesh.position,direction);
   if(!ledge)return false;
   this.climb={start:this.mesh.position.clone(),target:ledge.landing,time:0,duration:Math.max(.48,Math.min(.86,.45+ledge.rise*.14))};
   this.velocity.set(0,0,0);this.moveVelocity.set(0,0,0);
   this.horizontalSpeed=0;this.jumpPreparation=0;this.keys.aiming=false;
   this.isGrounded=false;this.climbCooldown=.6;
   return true;
  }
 recordLanding(velocityY){
  const speed=Math.max(0,-Number(velocityY||0));
  const impact=THREE.MathUtils.clamp((speed-4.5)/10.5,0,1);
  const hard=THREE.MathUtils.clamp((speed-9)/8,0,1);
  this.landingImpact=Math.max(this.landingImpact,impact);
  this.hardLanding=Math.max(this.hardLanding,hard);
  if(hard>.45){
   this.recoveryStrength=Math.max(this.recoveryStrength,hard);
   this.recoveryTimer=Math.max(this.recoveryTimer,.38+.34*hard);
  }
 }
 canStand(){
  const p=this.mesh.position,r=.45;
  return !houseParkour.solidBoxes.some(b=>p.x+r>b.minX&&p.x-r<b.maxX&&p.z+r>b.minZ&&p.z-r<b.maxZ&&b.maxY>p.y+this.crouchingHeight&&b.minY<p.y+this.standingHeight);
 }
 _onKeyChange(code,isPressed){
  if(this.mesh.userData.dead&&isPressed)return;
  if(code==='ControlLeft'||code==='ControlRight'){
   if(isPressed)this.crouchInputs.add(code);else this.crouchInputs.delete(code);
   return;
  }
  if(this.climb){if(code==='Space'&&!isPressed)this.keys.jetpack=false;return;}
   if(code==='KeyQ'){if(isPressed&&this.isGrounded&&gameStarted)this.cover.toggle();return;}
  if(code==='KeyC'){if(isPressed)this.keys.crouch=!this.keys.crouch;return;}
  switch(code){
   case 'KeyW': case 'ArrowUp': this.keys.forward=isPressed; break;
   case 'KeyS': case 'ArrowDown': this.keys.backward=isPressed; break;
   case 'KeyA': case 'ArrowLeft': this.keys.left=isPressed; break;
   case 'KeyD': case 'ArrowRight': this.keys.right=isPressed; break;
   case 'ShiftLeft': case 'ShiftRight': this.keys.sprint=isPressed; break;
   case 'Space':
    if(isPressed){const action=this.jumpOrClimb();this.keys.jetpack=action!=='climb';}
    else this.keys.jetpack=false;
    break;
  }
 }
 update(dt){
  this.climbCooldown=Math.max(0,this.climbCooldown-dt);
   if(this.climb){
    const c=this.climb;c.time+=dt;
    const p=window.ClimbRules.climbPosition(c.start,c.target,Math.min(1,c.time/c.duration));
    this.mesh.position.set(p.x,p.y,p.z);
    this.velocity.set(0,0,0);this.horizontalSpeed=0;
    setAction('jump');if(mixer)mixer.update(dt);
    if(c.time>=c.duration){this.mesh.position.set(c.target.x,c.target.y,c.target.z);this.climb=null;this.isGrounded=true;this.recordLanding(-2);}
    return 'jump';
   }
   this.aimTransition=THREE.MathUtils.lerp(this.aimTransition,this.keys.aiming?1:0,1-Math.exp(-(this.keys.aiming?14:10)*dt));
  this.stepBlend=THREE.MathUtils.lerp(this.stepBlend,0,1-Math.exp(-8*dt));
  this.landingImpact=THREE.MathUtils.lerp(this.landingImpact,0,1-Math.exp(-3.2*dt));
  this.hardLanding=THREE.MathUtils.lerp(this.hardLanding,0,1-Math.exp(-2.6*dt));
  this.recoveryTimer=Math.max(0,this.recoveryTimer-dt);
  if(this.recoveryTimer<=0)this.recoveryStrength=THREE.MathUtils.lerp(this.recoveryStrength,0,1-Math.exp(-7*dt));
  if(this.jumpPreparation>0){
   if(!this.isGrounded||this.isCrouching)this.jumpPreparation=0;
   else{this.jumpPreparation=Math.max(0,this.jumpPreparation-dt);if(this.jumpPreparation===0){this.velocity.y=this.jumpForce;this.isGrounded=false;}}
  }
  this.cover.update(dt,{left:this.keys.left,right:this.keys.right,backward:this.keys.backward,aiming:this.keys.aiming,grounded:this.isGrounded,canStand:this.canStand()});
  const lowPeek=this.cover.active&&this.cover.low&&this.cover.isPeeking;
  const requestedCrouch=!lowPeek&&(this.keys.crouch||this.crouchInputs.size>0||(this.cover.active&&this.cover.low));
  this.isCrouching=this.isGrounded&&(requestedCrouch||(this.isCrouching&&!this.canStand()));
  this.crouchBlend=THREE.MathUtils.lerp(this.crouchBlend,this.isCrouching?1:0,1-Math.exp(-12*dt));
  this.collisionHeight=THREE.MathUtils.lerp(this.standingHeight,this.crouchingHeight,this.crouchBlend);
  const crouchButton=document.getElementById('crouchBtn');
  crouchButton?.setAttribute('aria-pressed',String(this.isCrouching));
  if(crouchButton)crouchButton.textContent=this.isCrouching?'LEVANTAR':'AGACHAR';
  const inputDir=new THREE.Vector3();
  if(this.keys.forward)inputDir.z-=1;
  if(this.keys.backward)inputDir.z+=1;
  if(this.keys.left)inputDir.x-=1;
  if(this.keys.right)inputDir.x+=1;

  let moving=false;
  if(this.cover.active){
   this.horizontalSpeed=this.cover.speed;moving=this.horizontalSpeed>.02;
   this.moveVelocity.multiplyScalar(Math.exp(-14*dt));
   this.strafeAmount=THREE.MathUtils.lerp(this.strafeAmount,0,1-Math.exp(-10*dt));
   this.forwardAmount=THREE.MathUtils.lerp(this.forwardAmount,0,1-Math.exp(-10*dt));
   this.braking=THREE.MathUtils.lerp(this.braking,0,1-Math.exp(-10*dt));
   this.turnAmount=THREE.MathUtils.lerp(this.turnAmount,0,1-Math.exp(-12*dt));
   this.turnSharpness=THREE.MathUtils.lerp(this.turnSharpness,0,1-Math.exp(-12*dt));
   this.stamina=Math.min(this.maxStamina,this.stamina+dt*18);
  }else if(inputDir.lengthSq()>0){
   moving=true;
   inputDir.normalize();

   const cameraDirection=new THREE.Vector3();
   this.camera.getWorldDirection(cameraDirection);
   cameraDirection.y=0;
   cameraDirection.normalize();

   const cameraAngle=Math.atan2(cameraDirection.x,cameraDirection.z);
   const moveAngle=Math.atan2(inputDir.x,inputDir.z)+cameraAngle+Math.PI;
   const moveDir=new THREE.Vector3(Math.sin(moveAngle),0,Math.cos(moveAngle));

   const canSprint=this.keys.sprint&&this.stamina>0&&!this.isCrouching&&!this.keys.aiming;
   const adsMoveScale=this.keys.aiming?.72:1;
   let directionalScale=1;
   if(this.keys.aiming){
    const lateral=Math.abs(inputDir.x);
    const backward=Math.max(0,inputDir.z);
    directionalScale*=1-lateral*.10-backward*.18;
   }
   const recoveryScale=this.recoveryTimer>0?THREE.MathUtils.lerp(.58,.78,1-this.recoveryStrength):1;
   const currentSpeed=(this.isCrouching?this.crouchSpeed:canSprint?this.sprintSpeed:this.walkSpeed)*adsMoveScale*directionalScale*recoveryScale;
   if(canSprint)this.stamina=Math.max(0,this.stamina-dt*24);
   else this.stamina=Math.min(this.maxStamina,this.stamina+dt*16);

   const targetVelocity=moveDir.multiplyScalar(currentSpeed);
   // Velocity-vector based direction changes drive visual pivots without turning the aim camera.
   const oldVX=this.moveVelocity.x,oldVZ=this.moveVelocity.z;
   const oldSpeedSq=oldVX*oldVX+oldVZ*oldVZ;
   const newSpeedSq=targetVelocity.x*targetVelocity.x+targetVelocity.z*targetVelocity.z;
   const turnDot=oldSpeedSq>.36&&newSpeedSq>.36?
     THREE.MathUtils.clamp((oldVX*targetVelocity.x+oldVZ*targetVelocity.z)/Math.sqrt(oldSpeedSq*newSpeedSq),-1,1):1;
   const cross=oldVX*targetVelocity.z-oldVZ*targetVelocity.x;
   const turnAngle=Math.acos(turnDot);
   const turnDirection=cross>0?1:cross<0?-1:0;
   const pivotTarget=Math.min(1,turnAngle/(Math.PI*.70));
   this.turnAmount=THREE.MathUtils.lerp(this.turnAmount,turnDirection,1-Math.exp(-13*dt));
   this.turnSharpness=THREE.MathUtils.lerp(this.turnSharpness,pivotTarget,1-Math.exp(-17*dt));
   const reversal=turnDot<-.25;
   const accel=reversal?18:canSprint?10:13;
   this.moveVelocity.lerp(targetVelocity,1-Math.exp(-accel*dt));
   this.mesh.position.addScaledVector(this.moveVelocity,dt);
   this.horizontalSpeed=this.moveVelocity.length();

   this.strafeAmount=THREE.MathUtils.lerp(this.strafeAmount,inputDir.x,1-Math.exp(-12*dt));
   this.forwardAmount=THREE.MathUtils.lerp(this.forwardAmount,-inputDir.z,1-Math.exp(-12*dt));
   this.braking=THREE.MathUtils.lerp(this.braking,reversal?1:0,1-Math.exp(-16*dt));
   this.previousMoveDir.copy(targetVelocity).normalize();

   // Facing is controlled by the over-the-shoulder camera yaw.
  }else{
   const wasFast=this.moveVelocity.length()>4;
   this.moveVelocity.multiplyScalar(Math.exp(-(wasFast?7.5:11)*dt));
   if(this.moveVelocity.length()<.03)this.moveVelocity.set(0,0,0);
   this.mesh.position.addScaledVector(this.moveVelocity,dt);
   this.horizontalSpeed=this.moveVelocity.length();
   this.strafeAmount=THREE.MathUtils.lerp(this.strafeAmount,0,1-Math.exp(-10*dt));
   this.forwardAmount=THREE.MathUtils.lerp(this.forwardAmount,0,1-Math.exp(-10*dt));
   this.braking=THREE.MathUtils.lerp(this.braking,wasFast?1:0,1-Math.exp(-(wasFast?13:7)*dt));
   this.turnAmount=THREE.MathUtils.lerp(this.turnAmount,0,1-Math.exp(-9*dt));
   this.turnSharpness=THREE.MathUtils.lerp(this.turnSharpness,0,1-Math.exp(-10*dt));
   moving=this.horizontalSpeed>.08;
   this.stamina=Math.min(this.maxStamina,this.stamina+dt*18);
  }

  const terrainY=forestEnvironment.getTerrainHeight(this.mesh.position.x,this.mesh.position.z);

  if(typeof jetpackSystem!=='undefined')jetpackSystem.update(dt,this);
  this.velocity.y+=this.gravity*dt;
  this.mesh.position.y+=this.velocity.y*dt;

  if(this.mesh.position.y<=terrainY){
   if(!this.isGrounded||this.velocity.y<-.5)this.recordLanding(this.velocity.y);
   this.mesh.position.y=terrainY;
   this.velocity.y=0;
   this.isGrounded=true;
  }

  houseParkour.resolvePlayerCollision(this,.45,this.collisionHeight);

  const actionKind=!this.isGrounded?'jump':this.isCrouching?'idle':moving?((this.keys.sprint&&this.stamina>0)?'run':'walk'):'idle';
  setAction(actionKind);
  if(mixer)mixer.update(dt);
  return actionKind;
 }
}

let model=null,mixer=null,actions={},active=null;
let score=0,shots=0,hitCount=0;
const scoreEl=document.getElementById('score');
const hitsEl=document.getElementById('hits');
const playerStateEl=document.getElementById('playerState');
const speedEl=document.getElementById('speed');
const staminaBarEl=document.getElementById('staminaBar');
const altitudeEl=document.getElementById('altitude');
const healthEl=document.getElementById('playerHealth');
const damageFlashEl=document.getElementById('damageFlash');
let playerDamageFlash=0;
const hitmarkerEl=document.getElementById('hitmarker');

function flashHitmarker(){
 if(!hitmarkerEl)return;
 hitmarkerEl.classList.remove('active');
 void hitmarkerEl.offsetWidth;
 hitmarkerEl.classList.add('active');
}

class GTACameraController {
 constructor(camera,targetMesh,domElement,getGroundHeight){
  this.camera=camera;
  this.target=targetMesh;
  this.domElement=domElement;
  this.getGroundHeight=getGroundHeight;

  this.distances=[2.2,4.8,8.5,.05];
  this.modeNames=['3P PERTO','3P MEDIO','3P LONGE','1P'];
  this.modeIndex=1;
  this.targetDistance=this.distances[this.modeIndex];
  this.currentDistance=this.targetDistance;

  this.yaw=0;
  this.pitch=.2;
  this.sensitivity=.00375;
  this.minPitch=-.6;
  this.maxPitch=1.25;
  this.zoomSpeed=10;

  this.offset=new THREE.Vector3(0,1.5,0);
  this.shoulderOffset=.65;
  this.currentShoulderOffset=.65;
  this.isLookingBack=false;
  this.isMouseDown=false;
  this.previousMouseX=0;
  this.previousMouseY=0;
  this.recoilPitch=0;
  this.recoilShake=0;
  this.recoilRecovery=16;
  this.recoilTime=0;
  this.adsBlend=0;
  this.baseFov=camera.fov;

  this.raycaster=new THREE.Raycaster();
  this.collisionMargin=.3;
  this.minCollisionDistance=.4;

  this._initEvents();
 }

 _initEvents(){
  this.domElement.addEventListener('mousedown',e=>{
   if(!gameStarted||player.userData.dead)return;
   this.isMouseDown=true;
   this.previousMouseX=e.clientX;
   this.previousMouseY=e.clientY;
   if(document.pointerLockElement!==this.domElement){
    this.domElement.requestPointerLock?.();
   }
  });

  window.addEventListener('mouseup',()=>{this.isMouseDown=false;});

  window.addEventListener('mousemove',e=>{
   let mx=0,my=0;

   if(document.pointerLockElement===this.domElement){
    mx=e.movementX;
    my=e.movementY;
   }else if(this.isMouseDown){
    mx=e.clientX-this.previousMouseX;
    my=e.clientY-this.previousMouseY;
    this.previousMouseX=e.clientX;
    this.previousMouseY=e.clientY;
   }else{
    return;
   }

   const aimScale=(controller?.keys?.aiming?0.68:1);
   this.yaw-=mx*this.sensitivity*aimScale;
   // Same vertical direction as the supplied tester.
   this.pitch+=my*this.sensitivity*aimScale;
   this.pitch=THREE.MathUtils.clamp(this.pitch,this.minPitch,this.maxPitch);
  });

  document.addEventListener('keydown',e=>{
   if(!gameStarted||player.userData.dead)return;
   if(e.code==='KeyV'){
    this.modeIndex=(this.modeIndex+1)%this.distances.length;
    this.targetDistance=this.distances[this.modeIndex];
   }
   if(e.code==='KeyB')this.isLookingBack=true;
  });

  document.addEventListener('keyup',e=>{
   if(e.code==='KeyB')this.isLookingBack=false;
  });

  window.addEventListener('wheel',e=>{
   if(this.modeIndex===3)return;
   this.targetDistance+=e.deltaY*.005;
   this.targetDistance=THREE.MathUtils.clamp(this.targetDistance,1.2,15);
  },{passive:true});
 }

 addShotRecoil(aimKickDeg=1.6,shake=.46,recovery=16){
  this.recoilPitch=Math.min(THREE.MathUtils.degToRad(7),this.recoilPitch+THREE.MathUtils.degToRad(aimKickDeg));
  this.recoilShake=Math.min(1.4,this.recoilShake+shake);
  this.recoilRecovery=Math.max(1,recovery);
  this.recoilTime=.11;
 }

 _cameraCollision(focusPoint,desiredPosition){
  const rayDirection=desiredPosition.clone().sub(focusPoint);
  const maxDistance=rayDirection.length();
  if(maxDistance<=.001)return desiredPosition;
  rayDirection.normalize();

  this.raycaster.set(focusPoint,rayDirection);
  this.raycaster.far=maxDistance;

  const ignored=new Set();
  this.target.traverse(o=>ignored.add(o));
  if(typeof humanCharacter!=='undefined'&&humanCharacter.model){
   humanCharacter.model.traverse(o=>ignored.add(o));
  }

  const candidates=[];
  scene.traverse(o=>{
   if(!o.isMesh||!o.visible||ignored.has(o))return;
   // Ignore tiny transient weapon/effect meshes attached to player.
   if(o.parent&&ignored.has(o.parent))return;
   for(let p=o;p;p=p.parent)if(p.userData.ignoreCamera||p.userData.ignoreCombat)return;
   candidates.push(o);
  });

  const hits=this.raycaster.intersectObjects(candidates,false);
  if(!hits.length)return desiredPosition;

  const hit=hits[0];
  const safeDistance=Math.max(
   this.minCollisionDistance,
   hit.distance-this.collisionMargin
  );
  return focusPoint.clone().add(rayDirection.multiplyScalar(safeDistance));
 }

 update(delta,aiming=false){
  if(!this.target)return;

  const applyBodyTurn=(desiredYaw)=>{
   const current=this.target.rotation.y;
   const diff=Math.atan2(Math.sin(desiredYaw-current),Math.cos(desiredYaw-current));
   const speed=aiming?16:controller.horizontalSpeed>6?10:12;
   const blend=1-Math.exp(-speed*delta);
   this.target.rotation.y=current+diff*blend;
   controller.turnAmount=THREE.MathUtils.lerp(controller.turnAmount,THREE.MathUtils.clamp(diff/(Math.PI*.55),-1,1),1-Math.exp(-18*delta));
   controller.turnSharpness=THREE.MathUtils.lerp(controller.turnSharpness,THREE.MathUtils.clamp(Math.abs(diff)/(Math.PI*.75),0,1),1-Math.exp(-14*delta));
  };

  const blend=1-Math.exp(-this.zoomSpeed*delta);
  const adsTarget=0;
  this.adsBlend=THREE.MathUtils.lerp(this.adsBlend,adsTarget,1-Math.exp(-delta*(adsTarget?14:10)));
  const adsDistance=THREE.MathUtils.lerp(this.targetDistance,Math.min(this.targetDistance,2.8),this.adsBlend);
  this.currentDistance=THREE.MathUtils.lerp(
   this.currentDistance,
   this.modeIndex===3&&controller.cover.active?2.5:adsDistance,
   blend
  );
  const targetFov=THREE.MathUtils.lerp(this.baseFov,50,this.adsBlend);
  if(!aiming&&Math.abs(this.camera.fov-targetFov)>.01){
   this.camera.fov=THREE.MathUtils.lerp(this.camera.fov,targetFov,1-Math.exp(-delta*14));
   this.camera.updateProjectionMatrix();
  }

  this.recoilPitch*=Math.exp(-this.recoilRecovery*delta);
  this.recoilShake*=Math.exp(-this.recoilRecovery*1.25*delta);
  this.recoilTime=Math.max(0,this.recoilTime-delta);
  const effectivePitch=THREE.MathUtils.clamp(this.pitch-this.recoilPitch,this.minPitch,this.maxPitch);

  this.offset.y=(aiming?1.55:1.5)-controller.crouchBlend*.35;
  const activeYaw=this.isLookingBack?this.yaw+Math.PI:this.yaw;
  const bodyFocus=this.target.position.clone().add(this.offset);
  const focusPoint=bodyFocus.clone();

  if(aiming||(this.modeIndex===3&&!controller.cover.active)){
   this.camera.position.copy(focusPoint);

   const lookDir=new THREE.Vector3(
    -Math.sin(activeYaw)*Math.cos(effectivePitch),
    -Math.sin(effectivePitch),
    -Math.cos(activeYaw)*Math.cos(effectivePitch)
   ).normalize();

   this.camera.lookAt(focusPoint.clone().add(lookDir));

   if(!this.isLookingBack){
    applyBodyTurn(controller.cover.facingYaw(this.yaw+Math.PI));
   }

   if(typeof humanCharacter!=='undefined'&&humanCharacter.model){
    humanCharacter.model.visible=false;
   }
   if(typeof mainAvatar!=='undefined'&&mainAvatar.group){
    mainAvatar.group.visible=false;
   }
   return;
  }

  // Shift both the camera and its aim pivot; keep the white dot at raycast center.
  const screenRight=new THREE.Vector3(Math.cos(activeYaw),0,-Math.sin(activeYaw));
  const adsShoulder=THREE.MathUtils.lerp(this.shoulderOffset,.92,this.adsBlend);
  this.currentShoulderOffset=THREE.MathUtils.lerp(this.currentShoulderOffset,adsShoulder*controller.cover.shoulderSign(activeYaw),blend);
  focusPoint.addScaledVector(screenRight,this.currentShoulderOffset);

  const offsetX=Math.sin(activeYaw)*Math.cos(effectivePitch)*this.currentDistance;
  const offsetY=Math.sin(effectivePitch)*this.currentDistance;
  const offsetZ=Math.cos(activeYaw)*Math.cos(effectivePitch)*this.currentDistance;

  let desiredPosition=new THREE.Vector3(
   focusPoint.x+offsetX,
   focusPoint.y+offsetY,
   focusPoint.z+offsetZ
  );

  desiredPosition=this._cameraCollision(bodyFocus,desiredPosition);

  if(typeof this.getGroundHeight==='function'){
   const minY=this.getGroundHeight(desiredPosition.x,desiredPosition.z)+.35;
   if(desiredPosition.y<minY)desiredPosition.y=minY;
  }

  if(this.recoilShake>.001&&this.recoilTime>0){
   const shakeAmount=this.recoilShake*.018;
   desiredPosition.x+=(Math.random()-.5)*shakeAmount;
   desiredPosition.y+=(Math.random()-.5)*shakeAmount;
  }
  this.camera.position.copy(desiredPosition);
  this.camera.lookAt(focusPoint);

  if(!this.isLookingBack){
   applyBodyTurn(controller.cover.facingYaw(this.yaw+Math.PI));
  }

  if(typeof humanCharacter!=='undefined'&&humanCharacter.model){
   humanCharacter.model.visible=true;
  }
  if(typeof mainAvatar!=='undefined'&&mainAvatar.group){
   mainAvatar.group.visible=!useHumanCharacter;
  }
 }
}


function getAimRaycastHit(raycaster,camera,scene,avatarGroup,ignoredObjects=[]){
 raycaster.setFromCamera(new THREE.Vector2(0,0),camera);

 const avatarMeshes=[];
 avatarGroup.traverse(child=>{
  if(child.isMesh)avatarMeshes.push(child);
 });
 const allIgnored=new Set([...avatarMeshes,...ignoredObjects]);

 const validTargets=scene.children.filter(obj=>!allIgnored.has(obj)&&obj!==avatarGroup);
 const intersects=raycaster.intersectObjects(validTargets,true);
 return intersects.find(hit=>!allIgnored.has(hit.object))||null;
}

const mainAvatar=new window.OperatorAvatar();
window.GameSkins?.attachAvatar(mainAvatar);
// Operator local +Z already follows the player root facing set by the camera.
mainAvatar.group.rotation.y=0;
mainAvatar.group.userData.combatHitWhenHidden=true;
player.add(mainAvatar.group);
const combatAnimator=new RealisticCombatAnimator(player,mainAvatar);
const humanCharacter=new HumanCharacter(scene,camera);
let useHumanCharacter=false;

async function activateHumanCharacter(url='/assets/models/human_rigged.glb'){
 try{
  const model=await humanCharacter.load(url);
  // Keep existing player root for physics/camera/collisions.
  if(model.parent)model.parent.remove(model);
  player.add(model);
  model.position.set(0,0,0);
  // Soldier GLB local forward is opposite our TPS forward.
  model.userData.forwardYawOffset=Math.PI;
  model.rotation.y=model.userData.forwardYawOffset;

  const bounds=new THREE.Box3().setFromObject(model);
  const height=bounds.max.y-bounds.min.y;
  if(height>0)model.scale.setScalar(1.8/height);
  const scaledBounds=new THREE.Box3().setFromObject(model);
  model.position.y=-scaledBounds.min.y;

  mainAvatar.group.visible=false;
  useHumanCharacter=true;
  if(typeof pistolWeapon!=='undefined')pistolWeapon.attachToSoldier(humanCharacter);
  stateEl.textContent='HUMANO GLB ATIVO';
  return true;
 }catch(err){
  console.warn('Human GLB unavailable, procedural fallback active:',err);
  mainAvatar.group.visible=true;
  useHumanCharacter=false;
  return false;
 }
}
const pistolWeapon=new PistolController(scene,player,mainAvatar,camera);

// Dedicated first-person weapon model used only while ADS.
// Keeping it on the camera prevents the world avatar rig from blocking movement or drifting off-center.
const adsViewModel=new THREE.Group();
adsViewModel.name='ADS_VIEWMODEL';
camera.add(adsViewModel);
if(!camera.parent)scene.add(camera);
let adsViewWeapon=null;
let adsViewWeaponId=null;
function ensureAdsViewWeapon(id){
 if(adsViewWeaponId===id&&adsViewWeapon)return adsViewWeapon;
 if(adsViewWeapon){
  adsViewModel.remove(adsViewWeapon);
  adsViewWeapon.traverse(o=>{if(o.isMesh){o.geometry?.dispose?.();}});
 }
 adsViewWeapon=window.WeaponLootSystem.createModel(id);
 adsViewWeaponId=id;
 adsViewModel.add(adsViewWeapon);
 return adsViewWeapon;
}
function updateAdsViewModel(dt){
 const active=controller?.keys?.aiming&&pistolWeapon.isEquipped&&!pistolWeapon.isReloading&&pistolWeapon.equipTimer<=0;
 const id=weaponLoot?.definition?.id||'pistol';
 adsViewModel.visible=!!active;
 if(!active)return;
 const gun=ensureAdsViewWeapon(id);
 window.WeaponLootSystem?.applyAccessoryVisuals?.(gun,id,weaponLoot?.slots?.[weaponLoot.activeSlot]?.attachments||{});
 window.WeaponLootSystem?.animateMechanics?.(gun,{reload:pistolWeapon.reloadBlend,reloading:pistolWeapon.isReloading,shot:pistolWeapon.mechanismShot});
 const recoil=pistolWeapon.recoil||0;
 const bob=controller.horizontalSpeed>0.1?Math.sin(performance.now()*.009)*.004:0;
 const poses={
  pistol:{p:[.10,-.20,-.50],r:[-.02,Math.PI,0],s:.58},
  smg:{p:[.12,-.23,-.66],r:[-.012,Math.PI,0],s:.52},
  rifle:{p:[.11,-.24,-.74],r:[-.01,Math.PI,0],s:.50},
  shotgun:{p:[.13,-.25,-.78],r:[-.012,Math.PI,0],s:.48},
  sniper:{p:[.10,-.26,-.90],r:[-.008,Math.PI,0],s:.46}
 };
 const pose=poses[id]||poses.pistol;
 const t=1-Math.exp(-dt*20);
 gun.position.x=THREE.MathUtils.lerp(gun.position.x,pose.p[0]+bob,t);
 gun.position.y=THREE.MathUtils.lerp(gun.position.y,pose.p[1]-Math.abs(bob)*.4+recoil*.012,t);
 gun.position.z=THREE.MathUtils.lerp(gun.position.z,pose.p[2]+recoil*.06,t);
 gun.rotation.x=THREE.MathUtils.lerp(gun.rotation.x,pose.r[0]-recoil*.08,t);
 gun.rotation.y=THREE.MathUtils.lerp(gun.rotation.y,pose.r[1],t);
 gun.rotation.z=THREE.MathUtils.lerp(gun.rotation.z,pose.r[2]+bob*.7,t);
 gun.scale.setScalar(pose.s);
}

// Use the locally bundled, approved operator instead of loading Soldier from a CDN.
pistolWeapon.pistol.removeFromParent ? pistolWeapon.pistol.removeFromParent() : pistolWeapon.pistol.parent.remove(pistolWeapon.pistol);
pistolWeapon.pistol=mainAvatar.gun;
pistolWeapon.operatorAttached=true;
pistolWeapon.muzzlePoint.position.set(0,.035,.2);
mainAvatar.gun.add(pistolWeapon.muzzlePoint);
pistolWeapon.holster();
stateEl.textContent='OPERADOR 2K • 18 OSSOS';

// Erika preservada no projeto, mas desativada nesta build.
const useErika=false;
if(useErika)new THREE.FBXLoader().load('/assets/models/erika-archer.fbx',fbx=>{
 model=fbx;
 model.traverse(o=>{if(o.isMesh){o.castShadow=true;o.receiveShadow=true}});
 const box3=new THREE.Box3().setFromObject(model),h=box3.max.y-box3.min.y;
 model.scale.setScalar(h>0?1.85/h:1);
 const b2=new THREE.Box3().setFromObject(model); model.position.y=-b2.min.y;
 player.add(model);
 mainAvatar.group.visible=false;
 if(model.animations?.length){
   mixer=new THREE.AnimationMixer(model);
   for(const clip of model.animations) actions[clip.name.toLowerCase()]=mixer.clipAction(clip);
 }
 stateEl.textContent='ERIKA READY';
},undefined,()=>{
 mainAvatar.group.visible=true;
 stateEl.textContent='AVATAR PROCEDURAL';
});

function pickAction(kind){
 const names=kind==='run'?['run','sprint']:kind==='walk'?['walk','locomotion']:kind==='jump'?['jump']:['idle','stand'];
 for(const n of names){const k=Object.keys(actions).find(k=>k.includes(n)); if(k)return actions[k]}
 return null;
}
function setAction(kind){
 const next=pickAction(kind); if(next===active)return;
 if(active)active.fadeOut(.14);
 active=next;
 if(active)active.reset().fadeIn(.14).play();
}


class SpecialJetpack {
 constructor(scene,player,getGroundHeight){
  this.scene=scene;
  this.player=player;
  this.getGroundHeight=getGroundHeight;
  this.equipped=false;
  this.fuel=100;
  this.maxFuel=100;
  this.thrust=31;
  this.maxRiseSpeed=11;
  this.burnRate=24;
  this.rechargeRate=15;
  this.pickupRadius=2.2;
  this.pickupPosition=new THREE.Vector3(0,getGroundHeight(0,14)+6.15,14);
  this.pickup=this._buildJetpack(false);
  this.pickup.position.copy(this.pickupPosition);
  scene.add(this.pickup);

  const ringMat=new THREE.MeshBasicMaterial({color:0xffb52e,transparent:true,opacity:.75});
  this.ring=new THREE.Mesh(new THREE.TorusGeometry(.85,.045,8,32),ringMat);
  this.ring.rotation.x=Math.PI/2;
  this.ring.position.copy(this.pickupPosition);
  this.ring.position.y-=.42;
  scene.add(this.ring);

  this.glow=new THREE.PointLight(0xffa91f,2.1,5);
  this.glow.position.copy(this.pickupPosition);
  scene.add(this.glow);

  this.backpack=null;
  this.flames=[];
  this._bind();
 }
 _buildJetpack(onBack){
  const g=new THREE.Group();
  g.name='SPECIAL_JETPACK';
  const dark=new THREE.MeshStandardMaterial({color:0x22282a,metalness:.55,roughness:.42});
  const panel=new THREE.MeshStandardMaterial({color:0x3c4243,metalness:.35,roughness:.5});
  const gold=new THREE.MeshStandardMaterial({color:0xe59b21,emissive:0x5b2a00,emissiveIntensity:.45,metalness:.5,roughness:.35});
  const body=new THREE.Mesh(new THREE.BoxGeometry(.52,.58,.22),panel);
  body.castShadow=true;g.add(body);
  const handle=new THREE.Mesh(new THREE.TorusGeometry(.16,.035,6,16,Math.PI),dark);
  handle.rotation.z=Math.PI;handle.position.set(0,.37,0);g.add(handle);
  for(const sx of [-.38,.38]){
   const tank=new THREE.Mesh(new THREE.CylinderGeometry(.13,.16,.58,12),dark);
   tank.position.set(sx,0,0);tank.castShadow=true;g.add(tank);
   const band=new THREE.Mesh(new THREE.CylinderGeometry(.145,.145,.08,12),gold);
   band.position.set(sx,.10,0);g.add(band);
   const nozzle=new THREE.Mesh(new THREE.CylinderGeometry(.11,.075,.18,12),dark);
   nozzle.position.set(sx,-.36,0);g.add(nozzle);
   const flame=new THREE.Mesh(new THREE.ConeGeometry(.09,.46,10),new THREE.MeshBasicMaterial({color:0xffb12b,transparent:true,opacity:0}));
   flame.position.set(sx,-.66,0);flame.rotation.z=Math.PI;g.add(flame);
   g.userData.flames=(g.userData.flames||[]);g.userData.flames.push(flame);
  }
  const emblem=new THREE.Mesh(new THREE.BoxGeometry(.26,.07,.235),gold);
  emblem.position.set(0,.02,.02);g.add(emblem);
  g.scale.setScalar(onBack?.72:.9);
  return g;
 }
 _bind(){
  addEventListener('keydown',e=>{
   if(e.code!=='KeyE'||e.repeat||!gameStarted||player.userData.dead||this.equipped)return;
   if(this.player.position.distanceTo(this.pickupPosition)<=this.pickupRadius)this.pickupNow();
  });
 }
 pickupNow(){
  if(this.equipped||this.player.userData.dead)return;
  this.equipped=true;
  this.pickup.visible=false;this.ring.visible=false;this.glow.visible=false;
  this.backpack=this._buildJetpack(true);
  this.backpack.position.set(0,1.28,-.34);
  this.backpack.rotation.y=0;
  this.player.add(this.backpack);
  this.flames=this.backpack.userData.flames||[];
  const hud=document.getElementById('jetpackHud');if(hud)hud.hidden=false;
  const prompt=document.getElementById('jetpackPrompt');if(prompt)prompt.hidden=true;
 }
 dropOnDeath(position){
  if(!this.equipped)return false;
  this.equipped=false;
  if(this.backpack){
   this.player.remove(this.backpack);
   this.backpack.traverse(o=>{if(o.isMesh){o.geometry.dispose();o.material.dispose();}});
  }
  this.backpack=null;this.flames=[];
  this.pickupPosition.copy(position);this.pickupPosition.y+=.48;
  this.pickup.position.copy(this.pickupPosition);this.ring.position.copy(this.pickupPosition);this.ring.position.y-=.42;
  this.glow.position.copy(this.pickupPosition);
  this.pickup.visible=true;this.ring.visible=true;this.glow.visible=true;
  const hud=document.getElementById('jetpackHud');if(hud)hud.hidden=true;
  const prompt=document.getElementById('jetpackPrompt');if(prompt)prompt.hidden=true;
  return true;
 }
 update(dt,controller){
  if(!this.equipped){
   const near=this.player.position.distanceTo(this.pickupPosition)<=this.pickupRadius;
   const p=document.getElementById('jetpackPrompt');
   if(p){p.hidden=!near;p.textContent='E · PEGAR JETPACK ESPECIAL';}
   this.ring.rotation.z+=dt*.9;
   this.pickup.rotation.y+=dt*.65;
   this.pickup.position.y=this.pickupPosition.y+Math.sin(performance.now()*.002)*.08;
   return;
  }

  const active=controller.keys.jetpack&&this.fuel>0&&!controller.cover.active;
  if(active){
   controller.isGrounded=false;
   controller.velocity.y=Math.min(this.maxRiseSpeed,controller.velocity.y+this.thrust*dt);
   this.fuel=Math.max(0,this.fuel-this.burnRate*dt);
  }else{
   this.fuel=Math.min(this.maxFuel,this.fuel+this.rechargeRate*dt);
  }
  for(const flame of this.flames){
   flame.material.opacity=THREE.MathUtils.lerp(flame.material.opacity,active?.95:0,1-Math.exp(-dt*16));
   flame.scale.y=active?.75+Math.random()*.45:.2;
  }
  const fill=document.getElementById('jetpackFuelFill');
  const text=document.getElementById('jetpackFuelText');
  if(fill)fill.style.width=this.fuel.toFixed(0)+'%';
  if(text)text.textContent=this.fuel.toFixed(0)+'%';
 }
}
const jetpackSystem=new SpecialJetpack(scene,player,forestEnvironment.getTerrainHeight);

const controller=new PlayerController(player,camera);
const thirdPersonCamera=new GTACameraController(camera,player,canvas,forestEnvironment.getTerrainHeight);
const weaponLoot=new window.WeaponLootSystem({scene,player,avatar:mainAvatar,controller:pistolWeapon,terrainHeight:forestEnvironment.getTerrainHeight,solidBoxes:()=>houseParkour.solidBoxes});
window.weaponLoot=weaponLoot;
window.weaponController=pistolWeapon;
window.weaponLoot=weaponLoot;
window.weaponController=pistolWeapon;
addEventListener('keydown',e=>{if(gameStarted&&!player.userData.dead&&e.code==='KeyE'&&!e.repeat)weaponLoot.pickup();});
document.getElementById('pickupBtn')?.addEventListener('click',()=>{if(gameStarted&&!player.userData.dead)weaponLoot.pickup();});
for(let slot=0;slot<2;slot++)document.getElementById('weaponSlot'+slot)?.addEventListener('click',()=>{if(gameStarted&&!player.userData.dead)weaponLoot.select(slot);});

function corpseFloorAt(x,z,fromY){
 let floor=forestEnvironment.getTerrainHeight(x,z);
 for(const box of houseParkour.solidBoxes)if(x>=box.minX&&x<=box.maxX&&z>=box.minZ&&z<=box.maxZ&&box.maxY<=fromY+.10)floor=Math.max(floor,box.maxY);
 return floor;
}
// Sample supporting terrain separately under each foot (visual-only, no collision changes).
// The character faces local +Z; rotate local foot offsets by the player's yaw.
const soldierFootHeights={left:0,right:0};
let soldierFootProbeAccumulator=1;
function sampleSoldierFootHeights(dt){
 if(!controller.isGrounded||playerLife.dead){
  soldierFootHeights.left=0;soldierFootHeights.right=0;return soldierFootHeights;
 }
 // Foot probes at ~30 Hz; smoothing is performed every animation frame.
 soldierFootProbeAccumulator+=dt;
 if(soldierFootProbeAccumulator<1/30)return soldierFootHeights;
 soldierFootProbeAccumulator=0;
 const yaw=player.rotation.y,sin=Math.sin(yaw),cos=Math.cos(yaw);
 const feet=[-.18,.18],result=soldierFootHeights;
 for(let i=0;i<2;i++){
  const localX=feet[i],localZ=.045;
  const x=player.position.x+localX*cos+localZ*sin;
  const z=player.position.z-localX*sin+localZ*cos;
  // Existing platform AABBs are the same supports used for the game's collision logic.
  let surface=forestEnvironment.getTerrainHeight(x,z);
  for(const box of houseParkour.solidBoxes){
   if(x>=box.minX&&x<=box.maxX&&z>=box.minZ&&z<=box.maxZ&&
      box.maxY<=player.position.y+.28&&box.maxY>=player.position.y-.65){
    surface=Math.max(surface,box.maxY);
   }
  }
  result[i===0?'right':'left']=Math.max(-.24,Math.min(.24,surface-player.position.y));
 }
 return result;
}
let corpseFallVelocity=0;
const playerLife=new window.PlayerLife({
 onDamage:damage=>{
  playerDamageFlash=.65;lastReceivedDamage=damage;forestAudio.playPlayerHit();thirdPersonCamera.addShotRecoil(.3,.85,8);
 },
 onDeath:()=>{
  corpseFallVelocity=Math.min(0,controller.velocity.y);player.userData.dead=true;controller.cover.exit();controller.clearInput();controller.velocity.set(0,0,0);controller.horizontalSpeed=0;
  const deathPosition=player.position.clone();
  tacticalGear.unequip();weaponLoot.dropOnDeath(deathPosition);
  const jetpackPosition=weaponLoot.safeDrop(deathPosition)||new THREE.Vector3(deathPosition.x,corpseFloorAt(deathPosition.x,deathPosition.z,deathPosition.y),deathPosition.z);
  jetpackSystem.dropOnDeath(jetpackPosition);
 },
 onRespawn:()=>{
  player.userData.dead=false;combatBots.health=100;controller.cover.exit();controller.clearInput();controller.velocity.set(0,0,0);controller.isGrounded=true;controller.stamina=controller.maxStamina;
  if(!multiplayer.active)player.position.set(0,forestEnvironment.getTerrainHeight(0,0),0);
  weaponLoot.resetAfterDeath();tacticalGear.resetInventory();playerDamageFlash=0;
 }
});
let lastReceivedDamage=0;
let playerHitReaction={strength:0,side:0,front:0};
const combatBots=new window.CombatBotSystem({
 scene,player,camera,terrainHeight:forestEnvironment.getTerrainHeight,solidBoxes:houseParkour.solidBoxes,
 onKill:bot=>{score+=100;weaponLoot.dropFromBot(bot.group.position);},
 onPlayerHit:(health,damage,source)=>{
  if(source){
   const toSource=new THREE.Vector3(source.x-player.position.x,0,source.z-player.position.z);
   if(toSource.lengthSq()>.0001){
    toSource.normalize();
    const local=toSource.applyAxisAngle(new THREE.Vector3(0,1,0),-player.rotation.y);
    playerHitReaction.side=THREE.MathUtils.clamp(local.x,-1,1);
    playerHitReaction.front=THREE.MathUtils.clamp(local.z,-1,1);
   }
  }
  playerHitReaction.strength=Math.max(playerHitReaction.strength,THREE.MathUtils.clamp((damage||6)/18,.25,1));
  playerLife.receiveHealth(health);
 },
 onPlayerDeath:()=>playerLife.die(5)
});

let tacticalNoticeTime=0;
const tacticalGear=new window.TacticalGear({
 scene,player,camera,hand:mainAvatar.rightHand,boxes:()=>houseParkour.solidBoxes,terrainHeight:forestEnvironment.getTerrainHeight,
 canAct:()=>gameStarted&&!player.userData.dead,online:()=>multiplayer.active,send:message=>multiplayer.send(message),
 onEquip:()=>{pistolWeapon.holster();pistolWeapon.triggerHeld=false;controller.keys.aiming=false;},
 targets:()=>[
  ...(!playerLife.dead?[{id:'self',position:player.position,damage:amount=>combatBots.damagePlayer(amount)}]:[]),
  ...(multiplayer.active?[...multiplayerWorld.players.values()].filter(p=>!p.state.dead).map(p=>({position:p.avatar.group.position,damage:()=>{}})):combatBots.bots.filter(b=>b.alive).map(b=>({position:b.group.position,damage:amount=>b.takeDamage(amount)})))
 ],
 onEffect:(kind,position)=>forestAudio.playTactical(kind,player.position.distanceTo(new THREE.Vector3(position.x,position.y,position.z))),
 notify:message=>{const notice=document.getElementById('tacticalNotice');if(notice){notice.textContent=message;notice.hidden=false;tacticalNoticeTime=2.5;}}
});
combatBots.onCoverHit=(id,damage)=>tacticalGear.damageWall(id,damage);
combatBots.getGrenades=()=>[...tacticalGear.grenades.values()].map(entry=>entry.state);
combatBots.getWalls=()=>[...tacticalGear.walls.values()];
addEventListener('keydown',e=>{if(gameStarted&&!player.userData.dead&&!e.repeat&&e.code==='KeyF')tacticalGear.deployIce();});
addEventListener('mousedown',e=>{if(e.button===0&&e.target===canvas)tacticalGear.beginThrow();});
addEventListener('mouseup',e=>{if(e.button===0)tacticalGear.endThrow();});
addEventListener('blur',()=>tacticalGear.cancelThrow());
document.getElementById('grenadeSlotBtn')?.addEventListener('click',()=>tacticalGear.equipGrenade());
document.getElementById('iceWallBtn')?.addEventListener('click',()=>tacticalGear.deployIce());
const grenadeThrowButton=document.getElementById('grenadeThrowBtn');
grenadeThrowButton?.addEventListener('pointerdown',e=>{e.preventDefault();grenadeThrowButton.setPointerCapture?.(e.pointerId);tacticalGear.beginThrow();});
grenadeThrowButton?.addEventListener('pointerup',e=>{e.preventDefault();tacticalGear.endThrow();});
for(const event of ['pointercancel','lostpointercapture'])grenadeThrowButton?.addEventListener(event,()=>tacticalGear.cancelThrow());

function updateCamera(dt){
 if(playerLife.dead){
  mainAvatar.group.visible=true;adsViewModel.visible=false;
  document.getElementById('opticReticle')?.classList.remove('active');document.getElementById('sniperScope')?.classList.remove('active');document.getElementById('aimDot')?.classList.add('ads-hidden');document.body.classList.remove('ads-optic','ads-scope');
  const focus=player.position.clone().add(new THREE.Vector3(0,.35,0));
  const offset=new THREE.Vector3(2,2.8,-3.7).applyAxisAngle(new THREE.Vector3(0,1,0),player.rotation.y);
  camera.position.lerp(focus.clone().add(offset),1-Math.exp(-5*dt));camera.lookAt(focus);camera.fov=THREE.MathUtils.lerp(camera.fov,58,1-Math.exp(-5*dt));camera.updateProjectionMatrix();return;
 }
 const ads=controller.keys.aiming&&pistolWeapon.isEquipped&&!pistolWeapon.isReloading&&pistolWeapon.equipTimer<=0;
 const aimDot=document.getElementById('aimDot');
 const optic=document.getElementById('opticReticle');
 const scope=document.getElementById('sniperScope');
 const weaponId=weaponLoot?.definition?.id||'pistol';

 if(!ads){
  thirdPersonCamera.update(dt);
  aimDot?.classList.remove('ads-hidden');
  optic?.classList.remove('active');
  scope?.classList.remove('active');
  document.body.classList.remove('ads-optic','ads-scope');
  return;
 }

 let targetFov=46;
 let mode='iron';

 if(weaponId==='smg'||weaponId==='rifle'){
  mode='optic';
  targetFov=38;
 }else if(weaponId==='sniper'){
  mode='scope';
  targetFov=20;
 }else if(weaponId==='shotgun'){
  targetFov=43;
 }

 // Use the same mouse yaw/pitch and player position in both camera modes.
 // The old sight meshes belong to a detached gun and cannot define aim direction.
 thirdPersonCamera.update(dt,true);

 camera.fov=THREE.MathUtils.lerp(camera.fov,targetFov,1-Math.exp(-dt*(weaponId==='sniper'?10:14)));
 camera.updateProjectionMatrix();

 aimDot?.classList.add('ads-hidden');
 optic?.classList.toggle('active',mode==='optic');
 scope?.classList.toggle('active',mode==='scope');
 document.body.classList.toggle('ads-optic',mode==='optic');
 document.body.classList.toggle('ads-scope',mode==='scope');
}
function resize(){renderer.setSize(innerWidth,innerHeight,false);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix()}
addEventListener('resize',resize);resize();


/* Current 3D game's aircraft and parachute sequence. No 2D canvas dependencies. */
const deployment={phase:'idle',time:0,height:0,flightZ:0,plane:null,chute:null,button:null,keys:new Set()};
function createDeploymentVisuals(){
 if(deployment.plane)return;
 // Original low-poly military transport, using shared materials and simple geometry.
 const paint=new THREE.MeshStandardMaterial({color:0x758994,metalness:.38,roughness:.62,flatShading:true});
 const dark=new THREE.MeshStandardMaterial({color:0x293d49,metalness:.45,roughness:.55});
 const wingPaint=new THREE.MeshStandardMaterial({color:0x5b7480,metalness:.28,roughness:.7});
 const glass=new THREE.MeshStandardMaterial({color:0x203c50,metalness:.28,roughness:.28,emissive:0x07131b,emissiveIntensity:.35});
 const beacon=new THREE.MeshBasicMaterial({color:0xff5c43});
 const plane=new THREE.Group();plane.name='GAMETESTE_TRANSPORT_AIRCRAFT';
 function mesh(geometry,material,position,rotation){
  const m=new THREE.Mesh(geometry,material);
  if(position)m.position.set(...position);
  if(rotation)m.rotation.set(...rotation);
  m.castShadow=false;m.receiveShadow=false;plane.add(m);return m;
 }
 // Aircraft faces local -Z. Smooth tapered body, raised cockpit and rear cargo ramp.
 mesh(new THREE.CylinderGeometry(1.55,1.95,14,10,1),paint,[0,0,0],[Math.PI/2,0,0]);
 mesh(new THREE.ConeGeometry(1.52,4.1,10),paint,[0,0,-8.9],[-Math.PI/2,0,0]);
 mesh(new THREE.ConeGeometry(1.65,3.3,10),paint,[0,.18,8.5],[Math.PI/2,0,0]);
 mesh(new THREE.BoxGeometry(2.5,.65,2.2),glass,[0,.94,-5.6],[-.24,0,0]);
 // Main wings, slight sweep and contrasting leading edge.
 for(const side of [-1,1]){
  const wing=mesh(new THREE.BoxGeometry(11.6,.32,3.45),wingPaint,[side*6,1,.2],[0,side*.13,side*.035]);
  mesh(new THREE.BoxGeometry(4.1,.3,1.55),wingPaint,[side*3.1,.85,7.1],[0,side*.24,0]);
  // Four engines below the wings.
  for(const x of [side*4.1,side*8.0]){
   mesh(new THREE.CylinderGeometry(.55,.64,2.8,10),dark,[x,.15,-1.15],[Math.PI/2,0,0]);
   mesh(new THREE.CylinderGeometry(.38,.38,.12,10),glass,[x,.15,-2.61],[Math.PI/2,0,0]);
  }
  mesh(new THREE.BoxGeometry(.5,1.9,1.7),dark,[side*1.4,2.1,6.8],[0,0,side*.22]);
 }
 mesh(new THREE.BoxGeometry(.42,3.3,4.1),wingPaint,[0,2.35,7]);
 mesh(new THREE.BoxGeometry(2.2,.16,1.3),dark,[0,-1.34,7.1]);
 mesh(new THREE.BoxGeometry(.5,.16,.7),beacon,[0,2.15,-1.9]);
 // Painted cargo stripes improve silhouette without loading textures.
 for(const side of [-1,1])mesh(new THREE.BoxGeometry(.07,.18,4.5),dark,[side*1.58,.28,2.4]);
 scene.add(plane);deployment.plane=plane;plane.visible=false;
 const canopy=new THREE.Group();
 const cloth=new THREE.Mesh(new THREE.SphereGeometry(3.2,20,10,0,Math.PI,0,Math.PI/2),new THREE.MeshStandardMaterial({color:0xf28d47,side:THREE.DoubleSide}));
 cloth.rotation.x=Math.PI;cloth.position.y=3.3;canopy.add(cloth);
 const lineMat=new THREE.LineBasicMaterial({color:0xd8ebef});
 for(const dx of [-2.6,-1.3,0,1.3,2.6]){
  const points=[new THREE.Vector3(dx,3.3,0),new THREE.Vector3(dx*.12,.7,0)];
  canopy.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(points),lineMat));
 }
 player.add(canopy);canopy.visible=false;deployment.chute=canopy;
 const button=document.createElement('button');button.id='deployAction';button.textContent='PULAR DO AVIÃO';
 button.style.cssText='position:fixed;right:24px;bottom:110px;z-index:30;padding:15px 23px;background:#144f79;color:white;border:2px solid #a8e4fa;border-radius:10px;font:900 14px system-ui;cursor:pointer';
 button.addEventListener('click',deploymentAction);document.body.appendChild(button);deployment.button=button;button.hidden=true;
}
function startDeployment(){
 createDeploymentVisuals();deployment.phase='plane';deployment.time=0;deployment.height=95;deployment.flightZ=0;
 deployment.plane.visible=true;deployment.chute.visible=false;deployment.button.hidden=false;deployment.button.textContent='PULAR DO AVIÃO';
 deployment.keys.clear();player.position.set(-90,deployment.height,0);controller.clearInput();controller.cover.exit();controller.velocity.set(0,0,0);
}
function deploymentAction(){
 if(!gameStarted)return;
 if(deployment.phase==='plane'){
  deployment.phase='freefall';deployment.time=0;deployment.plane.visible=false;deployment.button.textContent='ABRIR PARAQUEDAS';
 }else if(deployment.phase==='freefall')deployParachute();
}
function deployParachute(){
 if(deployment.phase!=='freefall')return;
 deployment.phase='glide';deployment.chute.visible=true;deployment.button.hidden=true;
}
function updateDeployment(dt){
 const d=deployment;if(d.phase==='idle'||d.phase==='landed')return false;
 d.time+=dt;
 if(d.phase==='plane'){
  player.position.x=Math.min(90,player.position.x+11*dt);
  player.position.y=d.height;player.position.z=d.flightZ;
  d.plane.position.copy(player.position);d.plane.rotation.y=-Math.PI/2;
  d.plane.rotation.z=Math.sin(d.time*.38)*.018;
  if(player.position.x>=89.5)deploymentAction();
 }else{
  const keys=d.keys;
  const held=(...codes)=>codes.some(code=>keys.has(code));
  const speed=d.phase==='glide'?8:12,down=d.phase==='glide'?8:held('ShiftLeft','ShiftRight')?32:23;
  player.position.x=THREE.MathUtils.clamp(player.position.x+(Number(held('KeyD','ArrowRight'))-Number(held('KeyA','ArrowLeft')))*speed*dt,-120,120);
  player.position.z=THREE.MathUtils.clamp(player.position.z+(Number(held('KeyS','ArrowDown'))-Number(held('KeyW','ArrowUp')))*speed*dt,-120,120);
  const floor=forestEnvironment.getTerrainHeight(player.position.x,player.position.z);
  player.position.y=Math.max(floor,player.position.y-down*dt);
  if(d.phase==='freefall'&&player.position.y-floor<12)deployParachute();
  if(player.position.y<=floor+.05){
   player.position.y=floor;d.phase='landed';d.chute.visible=false;d.button.hidden=true;
   controller.velocity.set(0,0,0);controller.isGrounded=true;d.keys.clear();
  }
 }
 if(d.phase==='plane'){
  camera.position.set(player.position.x-27,player.position.y+13,player.position.z+30);
  camera.lookAt(player.position.x+6,player.position.y,player.position.z);
 }else{
  camera.position.set(player.position.x-15,player.position.y+9,player.position.z+22);
  camera.lookAt(player.position.x,player.position.y-2,player.position.z);
 }
 if(camera.far!==350){camera.far=350;camera.updateProjectionMatrix();}
 return true;
}
addEventListener('keydown',e=>{
 if(!gameStarted||deployment.phase==='idle'||deployment.phase==='landed')return;
 if(['Space','ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.code))e.preventDefault();
 deployment.keys.add(e.code);
 if(e.code==='Space'&&!e.repeat)deploymentAction();
},true);
addEventListener('keyup',e=>deployment.keys.delete(e.code),true);
addEventListener('blur',()=>deployment.keys.clear());

let gameStarted=false;
const menuOverlay=document.getElementById('aventura-menu-overlay');
const menuSettings={soundEnabled:true,sensitivity:1,shadows:true};
const menuViews=['view-main','view-modes','view-multiplayer','view-settings'];
const safeZoneVisual=(()=>{
 const geometry=new THREE.BufferGeometry(),vertices=new Float32Array(128*3);
 geometry.setAttribute('position',new THREE.BufferAttribute(vertices,3));
 const mat=new THREE.LineBasicMaterial({color:0x60d5ff,transparent:true,opacity:.9,depthWrite:false});
 const ring=new THREE.LineLoop(geometry,mat);
 ring.visible=false;ring.frustumCulled=false;ring.userData.ignoreCombat=true;ring.userData.ignoreCamera=true;scene.add(ring);
 const hud=document.createElement('div');hud.id='safeZoneHud';hud.hidden=true;
 hud.style.cssText='position:fixed;top:74px;right:12px;z-index:35;background:#081b27dc;color:#e2faff;border:1px solid #60d5ff;border-radius:8px;padding:8px 12px;font:700 12px system-ui;pointer-events:none';
 document.body.appendChild(hud);
 let zone=null;
 function update(){
  if(!zone)return;
  const outside=Math.hypot(player.position.x-zone.x,player.position.z-zone.z)>zone.radius&&player.position.y<12;
  hud.style.borderColor=outside?'#ff6c77':'#60d5ff';
  hud.textContent=(outside?'FORA DA ZONA! · ':'ZONA SEGURA · ')+'FASE '+zone.phase+' · '+Math.ceil(zone.radius)+'m · '+(zone.stage==='shrinking'?'FECHANDO':'FECHA EM')+' '+zone.seconds+'s';
 }
 function receive(data){
  zone=data;ring.visible=true;hud.hidden=false;
  const p=geometry.attributes.position;
  for(let i=0;i<128;i++){
   const angle=i/128*Math.PI*2,x=data.x+Math.cos(angle)*data.radius,z=data.z+Math.sin(angle)*data.radius;
   p.setXYZ(i,x,forestEnvironment.getTerrainHeight(x,z)+1.7,z);
  }
  p.needsUpdate=true;geometry.computeBoundingSphere();update();
 }
 function clear(){zone=null;ring.visible=false;hud.hidden=true;}
 return {receive,clear,update};
})();
const battleUI={waiting:document.getElementById('battleWaiting'),count:document.getElementById('battleWaitingCount'),result:document.getElementById('battleResult'),queue:document.getElementById('battleQueueStatus'),active:false};
function battleReturn(){safeZoneVisual.clear();battleUI.waiting.hidden=true;battleUI.result.hidden=true;battleUI.active=false;showGameMenu();}
document.getElementById('battleCancel')?.addEventListener('click',battleReturn);
document.getElementById('battleReturn')?.addEventListener('click',battleReturn);
document.getElementById('btn-lobby-arsenal')?.addEventListener('click',()=>window.WeaponArsenal?.open());
function battleEnd(data){
 safeZoneVisual.clear();battleUI.active=false;battleUI.waiting.hidden=true;battleUI.result.hidden=false;
 const won=data.winnerId===multiplayer.id;
 document.getElementById('battleResultTitle').textContent=won?'VITÓRIA ROYALE!':'PARTIDA ENCERRADA';
 document.getElementById('battleResultText').textContent=won?'Você foi o último sobrevivente.':data.winnerName?'Vencedor: '+data.winnerName:'Sem sobreviventes.';
}
function initBattlePreview(){
 const canvas=document.getElementById('battleCharacterPreview');if(!canvas)return;
 let pr;try{pr=new THREE.WebGLRenderer({canvas,alpha:true,antialias:false,powerPreference:'low-power'});}catch{return;}
 pr.setPixelRatio(1);
 const scene2=new THREE.Scene(),cam2=new THREE.PerspectiveCamera(39,1,.1,30);
 scene2.add(new THREE.HemisphereLight(0xc5e7ef,0x35444f,1.7));
 const key=new THREE.DirectionalLight(0xffe3bb,1.4);key.position.set(2,4,5);scene2.add(key);
 // A SkinnedMesh cannot be cloned with Group.clone(true): its skeleton keeps
 // references to the original player's bones, separating boots/armor in preview.
 // Create an independent operator with its own 18-bone skeleton instead.
 let previewAvatar=null,model;
 try{
  previewAvatar=new window.OperatorAvatar({team:'player'});
  previewAvatar.update(0,{armed:false,grounded:true,speed:0});
  model=previewAvatar.group;
 }catch(error){
  console.warn('Independent Soldier preview unavailable:',error);
  model=new THREE.Group();
  const body=new THREE.Mesh(new THREE.BoxGeometry(.9,1.4,.5),new THREE.MeshStandardMaterial({color:0x344653}));
  body.position.y=.9;model.add(body);
  const head=new THREE.Mesh(new THREE.SphereGeometry(.32,12,8),new THREE.MeshStandardMaterial({color:0xc7ac8f}));
  head.position.y=1.8;model.add(head);
 }
 model.position.set(0,-.9,0);scene2.add(model);
 cam2.position.set(0,1.1,5.6);cam2.lookAt(0,.7,0);
 let last=0;
 function draw(t){
  requestAnimationFrame(draw);
  if(t-last<90||!menuOverlay||menuOverlay.classList.contains('hidden-menu')||!battleUI.waiting.hidden||!battleUI.result.hidden)return;
  last=t;const w=canvas.clientWidth||320,h=canvas.clientHeight||300;
  if(canvas.width!==w||canvas.height!==h){pr.setSize(w,h,false);cam2.aspect=w/h;cam2.updateProjectionMatrix();}
  if(previewAvatar)previewAvatar.update(Math.min((t-last+90)/1000,.05),{armed:false,grounded:true,speed:0});
  model.rotation.y+=.012;pr.render(scene2,cam2);
 }
 requestAnimationFrame(draw);
}
initBattlePreview();
function switchMenuView(id){
 menuViews.forEach(v=>document.getElementById(v)?.classList.add('hidden-view'));
 document.getElementById(id)?.classList.remove('hidden-view');
 if(id==='view-multiplayer')publicRoomBrowser.open();else publicRoomBrowser.close();
}
function hideGameMenu(){
 publicRoomBrowser.close();
 menuOverlay?.classList.add('hidden-menu');
 gameStarted=true;
 startDeployment();
 forestAudio.init();
}
function showGameMenu(){
 safeZoneVisual.clear();tacticalGear.unequip();
 if(multiplayer.active||multiplayer.pending)leaveRoom();
 controller.clearInput();pistolWeapon.triggerHeld=false;
 deployment.keys.clear();if(deployment.button)deployment.button.hidden=true;if(deployment.plane)deployment.plane.visible=false;if(deployment.chute)deployment.chute.visible=false;deployment.phase='idle';
 gameStarted=false;
 switchMenuView('view-main');
 menuOverlay?.classList.remove('hidden-menu');
}

const nickname='Operador_'+Math.floor(100+Math.random()*900);
const nameInput=document.getElementById('input-player-name');
if(nameInput)nameInput.value=nickname;
document.getElementById('btn-menu-play')?.addEventListener('click',()=>switchMenuView('view-multiplayer'));
document.getElementById('btn-menu-settings')?.addEventListener('click',()=>switchMenuView('view-settings'));
document.getElementById('btn-menu-exit')?.addEventListener('click',()=>{ try{window.close()}catch(_){} });
document.getElementById('btn-modes-back')?.addEventListener('click',()=>switchMenuView('view-main'));
// Solo mode removed from the Battle Royale lobby.
document.getElementById('btn-mode-multi')?.addEventListener('click',()=>switchMenuView('view-multiplayer'));
document.getElementById('btn-multi-back')?.addEventListener('click',()=>{leaveRoom();switchMenuView('view-modes');});
const multiplayerWorld=new window.MultiplayerWorld(scene,corpseFloorAt,{
 playShoot:(weapon,volume)=>{forestAudio.init();forestAudio.playShoot(weapon,volume);},
 listenerPosition:()=>camera.position
});
let networkTick=0,multiplayerShotSequence=0;
const confirmedNetworkShots=new Set();
function roomStatus(message){
 const status=document.getElementById('multi-status-msg');if(status)status.textContent=message;
 for(const id of ['btn-create-room','btn-join-room']){const button=document.getElementById(id);if(button)button.disabled=multiplayer?.pending||false;}
}
function roomHud(){
 const badge=document.getElementById('room-hud');if(!badge)return;
 badge.hidden=!multiplayer.active;
 const text=document.getElementById('room-hud-text');if(text)text.textContent=multiplayer.room+' · '+(multiplayerWorld.players.size+1)+'/8 jogadores · '+[multiplayer.name,...[...multiplayerWorld.players.values()].map(p=>p.state.name)].join(', ');
}
function setMultiplayerBots(active){for(const bot of combatBots.bots)bot.group.visible=active&&bot.alive;}
const multiplayer=new window.MultiplayerClient({
 onStatus:message=>roomStatus(message),
 onReady:welcome=>{
  tacticalGear.snapshot(welcome.tactical);multiplayerWorld.clear();playerLife.reset();player.userData.dead=false;combatBots.health=100;setMultiplayerBots(false);
  controller.cover.exit();controller.clearInput();controller.velocity.set(0,0,0);controller.isGrounded=true;
  const slot=welcome.players.length;player.position.set(-4+(slot%4)*2.5,0,6+Math.floor(slot/4)*3);
  player.position.y=forestEnvironment.getTerrainHeight(player.position.x,player.position.z);
  for(const state of welcome.players)if(state.id!==welcome.id)multiplayerWorld.receive(state);
  networkTick=1;roomHud();battleUI.waiting.hidden=false;battleUI.result.hidden=true;
  battleUI.count.textContent=Math.min(8,welcome.players.length)+' / 8';
 },
 onDisconnect:wasActive=>{tacticalGear.clear();tacticalGear.resetInventory();multiplayerWorld.clear();setMultiplayerBots(true);roomHud();battleUI.waiting.hidden=true;if(wasActive){showGameMenu();switchMenuView('view-multiplayer');}},
 onMessage:data=>{
  if(data.type==='safezone3d'){safeZoneVisual.receive(data);return;}
  if(data.type==='battle-status'){
   battleUI.queue.textContent=data.phase==='waiting'?'Jogadores '+data.connected+'/8 • Início em '+data.remainingSeconds+'s • vagas restantes serão bots':'Sobreviventes: '+data.alive+' / 8';
   if(data.phase==='waiting'){battleUI.waiting.hidden=false;battleUI.count.textContent=data.connected+' / 8 · '+data.remainingSeconds+'s';}
   return;
  }
  if(data.type==='battle-start'){
   safeZoneVisual.clear();battleUI.active=true;battleUI.waiting.hidden=true;
   for(const state of data.players||[])if(state.id!==multiplayer.id)multiplayerWorld.receive(state);
   hideGameMenu();networkTick=1;sendNetworkState();roomHud();return;
  }
  if(data.type==='battle-end'){battleEnd(data);return;}
  if(['grenade3d','icewall3d','icewall-remove3d','explosion3d','inventory3d'].includes(data.type)){tacticalGear.receive(data);return;}
  if(data.type==='state3d'&&data.id!==multiplayer.id)multiplayerWorld.receive(data);
  else if(data.type==='leave')multiplayerWorld.remove(data.id);
  else if(data.type==='shot3d'&&data.ownerId!==multiplayer.id)multiplayerWorld.shot(data);
  else if(data.type==='hit3d'){
   if(data.targetId===multiplayer.id){combatBots.health=data.health;playerLife.receiveHealth(data.health,data.respawnIn??0);}
   else{const remote=multiplayerWorld.players.get(data.targetId);if(remote)multiplayerWorld.receive({...remote.state,health:data.health,dead:data.killed||false});}
   if(data.attackerId===multiplayer.id){
    if(!confirmedNetworkShots.has(data.shotId)){confirmedNetworkShots.add(data.shotId);if(confirmedNetworkShots.size>128)confirmedNetworkShots.delete(confirmedNetworkShots.values().next().value);hitCount++;score+=12;flashHitmarker();forestAudio.playHit();}
    if(data.killed)score+=100;
   }
  }else if(data.type==='respawn3d'){
   if(data.id===multiplayer.id){player.position.set(data.x,forestEnvironment.getTerrainHeight(data.x,data.z),data.z);controller.velocity.set(0,0,0);controller.clearInput();controller.cover.exit();combatBots.health=100;playerLife.respawn();}
   else{const remote=multiplayerWorld.players.get(data.id);if(remote)multiplayerWorld.receive({...remote.state,...data,dead:false});}
  }
  roomHud();
 }
});
function sendNetworkState(){const active=weaponLoot.slots[weaponLoot.activeSlot];multiplayer.sendState({x:player.position.x,y:player.position.y,z:player.position.z,angle:player.rotation.y,moving:controller.horizontalSpeed>.1,running:controller.keys.sprint&&controller.stamina>0,grounded:controller.isGrounded,crouching:controller.isCrouching,verticalVelocity:controller.velocity.y,aiming:controller.keys.aiming,reload:pistolWeapon.isEquipped&&pistolWeapon.isReloading?pistolWeapon.reloadBlend:0,firing:!!(pistolWeapon.isEquipped&&!pistolWeapon.isReloading&&(pistolWeapon.triggerHeld||pistolWeapon.mechanismShot>.1||pistolWeapon.recoil>.18)),weapon:pistolWeapon.isEquipped?pistolWeapon.weaponSpec.id:'none',soldierSkin:window.GameSkins?.getSoldier()||'original',weaponSkin:window.GameSkins?.getWeapon(pistolWeapon.weaponSpec.id)||'original',attachments:pistolWeapon.isEquipped&&active?{...(active.attachments||{})}:{},gear:tacticalGear.active||'none',jetpack:!!jetpackSystem.equipped,jetpackActive:!!(jetpackSystem.equipped&&controller.keys.jetpack&&jetpackSystem.fuel>0&&!controller.cover.active)});}
function leaveRoom(){tacticalGear.clear();tacticalGear.resetInventory();confirmedNetworkShots.clear();multiplayer.disconnect();multiplayerWorld.clear();setMultiplayerBots(true);playerLife.reset();player.userData.dead=false;combatBots.health=100;roomHud();roomStatus('Você saiu da sala.');}
function enterRoom(action){
 if(multiplayer.pending)return;
 const input=document.getElementById('input-room-code');
 let code=input?.value||'';
 if(action==='create'){const letters='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';code='FLR-';for(let i=0;i<5;i++)code+=letters[Math.floor(Math.random()*letters.length)];if(input)input.value=code;}
 multiplayer.connect(action,code,nameInput?.value||'',document.getElementById('room-visibility')?.value||'public');
}
const publicRoomBrowser=new window.PublicRoomBrowser({
 root:document.getElementById('public-room-list'),status:document.getElementById('public-room-status'),refreshButton:document.getElementById('btn-refresh-rooms'),moreButton:document.getElementById('btn-more-rooms'),
 onJoin:code=>{if(multiplayer.pending)return;const input=document.getElementById('input-room-code');if(input)input.value=code;enterRoom('join');}
});
document.getElementById('btn-create-room')?.addEventListener('click',()=>enterRoom('create'));
document.getElementById('btn-join-room')?.addEventListener('click',()=>enterRoom('join'));
document.getElementById('input-room-code')?.addEventListener('keydown',e=>{if(e.key==='Enter')enterRoom('join');});
document.getElementById('btn-leave-room')?.addEventListener('click',()=>{leaveRoom();showGameMenu();});
document.getElementById('btn-toggle-audio')?.addEventListener('click',e=>{
 menuSettings.soundEnabled=!menuSettings.soundEnabled;
 forestAudio.setEnabled(menuSettings.soundEnabled);
 e.currentTarget.textContent='SOM: '+(menuSettings.soundEnabled?'ATIVADO':'DESATIVADO');
});
document.getElementById('range-sens')?.addEventListener('input',e=>{
 menuSettings.sensitivity=parseFloat(e.target.value);
 document.getElementById('lbl-sens').textContent=menuSettings.sensitivity.toFixed(1);
 thirdPersonCamera.sensitivity=.005*menuSettings.sensitivity;
});
document.getElementById('btn-toggle-shadows')?.addEventListener('click',e=>{
 menuSettings.shadows=!menuSettings.shadows;
 renderer.shadowMap.enabled=menuSettings.shadows;
 e.currentTarget.textContent='SOMBRAS: '+(menuSettings.shadows?'ATIVADAS':'DESATIVADAS');
});
document.getElementById('btn-settings-back')?.addEventListener('click',()=>switchMenuView('view-main'));
addEventListener('keydown',e=>{if(gameStarted&&!player.userData.dead&&e.code==='KeyM')showGameMenu()});

(function initMenuParticles(){
 const c=document.getElementById('menu-particles-canvas'); if(!c)return;
 const ctx=c.getContext('2d'); let w,h;
 const particles=[];
 function resizeP(){w=c.width=innerWidth;h=c.height=innerHeight}
 resizeP(); addEventListener('resize',resizeP);
 for(let i=0;i<45;i++)particles.push({x:Math.random()*innerWidth,y:Math.random()*innerHeight,r:Math.random()*2.2+.8,vx:(Math.random()-.5)*.35,vy:-Math.random()*.4-.1,a:Math.random()*.8+.2,p:Math.random()*Math.PI*2});
 function draw(){
  requestAnimationFrame(draw);
  if(menuOverlay?.classList.contains('hidden-menu'))return;
  ctx.clearRect(0,0,w,h);
  for(const p of particles){
   p.x+=p.vx;p.y+=p.vy;p.p+=.03;
   if(p.y<-10)p.y=h+10;if(p.x<-10)p.x=w+10;if(p.x>w+10)p.x=-10;
   const a=p.a*(.6+.4*Math.sin(p.p));
   ctx.beginPath();ctx.arc(p.x,p.y,p.r,0,Math.PI*2);ctx.fillStyle='rgba(255,223,150,'+a+')';ctx.shadowBlur=10;ctx.shadowColor='#ffd27d';ctx.fill();
  }
 }
 draw();
})();

const clock=new THREE.Clock();
function loop(){
 requestAnimationFrame(loop); const elapsed=clock.getDelta(),dt=Math.min(elapsed,.033);
 if(!gameStarted){ renderer.render(scene,camera);performancePanel.frame(elapsed*1000); return; }
 if(updateDeployment(dt)){
  // Keep the Soldier's rig animated while leaving the aircraft and under the parachute.
  if(deployment.phase==='freefall'||deployment.phase==='glide'){
   mainAvatar.update(dt,{grounded:false,armed:false,aiming:false,speed:0,verticalVelocity:deployment.phase==='glide'?-8:-23});
  }
  if(multiplayer.active){networkTick+=dt;if(networkTick>=.10){networkTick=0;sendNetworkState();multiplayerWorld.update(dt);safeZoneVisual.update();}}
  renderer.render(scene,camera);performancePanel.frame(elapsed*1000);return;
 }
 playerLife.update(elapsed,multiplayer.active);
 if(!playerLife.dead){controller.update(dt);weaponLoot.update(dt);}
 else{controller.clearInput();const floor=corpseFloorAt(player.position.x,player.position.z,player.position.y);corpseFallVelocity-=22*dt;player.position.y=Math.max(floor,player.position.y+corpseFallVelocity*dt);if(player.position.y===floor)corpseFallVelocity=0;}
 player.userData.crouching=controller.isCrouching;
 if(!multiplayer.active&&!window.GametesteTraining?.isActive())combatBots.update(dt);
 tacticalGear.update(elapsed);
 if(multiplayer.active){networkTick+=dt;if(networkTick>=.10){networkTick=0;sendNetworkState();}multiplayerWorld.update(dt);safeZoneVisual.update();}
 playerDamageFlash=Math.max(0,playerDamageFlash-dt);
 playerHitReaction.strength=THREE.MathUtils.lerp(playerHitReaction.strength,0,1-Math.exp(-10*dt));
 playerHitReaction.side=THREE.MathUtils.lerp(playerHitReaction.side,0,1-Math.exp(-7*dt));
 playerHitReaction.front=THREE.MathUtils.lerp(playerHitReaction.front,0,1-Math.exp(-7*dt));
 const damageText=document.getElementById('receivedDamage');if(damageText){damageText.textContent='−'+Math.round(lastReceivedDamage)+' · ATINGIDO';damageText.style.opacity=String(Math.min(1,playerDamageFlash/.35));}
 const lifeFill=document.getElementById('vitalFill');if(lifeFill)lifeFill.style.width=combatBots.health+'%';
 const lifeValue=document.getElementById('vitalValue');if(lifeValue)lifeValue.textContent=combatBots.health+' / 100';
 document.body.classList.toggle('low-health',combatBots.health>0&&combatBots.health<=30);
 const deathOverlay=document.getElementById('deathOverlay');if(deathOverlay)deathOverlay.hidden=!playerLife.dead;
 const deathCountdown=document.getElementById('deathCountdown');if(deathCountdown)deathCountdown.textContent=multiplayer.active?'ELIMINADO · AGUARDE O VENCEDOR':playerLife.remaining>0?'RENASCENDO EM '+Math.ceil(playerLife.remaining)+'s':'RENASCENDO…';
 if(damageFlashEl)damageFlashEl.style.opacity=String(Math.min(.9,playerDamageFlash/.30));
 if(healthEl){healthEl.textContent=String(combatBots.health);healthEl.style.color=combatBots.health<35?'#ff8278':'#7ee8ff';}
 const movingNow=controller.horizontalSpeed>0.01;
 if(mainAvatar instanceof window.OperatorAvatar){
  const footHeights=sampleSoldierFootHeights(dt);
  mainAvatar.update(dt,{footLeft:footHeights.left,footRight:footHeights.right,dead:playerLife.dead,speed:controller.horizontalSpeed,grounded:controller.isGrounded,armed:pistolWeapon.isEquipped||tacticalGear.active==='grenade',aiming:controller.keys.aiming,sprinting:controller.keys.sprint&&controller.stamina>0&&!controller.keys.aiming,verticalVelocity:controller.velocity.y,jumpPreparation:controller.jumpPreparation,jumpForce:controller.jumpForce,gravity:controller.gravity,recoil:pistolWeapon.recoil*.55,firing:!!(pistolWeapon.isEquipped&&!pistolWeapon.isReloading&&(pistolWeapon.triggerHeld||pistolWeapon.mechanismShot>.1||pistolWeapon.recoil>.18)),crouching:controller.isCrouching,covering:controller.cover.active&&!controller.cover.isPeeking,coverSide:controller.cover.side,strafe:controller.strafeAmount,forward:controller.forwardAmount,braking:controller.braking,turn:controller.turnAmount,turnSharpness:controller.turnSharpness,aimTransition:controller.aimTransition,stepBlend:controller.stepBlend,landingImpact:controller.landingImpact,hardLanding:controller.hardLanding,recovery:controller.recoveryTimer>0?controller.recoveryStrength:0,reload:pistolWeapon.reloadBlend,equip:pistolWeapon.equipBlend,hitStrength:playerHitReaction.strength,hitSide:playerHitReaction.side,hitFront:playerHitReaction.front});
 }else if(useHumanCharacter&&humanCharacter.model){
  humanCharacter.updateLocomotion(controller.horizontalSpeed,controller.isGrounded);

  // Player root follows camera aim; preserve the Soldier's local forward correction.
  const humanForwardOffset=humanCharacter.model.userData.forwardYawOffset||0;
  humanCharacter.model.rotation.y=THREE.MathUtils.lerp(
   humanCharacter.model.rotation.y,
   humanForwardOffset,
   1-Math.exp(-10*dt)
  );

  const aimPoint=camera.position.clone().add(
   camera.getWorldDirection(new THREE.Vector3()).multiplyScalar(20)
  );
  humanCharacter.lookAtTarget(aimPoint);
  humanCharacter.update(dt);
  humanCharacter.updateJumpPose(dt,controller.velocity.y,controller.isGrounded);
 }else{
  combatAnimator.update(dt,{
  moving:movingNow,
  sprinting:controller.keys.sprint&&controller.stamina>0,
  grounded:controller.isGrounded,
  speed:controller.horizontalSpeed,
  moveX:0,
  moveZ:0
  });
 }
 weaponLoot.updateHeldPose();
 pistolWeapon.update(dt,movingNow);
 if(tacticalGear.active==='grenade')mainAvatar.gun.visible=false;
 const grenadeCount=document.getElementById('grenadeCount');if(grenadeCount)grenadeCount.textContent=tacticalGear.inventory.grenades+' un';
 document.getElementById('grenadeSlotBtn')?.setAttribute('aria-pressed',String(tacticalGear.active==='grenade'));
 const iceCount=document.getElementById('iceCount');if(iceCount)iceCount.textContent=String(tacticalGear.inventory.ice);
 const throwButton=document.getElementById('grenadeThrowBtn');if(throwButton)throwButton.hidden=tacticalGear.active!=='grenade'||playerLife.dead;
 tacticalNoticeTime=Math.max(0,tacticalNoticeTime-dt);if(!tacticalNoticeTime){const notice=document.getElementById('tacticalNotice');if(notice)notice.hidden=true;}
 updateAdsViewModel(dt);
 updateCamera(dt);
 const moving=controller.horizontalSpeed>0.01;
 if(moving&&controller.isGrounded)forestAudio.playFootstep();
 const stateLabel=playerLife.dead?'Caído · renascendo':controller.climb?'Escalando':controller.cover.active?(controller.cover.isPeeking?'Exposto':'Em cobertura'):!controller.isGrounded?'Pulando':controller.isCrouching?(moving?'Andando agachado':'Agachado'):moving?((controller.keys.sprint&&controller.stamina>0)?'Correndo':'Andando'):'Parado';
 const coverPrompt=document.getElementById('coverPrompt');
 if(coverPrompt){
  const near=controller.cover.active?null:controller.cover.findNearby();
  coverPrompt.hidden=!controller.cover.active&&!near;
  coverPrompt.textContent=controller.cover.active?(controller.cover.isPeeking?'Exposto · solte a mira para se proteger':controller.cover.low?'Cobertura baixa · botão direito para mirar · Q sair':'Cobertura · A/D até a quina · botão direito para mirar · Q sair'):'Q · entrar em cobertura';
 }
 const lootPrompt=document.getElementById('lootPrompt');
 const lootText=document.getElementById('lootPromptText');
 if(lootPrompt){lootPrompt.hidden=!weaponLoot.prompt;if(lootText&&lootText.textContent!==weaponLoot.prompt)lootText.textContent=weaponLoot.prompt;}
 const pickupButton=document.getElementById('pickupBtn');if(pickupButton)pickupButton.hidden=!weaponLoot.nearest;
 const shortNames={pistol:'Pistola',smg:'SMG',rifle:'Rifle',shotgun:'Escopeta',sniper:'Sniper'};
 for(let slot=0;slot<2;slot++){
  const item=weaponLoot.slots[slot],button=document.getElementById('weaponSlot'+slot),label=document.getElementById('weaponName'+slot),ammo=document.getElementById('weaponAmmo'+slot);
  if(label)label.textContent=item?shortNames[item.id]:'Vazio';
  if(ammo)ammo.textContent=item?(slot===weaponLoot.activeSlot&&pistolWeapon.isReloading?'Recarregando…':item.ammo+' / '+weaponLoot.reserves[window.WeaponLootSystem.DEFINITIONS[item.id].ammoType]):'—';
  button?.setAttribute('aria-pressed',String(slot===weaponLoot.activeSlot&&pistolWeapon.isEquipped));
 }
 const coverButton=document.getElementById('coverBtn');
 if(coverButton){coverButton.textContent=controller.cover.active?'SAIR':'COVER';coverButton.setAttribute('aria-pressed',String(controller.cover.active));}
 if(scoreEl)scoreEl.textContent=String(score);
 if(hitsEl)hitsEl.textContent=hitCount+' / '+shots;
 if(playerStateEl)playerStateEl.textContent=stateLabel;
 if(speedEl)speedEl.textContent=controller.horizontalSpeed.toFixed(1)+' m/s';
 if(staminaBarEl)staminaBarEl.style.width=(controller.stamina/controller.maxStamina*100).toFixed(0)+'%';
 if(altitudeEl)altitudeEl.textContent=player.position.y.toFixed(1)+' m';
 stateEl.textContent=(controller.isGrounded?'CHÃO':'AR')+' • '+controller.horizontalSpeed.toFixed(1)+' m/s • Y '+player.position.y.toFixed(1)+' m';
 renderer.render(scene,camera);performancePanel.frame(elapsed*1000);
}
loop();

