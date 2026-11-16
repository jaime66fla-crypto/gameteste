// Multiplayer for the Godot build (itch.io web + Windows download).
// One Durable Object instance acts as the matchmaker ("godot-matchmaker");
// every other instance is an 8-player elimination match ("match:<code>").
// The lobby starts 20 s after the first player joins (or at 8 players) and
// empty slots are filled with bots. Bots are simulated by one human client
// (the "host") so they respect the Godot map collision; the server owns
// every health value and decides the winner.

// Spawns (one per building) and loot spots, shared with the Godot client.
import layout from '../godot/data/match_layout.json' with { type: 'json' };

const CAPACITY = 8;
// Loot: everyone starts unarmed; crates hold one weapon plus reserve ammo.
const LOOT_WEIGHTS = [['pistol', 30], ['smg', 24], ['rifle', 20], ['shotgun', 16], ['sniper', 10]];
const RESERVE_AMMO = { pistol: 45, smg: 90, rifle: 90, shotgun: 18, sniper: 15 };
const LOOT_RANGE = 3.5; // metres between the looter's last known position and the crate
const LOBBY_MS = 20000;
const MAX_MATCH_MS = 8 * 60 * 1000;
const CLOSE_AFTER_END_MS = 15000;
// Per-hit damage caps (one pellet). Matches godot/scripts/weapon_data.gd.
const WEAPON_DAMAGE = { pistol: 22, smg: 12, rifle: 27, shotgun: 11, sniper: 95 };
// Body-part multipliers. Matches godot/scripts/net/hitbox.gd.
const ZONE_MULTIPLIER = { head: 2.0, chest: 1.0, pelvis: 0.9, arm: 0.7, leg: 0.7 };
const BOT_DAMAGE = 14;
const MAX_HITS_PER_SECOND = 18; // shotgun fires 8 pellets per shot
const BOT_NAMES = ['Cabo Rocha', 'Sgt. Lima', 'Recruta Dias', 'Ten. Faria', 'Cabo Nunes', 'Sgt. Prado', 'Soldado Reis', 'Cabo Vidal'];

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

function json(data, status = 200) {
	return new Response(JSON.stringify(data), {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
	});
}

const finite = (v, limit) => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= limit;
const vec3 = (v, limit) => (Array.isArray(v) && v.length === 3 && v.every((n) => finite(n, limit)) ? v.map((n) => Math.round(n * 100) / 100) : null);

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
		a: !!d.a,
		f: !!d.f,
		rl: !!d.rl,
		h: !!d.h, // holstered / no weapon yet
		v,
	};
}

/**
 * Client builds below GODOT_MIN_BUILD (wrangler.jsonc vars) are told to update.
 * Build numbers come from the game version: 0.1.0 -> 100, 1.2.3 -> 10203.
 * The socket is accepted only to deliver the message, then closed.
 */
function outdatedSocket(env, build) {
	const pair = new WebSocketPair();
	const [client, server] = [pair[0], pair[1]];
	server.accept();
	server.send(
		JSON.stringify({
			t: 'outdated',
			build,
			min: Number(env.GODOT_MIN_BUILD) || 0,
			url: String(env.GODOT_DOWNLOAD_URL || ''),
			message: 'Há uma nova versão do Campo de Fogo. Atualize para jogar online.',
		}),
	);
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
	const matchmaker = env.GODOT_MATCHES.get(env.GODOT_MATCHES.idFromName('godot-matchmaker'));
	const name = (url.searchParams.get('name') || 'Operador').replace(/[^\p{L}\p{N} ._-]/gu, '').trim().slice(0, 16) || 'Operador';
	let full = '';
	for (let attempt = 0; attempt < 3; attempt++) {
		const assigned = await matchmaker.fetch('https://internal/assign' + (full ? '?full=' + encodeURIComponent(full) : ''));
		const { room } = await assigned.json();
		const stub = env.GODOT_MATCHES.get(env.GODOT_MATCHES.idFromName('match:' + room));
		const target = 'https://internal/join?room=' + encodeURIComponent(room) + '&name=' + encodeURIComponent(name);
		const response = await stub.fetch(new Request(target, request));
		if (response.status === 101) return response;
		full = room; // started or full in the meantime: ask for a fresh room
	}
	return new Response('Nenhuma sala disponível. Tente novamente.', { status: 503 });
}

