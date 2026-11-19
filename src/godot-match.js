// Multiplayer for the Godot build (itch.io web + Windows download).
// One Durable Object instance acts as the matchmaker ("godot-matchmaker");
// every other instance is an 8-player elimination match ("match:<code>") or a
// custom team room created with a shareable code ("party:<code>", 2x2 or 4x4).
// Rooms never start on a timer: players confirm "ready" and the first player
// in the room (the leader) starts the match; empty slots are filled with bots. Bots are simulated by one human client
// (the "host") so they respect the Godot map collision; the server owns
// every health value and decides the winner.

// Spawns (one per building) and loot spots, shared with the Godot client.
import layout from '../godot/data/match_layout.json' with { type: 'json' };
import { resolveSession, rankFor, XP_REWARDS } from './godot-accounts.js';
import { HitCheck, stanceOf } from './godot-hitcheck.js';

const CAPACITY = 8;
// Shop (no loot crates in these modes): everyone gets START_CREDITS and may buy
// only during the first BUY_WINDOW_MS of the match (and of every respawn in
// mata-mata). Kills earn credits. A weapon comes with RESERVE_AMMO.
const SHOP_PRICES = { pistol: 200, smg: 1200, shotgun: 1400, rifle: 2200, sniper: 3200, medkit: 300, grenade: 300 };
const START_CREDITS = 800;
const BUY_WINDOW_MS = 20000;
const KILL_CREDITS = { player: 400, bot: 200, headshot: 100 };
const MAX_CREDITS = 16000;
// Bots do not shop: they get a random weapon (and one medkit) when they spawn.
const LOOT_WEIGHTS = [['pistol', 30], ['smg', 24], ['rifle', 20], ['shotgun', 16], ['sniper', 10]];
const RESERVE_AMMO = { pistol: 45, smg: 90, rifle: 90, shotgun: 18, sniper: 15 };
const MEDKIT_HEAL = 50; // health restored by a medkit (max 100)
const MAX_MEDKITS = 5; // medkits a player can carry
const MEDKIT_USE_MS = 3000; // using a medkit takes 3 s (heal_start -> heal)
// Grenades: bought in the shop (G throws). The thrower's client simulates the
// flight and reports where it exploded; the server checks it and deals
// distance-based damage to everyone in the blast.
const MAX_NADES = 3;
const GRENADE_RADIUS = 7; // metres
const GRENADE_MAX_DAMAGE = 100; // at the centre, falling to 0 at the radius
const GRENADE_RANGE = 45; // max ground distance from the throw to the blast
const GRENADE_FUSE_MS = [1200, 8000]; // accepted time between throw and blast
const MAX_MATCH_MS = 8 * 60 * 1000;
const CLOSE_AFTER_END_MS = 15000;
// Per-hit damage caps (one pellet). Matches godot/scripts/weapon_data.gd.
const WEAPON_DAMAGE = { pistol: 22, smg: 12, rifle: 27, shotgun: 11, sniper: 95 };
const FIST_DAMAGE = 15; // soco (×1,5 na cabeça)
const PUNCH_REACH = 3.2; // metros entre os dois (folga para o atraso da rede)
const PUNCH_COOLDOWN_MS = 550;
// Body-part multipliers. Matches godot/scripts/net/hitbox.gd.
const ZONE_MULTIPLIER = { head: 2.0, chest: 1.0, pelvis: 0.9, arm: 0.7, leg: 0.7 };
const BOT_DAMAGE = 14;
const MAX_HITS_PER_SECOND = 18; // shotgun fires 8 pellets per shot
const BOT_NAMES = ['Cabo Rocha', 'Sgt. Lima', 'Recruta Dias', 'Ten. Faria', 'Cabo Nunes', 'Sgt. Prado', 'Soldado Reis', 'Cabo Vidal'];
// Custom rooms ("party:<code>"): two teams of 2 or 4, created by a leader who
// shares the code with friends. Teams spawn far apart, two per building:
// Alfa in MERCADO/OFICINA (south-west), Bravo in GALPAO/ESCRITORIO (north-east).
const TEAM_NAMES = ['Alfa', 'Bravo'];
const TEAM_BUILDINGS = [[4, 5], [6, 7]];
const TEAM_SIZES = [2, 4];
// Mata-mata ("mode=dm"): same 8-player public rooms, but nobody stays dead.
// You respawn after a few seconds with a free pistol in the building farthest
// from the others, and the shop opens again; the first to DM_KILL_GOAL kills
// (or the most kills when time runs out) wins. Dying costs no XP here.
const DM_KILL_GOAL = 15;
const DM_MATCH_MS = 6 * 60 * 1000;
const DM_RESPAWN_MS = 3000;
const DM_SPAWN_PROTECT_MS = 1500; // invulnerable right after respawning (until you attack)
const DM_KIT = 'pistol';
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function newPartyCode() {
	let code = '';
	for (const byte of crypto.getRandomValues(new Uint8Array(5))) code += CODE_CHARS[byte % CODE_CHARS.length];
	return code;
}

/** Spawn for the k-th member of a team: two per building, side by side. */
function teamSpawn(team, k) {
	const building = layout.buildings[TEAM_BUILDINGS[team][Math.floor(k / 2) % 2]];
	return [building.spawn[0] + (k % 2 ? 1.2 : -1.2), 0, building.spawn[1]];
}

function rollWeapon() {
	const total = LOOT_WEIGHTS.reduce((sum, [, weight]) => sum + weight, 0);
	let pick = Math.random() * total;
	for (const [weapon, weight] of LOOT_WEIGHTS) {
		pick -= weight;
		if (pick < 0) return weapon;
	}
	return 'pistol';
}

const flatDistance = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);

/** Uniform shuffle (Fisher–Yates). sort(() => Math.random() - 0.5) is heavily
 * biased on small arrays and kept the first player in the first house. */
function shuffle(list) {
	for (let i = list.length - 1; i > 0; i--) {
		const j = Math.floor(Math.random() * (i + 1));
		[list[i], list[j]] = [list[j], list[i]];
	}
	return list;
}

function json(data, status = 200) {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
	});
}

