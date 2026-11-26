import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { makeGame, applyAction, tick, joinPlayer, addHost, publicGame, totals } from './engine.mjs';
import { createServer } from './api.mjs';
import { GameStore } from './store.mjs';

const now = 1_000_000;
const action = data => ({ ...data, requestId: randomUUID() });
const duel = () => {
  const game = makeGame({ host: 'Jack', seed: 27, now });
  joinPlayer(game, { name: 'Donald', clientId: randomUUID(), invite: game.inviteKey }, now);
  return game;
};

test('build, upgrade, repair and ownership are server authoritative', () => {
  const game = duel();
  const first = action({ type: 'build', kind: 'house', tile: 44 });
  applyAction(game, 0, first, now);
  assert.equal(game.tiles[44].kind, 'house');
  const gold = game.players[0].gold;
  assert.equal(applyAction(game, 0, first, now), false);
  assert.equal(game.players[0].gold, gold);
  assert.throws(() => applyAction(game, 1, action({ type: 'build', kind: 'house', tile: 44 }), now));
  assert.throws(() => applyAction(game, 0, action({ type: 'build', kind: 'constructor', tile: 45 }), now));
  assert.throws(() => applyAction(game, 0, action({ type: 'build', kind: 'house', tile: 0 }), now));
  applyAction(game, 0, action({ type: 'upgrade', tile: 44 }), now);
  assert.equal(game.tiles[44].level, 2);
  game.tiles[44].hp = 1;
  applyAction(game, 0, action({ type: 'repair', tile: 44 }), now);
  assert.equal(game.tiles[44].hp, 71);
  game.players[0].gold = 0;
  assert.throws(() => applyAction(game, 0, action({ type: 'build', kind: 'tower', tile: 45 }), now));
});

test('armies travel, inflict damage and consume troops, with a cooldown', () => {
  const game = duel();
  applyAction(game, 0, action({ type: 'attack', tile: 95 }), now + 3000);
  assert.equal(game.tiles[95].hp, 240);
  assert.equal(game.players[0].troops, 7);
  assert.throws(() => applyAction(game, 0, action({ type: 'attack', tile: 95 }), now + 3100));
  tick(game, game.waves[0].arrival + 1);
  assert.equal(game.tiles[95].hp, 160);
  assert.equal(game.effects[0].damage, 80);
  assert.throws(() => applyAction(game, 0, action({ type: 'attack', tile: 100 }), now + 10000));
});

test('shield and defenses reduce incoming damage', () => {
  const game = duel();
  applyAction(game, 1, action({ type: 'shield' }), now);
  applyAction(game, 0, action({ type: 'attack', tile: 95 }), now + 3000);
  tick(game, game.waves[0].arrival + 1);
  assert.equal(game.tiles[95].hp, 205);
});

test('capturing the crystal generates crowns and ends the match', () => {
  const game = duel();
  applyAction(game, 0, action({ type: 'claim' }), now + 3000);
  tick(game, game.waves[0].arrival + 1);
  assert.equal(game.relic.owner, 0);
  game.players[0].score = 79;
  tick(game, game.lastTick + 1100);
  assert.equal(game.phase, 'finished');
  assert.equal(game.winner, 0);
  assert.throws(() => applyAction(game, 1, action({ type: 'train' }), now + 10000));
});

test('citadel destruction wins and rematch retains membership and sharing links', () => {
  const game = duel();
  const identity = addHost(game, randomUUID());
  const key = game.inviteKey;
  game.tiles[95].hp = 10;
  applyAction(game, 0, action({ type: 'attack', tile: 95 }), now + 3000);
  tick(game, game.waves[0].arrival + 1);
  assert.equal(game.winner, 0);
  assert.throws(() => applyAction(game, 1, action({ type: 'rematch' }), now + 12000));
  applyAction(game, 0, action({ type: 'rematch' }), now + 12000);
  assert.equal(game.phase, 'playing');
  assert.equal(game.tiles[95].hp, 240);
  assert.equal(game.members[identity.token].seat, 0);
  assert.equal(game.inviteKey, key);
});

