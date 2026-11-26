// Chat do menu (Godot): canal global e conversa individual entre amigos, em tempo real.
//
// Roda dentro do Durable Object de contas (GodotAccounts), que já conhece as
// sessões e os amigos: rota /godot/chat abre um WebSocket (com hibernação) e
// cada socket guarda a conta dona dele. Mensagens:
//   jogo -> servidor   {t:'say', text}                 canal global
//                      {t:'dm', to, text}               só para amigos
//                      {t:'history', with}              conversa com um amigo
//   servidor -> jogo   {t:'chat_hello', name, global, recent}
//                      {t:'msg', ch:'global'|'dm', from, to?, rank, text, at}
//                      {t:'history', with, messages}
//                      {t:'chat_error', message}
// Guarda as últimas CHAT_HISTORY mensagens do global e de cada conversa.

export const CHAT_MAX_LEN = 200;
export const CHAT_HISTORY = 50;
const RECENT_MAX = 30; // conversas recentes mandadas ao conectar
const MIN_GAP_MS = 700; // entre duas mensagens da mesma conta
const RATE_WINDOW_MS = 10000;
const RATE_MAX = 6; // mensagens por janela

function json(data, status = 200) {
	return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
}

// Controle, DEL, caracteres invisíveis (zero-width, marcas de direção) e separadores de linha.
// Montada por códigos para o arquivo não ter esses caracteres literais.
const INVISIBLE = new RegExp('[\\u0000-\\u001f\\u007f\\u200b-\\u200f\\u2028\\u2029]', 'g');

/** Texto limpo: sem caracteres de controle, espaços juntos, no máximo CHAT_MAX_LEN. */
export function cleanText(text) {
	if (typeof text !== 'string') return '';
	return text.replace(INVISIBLE, ' ').replace(/\s+/g, ' ').trim().slice(0, CHAT_MAX_LEN);
}

const pairKey = (a, b) => 'dm:' + [a, b].sort().join('|');

/** Acrescenta o chat ao Durable Object de contas (usa accountFor e keyForName dele). */
export function installChat(AccountsClass, rankFor, banOf = () => null) {
	Object.assign(AccountsClass.prototype, {
		/** GET /chat (WebSocket): conecta a conta da sessão ao chat. */
		async chatConnect(request, token) {
			if (request.headers.get('Upgrade') !== 'websocket') return json({ error: 'WebSocket required' }, 426);
			const found = await this.accountFor(token);
			if (!found) return json({ error: 'Sessão expirada. Entre de novo.' }, 401);
			if (banOf(found.account)) return json({ error: 'Conta suspensa.' }, 403);
			const pair = new WebSocketPair();
			const client = pair[0];
			const server = pair[1];
			this.ctx.acceptWebSocket(server, [found.key]);
			server.serializeAttachment({ key: found.key });
			const recent = [];
			const index = (await this.ctx.storage.get('dmidx:' + found.key)) || {};
			for (const [otherKey, at] of Object.entries(index).sort((a, b) => b[1] - a[1]).slice(0, RECENT_MAX)) {
				const other = await this.ctx.storage.get(otherKey);
				if (other) recent.push({ with: other.name, at });
			}
			server.send(JSON.stringify({ t: 'chat_hello', name: found.account.name, global: (await this.ctx.storage.get('chat:global')) || [], recent }));
			return new Response(null, { status: 101, webSocket: client });
		},

		chatSend(ws, data) {
			try {
				ws.send(JSON.stringify(data));
			} catch {}
		},

		/** Todos os sockets abertos (de uma conta, com `key`). */
		chatSockets(key = undefined) {
			return key ? this.ctx.getWebSockets(key) : this.ctx.getWebSockets();
		},

		/** Anti-spam: intervalo mínimo e no máximo RATE_MAX por janela. Devolve a mensagem de erro ou ''. */
		chatRate(key) {
			this.chatTimes = this.chatTimes || new Map();
			const now = Date.now();
			const times = (this.chatTimes.get(key) || []).filter((t) => now - t < RATE_WINDOW_MS);
			if (times.length && now - times[times.length - 1] < MIN_GAP_MS) return 'Calma: espere um instante entre as mensagens.';
			if (times.length >= RATE_MAX) return 'Muitas mensagens seguidas. Espere alguns segundos.';
			times.push(now);
			this.chatTimes.set(key, times);
			return '';
		},

		async webSocketMessage(ws, raw) {
			let d;
			try {
				d = JSON.parse(typeof raw === 'string' ? raw : new TextDecoder().decode(raw));
			} catch {
				return;
			}
			if (!d || typeof d !== 'object') return;
			const meKey = ws.deserializeAttachment()?.key;
			const me = meKey && (await this.ctx.storage.get(meKey));
			if (!me || banOf(me)) {
				try {
					ws.close(4001, 'Sessão expirada');
				} catch {}
				return;
			}
			const error = (message) => this.chatSend(ws, { t: 'chat_error', message });
			switch (d.t) {
				case 'say': {
					const text = cleanText(d.text);
					if (!text) return;
					const limited = this.chatRate(meKey);
					if (limited) return error(limited);
					const msg = { ch: 'global', from: me.name, rank: rankFor(me.xp || 0).rank, text, at: Date.now() };
					const history = (await this.ctx.storage.get('chat:global')) || [];
					history.push(msg);
					await this.ctx.storage.put('chat:global', history.slice(-CHAT_HISTORY));
					for (const socket of this.chatSockets()) this.chatSend(socket, { t: 'msg', ...msg });
					return;
				}
				case 'dm': {
					const text = cleanText(d.text);
					if (!text) return;
					const other = await this.chatFriend(me, meKey, d.to);
					if (!other) return error('Só dá para conversar em particular com amigos.');
					const limited = this.chatRate(meKey);
					if (limited) return error(limited);
					const msg = { ch: 'dm', from: me.name, to: other.account.name, rank: rankFor(me.xp || 0).rank, text, at: Date.now() };
					const key = pairKey(meKey, other.key);
					const history = (await this.ctx.storage.get(key)) || [];
					history.push(msg);
					const myIndex = (await this.ctx.storage.get('dmidx:' + meKey)) || {};
					const theirIndex = (await this.ctx.storage.get('dmidx:' + other.key)) || {};
					myIndex[other.key] = msg.at;
					theirIndex[meKey] = msg.at;
					await this.ctx.storage.put({ [key]: history.slice(-CHAT_HISTORY), ['dmidx:' + meKey]: myIndex, ['dmidx:' + other.key]: theirIndex });
					for (const socket of [...this.chatSockets(meKey), ...this.chatSockets(other.key)]) this.chatSend(socket, { t: 'msg', ...msg });
					return;
				}
				case 'history': {
					const other = await this.chatFriend(me, meKey, d.with);
					if (!other) return error('Só dá para conversar em particular com amigos.');
					this.chatSend(ws, { t: 'history', with: other.account.name, messages: (await this.ctx.storage.get(pairKey(meKey, other.key))) || [] });
					return;
				}
			}
		},

		/** Amigo pelo nick (as duas contas precisam se ter na lista). */
		async chatFriend(me, meKey, name) {
			if (typeof name !== 'string' || !name.trim()) return null;
			const otherKey = await this.keyForName(name.trim());
			if (otherKey === meKey || !(me.friends || []).includes(otherKey)) return null;
			const account = await this.ctx.storage.get(otherKey);
			if (!account || !(account.friends || []).includes(meKey)) return null;
			return { key: otherKey, account };
		},

		async webSocketClose(ws) {
			try {
				ws.close();
			} catch {}
		},
	});
}
