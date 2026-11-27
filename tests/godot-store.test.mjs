// Loja interna (Brasas) em src/godot-accounts.js, com armazenamento falso do Durable Object.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const { GodotAccounts } = await import('../src/godot-accounts.js');
const store = JSON.parse(readFileSync(new URL('../godot/data/store.json', import.meta.url), 'utf8'));

function service(seed = {}) {
	const data = new Map(Object.entries(seed));
	const storage = {
		get: async (k) => structuredClone(data.get(k)),
		put: async (k, v) => {
			if (typeof k === 'object') for (const [key, value] of Object.entries(k)) data.set(key, structuredClone(value));
			else data.set(k, structuredClone(v));
		},
		delete: async (k) => data.delete(k),
		list: async ({ prefix }) => new Map([...data].filter(([key]) => key.startsWith(prefix)).map(([key, value]) => [key, structuredClone(value)])),
	};
	return { accounts: new GodotAccounts({ storage }, {}), data };
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

const paid = store.items.filter((item) => item.preco > 0).sort((a, b) => a.preco - b.preco);
const free = store.items.find((item) => item.preco === 0);

test('catalog is valid: unique ids, known pieces, paid skins have a texture', () => {
	const ids = store.items.map((item) => item.id);
	assert.equal(new Set(ids).size, ids.length);
	for (const item of store.items) {
		assert.ok(Number.isInteger(item.preco) && item.preco >= 0, item.id);
		if (item.grupo === 'skins_personagens') assert.ok(['bone', 'camiseta', 'calca', 'bermuda', 'tenis'].includes(item.peca), item.id);
		if (item.grupo !== 'personagens' && item.preco > 0) assert.match(item.textura, /^res:\/\/.+\.png$/, item.id);
	}
	assert.ok(paid.length > 0 && store.start > 0 && store.xp_per_brasa > 0);
});

test('new and old accounts start with the welcome Brasas and own nothing paid', async () => {
	const { accounts } = service({ 'acct:velho': { name: 'Velho', salt: 'x', hash: 'y', xp: 500, kills: 0, botKills: 0, wins: 0, matches: 0 } });
	const token = await register(accounts, 'Nova');
	const me = (await call(accounts, '/me', { token })).data.profile;
	assert.equal(me.brasas, store.start);
	assert.deepEqual(me.owned, []);
	const old = (await call(accounts, '/internal/xp', { body: { account: 'acct:velho', xp: 0 } })).data.profile;
	assert.equal(old.brasas, store.start, 'conta antiga ganha o bônus inicial');
});

test('positive XP earns Brasas, the remainder carries over and penalties never take Brasas', async () => {
	const { accounts } = service();
	await register(accounts, 'Dani');
	const per = store.xp_per_brasa;
	let r = await call(accounts, '/internal/xp', { body: { account: 'acct:dani', xp: per * 3 + per / 2 } });
	assert.equal(r.data.brasasGained, 3);
	assert.equal(r.data.profile.brasas, store.start + 3);
	r = await call(accounts, '/internal/xp', { body: { account: 'acct:dani', xp: per / 2 } });
	assert.equal(r.data.brasasGained, 1, 'sobra da partida anterior conta');
	r = await call(accounts, '/internal/xp', { body: { account: 'acct:dani', xp: -100 } });
	assert.equal(r.data.brasasGained, 0);
	assert.equal(r.data.profile.brasas, store.start + 4);
});

test('buying: needs a session, enough Brasas, a real paid item, and only once', async () => {
	const { accounts, data } = service();
	const token = await register(accounts, 'Eva');
	const cheap = paid[0];
	assert.equal((await call(accounts, '/store/buy', { body: { item: cheap.id } })).status, 401);
	assert.equal((await call(accounts, '/store/buy', { token, body: { item: 'arma_dourada' } })).status, 404);
	const freeBuy = await call(accounts, '/store/buy', { token, body: { item: free.id } });
	assert.equal(freeBuy.status, 200);
	assert.equal(freeBuy.data.profile.brasas, store.start, 'item grátis não cobra');

	const account = data.get('acct:eva');
	account.brasas = cheap.preco - 1;
	data.set('acct:eva', account);
	const poor = await call(accounts, '/store/buy', { token, body: { item: cheap.id } });
	assert.equal(poor.status, 402);
	assert.match(poor.data.error, /Faltam 1 /);

	account.brasas = cheap.preco + 5;
	data.set('acct:eva', account);
	const ok = await call(accounts, '/store/buy', { token, body: { item: cheap.id } });
	assert.equal(ok.status, 200);
	assert.equal(ok.data.profile.brasas, 5);
	assert.deepEqual(ok.data.profile.owned, [cheap.id]);
	const again = await call(accounts, '/store/buy', { token, body: { item: cheap.id } });
	assert.equal(again.data.profile.brasas, 5, 'comprar de novo não cobra');
	assert.deepEqual(data.get('acct:eva').purchases.map((p) => [p.item, p.price]), [[cheap.id, cheap.preco]]);
	assert.equal((await call(accounts, '/store/buy', { token })).status, 405);
});

test('store groups: every item has a known group, 01 is never sold', () => {
	const groups = store.groups.map((group) => group.id);
	assert.deepEqual(groups, ['personagens', 'skins_armas', 'skins_personagens']);
	for (const item of store.items) {
		assert.ok(groups.includes(item.grupo), item.id);
		if (item.grupo === 'skins_armas') assert.ok(['pistol', 'smg', 'shotgun', 'rifle', 'sniper'].includes(item.arma), item.id);
	}
	assert.equal(store.items.find((item) => item.id === '01'), undefined);
	assert.ok(store.items.filter((item) => item.grupo === 'personagens').every((item) => item.preco > 0));
});

test('paid characters are only shown to others when the account bought them', async () => {
	const { allowedCharacter, ownedQuery, ownedFrom } = await import('../src/godot-accounts.js');
	assert.equal(allowedCharacter('01', []), '01', 'padrão é livre');
	// Sem personagens pagos na loja (só o 01 desde a 1.51): nada a travar.
	const paid = store.items.find((item) => item.grupo === 'personagens' && item.preco > 0);
	if (paid) {
		assert.equal(allowedCharacter(paid.id, []), '');
		assert.equal(allowedCharacter(paid.id, [paid.id]), paid.id);
	}
	assert.equal(allowedCharacter('remy', []), 'remy', 'removido da loja: sem trava');
	assert.equal(allowedCharacter('jaime_swat', []), 'jaime_swat', 'fora da loja: sem trava');
	assert.equal(allowedCharacter('', []), '');
	const url = new URL('https://internal/join?x=1' + ownedQuery({ owned: ['bone_vinho', 'rifle_deserto'] }) + '%2Cinventado');
	assert.deepEqual(ownedFrom(url), ['bone_vinho', 'rifle_deserto']);
	// A sessão interna leva os itens da conta até a sala.
	const { accounts, data } = service();
	const token = await register(accounts, 'Gil');
	const account = data.get('acct:gil');
	account.owned = ['remy'];
	data.set('acct:gil', account);
	const session = await call(accounts, '/internal/session', { token });
	assert.deepEqual(session.data.owned, ['remy']);
});

test('outfits and weapon skins shown to others: only what the account owns, one per piece, skin of the gun in hand', async () => {
	const { allowedCosmetics } = await import('../src/godot-accounts.js');
	// Cliente antigo: sem rp (os outros veem a roupa padrão) e sem skin.
	assert.deepEqual(allowedCosmetics({ w: 'rifle' }, 'rifle', []), { ws: '' });
	// Grátis passa; paga só se comprou; peça repetida e item de outro grupo saem.
	assert.deepEqual(allowedCosmetics({ rp: ['bone_vinho', 'camiseta', 'calca'] }, 'rifle', []).rp, ['camiseta', 'calca']);
	assert.deepEqual(allowedCosmetics({ rp: ['bone_vinho', 'bone', 'remy', 'rifle_deserto', 7] }, 'rifle', ['bone_vinho']).rp, ['bone_vinho']);
	assert.deepEqual(allowedCosmetics({ rp: [] }, 'rifle', []).rp, [], 'sem roupa nenhuma também é escolha');
	assert.equal(allowedCosmetics({ rp: ['a', 'b', 'c', 'd', 'bone'] }, 'rifle', []).rp.length, 0, 'no máximo 4 itens olhados');
	// Skin: comprada e da arma que está na mão.
	assert.equal(allowedCosmetics({ ws: 'rifle_deserto' }, 'rifle', []).ws, '');
	assert.equal(allowedCosmetics({ ws: 'rifle_deserto' }, 'rifle', ['rifle_deserto']).ws, 'rifle_deserto');
	assert.equal(allowedCosmetics({ ws: 'rifle_deserto' }, 'pistol', ['rifle_deserto']).ws, '');
	assert.equal(allowedCosmetics({ ws: 'bone_vinho' }, 'rifle', ['bone_vinho']).ws, '');
});

test('the leaderboard never shows Brasas or owned items', async () => {
	const { accounts } = service();
	const token = await register(accounts, 'Fabi');
	const board = (await call(accounts, '/leaderboard', { token })).data;
	for (const row of [...board.players, board.me]) {
		assert.equal(row.brasas, undefined);
		assert.equal(row.owned, undefined);
	}
});

test('master account (jaimexzz.dev) owns every paid item without buying', async () => {
	const { accounts } = service();
	const token = await register(accounts, 'jaimexzz.dev');
	const me = await call(accounts, '/me', { token });
	assert.equal(me.status, 200);
	for (const item of paid) assert.ok(me.data.profile.owned.includes(item.id), `master sem ${item.id}`);
	const before = me.data.profile.brasas;
	const bought = await call(accounts, '/store/buy', { token, body: { item: paid.at(-1).id } });
	assert.equal(bought.data.profile.brasas, before, 'master não deveria gastar Brasas');
	const login = await call(accounts, '/login', { body: { name: 'JaimeXZZ.dev', password: 'segredo1' } });
	assert.equal(login.data.profile.owned.length >= paid.length, true);
	const other = await register(accounts, 'outra.conta');
	const them = await call(accounts, '/me', { token: other });
	assert.deepEqual(them.data.profile.owned, []);
});

test('master by current name: account renamed to Jaimexzz.dev also owns everything', async () => {
	const { accounts, data } = service();
	const token = await register(accounts, 'cadastro.antigo');
	const acc = data.get('acct:cadastro.antigo');
	acc.name = 'Jaimexzz.dev';
	data.set('acct:cadastro.antigo', acc);
	const me = await call(accounts, '/me', { token });
	for (const item of paid) assert.ok(me.data.profile.owned.includes(item.id), `master sem ${item.id}`);
});
