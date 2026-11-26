import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';

const base = process.env.VOXEL_DEMO_URL || 'https://voxel-clash-production.up.railway.app';
const sockets = [];
async function request(route, body, token) {
  const response = await fetch(base + route, {
    method: body ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(15000),
  });
  return { status: response.status, ...await response.json() };
}
function message(socket, predicate, timeout = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { cleanup(); reject(new Error('Live update timed out')); }, timeout);
    const cleanup = () => { clearTimeout(timer); socket.off('message', received); socket.off('error', failed); };
    const failed = error => { cleanup(); reject(error); };
    const received = raw => {
      const value = JSON.parse(raw.toString());
      if (predicate(value)) { cleanup(); resolve(value); }
    };
    socket.on('message', received); socket.once('error', failed);
  });
}
function live(id, token, watch) {
  const url = new URL('/live', base); url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.searchParams.set('game', id);
  if (watch) url.searchParams.set('watch', watch);
  const socket = new WebSocket(url, token ? ['voxel-v2', 'session.' + token] : ['voxel-v2']);
  sockets.push(socket);
  return socket;
}
try {
  const health = await request('/health');
  assert.equal(health.version, 2);
  assert.equal(health.transport, 'websocket');
  const jack = await request('/api/games', { name: 'Jack', clientId: randomUUID(), title: 'Automated demo verification' });
  assert.equal(jack.status, 200);
  const id = jack.game.id, invite = new URL(jack.links.invite).searchParams.get('key'), watch = new URL(jack.links.watch).searchParams.get('key');
  const donald = await request(`/api/games/${id}/join`, { name: 'Donald', clientId: randomUUID(), key: invite });
  assert.equal(donald.status, 200); assert.equal(donald.seat, 1);
  assert.equal((await request(`/api/games/${id}/state`)).status, 401);
  assert.equal((await request(`/api/games/${id}/view?key=invalid`)).status, 403);
  const player = live(id, jack.token), rival = live(id, donald.token), viewer = live(id, null, watch);
  await Promise.all([player, rival, viewer].map(socket => message(socket, m => m.type === 'state')));
  const build = { type: 'build', tile: 44, kind: 'house', requestId: randomUUID() };
  const observed = message(viewer, m => m.type === 'state' && m.game.tiles[44].kind === 'house');
  const rivalObserved = message(rival, m => m.type === 'state' && m.game.tiles[44].kind === 'house');
  const ack = message(player, m => m.type === 'ack' && m.requestId === build.requestId);
  const started = Date.now(); player.send(JSON.stringify(build));
  const update = await observed; const pushLatency = Date.now() - started;
  await Promise.all([rivalObserved, ack]);
  assert.equal(update.role, 'spectator'); assert.equal(update.links.invite, undefined);
  assert.equal((await request(`/api/games/${id}/action`, build, jack.token)).status, 200);
  const deniedId = randomUUID(), denied = message(viewer, m => m.type === 'error' && m.requestId === deniedId);
  viewer.send(JSON.stringify({ type: 'train', requestId: deniedId }));
  assert.match((await denied).error, /Spectators/);
  const attack = { type: 'attack', tile: 95, requestId: randomUUID() };
  const impact = message(viewer, m => m.type === 'state' && m.game.tiles[95].hp === 160);
  player.send(JSON.stringify(attack)); await impact;
  player.close();
  const resumed = live(id, jack.token);
  const restored = await message(resumed, m => m.type === 'state');
  assert.equal(restored.game.id, id); assert.equal(restored.game.tiles[44].kind, 'house');
  console.log(`PASS: private invitations, live players, read-only spectators, combat, idempotency and reconnect. Railway push: ${pushLatency} ms. Verification match: ${id}.`);
} finally {
  for (const socket of sockets) socket.terminate();
}
