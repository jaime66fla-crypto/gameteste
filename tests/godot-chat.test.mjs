// Chat do menu (src/godot-chat.js, dentro de GodotAccounts): global, amigos, histórico e anti-spam.
import test from 'node:test';
import assert from 'node:assert/strict';

class FakeSocket {
	constructor() {
		this.sent = [];
		this.attachment = null;
		this.closed = false;
	}
	send(text) {
		this.sent.push(JSON.parse(text));
	}
	close() {
		this.closed = true;
	}
	serializeAttachment(value) {
		this.attachment = value;
	}
	deserializeAttachment() {
		return this.attachment;
	}
	all(type) {
		return this.sent.filter((m) => m.t === type);
	}
	last(type) {
		return this.all(type).at(-1);
	}
}
globalThis.WebSocketPair = class {
	constructor() {
		this[0] = new FakeSocket();
		this[1] = new FakeSocket();
	}
};
const RealResponse = globalThis.Response;
globalThis.Response = class extends RealResponse {
	constructor(body, init = {}) {
		super(body, { ...init, status: init.status === 101 ? 200 : init.status });
		this.upgraded = init.status === 101;
	}
	get status() {
		return this.upgraded ? 101 : super.status;
	}
};

const { GodotAccounts } = await import('../src/godot-accounts.js');
const { CHAT_MAX_LEN, CHAT_HISTORY, cleanText } = await import('../src/godot-chat.js');

function service() {
	const store = new Map();
	const sockets = []; // [socket, tags]
	const ctx = {
		storage: {
			get: async (k) => structuredClone(store.get(k)),
			put: async (k, v) => {
				if (typeof k === 'object') for (const [key, value] of Object.entries(k)) store.set(key, structuredClone(value));
				else store.set(k, structuredClone(v));
			},
			delete: async (k) => store.delete(k),
		},
		acceptWebSocket: (ws, tags = []) => sockets.push([ws, tags]),
		getWebSockets: (tag) => sockets.filter(([ws, tags]) => !ws.closed && (!tag || tags.includes(tag))).map(([ws]) => ws),
	};
	return new GodotAccounts(ctx, {});
}

async function call(accounts, path, { token = '', body } = {}) {
	const headers = { 'content-type': 'application/json' };
	if (token) headers.Authorization = 'Bearer ' + token;
	const response = await accounts.fetch(new Request('https://internal' + path, { method: body ? 'POST' : 'GET', headers, body: body ? JSON.stringify(body) : undefined }));
	return response.json();
}

async function register(accounts, name) {
	return (await call(accounts, '/register', { body: { name, password: 'segredo1' } })).token;
}

/** Abre o chat como o jogo faz; devolve o socket do lado do servidor (onde chegam as mensagens). */
async function connect(accounts, token) {
	const before = accounts.ctx.getWebSockets().length;
	const response = await accounts.fetch(new Request('https://internal/chat', { headers: { Upgrade: 'websocket', Authorization: 'Bearer ' + token } }));
	if (response.status !== 101) return { status: response.status };
	const ws = accounts.ctx.getWebSockets()[before];
	return { status: 101, ws, say: (data) => accounts.webSocketMessage(ws, JSON.stringify(data)) };
}

async function friends(accounts, a, b, bName) {
	await call(accounts, '/friends/add', { token: a, body: { name: bName } });
	const aName = (await call(accounts, '/me', { token: a })).profile.name;
	await call(accounts, '/friends/accept', { token: b, body: { name: aName } });
}

test('connecting needs a session; hello brings the global history', async () => {
	const accounts = service();
	assert.equal((await connect(accounts, 'f'.repeat(64))).status, 401);
	const ana = await register(accounts, 'Ana');
	const a = await connect(accounts, ana);
	assert.equal(a.status, 101);
	assert.deepEqual(a.ws.last('chat_hello'), { t: 'chat_hello', name: 'Ana', global: [], recent: [] });
});

test('global chat reaches everyone in real time and is kept for who connects later', async () => {
	const accounts = service();
	const a = await connect(accounts, await register(accounts, 'Ana'));
	const b = await connect(accounts, await register(accounts, 'Beto'));
	await a.say({ t: 'say', text: '  oi   pessoal \n ' });
	const msg = b.ws.last('msg');
	assert.equal(msg.ch, 'global');
	assert.equal(msg.from, 'Ana');
	assert.equal(msg.text, 'oi pessoal', 'spaces and line breaks cleaned');
	assert.ok(msg.rank && msg.at > 0);
	assert.equal(a.ws.last('msg').text, 'oi pessoal', 'sender sees it too');
	const c = await connect(accounts, await register(accounts, 'Caio'));
	assert.equal(c.ws.last('chat_hello').global.at(-1).text, 'oi pessoal');
	await a.say({ t: 'say', text: '   ' });
	assert.equal(b.ws.all('msg').length, 1, 'empty message ignored');
});

test('private messages only between friends, to both sides, with history and recent list', async () => {
	const accounts = service();
	const ana = await register(accounts, 'Ana');
	const beto = await register(accounts, 'Beto');
	const caio = await register(accounts, 'Caio');
	await friends(accounts, ana, beto, 'Beto');
	const a = await connect(accounts, ana);
	const b = await connect(accounts, beto);
	const c = await connect(accounts, caio);
	await a.say({ t: 'dm', to: 'beto', text: 'bora jogar?' });
	assert.deepEqual([b.ws.last('msg').ch, b.ws.last('msg').from, b.ws.last('msg').to, b.ws.last('msg').text], ['dm', 'Ana', 'Beto', 'bora jogar?']);
	assert.equal(a.ws.last('msg').text, 'bora jogar?', 'echo to the sender');
	assert.equal(c.ws.all('msg').length, 0, 'nobody else sees it');
	await c.say({ t: 'dm', to: 'Ana', text: 'oi' });
	assert.match(c.ws.last('chat_error').message, /amigos/);
	assert.equal(a.ws.all('msg').length, 1);
	await b.say({ t: 'history', with: 'Ana' });
	assert.deepEqual(b.ws.last('history').messages.map((m) => m.text), ['bora jogar?']);
	const again = await connect(accounts, beto);
	assert.deepEqual(again.ws.last('chat_hello').recent.map((r) => r.with), ['Ana'], 'recent conversations on connect');
	await call(accounts, '/friends/remove', { token: beto, body: { name: 'Ana' } });
	await a.say({ t: 'dm', to: 'Beto', text: 'ainda aí?' });
	assert.match(a.ws.last('chat_error').message, /amigos/, 'no longer friends');
});

test('anti-spam, length limit and capped history', async () => {
	const accounts = service();
	const a = await connect(accounts, await register(accounts, 'Ana'));
	await a.say({ t: 'say', text: 'um' });
	await a.say({ t: 'say', text: 'dois' });
	assert.match(a.ws.last('chat_error').message, /espere/);
	assert.equal(cleanText('x'.repeat(500)).length, CHAT_MAX_LEN);
	assert.equal(cleanText('a\u0000b​c'), 'a b c');
	accounts.chatTimes = new Map();
	const now = Date.now;
	let t = now();
	Date.now = () => (t += 2000);
	try {
		for (let i = 0; i < CHAT_HISTORY + 10; i++) await a.say({ t: 'say', text: 'm' + i });
	} finally {
		Date.now = now;
	}
	const history = await accounts.ctx.storage.get('chat:global');
	assert.equal(history.length, CHAT_HISTORY);
	assert.equal(history.at(-1).text, 'm' + (CHAT_HISTORY + 9));
});
