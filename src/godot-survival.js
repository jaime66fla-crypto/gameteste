// Modo Sobrevivência (Godot): mundo aberto de floresta para até 16 jogadores.
// Ninguém começa com nada: tudo vem da coleta (galhos, pedras, fibra, toras,
// frutas, ervas, água dos lagos) e da fabricação. Zumbis só aparecem à noite.
// (O código de recipientes, carros e armas de fogo continua aqui, mas o mapa
// de floresta não tem nenhum deles.)
//
// Cada mundo é um Durable Object ("world:<n>"). Não há sala de espera: quem
// entra nasce na hora e quem sai guarda o personagem (posição, vida, fome,
// sede e mochila) para voltar ao mesmo mundo depois.
//
// O servidor é dono de tudo o que importa: vida dos jogadores e dos zumbis,
// inventário, conteúdo dos recipientes, recursos coletados, fome e sede.
// Os zumbis são movidos por um jogador (o "anfitrião", como os bots do mata-mata)
// porque precisam da colisão real do mapa; o servidor confere distâncias e
// limita o dano que eles causam.
//
// Mapa, itens, saques e receitas: godot/data/survival_world.json e
// godot/data/survival_items.json (os mesmos arquivos que o jogo lê).
import world from '../godot/data/survival_world.json' with { type: 'json' };
import catalog from '../godot/data/survival_items.json' with { type: 'json' };
import { resolveSession, rankFor } from './godot-accounts.js';
import { HitCheck, stanceOf } from './godot-hitcheck.js';

/** Visible character id (godot/characters/*.tres): short slug or '' (others then show the default). */
const characterId = (v) => (typeof v === 'string' && /^[a-z0-9_]{1,32}$/.test(v) ? v : '');

export const CAPACITY = 16;
const MAX_WORLDS = 12;
const TICK_MS = 3000;
// Fome e sede: de 100 a 0 em ~75 min e ~50 min. Zeradas, tiram 1 de vida por tick.
const HUNGER_PER_TICK = 100 / ((75 * 60 * 1000) / TICK_MS);
const THIRST_PER_TICK = 100 / ((50 * 60 * 1000) / TICK_MS);
const STARVE_DAMAGE = 1;
const DAY_MS = 24 * 60 * 1000; // um dia inteiro (dia + noite) dura 24 minutos
const RESPAWN_MS = 8000;
const REACH = 3.6; // metros entre o jogador e o recipiente/recurso
const MELEE_REACH = 3.2;
const GUN_REACH = 700; // alcance da sniper (scripts/weapon_data.gd)
const CONTAINER_REFILL_MS = 45 * 60 * 1000;
const BAG_LIFETIME_MS = 25 * 60 * 1000;
const CHAR_KEEP_MS = 3 * 24 * 3600 * 1000; // personagem guardado de quem saiu
// Só recebe posições de quem está até essa distância. Precisa cobrir o alcance
// útil da sniper/fuzil, senão o alvo distante fica "congelado" e o tiro erra.
const INTEREST_RANGE = 360;
// Armas de fogo: mesmo dano por acerto do mata-mata (scripts/weapon_data.gd).
const WEAPON_DAMAGE = { pistol: 22, smg: 12, rifle: 27, shotgun: 11, sniper: 95 };
const ZONE_MULTIPLIER = { head: 2.0, chest: 1.0, pelvis: 0.9, arm: 0.7, leg: 0.7 };
const FIST_DAMAGE = 12; // soco sem arma branca
const MAX_HITS_PER_SECOND = 18;
// Zumbis: andarilho, corredor (mais rápido, menos vida) e brutamontes.
export const ZOMBIE_KINDS = {
	walker: { hp: 60, damage: 9, weight: 70 },
	runner: { hp: 45, damage: 7, weight: 20 },
	brute: { hp: 150, damage: 16, weight: 10 },
};
const ZOMBIE_ATTACK_MS = 1000;
const ZOMBIE_REACH = 1.8; // alcance do golpe (o jogo usa 1,25 m; a folga cobre o atraso da rede)
const ZOMBIE_REACH_LAG = 1.0;
// Mundo de floresta: zumbis só à noite (20h–6h), poucos (as armas são primitivas).
const ZOMBIE_BASE = 4;
const ZOMBIE_PER_PLAYER = 4;
const ZOMBIE_MAX = 50;
const ZOMBIE_DAWN_FADE = 0.25; // de dia, chance por tick de cada zumbi perto de alguém sumir
const NIGHT_START = 20;
const NIGHT_END = 6;
// Versão do mundo salvo: mundo de outra versão (a cidade antiga) recomeça do zero.
export const WORLD_VERSION = 2;
const ZOMBIE_SPAWN_MIN = 55; // nunca nascem na cara de ninguém
const ZOMBIE_SAFE_START = 60; // ao entrar/renascer, some zumbi que estiver mais perto que isso
const ZOMBIE_FIGHT_KEEP = 25; // ...a não ser que outro jogador esteja brigando com ele
const ZOMBIE_SPAWN_MAX = 130;
const ZOMBIE_DESPAWN = 210;
const ZOMBIE_SPAWN_BATCH = 6;
const XP = { zombie: 5, player: 60 };
// Carros: entrar/abastecer a até 4 m; o motorista manda a posição (10 por segundo).
const VEHICLE_REACH = 4.2;
const VEHICLE_MAX_STEP = 12; // metros entre dois pacotes (bem acima de 26 m/s × 0,1 s)
const RAM_MIN_SPEED = 6; // m/s para atropelar um zumbi
const RAM_DAMAGE_PER_MS = 7; // dano = velocidade × 7 (60 km/h ≈ 115)
const VEHICLES = catalog.vehicles;
// Lataria: só batida forte tira (perda de velocidade acima de CRASH_MIN m/s, não um encostão).
const CRASH_MIN = 4.5;
const CRASH_DAMAGE_PER_MS = 5; // 60 km/h de frente num muro ≈ 60 de dano
const RAM_CAR_DAMAGE = 3; // atropelar zumbi amassa um pouco
const EXPLOSION_RADIUS = 8;
const EXPLOSION_PLAYER_DAMAGE = 90;
const EXPLOSION_ZOMBIE_DAMAGE = 160;
// Mordida de zumbi infecta: sem vacina em 2 minutos, o jogador vira zumbi (e morre).
export const INFECTION_MS = 2 * 60 * 1000;

const ITEMS = catalog.items;
const CONTAINERS = Object.fromEntries(world.containers.map((c) => [c.id, c]));
const RESOURCES = Object.fromEntries(world.resources.map((r) => [r.id, r]));
const RECIPES = Object.fromEntries(catalog.recipes.map((r) => [r.id, r]));

const finite = (v, limit) => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= limit;
const vec3 = (v, limit) => (Array.isArray(v) && v.length === 3 && v.every((n) => finite(n, limit)) ? v.map((n) => Math.round(n * 100) / 100) : null);
const flat = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);
const randInt = (min, max) => min + Math.floor(Math.random() * (max - min + 1));
const round1 = (n) => Math.round(n * 10) / 10;

function weighted(entries, weightOf) {
	const total = entries.reduce((sum, e) => sum + weightOf(e), 0);
	let roll = Math.random() * total;
	for (const e of entries) {
		roll -= weightOf(e);
		if (roll < 0) return e;
	}
	return entries[entries.length - 1];
}

/** Sorteia o conteúdo de um recipiente pela tabela do seu tipo. */
export function rollLoot(type) {
	const table = catalog.loot[type];
	if (!table) return {};
	const items = {};
	if (Math.random() < (table.empty || 0)) return items; // muitos recipientes já foram saqueados
	const rolls = randInt(table.rolls[0], table.rolls[1]);
	for (let i = 0; i < rolls; i++) {
		const [item, , min, max] = weighted(table.table, (e) => e[1]);
		items[item] = (items[item] || 0) + randInt(min, max);
	}
	return items;
}

