/* Room transport: opening a socket is not confirmation of admission. */
(()=>{'use strict';
class MultiplayerClient{
 constructor({onStatus=()=>{},onReady=()=>{},onMessage=()=>{},onDisconnect=()=>{}}={}){Object.assign(this,{onStatus,onReady,onMessage,onDisconnect});this.active=false;this.pending=false;this.socket=null;this.id=null;}
 connect(action,code,name){
  code=String(code||'').trim().toUpperCase();name=String(name||'').trim().slice(0,16);
  if(!name){this.onStatus('Digite seu nome.');return false;}
  if(!/^FLR-[A-Z0-9]{5}$/.test(code)){this.onStatus('Digite o código completo: FLR-XXXXX.');return false;}
  this.disconnect();this.room=code;this.name=name;this.pending=true;
  this.onStatus(action==='create'?'Criando sala…':'Entrando na sala…');
  let ws;try{ws=new WebSocket((location.protocol==='https:'?'wss://':'ws://')+location.host+'/ws?mode=3d&action='+action+'&room='+encodeURIComponent(code));}catch{this.fail('Não foi possível conectar ao servidor.');return false;}
  this.socket=ws;
  const fail=()=>{if(this.socket===ws)this.fail('Sem conexão. Verifique a rede e se a sala ainda está aberta.');};
  this.timer=setTimeout(fail,10000);
  ws.onopen=()=>{};
  ws.onerror=fail;ws.onclose=fail;
  ws.onmessage=e=>{
   if(this.socket!==ws)return;
   let data;try{data=JSON.parse(e.data)}catch{return}
   if(data.type==='welcome3d'&&!this.active){clearTimeout(this.timer);this.id=data.id;this.active=true;this.pending=false;this.onStatus('Conectado à sala '+code);this.onReady(data);}
   else if(this.active)this.onMessage(data);
  };
  return true;
 }
 send(data){if(this.active&&this.socket?.readyState===1){try{this.socket.send(JSON.stringify(data));return true}catch{this.fail('A conexão com a sala foi interrompida.')}}return false;}
 sendState(state){return this.send({...state,type:'state3d',name:this.name});}
 disconnect(){clearTimeout(this.timer);const ws=this.socket;this.socket=null;this.active=false;this.pending=false;this.id=null;if(ws)ws.close();}
 fail(message){const wasActive=this.active;this.disconnect();this.onStatus(message);this.onDisconnect(wasActive);}
}
window.MultiplayerClient=MultiplayerClient;
})();
