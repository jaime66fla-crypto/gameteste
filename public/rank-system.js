/* Gameteste - persistent local XP and rank progression (cosmetic only). */
(()=>{
 'use strict';
 const KEY='gameteste-rank-xp-v1';
 const RANKS=[
  ['Recruta',0],['Soldado',200],['Cabo',500],['Sargento',1000],
  ['Subtenente',1800],['Tenente',2900],['Capitão',4300],
  ['Major',6200],['Coronel',8700],['General',12000],
  ['Elite',16500],['Lenda',22500]
 ];
 const REWARD={hit:5,kill:100,victory:250};
 let xp=0,kills=0;try{const saved=JSON.parse(localStorage.getItem(KEY)||'{}');xp=Math.max(0,Math.min(1e8,Math.floor(Number(saved.xp)||0)));kills=Math.max(0,Math.floor(Number(saved.kills)||0));}catch(_){}
 let current=RANKS.reduce((n,rank,i)=>xp>=rank[1]?i:n,0);
 function save(){try{localStorage.setItem(KEY,JSON.stringify({xp,kills}))}catch(_){}}
 function getState(){
  const rank=RANKS[current],next=RANKS[current+1];
  return {xp,kills,rank:rank[0],rankIndex:current+1,totalRanks:RANKS.length,
   nextRank:next?.[0]||null,nextAt:next?.[1]||null,
   progress:next?Math.min(1,(xp-rank[1])/(next[1]-rank[1])):1};
 }
 const style=document.createElement('style');
 style.textContent='#rankHud{position:fixed;top:14px;left:14px;z-index:12;background:#0a1822e8;border:1px solid #5c8598;border-radius:9px;padding:9px 12px;width:185px;color:#e8f8ff;font:700 12px system-ui;pointer-events:none}#rankHud strong{font-size:13px}#rankTrack{height:5px;background:#294552;border-radius:5px;margin:8px 0 4px;overflow:hidden}#rankFill{height:100%;width:0;background:#77e3fa;transition:width .4s}#rankHud small{color:#b4d6e3}#rankToast{position:fixed;z-index:20010;top:13%;left:50%;transform:translateX(-50%);background:#102b3af5;color:#fff;padding:15px 22px;border:1px solid #b4ebff;border-radius:12px;font:800 17px system-ui;text-align:center;pointer-events:none}#rankToast[hidden]{display:none}@media(max-width:680px){#rankHud{top:8px;left:8px;width:128px;font-size:10px;padding:6px}#rankHud strong{font-size:11px}#rankToast{font-size:13px;width:70%}}';
 document.head.append(style);
 const hud=document.createElement('div');hud.id='rankHud';hud.setAttribute('aria-label','Patente e experiência');
 hud.innerHTML='<strong id="rankName"></strong><div id="rankTrack"><div id="rankFill"></div></div><small id="rankNumbers"></small>';
 document.body.append(hud);
 const toast=document.createElement('div');toast.id='rankToast';toast.hidden=true;document.body.append(toast);
 let toastUntil=0;
 function update(){
  const state=getState();
  hud.querySelector('#rankName').textContent=state.rank+' · '+state.rankIndex+'/'+state.totalRanks;
  hud.querySelector('#rankFill').style.width=(state.progress*100).toFixed(1)+'%';
  hud.querySelector('#rankNumbers').textContent=state.nextAt===null?state.xp.toLocaleString('pt-BR')+' XP · PATENTE MÁXIMA':state.xp.toLocaleString('pt-BR')+' / '+state.nextAt.toLocaleString('pt-BR')+' XP';
 }
 function award(kind){
  if(!Object.hasOwn(REWARD,kind))return false;
  const amount=REWARD[kind];xp+=amount;if(kind==='kill')kills++;
  const before=current;
  while(current<RANKS.length-1&&xp>=RANKS[current+1][1])current++;
  save();update();
  if(current>before){
   toast.textContent='NOVA PATENTE: '+RANKS[current][0].toUpperCase()+'!';
   toast.hidden=false;toastUntil=Date.now()+3800;
  }
  window.dispatchEvent(new CustomEvent('gameteste-rank-change',{detail:{...getState(),reward:kind,amount}}));
  return true;
 }
 function tick(){if(toastUntil&&Date.now()>toastUntil){toast.hidden=true;toastUntil=0}}
 update();window.GameRanks={award,getState,tick,RANKS: RANKS.map(([name,minXp])=>({name,minXp}))};
})();