test('practice opponent acts, and invitations can replace the bot', () => {
  const game = makeGame({ host: 'Jack', now });
  applyAction(game, 0, action({ type: 'practice' }), now);
  tick(game, now + 5000);
  assert.ok(game.waves.some(w => w.seat === 1));
  const joined = joinPlayer(game, { name: 'Donald', clientId: randomUUID(), invite: game.inviteKey }, now + 6000);
  assert.equal(joined.seat, 1);
  assert.equal(game.players[1].bot, false);
});

test('player seats depend on client identity, including equal commander names', () => {
  const game = makeGame({ host: 'Mira', now });
  const hostId = randomUUID(), guestId = randomUUID();
  const host = addHost(game, hostId);
  const guest = joinPlayer(game, { name: 'Mira', clientId: guestId, invite: game.inviteKey }, now);
  assert.equal(host.seat, 0);
  assert.equal(guest.seat, 1);
  assert.equal(game.players[0].name, game.players[1].name);
  assert.equal(joinPlayer(game, { name: 'Mira', clientId: hostId, invite: game.inviteKey }, now).token, host.token);
  assert.equal(joinPlayer(game, { name: 'Mira', clientId: guestId, invite: game.inviteKey }, now).token, guest.token);
  assert.throws(() => joinPlayer(game, { name: 'Noah', clientId: randomUUID(), invite: game.inviteKey }, now));
});

test('public snapshots omit player credentials and private capabilities', () => {
  const game = duel();
  addHost(game, randomUUID());
  const snapshot = publicGame(game, now);
  for (const field of ['members', 'inviteKey', 'watchKey', 'processed']) assert.equal(snapshot[field], undefined);
  assert.ok(totals(game, 0).cap >= 20);
});

test('the first decisive arrival ends combat and practice cannot restart an active clock', () => {
  const game = duel();
  game.tiles[95].hp = 1; game.tiles[100].hp = 1;
  applyAction(game, 0, action({ type: 'attack', tile: 95 }), now + 3000);
  applyAction(game, 1, action({ type: 'attack', tile: 100 }), now + 3000);
  tick(game, now + 10000);
  assert.equal(game.winner, 0);
  assert.equal(game.tiles[100].hp, 1);
  assert.equal(game.waves.length, 0);
  const practice = makeGame({ host: 'Jack', now });
  applyAction(practice, 0, action({ type: 'practice' }), now);
  assert.throws(() => applyAction(practice, 0, action({ type: 'practice' }), now + 3000));
});

test('the match clock resolves equal crowns using citadel health', () => {
  const game = duel();
  game.tiles[95].hp = 120;
  tick(game, now + game.duration);
  assert.equal(game.phase, 'finished');
  assert.equal(game.winner, 0);
  const tied = duel();
  tick(tied, now + tied.duration);
  assert.equal(tied.winner, -1);
});

test('private games survive a store restart with resume credentials intact', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'voxel-store-'));
  try {
    const first = new GameStore(directory);
    const created = first.create('Jack', randomUUID(), 'CEO match');
    const second = new GameStore(directory);
    assert.equal(second.games.get(created.game.id).members[created.token].seat, 0);
    assert.equal(second.games.get(created.game.id).watchKey, created.game.watchKey);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

function waitMessage(socket, predicate, timeout = 3000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { socket.off('message', handler); reject(new Error('WebSocket message timeout')); }, timeout);
    const handler = raw => {
      const message = JSON.parse(raw.toString());
      if (predicate(message)) { clearTimeout(timer); socket.off('message', handler); resolve(message); }
    };
    socket.on('message', handler);
  });
}