const finite = (v, limit) => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= limit;
const vec3 = (v, limit) => (Array.isArray(v) && v.length === 3 && v.every((n) => finite(n, limit)) ? v.map((n) => Math.round(n * 100) / 100) : null);
/** Visible character id (godot/characters/*.tres): short slug or '' (others then show the default). */
const characterId = (v) => (typeof v === 'string' && /^[a-z0-9_]{1,32}$/.test(v) ? v : '');

/** Copy only known animation/state fields from a client packet. */
function cleanState(d) {
	const p = vec3(d.p, 500);
	if (!p) return null;
	const v = Array.isArray(d.v) && d.v.length === 2 && d.v.every((n) => finite(n, 50)) ? d.v : [0, 0];
	return {
		p,
		y: finite(d.y, 1000) ? d.y : 0,
		pi: finite(d.pi, 2) ? d.pi : 0,
		w: WEAPON_DAMAGE[d.w] ? d.w : 'rifle',
		m: finite(d.m, 1) ? Math.max(0, d.m) : 0,
		r: !!d.r,
		c: !!d.c,
		pr: !!d.pr, // prone (lying down): without it the others saw you standing
		a: !!d.a,
		f: !!d.f,
		rl: !!d.rl,
		h: !!d.h, // holstered / no weapon yet
		l: finite(d.l, 1) ? Math.round(d.l * 100) / 100 : 0, // lean (Q/E while aiming): -1 left .. 1 right
		ch: characterId(d.ch),
		v,
	};
}

/**
 * Client builds below GODOT_MIN_BUILD (wrangler.jsonc vars) are told to update.
 * Build numbers come from the game version: 0.1.0 -> 100, 1.2.3 -> 10203.
 * The socket is accepted only to deliver the message, then closed.
 */
function outdatedSocket(env, build) {
	return noticeSocket({
		t: 'outdated',
		build,
		min: Number(env.GODOT_MIN_BUILD) || 0,
		url: String(env.GODOT_DOWNLOAD_URL || ''),
		message: 'Há uma nova versão do Campo de Fogo. Atualize para jogar online.',
	});
}

/** Accept a socket only to deliver one message (update needed, login needed), then close. */
function noticeSocket(message) {
	const pair = new WebSocketPair();
	const [client, server] = [pair[0], pair[1]];
	server.accept();
	server.send(JSON.stringify(message));
	// Godot drops packets that arrive together with the close frame, so give the
	// client time to read the message (it closes on its own after reading).
	setTimeout(() => {
		try {
			server.close(4000, 'outdated');
		} catch {}
	}, 2000);
	return new Response(null, { status: 101, webSocket: client });
}

/** Route used by the public Worker: /godot/ws → matchmaker → match room. */
export async function handleGodotSocket(request, env, url) {
	if (request.headers.get('Upgrade') !== 'websocket') return new Response('WebSocket required', { status: 426 });
	const build = Number.parseInt(url.searchParams.get('v') || '0', 10) || 0;
	if (build < (Number(env.GODOT_MIN_BUILD) || 0)) return outdatedSocket(env, build);
	// Online play needs an account: the name and XP come from the session.
	const header = request.headers.get('Authorization') || '';
	const token = header.startsWith('Bearer ') ? header.slice(7).trim() : url.searchParams.get('token') || '';
	const session = await resolveSession(env, token);
	if (!session) return noticeSocket({ t: 'auth', message: 'Entre na sua conta para jogar online.' });
	const party = (url.searchParams.get('party') || '').trim().toUpperCase();
	if (party) return joinParty(request, env, session, party);
	const invited = (url.searchParams.get('elim') || '').trim().toLowerCase();
	if (invited) return joinInvitedElimination(request, env, session, invited);
	const matchmaker = env.GODOT_MATCHES.get(env.GODOT_MATCHES.idFromName('godot-matchmaker'));
	const name = session.name;
	// Mata-mata has its own queue; its rooms are "match:<id>" too, so friend invites work the same.
	const mode = url.searchParams.get('mode') === 'dm' ? 'dm' : '';
	let full = '';
	for (let attempt = 0; attempt < 3; attempt++) {
		const query = [mode && 'mode=' + mode, full && 'full=' + encodeURIComponent(full)].filter(Boolean).join('&');
		const assigned = await matchmaker.fetch('https://internal/assign' + (query ? '?' + query : ''));
		const { room } = await assigned.json();
		const stub = env.GODOT_MATCHES.get(env.GODOT_MATCHES.idFromName('match:' + room));
		const target =
			'https://internal/join?room=' + encodeURIComponent(room) + '&name=' + encodeURIComponent(name) +
			'&account=' + encodeURIComponent(session.account) + '&xp=' + encodeURIComponent(session.xp) + (mode ? '&mode=' + mode : '');
		const response = await stub.fetch(new Request(target, request));
		if (response.status === 101) return response;
		full = room; // started or full in the meantime: ask for a fresh room
	}
	return new Response('Nenhuma sala disponível. Tente novamente.', { status: 503 });
}

/** Convite de amigo para a sala de espera de uma eliminatória pública (elim=<sala>). */
async function joinInvitedElimination(request, env, session, room) {
	if (!/^[0-9a-f]{6}$/.test(room)) return noticeSocket({ t: 'party_error', message: 'Convite inválido.' });
	const stub = env.GODOT_MATCHES.get(env.GODOT_MATCHES.idFromName('match:' + room));
	const target =
		'https://internal/join?invite=1&room=' + room + '&name=' + encodeURIComponent(session.name) +
		'&account=' + encodeURIComponent(session.account) + '&xp=' + encodeURIComponent(session.xp);
	const response = await stub.fetch(new Request(target, request));
	if (response.status === 101) return response;
	const reason = await response.text();
	const message = /andamento/.test(reason) ? 'A partida dessa eliminatória já começou.' : /cheia/i.test(reason) ? 'A sala de eliminatória está cheia.' : reason;
	return noticeSocket({ t: 'party_error', message });
}

