/* Shared local/online player lifecycle. Online resurrection is server-authorized. */
(()=>{'use strict';
class PlayerLife{
 constructor({onDamage=()=>{},onDeath=()=>{},onRespawn=()=>{}}={}){Object.assign(this,{onDamage,onDeath,onRespawn});this.health=100;this.dead=false;this.remaining=0;}
 receiveHealth(value,respawnIn=5){
  if(!Number.isFinite(value))return;
  const next=Math.max(0,Math.min(100,value)),damage=this.health-next;
  if(this.dead)return;
  this.health=next;if(damage>0)this.onDamage(damage);
  if(next===0)this.die(respawnIn);
 }
 die(seconds=5){if(this.dead)return;this.dead=true;this.health=0;this.remaining=seconds;this.onDeath();}
 update(dt,online=false){if(!this.dead)return;this.remaining=Math.max(0,this.remaining-Math.max(0,dt));if(this.remaining===0&&!online)this.respawn();}
 respawn(){this.dead=false;this.health=100;this.remaining=0;this.onRespawn();}
 reset(){this.dead=false;this.health=100;this.remaining=0;}
}
window.PlayerLife=PlayerLife;
})();