export function inventoryWeight(inv) {
	let total = 0;
	for (const [item, n] of Object.entries(inv)) total += (ITEMS[item]?.weight || 0) * n;
	return Math.round(total * 100) / 100;
}

/** Peso máximo: bolsos do personagem + a mochila equipada nas costas (se houver). */
export function carryLimit(back = '') {
	return catalog.carry_base + (ITEMS[back]?.carry || 0);
}

/** Espaços do corpo: slot do item → campo do jogador. */
export const GEAR_SLOTS = { back: 'back', head: 'head', chest: 'chest' };
/** Partes do corpo que cada proteção cobre. */
const ARMOR_COVERS = { head: ['head'], chest: ['chest', 'pelvis'] };

/** Peso carregado: itens + o que está vestido (mochila, capacete, colete). */
export function carriedWeight(player) {
	let worn = 0;
	for (const field of Object.values(GEAR_SLOTS)) worn += ITEMS[player[field]]?.weight || 0;
	return Math.round((inventoryWeight(player.inv) + worn) * 100) / 100;
}

/**
 * Fração do dano que passa pela proteção. Capacete protege a cabeça; colete o
 * peito e o quadril (explosão conta como peito). Mordida de zumbi não tem parte
 * do corpo: o colete segura metade do que seguraria um tiro.
 */
export function armorFactor(player, zone, weapon = '') {
	if (weapon === 'zombie') return 1 - (ITEMS[player.chest]?.armor || 0) / 2;
	for (const [field, zones] of Object.entries(ARMOR_COVERS)) {
		if (zones.includes(zone)) return 1 - (ITEMS[player[field]]?.armor || 0);
	}
	return 1;
}

function addItems(inv, item, n) {
	if (!ITEMS[item] || !(n > 0)) return;
	inv[item] = (inv[item] || 0) + n;
}

function removeItems(inv, item, n) {
	if (!inv[item] || inv[item] < n) return false;
	inv[item] -= n;
	if (inv[item] <= 0) delete inv[item];
	return true;
}

/** Quanto de `item` cabe no inventário do jogador sem passar do peso. */
function roomFor(player, item, wanted) {
	const unit = ITEMS[item]?.weight || 0;
	if (unit <= 0) return wanted;
	const free = carryLimit(player.back) - carriedWeight(player);
	return Math.max(0, Math.min(wanted, Math.floor((free + 1e-6) / unit)));
}

function noticeSocket(message) {
	const pair = new WebSocketPair();
	const [client, server] = [pair[0], pair[1]];
	server.accept();
	server.send(JSON.stringify(message));
	setTimeout(() => {
		try {
			server.close(4000, 'notice');
		} catch {}
	}, 2000);
	return new Response(null, { status: 101, webSocket: client });
}

/** Rota pública /godot/survival: entra no primeiro mundo com vaga. */
export async function handleSurvivalSocket(request, env, url) {
	if (request.headers.get('Upgrade') !== 'websocket') return new Response('WebSocket required', { status: 426 });
	const build = Number.parseInt(url.searchParams.get('v') || '0', 10) || 0;
	if (build < (Number(env.GODOT_MIN_BUILD) || 0)) {
		return noticeSocket({ t: 'outdated', url: String(env.GODOT_DOWNLOAD_URL || ''), message: 'Há uma nova versão do Campo de Fogo. Atualize para jogar online.' });
	}
	const header = request.headers.get('Authorization') || '';
	const token = header.startsWith('Bearer ') ? header.slice(7).trim() : url.searchParams.get('token') || '';
	const session = await resolveSession(env, token);
	if (!session) return noticeSocket({ t: 'auth', message: 'Entre na sua conta para jogar online.' });
	const query = '&name=' + encodeURIComponent(session.name) + '&account=' + encodeURIComponent(session.account) + '&xp=' + encodeURIComponent(session.xp);
	const order = WORLD_NAMES.slice();
	// Mundo escolhido na lista: só ele (cada mundo guarda o seu próprio personagem).
	const chosen = url.searchParams.get('world') || '';
	if (chosen) {
		if (!WORLD_NAMES.includes(chosen)) return noticeSocket({ t: 'party_error', message: 'Mundo não encontrado.' });
		const stub = env.GODOT_SURVIVAL.get(env.GODOT_SURVIVAL.idFromName(chosen));
		const response = await stub.fetch(new Request('https://internal/join?world=' + encodeURIComponent(chosen) + query, request));
		if (response.status === 101) return response;
		const reason = response.status === 409 ? await response.text() : '';
		return noticeSocket({ t: 'party_error', message: reason === 'Conta já está neste mundo' ? 'Sua conta já está jogando neste mundo.' : 'Esse mundo está cheio. Escolha outro na lista.' });
	}
	// Sem escolha: volta para o mundo onde o personagem ficou dormindo (se houver vaga), senão o primeiro com vaga.
	const home = (await worldInfos(env, session.account)).filter((w) => w.mine).sort((a, b) => b.savedAt - a.savedAt)[0];
	if (home) order.unshift(...order.splice(order.indexOf(home.name), 1));
	for (const name of order) {
		const stub = env.GODOT_SURVIVAL.get(env.GODOT_SURVIVAL.idFromName(name));
		const response = await stub.fetch(new Request('https://internal/join?world=' + encodeURIComponent(name) + query, request));
		if (response.status === 101) return response;
	}
	return noticeSocket({ t: 'party_error', message: 'Todos os mundos estão cheios. Tente de novo em alguns minutos.' });
}

const WORLD_NAMES = [...Array(MAX_WORLDS).keys()].map((i) => 'world:' + (i + 1));

/** Rota /godot/survival/worlds: lista dos mundos, quantos estão online e onde você tem personagem. */
export async function handleSurvivalWorlds(request, env) {
	const header = request.headers.get('Authorization') || '';
	const session = await resolveSession(env, header.startsWith('Bearer ') ? header.slice(7).trim() : '');
	if (!session) return Response.json({ error: 'Entre na sua conta para jogar online.' }, { status: 401 });
	const worlds = (await worldInfos(env, session.account)).map(({ name, number, online, mine, day }) => ({ id: name, number, online, capacity: CAPACITY, mine, day }));
	return Response.json({ worlds });
}

/** Situação de cada mundo (online, dia, personagem guardado desta conta). */
async function worldInfos(env, account) {
	return Promise.all(WORLD_NAMES.map(async (name, i) => {
		const base = { name, number: i + 1, online: 0, savedAt: 0, mine: false, day: 1 };
		try {
			const stub = env.GODOT_SURVIVAL.get(env.GODOT_SURVIVAL.idFromName(name));
			const res = await stub.fetch('https://internal/has?account=' + encodeURIComponent(account || ''));
			const data = res.ok ? await res.json() : {};
			return { ...base, online: data.online || 0, savedAt: data.savedAt || 0, mine: !!data.savedAt, day: data.day || 1 };
		} catch {
			return base;
		}
	}));
}

export class GodotSurvival {
	constructor(ctx, env) {
		this.ctx = ctx;
		this.env = env;
		this.sessions = new Map(); // player id -> WebSocket
		this.hitLog = new Map();
		this.hitCheck = new HitCheck(); // alcance, cabeça plausível e taxa de tiros na cabeça
		this.state = this.fresh();
		this.dirty = false;
		ctx.blockConcurrencyWhile(async () => {
			const saved = await ctx.storage.get('world');
			// Mundo de outra versão (cidade, saque, carros): recomeça como floresta.
			if (saved && saved.version === WORLD_VERSION) this.state = saved;
			for (const ws of ctx.getWebSockets()) {
				const meta = ws.deserializeAttachment();
				if (meta?.id) this.sessions.set(meta.id, ws);
			}
		});
	}

	fresh() {
		return {
			version: WORLD_VERSION, name: '', createdAt: Date.now(), players: {}, chars: {}, host: null,
			zombies: {}, zSeq: 0, containers: {}, bags: {}, bagSeq: 0, depleted: {}, vehicles: {},
		};
	}

