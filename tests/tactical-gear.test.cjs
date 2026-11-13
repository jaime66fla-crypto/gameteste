const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm'),THREE=require('../public/vendor/three-r128.min.js');
function setup(online=false){assert(fs.existsSync('public/tactical-gear.js'),'tactical equipment module must exist');const c={THREE,window:{},Date,Math};vm.createContext(c);for(const p of ['tactical-rules.js','tactical-gear.js'])vm.runInContext(fs.readFileSync('public/'+p,'utf8'),c);const scene=new THREE.Scene(),player=new THREE.Group(),camera=new THREE.PerspectiveCamera(),hand=new THREE.Group(),boxes=[],damage=[],sent=[];player.add(hand);scene.add(player);camera.lookAt(0,0,-1);const gear=new c.window.TacticalGear({scene,player,camera,hand,boxes:()=>boxes,terrainHeight:()=>0,canAct:()=>!player.userData.dead,online:()=>online,send:d=>sent.push(d),targets:()=>[{id:'self',position:player.position,damage:d=>damage.push(d)}]});return {c,scene,player,camera,gear,boxes,damage,sent};}
test('equipped grenade uses charges once, prepared throw cancels on death, ice blocks and cleans up',()=>{
 const s=setup();assert(s.gear.equipGrenade());assert.equal(s.gear.active,'grenade');assert(s.gear.beginThrow());assert(s.gear.endThrow());assert.equal(s.gear.inventory.grenades,2);assert.equal(s.gear.grenades.size,1);assert(!s.gear.endThrow(),'Release cannot duplicate grenade');
 s.gear.beginThrow();s.player.userData.dead=true;assert(!s.gear.endThrow());assert.equal(s.gear.inventory.grenades,2);s.player.userData.dead=false;
 s.gear.cooldown=0;assert(s.gear.deployIce());assert.equal(s.gear.inventory.ice,2);assert.equal(s.boxes.length,5);const wall=[...s.gear.walls.values()][0];
 s.gear.cooldown=0;assert(!s.gear.deployIce());assert.equal(s.gear.inventory.ice,2,'Invalid ice does not consume a charge');s.gear.damageWall(wall.state.id,260);assert.equal(s.boxes.length,0);assert.equal(s.gear.walls.size,0);
 s.gear.clear();assert.equal(s.gear.grenades.size,0);assert.equal(s.gear.active,null);assert(!s.gear.preparing);
});
test('online equipment waits for authoritative events and does not apply local damage',()=>{
 const s=setup(true);s.gear.equipGrenade();s.gear.beginThrow();s.gear.endThrow();assert.equal(s.sent[0].type,'gear3d');assert.equal(s.sent[0].kind,'grenade');assert.equal(s.gear.grenades.size,0);assert.equal(s.gear.inventory.grenades,3);
 s.gear.receive({type:'inventory3d',grenades:2,ice:3});assert.equal(s.gear.inventory.grenades,2);
 const g=s.c.TacticalRules.grenade('net','peer',{x:0,y:0,z:0},{x:0,y:0,z:-1},Date.now());s.gear.receive({type:'grenade3d',grenade:g});s.gear.update(3);assert.equal(s.damage.length,0);s.gear.receive({type:'explosion3d',id:'net',position:g.position});assert.equal(s.gear.grenades.size,0);
});
