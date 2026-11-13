/* Gameteste - persistent local XP and rank progression (cosmetic only). */
(()=>{
 'use strict';
 const KEY='gameteste-rank-xp-v1';
 const RANKS=[
  ['Recruta',0],['Soldado',200],['Cabo',500],['Sargento',1000],
  ['Tenente',2900],['Capitão',4300],['Major',6200],['Mestre',12000]
 ];
 const RANK_IDS=['recruta','soldado','cabo','sargento','tenente','capitao','major','mestre'];
 const badgeMarkup=i=>'<span class="rank-insignia rank-insignia-'+RANK_IDS[i]+'" style="background-position:'+((i/7)*100).toFixed(4)+'% center" aria-hidden="true"></span>';

 const REWARD={hit:5,kill:100,victory:250};
 let xp=0,kills=0;try{const saved=JSON.parse(localStorage.getItem(KEY)||'{}');xp=Math.max(0,Math.min(1e8,Math.floor(Number(saved.xp)||0)));kills=Math.max(0,Math.floor(Number(saved.kills)||0));}catch(_){}
 // A one-time, browser-local promotion link for the game owner's profile.
 // Never promote other visitors just because the patch was published.
 let masterActivated=false;
 try{
  const uri=new URL(location.href);
  if(uri.searchParams.get('patente')==='mestre'){
   xp=Math.max(xp,RANKS[RANKS.length-1][1]);masterActivated=true;
   uri.searchParams.delete('patente');
   history.replaceState(null,'',uri.pathname+uri.search+uri.hash);
  }
 }catch(_){}
 let current=RANKS.reduce((n,rank,i)=>xp>=rank[1]?i:n,0);
 function save(){try{localStorage.setItem(KEY,JSON.stringify({xp,kills}))}catch(_){}}
 if(masterActivated)save();
 function getState(){
  const rank=RANKS[current],next=RANKS[current+1];
  return {xp,kills,rank:rank[0],rankId:RANK_IDS[current],rankIndex:current+1,totalRanks:RANKS.length,
   nextRank:next?.[0]||null,nextAt:next?.[1]||null,
   progress:next?Math.min(1,(xp-rank[1])/(next[1]-rank[1])):1};
 }
 const style=document.createElement('style');
 style.textContent='#rankHud{position:fixed;top:178px;left:10px;z-index:12;background:#0a1822e8;border:1px solid #5c8598;border-radius:9px;padding:9px 12px;width:185px;color:#e8f8ff;font:700 12px system-ui;pointer-events:none}#rankHud strong{font-size:13px}#rankTrack{height:5px;background:#294552;border-radius:5px;margin:8px 0 4px;overflow:hidden}#rankFill{height:100%;width:0;background:#77e3fa;transition:width .4s}#rankHud small{color:#b4d6e3}#rankToast{position:fixed;z-index:20010;top:13%;left:50%;transform:translateX(-50%);background:#102b3af5;color:#fff;padding:15px 22px;border:1px solid #b4ebff;border-radius:12px;font:800 17px system-ui;text-align:center;pointer-events:none}#rankToast[hidden]{display:none}@media(max-width:680px){#rankHud{top:150px;left:8px;width:142px;font-size:10px;padding:6px}#rankHud strong{font-size:11px}#rankToast{font-size:13px;width:70%}}';
 style.textContent+='\n.rank-insignia{display:inline-block;flex-shrink:0;width:52px;height:58px;background-image:url("/rank-badges.svg?v=1");background-repeat:no-repeat;background-size:800% 100%;filter:drop-shadow(0 2px 6px #0008);vertical-align:middle}.rank-emblem-line{display:flex;align-items:center;gap:9px}.rank-emblem-line .rank-insignia{width:58px;height:64px}.rank-insignia-mestre{filter:drop-shadow(0 0 7px #ffc34f99)}#rankHud .rank-insignia{width:44px;height:48px}#rankHud{width:205px}#rankName{display:block}#rank-gallery{margin-top:8px;border:1px solid #b6935266;border-radius:10px;padding:8px;background:#0c1728e8;color:#f7e4b2;font:650 11px system-ui}#rank-gallery summary{cursor:pointer;list-style:none}#rank-gallery summary::before{content:"✦ ";color:#f8c86d}.rank-gallery-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin-top:10px}.rank-gallery-entry{display:flex;flex-direction:column;align-items:center;gap:3px;padding:6px 2px;border:1px solid #7b8b9c4d;border-radius:8px;background:#111c2dd0;color:#e9edf1;font:750 9px system-ui;text-align:center}.rank-gallery-entry.is-current{border-color:#ffcf62;box-shadow:0 0 14px #c48a3047}.rank-gallery-entry .rank-insignia{width:47px;height:53px}@media(max-width:680px){#rankHud{width:160px}#rankHud .rank-insignia{width:34px;height:38px}.rank-gallery-grid{grid-template-columns:repeat(4,minmax(0,1fr))}.rank-gallery-entry{font-size:8px}.rank-gallery-entry .rank-insignia{width:35px;height:39px}}';
 // Compact popover aligned to the right of the lobby header instead of full-width row.
 style.textContent+='\n#aventura-menu-overlay #rank-gallery{position:relative;flex:0 0 auto;margin-left:auto;width:190px;padding:5px 9px;border-color:#d9ab5b77;z-index:25}#aventura-menu-overlay #rank-gallery summary{text-align:center;white-space:nowrap;font-size:10px;letter-spacing:.035em;line-height:20px}#aventura-menu-overlay #rank-gallery[open]{z-index:150}#aventura-menu-overlay #rank-gallery .rank-gallery-grid{position:absolute;right:0;top:calc(100% + 8px);width:350px;max-width:min(94vw,350px);padding:12px;background:#101d32f5;border:1px solid #d1a65388;border-radius:12px;box-shadow:0 20px 38px #000b;grid-template-columns:repeat(4,minmax(0,1fr))}@media(max-width:680px){#aventura-menu-overlay .battle-lobby-header{flex-wrap:wrap}#aventura-menu-overlay #rank-gallery{width:155px;padding:4px 7px}#aventura-menu-overlay #rank-gallery summary{font-size:9px}#aventura-menu-overlay #rank-gallery .rank-gallery-grid{width:310px;max-width:calc(100vw - 30px)}}';
 document.head.append(style);
 const hud=document.createElement('div');hud.id='rankHud';hud.setAttribute('aria-label','Patente e experiência');
 hud.innerHTML='<div class="rank-emblem-line"><span id="rankHudBadge"></span><strong id="rankName"></strong></div><div id="rankTrack"><div id="rankFill"></div></div><small id="rankNumbers"></small>';
 document.body.append(hud);
 const toast=document.createElement('div');toast.id='rankToast';toast.hidden=true;document.body.append(toast);
 const lobbyRank=document.getElementById('battleLobbyRank');
 const lobbyCard=lobbyRank?.closest('.battle-rank-card');
 if(lobbyRank){
  const badge=document.createElement('span');badge.id='rankLobbyBadge';
  const row=document.createElement('div');row.className='rank-emblem-line';
  lobbyRank.before(row);row.append(badge,lobbyRank);
 }
 const rankGallery=document.createElement('details');rankGallery.id='rank-gallery';
 rankGallery.innerHTML='<summary>VER TODAS AS PATENTES</summary><div class="rank-gallery-grid">'+RANKS.map(([name],i)=>'<div class="rank-gallery-entry" data-rank="'+i+'">'+badgeMarkup(i)+'<span>'+name.toUpperCase()+'</span></div>').join('')+'</div>';
 document.querySelector('.battle-lobby-header')?.append(rankGallery);
 let toastUntil=0;
 function update(){
  const state=getState();
  hud.querySelector('#rankName').textContent=state.rank+' · '+state.rankIndex+'/'+state.totalRanks;
  hud.querySelector('#rankHudBadge').innerHTML=badgeMarkup(current);
  const lobby=document.getElementById('rankLobbyBadge');if(lobby)lobby.innerHTML=badgeMarkup(current);
  for(const el of rankGallery.querySelectorAll('[data-rank]'))el.classList.toggle('is-current',Number(el.dataset.rank)===current);

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
