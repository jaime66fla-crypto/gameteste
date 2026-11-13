const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
function rules(){assert(fs.existsSync('public/tactical-rules.js'),'shared tactical rules must exist');const c={};vm.createContext(c);vm.runInContext(fs.readFileSync('public/tactical-rules.js','utf8'),c);return c.TacticalRules;}
test('grenades follow a bounded ballistic arc, bounce off walls/floor and detonate once fuse expires',()=>{
 const R=rules(),g=R.grenade('one','owner',{x:0,y:0,z:0},{x:0,y:0,z:-1},0);const box={minX:-2,maxX:2,minY:0,maxY:3,minZ:-4,maxZ:-3.5};let minZ=0;
 for(let i=0;i<140;i++){R.advance(g,.02,[box]);minZ=Math.min(minZ,g.position.z);assert(g.position.y>=.119);}
 assert(minZ>-3.5,'A swept projectile must not tunnel through the blocking wall');assert(g.age>=2.799);assert(g.position.z>-3.5);assert(R.expired(g));
});
test('blast damage falls with distance and is stopped by real cover',()=>{
 const R=rules(),origin={x:0,y:1,z:0};assert(R.blastDamage(origin,{x:0,y:0,z:1},[])>80);assert.equal(R.blastDamage(origin,{x:0,y:0,z:9},[]),0);
 assert.equal(R.blastDamage(origin,{x:0,y:0,z:3},[{minX:-2,maxX:2,minY:0,maxY:3,minZ:1,maxZ:1.5}]),0);
});
test('instant ice is placed perpendicular to heading, rejects overlap and shields targets',()=>{
 const R=rules(),p={x:0,y:0,z:0},wall=R.iceWall('ice','owner',p,{x:0,y:0,z:-1},0,[],[]);assert(wall);assert.equal(wall.boxes.length,5);assert.equal(wall.health,260);assert.equal(wall.position.z,-3);
 assert.equal(R.blastDamage({x:0,y:1,z:-5},p,wall.boxes),0);assert.equal(R.iceWall('blocked','owner',p,{x:0,y:0,z:-1},0,wall.boxes,[]),null);
 assert.equal(R.iceWall('person','owner',p,{x:0,y:0,z:-1},0,[],[{x:0,y:0,z:-3}]),null);
 const side=R.iceWall('side','owner',p,{x:1,y:0,z:0},0,[],[]);assert(side);assert.equal(side.position.x,3);assert.equal(side.position.z,0);
});
test('a grenade leaves a raised platform after a real bounce instead of sticking at the contact',()=>{
 const R=rules(),g=R.grenade('roof','owner',{x:0,y:3,z:0},{x:0,y:-1,z:0},0),platform={minX:-3,maxX:3,minY:0,maxY:1,minZ:-3,maxZ:3};let touched=false,bounced=false;
 for(let i=0;i<200;i++){R.advance(g,.01,[platform]);if(g.position.y<1.14)touched=true;if(touched&&g.position.y>1.3)bounced=true;}
 assert(touched);assert(bounced,'Contact must allow the reflected projectile to leave the surface');
});