	/** Carros do mapa (criados na primeira vez, com pouca ou nenhuma gasolina). */
	vehicles() {
		const s = this.state;
		if (!s.vehicles) s.vehicles = {};
		for (const spot of world.vehicles || []) {
			if (s.vehicles[spot.id]) continue;
			const fuel = Math.random() < 0.4 ? 0 : randInt(4, 22);
			s.vehicles[spot.id] = { id: spot.id, kind: spot.kind, color: spot.color, p: [...spot.p], yaw: spot.yaw, fuel, driver: null, speed: 0, hp: 100, broken: false };
		}
		for (const v of Object.values(s.vehicles)) {
			if (typeof v.hp !== 'number') v.hp = 100; // mundos salvos antes da lataria
			if (typeof v.broken !== 'boolean') v.broken = false;
		}
		return s.vehicles;
	}

	vehiclePacket(v) {
		return { id: v.id, kind: v.kind, color: v.color, p: v.p, yaw: v.yaw, fuel: round1(v.fuel), driver: v.driver, hp: Math.round(v.hp), broken: !!v.broken };
	}

	/** Batida relatada pelo motorista: `i` = velocidade perdida no choque (m/s). */
	crash(me, d) {
		const v = this.vehicles()[d.v];
		if (!v || v.broken || v.driver !== me.id || me.vehicle !== v.id) return;
		const impact = finite(d.i, 60) ? Math.abs(d.i) : 0;
		if (impact < CRASH_MIN) return; // encostar não estraga
		const now = Date.now();
		if (now - (v.crashAt || 0) < 300) return;
		v.crashAt = now;
		this.damageVehicle(v, (impact - CRASH_MIN) * CRASH_DAMAGE_PER_MS + 4, me);
	}

	damageVehicle(v, amount, by = null) {
		if (v.broken || !(amount > 0)) return;
		v.hp = Math.max(0, round1(v.hp - amount));
		if (v.hp <= 0) return this.explodeVehicle(v, by);
		this.broadcast({ t: 'veh', ...this.vehiclePacket(v) });
		this.save();
	}

	/** Lataria zerada: explode, quem está perto se machuca, o carro fica quebrado. */
	explodeVehicle(v, by = null) {
		const s = this.state;
		const driver = v.driver && s.players[v.driver];
		v.hp = 0;
		v.broken = true;
		v.fuel = 0;
		v.speed = 0;
		if (driver) this.leaveVehicle(driver);
		v.driver = null;
		this.broadcast({ t: 'boom', id: v.id, p: v.p });
		this.broadcast({ t: 'veh', ...this.vehiclePacket(v) });
		for (const target of Object.values(s.players)) {
			if (target.dead || !this.sessions.has(target.id)) continue;
			const d = Math.hypot(target.p[0] - v.p[0], target.p[2] - v.p[2]);
			if (d < EXPLOSION_RADIUS) this.damagePlayer(target, EXPLOSION_PLAYER_DAMAGE * (1 - d / EXPLOSION_RADIUS), by?.id || v.id, 'explosion', 'chest', by && by.id !== target.id ? by : null);
		}
		for (const zombie of Object.values(s.zombies)) {
			const d = flat(zombie.p, v.p);
			if (d >= EXPLOSION_RADIUS) continue;
			zombie.hp = Math.max(0, round1(zombie.hp - EXPLOSION_ZOMBIE_DAMAGE * (1 - d / EXPLOSION_RADIUS)));
			if (zombie.hp > 0) {
				this.broadcastNear(zombie.p, { t: 'zhp', id: zombie.id, hp: zombie.hp, by: by?.id || '', zone: 'chest' });
				continue;
			}
			delete s.zombies[zombie.id];
			if (by) {
				by.zkills++;
				this.credit(by, XP.zombie);
			}
			this.broadcast({ t: 'zdead', id: zombie.id, by: by?.id || '', zone: 'chest', w: 'explosion' });
		}
		this.save();
	}

	/** Kit de reparos perto do carro (depois de segurar 5 s): conserta a lataria e tira do "quebrado". */
	repair(me, d, note) {
		const v = this.vehicles()[d.v];
		if (!v) return;
		if (flat(me.p, v.p) > VEHICLE_REACH) return note('Longe demais.');
		if (!me.inv.repair_kit) return note('Você precisa de um kit de reparos.');
		if (!v.broken && v.hp >= 100) return note('O carro não precisa de conserto.');
		const rule = ITEMS.repair_kit;
		const waited = Date.now() - (me.useAt || 0);
		if (me.useItem !== 'repair_kit' || waited < rule.use_time * 1000 - 300 || waited > rule.use_time * 1000 + 6000) return;
		me.useAt = 0;
		removeItems(me.inv, 'repair_kit', 1);
		v.hp = v.broken ? rule.repair : Math.min(100, v.hp + rule.repair);
		v.broken = false;
		this.save();
		this.sendInv(me);
		this.broadcast({ t: 'veh', ...this.vehiclePacket(v) });
		note(`Carro consertado: lataria em ${Math.round(v.hp)}%.` + (v.fuel <= 0 ? ' Precisa de gasolina.' : ''));
	}

	/** Sai do carro (por vontade, morte ou desconexão); o carro fica onde parou. */
	leaveVehicle(player) {
		const v = player?.vehicle && this.vehicles()[player.vehicle];
		if (player) player.vehicle = null;
		if (!v || v.driver !== player.id) return;
		v.driver = null;
		v.speed = 0;
		this.broadcast({ t: 'veh', ...this.vehiclePacket(v) });
		this.save();
	}

	enterVehicle(me, d, note) {
		const v = this.vehicles()[d.v];
		if (!v || me.vehicle) return;
		if (v.broken) return note('Carro destruído. Conserte com um kit de reparos.');
		if (v.driver && this.sessions.has(v.driver) && this.state.players[v.driver]?.vehicle === v.id) return note('Já tem alguém dirigindo.');
		if (flat(me.p, v.p) > VEHICLE_REACH) return note('Longe demais.');
		v.driver = me.id;
		me.vehicle = v.id;
		this.broadcast({ t: 'veh', ...this.vehiclePacket(v) });
		if (v.fuel <= 0) note('Tanque vazio. Abasteça com um galão de gasolina (E fora do carro).');
		this.save();
	}

	/** Posição do carro vinda do motorista; gasta combustível pela distância. */
	driveVehicle(me, d) {
		const v = this.vehicles()[d.v];
		if (!v || v.driver !== me.id || me.vehicle !== v.id) return;
		const p = vec3(d.p, 600);
		if (!p) return;
		const step = flat(v.p, p);
		if (step > VEHICLE_MAX_STEP) return this.sendTo(me.id, { t: 'veh', ...this.vehiclePacket(v), snap: true });
		if (v.fuel <= 0 && step > 0.6) return this.sendTo(me.id, { t: 'veh', ...this.vehiclePacket(v), snap: true });
		const rule = VEHICLES[v.kind] || VEHICLES.sedan;
		const before = v.fuel;
		v.fuel = Math.max(0, v.fuel - (step / 1000) * rule.per_km);
		v.p = p;
		v.yaw = finite(d.y, 100) ? d.y : v.yaw;
		v.speed = finite(d.s, 60) ? Math.abs(d.s) : 0;
		me.p = p;
		if (Math.floor(before) !== Math.floor(v.fuel)) this.sendTo(me.id, { t: 'fuel', v: v.id, fuel: round1(v.fuel) });
		if (before > 0 && v.fuel <= 0) this.sendTo(me.id, { t: 'note', message: 'Acabou a gasolina.' });
		this.broadcastNear(p, { t: 'vs', id: v.id, p, y: v.yaw, s: round1(v.speed) }, me.id);
	}

