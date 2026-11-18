// Friends list and room invites in src/godot-accounts.js, with a fake Durable Object storage.
import test from 'node:test';
import assert from 'node:assert/strict';

const { GodotAccounts } = await import('../src/godot-accounts.js');

function service() {
	const store = new Map();
	const storage = {
		get: async (k) => structuredClone(store.get(k)),
		put: async (k, v) => {
			if (typeof k === 'object') for (const [key, value] of Object.entries(k)) store.set(key, structuredClone(value));
			else store.set(k, structuredClone(v));
		},
		delete: async (k) => store.delete(k),
	};
	return new GodotAccounts({ storage }, {});
}

async function call(accounts, path, { token = '', body, method } = {}) {
	const headers = { 'content-type': 'application/json' };
	if (token) headers.Authorization = 'Bearer ' + token;
	const response = await accounts.fetch(new Request('https://internal' + path, { method: method || (body ? 'POST' : 'GET'), headers, body: body ? JSON.stringify(body) : undefined }));
	return { status: response.status, data: await response.json() };
}

async function register(accounts, name) {
	const r = await call(accounts, '/register', { body: { name, password: 'segredo1' } });
	assert.equal(r.status, 201);
	return r.data.token;
}

test('edit profile: new nickname (unique, once a day, login and friends follow it) and photo', async () => {
	const accounts = service();
	const ana = await register(accounts, 'Ana');
	const beto = await register(accounts, 'Beto');
	await call(accounts, '/friends/add', { token: beto, body: { name: 'Ana' } });
	await call(accounts, '/friends/accept', { token: ana, body: { name: 'Beto' } });
	// Nick ocupado (atual ou original de alguém) é recusado.
	assert.equal((await call(accounts, '/profile/name', { token: ana, body: { name: 'beto' } })).status, 409);
	assert.equal((await call(accounts, '/profile/name', { token: ana, body: { name: 'x' } })).status, 400);
	let r = await call(accounts, '/profile/name', { token: ana, body: { name: 'AnaSniper' } });
	assert.equal(r.status, 200);
	assert.equal(r.data.profile.name, 'AnaSniper');
	// O amigo vê o nick novo; entrar com o nick novo funciona; ninguém registra o nick novo.
	assert.equal((await call(accounts, '/friends', { token: beto })).data.friends[0].name, 'AnaSniper');
	assert.equal((await call(accounts, '/login', { body: { name: 'anasniper', password: 'segredo1' } })).status, 200);
	assert.equal((await call(accounts, '/register', { body: { name: 'AnaSniper', password: 'segredo1' } })).status, 409);
	assert.equal((await call(accounts, '/register', { body: { name: 'Ana', password: 'segredo1' } })).status, 409, 'original nick stays reserved');
	// Adicionar pelo nick novo acha a conta.
	const caio = await register(accounts, 'Caio');
	assert.match((await call(accounts, '/friends/add', { token: caio, body: { name: 'AnaSniper' } })).data.message, /AnaSniper|pedido|enviado/i);
	// Só uma troca por dia.
	assert.equal((await call(accounts, '/profile/name', { token: ana, body: { name: 'AnaDois' } })).status, 429);
	// Foto: JPEG/PNG pequeno, servido por /avatar com a versão no perfil.
	const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]).toString('base64');
	assert.equal((await call(accounts, '/profile/avatar', { token: ana, body: { image: Buffer.from('not an image').toString('base64') } })).status, 400);
	r = await call(accounts, '/profile/avatar', { token: ana, body: { image: png } });
	assert.ok(r.data.profile.avatar > 0);
	const image = await accounts.fetch(new Request('https://internal/avatar?name=AnaSniper&v=1'));
	assert.equal(image.status, 200);
	assert.equal(image.headers.get('content-type'), 'image/png');
	assert.ok((await call(accounts, '/friends', { token: beto })).data.friends[0].avatar > 0, 'friends get the photo version');
	r = await call(accounts, '/profile/avatar', { token: ana, body: { image: '' } });
	assert.equal(r.data.profile.avatar, 0);
	assert.equal((await accounts.fetch(new Request('https://internal/avatar?name=AnaSniper'))).status, 404);
});

