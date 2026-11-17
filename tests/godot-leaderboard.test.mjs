// Player leaderboard in src/godot-accounts.js, with a fake Durable Object storage.
import test from 'node:test';
import assert from 'node:assert/strict';

const { GodotAccounts } = await import('../src/godot-accounts.js');

function service(seed = {}) {
	const store = new Map(Object.entries(seed));
	const storage = {
		get: async (k) => structuredClone(store.get(k)),
		put: async (k, v) => {
			if (typeof k === 'object') for (const [key, value] of Object.entries(k)) store.set(key, structuredClone(value));
			else store.set(k, structuredClone(v));
		},
		delete: async (k) => store.delete(k),
		list: async ({ prefix }) => new Map([...store].filter(([key]) => key.startsWith(prefix)).map(([key, value]) => [key, structuredClone(value)])),
	};
	return new GodotAccounts({ storage }, {});
}

async function call(accounts, path, { token = '', body } = {}) {
	const headers = { 'content-type': 'application/json' };
	if (token) headers.Authorization = 'Bearer ' + token;
	const response = await accounts.fetch(new Request('https://internal' + path, { method: body ? 'POST' : 'GET', headers, body: body ? JSON.stringify(body) : undefined }));
	return { status: response.status, data: await response.json() };
}

async function register(accounts, name) {
	const r = await call(accounts, '/register', { body: { name, password: 'segredo1' } });
	assert.equal(r.status, 201);
	return r.data.token;
}

test('leaderboard orders by XP, then wins, and follows match results', async () => {
	const accounts = service();
	const ana = await register(accounts, 'Ana');
	await register(accounts, 'Beto');
	await register(accounts, 'Caio');
	await call(accounts, '/internal/xp', { body: { account: 'acct:beto', xp: 300, kills: 2, win: true } });
	await call(accounts, '/internal/xp', { body: { account: 'acct:caio', xp: 300, kills: 5 } });
	await call(accounts, '/internal/xp', { body: { account: 'acct:ana', xp: 120 } });
	const board = (await call(accounts, '/leaderboard?limit=2', { token: ana })).data;
	assert.deepEqual(board.players.map((p) => [p.position, p.name, p.xp]), [[1, 'Beto', 300], [2, 'Caio', 300]]);
	assert.equal(board.players[0].wins, 1);
	assert.equal(typeof board.players[0].rank, 'string');
	assert.equal(board.me.name, 'Ana');
	assert.equal(board.me.position, 3);
	assert.equal(board.total, 3);
	// Public without a session: no "me" line.
	const open = (await call(accounts, '/leaderboard')).data;
	assert.equal(open.me, null);
	assert.equal(open.players.length, 3);
});

test('leaderboard is built from existing accounts the first time', async () => {
	const accounts = service({
		'acct:velho': { name: 'Velho', xp: 900, kills: 10, wins: 3, matches: 12 },
		'acct:novo': { name: 'Novo', xp: 50, kills: 1, wins: 0, matches: 1 },
		'sess:abc': { account: 'acct:velho', expires: 0 },
	});
	const board = (await call(accounts, '/leaderboard?limit=999')).data;
	assert.deepEqual(board.players.map((p) => p.name), ['Velho', 'Novo']);
});