	refuel(me, d, note) {
		const v = this.vehicles()[d.v];
		if (!v) return;
		if (flat(me.p, v.p) > VEHICLE_REACH) return note('Longe demais.');
		if (v.broken) return note('Carro destruído: conserte antes de abastecer.');
		if (!me.inv.gasoline) return note('Você precisa de um galão de gasolina.');
		if (v.fuel >= 99) return note('Tanque cheio.');
		removeItems(me.inv, 'gasoline', 1);
		v.fuel = Math.min(100, v.fuel + (ITEMS.gasoline.fuel || 35));
		this.save();
		this.sendInv(me);
		this.broadcast({ t: 'veh', ...this.vehiclePacket(v) });
		note(`Abasteceu: tanque em ${Math.round(v.fuel)}%.`);
	}

	/** O motorista atropelou um zumbi: dano pela velocidade do carro. */
	ram(me, d) {
		const v = this.vehicles()[me.vehicle];
		const zombie = this.state.zombies[d.z];
		if (!v || v.driver !== me.id || !zombie) return;
		if (v.speed < RAM_MIN_SPEED || flat(v.p, zombie.p) > 5) return;
		const now = Date.now();
		if (now - (zombie.rammedAt || 0) < 500) return;
		zombie.rammedAt = now;
		this.applyHit(me, zombie.id, Math.min(200, v.speed * RAM_DAMAGE_PER_MS), 'car', 'chest', 6);
		this.damageVehicle(v, RAM_CAR_DAMAGE, me);
	}

	save(now = false) {
		this.dirty = true;
		if (now) this.flushSave();
	}

	flushSave() {
		if (!this.dirty) return;
		this.dirty = false;
		this.ctx.waitUntil(this.ctx.storage.put('world', this.state));
	}

	send(ws, data) {
		try {
			ws.send(JSON.stringify(data));
		} catch {}
	}

	sendTo(id, data) {
		const ws = this.sessions.get(id);
		if (ws) this.send(ws, data);
	}

	broadcast(data, exceptId = null) {
		const out = JSON.stringify(data);
		for (const [id, ws] of this.sessions) {
			if (id === exceptId) continue;
			try {
				ws.send(out);
			} catch {}
		}
	}

	/** Só para quem está perto de `p` (posições, tiros). */
	broadcastNear(p, data, exceptId = null, range = INTEREST_RANGE) {
		const out = JSON.stringify(data);
		for (const [id, ws] of this.sessions) {
			if (id === exceptId) continue;
			const other = this.state.players[id];
			if (other?.p && p && flat(other.p, p) > range) continue;
			try {
				ws.send(out);
			} catch {}
		}
	}

	living() {
		return Object.values(this.state.players).filter((p) => !p.dead && this.sessions.has(p.id));
	}

	clock() {
		return { day_ms: DAY_MS, time: (Date.now() - this.state.createdAt) % DAY_MS };
	}

	/** Hora do jogo (o dia começa às 6h, como no cliente). */
	hour(now = Date.now()) {
		return (6 + (((now - this.state.createdAt) % DAY_MS) / DAY_MS) * 24) % 24;
	}

	isNight(now = Date.now()) {
		const h = this.hour(now);
		return h >= NIGHT_START || h < NIGHT_END;
	}

	async fetch(request) {
		const url = new URL(request.url);
		if (url.pathname === '/has') {
			// Só diz se a conta tem personagem guardado aqui (e quando saiu); nada de dados.
			const saved = this.state.chars[url.searchParams.get('account') || ''];
			const fresh = saved && Date.now() - saved.savedAt < CHAR_KEEP_MS;
			const day = this.state.name ? Math.floor((Date.now() - this.state.createdAt) / DAY_MS) + 1 : 1;
			return Response.json({ savedAt: fresh ? saved.savedAt : 0, online: this.sessions.size, day });
		}
		if (url.pathname !== '/join') return new Response('Not found', { status: 404 });
		if (request.headers.get('Upgrade') !== 'websocket') return new Response('WebSocket required', { status: 426 });
		const s = this.state;
		if (!s.name) s.name = url.searchParams.get('world') || 'world';
		if (this.sessions.size >= CAPACITY) return new Response('Mundo cheio', { status: 409 });
		const account = url.searchParams.get('account') || '';
		if (account && Object.values(s.players).some((p) => p.account === account && this.sessions.has(p.id))) {
			return new Response('Conta já está neste mundo', { status: 409 });
		}
		const pair = new WebSocketPair();
		const [client, server] = [pair[0], pair[1]];
		const id = crypto.randomUUID().slice(0, 8);
		this.ctx.acceptWebSocket(server);
		server.serializeAttachment({ id });
		this.sessions.set(id, server);
		const totalXp = Math.max(0, Number(url.searchParams.get('xp')) || 0);
		const saved = account ? s.chars[account] : null;
		const player = {
			id, account, name: url.searchParams.get('name') || 'Sobrevivente', rank: rankFor(totalXp).rank,
			xpGain: 0, kills: 0, zkills: 0, useAt: 0, gatherAt: 0, gatherId: '', respawnAt: 0, y: 0,
			...(saved && Date.now() - saved.savedAt < CHAR_KEEP_MS ? this.restore(saved) : this.newCharacter()),
		};
		s.players[id] = player;
		if (saved) {
			// Acordou: o corpo dormindo some para os outros (o jogador volta como ele mesmo).
			delete s.chars[account];
			if (saved.sid) this.broadcast({ t: 'wake', id: saved.sid });
		}
		if (!s.host || !this.sessions.has(s.host)) s.host = id;
		if (!player.dead) this.clearZombiesNear(player.p, id);
		this.save(true);
		this.send(server, { t: 'welcome', id, room: s.name, survival: true, capacity: CAPACITY });
		this.send(server, this.startPacket(player));
		this.broadcast({ t: 'join', id, name: player.name, rank: player.rank, p: player.p, dead: player.dead }, id);
		this.ctx.waitUntil(this.ensureAlarm());
		return new Response(null, { status: 101, webSocket: client });
	}

	newCharacter() {
		const spawn = world.spawns[Math.floor(Math.random() * world.spawns.length)];
		return { p: [spawn[0], 0.2, spawn[1]], hp: 100, hunger: 85, thirst: 85, inv: { ...catalog.starter_kit }, back: '', head: '', chest: '', dead: false, infectedAt: 0 };
	}

	restore(saved) {
		if (saved.dead) return { ...this.newCharacter(), inv: {}, dead: true, respawnAt: Date.now() };
		// A infecção fica "pausada" enquanto o jogador está fora do jogo.
		const left = Math.max(0, Math.min(INFECTION_MS, Number(saved.infectedLeft) || 0));
		return {
			p: saved.p, y: saved.y || 0, hp: saved.hp, hunger: saved.hunger, thirst: saved.thirst, inv: saved.inv || {}, back: saved.back || '', head: saved.head || '', chest: saved.chest || '', dead: false,
			infectedAt: left > 0 ? Date.now() - (INFECTION_MS - left) : 0,
		};
	}

	/** Personagens de quem saiu: ficam deitados, dormindo, onde o jogador estava. */
	sleepers() {
		const now = Date.now();
		return Object.values(this.state.chars)
			.filter((c) => c.sid && !c.dead && Array.isArray(c.p) && now - c.savedAt < CHAR_KEEP_MS)
			.map((c) => this.sleeperPacket(c));
	}

	sleeperPacket(c) {
		return { id: c.sid, name: c.name || '', rank: c.rank || '', p: c.p, y: c.y || 0, bp: c.back || '' };
	}