test('friend request, accept, presence, invite once, remove', async () => {
	const accounts = service();
	const ana = await register(accounts, 'Ana');
	const beto = await register(accounts, 'Beto');
	// Unknown player and self are refused.
	assert.equal((await call(accounts, '/friends/add', { token: ana, body: { name: 'Ninguem' } })).status, 404);
	assert.equal((await call(accounts, '/friends/add', { token: ana, body: { name: 'ana' } })).status, 400);
	// Request -> Beto sees it -> accepts.
	assert.match((await call(accounts, '/friends/add', { token: ana, body: { name: 'beto' } })).data.message, /enviado/);
	let list = (await call(accounts, '/friends?status=menu', { token: beto })).data;
	assert.deepEqual(list.requests, ['Ana']);
	assert.match((await call(accounts, '/friends/accept', { token: beto, body: { name: 'Ana' } })).data.message, /amigos/);
	// Ana polls from a room: Beto sees her online in that room.
	await call(accounts, '/friends?status=room&code=K7Q2M', { token: ana });
	list = (await call(accounts, '/friends?status=menu', { token: beto })).data;
	assert.equal(list.requests.length, 0);
	assert.deepEqual(list.friends, [{ name: 'Ana', avatar: 0, rank: list.friends[0].rank, online: true, status: 'room', code: 'K7Q2M' }]);
	// Invite is delivered once.
	assert.match((await call(accounts, '/friends/invite', { token: ana, body: { name: 'Beto', code: 'K7Q2M' } })).data.message, /Convite/);
	list = (await call(accounts, '/friends', { token: beto })).data;
	assert.deepEqual(list.invites, [{ from: 'Ana', code: 'K7Q2M', kind: 'party' }]);
	list = (await call(accounts, '/friends', { token: beto })).data;
	assert.deepEqual(list.invites, []);
	// Convite para a sala de espera de uma eliminatória (código de 6 hex).
	assert.match((await call(accounts, '/friends/invite', { token: ana, body: { name: 'Beto', code: 'a1b2c3', kind: 'elim' } })).data.message, /Convite/);
	list = (await call(accounts, '/friends', { token: beto })).data;
	assert.deepEqual(list.invites, [{ from: 'Ana', code: 'a1b2c3', kind: 'elim' }]);
	assert.equal((await call(accounts, '/friends/invite', { token: ana, body: { name: 'Beto', code: 'K7Q2M', kind: 'elim' } })).status, 400, 'elim needs a 6-hex room');
	// Invites need a valid room code and a friend.
	assert.equal((await call(accounts, '/friends/invite', { token: ana, body: { name: 'Beto', code: '' } })).status, 400);
	const caio = await register(accounts, 'Caio');
	assert.equal((await call(accounts, '/friends/invite', { token: caio, body: { name: 'Ana', code: 'K7Q2M' } })).status, 400);
	// Remove works both ways.
	await call(accounts, '/friends/remove', { token: beto, body: { name: 'Ana' } });
	assert.deepEqual((await call(accounts, '/friends', { token: ana })).data.friends, []);
});

test('mutual add accepts automatically; offline friends show offline; no session is refused', async () => {
	const accounts = service();
	const ana = await register(accounts, 'Ana');
	const beto = await register(accounts, 'Beto');
	await call(accounts, '/friends/add', { token: ana, body: { name: 'Beto' } });
	assert.match((await call(accounts, '/friends/add', { token: beto, body: { name: 'Ana' } })).data.message, /amigos/);
	const list = (await call(accounts, '/friends', { token: ana })).data;
	assert.equal(list.friends[0].name, 'Beto');
	assert.equal(list.friends[0].online, false);
	assert.equal(list.friends[0].status, 'offline');
	assert.equal((await call(accounts, '/friends')).status, 401);
});
