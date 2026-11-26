import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';
import { GameStore } from './store.mjs';
import { joinPlayer, applyAction, tick, publicGame } from './engine.mjs';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), 'public');
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
const nameOf = value => typeof value === 'string' && value.trim().length > 0 && value.trim().length <= 24 ? value.trim() : null;
const validClient = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{20,100}$/.test(value);

export function createServer({ directory = process.env.RAILWAY_VOLUME_MOUNT_PATH || process.env.DATA_DIR || '/tmp/voxel-clash', origin = process.env.PUBLIC_URL || 'https://voxel-clash-production.up.railway.app', ticking = true } = {}) {
  const store = new GameStore(directory);
  const sockets = new Map();
  const limits = new Map();
  let dirty = false;
  const base = origin.replace(/\/$/, '');
  const links = game => ({ invite: `${base}/play/${game.id}?key=${game.inviteKey}`, watch: `${base}/watch/${game.id}?key=${game.watchKey}` });
  const watchers = game => [...(sockets.get(game.id) || [])].filter(s => s.viewer && s.readyState === WebSocket.OPEN).length;
  const envelope = (game, member, extras = {}) => ({ type: 'state', game: publicGame(game, Date.now(), watchers(game)), seat: member?.seat ?? null, role: member ? 'player' : 'spectator', links: member ? links(game) : { watch: links(game).watch }, ...extras });
  const broadcast = game => {
    for (const socket of sockets.get(game.id) || []) {
      if (socket.readyState !== WebSocket.OPEN) continue;
      if (socket.bufferedAmount > 256 * 1024) { socket.close(1013, 'Reconnect for a fresh snapshot'); continue; }
      socket.send(JSON.stringify(envelope(game, socket.member)));
    }
  };
  function json(response, status, value) {
    response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' });
    response.end(JSON.stringify(value));
  }
  async function readBody(request) {
    let size = 0, result = '';
    for await (const chunk of request) { size += chunk.length; if (size > 8192) throw new Error('Request is too large.'); result += chunk; }
    const data = JSON.parse(result || '{}');
    if (!data || Array.isArray(data) || typeof data !== 'object') throw new Error('Invalid request.');
    return data;
  }
  const tokenOf = request => {
    const auth = request.headers.authorization;
    if (typeof auth === 'string' && auth.startsWith('Bearer ')) return auth.slice(7);
    const protocols = String(request.headers['sec-websocket-protocol'] || '').split(',').map(p => p.trim());
    return protocols.find(p => p.startsWith('session.'))?.slice(8);
  };
  const memberOf = (game, request) => {
    const token = tokenOf(request);
    return typeof token === 'string' && Object.hasOwn(game.members, token) ? game.members[token] : null;
  };
  const address = request => request.socket.remoteAddress || 'local';
  function rate(request, key, maximum) {
    const id = address(request) + ':' + key, now = Date.now();
    let item = limits.get(id);
    if (!item || item.until < now) { item = { count: 0, until: now + 60000 }; limits.set(id, item); }
    item.count++;
    if (limits.size > 5000) for (const [id, item] of limits) if (item.until < now) limits.delete(id);
    return item.count <= maximum;
  }
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, base), route = url.pathname;
      if (route === '/health') return json(response, 200, { ok: true, version: 2, transport: 'websocket', games: store.games.size });
      if (route.startsWith('/api/')) {
        if (!rate(request, 'api', 600)) return json(response, 429, { error: 'Too many requests. Please wait a moment.' });
        if (request.method === 'POST' && ['/api/games', '/api/demo'].includes(route)) {
          if (!rate(request, 'create', 40)) return json(response, 429, { error: 'Please reuse your existing match for a moment.' });
          const body = await readBody(request), name = nameOf(body.name);
          if (!name || !validClient(body.clientId)) return json(response, 400, { error: 'Choose a valid player name.' });
          if (body.title !== undefined && (typeof body.title !== 'string' || body.title.length > 60)) return json(response, 400, { error: 'Match names must be under 60 characters.' });
          const result = store.create(name, body.clientId, body.title);
          broadcast(result.game);
          return json(response, 200, envelope(result.game, { seat: result.seat }, { token: result.token }));
        }
        const match = /^\/api\/games\/([a-zA-Z0-9-]{1,40})(?:\/(join|view|state|action))?$/.exec(route);
        if (!match) return json(response, 404, { error: 'Unknown game endpoint.' });
        const game = store.games.get(match[1]);
        if (!game) return json(response, 404, { error: 'This match could not be found. Create a new game.' });
        const operation = match[2] || 'state';
        if (operation === 'join' && request.method === 'POST') {
          const body = await readBody(request);
          const identity = joinPlayer(game, { name: body.name, clientId: body.clientId, invite: body.key });
          dirty = true; store.save(); broadcast(game);
          return json(response, 200, envelope(game, { seat: identity.seat }, { token: identity.token }));
        }
        if (operation === 'view' && request.method === 'GET') {
          if (url.searchParams.get('key') !== game.watchKey) return json(response, 403, { error: 'This spectator link is invalid.' });
          return json(response, 200, envelope(game, null));
        }
        const member = memberOf(game, request);
        if (!member) return json(response, 401, { error: 'Your player session is unavailable. Reopen your invitation.' });
        game.players[member.seat].lastSeen = Date.now();
        if (operation === 'state' && request.method === 'GET') return json(response, 200, envelope(game, member));
        if (operation === 'action' && request.method === 'POST') {
          const body = await readBody(request);
          applyAction(game, member.seat, body); dirty = true; store.save(); broadcast(game);
          return json(response, 200, envelope(game, member, { ack: body.requestId }));
        }
        return json(response, 405, { error: 'Unsupported operation.' });
      }
      if (request.method !== 'GET' && request.method !== 'HEAD') return json(response, 405, { error: 'Unsupported operation.' });
      const asset = route === '/' || /^\/(play|watch)\/[a-zA-Z0-9-]+$/.test(route) ? 'index.html' : route.replace(/^\//, '');
      const file = path.resolve(root, asset);
      if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) return json(response, 404, { error: 'Page not found.' });
      response.writeHead(200, {
        'Content-Type': types[path.extname(file)] || 'application/octet-stream',
        'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
        'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' wss: ws:; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'",
      });
      if (request.method === 'HEAD') response.end(); else fs.createReadStream(file).pipe(response);
    } catch (error) {
      json(response, 400, { error: error instanceof SyntaxError ? 'Invalid JSON request.' : error.message || 'The action could not be completed.' });
    }
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 8192, perMessageDeflate: false, handleProtocols: protocols => protocols.has('voxel-v2') ? 'voxel-v2' : false });
  server.on('upgrade', (request, socket, head) => {
    try {
      const url = new URL(request.url, base), game = store.games.get(url.searchParams.get('game'));
      const member = game && memberOf(game, request);
      const viewer = game && url.searchParams.get('watch') === game.watchKey;
      const suppliedOrigin = request.headers.origin;
      const allowedOrigin = !suppliedOrigin || suppliedOrigin === base || suppliedOrigin === `http://${request.headers.host}`;
      if (url.pathname !== '/live' || !game || (!member && !viewer) || !allowedOrigin || !rate(request, 'upgrade', 120)) {
        socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n'); return;
      }
      wss.handleUpgrade(request, socket, head, connection => {
        connection.gameId = game.id; connection.member = member || null; connection.viewer = !member; connection.alive = true; connection.actions = [];
        if (!sockets.has(game.id)) sockets.set(game.id, new Set());
        sockets.get(game.id).add(connection);
        if (member) game.players[member.seat].lastSeen = Date.now();
        connection.on('pong', () => { connection.alive = true; if (member) game.players[member.seat].lastSeen = Date.now(); });
        connection.on('error', () => {});
        connection.on('close', () => { sockets.get(game.id)?.delete(connection); broadcast(game); });
        connection.on('message', raw => {
          let requestId;
          try {
            const action = JSON.parse(raw.toString());
            if (!action || typeof action !== 'object' || Array.isArray(action)) throw new Error('Invalid game action.');
            if (typeof action.requestId === 'string' && action.requestId.length <= 100) requestId = action.requestId;
            if (action.type === 'ping') { connection.send(JSON.stringify({ type: 'pong', at: Date.now() })); if (member) game.players[member.seat].lastSeen = Date.now(); return; }
            if (!member) throw new Error('Spectators can watch, but cannot change the game.');
            const now = Date.now();
            connection.actions = connection.actions.filter(t => now - t < 1000);
            if (connection.actions.length >= 5) throw new Error('Please wait for your previous action.');
            connection.actions.push(now);
            game.players[member.seat].lastSeen = now;
            applyAction(game, member.seat, action, now); dirty = true; broadcast(game);
            connection.send(JSON.stringify({ type: 'ack', requestId: action.requestId, revision: game.revision }));
          } catch (error) { connection.send(JSON.stringify({ type: 'error', requestId, error: error.message })); }
        });
        broadcast(game);
      });
    } catch { socket.destroy(); }
  });
  const simulation = ticking ? setInterval(() => { for (const game of store.games.values()) if (tick(game)) { dirty = true; broadcast(game); } }, 100) : null;
  const persistence = setInterval(() => { if (dirty) { store.save(); dirty = false; } }, 1000);
  const heartbeat = setInterval(() => {
    for (const connection of wss.clients) {
      if (!connection.alive) { connection.terminate(); continue; }
      connection.alive = false; connection.ping();
    }
  }, 6000);
  const close = async () => {
    clearInterval(simulation); clearInterval(persistence); clearInterval(heartbeat); store.save();
    for (const connection of wss.clients) connection.terminate();
    wss.close();
    await new Promise(resolve => server.close(resolve));
  };
  return { server, store, close, broadcast };
}
