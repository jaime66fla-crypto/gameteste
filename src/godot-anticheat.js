// Anticheat do servidor (mata-mata, eliminatória, equipes e Sobrevivência).
//
// O servidor não tem física: quem atira diz em quem acertou e cada jogo manda a
// própria posição. O que dá para conferir sem física fica aqui:
//   1. ShotGate: cada acerto de bala precisa de um tiro ("shot") recente da
//      mesma arma, e os tiros respeitam a cadência da arma (weapon_data.gd).
//      Escopeta: um tiro vale até 8 acertos (chumbos). Quem manda "hit" sem
//      atirar, ou atira mais rápido que a arma, não causa dano.
//   2. MoveGate: ninguém anda mais rápido do que o jogo permite. Cada um tem um
//      "saldo" de metros que enche com o tempo (velocidade máxima) até um teto;
//      um pulo maior que o saldo é cortado: a posição do servidor anda só até
//      onde dava. Teletransporte vira corrida normal, e as conferências de
//      alcance (tiro, soco, saque) usam essa posição.
//   3. Infrações: cada recusa conta pontos por conta; os pontos vão para a
//      conta no fim da partida (ou ao sair), e o painel de admin mostra quem
//      acumulou mais para decidir um ban.
// Atraso de rede não pune o jogador honesto: tiros e passos podem chegar
// juntos (folga de 1,5 s de tiros e 6 m de passos), e a posição volta ao
// normal sozinha em poucos pacotes.

/** Cadência e chumbos de cada arma (godot/scripts/weapon_data.gd). */
export const FIRE = {
	pistol: { interval: 0.22, pellets: 1 },
	smg: { interval: 0.085, pellets: 1 },
	rifle: { interval: 0.115, pellets: 1 },
	shotgun: { interval: 0.85, pellets: 8 },
	sniper: { interval: 1.3, pellets: 1 },
	bow: { interval: 0.35, pellets: 1 },
	melee: { interval: 0.6, pellets: 1 }, // golpe da Sobrevivência (MELEE_COOLDOWN do survival_controller.gd)
};
/** Bots atiram a 0,8× o intervalo (net_actor.gd); a folga cobre isso e o atraso. */
export const FIRE_SLACK = 0.75;
/** Rajada aceita de uma vez (pacotes que chegam juntos depois de um engasgo da rede). */
export const FIRE_BURST_S = 1.5;
/** Um acerto vale até este tempo depois do tiro (no jogo é o mesmo quadro). */
export const CREDIT_MS = 3000;

/** Velocidade máxima no chão: correr = 5 × 1,6 = 8 m/s (player.gd), com folga. */
export const PLAYER_SPEED = 9.5;
/** Bots correm a 6 m/s (×1,35 caçando, net_actor.gd). */
export const BOT_SPEED = 9.5;
/** Zumbi corredor persegue a 3,8 m/s (zombie.gd). */
export const ZOMBIE_SPEED = 6;
/** Bichos correm no máximo ~10 m/s. */
export const ANIMAL_SPEED = 12;
/** Metros que se pode andar de uma vez (pacotes juntos depois de um engasgo). */
export const MOVE_BURST = 6;
/** Depois de nascer/renascer/rodada nova: o primeiro pacote pode estar até aqui do ponto do servidor. */
export const MOVE_GRACE = 30;
/** Pulo de posição acima disto (além do saldo) conta como infração de teletransporte. */
export const TELEPORT_FLAG_M = 15;

/** Pontos por infração (o painel soma). */
export const FLAG_POINTS = { nocredit: 1, rate: 1, teleport: 3, headshots: 10 };

const round2 = (n) => Math.round(n * 100) / 100;
const flat = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);

/** Tiros e acertos de cada atirador (jogador ou bot). */
export class ShotGate {
	constructor() {
		this.by = new Map(); // id -> { tokens: {arma: n}, at: {arma: ms}, credits: [{w, n, at}] }
	}

	reset() {
		this.by.clear();
	}

	forget(id) {
		this.by.delete(id);
	}

	state(id) {
		let s = this.by.get(id);
		if (!s) this.by.set(id, (s = { tokens: {}, at: {}, credits: [] }));
		return s;
	}

