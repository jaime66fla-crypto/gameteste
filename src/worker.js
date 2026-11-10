export default {
 async fetch(request, env) {
  const url = new URL(request.url);
  if (url.pathname === "/ws") {
   const room = (url.searchParams.get("room") || "cidade-1").toLowerCase().replace(/[^a-z0-9-]/g, "").slice(0, 24) || "cidade-1";
   const id = env.GAME_ROOMS.idFromName(room);
   return env.GAME_ROOMS.get(id).fetch(request);
  }
  return env.ASSETS.fetch(request);
 }
};

export class GameRoom {
 constructor(ctx, env) {
  this.ctx = ctx;
  this.sessions = new Map();
  for (const ws of ctx.getWebSockets()) {
   const data = ws.deserializeAttachment();
   if (data?.id) this.sessions.set(data.id, ws);
  }
 }
 async fetch(request) {
  if (request.headers.get("Upgrade") !== "websocket") return new Response("WebSocket required", {status: 426});
  const pair = new WebSocketPair();
  const client = pair[0], server = pair[1];
  const id = crypto.randomUUID().slice(0, 8);
  this.ctx.acceptWebSocket(server);
  server.serializeAttachment({id});
  this.sessions.set(id, server);
  server.send(JSON.stringify({type:"welcome", id}));
  return new Response(null, {status:101, webSocket:client});
 }
 webSocketMessage(ws, message) {
  const meta = ws.deserializeAttachment();
  if (!meta?.id) return;
  let data;
  try { data = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message)); } catch { return; }
  if (data.type !== "state") return;
  const safe = {
   type:"state", id:meta.id,
   name:String(data.name || "Jogador").slice(0,18),
   x:Number(data.x)||0, y:Number(data.y)||0, angle:Number(data.angle)||0,
   inCar:!!data.inCar, shooting:!!data.shooting
  };
  const out = JSON.stringify(safe);
  for (const [id, peer] of this.sessions) if (id !== meta.id) {
   try { peer.send(out); } catch {}
  }
 }
 webSocketClose(ws) { this.drop(ws); }
 webSocketError(ws) { this.drop(ws); }
 drop(ws) {
  const meta = ws.deserializeAttachment();
  if (!meta?.id) return;
  this.sessions.delete(meta.id);
  const out = JSON.stringify({type:"leave", id:meta.id});
  for (const peer of this.sessions.values()) { try { peer.send(out); } catch {} }
 }
}