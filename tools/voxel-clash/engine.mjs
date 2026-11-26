import { randomBytes, randomUUID } from 'node:crypto';

export const SIZE = 14;
export const RULES = {
  house: { title: 'Cottage', gold: 45, hp: 65, income: 2, cap: 4 },
  farm: { title: 'Windmill', gold: 60, hp: 60, food: 3 },
  quarry: { title: 'Crystal mine', gold: 80, hp: 85, energy: 2 },
  barracks: { title: 'Barracks', gold: 100, hp: 100, troops: 1 },
  tower: { title: 'Watchtower', gold: 110, hp: 150, defense: 12 },
  wall: { title: 'Rampart', gold: 25, hp: 180, defense: 4 },
  nexus: { title: 'Citadel', gold: 0, hp: 240, income: 4, cap: 8 },
};
export const coordinate = id => String.fromCharCode(65 + id % SIZE) + (Math.floor(id / SIZE) + 1);
export const distance = (a, b) => Math.hypot(a % SIZE - b % SIZE, Math.floor(a / SIZE) - Math.floor(b / SIZE));
export const capability = () => randomBytes(24).toString('base64url');

function player(seat, name = '') {
  return { seat, name, joined: !!name, bot: false, gold: 280, food: 90, energy: 60, troops: 12, score: 0, shieldUntil: 0, lastAttack: 0, lastSeen: 0, color: seat === 0 ? '#67e8c3' : '#ffb485' };
}

export function makeGame({ id = randomBytes(6).toString('hex'), name = 'Floating kingdoms', host = 'Player', seed = Math.floor(Math.random() * 100000), now = Date.now() } = {}) {
  const game = {
    id, name, seed, revision: 1, phase: 'waiting', createdAt: now, startedAt: 0, duration: 360000,
    players: [player(0, host), player(1)], tiles: [], waves: [], effects: [], events: [],
    relic: { tile: 6 * SIZE + 6, owner: -1, capturedAt: 0 }, winner: null, lastTick: now,
    inviteKey: capability(), watchKey: capability(), members: {}, processed: {}, botAt: now,
  };
  for (let z = 0; z < SIZE; z++) for (let x = 0; x < SIZE; x++) {
    const channel = (x === 6 || x === 7) && z !== 6 && z !== 7;
    const edge = x === 0 || z === 0 || x === 13 || z === 13;
    const water = edge || channel;
    const terrain = water ? 'water' : (x === 6 || x === 7) ? 'bridge' : 'grass';
    game.tiles.push({ id: z * SIZE + x, owner: x < 6 ? 0 : x > 7 ? 1 : -1, terrain, height: water ? -0.5 : 0.12 + ((x * 19 + z * 7 + seed) % 3) * 0.025, kind: 'empty', level: 0, hp: 0, maxHp: 0, builtAt: 0 });
  }
  const place = (id, kind) => {
    const tile = game.tiles[id];
    Object.assign(tile, { kind, level: 1, hp: RULES[kind].hp, maxHp: RULES[kind].hp, builtAt: now - 2000 });
  };
  for (const [id, kind] of [[100, 'nexus'], [86, 'house'], [114, 'farm'], [101, 'barracks'], [95, 'nexus'], [81, 'house'], [109, 'farm'], [94, 'barracks']]) place(id, kind);
  event(game, `${host} founded a kingdom. Invite a rival or start a practice match.`, now);
  return game;
}

export function event(game, text, now = Date.now(), kind = 'info') {
  game.events.unshift({ id: randomUUID(), text, at: now, kind });
  game.events = game.events.slice(0, 14);
}

export function totals(game, seat) {
  const result = { gold: 3, food: 1, energy: 1, troops: 0, cap: 12, buildings: 0 };
  for (const tile of game.tiles) {
    if (tile.owner !== seat || tile.kind === 'empty') continue;
    result.buildings++;
    const rule = RULES[tile.kind];
    for (const key of ['income', 'food', 'energy', 'troops', 'cap']) result[key === 'income' ? 'gold' : key] += (rule[key] || 0) * tile.level;
  }
  return result;
}

