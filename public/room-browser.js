/* Public room directory. Room admission and capacity are still checked by the server. */
(()=>{'use strict';
class PublicRoomBrowser{
 constructor({root,status,refreshButton,moreButton,onJoin}){
  Object.assign(this,{root,status,refreshButton,moreButton,onJoin});this.active=false;this.sequence=0;this.buttons=[];
  refreshButton?.addEventListener('click',()=>this.refresh());
  moreButton?.addEventListener('click',()=>this.refresh(true));
 }
 open(){this.active=true;return this.refresh();}
 close(){this.active=false;this.sequence++;this.request?.abort();for(const button of this.buttons)button.disabled=true;}
 async refresh(append=false){
  if(!this.active)return;
  this.request?.abort();const request=new AbortController();this.request=request;
  const sequence=++this.sequence;this.refreshButton.disabled=true;this.status.textContent='Buscando salas públicas…';
  if(this.moreButton)this.moreButton.disabled=true;
  if(!append){this.root.replaceChildren();this.buttons=[];this.cursor=null;this.count=0;}
  const timer=setTimeout(()=>request.abort(),8000);
  try{
   const response=await fetch('/api/rooms'+(append&&this.cursor?'?cursor='+encodeURIComponent(this.cursor):''),{cache:'no-store',signal:request.signal});
   if(!response.ok)throw Error('directory unavailable');
   const data=await response.json();if(!Array.isArray(data.rooms))throw Error('invalid directory');
   if(!this.active||sequence!==this.sequence)return;
   const rooms=data.rooms.filter(r=>/^FLR-[A-Z0-9]{5}$/.test(r.code)&&Number.isInteger(r.players)&&r.players>0&&r.players<=8&&r.capacity===8);
   this.cursor=/^room:flr-[a-z0-9]{5}$/.test(data.cursor||'')?data.cursor:null;this.count+=rooms.length;
   this.status.textContent=this.count?this.count+' sala(s) pública(s) · até 8 jogadores':this.cursor?'Nenhuma sala nesta página. Carregue mais salas.':'Nenhuma sala pública aberta. Crie a primeira!';
   if(this.moreButton)this.moreButton.hidden=!this.cursor;
   for(const room of rooms){
    const row=document.createElement('div');row.className='public-room-row';
    const label=document.createElement('span');label.textContent=room.code+' · '+room.players+'/'+room.capacity;
    const button=document.createElement('button');button.type='button';button.className='public-room-join';button.textContent=room.players>=room.capacity?'CHEIA':'ENTRAR';button.disabled=room.players>=room.capacity;
    button.setAttribute('aria-label','Entrar na sala '+room.code);button.addEventListener('click',()=>{if(this.active)this.onJoin(room.code);});
    this.buttons.push(button);row.appendChild(label);row.appendChild(button);this.root.appendChild(row);
   }
  }catch{
   if(this.active&&sequence===this.sequence)this.status.textContent='Não foi possível carregar as salas. Toque em Atualizar para tentar novamente.';
  }finally{
   clearTimeout(timer);if(sequence===this.sequence){this.refreshButton.disabled=false;if(this.moreButton)this.moreButton.disabled=false;}
  }
 }
}
window.PublicRoomBrowser=PublicRoomBrowser;
})();
