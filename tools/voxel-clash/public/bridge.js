const VOXEL_BROWSER = true;
const voxelListeners = new Map();
const voxelSession = {
  socket: null, credential: null, latest: {}, connected: false, loading: false, attempts: 0,
  pending: new Map(), timer: null, pingAt: 0, latency: 0,
  name: sessionStorage.getItem('voxel.name') || 'Explorer',
  clientId: sessionStorage.getItem('voxel.client') || crypto.randomUUID(),
};
sessionStorage.setItem('voxel.client', voxelSession.clientId);
function emitVoxel(extra = {}) {
  const result = { ...voxelSession.latest, connected: voxelSession.connected, loading: voxelSession.loading, latency: voxelSession.latency, ...extra };
  for (const listener of voxelListeners.get('voxelState') || []) listener(result);
}
function voxelError(error) { emitVoxel({ error: error.message || String(error) }); }
async function voxelAPI(route, body) {
  voxelSession.loading = true; emitVoxel();
  try {
    const response = await fetch(route, { method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Could not connect to this match.');
    return result;
  } finally { voxelSession.loading = false; }
}
function voxelAdopt(result, watchKey = null) {
  clearTimeout(voxelSession.timer);
  const previous = voxelSession.socket; voxelSession.socket = null;
  if (previous) previous.close();
  voxelSession.connected = false; voxelSession.pending.clear();
  const credential = { id: result.game.id, role: watchKey ? 'spectator' : 'player', token: result.token, watch: watchKey };
  voxelSession.credential = credential;
  sessionStorage.setItem('voxel.match.' + result.game.id + '.' + credential.role, JSON.stringify(credential));
  const { token, ...safe } = result;
  voxelSession.latest = safe;
  emitVoxel();
  document.getElementById('entry').replaceChildren();
  const link = watchKey ? result.links.watch : result.links.invite;
  if (link) history.replaceState(null, '', new URL(link).pathname + new URL(link).search);
  updateTelegramLink();
  voxelConnect();
}
function voxelConnect() {
  const credential = voxelSession.credential;
  if (!credential || voxelSession.socket) return;
  const url = new URL('/live', location.href); url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  url.searchParams.set('game', credential.id);
  if (credential.watch) url.searchParams.set('watch', credential.watch);
  const socket = new WebSocket(url, credential.token ? ['voxel-v2', 'session.' + credential.token] : ['voxel-v2']);
  voxelSession.socket = socket;
  socket.onmessage = event => {
    if (voxelSession.socket !== socket) return;
    const message = JSON.parse(event.data);
    if (message.type === 'state') {
      const fresh = !voxelSession.connected;
      voxelSession.connected = true; voxelSession.attempts = 0; voxelSession.latest = message; emitVoxel();
      if (fresh) for (const action of voxelSession.pending.values()) socket.send(JSON.stringify(action));
    } else if (message.type === 'ack') voxelSession.pending.delete(message.requestId);
    else if (message.type === 'error') { if (message.requestId) voxelSession.pending.delete(message.requestId); else voxelSession.pending.clear(); voxelError(message.error); }
    else if (message.type === 'pong') voxelSession.latency = Math.max(1, Date.now() - voxelSession.pingAt);
  };
  socket.onerror = () => {};
  socket.onclose = () => {
    if (voxelSession.socket !== socket) return;
    voxelSession.socket = null; voxelSession.connected = false; voxelSession.attempts++;
    emitVoxel({ error: 'Reconnecting to the live match…' });
    voxelSession.timer = setTimeout(voxelConnect, Math.min(12000, Math.pow(1.6, voxelSession.attempts) * 1000));
  };
}
async function voxelJoinLink(text) {
  const url = new URL(text, location.href), parts = url.pathname.split('/').filter(Boolean), key = url.searchParams.get('key');
  if (url.origin !== location.origin || !['play', 'watch'].includes(parts[0]) || parts.length !== 2 || !key || key.length < 24) throw new Error('Paste an invitation or spectator link for this Voxel Clash server.');
  if (parts[0] === 'watch') voxelAdopt(await voxelAPI(`/api/games/${parts[1]}/view?key=${encodeURIComponent(key)}`), key);
  else voxelAdopt(await voxelAPI(`/api/games/${parts[1]}/join`, { name: voxelSession.name, clientId: voxelSession.clientId, key }));
}
async function voxelAction(action) {
  try {
    if (action.type === 'create') { voxelAdopt(await voxelAPI('/api/games', { name: voxelSession.name, clientId: voxelSession.clientId, title: `${voxelSession.name}’s sky kingdom` })); return; }
    if (action.type === 'demo') { showEntry('create', 'Create a private game or paste an invitation.'); return; }
    if (action.type === 'joinClipboard') { showEntry('link'); return; }
    if (action.type === 'copyInvite' || action.type === 'copyWatch') {
      const link = voxelSession.latest.links?.[action.type === 'copyInvite' ? 'invite' : 'watch'];
      if (!link) throw new Error('Create or join a game first.');
      await navigator.clipboard.writeText(link);
      emitVoxel({ notice: action.type === 'copyInvite' ? 'Invitation copied. Send it to your rival.' : 'Spectator link copied. Anyone with the link can watch live.' }); return;
    }
    if (action.type === 'openWatch') { const url = voxelSession.latest.links?.watch; if (url) window.open(url, '_blank', 'noopener'); return; }
    if (action.type === 'sync') return;
    if (voxelSession.credential?.role === 'spectator') throw new Error('Spectators can watch, but cannot change the game.');
    if (!voxelSession.connected || voxelSession.socket?.readyState !== WebSocket.OPEN) throw new Error('Reconnecting. Please try again in a moment.');
    if (voxelSession.pending.size >= 8) throw new Error('Waiting for your previous actions…');
    action.requestId = crypto.randomUUID(); voxelSession.pending.set(action.requestId, action);
    voxelSession.socket.send(JSON.stringify(action));
  } catch (error) { voxelError(error); }
}
globalThis.TelegramWidget = {
  sendMessage(text) { if (text.startsWith('voxel:')) voxelAction(JSON.parse(text.slice(6))); },
  on(name, listener) { voxelListeners.set(name, [...(voxelListeners.get(name) || []), listener]); },
};
function updateTelegramLink() {
  const link = document.getElementById('telegram-link');
  link.href = 'tg://voxelclash?url=' + encodeURIComponent(location.href);
  link.hidden = !/^\/(play|watch)\//.test(location.pathname);
}
function showEntry(mode = 'create', message = '') {
  const entry = document.getElementById('entry');
  entry.innerHTML = '<form class="entry" id="match-form"><h1>' + (mode === 'join' ? 'Your rival is waiting.' : mode === 'link' ? 'Join a live kingdom.' : 'A kingdom of your own.') + '</h1><p>' + (message || (mode === 'join' ? 'Build your city, command an army, and battle for the Sky Crystal.' : 'Create a private match, invite a rival, and share the battle with live spectators.')) + '</p><label for="player-name">Your commander name</label><input id="player-name" maxlength="24" autocomplete="nickname" required>' + (mode === 'link' ? '<label for="game-link">Invitation or spectator link</label><input id="game-link" type="url" placeholder="Paste your game link" required>' : '') + '<button class="primary" type="submit">' + (mode === 'join' ? 'Join the match' : mode === 'link' ? 'Open match' : 'Create a private match') + '</button><p class="entryerror" id="entry-error"></p></form>';
  const input = document.getElementById('player-name'); input.value = voxelSession.name === 'Explorer' ? '' : voxelSession.name;
  document.getElementById('match-form').onsubmit = async event => {
    event.preventDefault();
    voxelSession.name = input.value.trim(); sessionStorage.setItem('voxel.name', voxelSession.name);
    const submit = event.currentTarget.querySelector('button'); submit.disabled = true; submit.textContent = 'Opening your kingdom…';
    try {
      if (mode === 'join') await voxelJoinLink(location.href);
      else if (mode === 'link') await voxelJoinLink(document.getElementById('game-link').value);
      else voxelAdopt(await voxelAPI('/api/games', { name: voxelSession.name, clientId: voxelSession.clientId }));
    } catch (error) { document.getElementById('entry-error').textContent = error.message; submit.disabled = false; submit.textContent = 'Try again'; }
  };
  entry.scrollIntoView({ behavior: 'smooth', block: 'start' });
}
setInterval(() => { if (voxelSession.socket?.readyState === WebSocket.OPEN) { voxelSession.pingAt = Date.now(); voxelSession.socket.send(JSON.stringify({ type: 'ping' })); } }, 5000);
