// Conferência de acertos de bala (mata-mata e Sobrevivência).
//
// O jogo de quem atira diz em quem acertou e em que parte do corpo; o servidor
// não tem física para refazer o tiro. Aqui ele confere o que dá para conferir:
//   1. distância: o alvo precisa estar dentro do alcance da arma;
//   2. cabeça plausível: o ponto do acerto (quando o jogo manda) precisa estar
//      perto do alvo e numa altura em que a cabeça pode estar, conforme a
//      postura (em pé, agachado, deitado) que o próprio alvo informou;
//   3. taxa de tiros na cabeça: quem acerta a cabeça demais (muitos acertos
//      seguidos) fica marcado e os próximos "cabeça" valem como peito.
// Acerto implausível na cabeça vira peito (não some): atraso de rede não
// pune o jogador honesto, só tira o bônus de quem trapaceia.

/** Alcance de cada arma em metros (scripts/weapon_data.gd, "range"). */
export const WEAPON_RANGE = { pistol: 250, smg: 220, rifle: 450, shotgun: 70, sniper: 700, bow: 120 };
const RANGE_SLACK = 12; // atraso de rede: o alvo andou desde a última posição

/**
 * Altura do ponto do acerto na cabeça, acima dos pés do alvo, por postura.
 * Folgada: pulo, inclinar (Q/E), animação e a postura chegando atrasada.
 */
export const HEAD_HEIGHT = { stand: [1.15, 2.6], crouch: [0.6, 2.2], prone: [-0.2, 1.3] };
/** Distância horizontal máxima do ponto ao alvo (deitado o corpo se estica; atraso de rede). */
export const HEAD_MAX_FLAT = 2.5;

/** Taxa de tiros na cabeça: a partir de minHits acertos em jogadores, acima de maxRatio marca. */
export const HEADSHOT_WATCH = { minHits: 20, maxRatio: 0.7 };

const finite = (v, limit) => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= limit;
const point3 = (v) => (Array.isArray(v) && v.length === 3 && v.every((n) => finite(n, 2000)) ? v : null);

/** Postura informada no estado do jogador ('s'): c = agachado, pr = deitado. */
export function stanceOf(state) {
	if (state?.pr) return 'prone';
	if (state?.c) return 'crouch';
	return 'stand';
}

export class HitCheck {
	constructor() {
		this.arrows = new Map(); // owner + arrow id -> recorded ballistic launch
		this.arrowLaunches = new Map();
		this.stats = new Map(); // atacante -> { hits, heads, flagged }
	}

	reset() {
		this.stats.clear();
		this.arrows.clear();
		this.arrowLaunches.clear();
	}

	/** Record releases, not button presses. Survival consumes the inventory arrow separately. */
	recordArrow({ attacker, id, origin, velocity, now = Date.now() }) {
		if (!attacker?.id || typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(id)) return false;
		const o = point3(origin), v = point3(velocity), p = point3(attacker.p);
		if (!o || !v || !p || Math.hypot(...o.map((n, i) => n - p[i])) > 4) return false;
		const speed = Math.hypot(...v);
		if (speed < 19 || speed > 49) return false;
		// Keep used ids until expiry so replaying a launch cannot create another impact.
		for (const [key, arrow] of this.arrows) if (now - arrow.at > 8500) this.arrows.delete(key);
		const key = attacker.id + ':' + id;
		if (this.arrows.has(key) || now - (this.arrowLaunches.get(attacker.id) ?? -Infinity) < 200) return false;
		this.arrows.set(key, { o: [...o], v: [...v], at: now, used: false });
		this.arrowLaunches.set(attacker.id, now);
		return true;
	}

	/** Validate gravity and flight time; the server has no collision mesh to retrace walls. */
	checkArrow({ attacker, target, id, point, zone, player = true, now = Date.now() }) {
		const arrow = this.arrows.get(attacker?.id + ':' + id);
		const pt = point3(point), tp = point3(target?.p);
		if (!arrow || arrow.used || !pt || !tp) return { ok: false, reason: 'arrow' };
		const elapsed = (now - arrow.at) / 1000;
		if (elapsed < 0 || elapsed > 8.5) return { ok: false, reason: 'flight' };
		if (Math.hypot(pt[0] - tp[0], pt[2] - tp[2]) > 3 || Math.abs(pt[1] - tp[1]) > 3.5) return { ok: false, reason: 'target' };
		// Sample the recorded curved path, including near-vertical shots.
		let best = Infinity, flight = 0;
		for (let t = 0; t <= Math.min(8.5, elapsed + 0.15); t += 0.01) {
			const d = Math.hypot(pt[0] - arrow.o[0] - arrow.v[0] * t, pt[1] - arrow.o[1] - arrow.v[1] * t + 4.9 * t * t, pt[2] - arrow.o[2] - arrow.v[2] * t);
			if (d < best) { best = d; flight = t; }
		}
		if (best > 1.2 || Math.abs(flight - elapsed) > 0.4) return { ok: false, reason: 'trajectory' };
		// Range is measured from the recorded release, even if the archer moved.
		const verdict = this.check({ attacker: { ...attacker, p: arrow.o }, target, weapon: 'bow', zone, point: pt, player });
		if (verdict.ok) arrow.used = true;
		return verdict;
	}

	/**
	 * Confere um acerto de bala. Devolve { ok: false } para recusar, ou
	 * { ok: true, zone, reason } com a parte do corpo que vale ('head' pode
	 * virar 'chest'). `player` = o alvo é um jogador (zumbis e bonecos só
	 * passam pela distância).
	 */
	check({ attacker, target, weapon, zone, point = null, player = true }) {
		const range = WEAPON_RANGE[weapon];
		if (!range) return { ok: false, reason: 'weapon' };
		if (Array.isArray(attacker?.p) && Array.isArray(target?.p)) {
			const d = Math.hypot(attacker.p[0] - target.p[0], attacker.p[1] - target.p[1], attacker.p[2] - target.p[2]);
			if (d > range + RANGE_SLACK) return { ok: false, reason: 'range' };
		}
		if (!player) return { ok: true, zone, reason: '' };
		let reason = '';
		const claimedHead = zone === 'head';
		if (claimedHead) {
			const pt = point3(point);
			if (pt && Array.isArray(target?.p)) {
				const flat = Math.hypot(pt[0] - target.p[0], pt[2] - target.p[2]);
				const [low, high] = HEAD_HEIGHT[target.stance] || HEAD_HEIGHT.stand;
				const dy = pt[1] - target.p[1];
				if (flat > HEAD_MAX_FLAT || dy < low || dy > high) {
					zone = 'chest';
					reason = 'point';
				}
			}
		}
		const id = attacker?.id;
		if (id) {
			const s = this.stats.get(id) || { hits: 0, heads: 0, flagged: false };
			s.hits++;
			if (claimedHead) s.heads++;
			if (!s.flagged && s.hits >= HEADSHOT_WATCH.minHits && s.heads / s.hits > HEADSHOT_WATCH.maxRatio) {
				s.flagged = true;
				console.warn(`[hitcheck] ${attacker.name || id}: ${s.heads}/${s.hits} acertos na cabeça — cabeça passa a valer peito`);
			}
			this.stats.set(id, s);
			if (s.flagged && zone === 'head') {
				zone = 'chest';
				reason = 'ratio';
			}
		}
		return { ok: true, zone, reason };
	}

	flagged(id) {
		return !!this.stats.get(id)?.flagged;
	}
}
