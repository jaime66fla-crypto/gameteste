export function createMultiplayer3D(options){
 const {onState=()=>{},onLeave=()=>{},onShot=()=>{},onHit=()=>{},onRespawn=()=>{},onStatus=()=>{},onRanking=()=>{},url,Socket=globalThis.WebSocket}=options;
 let socket=null,epoch=0,desired=false,name='Jogador',room='cidade-1',timer=0,sequence=0,retries=0,retryTimer=null;
 const api={id:null,connected:false,name,room};
 const send=message=>{if(socket?.readyState===1){socket.send(JSON.stringify(message));return true}return false};
 function clearPeers(){onLeave(null);onRanking([])}
 function open(){
  const current=++epoch;onStatus('connecting',room);
  socket=new Socket(url(room));
  socket.onmessage=event=>{
   if(current!==epoch)return;
   let message;try{message=JSON.parse(event.data)}catch{return}
   if(message.type==='welcome3d'){
    api.id=message.id;api.connected=true;retries=0;timer=1;
    for(const state of message.players||[])if(state.id!==api.id)onState(state);
    onStatus('connected',room);return;
   }
   if(message.type==='state3d'&&message.id!==api.id)onState(message);
   if(message.type==='shot3d'&&message.ownerId!==api.id)onShot(message);
   if(message.type==='hit3d')onHit(message,api.id);
   if(message.type==='respawn3d')onRespawn(message,api.id);
   if(message.type==='ranking')onRanking(message.players||[]);
   if(message.type==='leave')onLeave(message.id);
  };
  socket.onerror=()=>{if(current===epoch)onStatus('error',room)};
  socket.onclose=()=>{
   if(current!==epoch)return;
   api.connected=false;api.id=null;clearPeers();onStatus('offline',room);
   if(desired&&retries++<5)retryTimer=setTimeout(()=>{if(desired&&current===epoch)open()},Math.min(5000,1000*retries));
  };
 }
 api.connect=(playerName,roomName)=>{
  api.disconnect();name=String(playerName||'Jogador').trim().slice(0,18)||'Jogador';
  room=String(roomName||'cidade-1').toLowerCase().replace(/[^a-z0-9-]/g,'').slice(0,24)||'cidade-1';
  api.name=name;api.room=room;sequence=0;retries=0;desired=true;open();
 };
 api.disconnect=()=>{desired=false;epoch++;clearTimeout(retryTimer);socket?.close();socket=null;api.connected=false;api.id=null;clearPeers();onStatus('solo')};
 api.update=(dt,state)=>{timer+=dt;if(api.connected&&timer>=.05){timer%=.05;send({type:'state3d',...state,name})}};
 api.shoot=payload=>{if(!api.connected)return null;const shotId=Date.now().toString(36)+'-'+(++sequence).toString(36);return send({type:'shot3d',...payload,shotId})?shotId:null};
 api.hit=(shotId,pellet,targetId)=>send({type:'hit3d',shotId,pellet,targetId});
 return api;
}