	/** Um tiro de `weapon`. false = mais rápido que a arma (o tiro não vale acerto). */
	shot(id, weapon, now = Date.now()) {
		const fire = FIRE[weapon];
		if (!fire || !id) return false;
		const s = this.state(id);
		const step = fire.interval * FIRE_SLACK; // segundos por tiro aceito
		const cap = Math.max(3, FIRE_BURST_S / step);
		const last = s.at[weapon];
		const tokens = last === undefined ? cap : Math.min(cap, s.tokens[weapon] + (now - last) / 1000 / step);
		s.at[weapon] = now;
		if (tokens < 1) {
			s.tokens[weapon] = tokens;
			return false;
		}
		s.tokens[weapon] = tokens - 1;
		s.credits = s.credits.filter((c) => c.n > 0 && now - c.at <= CREDIT_MS);
		s.credits.push({ w: weapon, n: fire.pellets, at: now });
		if (s.credits.length > 40) s.credits.splice(0, s.credits.length - 40);
		return true;
	}

	/** Um acerto de `weapon`: gasta um chumbo de um tiro recente. false = acerto sem tiro. */
	hit(id, weapon, now = Date.now()) {
		const s = this.by.get(id);
		if (!s) return false;
		const credit = s.credits.find((c) => c.w === weapon && c.n > 0 && now - c.at <= CREDIT_MS && now >= c.at);
		if (!credit) return false;
		credit.n--;
		return true;
	}
}

/** Velocidade máxima de quem manda a própria posição (jogadores, bots, zumbis, bichos, carros). */
export class MoveGate {
	constructor(speed, { burst = MOVE_BURST, grace = MOVE_GRACE } = {}) {
		this.speed = speed;
		this.burst = burst;
		this.grace = grace;
		this.by = new Map(); // id -> { at, budget, grace }
	}

	forget(id) {
		this.by.delete(id);
	}

	/** O servidor pôs `id` num lugar (nascer, rodada, cama): o próximo pacote pode chegar de perto dali. */
	place(id, now = Date.now()) {
		this.by.set(id, { at: now, budget: this.burst, grace: true });
	}

	/** O servidor já sabe onde `id` está agora (carro dirigido): segue dali com o saldo cheio. */
	sync(id, now = Date.now()) {
		this.by.set(id, { at: now, budget: this.burst, grace: false });
	}

	/**
	 * Nova posição relatada `to`, saindo de `from` (a do servidor). Devolve
	 * { p, over }: p = a posição aceita (cortada se passou do saldo) e
	 * over = metros cortados (0 quando estava tudo certo).
	 */
	move(id, from, to, now = Date.now()) {
		let s = this.by.get(id);
		if (!Array.isArray(from)) {
			this.by.set(id, { at: now, budget: this.burst, grace: false });
			return { p: to, over: 0 };
		}
		if (!s) s = { at: now, budget: this.burst, grace: true }; // servidor acordou: sem histórico
		if (s.grace) {
			s.grace = false;
			if (flat(from, to) <= this.grace) {
				this.by.set(id, { at: now, budget: this.burst, grace: false });
				return { p: to, over: 0 };
			}
		}
		const dt = Math.min(2, Math.max(0, (now - s.at) / 1000));
		s.at = now;
		s.budget = Math.min(this.burst, s.budget + this.speed * dt);
		this.by.set(id, s);
		const step = flat(from, to);
		if (step <= s.budget) {
			s.budget -= step;
			return { p: to, over: 0 };
		}
		const k = s.budget / step;
		const p = [round2(from[0] + (to[0] - from[0]) * k), to[1], round2(from[2] + (to[2] - from[2]) * k)];
		const over = step - s.budget;
		s.budget = 0;
		return { p, over };
	}
}

/** Pontos de infração por jogador (id da sala -> {tipo: vezes}), mandados para a conta depois. */
export class CheatLog {
	constructor() {
		this.by = new Map();
	}

	add(id, kind, times = 1) {
		if (!id || !FLAG_POINTS[kind]) return;
		const counts = this.by.get(id) || {};
		counts[kind] = (counts[kind] || 0) + times;
		this.by.set(id, counts);
	}

	/** Contagens de `id` (e zera), ou null se não houve nada. */
	take(id) {
		const counts = this.by.get(id);
		this.by.delete(id);
		return counts && Object.keys(counts).length ? counts : null;
	}

	reset() {
		this.by.clear();
	}
}

/** Soma de pontos de um conjunto de contagens {tipo: vezes}. */
export function flagPoints(counts) {
	let total = 0;
	for (const [kind, times] of Object.entries(counts || {})) total += (FLAG_POINTS[kind] || 0) * (Number(times) || 0);
	return total;
}