	startPacket(me) {
		const s = this.state;
		const now = Date.now();
		const depleted = {};
		for (const [rid, until] of Object.entries(s.depleted)) if (until > now) depleted[rid] = Math.round((until - now) / 1000);
		return {
			t: 'start',
			survival: true,
			host: s.host,
			clock: this.clock(),
			you: { id: me.id, p: me.p, y: me.y || 0, infected: Math.round(this.infectionLeft(me, now) / 1000), hp: me.hp, hunger: round1(me.hunger), thirst: round1(me.thirst), dead: me.dead, ...this.invPacket(me) },
			roster: Object.values(s.players)
				.filter((p) => p.id !== me.id && this.sessions.has(p.id))
				.map((p) => ({ id: p.id, name: p.name, rank: p.rank, p: p.p, dead: p.dead })),
			zombies: Object.values(s.zombies),
			vehicles: Object.values(this.vehicles()).map((v) => this.vehiclePacket(v)),
			bags: Object.values(s.bags).map((b) => this.bagSummary(b)),
			sleepers: this.sleepers(),
			searched: Object.keys(s.containers).filter((k) => s.containers[k].refillAt > now && !Object.keys(s.containers[k].items).length),
			depleted,
		};
	}

	invPacket(player) {
		return { inv: player.inv, back: player.back || '', head: player.head || '', chest: player.chest || '', weight: carriedWeight(player), cap: carryLimit(player.back) };
	}

	sendInv(player) {
		this.sendTo(player.id, { t: 'inv', ...this.invPacket(player) });
	}

	sendStats(player) {
		this.sendTo(player.id, { t: 'stats', hp: player.hp, hunger: round1(player.hunger), thirst: round1(player.thirst) });
	}

	bagSummary(bag) {
		return { id: bag.id, p: bag.p, name: bag.name, count: Object.values(bag.items).reduce((a, b) => a + b, 0) };
	}

	async ensureAlarm() {
		const current = await this.ctx.storage.getAlarm?.();
		if (!current) await this.ctx.storage.setAlarm(Date.now() + TICK_MS);
	}

	// ------------------------------------------------------------- mensagens ---

	webSocketMessage(ws, message) {
		const meta = ws.deserializeAttachment();
		const s = this.state;
		const me = meta?.id && s.players[meta.id];
		if (!me) return;
		let d;
		try {
			d = JSON.parse(typeof message === 'string' ? message : new TextDecoder().decode(message));
		} catch {
			return;
		}
		if (!d || typeof d !== 'object') return;
		const isHost = meta.id === s.host;
		const reply = (data) => this.send(ws, data);
		const note = (message) => reply({ t: 'note', message });
		// Ping: devolve na hora o relógio do jogo, que mede o tempo de ida e volta.
		if (d.t === 'ping') return reply({ t: 'pong', c: finite(d.c, 1e15) ? d.c : 0 });
		if (d.t === 'respawn') return this.respawn(me);
		if (me.dead) return;
		switch (d.t) {
			case 's': {
				const p = vec3(d.p, 600);
				if (!p) return;
				me.p = p;
				me.stance = stanceOf(d);
				if (finite(d.y, 1000)) me.y = d.y;
				this.broadcastNear(p, {
					t: 's', id: me.id, p, y: finite(d.y, 1000) ? d.y : 0, pi: finite(d.pi, 2) ? d.pi : 0,
					w: WEAPON_DAMAGE[d.w] ? d.w : 'pistol', m: finite(d.m, 1) ? Math.max(0, d.m) : 0,
					r: !!d.r, c: !!d.c, pr: !!d.pr, a: !!d.a, f: !!d.f, rl: !!d.rl, h: !!d.h, bp: me.back || '', dv: me.vehicle || '', ch: characterId(d.ch),
					act: ['chop', 'pry', 'swing', 'open', 'harvest', 'consume'].includes(d.act) ? d.act : '', tool: typeof d.tool === 'string' && ITEMS[d.tool]?.melee ? d.tool : '',
					v: Array.isArray(d.v) && d.v.length === 2 && d.v.every((n) => finite(n, 50)) ? d.v : [0, 0],
				}, me.id);
				return;
			}
			case 'z': return isHost && this.zombieStates(d.l);
			case 'shot': {
				const o = vec3(d.o, 600);
				const e = vec3(d.e, 1200);
				if (!o || !e) return;
				this.broadcastNear(o, { t: 'shot', id: me.id, w: WEAPON_DAMAGE[d.w] ? d.w : 'pistol', o, e }, me.id, INTEREST_RANGE);
				return;
			}
			case 'hit': return this.gunHit(me, d);
			case 'melee': return this.meleeHit(me, d);
			case 'zhit': return isHost && this.zombieHit(d);
			case 'search': return this.search(me, d, reply, note);
			case 'take': return this.take(me, d, reply, note);
			case 'drop': return this.drop(me, d, note);
			case 'use_start': {
				if (!me.inv[d.item]) return;
				me.useAt = Date.now();
				me.useItem = d.item;
				return;
			}
			case 'use': return this.use(me, d, note);
			case 'craft': return this.craft(me, d, note);
			case 'enter': return this.enterVehicle(me, d, note);
			case 'exit': return this.leaveVehicle(me);
			case 'drive': return this.driveVehicle(me, d);
			case 'refuel': return this.refuel(me, d, note);
			case 'ram': return this.ram(me, d);
			case 'crash': return this.crash(me, d);
			case 'repair_start': {
				if (!me.inv.repair_kit) return;
				me.useAt = Date.now();
				me.useItem = 'repair_kit';
				return;
			}
			case 'repair': return this.repair(me, d, note);
			case 'equip': return this.equip(me, d, note);
			case 'unequip': return this.unequip(me, d, note);
			case 'gather_start': {
				const res = RESOURCES[d.r];
				if (!res || flat(me.p, res.p) > REACH + (res.r || 0)) return;
				me.gatherAt = Date.now();
				me.gatherId = res.id;
				return;
			}
			case 'gather': return this.gather(me, d, note);
			case 'consume': {
				// Munição gasta na recarga (o jogo avisa quantas balas foram para o pente).
				const item = d.ammo;
				const n = Number.isInteger(d.n) ? Math.max(0, Math.min(d.n, 200)) : 0;
				if (!item?.startsWith?.('a_') || !n) return;
				removeItems(me.inv, item, Math.min(n, me.inv[item] || 0));
				this.save();
				this.sendInv(me);
				return;
			}
		}
	}

	// --------------------------------------------------------------- combate ---

	allowHit(attackerId) {
		const now = Date.now();
		const recent = (this.hitLog.get(attackerId) || []).filter((t) => now - t < 1000);
		if (recent.length >= MAX_HITS_PER_SECOND) return false;
		recent.push(now);
		this.hitLog.set(attackerId, recent);
		return true;
	}

	gunHit(me, d) {
		const weapon = WEAPON_DAMAGE[d.w] ? d.w : null;
		if (!weapon || !me.inv['w_' + weapon] || !this.allowHit(me.id)) return;
		let zone = ZONE_MULTIPLIER[d.zone] ? d.zone : 'chest';
		// Alcance da arma; em jogadores, cabeça plausível e taxa de tiros na cabeça.
		const s = this.state;
		const target = s.zombies[d.target] || s.players[d.target];
		if (target) {
			const verdict = this.hitCheck.check({ attacker: me, target, weapon, zone, point: d.pt, player: !s.zombies[d.target] });
			if (!verdict.ok) return;
			zone = verdict.zone;
		}
		this.applyHit(me, d.target, WEAPON_DAMAGE[weapon] * ZONE_MULTIPLIER[zone], weapon, zone, GUN_REACH);
	}

	/** Soco (Q) ou arma branca da mochila; alcance curto. */
	meleeHit(me, d) {
		const item = typeof d.item === 'string' && me.inv[d.item] && ITEMS[d.item]?.melee ? d.item : '';
		const damage = item ? ITEMS[item].melee : FIST_DAMAGE;
		if (!this.allowHit(me.id)) return;
		this.applyHit(me, d.target, damage * (d.zone === 'head' ? 1.5 : 1), item || 'fist', d.zone === 'head' ? 'head' : 'chest', MELEE_REACH);
	}