/** Custom room: party=NEW creates one with a fresh code, party=<code> joins it. */
async function joinParty(request, env, session, party) {
	const creating = party === 'NEW';
	if (!creating && !/^[A-Z0-9]{5}$/.test(party)) return noticeSocket({ t: 'party_error', message: 'Código inválido. Ele tem 5 letras/números.' });
	for (let attempt = 0; attempt < (creating ? 4 : 1); attempt++) {
		const code = creating ? newPartyCode() : party;
		const stub = env.GODOT_MATCHES.get(env.GODOT_MATCHES.idFromName('party:' + code));
		const target =
			'https://internal/join?party=1' + (creating ? '&create=1' : '') + '&room=' + code + '&name=' + encodeURIComponent(session.name) +
			'&account=' + encodeURIComponent(session.account) + '&xp=' + encodeURIComponent(session.xp);
		const response = await stub.fetch(new Request(target, request));
		if (response.status === 101) return response;
		if (creating && response.status === 409) continue; // code in use: draw another
		return noticeSocket({ t: 'party_error', message: await response.text() });
	}
	return noticeSocket({ t: 'party_error', message: 'Não foi possível criar a sala. Tente novamente.' });
}

export class GodotMatch {
	constructor(ctx, env) {
		this.ctx = ctx;
		this.env = env;
		this.sessions = new Map(); // player id -> WebSocket
		this.hitLog = new Map(); // attacker id -> recent hit timestamps
		this.hitCheck = new HitCheck(); // alcance, cabeça plausível e taxa de tiros na cabeça
		this.match = this.fresh('');
		ctx.blockConcurrencyWhile(async () => {
			const saved = await ctx.storage.get('match');
			if (saved) this.match = saved;
			for (const ws of ctx.getWebSockets()) {
				const meta = ws.deserializeAttachment();
				if (meta?.id) this.sessions.set(meta.id, ws);
			}
		});
	}

	fresh(room) {
		return {
			room, phase: 'waiting', deadline: 0, startedAt: 0, players: {}, order: [], host: null, winner: null, crates: {}, dropSeq: 0,
			// Custom rooms only.
			party: false, leader: null, size: 2, bots: true, winnerTeam: null, grenades: {},
			mode: 'elim', // public rooms: 'elim' (one life) or 'dm' (mata-mata, respawn)
		};
	}

	isDm() {
		return !this.match.party && this.match.mode === 'dm';
	}

	matchLength() {
		return this.isDm() ? DM_MATCH_MS : MAX_MATCH_MS;
	}

	capacity() {
		return this.match.party ? this.match.size * 2 : CAPACITY;
	}

	teamCount(team) {
		return this.humans().filter((p) => p.team === team).length;
	}

	save() {
		this.ctx.waitUntil(this.ctx.storage.put('match', this.match));
	}