export function joinPlayer(game, { name, clientId, invite }, now = Date.now()) {
  if (invite !== game.inviteKey) throw new Error('This invitation is invalid. Ask the host for a fresh link.');
  if (typeof name !== 'string' || !name.trim() || name.trim().length > 24) throw new Error('Choose a name between 1 and 24 characters.');
  if (typeof clientId !== 'string' || clientId.length < 20 || clientId.length > 100) throw new Error('Missing player identity.');
  const existing = Object.entries(game.members).find(([, member]) => member.clientId === clientId);
  if (existing) return { token: existing[0], seat: existing[1].seat };
  const seat = game.players.findIndex(p => !p.joined || p.bot);
  if (seat < 0) throw new Error('Both player seats are taken. You can watch this match instead.');
  const token = capability();
  game.members[token] = { seat, clientId };
  Object.assign(game.players[seat], { name: name.trim(), joined: true, bot: false, lastSeen: now });
  if (game.phase === 'waiting') { game.phase = 'playing'; game.startedAt = now; game.lastTick = now; }
  game.revision++;
  event(game, `${name.trim()} joined. The battle for the Sky Crystal begins.`, now, 'join');
  return { token, seat };
}

export function addHost(game, clientId) {
  const token = capability();
  game.members[token] = { seat: 0, clientId };
  game.players[0].lastSeen = Date.now();
  return { token, seat: 0 };
}

function pay(p, gold = 0, food = 0, energy = 0) {
  if (p.gold < gold) throw new Error(`You need ${gold} gold. Build cottages to grow your economy.`);
  if (p.food < food) throw new Error(`You need ${food} food. Windmills feed your army.`);
  if (p.energy < energy) throw new Error(`You need ${energy} crystal energy. Build crystal mines.`);
  p.gold -= gold; p.food -= food; p.energy -= energy;
}