	applyHit(attacker, targetId, amount, weapon, zone, reach) {
		const s = this.state;
		if (typeof targetId !== 'string') return;
		const zombie = s.zombies[targetId];
		if (zombie) {
			if (flat(attacker.p, zombie.p) > reach + 2) return;
			zombie.hp = Math.max(0, round1(zombie.hp - amount));
			if (zombie.hp > 0) {
				this.broadcastNear(zombie.p, { t: 'zhp', id: zombie.id, hp: zombie.hp, by: attacker.id, zone });
				return;
			}
			delete s.zombies[zombie.id];
			attacker.zkills++;
			this.credit(attacker, XP.zombie);
			this.broadcast({ t: 'zdead', id: zombie.id, by: attacker.id, zone, w: weapon });
			this.save();
			return;
		}
		const target = s.players[targetId];
		if (!target || target.dead || target.id === attacker.id || !this.sessions.has(target.id)) return;
		if (target.vehicle) return; // dentro do carro ninguém se machuca (o carro protege)
		if (flat(attacker.p, target.p) > reach + 2) return;
		this.damagePlayer(target, amount, attacker.id, weapon, zone, attacker);
	}

	damagePlayer(target, amount, by, weapon, zone = null, attacker = null) {
		amount *= armorFactor(target, zone, weapon);
		target.hp = Math.max(0, round1(target.hp - amount));
		const killed = target.hp === 0;
		this.broadcast({ t: 'hp', id: target.id, hp: target.hp, by, w: weapon, zone, killed });
		if (killed) this.kill(target, attacker);
		this.save();
	}

	kill(target, attacker) {
		this.leaveVehicle(target);
		target.dead = true;
		target.infectedAt = 0;
		target.respawnAt = Date.now() + RESPAWN_MS;
		if (attacker && attacker.id !== target.id) {
			attacker.kills++;
			this.credit(attacker, XP.player);
		}
		// Tudo o que carregava e vestia fica numa mochila no chão.
		for (const field of Object.values(GEAR_SLOTS)) {
			if (target[field]) addItems(target.inv, target[field], 1);
			target[field] = '';
		}
		if (Object.keys(target.inv).length) this.makeBag(target.p, target.inv, target.name);
		target.inv = {};
		this.sendInv(target);
	}

	respawn(me) {
		if (!me.dead || Date.now() < me.respawnAt) return;
		Object.assign(me, this.newCharacter());
		this.clearZombiesNear(me.p, me.id);
		this.save();
		this.sendTo(me.id, { t: 'respawned', p: me.p, hp: me.hp, hunger: me.hunger, thirst: me.thirst, ...this.invPacket(me) });
		this.broadcast({ t: 'join', id: me.id, name: me.name, rank: me.rank, p: me.p, dead: false }, me.id);
	}

	credit(player, amount) {
		if (!player?.account) return;
		player.xpGain = (player.xpGain || 0) + amount;
		this.sendTo(player.id, { t: 'xp', amount, total: player.xpGain });
	}