export class GodotMatch {
	constructor(ctx, env) {
		this.ctx = ctx;
		this.env = env;
		this.sessions = new Map(); // player id -> WebSocket
		this.hitLog = new Map(); // attacker id -> recent hit timestamps
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
		return { room, phase: 'waiting', deadline: 0, startedAt: 0, players: {}, order: [], host: null, winner: null, crates: {}, dropSeq: 0 };
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
		const m = this.match;
		if (m.phase !== 'waiting') return new Response('Partida em andamento', { status: 409 });
		if (this.sessions.size >= CAPACITY) return new Response('Sala cheia', { status: 409 });
		if (!m.room) m.room = url.searchParams.get('room') || '';

		const pair = new WebSocketPair();
		const [client, server] = [pair[0], pair[1]];
		const id = crypto.randomUUID().slice(0, 8);
		this.ctx.acceptWebSocket(server);
		server.serializeAttachment({ id });
		this.sessions.set(id, server);
		const now = Date.now();
		if (!m.deadline) m.deadline = now + LOBBY_MS;
		m.players[id] = { id, name: url.searchParams.get('name') || 'Operador', bot: false, hp: 100, dead: false, kills: 0, spawn: 0 };
		this.save();
		this.send(server, { t: 'welcome', id, room: m.room, capacity: CAPACITY, seconds: Math.ceil((m.deadline - now) / 1000) });
		if (this.sessions.size >= CAPACITY) this.start();
		else {
			this.broadcastLobby();
			await this.ctx.storage.setAlarm(Math.min(m.deadline, now + 1000));
		}
		return new Response(null, { status: 101, webSocket: client });
	}

	/** Matchmaker: hand out the current open room, opening a new one when needed. */
	async assign(url) {
		const now = Date.now();
		let mm = await this.ctx.storage.get('mm');
		const full = url.searchParams.get('full');
		// Stop filling a room shortly before its countdown ends.
		if (!mm || mm.count >= CAPACITY || now - mm.openedAt > LOBBY_MS - 2500 || (full && full === mm.room)) {
			mm = { room: crypto.randomUUID().slice(0, 6), openedAt: now, count: 0 };
		}
		mm.count++;
		await this.ctx.storage.put('mm', mm);
		return json({ room: mm.room });
	}

	broadcastLobby() {
		const m = this.match;
		this.broadcast({
			t: 'lobby',
			count: this.sessions.size,
			capacity: CAPACITY,
			seconds: Math.max(0, Math.ceil((m.deadline - Date.now()) / 1000)),
			names: this.humans().map((p) => p.name),
		});
	}