test('HTTP and WebSocket flow isolates rooms and enforces read-only spectators', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'voxel-http-'));
  const app = createServer({ directory, ticking: false });
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  const base = 'http://127.0.0.1:' + app.server.address().port;
  const call = async (route, body, token) => {
    const response = await fetch(base + route, { method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: response.status, ...await response.json() };
  };
  try {
    const first = await call('/api/games', { name: 'Mira', clientId: randomUUID() });
    const other = await call('/api/games', { name: 'Noah', clientId: randomUUID() });
    const legacy = await call('/api/demo', { name: 'Aria', clientId: randomUUID() });
    const anotherLegacy = await call('/api/demo', { name: 'Aria', clientId: randomUUID() });
    assert.equal(legacy.status, 200);
    assert.equal(legacy.game.players[0].name, 'Aria');
    assert.notEqual(legacy.game.id, anotherLegacy.game.id);
    const id = first.game.id;
    assert.equal((await call(`/api/games/${other.game.id}/state`, null, first.token)).status, 401);
    assert.equal((await call(`/api/games/${id}/state`, null, '__proto__')).status, 401);
    const invitation = new URL(first.links.invite).searchParams.get('key');
    const watch = new URL(first.links.watch).searchParams.get('key');
    assert.equal((await call(`/api/games/${id}/join`, { name: 'Donald', clientId: randomUUID(), key: 'invalid' })).status, 400);
    const second = await call(`/api/games/${id}/join`, { name: 'Noah', clientId: randomUUID(), key: invitation });
    assert.equal(second.seat, 1);
    assert.equal(second.game.players[0].name, 'Mira');
    assert.equal(second.game.players[1].name, 'Noah');
    assert.equal((await call(`/api/games/${id}/join`, { name: 'Third', clientId: randomUUID(), key: invitation })).status, 400);
    assert.equal((await call(`/api/games/${id}/view?key=invalid`)).status, 403);
    assert.equal((await call(`/api/games/${id}/action`, action({ type: 'train' }), watch)).status, 401);
    const player = new WebSocket(base.replace('http', 'ws') + '/live?game=' + id, ['voxel-v2', 'session.' + first.token]);
    const viewer = new WebSocket(base.replace('http', 'ws') + `/live?game=${id}&watch=${watch}`, ['voxel-v2']);
    await Promise.all([waitMessage(player, m => m.type === 'state'), waitMessage(viewer, m => m.type === 'state')]);
    const observed = waitMessage(viewer, m => m.type === 'state' && m.game.tiles[44].kind === 'tower');
    const started = Date.now();
    player.send(JSON.stringify(action({ type: 'build', kind: 'tower', tile: 44 })));
    const update = await observed;
    assert.equal(update.role, 'spectator');
    assert.ok(Date.now() - started < 800, 'push updates should not wait for a polling interval');
    assert.equal(update.links.invite, undefined);
    const rejected = action({ type: 'build', kind: 'house', tile: 45 });
    const denied = waitMessage(viewer, m => m.type === 'error' && m.requestId === rejected.requestId);
    viewer.send(JSON.stringify(rejected));
    assert.match((await denied).error, /Spectators/);
    const malformed = waitMessage(player, m => m.type === 'error');
    player.send('null');
    assert.match((await malformed).error, /Invalid game action/);
    const retry = action({ type: 'build', kind: 'house', tile: 45 });
    const built = await call(`/api/games/${id}/action`, retry, first.token);
    const resumed = new WebSocket(base.replace('http', 'ws') + '/live?game=' + id, { headers: { Authorization: 'Bearer ' + first.token } });
    const restored = await waitMessage(resumed, m => m.type === 'state');
    assert.equal(restored.game.tiles[45].kind, 'house');
    const retried = waitMessage(resumed, m => m.type === 'ack' && m.requestId === retry.requestId);
    resumed.send(JSON.stringify(retry));
    await retried;
    assert.equal((await call(`/api/games/${id}/state`, null, first.token)).game.players[0].gold, built.game.players[0].gold);
    resumed.close();
    const separate = await call(`/api/games/${other.game.id}/state`, null, other.token);
    assert.equal(separate.game.tiles[44].kind, 'empty');
    player.close(); viewer.close();
  } finally { await app.close(); fs.rmSync(directory, { recursive: true, force: true }); }
});