	send(ws, data) {
		try {
			ws.send(JSON.stringify(data));
		} catch {}
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

	humans() {
		return Object.values(this.match.players).filter((p) => !p.bot);
	}

	alive() {
		return this.match.order.filter((id) => this.match.players[id] && !this.match.players[id].dead);
	}

	async fetch(request) {
		const url = new URL(request.url);
		if (url.pathname === '/assign') return this.assign(url);
		if (url.pathname !== '/join') return new Response('Not found', { status: 404 });
		if (request.headers.get('Upgrade') !== 'websocket') return new Response('WebSocket required', { status: 426 });
		const isParty = url.searchParams.get('party') === '1';
		if (isParty && url.searchParams.get('create') === '1') {
			if (this.sessions.size) return new Response('Código em uso', { status: 409 });
			this.match = this.fresh(url.searchParams.get('room') || '');
			this.match.party = true;
		} else if (isParty && (!this.match.party || !this.sessions.size)) {
			return new Response('Sala não encontrada. Confira o código com quem criou.', { status: 404 });
		} else if (url.searchParams.get('invite') === '1' && (this.match.party || !this.sessions.size)) {
			// Convite para uma eliminatória: só entra se a sala ainda existe (alguém dentro).
			return new Response('Essa sala de eliminatória não existe mais.', { status: 404 });
		}
		const m = this.match;
		if (!isParty && url.searchParams.get('invite') !== '1') {
			// The first player of a public room sets its mode; the matchmaker never mixes queues.
			const mode = url.searchParams.get('mode') === 'dm' ? 'dm' : 'elim';
			if (!this.sessions.size && m.phase === 'waiting') m.mode = mode;
			else if ((m.mode || 'elim') !== mode) return new Response('Sala de outro modo', { status: 409 });
		}
		if (m.phase !== 'waiting') return new Response(m.party ? 'A partida desta sala já começou.' : 'Partida em andamento', { status: 409 });
		if (this.sessions.size >= this.capacity()) return new Response(m.party ? 'A sala está cheia.' : 'Sala cheia', { status: 409 });
		const account = url.searchParams.get('account') || '';
		if (account && Object.values(m.players).some((p) => p.account === account)) return new Response(m.party ? 'Sua conta já está nesta sala.' : 'Conta já está nesta sala', { status: 409 });
		if (!m.room) m.room = url.searchParams.get('room') || '';

		const pair = new WebSocketPair();
		const [client, server] = [pair[0], pair[1]];
		const id = crypto.randomUUID().slice(0, 8);
		this.ctx.acceptWebSocket(server);
		server.serializeAttachment({ id });
		this.sessions.set(id, server);
		const totalXp = Math.max(0, Number(url.searchParams.get('xp')) || 0);
		m.players[id] = {
			id, name: url.searchParams.get('name') || 'Operador', bot: false, hp: 100, dead: false, kills: 0, spawn: 0,
			account, totalXp, rank: rankFor(totalXp).rank, xpGain: 0, playerKills: 0, botKills: 0, flushed: false, ready: false,
		};
		// No countdown in any room: players confirm "ready" and the first player
		// in the room (the leader) starts the match. Team rooms: join the smaller team.
		if (!m.leader) m.leader = id;
		if (m.party) m.players[id].team = this.teamCount(0) <= this.teamCount(1) ? 0 : 1;
		this.save();
		this.send(server, { t: 'welcome', id, room: m.room, party: m.party, mode: m.mode || 'elim', lobby: true, code: m.party ? m.room : '', capacity: this.capacity() });
		this.broadcastParty();
		return new Response(null, { status: 101, webSocket: client });
	}

	/**
	 * Matchmaker: hand out the current open public room. A room stays open until
	 * its leader starts it or it fills up; the join then answers 409 and the
	 * caller asks again with full=<room>, which opens a new one.
	 */
	async assign(url) {
		const key = url.searchParams.get('mode') === 'dm' ? 'mm_dm' : 'mm';
		let mm = await this.ctx.storage.get(key);
		const full = url.searchParams.get('full');
		if (!mm || (full && full === mm.room)) mm = { room: crypto.randomUUID().slice(0, 6), openedAt: Date.now() };
		await this.ctx.storage.put(key, mm);
		return json({ room: mm.room });
	}

	/** Not ready yet: everyone except the leader (whose "start" is the confirmation). */
	waitingOn() {
		return this.humans().filter((p) => p.id !== this.match.leader && !p.ready);
	}

	/** Room lobby (public elimination or team room): settings, players and who is ready. */
	broadcastParty() {
		const m = this.match;
		this.broadcast({
			t: 'party',
			party: m.party,
			mode: m.mode || 'elim',
			goal: this.isDm() ? DM_KILL_GOAL : undefined,
			code: m.party ? m.room : '',
			leader: m.leader,
			size: m.size,
			bots: m.bots,
			capacity: this.capacity(),
			teams: TEAM_NAMES,
			allReady: this.waitingOn().length === 0,
			players: this.humans().map((p) => ({ id: p.id, name: p.name, rank: p.rank, team: p.team, ready: !!p.ready || p.id === m.leader })),
		});
	}

	/** Lobby actions: ready up, pick a team (team rooms); the leader sets the mode and starts. */
	partyMessage(id, d, ws) {
		const m = this.match;
		const me = m.players[id];
		const note = (message) => this.send(ws, { t: 'party_note', message });
		switch (d.t) {
			case 'ready': {
				me.ready = d.ready !== false;
				break;
			}
			case 'team': {
				if (!m.party) return;
				const team = d.team === 1 ? 1 : 0;
				if (me.team === team) return;
				if (this.teamCount(team) >= m.size) return note(`A equipe ${TEAM_NAMES[team]} está cheia.`);
				me.team = team;
				me.ready = false; // confirm again on the new team
				break;
			}
			case 'config': {
				if (id !== m.leader || !m.party) return;
				const size = TEAM_SIZES.includes(d.size) ? d.size : m.size;
				if (this.teamCount(0) > size || this.teamCount(1) > size) return note(`Cada equipe pode ter no máximo ${size} jogadores em ${size}x${size}. Alguém precisa sair ou trocar de equipe.`);
				m.size = size;
				if (typeof d.bots === 'boolean') m.bots = d.bots;
				break;
			}
			case 'start': {
				if (id !== m.leader) return;
				const waiting = this.waitingOn();
				if (waiting.length) return note(`Aguardando ${waiting.map((p) => p.name).join(', ')} confirmar pronto.`);
				if (m.party && !m.bots && (!this.teamCount(0) || !this.teamCount(1))) return note('Sem bots, as duas equipes precisam ter pelo menos um jogador.');
				return this.start();
			}
			default:
				return;
		}
		this.save();
		this.broadcastParty();
	}

	start() {
		const m = this.match;
		if (m.phase !== 'waiting') return;
		const humans = this.humans().map((p) => p.id);
		if (!humans.length) return this.reset();
		if (m.party) {
			// Teams: fill each side with bots up to the team size (when enabled).
			let n = 0;
			for (const team of [0, 1]) {
				for (let k = this.teamCount(team); m.bots && k < m.size; k++, n++) {
					const id = 'bot' + (n + 1);
					m.players[id] = { id, name: BOT_NAMES[n % BOT_NAMES.length], bot: true, hp: 100, dead: false, kills: 0, spawn: 0, team };
				}
			}
			m.order = Object.keys(m.players);
			// Random side of the map for each team, random spot inside it.
			const sides = Math.random() < 0.5 ? [0, 1] : [1, 0];
			const slots = [0, 1].map(() => shuffle([0, 1, 2, 3]));
			const seen = [0, 0];
			for (const id of m.order) {
				const player = m.players[id];
				const side = sides[player.team];
				const k = slots[player.team][seen[player.team]++ % 4];
				player.spawn = TEAM_BUILDINGS[side][Math.floor(k / 2) % 2];
				player.p = teamSpawn(side, k);
				player.inv = {};
			}
		} else {
			for (let n = 0; humans.length + n < CAPACITY; n++) {
				const id = 'bot' + (n + 1);
				m.players[id] = { id, name: BOT_NAMES[n % BOT_NAMES.length], bot: true, hp: 100, dead: false, kills: 0, spawn: 0 };
			}
			m.order = Object.keys(m.players);
			// One building each, shuffled; everyone starts indoors and unarmed.
			const spawns = shuffle([...Array(layout.buildings.length).keys()]);
			m.order.forEach((id, i) => {
				const player = m.players[id];
				player.spawn = spawns[i];
				const at = layout.buildings[spawns[i] % layout.buildings.length].spawn;
				player.p = [at[0], 0, at[1]];
				player.inv = {};
			});
		}
		const now = Date.now();
		for (const id of m.order) {
			const p = m.players[id];
			Object.assign(p, { medkits: 0, nades: 0, deaths: 0, respawnAt: 0, credits: START_CREDITS, buyUntil: now + BUY_WINDOW_MS });
			// Mata-mata: a free pistol at the start and on every respawn.
			if (this.isDm()) p.inv = { [DM_KIT]: true };
			if (p.bot) this.armBot(p);
		}
		m.grenades = {};
		m.crates = {}; // no loot crates: weapons come from the shop
		m.phase = 'running';
		m.startedAt = now;
		m.host = m.party && m.leader && this.sessions.has(m.leader) ? m.leader : humans[0];
		this.save();
		this.broadcast({
			t: 'start',
			host: m.host,
			alive: m.order.length,
			party: m.party,
			mode: m.mode || 'elim',
			goal: this.isDm() ? DM_KILL_GOAL : undefined,
			duration: this.matchLength(),
			respawn: this.isDm() ? DM_RESPAWN_MS : undefined,
			kit: this.isDm() ? { [DM_KIT]: RESERVE_AMMO[DM_KIT] } : undefined,
			teams: m.party ? TEAM_NAMES : undefined,
			roster: m.order.map((id) => {
				const p = m.players[id];
				const entry = { id, name: p.name, bot: p.bot, spawn: p.spawn, rank: p.rank || '' };
				if (m.party) Object.assign(entry, { team: p.team, sp: [p.p[0], p.p[2]] });
				if (p.bot) Object.assign(entry, { w: Object.keys(p.inv)[0], medkits: p.medkits });
				return entry;
			}),
			shop: { prices: SHOP_PRICES, credits: START_CREDITS, window: BUY_WINDOW_MS, ammo: RESERVE_AMMO, maxMedkits: MAX_MEDKITS, maxNades: MAX_NADES },
			crates: [],
		});
		this.schedule();
	}

	/** Bots do not shop: a random weapon (pistol most often) and one medkit. */
	armBot(bot) {
		const weapon = rollWeapon();
		bot.inv = { [weapon]: true };
		bot.medkits = 1;
		return weapon;
	}

	/**
	 * Shop: {t:'buy', item}. Only alive, during your buy window, with enough
	 * credits; one of each weapon, medkits/grenades up to their carry limit.
	 */
	buy(player, item, ws) {
		const deny = (message) => this.send(ws, { t: 'buy_denied', item, message, credits: player.credits || 0 });
		const price = SHOP_PRICES[item];
		if (price === undefined) return deny('Item inválido');
		if (player.dead) return deny('Você está fora de combate');
		if (Date.now() > (player.buyUntil || 0)) return deny('Tempo de compra encerrado');
		if ((player.credits || 0) < price) return deny('Créditos insuficientes');
		const weapon = RESERVE_AMMO[item] !== undefined;
		player.inv = player.inv || {};
		if (weapon && player.inv[item]) return deny('Você já tem essa arma');
		if (item === 'medkit' && (player.medkits || 0) >= MAX_MEDKITS) return deny('Limite de kits');
		if (item === 'grenade' && (player.nades || 0) >= MAX_NADES) return deny('Limite de granadas');
		player.credits -= price;
		if (weapon) player.inv[item] = true;
		else if (item === 'medkit') player.medkits = (player.medkits || 0) + 1;
		else player.nades = (player.nades || 0) + 1;
		this.save();
		this.broadcast({ t: 'bought', by: player.id, item, ammo: weapon ? RESERVE_AMMO[item] : 0, credits: player.credits });
		if (item === 'medkit') this.broadcast({ t: 'medkits', id: player.id, count: player.medkits });
		if (item === 'grenade') this.broadcast({ t: 'nades', id: player.id, count: player.nades });
	}

	/** Credits for a kill (humans only), told to the killer right away. */
	reward(attacker, target, zone) {
		if (attacker.bot) return;
		const amount = (target.bot ? KILL_CREDITS.bot : KILL_CREDITS.player) + (zone === 'head' ? KILL_CREDITS.headshot : 0);
		attacker.credits = Math.min(MAX_CREDITS, (attacker.credits || 0) + amount);
		const ws = this.sessions.get(attacker.id);
		if (ws) this.send(ws, { t: 'credits', amount, total: attacker.credits, victim: target.name, head: zone === 'head' });
	}

	/** Next alarm: the end of the match, or (mata-mata) the next respawn. */
	schedule() {
		const m = this.match;
		if (m.phase !== 'running') return;
		let next = m.startedAt + this.matchLength();
		if (this.isDm()) {
			for (const p of Object.values(m.players)) if (p.dead && p.respawnAt) next = Math.min(next, p.respawnAt);
		}
		this.ctx.waitUntil(this.ctx.storage.setAlarm(next));
	}

	/** Mata-mata: bring back whoever finished waiting. */
	dmTick(now = Date.now()) {
		const m = this.match;
		for (const id of m.order) {
			const p = m.players[id];
			if (p?.dead && p.respawnAt && p.respawnAt <= now) this.respawn(p, now);
		}
		this.save();
	}

	/** Respawn in the building farthest from the living (random among the 3 best), with a pistol; the shop reopens. */
	respawn(p, now = Date.now()) {
		const m = this.match;
		p.respawnAt = 0;
		if (!p.bot && !this.sessions.has(p.id)) return; // left the match: stays out
		const others = m.order.map((id) => m.players[id]).filter((o) => o && o !== p && !o.dead && o.p);
		const ranked = layout.buildings
			.map((b, i) => ({ i, d: others.length ? Math.min(...others.map((o) => flatDistance([b.spawn[0], 0, b.spawn[1]], o.p))) : Math.random() }))
			.sort((a, b) => b.d - a.d);
		const pick = ranked[Math.floor(Math.random() * Math.min(3, ranked.length))];
		const at = layout.buildings[pick.i].spawn;
		Object.assign(p, {
			dead: false, hp: 100, spawn: pick.i, p: [at[0], 0, at[1]], inv: { [DM_KIT]: true }, medkits: 0, nades: 0, healAt: 0,
			safeUntil: now + DM_SPAWN_PROTECT_MS, buyUntil: now + BUY_WINDOW_MS,
		});
		const weapon = p.bot ? this.armBot(p) : DM_KIT;
		this.broadcast({
			t: 'respawn', id: p.id, spawn: pick.i, p: p.p, w: weapon, ammo: RESERVE_AMMO[weapon], safe: DM_SPAWN_PROTECT_MS, alive: this.alive().length,
			buy: BUY_WINDOW_MS, medkits: p.medkits,
		});
	}

	webSocketMessage(ws, message) {
		const meta = ws.deserializeAttachment();
		const m = this.match;
		const me = meta?.id && m.players[meta.id];
		if (!me) return;
		let d;
		try {
			d = JSON.parse(typeof message === 'string' ? message : new TextDecoder().decode(message));
		} catch {
			return;
		}
		if (!d || typeof d !== 'object') return;
		// Ping: devolve na hora o relógio do jogo, que mede o tempo de ida e volta.
		if (d.t === 'ping') return this.send(ws, { t: 'pong', c: finite(d.c, 1e15) ? d.c : 0 });
		if (m.phase === 'waiting') return this.partyMessage(meta.id, d, ws);
		if (m.phase !== 'running') return;
		const isHost = meta.id === m.host;
		switch (d.t) {
			case 's': {
				if (me.dead) return;
				const state = cleanState(d);
				if (!state) return;
				me.p = state.p; // last known position, for loot range and death drops
				me.stance = stanceOf(state); // a cabeça de quem está agachado/deitado fica mais baixa
				this.broadcast({ t: 's', id: meta.id, ...state }, meta.id);
				return;
			}
			case 'b': {
				// Bot positions, only from the client that simulates them.
				if (!isHost || !Array.isArray(d.l)) return;
				const list = [];
				for (const entry of d.l.slice(0, CAPACITY)) {
					const bot = m.players[entry?.id];
					if (!bot?.bot || bot.dead) continue;
					const state = cleanState(entry);
					if (!state) continue;
					bot.p = state.p;
					bot.stance = stanceOf(state);
					list.push({ id: bot.id, ...state });
				}
				if (list.length) this.broadcast({ t: 'b', l: list }, meta.id);
				return;
			}
			case 'shot': {
				const shooter = d.bot ? m.players[d.bot] : me;
				if (!shooter || shooter.dead || (d.bot && (!isHost || !shooter.bot))) return;
				const o = vec3(d.o, 500);
				const e = vec3(d.e, 1000);
				if (!o || !e) return;
				this.broadcast({ t: 'shot', id: shooter.id, w: WEAPON_DAMAGE[d.w] ? d.w : 'rifle', o, e }, meta.id);
				return;
			}
			case 'buy': {
				return this.buy(me, typeof d.item === 'string' ? d.item : '', ws);
			}
			case 'throw': {
				// Grenade thrown by a player (bots do not throw): {id, o, v}.
				if (me.dead || !me.nades || typeof d.id !== 'string' || !/^[a-z0-9]{4,10}$/.test(d.id)) return;
				const o = vec3(d.o, 500);
				const v = vec3(d.v, 40);
				if (!o || !v || (me.p && flatDistance(o, me.p) > 4)) return;
				const key = meta.id + ':' + d.id;
				if (m.grenades[key]) return;
				me.nades--;
				m.grenades[key] = { by: meta.id, o, at: Date.now() };
				this.save();
				this.broadcast({ t: 'nade', id: d.id, by: meta.id, o, v }, meta.id);
				this.broadcast({ t: 'nades', id: meta.id, count: me.nades });
				return;
			}
			case 'boom': {
				// The thrower's client reports where its grenade exploded.
				const key = meta.id + ':' + d.id;
				const grenade = m.grenades[key];
				const p = vec3(d.p, 500);
				if (!grenade || !p) return;
				delete m.grenades[key];
				const elapsed = Date.now() - grenade.at;
				if (elapsed < GRENADE_FUSE_MS[0] || elapsed > GRENADE_FUSE_MS[1] || flatDistance(p, grenade.o) > GRENADE_RANGE) return this.save();
				this.broadcast({ t: 'boom', id: d.id, by: meta.id, p });
				this.explode(me, p);
				return;
			}
			case 'heal_start': {
				// Using a medkit takes 3 s: remember when it started.
				const user = d.bot ? m.players[d.bot] : me;
				if (!user || user.dead || (d.bot && (!isHost || !user.bot)) || !user.medkits) return;
				user.healAt = Date.now();
				return;
			}
			case 'heal': {
				// Use one carried medkit (bots: only from the client that runs them).
				const user = d.bot ? m.players[d.bot] : me;
				if (!user || user.dead || (d.bot && (!isHost || !user.bot))) return;
				if (!user.medkits || user.hp >= 100) return;
				const waited = Date.now() - (user.healAt || 0);
				user.healAt = 0;
				if (waited < MEDKIT_USE_MS - 300 || waited > MEDKIT_USE_MS + 6000) return; // must take the 3 s
				user.medkits--;
				user.hp = Math.min(100, user.hp + MEDKIT_HEAL);
				this.save();
				this.broadcast({ t: 'medkits', id: user.id, count: user.medkits, healed: MEDKIT_HEAL });
				this.broadcast({ t: 'hp', id: user.id, hp: user.hp, by: user.id, w: '', zone: null, killed: false, kills: user.kills, alive: this.alive().length });
				return;
			}
			case 'hit': {
				const attacker = d.bot ? m.players[d.bot] : me;
				if (!attacker || attacker.dead || (d.bot && (!isHost || !attacker.bot))) return;
				// Only weapons actually picked up can deal damage.
				const owned = attacker.inv || {};
				if (attacker.bot ? !Object.keys(owned).length : !owned[d.w]) return;
				const target = m.players[d.target];
				if (!target || target.dead || target.id === attacker.id) return;
				if (m.party && target.team === attacker.team) return; // no friendly fire
				let damage = 0;
				let zone = ZONE_MULTIPLIER[d.zone] ? d.zone : null;
				if (!attacker.bot) {
					// Alcance da arma e cabeça plausível (cabeça duvidosa vale como peito).
					const verdict = this.hitCheck.check({ attacker, target, weapon: d.w, zone, point: d.pt });
					if (!verdict.ok) return;
					zone = verdict.zone;
				}
				if (attacker.bot) damage = finite(d.dmg, 1000) ? Math.min(Math.max(d.dmg, 0), BOT_DAMAGE) : 0;
				// Human hits: the server computes damage from weapon and body zone.
				else if (zone) damage = (WEAPON_DAMAGE[d.w] || 0) * ZONE_MULTIPLIER[zone];
				else damage = finite(d.dmg, 1000) ? Math.min(Math.max(d.dmg, 0), WEAPON_DAMAGE[d.w] || 0) : 0;
				if (damage <= 0 || !this.allowHit(attacker.id)) return;
				this.damage(attacker, target, damage, d.w, zone);
				return;
			}
			case 'melee': {
				// Soco: só de perto, no máximo um a cada PUNCH_COOLDOWN_MS, sem fogo amigo.
				const target = m.players[d.target];
				if (me.dead || !target || target.dead || target.id === me.id) return;
				if (m.party && target.team === me.team) return;
				if (!me.p || !target.p || Math.hypot(me.p[0] - target.p[0], me.p[2] - target.p[2]) > PUNCH_REACH) return;
				const now = Date.now();
				if (now - (me.lastPunch || 0) < PUNCH_COOLDOWN_MS) return;
				me.lastPunch = now;
				const head = d.zone === 'head';
				this.damage(me, target, FIST_DAMAGE * (head ? 1.5 : 1), 'fist', head ? 'head' : 'chest');
				return;
			}
		}
	}

	/** Blast damage: linear falloff from the centre (chest height), no friendly fire in teams. */
	explode(thrower, p) {
		const m = this.match;
		for (const id of [...m.order]) {
			if (this.match !== m || m.phase !== 'running') return; // the blast ended the match
			const target = m.players[id];
			if (!target || target.dead || !target.p) continue;
			if (m.party && target.id !== thrower.id && target.team === thrower.team) continue;
			const distance = Math.hypot(target.p[0] - p[0], target.p[1] + 1.0 - p[1], target.p[2] - p[2]);
			if (distance >= GRENADE_RADIUS) continue;
			const amount = Math.round(GRENADE_MAX_DAMAGE * (1 - distance / GRENADE_RADIUS));
			if (amount > 0) this.damage(thrower, target, amount, 'grenade', null);
		}
		if (this.match === m) this.save();
	}

	allowHit(attackerId) {
		const now = Date.now();
		const recent = (this.hitLog.get(attackerId) || []).filter((t) => now - t < 1000);
		if (recent.length >= MAX_HITS_PER_SECOND) return false;
		recent.push(now);
		this.hitLog.set(attackerId, recent);
		return true;
	}

	damage(attacker, target, amount, weapon, zone = null) {
		const self = attacker.id === target.id; // own grenade: no kill, no XP
		const dm = this.isDm();
		if (dm && !self) {
			attacker.safeUntil = 0; // attacking ends your spawn protection
			if (target.safeUntil && Date.now() < target.safeUntil) return;
		}
		target.hp = Math.max(0, Math.round((target.hp - amount) * 10) / 10);
		const killed = target.hp === 0;
		if (killed) {
			target.dead = true;
			if (!self) attacker.kills++;
			if (dm) {
				target.deaths = (target.deaths || 0) + 1;
				target.respawnAt = Date.now() + DM_RESPAWN_MS;
			}
		}
		this.save();
		this.broadcast({
			t: 'hp', id: target.id, hp: target.hp, by: attacker.id, w: weapon, zone, killed, kills: attacker.kills, alive: this.alive().length,
			...(dm && killed ? { respawn: DM_RESPAWN_MS, deaths: target.deaths } : {}),
		});
		if (killed) {
			// XP: a real player is worth much more than a bot.
			if (!attacker.bot && !self) {
				if (target.bot) {
					attacker.botKills++;
					this.credit(attacker, XP_REWARDS.kill_bot, 'kill_bot', target.name);
				} else {
					attacker.playerKills++;
					this.credit(attacker, XP_REWARDS.kill_player, 'kill_player', target.name);
				}
				if (zone === 'head') this.credit(attacker, XP_REWARDS.headshot_bonus, 'headshot', target.name);
				this.reward(attacker, target, zone);
			}
			// Morrer custa XP (inclusive na própria granada) — menos no mata-mata, onde se renasce.
			if (!target.bot && !dm) this.credit(target, XP_REWARDS.death, 'death', self ? '' : attacker.name);
			this.stripInventory(target);
			this.checkEnd();
			if (dm) this.schedule(); // respawn alarm (no-op once the match ended)
		}
	}

	/** Add XP earned in this match and tell the player right away. */
	credit(player, amount, reason, victim = '') {
		if (!player || player.bot || !player.account || player.flushed) return;
		player.xpGain = (player.xpGain || 0) + amount;
		const ws = this.sessions.get(player.id);
		if (ws) this.send(ws, { t: 'xp', amount, reason, victim, total: player.xpGain });
	}

	/** Save a player's match XP and stats to their account (once). */
	async flush(player, win = false) {
		if (!player || player.bot || !player.account || player.flushed) return;
		player.flushed = true;
		this.save();
		try {
			const accounts = this.env.GODOT_ACCOUNTS.get(this.env.GODOT_ACCOUNTS.idFromName('godot-accounts'));
			const response = await accounts.fetch(
				new Request('https://internal/internal/xp', {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ account: player.account, xp: player.xpGain || 0, kills: player.playerKills || 0, botKills: player.botKills || 0, win }),
				}),
			);
			if (!response.ok) return;
			const result = await response.json();
			const ws = this.sessions.get(player.id);
			if (ws) this.send(ws, { t: 'profile', gained: player.xpGain || 0, profile: result.profile, rankUp: !!result.rankUp });
		} catch {}
	}

	/** A dead player loses what they carried (nothing drops: weapons only come from the shop). */
	stripInventory(player) {
		player.inv = {};
		player.medkits = 0;
		player.nades = 0;
		this.save();
	}

	checkEnd(force = false) {
		const m = this.match;
		if (m.phase !== 'running') return;
		if (m.party) return this.checkTeamEnd(force);
		const dm = this.isDm();
		const byScore = (a, b) => m.players[b].kills - m.players[a].kills || (m.players[a].deaths || 0) - (m.players[b].deaths || 0);
		let winner;
		let reason;
		if (dm) {
			// Mata-mata: first to the kill goal; on timeout, most kills (then fewest deaths).
			winner = [...m.order].sort(byScore)[0] || null;
			const reached = !!winner && m.players[winner].kills >= DM_KILL_GOAL;
			if (!reached && !force) return;
			reason = reached ? 'abates' : 'tempo';
		} else {
			const alive = this.alive();
			if (alive.length > 1 && !force) return;
			// On timeout the survivor with most kills (then most health) wins.
			alive.sort((a, b) => m.players[b].kills - m.players[a].kills || m.players[b].hp - m.players[a].hp);
			winner = alive[0] || null;
			reason = force ? 'tempo' : 'eliminacao';
		}
		m.phase = 'finished';
		m.winner = winner;
		this.save();
		const winnerPlayer = m.winner ? m.players[m.winner] : null;
		// Everyone who played to the end earns match XP; the winner a bonus.
		for (const id of m.order) {
			const player = m.players[id];
			if (player.bot || player.flushed) continue;
			this.credit(player, XP_REWARDS.match, 'match');
			if (id === m.winner) this.credit(player, XP_REWARDS.win, 'win');
		}
		this.broadcast({
			t: 'end',
			winner: m.winner,
			name: winnerPlayer ? winnerPlayer.name : 'Ninguém',
			reason,
			mode: m.mode || 'elim',
			goal: dm ? DM_KILL_GOAL : undefined,
			board: [...m.order]
				.sort(byScore)
				.map((id) => ({ id, name: m.players[id].name, kills: m.players[id].kills, deaths: m.players[id].deaths || 0, bot: m.players[id].bot, rank: m.players[id].rank || '', xp: m.players[id].xpGain || 0 })),
		});
		this.ctx.waitUntil(Promise.all(m.order.map((id) => this.flush(m.players[id], id === m.winner))));
		this.ctx.waitUntil(this.ctx.storage.setAlarm(Date.now() + CLOSE_AFTER_END_MS));
	}

	/** Team match: ends when one side is wiped out; on timeout, most kills (then most alive) wins. */
	checkTeamEnd(force) {
		const m = this.match;
		const alive = this.alive();
		const aliveBy = [0, 1].map((team) => alive.filter((id) => m.players[id].team === team).length);
		if (aliveBy[0] && aliveBy[1] && !force) return;
		const killsBy = [0, 1].map((team) => m.order.reduce((sum, id) => sum + (m.players[id].team === team ? m.players[id].kills : 0), 0));
		let winnerTeam = null;
		if (!aliveBy[0] !== !aliveBy[1]) winnerTeam = aliveBy[0] ? 0 : 1;
		else if (killsBy[0] !== killsBy[1]) winnerTeam = killsBy[0] > killsBy[1] ? 0 : 1;
		else if (aliveBy[0] !== aliveBy[1]) winnerTeam = aliveBy[0] > aliveBy[1] ? 0 : 1;
		m.phase = 'finished';
		m.winner = null;
		m.winnerTeam = winnerTeam;
		this.save();
		for (const id of m.order) {
			const player = m.players[id];
			if (player.bot || player.flushed) continue;
			this.credit(player, XP_REWARDS.match, 'match');
			if (player.team === winnerTeam) this.credit(player, XP_REWARDS.win, 'win');
		}
		this.broadcast({
			t: 'end',
			winner: null,
			team: winnerTeam,
			name: winnerTeam === null ? 'Empate' : 'Equipe ' + TEAM_NAMES[winnerTeam],
			reason: force ? 'tempo' : 'eliminacao',
			score: killsBy,
			board: m.order
				.map((id) => ({ id, name: m.players[id].name, kills: m.players[id].kills, bot: m.players[id].bot, rank: m.players[id].rank || '', xp: m.players[id].xpGain || 0, team: m.players[id].team }))
				.sort((a, b) => a.team - b.team || b.kills - a.kills),
		});
		this.ctx.waitUntil(Promise.all(m.order.map((id) => this.flush(m.players[id], winnerTeam !== null && m.players[id].team === winnerTeam))));
		// Custom rooms survive the match: everyone goes back to the same lobby.
		if (m.party) return this.returnToRoom();
		this.ctx.waitUntil(this.ctx.storage.setAlarm(Date.now() + CLOSE_AFTER_END_MS));
	}

	/**
	 * After a custom-room match: same code, teams, leader, mode and bots option;
	 * bots and players who left are dropped, and everyone confirms "ready" again.
	 */
	returnToRoom() {
		const m = this.match;
		const players = {};
		for (const p of Object.values(m.players)) {
			if (p.bot || !this.sessions.has(p.id)) continue;
			const totalXp = (p.totalXp || 0) + (p.xpGain || 0);
			players[p.id] = {
				id: p.id, name: p.name, bot: false, hp: 100, dead: false, kills: 0, spawn: 0, account: p.account,
				totalXp, rank: rankFor(totalXp).rank, xpGain: 0, playerKills: 0, botKills: 0, flushed: false, ready: false, team: p.team,
			};
		}
		if (!Object.keys(players).length) return this.reset();
		const room = this.fresh(m.room);
		Object.assign(room, { party: true, size: m.size, bots: m.bots, players });
		room.leader = players[m.leader] ? m.leader : Object.keys(players)[0];
		this.match = room;
		this.hitLog.clear();
		this.hitCheck.reset();
		this.save();
		this.broadcastParty();
	}

	async alarm() {
		const m = this.match;
		const now = Date.now();
		if (!this.sessions.size) return this.reset();
		if (m.phase === 'waiting') {
			return; // rooms start only when the leader confirms
		} else if (m.phase === 'running') {
			if (now >= m.startedAt + this.matchLength()) return this.checkEnd(true);
			if (this.isDm()) this.dmTick(now);
			this.schedule();
		} else {
			for (const ws of this.sessions.values()) {
				try {
					ws.close(1000, 'Partida encerrada');
				} catch {}
			}
			this.reset();
		}
	}

	reset() {
		this.sessions.clear();
		this.hitLog.clear();
		this.hitCheck.reset();
		this.match = this.fresh('');
		this.ctx.waitUntil(this.ctx.storage.deleteAll());
	}

	webSocketClose(ws) {
		this.drop(ws);
	}

	webSocketError(ws) {
		this.drop(ws);
	}

	drop(ws) {
		const meta = ws.deserializeAttachment();
		if (!meta?.id || !this.sessions.has(meta.id)) return;
		this.sessions.delete(meta.id);
		const m = this.match;
		const player = m.players[meta.id];
		// Sair de uma partida em andamento ainda vivo custa XP (quem já morreu só está assistindo).
		if (m.phase === 'running' && player && !player.dead) this.credit(player, XP_REWARDS.quit, 'quit');
		if (!this.sessions.size) {
			// Last one out: still save the XP this player earned, then close the room.
			if (m.phase === 'running' && player) this.ctx.waitUntil(this.flush(player, false));
			return this.reset();
		}
		if (m.phase === 'waiting') {
			delete m.players[meta.id];
			// The next player in the room becomes leader.
			if (m.leader === meta.id) m.leader = this.humans().find((p) => this.sessions.has(p.id))?.id || null;
			this.save();
			this.broadcastParty();
			return;
		}
		this.broadcast({ t: 'leave', id: meta.id });
		if (m.phase !== 'running' || !player) return;
		// Leaving keeps the XP already earned (no match/win bonus), minus the quit penalty.
		this.ctx.waitUntil(this.flush(player, false));
		if (m.host === meta.id) {
			// Hand bot simulation to the next connected human.
			m.host = m.order.find((id) => this.sessions.has(id)) || null;
			this.broadcast({ t: 'host', id: m.host });
		}
		if (!player.dead) {
			player.dead = true;
			player.hp = 0;
			this.broadcast({ t: 'hp', id: player.id, hp: 0, by: 'saiu', w: '', killed: true, kills: 0, alive: this.alive().length });
			this.stripInventory(player);
		}
		this.save();
		this.checkEnd();
	}
}
