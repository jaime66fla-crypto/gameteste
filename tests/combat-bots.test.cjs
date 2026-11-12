const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const THREE=require('../public/vendor/three-r128.min.js');const context={THREE,window:{}};
assert(fs.existsSync('public/combat-bots.js'),'Combat bot system must exist');
vm.createContext(context);for(const path of ['public/operator-avatar.js','public/combat-bots.js'])vm.runInContext(fs.readFileSync(path,'utf8'),context);
const scene=new THREE.Scene(),player=new THREE.Group();const avatar=new context.window.OperatorAvatar();player.add(avatar.group);scene.add(player);let kills=0,deaths=0;
const system=new context.window.CombatBotSystem({scene,player,terrainHeight:()=>0,random:()=>0,onKill:()=>kills++,onPlayerDeath:()=>deaths++});
assert.equal(system.bots.length,3);assert(system.bots.every(b=>b.avatar.materials.fabric.color.r>b.avatar.materials.fabric.color.g));assert(avatar.materials.fabric.color.g>avatar.materials.fabric.color.r,'Bot tint must not affect the player');
const bot=system.bots[0],start=bot.group.position.clone();for(let i=0;i<60;i++)system.update(1/60);assert(bot.group.position.distanceTo(start)>.1);
bot.takeDamage(30);assert.equal(bot.health,60);bot.takeDamage(60);assert(!bot.alive);assert(!bot.group.visible);bot.takeDamage(90);assert.equal(kills,1);
for(let i=0;i<370;i++)system.update(1/60);assert(bot.alive&&bot.group.visible&&bot.health===90);
// Walls must block bot fire, and dead bots must not absorb player shots.
for(const b of system.bots){b.group.position.set(0,0,-8);b.cooldown=0;}
player.position.set(0,0,0);const wall=new THREE.Mesh(new THREE.BoxGeometry(30,5,.4),new THREE.MeshBasicMaterial());wall.position.set(0,2,-4);scene.add(wall);system.health=100;
for(let i=0;i<180;i++)system.update(1/60);assert.equal(system.health,100,'Bot fire must not pass through cover');
scene.remove(wall);for(let i=0;i<300;i++)system.update(1/60);assert(system.health<100||deaths>0,'Visible bots must be able to damage the player');
system.damagePlayer(1000);assert.equal(system.health,100);assert(deaths>0);
for(const b of system.bots)b.takeDamage(1000);scene.updateMatrixWorld(true);const ray=new THREE.Raycaster(new THREE.Vector3(0,1,-2),new THREE.Vector3(0,0,-1));assert.equal(context.window.CombatBotSystem.firstHit(scene,ray,player),null);
console.log('Combat bots: red palette, movement, damage/death/respawn, cover, return fire and player recovery pass');
// First-person rendering hides the avatar but must not make the player invulnerable.
avatar.group.userData.combatHitWhenHidden=true;avatar.group.visible=false;
const firstPersonBot=system.bots[0];firstPersonBot.alive=true;firstPersonBot.group.visible=true;firstPersonBot.group.position.set(0,0,-8);system.health=100;system.shoot(firstPersonBot);assert(system.health<100,'First-person camera must not disable player damage');
console.log('First-person player hit detection passes');