export function applyAction(game, seat, action, now = Date.now()) {
  const p = game.players[seat];
  if (!p?.joined) throw new Error('Join the match before playing.');
  if (typeof action.requestId !== 'string' || action.requestId.length < 8 || action.requestId.length > 100) throw new Error('Missing action identifier.');
  const key = seat + ':' + action.requestId;
  if (game.processed[key]) return false;
  if (game.phase === 'finished' && !['rematch', 'practice'].includes(action.type)) throw new Error('This match has finished. Start a rematch.');
  const tile = Number.isInteger(action.tile) ? game.tiles[action.tile] : null;
  if (action.type === 'practice') {
    if (seat !== 0) throw new Error('Only the host can start practice.');
    if (game.phase !== 'waiting') throw new Error('Start a rematch to begin a new practice battle.');
    if (game.players[1].joined && !game.players[1].bot) throw new Error('Your rival has already joined.');
    Object.assign(game.players[1], { name: 'Clockwork', joined: true, bot: true, lastSeen: now });
    game.phase = 'playing'; game.startedAt = now; game.lastTick = now;
    event(game, 'Clockwork joined. Practice against a live strategy opponent.', now, 'join');
  } else if (action.type === 'rematch') {
    if (seat !== 0) throw new Error('Only the host can start a rematch.');
    const fresh = makeGame({ id: game.id, name: game.name, host: game.players[0].name, seed: game.seed, now });
    const identities = game.players.map(p => ({ name: p.name, joined: p.joined, bot: p.bot, lastSeen: p.lastSeen }));
    const retained = { members: game.members, inviteKey: game.inviteKey, watchKey: game.watchKey, processed: game.processed, revision: game.revision };
    Object.assign(game, fresh, retained);
    identities.forEach((identity, i) => Object.assign(game.players[i], identity));
    game.phase = game.players[1].joined ? 'playing' : 'waiting';
    game.startedAt = game.phase === 'playing' ? now : 0;
    event(game, 'A new chapter begins. Both kingdoms are restored.', now, 'join');
  } else if (action.type === 'shield') {
    if (p.shieldUntil > now) throw new Error('Your shield is already active.');
    pay(p, 0, 0, 60); p.shieldUntil = now + 12000;
    event(game, `${p.name} raised a citadel shield for 12 seconds.`, now, 'shield');
  } else if (action.type === 'train') {
    if (p.troops + 5 > totals(game, seat).cap) throw new Error('Build cottages to increase your army capacity.');
    pay(p, 35, 25); p.troops += 5;
    event(game, `${p.name} recruited five sky knights.`, now, 'train');
  } else if (action.type === 'build') {
    if (!tile || tile.terrain !== 'grass' || tile.owner !== seat) throw new Error('Choose a grass plot in your own kingdom.');
    if (tile.kind !== 'empty') throw new Error('This plot is occupied. Upgrade or repair its building.');
    if (!Object.hasOwn(RULES, action.kind) || action.kind === 'nexus') throw new Error('Choose a building from the build menu.');
    const rule = RULES[action.kind]; pay(p, rule.gold);
    Object.assign(tile, { kind: action.kind, level: 1, hp: rule.hp, maxHp: rule.hp, builtAt: now });
    event(game, `${p.name} built a ${rule.title.toLowerCase()} at ${coordinate(tile.id)}.`, now, 'build');
  } else if (action.type === 'upgrade' || action.type === 'repair') {
    if (!tile || tile.owner !== seat || tile.kind === 'empty') throw new Error('Choose one of your buildings.');
    if (action.type === 'upgrade') {
      if (tile.level >= 3) throw new Error('This building is already at maximum level.');
      pay(p, 55 * tile.level, 0, 10 * tile.level); tile.level++;
      tile.maxHp = Math.round(RULES[tile.kind].hp * (1 + (tile.level - 1) * 0.65)); tile.hp = tile.maxHp; tile.builtAt = now;
      event(game, `${p.name} upgraded ${coordinate(tile.id)} to level ${tile.level}.`, now, 'build');
    } else {
      if (tile.hp >= tile.maxHp) throw new Error('This building is already fully repaired.');
      pay(p, 35); tile.hp = Math.min(tile.maxHp, tile.hp + 70);
      event(game, `${p.name} repaired ${coordinate(tile.id)}.`, now, 'build');
    }
  } else if (action.type === 'attack' || action.type === 'claim' || action.type === 'meteor') {
    if (game.phase !== 'playing') throw new Error('Invite a rival or start practice to begin the battle.');
    if (now - p.lastAttack < 2200) throw new Error('Your army is regrouping. Wait a moment.');
    const target = action.type === 'claim' ? game.tiles[game.relic.tile] : tile;
    if (!target || (action.type !== 'claim' && (target.owner === seat || target.kind === 'empty'))) throw new Error('Choose an enemy building or capture the Sky Crystal.');
    const units = action.type === 'claim' ? 3 : action.type === 'meteor' ? 0 : 5;
    if (p.troops < units) throw new Error(`You need ${units} knights. Train an army or build barracks.`);
    if (action.type === 'claim' && game.relic.owner === seat) throw new Error('You already control the Sky Crystal. Defend your kingdom.');
    pay(p, action.type === 'meteor' ? 0 : 20, 0, action.type === 'meteor' ? 80 : 0);
    p.troops -= units; p.lastAttack = now;
    const from = game.tiles.find(t => t.kind === 'nexus' && t.owner === seat)?.id ?? (seat === 0 ? 100 : 95);
    game.waves.push({ id: randomUUID(), seat, from, to: target.id, start: now, arrival: now + 1500 + distance(from, target.id) * 180, units, type: action.type });
    event(game, action.type === 'claim' ? `${p.name} sent knights to claim the Sky Crystal.` : `${p.name} launched ${action.type === 'meteor' ? 'a crystal meteor' : 'five knights'} toward ${coordinate(target.id)}.`, now, 'attack');
  } else throw new Error('Unknown game action.');
  game.processed[key] = now;
  const keys = Object.keys(game.processed);
  if (keys.length > 1024) for (const k of keys.slice(0, 256)) delete game.processed[k];
  game.revision++;
  return true;
}

function finish(game, winner, now, reason) {
  game.phase = 'finished'; game.winner = winner; game.waves = [];
  event(game, winner === -1 ? 'An even battle. Both kingdoms share the skies.' : `${game.players[winner].name} wins ${reason}!`, now, 'victory');
}