	async flushXp(player) {
		if (!player?.account || !player.xpGain) return;
		const gained = player.xpGain;
		player.xpGain = 0;
		try {
			const accounts = this.env.GODOT_ACCOUNTS.get(this.env.GODOT_ACCOUNTS.idFromName('godot-accounts'));
			await accounts.fetch(new Request('https://internal/internal/xp', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ account: player.account, xp: gained, kills: player.kills || 0, botKills: 0, win: false }),
			}));
			player.kills = 0;
		} catch {}
	}

	// ---------------------------------------------------------------- zumbis ---

	/** Posições vindas do anfitrião: [[id, x, y, z, yaw, anim], ...]. */
	zombieStates(list) {
		if (!Array.isArray(list)) return;
		const s = this.state;
		const moved = [];
		for (const entry of list.slice(0, ZOMBIE_MAX)) {
			if (!Array.isArray(entry) || entry.length < 6) continue;
			const zombie = s.zombies[entry[0]];
			const p = vec3([entry[1], entry[2], entry[3]], 600);
			if (!zombie || !p) continue;
			// Um zumbi não anda mais de ~3 m entre dois pacotes (6 por segundo).
			if (flat(zombie.p, p) > 12) continue;
			zombie.p = p;
			moved.push([zombie.id, p[0], p[1], p[2], finite(entry[4], 100) ? round1(entry[4]) : 0, Number.isInteger(entry[5]) ? entry[5] : 0]);
		}
		if (!moved.length) return;
		// Cada jogador só recebe os zumbis perto dele.
		for (const [id, ws] of this.sessions) {
			if (id === s.host) continue;
			const viewer = s.players[id];
			const near = viewer?.p ? moved.filter((z) => Math.hypot(z[1] - viewer.p[0], z[3] - viewer.p[2]) < INTEREST_RANGE) : moved;
			if (near.length) this.send(ws, { t: 'z', l: near });
		}
	}

	/** Mordida/golpe de um zumbi, relatado pelo anfitrião. */
	zombieHit(d) {
		const s = this.state;
		const zombie = s.zombies[d.z];
		const target = s.players[d.target];
		if (!zombie || !target || target.dead || !this.sessions.has(target.id)) return;
		if (target.vehicle) return; // dentro do carro o zumbi não alcança
		const now = Date.now();
		if (now - (zombie.lastHit || 0) < ZOMBIE_ATTACK_MS) return;
		if (Math.hypot(zombie.p[0] - target.p[0], zombie.p[2] - target.p[2]) > ZOMBIE_REACH + ZOMBIE_REACH_LAG) return;
		zombie.lastHit = now;
		this.damagePlayer(target, ZOMBIE_KINDS[zombie.kind]?.damage || 9, zombie.id, 'zombie');
		// Mordida infecta: começa o relógio de 2 minutos (só uma infecção por vez).
		if (!target.dead && !target.infectedAt) {
			target.infectedAt = now;
			this.sendTo(target.id, { t: 'infected', left: INFECTION_MS / 1000 });
			this.save();
		}
	}

	infectionLeft(player, now = Date.now()) {
		return player.infectedAt ? Math.max(0, INFECTION_MS - (now - player.infectedAt)) : 0;
	}

	/** Passou o tempo sem vacina: vira zumbi — o jogador morre e um zumbi nasce no lugar. */
	turnIntoZombie(player) {
		player.infectedAt = 0;
		const p = [...player.p];
		this.damagePlayer(player, player.hp + 1, player.id, 'infection');
		const zombie = { id: 'z' + ++this.state.zSeq, kind: 'walker', hp: ZOMBIE_KINDS.walker.hp, p, from: player.name };
		this.state.zombies[zombie.id] = zombie;
		this.broadcast({ t: 'zspawn', l: [zombie] });
	}

	/**
	 * Começo seguro: quem entra ou renasce não pode cair no meio dos zumbis.
	 * Some com os que estão perto do ponto (menos os que outro jogador já está
	 * enfrentando); o ciclo normal repõe depois, longe de todos.
	 */
	clearZombiesNear(p, exceptId) {
		const s = this.state;
		const others = this.living().filter((pl) => pl.id !== exceptId);
		const gone = [];
		for (const zombie of Object.values(s.zombies)) {
			if (flat(zombie.p, p) >= ZOMBIE_SAFE_START) continue;
			if (others.some((pl) => flat(pl.p, zombie.p) < ZOMBIE_FIGHT_KEEP)) continue;
			delete s.zombies[zombie.id];
			gone.push(zombie.id);
		}
		if (gone.length) this.broadcast({ t: 'zgone', l: gone });
	}

	spawnZombies() {
		const s = this.state;
		const players = this.living();
		const count = Object.keys(s.zombies).length;
		// Some quem ficou longe de todo mundo.
		const gone = [];
		for (const zombie of Object.values(s.zombies)) {
			if (!players.some((p) => flat(p.p, zombie.p) < ZOMBIE_DESPAWN)) {
				delete s.zombies[zombie.id];
				gone.push(zombie.id);
			}
		}
		// De dia não nasce zumbi; os que sobraram da noite somem aos poucos.
		if (players.length && !this.isNight()) {
			for (const zombie of Object.values(s.zombies)) {
				if (Math.random() >= ZOMBIE_DAWN_FADE) continue;
				delete s.zombies[zombie.id];
				gone.push(zombie.id);
			}
		}
		if (gone.length) this.broadcast({ t: 'zgone', l: gone });
		if (!players.length || !this.isNight()) return;
		const target = Math.min(ZOMBIE_MAX, ZOMBIE_BASE + ZOMBIE_PER_PLAYER * players.length);
		const born = [];
		for (let i = 0; i < ZOMBIE_SPAWN_BATCH && count - gone.length + born.length < target; i++) {
			const spot = this.zombieSpot(players);
			if (!spot) break;
			const [kind] = weighted(Object.entries(ZOMBIE_KINDS), ([, k]) => k.weight);
			const zombie = { id: 'z' + ++s.zSeq, kind, hp: ZOMBIE_KINDS[kind].hp, p: spot };
			s.zombies[zombie.id] = zombie;
			born.push(zombie);
		}
		if (born.length) this.broadcast({ t: 'zspawn', l: born });
	}

	/** Ponto numa área de zumbis (cidades pesam mais), longe de todos e perto de alguém. */
	zombieSpot(players) {
		const zones = world.zombie_zones.filter((z) => players.some((p) => Math.hypot(p.p[0] - z.x, p.p[2] - z.z) < ZOMBIE_SPAWN_MAX + z.r));
		for (let attempt = 0; attempt < 12; attempt++) {
			let x;
			let z;
			if (zones.length && Math.random() < 0.75) {
				const zone = weighted(zones, (zz) => zz.weight);
				const a = Math.random() * Math.PI * 2;
				const d = Math.sqrt(Math.random()) * zone.r;
				x = zone.x + Math.cos(a) * d;
				z = zone.z + Math.sin(a) * d;
			} else {
				// Errantes no meio do mato, ao redor de alguém.
				const anchor = players[Math.floor(Math.random() * players.length)];
				const a = Math.random() * Math.PI * 2;
				const d = ZOMBIE_SPAWN_MIN + Math.random() * (ZOMBIE_SPAWN_MAX - ZOMBIE_SPAWN_MIN);
				x = anchor.p[0] + Math.cos(a) * d;
				z = anchor.p[2] + Math.sin(a) * d;
			}
			if (Math.abs(x) > world.half_size - 4 || Math.abs(z) > world.half_size - 4) continue;
			const p = [round1(x), 0.2, round1(z)];
			const nearest = Math.min(...players.map((pl) => flat(pl.p, p)));
			if (nearest < ZOMBIE_SPAWN_MIN || nearest > ZOMBIE_SPAWN_MAX) continue;
			return p;
		}
		return null;
	}

	// ---------------------------------------------------------- saque e itens ---

	/** Revistar um recipiente do mapa ou uma mochila no chão. */
	search(me, d, reply, note) {
		const s = this.state;
		const bag = s.bags[d.k];
		if (bag) {
			if (flat(me.p, bag.p) > REACH) return note('Longe demais.');
			return reply({ t: 'container', k: bag.id, title: bag.name ? 'Mochila de ' + bag.name : 'Mochila', items: bag.items });
		}
		const spot = CONTAINERS[d.k];
		if (!spot) return;
		if (flat(me.p, spot.p) > REACH || Math.abs((me.p[1] || 0) - spot.p[1]) > 2.5) return note('Longe demais.');
		const now = Date.now();
		let box = s.containers[spot.id];
		if (!box || (box.refillAt <= now && !Object.keys(box.items).length)) {
			box = { items: rollLoot(spot.type), refillAt: now + CONTAINER_REFILL_MS };
			s.containers[spot.id] = box;
			this.save();
		}
		reply({ t: 'container', k: spot.id, title: catalog.loot[spot.type]?.name || 'Recipiente', items: box.items });
	}

	/** Pegar itens de um recipiente/mochila (limitado pelo peso). */
	take(me, d, reply, note) {
		const s = this.state;
		const bag = s.bags[d.k];
		const spot = CONTAINERS[d.k];
		const at = bag ? bag.p : spot?.p;
		const items = bag ? bag.items : s.containers[d.k]?.items;
		if (!items || !at || flat(me.p, at) > REACH) return;
		const wanted = Number.isInteger(d.n) && d.n > 0 ? Math.min(d.n, items[d.item] || 0) : items[d.item] || 0;
		if (!ITEMS[d.item] || !wanted) return;
		const fits = roomFor(me, d.item, wanted);
		if (!fits) return note('Mochila pesada demais.');
		removeItems(items, d.item, fits);
		addItems(me.inv, d.item, fits);
		if (fits < wanted) note('Não coube tudo: mochila pesada demais.');
		if (bag && !Object.keys(bag.items).length) {
			delete s.bags[bag.id];
			this.broadcast({ t: 'bag_gone', id: bag.id });
		} else if (bag) {
			this.broadcastNear(bag.p, { t: 'bag', bag: this.bagSummary(bag) });
		} else if (!Object.keys(items).length) {
			this.broadcastNear(spot.p, { t: 'emptied', k: spot.id });
		}
		this.save();
		this.sendInv(me);
		reply({ t: 'container', k: d.k, title: bag ? 'Mochila' + (bag.name ? ' de ' + bag.name : '') : catalog.loot[spot.type]?.name, items });
	}

	drop(me, d, note) {
		const have = me.inv[d.item] || 0;
		const n = Number.isInteger(d.n) && d.n > 0 ? Math.min(d.n, have) : have;
		if (!n) return;
		removeItems(me.inv, d.item, n);
		this.makeBag(me.p, { [d.item]: n }, me.name);
		this.save();
		this.sendInv(me);
		note(`Largou ${ITEMS[d.item]?.name || d.item} ×${n}.`);
	}

	/** Junta na mochila do chão mais próxima (até 2 m) ou cria uma nova. */
	makeBag(p, items, name) {
		const s = this.state;
		let bag = Object.values(s.bags).find((b) => flat(b.p, p) < 2);
		if (!bag) {
			bag = { id: 'b' + ++s.bagSeq, p: [round1(p[0]), round1(p[1] || 0), round1(p[2])], items: {}, name, expires: 0 };
			s.bags[bag.id] = bag;
		}
		for (const [item, n] of Object.entries(items)) addItems(bag.items, item, n);
		bag.expires = Date.now() + BAG_LIFETIME_MS;
		this.broadcast({ t: 'bag', bag: this.bagSummary(bag) });
		return bag;
	}

	/** Comer, beber, curar. Kit médico leva 3 s (use_start → use). */
	use(me, d, note) {
		const item = ITEMS[d.item];
		if (!item?.use || !me.inv[d.item]) return;
		if (item.use_time) {
			const waited = Date.now() - (me.useAt || 0);
			if (me.useItem !== d.item || waited < item.use_time * 1000 - 300 || waited > item.use_time * 1000 + 6000) return;
			me.useAt = 0;
		}
		if (item.use.cure && !me.infectedAt) return note('Você não está infectado.');
		if (item.use.hp && !item.use.cure && !item.use.hunger && !item.use.thirst && me.hp >= 100) return note('Vida cheia.');
		removeItems(me.inv, d.item, 1);
		const u = item.use;
		if (u.cure) {
			me.infectedAt = 0;
			this.sendTo(me.id, { t: 'infected', left: 0 });
		}
		if (u.hp) me.hp = Math.min(100, me.hp + u.hp);
		if (u.hunger) me.hunger = Math.max(0, Math.min(100, me.hunger + u.hunger));
		if (u.thirst) me.thirst = Math.max(0, Math.min(100, me.thirst + u.thirst));
		this.save();
		this.sendInv(me);
		this.sendStats(me);
		if (u.hp) this.broadcast({ t: 'hp', id: me.id, hp: me.hp, by: me.id, w: '', zone: null, killed: false });
		note(`Usou ${item.name}.`);
	}

	/** Veste mochila (costas), capacete (cabeça) ou colete (peito); o que estava volta para o inventário. */
	equip(me, d, note) {
		const item = ITEMS[d.item];
		const field = GEAR_SLOTS[item?.slot];
		if (!field || !me.inv[d.item]) return;
		const old = me[field] || '';
		removeItems(me.inv, d.item, 1);
		me[field] = d.item;
		if (old) addItems(me.inv, old, 1);
		if (carriedWeight(me) > carryLimit(me.back)) {
			// Trocar por uma mochila menor não pode deixar o jogador acima do limite.
			if (old) removeItems(me.inv, old, 1);
			me[field] = old;
			addItems(me.inv, d.item, 1);
			return note('Peso demais para essa mochila. Largue alguns itens antes.');
		}
		this.save();
		this.sendInv(me);
		note(item.carry ? `Equipou ${item.name} (+${item.carry} kg).` : `Vestiu ${item.name} (−${Math.round(item.armor * 100)}% de dano).`);
	}

	/** Tira o que está num espaço (padrão: costas). A mochila só sai se o resto couber nos bolsos. */
	unequip(me, d, note) {
		const field = GEAR_SLOTS[d?.slot] || 'back';
		if (!me[field]) return;
		const old = me[field];
		me[field] = '';
		addItems(me.inv, old, 1);
		if (carriedWeight(me) > carryLimit(me.back)) {
			removeItems(me.inv, old, 1);
			me[field] = old;
			return note('Os bolsos não aguentam tudo. Largue itens antes de tirar a mochila.');
		}
		this.save();
		this.sendInv(me);
		note(`Tirou ${ITEMS[old].name}.`);
	}

	craft(me, d, note) {
		const recipe = RECIPES[d.recipe];
		if (!recipe) return;
		for (const [item, n] of Object.entries(recipe.needs)) {
			if ((me.inv[item] || 0) < n) return note(`Falta ${ITEMS[item]?.name || item}.`);
		}
		for (const [item, n] of Object.entries(recipe.needs)) removeItems(me.inv, item, n);
		const [item, n] = recipe.gives;
		addItems(me.inv, item, n);
		this.save();
		this.sendInv(me);
		note(`Fabricou ${recipe.name}.`);
	}

	/** Coleta (tora, pedra, galho, fibra, frutas, ervas, água) depois de segurar E pelo tempo do recurso. */
	gather(me, d, note) {
		const s = this.state;
		const res = RESOURCES[d.r];
		if (!res || flat(me.p, res.p) > REACH + (res.r || 0)) return;
		const rule = catalog.resources[res.kind];
		const now = Date.now();
		if ((s.depleted[res.id] || 0) > now) return note('Já foi coletado. Volte mais tarde.');
		const waited = now - (me.gatherAt || 0);
		if (me.gatherId !== res.id || waited < rule.time * 1000 - 300 || waited > rule.time * 1000 + 6000) return;
		me.gatherAt = 0;
		// Lago: bebe na hora, nunca acaba.
		if (rule.drink) {
			me.thirst = Math.min(100, me.thirst + rule.drink);
			this.save();
			this.sendStats(me);
			return note(me.thirst >= 100 ? 'Bebeu água. Sede saciada.' : 'Bebeu água.');
		}
		const hasTool = (kind) => Object.keys(me.inv).some((item) => ITEMS[item]?.tool === kind);
		if (rule.needs && !hasTool(rule.needs)) {
			const tool = Object.values(ITEMS).find((item) => item.tool === rule.needs);
			return note(`Precisa de ${tool ? tool.name.toLowerCase() : 'uma ferramenta'}.`);
		}
		const tooled = !rule.needs && rule.tool && hasTool(rule.tool);
		const [min, max] = tooled ? rule.bonus : rule.base;
		const gained = { [rule.gives]: randInt(min, max) };
		if (rule.extra && Math.random() < rule.extra[1]) gained[rule.extra[0]] = 1;
		const got = [];
		for (const [item, n] of Object.entries(gained)) {
			const fits = roomFor(me, item, n);
			addItems(me.inv, item, fits);
			if (fits) got.push(`${ITEMS[item].name} +${fits}`);
		}
		if (!got.length) return note('Peso demais. Largue alguma coisa.');
		if (rule.regrow > 0) {
			s.depleted[res.id] = now + rule.regrow * 1000;
			this.broadcastNear(res.p, { t: 'depleted', r: res.id, secs: rule.regrow });
		}
		this.save();
		this.sendInv(me);
		note((rule.tool && !rule.needs && !tooled ? 'Com ferramenta rende mais. ' : '') + got.join(', '));
	}

	// ------------------------------------------------------------- relógio ---

	async alarm() {
		const s = this.state;
		const now = Date.now();
		if (!this.sessions.size) {
			// Mundo vazio: os zumbis somem; personagens e recipientes ficam guardados.
			s.zombies = {};
			s.host = null;
			this.save(true);
			return;
		}
		for (const player of this.living()) {
			player.hunger = Math.max(0, player.hunger - HUNGER_PER_TICK);
			player.thirst = Math.max(0, player.thirst - THIRST_PER_TICK);
			if (player.hunger <= 0 || player.thirst <= 0) {
				this.damagePlayer(player, STARVE_DAMAGE * ((player.hunger <= 0) + (player.thirst <= 0)), player.id, player.thirst <= 0 ? 'sede' : 'fome');
			}
			if (!player.dead && player.infectedAt && this.infectionLeft(player, now) <= 0) this.turnIntoZombie(player);
			if (!player.dead) this.sendStats(player);
		}
		for (const bag of Object.values(s.bags)) {
			if (bag.expires < now) {
				delete s.bags[bag.id];
				this.broadcast({ t: 'bag_gone', id: bag.id });
			}
		}
		for (const [rid, until] of Object.entries(s.depleted)) if (until <= now) delete s.depleted[rid];
		for (const [account, saved] of Object.entries(s.chars)) {
			if (now - saved.savedAt <= CHAR_KEEP_MS) continue;
			delete s.chars[account];
			if (saved.sid) this.broadcast({ t: 'wake', id: saved.sid });
		}
		this.spawnZombies();
		this.broadcast({ t: 'clock', ...this.clock(), online: this.sessions.size, zombies: Object.keys(s.zombies).length });
		this.save(true);
		await this.ctx.storage.setAlarm(now + TICK_MS);
	}

	// ---------------------------------------------------------------- saída ---

	webSocketClose(ws) {
		this.drop_(ws);
	}

	webSocketError(ws) {
		this.drop_(ws);
	}

	drop_(ws) {
		const meta = ws.deserializeAttachment();
		if (!meta?.id || !this.sessions.has(meta.id)) return;
		this.sessions.delete(meta.id);
		const s = this.state;
		const player = s.players[meta.id];
		if (player) {
			this.leaveVehicle(player);
			let sleeper = null;
			if (player.account) {
				sleeper = {
					sid: 'sl' + crypto.randomUUID().slice(0, 8), name: player.name, rank: player.rank,
					p: player.p, y: player.y || 0, hp: player.hp, hunger: player.hunger, thirst: player.thirst,
					inv: player.inv, back: player.back || '', head: player.head || '', chest: player.chest || '', dead: player.dead, savedAt: Date.now(),
					infectedLeft: this.infectionLeft(player),
				};
				s.chars[player.account] = sleeper;
			}
			this.ctx.waitUntil(this.flushXp(player));
			delete s.players[meta.id];
			this.broadcast({ t: 'leave', id: meta.id });
			// Quem saiu vivo fica deitado, dormindo, no lugar onde estava (os outros veem).
			if (sleeper && !sleeper.dead) this.broadcast({ t: 'sleep', ...this.sleeperPacket(sleeper) });
		} else {
			this.broadcast({ t: 'leave', id: meta.id });
		}
		if (s.host === meta.id) {
			s.host = [...this.sessions.keys()][0] || null;
			if (s.host) this.broadcast({ t: 'host', id: s.host });
		}
		this.save(true);
	}
}