	start() {
		const m = this.match;
		if (m.phase !== 'waiting') return;
		const humans = this.humans().map((p) => p.id);
		if (!humans.length) return this.reset();
		for (let n = 0; humans.length + n < CAPACITY; n++) {
			const id = 'bot' + (n + 1);
			m.players[id] = { id, name: BOT_NAMES[n % BOT_NAMES.length], bot: true, hp: 100, dead: false, kills: 0, spawn: 0 };
		}
		m.order = Object.keys(m.players);
		// One building each, shuffled; everyone starts indoors and unarmed.
		const spawns = [...Array(m.order.length).keys()].sort(() => Math.random() - 0.5);
		m.order.forEach((id, i) => {
			const player = m.players[id];
			player.spawn = spawns[i];
			const at = layout.buildings[spawns[i] % layout.buildings.length].spawn;
			player.p = [at[0], 0, at[1]];
			player.inv = {};
		});
		const spots = [...layout.buildings.map((b) => b.loot), ...layout.outdoor_loot];
		m.crates = {};
		spots.forEach((spot, i) => {
			const weapon = rollWeapon();
			m.crates['c' + i] = { id: 'c' + i, p: [spot[0], 0, spot[1]], items: { [weapon]: RESERVE_AMMO[weapon] }, open: false, drop: false };
		});
		m.phase = 'running';
		m.startedAt = Date.now();
		m.host = humans[0];
		this.save();
		this.broadcast({
			t: 'start',
			host: m.host,
			alive: m.order.length,
			roster: m.order.map((id) => ({ id, name: m.players[id].name, bot: m.players[id].bot, spawn: m.players[id].spawn })),
			crates: Object.values(m.crates),
		});
		this.ctx.waitUntil(this.ctx.storage.setAlarm(m.startedAt + MAX_MATCH_MS));
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
		if (!d || typeof d !== 'object' || m.phase !== 'running') return;
		const isHost = meta.id === m.host;
		switch (d.t) {
			case 's': {
				if (me.dead) return;
				const state = cleanState(d);
				if (!state) return;
				me.p = state.p; // last known position, for loot range and death drops
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
			case 'loot': {
				const looter = d.bot ? m.players[d.bot] : me;
				if (!looter || looter.dead || (d.bot && (!isHost || !looter.bot))) return;
				const crate = m.crates[d.crate];
				if (!crate || crate.open || !looter.p || flatDistance(looter.p, crate.p) > LOOT_RANGE) return;
				crate.open = true;
				looter.inv = looter.inv || {};
				for (const weapon of Object.keys(crate.items)) looter.inv[weapon] = true;
				this.save();
				this.broadcast({ t: 'looted', crate: crate.id, by: looter.id, items: crate.items });
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
				let damage = 0;
				const zone = ZONE_MULTIPLIER[d.zone] ? d.zone : null;
				if (attacker.bot) damage = finite(d.dmg, 1000) ? Math.min(Math.max(d.dmg, 0), BOT_DAMAGE) : 0;
				// Human hits: the server computes damage from weapon and body zone.
				else if (zone) damage = (WEAPON_DAMAGE[d.w] || 0) * ZONE_MULTIPLIER[zone];
				else damage = finite(d.dmg, 1000) ? Math.min(Math.max(d.dmg, 0), WEAPON_DAMAGE[d.w] || 0) : 0;
				if (damage <= 0 || !this.allowHit(attacker.id)) return;
				this.damage(attacker, target, damage, d.w, zone);
				return;
			}
		}
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
		target.hp = Math.max(0, Math.round((target.hp - amount) * 10) / 10);
		const killed = target.hp === 0;
		if (killed) {
			target.dead = true;
			attacker.kills++;
		}
		this.save();
		this.broadcast({ t: 'hp', id: target.id, hp: target.hp, by: attacker.id, w: weapon, zone, killed, kills: attacker.kills, alive: this.alive().length });
		if (killed) {
			this.dropCrate(target);
			this.checkEnd();
		}
	}

	/** A dead player's weapons stay where they fell, in a crate anyone can open. */
	dropCrate(player) {
		const m = this.match;
		const weapons = Object.keys(player.inv || {});
		if (!player.p || !weapons.length) return;
		const id = 'd' + ++m.dropSeq;
		const items = {};
		for (const weapon of weapons) items[weapon] = RESERVE_AMMO[weapon] || 0;
		const crate = { id, p: [...player.p], items, open: false, drop: true, name: player.name };
		m.crates[id] = crate;
		player.inv = {};
		this.save();
		this.broadcast({ t: 'crate', crate });
	}

	checkEnd(force = false) {
		const m = this.match;
		if (m.phase !== 'running') return;
		const alive = this.alive();
		if (alive.length > 1 && !force) return;
		// On timeout the survivor with most kills (then most health) wins.
		alive.sort((a, b) => m.players[b].kills - m.players[a].kills || m.players[b].hp - m.players[a].hp);
		m.phase = 'finished';
		m.winner = alive[0] || null;
		this.save();
		const winner = m.winner ? m.players[m.winner] : null;
		this.broadcast({
			t: 'end',
			winner: m.winner,
			name: winner ? winner.name : 'Ninguém',
			reason: force ? 'tempo' : 'eliminacao',
			board: m.order.map((id) => ({ id, name: m.players[id].name, kills: m.players[id].kills, bot: m.players[id].bot })).sort((a, b) => b.kills - a.kills),
		});
		this.ctx.waitUntil(this.ctx.storage.setAlarm(Date.now() + CLOSE_AFTER_END_MS));
	}

	async alarm() {
		const m = this.match;
		const now = Date.now();
		if (!this.sessions.size) return this.reset();
		if (m.phase === 'waiting') {
			if (now >= m.deadline) this.start();
			else {
				this.broadcastLobby();
				await this.ctx.storage.setAlarm(Math.min(m.deadline, now + 1000));
			}
		} else if (m.phase === 'running') {
			if (now >= m.startedAt + MAX_MATCH_MS) this.checkEnd(true);
			else await this.ctx.storage.setAlarm(m.startedAt + MAX_MATCH_MS);
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
		if (!this.sessions.size) return this.reset();
		if (m.phase === 'waiting') {
			delete m.players[meta.id];
			this.save();
			this.broadcastLobby();
			return;
		}
		this.broadcast({ t: 'leave', id: meta.id });
		if (m.phase !== 'running' || !player) return;
		if (m.host === meta.id) {
			// Hand bot simulation to the next connected human.
			m.host = m.order.find((id) => this.sessions.has(id)) || null;
			this.broadcast({ t: 'host', id: m.host });
		}
		if (!player.dead) {
			player.dead = true;
			player.hp = 0;
			this.broadcast({ t: 'hp', id: player.id, hp: 0, by: 'saiu', w: '', killed: true, kills: 0, alive: this.alive().length });
			this.dropCrate(player);
		}
		this.save();
		this.checkEnd();
	}
}