export function tick(game, now = Date.now()) {
  let changed = false;
  if (game.phase !== 'playing') return changed;
  const steps = Math.min(3, Math.floor((now - game.lastTick) / 1000));
  if (steps > 0) {
    game.lastTick += steps * 1000;
    if (now - game.lastTick > 5000) game.lastTick = now;
    for (const p of game.players) {
      const rate = totals(game, p.seat);
      p.gold = Math.min(1500, p.gold + rate.gold * steps);
      p.food = Math.min(500, p.food + rate.food * steps);
      p.energy = Math.min(300, p.energy + rate.energy * steps);
      if (Math.floor(game.lastTick / 1000) % 3 === 0 && p.food >= 3 && rate.troops) { p.troops = Math.min(rate.cap, p.troops + rate.troops); p.food -= 3; }
      if (game.relic.owner === p.seat) p.score += steps;
    }
    changed = true;
  }
  for (const wave of game.waves.filter(w => w.arrival <= now)) {
    const tile = game.tiles[wave.to];
    if (wave.type === 'claim') {
      game.relic.owner = wave.seat; game.relic.capturedAt = now;
      event(game, `${game.players[wave.seat].name} controls the Sky Crystal. +1 crown every second.`, now, 'capture');
    } else if (tile.kind !== 'empty' && tile.owner !== wave.seat) {
      const defender = game.players[tile.owner];
      const defense = game.tiles.filter(t => t.owner === tile.owner && distance(t.id, tile.id) <= 3 && ['tower', 'wall'].includes(t.kind)).reduce((sum, t) => sum + RULES[t.kind].defense * t.level, 0);
      const damage = Math.max(12, (wave.type === 'meteor' ? 65 : wave.units * 16) - defense - (defender.shieldUntil > now ? 45 : 0));
      tile.hp = Math.max(0, tile.hp - damage);
      game.effects.push({ id: wave.id, tile: tile.id, damage, start: now, until: now + 1800, seat: wave.seat });
      if (tile.hp === 0) {
        if (tile.kind === 'nexus') {
          finish(game, wave.seat, now, 'by conquering the rival citadel');
          changed = true;
          break;
        }
        else {
          game.players[wave.seat].score += 8; game.players[wave.seat].gold += 35;
          event(game, `${game.players[wave.seat].name} destroyed ${coordinate(tile.id)}! +8 crowns`, now, 'attack');
          Object.assign(tile, { kind: 'empty', level: 0, hp: 0, maxHp: 0 });
        }
      } else event(game, `${coordinate(tile.id)} took ${damage} damage. ${tile.hp} HP remain.`, now, 'attack');
    }
    changed = true;
  }
  game.waves = game.waves.filter(w => w.arrival > now);
  game.effects = game.effects.filter(e => e.until > now);
  if (game.phase === 'playing') {
    const champion = game.players.find(p => p.score >= 80);
    if (champion) { finish(game, champion.seat, now, 'with 80 crowns'); changed = true; }
    else if (now - game.startedAt >= game.duration) {
      const scores = game.players.map(p => p.score * 1000 + (game.tiles.find(t => t.owner === p.seat && t.kind === 'nexus')?.hp || 0));
      finish(game, scores[0] === scores[1] ? -1 : scores[0] > scores[1] ? 0 : 1, now, 'when the match clock expired'); changed = true;
    }
  }
  if (game.players[1].bot && game.phase === 'playing' && now >= game.botAt) {
    game.botAt = now + 4200;
    const p = game.players[1], own = game.tiles.filter(t => t.owner === 1 && t.terrain === 'grass' && t.kind === 'empty');
    let action;
    if (game.relic.owner !== 1 && p.troops >= 3) action = { type: 'claim' };
    else if (p.troops >= 5) action = { type: 'attack', tile: game.tiles.find(t => t.owner === 0 && t.kind === 'nexus').id };
    else if (p.gold >= 100 && own.length) action = { type: 'build', tile: own[(game.revision * 7) % own.length].id, kind: totals(game, 1).troops < 3 ? 'barracks' : 'farm' };
    else action = { type: 'train' };
    try { applyAction(game, 1, { ...action, requestId: randomUUID() }, now); changed = true; } catch {}
  }
  if (changed) game.revision++;
  return changed;
}

export function publicGame(game, now = Date.now(), spectators = 0) {
  const { inviteKey, watchKey, members, processed, botAt, ...publicState } = game;
  return { ...publicState, spectators, serverTime: now, players: game.players.map(p => ({ ...p, online: p.bot || now - p.lastSeen < 15000, rate: totals(game, p.seat) })) };
}
