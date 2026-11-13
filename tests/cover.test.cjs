const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const THREE=require('../public/vendor/three-r128.min.js'),context={THREE,window:{}};
assert(fs.existsSync('public/cover-controller.js'),'Cover controller must exist');
vm.runInNewContext(fs.readFileSync('public/cover-controller.js','utf8'),context);
const Cover=context.window.CoverController;
const wall={minX:-3,maxX:3,minY:0,maxY:3,minZ:-.5,maxZ:.5};
function setup(position,boxes=[wall]){const player=new THREE.Group();player.position.set(...position);const c=new Cover({player,boxes:()=>boxes,terrainHeight:()=>0});return {c,player,boxes};}
const step=(c,input={},n=60)=>{for(let i=0;i<n;i++)c.update(1/60,{grounded:true,canStand:true,...input});};
for(const p of [[0,0,1.2],[0,0,-1.2],[3.7,0,0],[-3.7,0,0]]){const w={...wall,minZ:-2,maxZ:2};const {c,player}=setup(p[2]===0?p:[0,0,Math.sign(p[2])*2.7],[w]);assert(c.toggle());assert(c.active);step(c);assert(c.surface.normal.dot(player.position.clone().sub(new THREE.Vector3(0,0,0)))>0);}
assert(!setup([0,0,5]).c.toggle(),'Far walls must not capture the player');
const {c,player}=setup([0,0,1.15]);assert(c.toggle());step(c,{aiming:true});assert(!c.isPeeking&&!c.canShoot,'Aiming from middle of tall wall must not shoot through it');
step(c,{right:true},240);assert(player.position.x<=wall.maxX-.45+.001,'Sliding must stop before the corner');
step(c,{aiming:true});assert(c.isPeeking&&c.canShoot);assert(player.position.x>wall.maxX+.4,'Peeking must move the actual body beyond the corner');
const opponent=new THREE.Vector3(0,1.1,-8),body=player.position.clone().add(new THREE.Vector3(0,1.1,0));const toward=body.clone().sub(opponent);const crossing=new THREE.Ray(opponent,toward.clone().normalize()).intersectBox(new THREE.Box3(new THREE.Vector3(-3,0,-.5),new THREE.Vector3(3,3,.5)),new THREE.Vector3());assert(!crossing||crossing.distanceTo(opponent)>toward.length(),'Peeking must expose a real line of fire around a thick wall');
step(c);assert(!c.isPeeking&&!c.canShoot);assert(player.position.x<wall.maxX-.4,'Release must retract behind the same wall');
assert(c.toggle());assert(!c.active);assert(c.canShoot);
const low={...wall,maxY:1.3};const l=setup([0,0,1.2],[low]);assert(l.c.toggle());assert(l.c.low);step(l.c,{aiming:true});assert(l.c.isPeeking,'Low cover must expose above the top');step(l.c,{aiming:true,canStand:false});assert(!l.c.isPeeking,'Overhead obstacle must prevent standing peek');
const blocked=setup([2.5,0,1.2],[wall,{minX:3.01,maxX:5,minY:0,maxY:3,minZ:.51,maxZ:2}]);assert(blocked.c.toggle());step(blocked.c,{aiming:true});assert(!blocked.c.isPeeking,'Adjacent obstacles must block corner exposure');
const away=setup([0,0,1.2]);away.c.toggle();step(away.c,{backward:true},1);assert(!away.c.active);const air=setup([0,0,1.2]);air.c.toggle();step(air.c,{grounded:false},1);assert(!air.c.active);
console.log('Cover geometry/state: acquisition, wall sides, distance, slide bounds, blocked/low/corner peeks, physical exposure, retraction and exits pass');
// Verify that exposure also changes real mesh hit detection against the same wall.
for(const file of ['public/operator-motion.js','public/operator-avatar.js','public/combat-bots.js'])vm.runInNewContext(fs.readFileSync(file,'utf8'),context);
const arena=new THREE.Scene(),bodyRoot=new THREE.Group(),operator=new context.window.OperatorAvatar();bodyRoot.add(operator.group);arena.add(bodyRoot);
const wallMesh=new THREE.Mesh(new THREE.BoxGeometry(6,3,1),new THREE.MeshBasicMaterial());wallMesh.position.y=1.5;arena.add(wallMesh);
const cover=new Cover({player:bodyRoot,boxes:()=>[wall],terrainHeight:()=>0});bodyRoot.position.set(2.5,0,1.2);cover.toggle();
function enemyHit(){arena.updateMatrixWorld(true);const from=new THREE.Vector3(0,1.1,-8),to=bodyRoot.position.clone().add(new THREE.Vector3(0,1.1,0));return context.window.CombatBotSystem.firstHit(arena,new THREE.Raycaster(from,to.sub(from).normalize()),null);}
assert.equal(enemyHit().object,wallMesh,'Wall must protect the actual covered body');
step(cover,{aiming:true});bodyRoot.rotation.y=Math.PI;operator.update(1/60,{armed:true});assert.notEqual(enemyHit().object,wallMesh,'Peeking must expose actual avatar geometry');
step(cover);assert.equal(enemyHit().object,wallMesh,'Retracting must restore physical protection');
console.log('Cover damage geometry: protected, exposed and retracted hit detection pass');

const lowShot=setup([0,0,1.2],[{...wall,maxY:1.3}]);lowShot.c.toggle();step(lowShot.c,{aiming:true});assert(!lowShot.c.canFireFrom(new THREE.Vector3(0,1,0)),'Muzzle inside a barrier must never fire through backfaces');assert(lowShot.c.canFireFrom(new THREE.Vector3(0,1.45,0)));
const highBarrier=setup([0,0,1.2],[{...wall,maxY:1.6}]);highBarrier.c.toggle();assert(!highBarrier.c.low,'Barriers above standing muzzle height require a corner peek');step(highBarrier.c,{aiming:true});assert(!highBarrier.c.canShoot);
console.log('Cover weapon clearance: interior muzzle and overly tall low covers are blocked');
