const{test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
test('damage feedback, single death, and five-second respawn',()=>{
 assert.ok(fs.existsSync('public/player-life.js'),'death lifecycle must exist');const events=[],c={window:{}};vm.createContext(c);vm.runInContext(fs.readFileSync('public/player-life.js','utf8'),c);
 const life=new c.window.PlayerLife({onDamage:d=>events.push(['hit',d]),onDeath:()=>events.push(['dead']),onRespawn:()=>events.push(['respawn'])});
 life.receiveHealth(70);assert.equal(events[0][1],30);life.receiveHealth(0);assert(life.dead);life.receiveHealth(0);assert.equal(events.filter(e=>e[0]==='dead').length,1);
 life.update(4.99);assert(life.dead);assert.equal(life.health,0);assert.equal(events.filter(e=>e[0]==='respawn').length,0);life.update(.011);assert(!life.dead);assert.equal(life.health,100);
 life.receiveHealth(0);life.update(6,true);assert(life.dead,'online respawn must wait for server');life.respawn();assert(!life.dead);
});
