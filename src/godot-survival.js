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
import { BuildGrid } from './godot-building.js';

const ANIMALS = catalog.animals || {};
const ANIMAL = catalog.animal_rules || {};
const BUILD = catalog.build_rules;
const BUILDS = catalog.builds;
/** Folga ao redor de cada recurso com colisão: a fundação não pode cobrir árvore/rocha/arbusto. */
const BLOCKING_RESOURCES = { tree: 0.5, rock: 1.3, ore: 1.3, saltpeter: 1.3, bush: 0.7, car: 2.5 };

/** Marca pública do dono das construções (não expõe a conta): FNV-1a em base 36. */
export function ownerTag(account) {
	let h = 0x811c9dc5;
	for (const ch of String(account || '')) {
		h ^= ch.codePointAt(0);
		h = Math.imul(h, 0x01000193) >>> 0;
	}
	return h.toString(36);
}

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
const WEAPON_DAMAGE = { pistol: 22, bow: 55, smg: 12, rifle: 27, shotgun: 11, sniper: 95 };
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
/** Chance de um zumbi morto deixar a glândula podre. */
export const ZOMBIE_GLAND_CHANCE = 0.3;
/** De dia, zumbis só nas áreas 'day' (cidades), no máximo esta fração da noite. */
const ZOMBIE_DAY_SHARE = 0.5;
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
		// Construções: uma chave por peça ("b:<id>"), fora do estado do mundo (que tem limite de tamanho).
		this.grid = new BuildGrid(BUILD, BUILDS);
		this.buildDirty = new Set();
		this.buildGone = new Set();
		ctx.blockConcurrencyWhile(async () => {
			const saved = await ctx.storage.get('world');
			// Mundo de outra versão (cidade, saque, carros): recomeça como floresta.
			if (saved && saved.version === WORLD_VERSION) {
				this.state = saved;
				if (typeof ctx.storage.list === 'function') {
					for (const piece of (await ctx.storage.list({ prefix: 'b:' })).values()) this.grid.add(piece);
				}
			}
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
			buildSeq: 0, auth: {}, animals: {}, aSeq: 0,
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
		for (const id of this.buildGone) this.ctx.waitUntil(this.ctx.storage.delete('b:' + id));
		for (const id of this.buildDirty) {
			const piece = this.grid.pieces.get(id);
			if (piece) this.ctx.waitUntil(this.ctx.storage.put('b:' + id, piece));
		}
		this.buildGone.clear();
		this.buildDirty.clear();
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
			id, account, tag: ownerTag(account || id), name: url.searchParams.get('name') || 'Sobrevivente', rank: rankFor(totalXp).rank,
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
		// Receitas aprendidas nas páginas do manual ficam até depois da morte.
		const known = Array.isArray(saved.known) ? saved.known.filter((id) => RECIPES[id]?.page) : [];
		if (saved.dead) return { ...this.newCharacter(), inv: {}, dead: true, respawnAt: Date.now(), known };
		// A infecção fica "pausada" enquanto o jogador está fora do jogo.
		const left = Math.max(0, Math.min(INFECTION_MS, Number(saved.infectedLeft) || 0));
		return {
			p: saved.p, y: saved.y || 0, hp: saved.hp, hunger: saved.hunger, thirst: saved.thirst, inv: saved.inv || {}, back: saved.back || '', head: saved.head || '', chest: saved.chest || '', dead: false,
			infectedAt: left > 0 ? Date.now() - (INFECTION_MS - left) : 0, known,
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
			animals: Object.values(s.animals || {}).map((a) => ({ id: a.id, kind: a.kind, hp: a.hp, p: a.p })),
			vehicles: Object.values(this.vehicles()).map((v) => this.vehiclePacket(v)),
			bags: Object.values(s.bags).map((b) => this.bagSummary(b)),
			sleepers: this.sleepers(),
			searched: Object.keys(s.containers).filter((k) => s.containers[k].refillAt > now && !Object.keys(s.containers[k].items).length),
			depleted,
			tag: me.tag,
			builds: [...this.grid.pieces.values()].map((b) => this.buildPacket(b)),
			auth: this.authList(me.tag),
			allowed: this.allowedOwners(me.tag),
		};
	}

	invPacket(player) {
		return { inv: player.inv, back: player.back || '', head: player.head || '', chest: player.chest || '', weight: carriedWeight(player), cap: carryLimit(player.back), known: player.known || [] };
	}

	sendInv(player) {
		this.sendTo(player.id, { t: 'inv', ...this.invPacket(player) });
	}

	sendStats(player) {
		this.sendTo(player.id, { t: 'stats', hp: player.hp, hunger: round1(player.hunger), thirst: round1(player.thirst) });
	}

	bagSummary(bag) {
		return { id: bag.id, p: bag.p, name: bag.name, title: bag.title || '', count: Object.values(bag.items).reduce((a, b) => a + b, 0) };
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
		if (d.t === 'respawn') return this.respawn(me, d, note);
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
					r: !!d.r, c: !!d.c, pr: !!d.pr, a: !!d.a, f: !!d.f, rl: !!d.rl, h: !!d.h, bp: me.back || '', tc: !!d.tc && (me.inv.torch || 0) > 0, dv: me.vehicle || '', ch: characterId(d.ch),
					act: ['chop', 'pry', 'swing', 'open', 'harvest', 'consume', 'bow_draw', 'bow_carry'].includes(d.act) ? d.act : '', tool: typeof d.tool === 'string' && (ITEMS[d.tool]?.melee || ITEMS[d.tool]?.weapon === 'bow') ? d.tool : '',
					charge: finite(d.charge, 1e6) ? Math.max(0, Math.min(1, d.charge)) : 0,
					v: Array.isArray(d.v) && d.v.length === 2 && d.v.every((n) => finite(n, 50)) ? d.v : [0, 0],
				}, me.id);
				return;
			}
			case 'z': return isHost && this.zombieStates(d.l);
			case 'an': return isHost && this.animalStates(d.l);
			case 'ahit': return isHost && this.animalHit(d);
			case 'shot': {
				const o = vec3(d.o, 600);
				const e = vec3(d.e, 1200);
				if (!o || !e) return;
				let arrow = {};
				if (d.w === 'bow') {
					const item = Object.keys(me.inv).find((key) => me.inv[key] > 0 && ITEMS[key]?.weapon === 'bow');
					if (!item || !me.inv[ITEMS[item].ammo] || !this.hitCheck.recordArrow({ attacker: me, id: d.a, origin: o, velocity: d.v })) return;
					arrow = { a: d.a, v: d.v };
				}
				this.broadcastNear(o, { t: 'shot', id: me.id, w: WEAPON_DAMAGE[d.w] ? d.w : 'pistol', o, e, ...arrow }, me.id, INTEREST_RANGE);
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
			case 'build': return this.build(me, d, note);
			case 'bhit': return this.buildHit(me, d);
			case 'zbhit': return isHost && this.zombieBuildHit(d);
			case 'bdel': return this.demolish(me, d, note);
			case 'brep': return this.repairBuild(me, d, note);
			case 'door': return this.toggleDoor(me, d, note);
			case 'fire': return this.toggleFire(me, d, note);
			case 'store': return this.store(me, d, reply, note);
			case 'auth_add': return this.authAdd(me, d, reply, note);
			case 'auth_del': return this.authDel(me, d, reply);
			case 'consume': {
				// Munição gasta na recarga (o jogo avisa quantas balas foram para o pente).
				const item = d.ammo;
				const n = Number.isInteger(d.n) ? Math.max(0, Math.min(d.n, 200)) : 0;
				if ((!item?.startsWith?.('a_') && item !== 'stone_arrow') || !n) return;
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
		if (!weapon || !Object.keys(me.inv).some((item) => me.inv[item] > 0 && ITEMS[item]?.weapon === weapon) || !this.allowHit(me.id)) return;
		let zone = ZONE_MULTIPLIER[d.zone] ? d.zone : 'chest';
		// Alcance da arma; em jogadores, cabeça plausível e taxa de tiros na cabeça.
		const s = this.state;
		const target = s.zombies[d.target] || s.players[d.target] || s.animals?.[d.target];
		if (weapon === 'bow' && !target) return;
		if (target) {
			const args = { attacker: me, target, weapon, zone, point: d.pt, player: !!s.players[d.target] };
			const verdict = weapon === 'bow' ? this.hitCheck.checkArrow({ ...args, id: d.a }) : this.hitCheck.check(args);
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
			// Às vezes o zumbi deixa a glândula podre (soro anti-infecção, mesa de química).
			if (Math.random() < ZOMBIE_GLAND_CHANCE) this.makeBag(zombie.p, { zombie_gland: 1 }, '', 'Restos de zumbi');
			this.save();
			return;
		}
		const animal = s.animals?.[targetId];
		if (animal) {
			if (flat(attacker.p, animal.p) > reach + 2) return;
			return this.hurtAnimal(animal, amount, attacker, zone);
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

	respawn(me, d = {}, note = () => {}) {
		if (!me.dead || Date.now() < me.respawnAt) return;
		// Renascer na cama: a cama tem que estar inteira e descansada.
		let bed = null;
		if (d.bed) {
			bed = this.bedOf(me.tag);
			if (!bed) return note('Você não tem cama. Renasça numa clareira.');
			const wait = Math.ceil(((bed.used || 0) + BUILD.bed_cooldown * 1000 - Date.now()) / 1000);
			if (wait > 0) return note(`A cama ainda não está pronta (${wait} s).`);
			bed.used = Date.now();
			this.buildDirty.add(bed.id);
			this.broadcast({ t: 'bp', b: this.buildPacket(bed) });
		}
		Object.assign(me, this.newCharacter());
		if (bed) me.p = [bed.p[0], bed.p[1] + 0.6, bed.p[2]];
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
		// De dia só há zumbis nas cidades; os do mato somem aos poucos.
		const night = this.isNight();
		const dayZones = (world.zombie_zones || []).filter((z) => z.day);
		const inDayZone = (p) => dayZones.some((z) => Math.hypot(p[0] - z.x, p[2] - z.z) < z.r + 10);
		if (players.length && !night) {
			for (const zombie of Object.values(s.zombies)) {
				if (inDayZone(zombie.p) || Math.random() >= ZOMBIE_DAWN_FADE) continue;
				delete s.zombies[zombie.id];
				gone.push(zombie.id);
			}
		}
		if (gone.length) this.broadcast({ t: 'zgone', l: gone });
		if (!players.length) return;
		// De dia: só nasce zumbi em cidade com alguém por perto.
		const dayPlayers = night ? players : players.filter((p) => dayZones.some((z) => Math.hypot(p.p[0] - z.x, p.p[2] - z.z) < ZOMBIE_SPAWN_MAX + z.r));
		if (!dayPlayers.length) return;
		const full = Math.min(ZOMBIE_MAX, ZOMBIE_BASE + ZOMBIE_PER_PLAYER * players.length);
		const target = night ? full : Math.ceil(full * ZOMBIE_DAY_SHARE);
		const born = [];
		for (let i = 0; i < ZOMBIE_SPAWN_BATCH && count - gone.length + born.length < target; i++) {
			const spot = this.zombieSpot(dayPlayers, !night);
			if (!spot) break;
			const [kind] = weighted(Object.entries(ZOMBIE_KINDS), ([, k]) => k.weight);
			const zombie = { id: 'z' + ++s.zSeq, kind, hp: ZOMBIE_KINDS[kind].hp, p: spot };
			s.zombies[zombie.id] = zombie;
			born.push(zombie);
		}
		if (born.length) this.broadcast({ t: 'zspawn', l: born });
	}

	/** Ponto numa área de zumbis (cidades pesam mais), longe de todos e perto de alguém. */
	zombieSpot(players, dayOnly = false) {
		const zones = world.zombie_zones.filter((z) => (!dayOnly || z.day) && players.some((p) => Math.hypot(p.p[0] - z.x, p.p[2] - z.z) < ZOMBIE_SPAWN_MAX + z.r));
		if (dayOnly && !zones.length) return null;
		for (let attempt = 0; attempt < 12; attempt++) {
			let x;
			let z;
			if (zones.length && (dayOnly || Math.random() < 0.75)) {
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

	// --------------------------------------------------------------- animais ---

	/** Posições vindas do anfitrião: [[id, x, y, z, yaw, anim], ...]. */
	animalStates(list) {
		const s = this.state;
		if (!Array.isArray(list) || !s.animals) return;
		const moved = [];
		for (const entry of list.slice(0, ANIMAL.max || 40)) {
			if (!Array.isArray(entry) || entry.length < 6) continue;
			const animal = s.animals[entry[0]];
			const p = vec3([entry[1], entry[2], entry[3]], 600);
			if (!animal || !p || flat(animal.p, p) > 14) continue; // corre no máximo ~10 m/s
			animal.p = p;
			moved.push([animal.id, p[0], p[1], p[2], finite(entry[4], 100) ? round1(entry[4]) : 0, Number.isInteger(entry[5]) ? entry[5] : 0]);
		}
		if (!moved.length) return;
		for (const [id, ws] of this.sessions) {
			if (id === s.host) continue;
			const viewer = s.players[id];
			const near = viewer?.p ? moved.filter((a) => Math.hypot(a[1] - viewer.p[0], a[3] - viewer.p[2]) < INTEREST_RANGE) : moved;
			if (near.length) this.send(ws, { t: 'an', l: near });
		}
	}

	/** Mordida de lobo / chifrada de javali, relatada pelo anfitrião. */
	animalHit(d) {
		const s = this.state;
		const animal = s.animals?.[d.a];
		const target = s.players[d.target];
		const rule = animal && ANIMALS[animal.kind];
		if (!rule?.damage || !target || target.dead || !this.sessions.has(target.id) || target.vehicle) return;
		const now = Date.now();
		if (now - (animal.lastHit || 0) < (ANIMAL.attack_ms || 1200)) return;
		if (flat(animal.p, target.p) > (ANIMAL.reach || 2.2) + ZOMBIE_REACH_LAG) return;
		animal.lastHit = now;
		this.damagePlayer(target, rule.damage, animal.id, 'a_' + animal.kind);
	}

	/** Golpe/tiro num animal; morto, vira uma carcaça (mochila no chão) com carne e couro. */
	hurtAnimal(animal, amount, attacker, zone = 'chest') {
		const s = this.state;
		animal.hp = Math.max(0, round1(animal.hp - amount));
		if (animal.hp > 0) {
			this.broadcastNear(animal.p, { t: 'ahp', id: animal.id, hp: animal.hp, by: attacker.id, zone });
			return;
		}
		delete s.animals[animal.id];
		const rule = ANIMALS[animal.kind] || {};
		const loot = {};
		for (const [item, [min, max]] of Object.entries(rule.loot || {})) {
			const n = randInt(min, max);
			if (n > 0 && ITEMS[item]) loot[item] = n;
		}
		if (Object.keys(loot).length) this.makeBag(animal.p, loot, '', `Carcaça de ${String(rule.name || 'animal').toLowerCase()}`);
		this.credit(attacker, ANIMAL.xp || 2);
		this.broadcast({ t: 'adead', id: animal.id, by: attacker.id, zone });
		this.save();
	}

	/** Nascem animais em volta dos jogadores (dia e noite) e somem os que ficaram longe de todos. */
	spawnAnimals() {
		const s = this.state;
		if (!s.animals) s.animals = {};
		const players = this.living();
		const gone = [];
		for (const animal of Object.values(s.animals)) {
			if (!players.some((p) => flat(p.p, animal.p) < (ANIMAL.despawn || 180))) {
				delete s.animals[animal.id];
				gone.push(animal.id);
			}
		}
		if (gone.length) this.broadcast({ t: 'agone', l: gone });
		if (!players.length || !Object.keys(ANIMALS).length) return;
		const target = Math.min(ANIMAL.max || 36, (ANIMAL.base || 4) + (ANIMAL.per_player || 3) * players.length);
		const born = [];
		for (let i = 0; i < (ANIMAL.batch || 4) && Object.keys(s.animals).length < target; i++) {
			const spot = this.animalSpot(players);
			if (!spot) break;
			const [kind, rule] = weighted(Object.entries(ANIMALS), ([, r]) => r.weight || 1);
			const group = randInt(rule.group?.[0] || 1, rule.group?.[1] || 1);
			for (let g = 0; g < group && Object.keys(s.animals).length < target; g++) {
				const p = [round1(spot[0] + (Math.random() - 0.5) * 6), 0.2, round1(spot[2] + (Math.random() - 0.5) * 6)];
				const animal = { id: 'a' + ++s.aSeq, kind, hp: rule.hp, p };
				s.animals[animal.id] = animal;
				born.push(animal);
			}
		}
		if (born.length) this.broadcast({ t: 'aspawn', l: born.map((a) => ({ id: a.id, kind: a.kind, hp: a.hp, p: a.p })) });
	}

	/** Ponto no mato a 35–110 m de algum jogador, longe de todos os outros, fora dos lagos. */
	animalSpot(players) {
		const min = ANIMAL.spawn_min || 35;
		const max = ANIMAL.spawn_max || 110;
		for (let attempt = 0; attempt < 10; attempt++) {
			const anchor = players[Math.floor(Math.random() * players.length)];
			const a = Math.random() * Math.PI * 2;
			const d = min + Math.random() * (max - min);
			const p = [round1(anchor.p[0] + Math.cos(a) * d), 0.2, round1(anchor.p[2] + Math.sin(a) * d)];
			if (Math.abs(p[0]) > world.half_size - 8 || Math.abs(p[2]) > world.half_size - 8) continue;
			if ((world.ponds || []).some((pond) => Math.hypot(pond.x - p[0], pond.z - p[2]) < pond.r + 4)) continue;
			if (players.some((pl) => flat(pl.p, p) < min)) continue;
			return p;
		}
		return null;
	}

	// ---------------------------------------------------------- saque e itens ---

	/** Revistar um recipiente do mapa ou uma mochila no chão. */
	search(me, d, reply, note) {
		const s = this.state;
		const chest = this.chestAt(d.k);
		if (chest) {
			if (flat(me.p, chest.p) > REACH) return note('Longe demais.');
			return reply(this.chestPacket(chest));
		}
		const bag = s.bags[d.k];
		if (bag) {
			if (flat(me.p, bag.p) > REACH) return note('Longe demais.');
			return reply({ t: 'container', k: bag.id, title: bag.title || (bag.name ? 'Mochila de ' + bag.name : 'Mochila'), items: bag.items });
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
		const chest = this.chestAt(d.k);
		if (chest) {
			if (flat(me.p, chest.p) > REACH || !ITEMS[d.item]) return;
			const have = chest.items[d.item] || 0;
			const wanted = Number.isInteger(d.n) && d.n > 0 ? Math.min(d.n, have) : have;
			if (!wanted) return;
			const fits = roomFor(me, d.item, wanted);
			if (!fits) return note('Mochila pesada demais.');
			removeItems(chest.items, d.item, fits);
			addItems(me.inv, d.item, fits);
			if (fits < wanted) note('Não coube tudo: mochila pesada demais.');
			this.buildDirty.add(chest.id);
			this.save();
			this.sendInv(me);
			return reply(this.chestPacket(chest));
		}
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
		reply({ t: 'container', k: d.k, title: bag ? bag.title || 'Mochila' + (bag.name ? ' de ' + bag.name : '') : catalog.loot[spot.type]?.name, items });
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
	makeBag(p, items, name, title = '') {
		const s = this.state;
		let bag = title ? null : Object.values(s.bags).find((b) => flat(b.p, p) < 2 && !b.title);
		if (!bag) {
			bag = { id: 'b' + ++s.bagSeq, p: [round1(p[0]), round1(p[1] || 0), round1(p[2])], items: {}, name, expires: 0 };
			if (title) bag.title = title;
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
		// Página do manual: aprende uma receita da era da pólvora que ainda não sabia.
		if (item.read) {
			const known = me.known || (me.known = []);
			const left = catalog.recipes.filter((r) => r.page && !r.soon && !known.includes(r.id));
			if (!left.length) return note('Você já sabe tudo que as páginas ensinam.');
			const learned = left[Math.floor(Math.random() * left.length)];
			removeItems(me.inv, d.item, 1);
			known.push(learned.id);
			this.save();
			this.sendInv(me);
			return note(`Aprendeu a fazer: ${learned.name} (veja no manual, L).`);
		}
		if (item.use.cure && !me.infectedAt) return note('Você não está infectado.');
		if (item.use.hp && !item.use.cure && !item.use.hunger && !item.use.thirst && me.hp >= 100) return note('Vida cheia.');
		removeItems(me.inv, d.item, 1);
		const u = item.use;
		if (u.cure) {
			me.infectedAt = 0;
			this.sendTo(me.id, { t: 'infected', left: 0 });
		}
		if (u.hp > 0) me.hp = Math.min(100, me.hp + u.hp);
		if (u.hunger) me.hunger = Math.max(0, Math.min(100, me.hunger + u.hunger));
		if (u.thirst) me.thirst = Math.max(0, Math.min(100, me.thirst + u.thirst));
		this.save();
		this.sendInv(me);
		this.sendStats(me);
		if (u.hp > 0) this.broadcast({ t: 'hp', id: me.id, hp: me.hp, by: me.id, w: '', zone: null, killed: false });
		// Carne crua faz mal: tira vida (pode matar quem já está fraco).
		if (u.hp < 0) this.damagePlayer(me, -u.hp, me.id, 'raw');
		note(u.hp < 0 ? `Comeu ${item.name.toLowerCase()} e passou mal. Asse na fogueira.` : `Usou ${item.name}.`);
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
		if (recipe.soon) return note('Essa receita ainda não existe no jogo.');
		if (recipe.page && !(me.known || []).includes(recipe.id)) return note('Falta a página do manual dessa receita (ache nas cidades).');
		// Estação (fogueira, bancada, forja...): perto de uma, acesa se ela acende.
		if (recipe.station) {
			const station = BUILDS[recipe.station] || {};
			const near = [...this.grid.pieces.values()].some((b) => b.kind === recipe.station && (!station.lit || b.on) && b.p && flat(b.p, me.p) < REACH && Math.abs(b.p[1] - (me.p[1] || 0)) < 2);
			if (!near) {
				const name = (station.name || 'estação').toLowerCase();
				return note(station.lit ? `Chegue perto de uma ${name} acesa (E acende).` : `Chegue perto de uma ${name}.`);
			}
		}
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
		// Melhor ferramenta do tipo na mochila: 0 = nenhuma, 1 = pedra, 2 = ferro.
		const toolTier = (kind) => Object.keys(me.inv).reduce((best, item) => (ITEMS[item]?.tool === kind ? Math.max(best, ITEMS[item].tier || 1) : best), 0);
		if (rule.needs && !toolTier(rule.needs)) {
			const tool = Object.values(ITEMS).find((item) => item.tool === rule.needs);
			return note(`Precisa de ${tool ? tool.name.toLowerCase() : 'uma ferramenta'}.`);
		}
		// Sem 'needs': qualquer ferramenta do tipo rende mais. Com 'needs': só a de ferro.
		const tooled = rule.needs ? toolTier(rule.needs) >= 2 && !!rule.bonus : rule.tool && toolTier(rule.tool) > 0;
		const [min, max] = tooled ? rule.bonus : rule.base;
		const gained = { [rule.gives]: randInt(min, max) };
		if (rule.extra && Math.random() < rule.extra[1]) gained[rule.extra[0]] = 1;
		// Carro velho: cada peça tem a sua chance (peças, borracha, vidro...).
		for (const [item, chance] of rule.extras || []) if (Math.random() < chance) gained[item] = (gained[item] || 0) + 1;
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

	// ------------------------------------------------------------ construção ---

	buildPacket(b) {
		const out = { id: b.id, kind: b.kind, hp: Math.round(b.hp), ow: b.ow };
		if (b.p) {
			out.p = b.p;
			out.y = b.y || 0;
			if (b.wall) out.wall = true;
		} else {
			Object.assign(out, { i: b.i, j: b.j, k: b.k, r: b.r || 0 });
			if (b.o) out.o = b.o;
		}
		if (b.kind === 'door') out.open = !!b.open;
		if (BUILDS[b.kind]?.lit) out.on = !!b.on;
		if (b.kind === 'bed') out.cd = Math.max(0, Math.ceil(((b.used || 0) + BUILD.bed_cooldown * 1000 - Date.now()) / 1000));
		return out;
	}

	maxHp(b) {
		return BUILDS[b.kind]?.hp || 100;
	}

	/** `tag` pode abrir as portas e construir junto de `owner` (é o dono ou foi autorizado). */
	allowed(owner, tag) {
		return owner === tag || (this.state.auth?.[owner] || []).some((a) => a.tag === tag);
	}

	authList(tag) {
		return (this.state.auth?.[tag] || []).map((a) => ({ tag: a.tag, name: a.name }));
	}

	/** Donos que liberaram a base para `tag`. */
	allowedOwners(tag) {
		return Object.entries(this.state.auth || {}).filter(([, list]) => list.some((a) => a.tag === tag)).map(([owner]) => owner);
	}

	chestAt(id) {
		const b = typeof id === 'string' ? this.grid.pieces.get(id) : null;
		return b?.kind === 'chest' ? b : null;
	}

	chestPacket(chest) {
		if (!chest.items) chest.items = {};
		return { t: 'container', k: chest.id, title: 'Baú', items: chest.items, store: true, cap: BUILDS.chest.carry, weight: inventoryWeight(chest.items) };
	}

	bedOf(tag) {
		for (const b of this.grid.pieces.values()) if (b.kind === 'bed' && b.ow === tag) return b;
		return null;
	}

	countOf(tag) {
		let n = 0;
		for (const b of this.grid.pieces.values()) if (b.ow === tag) n++;
		return n;
	}

	/** Alguém (vivo, no jogo) dentro do espaço que a peça vai ocupar? */
	blockedByPlayer(p) {
		const def = BUILDS[p.kind];
		const S = BUILD.cell;
		for (const pl of this.living()) {
			const [x, y, z] = pl.p;
			if (def.slot === 'free') {
				if (p.wall) continue; // tocha na parede fica acima da cabeça de quem passa
				if (Math.hypot(x - p.p[0], z - p.p[2]) < def.r + 0.25 && Math.abs(y - p.p[1]) < 1.6) return true;
				continue;
			}
			if (def.slot === 'edge') {
				const d = this.grid.distance(p, pl.p);
				if (d !== null && d < 0.45 && y > this.grid.top(p.k) - 1.6 && y < this.grid.top(p.k) + BUILD.story) return true;
				continue;
			}
			if (def.slot !== 'cell') continue;
			const inside = x > p.i * S - 0.3 && x < (p.i + 1) * S + 0.3 && z > p.j * S - 0.3 && z < (p.j + 1) * S + 0.3;
			if (!inside) continue;
			const top = this.grid.top(p.k);
			if (p.kind === 'foundation' ? y < top - 0.05 : y > top - 1.9 && y < top + 0.1) return true;
		}
		return false;
	}

	/** Nada do mapa embaixo (árvore, rocha, arbusto, lago) e dentro do mundo. */
	groundFree(p) {
		const S = BUILD.cell;
		const def = BUILDS[p.kind];
		const half = world.half_size - 6;
		let box;
		if (def.slot === 'free') box = [p.p[0] - def.r, p.p[2] - def.r, p.p[0] + def.r, p.p[2] + def.r];
		else if (p.kind === 'foundation') box = [p.i * S, p.j * S, (p.i + 1) * S, (p.j + 1) * S];
		else return '';
		if (box.some((n) => Math.abs(n) > half)) return 'Fora da área do mundo.';
		for (const pond of world.ponds || []) {
			const dx = Math.max(box[0] - pond.x, 0, pond.x - box[2]);
			const dz = Math.max(box[1] - pond.z, 0, pond.z - box[3]);
			if (Math.hypot(dx, dz) < pond.r + 1) return 'Não dá para construir na água.';
		}
		if (def.slot === 'free' && p.p[1] > 0.25) return ''; // em cima de piso: o chão embaixo não importa
		for (const res of world.resources) {
			const margin = BLOCKING_RESOURCES[res.kind];
			if (margin === undefined) continue;
			if (res.p[0] > box[0] - margin && res.p[0] < box[2] + margin && res.p[2] > box[1] - margin && res.p[2] < box[3] + margin) {
				return `Tem ${String(catalog.resources[res.kind]?.name || 'algo').toLowerCase()} no caminho.`;
			}
		}
		return '';
	}

	/** Coloca uma peça (B): confere lugar, apoio, alcance, espaço e material. */
	build(me, d, note) {
		const def = BUILDS[d.kind];
		if (!def) return;
		if (def.soon) return note('Essa construção ainda não existe no jogo.');
		const s = this.state;
		const p = { kind: d.kind };
		if (def.slot === 'free') {
			p.p = vec3(d.p, 600);
			if (!p.p) return;
			p.y = finite(d.y, 100) ? Math.round(d.y * 100) / 100 : 0;
			if (def.wall && d.wall === true) p.wall = true; // tocha presa na parede
		} else {
			Object.assign(p, { i: d.i, j: d.j, k: d.k, r: Number.isInteger(d.r) ? ((d.r % 4) + 4) % 4 : 0 });
			if (def.slot === 'edge' || def.slot === 'door') p.o = d.o;
		}
		const fail = this.grid.check(p, (b) => this.allowed(b.ow, me.tag));
		if (fail) return note(fail);
		const c = this.grid.center(p);
		if (flat(me.p, c) > BUILD.reach || Math.abs((me.p[1] || 0) - c[1]) > 6) return note('Longe demais.');
		const ground = this.groundFree(p);
		if (ground) return note(ground);
		if (p.kind === 'foundation') {
			for (let di = -1; di <= 1; di++) {
				for (let dj = -1; dj <= 1; dj++) {
					const other = this.grid.at(BuildGrid.cellKey(p.i + di, p.j + dj, 0));
					if (other && !this.allowed(other.ow, me.tag)) return note('Perto demais da base de outro jogador.');
				}
			}
		}
		if (def.slot === 'free') {
			for (const b of this.grid.pieces.values()) {
				if (!b.p || Math.abs(b.p[1] - p.p[1]) > 1) continue;
				if (Math.hypot(b.p[0] - p.p[0], b.p[2] - p.p[2]) < (def.r + (BUILDS[b.kind]?.r || 0.5)) * 0.8) return note('Sem espaço: tem outra coisa aí.');
			}
		}
		if (this.blockedByPlayer(p)) return note('Tem alguém no caminho.');
		if (p.kind === 'bed' && this.bedOf(me.tag)) return note('Você já tem uma cama. Desmonte a outra antes.');
		if (this.countOf(me.tag) >= BUILD.per_player) return note(`Limite de ${BUILD.per_player} peças por jogador.`);
		if (this.grid.pieces.size >= BUILD.per_world) return note('Este mundo já tem construções demais.');
		for (const [item, n] of Object.entries(def.cost)) {
			if ((me.inv[item] || 0) < n) return note(`Falta ${ITEMS[item]?.name || item} (${me.inv[item] || 0}/${n}).`);
		}
		for (const [item, n] of Object.entries(def.cost)) removeItems(me.inv, item, n);
		s.buildSeq = (s.buildSeq || 0) + 1;
		Object.assign(p, { id: 'P' + s.buildSeq, hp: def.hp, ow: me.tag, at: Date.now() });
		if (p.kind === 'chest') p.items = {};
		this.grid.add(p);
		this.buildDirty.add(p.id);
		this.save();
		this.sendInv(me);
		this.broadcast({ t: 'bp', b: this.buildPacket(p) });
	}

	damageBuild(b, amount, by = '') {
		if (!(amount > 0) || !this.grid.pieces.has(b.id)) return;
		b.hp = Math.max(0, round1(b.hp - amount));
		b.hitAt = Date.now();
		if (b.hp > 0) {
			this.buildDirty.add(b.id);
			this.broadcastNear(this.grid.center(b), { t: 'bhp', id: b.id, hp: Math.round(b.hp), by });
			return;
		}
		this.destroyBuild(b, by);
	}

	/** Some a peça e o que ela segurava; o que estava nos baús cai numa mochila no chão. */
	destroyBuild(b, by = '') {
		const gone = this.grid.remove(b.id);
		for (const piece of gone) {
			this.buildGone.add(piece.id);
			this.buildDirty.delete(piece.id);
			if (piece.kind === 'chest' && piece.items && Object.keys(piece.items).length) this.makeBag(piece.p, piece.items, '');
		}
		if (gone.length) this.broadcast({ t: 'bgone', l: gone.map((p) => p.id), by });
		this.save();
		return gone;
	}

	/** Golpe de jogador (Q) numa peça: machado rende mais; soco quase nada. */
	buildHit(me, d) {
		const b = this.grid.pieces.get(d.b);
		if (!b || !this.allowHit(me.id)) return;
		const dist = this.grid.distance(b, me.p);
		if (dist === null || dist > MELEE_REACH + 0.6) return;
		const now = Date.now();
		if (now - (me.bhitAt || 0) < 450) return; // o golpe tem recarga de 0,6 s
		me.bhitAt = now;
		const item = typeof d.item === 'string' && me.inv[d.item] && ITEMS[d.item]?.melee ? d.item : '';
		const amount = item ? ITEMS[item].melee * (ITEMS[item].tool === 'wood' ? BUILD.axe_factor : BUILD.melee_factor) : BUILD.fist;
		this.damageBuild(b, amount, me.id);
	}

	/** Zumbi batendo numa parede/porta (relatado pelo anfitrião). */
	zombieBuildHit(d) {
		const zombie = this.state.zombies[d.z];
		const b = this.grid.pieces.get(d.b);
		if (!zombie || !b) return;
		const now = Date.now();
		if (now - (zombie.lastBHit || 0) < ZOMBIE_ATTACK_MS) return;
		const dist = this.grid.distance(b, zombie.p);
		if (dist === null || dist > ZOMBIE_REACH + 0.8) return;
		zombie.lastBHit = now;
		this.damageBuild(b, (ZOMBIE_KINDS[zombie.kind]?.damage || 9) * BUILD.zombie_factor, zombie.id);
	}

	/** Desmontar (só o dono): devolve parte do material, proporcional à vida da peça. */
	demolish(me, d, note) {
		const b = this.grid.pieces.get(d.b);
		if (!b) return;
		if (b.ow !== me.tag) return note('Só o dono pode desmontar.');
		if (flat(me.p, this.grid.center(b)) > BUILD.reach) return note('Longe demais.');
		const frac = b.hp / this.maxHp(b);
		const back = {};
		for (const [item, n] of Object.entries(BUILDS[b.kind].cost)) {
			const got = Math.floor(n * BUILD.refund * frac);
			if (got > 0) back[item] = got;
		}
		const spill = {};
		for (const [item, n] of Object.entries(back)) {
			const fits = roomFor(me, item, n);
			addItems(me.inv, item, fits);
			if (fits < n) spill[item] = n - fits;
		}
		if (Object.keys(spill).length) this.makeBag(me.p, spill, me.name);
		const gone = this.destroyBuild(b, me.id);
		this.sendInv(me);
		const list = Object.entries(back).map(([item, n]) => `${ITEMS[item]?.name || item} +${n}`).join(', ');
		note('Desmontou ' + BUILDS[b.kind].name.toLowerCase() + (list ? `: ${list}` : '') + (gone.length > 1 ? ` (${gone.length - 1} peça(s) caíram junto)` : '') + '.');
	}

	/** Consertar: dono ou autorizado, fora de ataque; custa parte do material. */
	repairBuild(me, d, note) {
		const b = this.grid.pieces.get(d.b);
		if (!b) return;
		if (!this.allowed(b.ow, me.tag)) return note('Essa construção é de outro jogador.');
		if (flat(me.p, this.grid.center(b)) > BUILD.reach) return note('Longe demais.');
		const max = this.maxHp(b);
		if (b.hp >= max) return note('Não precisa de conserto.');
		const wait = Math.ceil(((b.hitAt || 0) + BUILD.repair_wait * 1000 - Date.now()) / 1000);
		if (wait > 0) return note(`Sob ataque: espere ${wait} s para consertar.`);
		const missing = 1 - b.hp / max;
		const cost = {};
		for (const [item, n] of Object.entries(BUILDS[b.kind].cost)) cost[item] = Math.max(1, Math.ceil(n * missing * BUILD.refund));
		for (const [item, n] of Object.entries(cost)) {
			if ((me.inv[item] || 0) < n) return note(`Para consertar falta ${ITEMS[item]?.name || item} (${me.inv[item] || 0}/${n}).`);
		}
		for (const [item, n] of Object.entries(cost)) removeItems(me.inv, item, n);
		b.hp = max;
		this.buildDirty.add(b.id);
		this.save();
		this.sendInv(me);
		this.broadcastNear(this.grid.center(b), { t: 'bhp', id: b.id, hp: max, by: me.id });
		note(`Consertou ${BUILDS[b.kind].name.toLowerCase()}.`);
	}

	toggleDoor(me, d, note) {
		const b = this.grid.pieces.get(d.b);
		if (b?.kind !== 'door') return;
		const dist = this.grid.distance(b, me.p);
		if (dist === null || dist > REACH) return note('Longe demais.');
		if (!this.allowed(b.ow, me.tag)) return note('Porta trancada.');
		b.open = !b.open;
		this.buildDirty.add(b.id);
		this.save();
		this.broadcast({ t: 'bp', b: this.buildPacket(b) });
	}

	toggleFire(me, d, note) {
		const b = this.grid.pieces.get(d.b);
		if (!b || !BUILDS[b.kind]?.lit) return;
		if (flat(me.p, b.p) > REACH) return note('Longe demais.');
		b.on = !b.on;
		this.buildDirty.add(b.id);
		this.save();
		this.broadcast({ t: 'bp', b: this.buildPacket(b) });
	}

	/** Guardar itens no baú (até a carga do baú). */
	store(me, d, reply, note) {
		const chest = this.chestAt(d.k);
		if (!chest || !ITEMS[d.item]) return;
		if (flat(me.p, chest.p) > REACH) return note('Longe demais.');
		if (!chest.items) chest.items = {};
		const have = me.inv[d.item] || 0;
		const wanted = Number.isInteger(d.n) && d.n > 0 ? Math.min(d.n, have) : have;
		if (!wanted) return;
		const unit = ITEMS[d.item].weight || 0;
		const free = BUILDS.chest.carry - inventoryWeight(chest.items);
		const fits = unit > 0 ? Math.max(0, Math.min(wanted, Math.floor((free + 1e-6) / unit))) : wanted;
		if (!fits) return note('O baú está cheio.');
		removeItems(me.inv, d.item, fits);
		addItems(chest.items, d.item, fits);
		if (fits < wanted) note('Não coube tudo: o baú está cheio.');
		this.buildDirty.add(chest.id);
		this.save();
		this.sendInv(me);
		reply(this.chestPacket(chest));
	}

	/** Libera a base (portas e construir junto) para quem está a até 6 m. */
	authAdd(me, d, reply, note) {
		const s = this.state;
		if (!s.auth) s.auth = {};
		const list = s.auth[me.tag] || (s.auth[me.tag] = []);
		const added = [];
		for (const pl of this.living()) {
			if (pl.id === me.id || pl.tag === me.tag || flat(pl.p, me.p) > 6) continue;
			if (list.some((a) => a.tag === pl.tag)) continue;
			if (list.length >= BUILD.auth_max) {
				note(`Limite de ${BUILD.auth_max} pessoas liberadas.`);
				break;
			}
			list.push({ tag: pl.tag, name: pl.name });
			added.push(pl);
		}
		if (!added.length) note('Ninguém novo por perto (chegue a até 6 m da pessoa).');
		else note('Base liberada para: ' + added.map((pl) => pl.name).join(', ') + '.');
		for (const pl of added) {
			this.sendTo(pl.id, { t: 'allowed', l: this.allowedOwners(pl.tag) });
			this.sendTo(pl.id, { t: 'note', message: `${me.name} liberou a base para você (portas e construir junto).` });
		}
		this.save();
		reply({ t: 'auth', l: this.authList(me.tag) });
	}

	authDel(me, d, reply) {
		const list = this.state.auth?.[me.tag];
		if (!list || typeof d.tag !== 'string') return;
		this.state.auth[me.tag] = list.filter((a) => a.tag !== d.tag);
		if (!this.state.auth[me.tag].length) delete this.state.auth[me.tag];
		for (const pl of Object.values(this.state.players)) {
			if (pl.tag === d.tag) this.sendTo(pl.id, { t: 'allowed', l: this.allowedOwners(pl.tag) });
		}
		this.save();
		reply({ t: 'auth', l: this.authList(me.tag) });
	}

	// ------------------------------------------------------------- relógio ---

	async alarm() {
		const s = this.state;
		const now = Date.now();
		if (!this.sessions.size) {
			// Mundo vazio: os zumbis somem; personagens e recipientes ficam guardados.
			s.zombies = {};
			s.animals = {};
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
		this.spawnAnimals();
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
					infectedLeft: this.infectionLeft(player), known: player.known || [],
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
