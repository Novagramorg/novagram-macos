const BROWSER = typeof VOXEL_BROWSER !== 'undefined' && VOXEL_BROWSER;
const BOARD = 14;
const PALETTE = [0x6bd2ba, 0xe9a57a];
const RULES_UI = {
  house: { name: 'Cottage', cost: 45, detail: '+2 gold/s · +4 army capacity', icon: 'house' },
  farm: { name: 'Windmill', cost: 60, detail: '+3 food/s · feeds your army', icon: 'wind' },
  quarry: { name: 'Crystal mine', cost: 80, detail: '+2 energy/s · powers meteors and shields', icon: 'diamond' },
  barracks: { name: 'Barracks', cost: 100, detail: 'Trains knights automatically', icon: 'flag' },
  tower: { name: 'Watchtower', cost: 110, detail: 'Reduces damage near your buildings', icon: 'tower' },
  wall: { name: 'Rampart', cost: 25, detail: 'Durable cover for neighboring buildings', icon: 'wall' },
  nexus: { name: 'Citadel', cost: 0, detail: 'Protect your citadel. Its fall ends the match.', icon: 'crown' },
};
const ICON_PATHS = {
  crown: '<path d="M3 7l4 4 5-7 5 7 4-4-2 12H5z"/><path d="M7 22h10"/>',
  house: '<path d="M3 11l9-8 9 8M5 10v11h14V10M10 21v-7h4v7"/>',
  wind: '<path d="M8 22l2-12h4l2 12M12 10V2M12 10l8-5M12 10l-8 5M12 10l8 5M12 10L4 5"/>',
  diamond: '<path d="M12 2l9 10-9 10L3 12zM3 12h18M12 2l-4 10 4 10 4-10z"/>',
  flag: '<path d="M5 22V3h14l-3 5 3 5H5"/>',
  tower: '<path d="M5 3v5h14V3M5 3h3v3h3V3h3v3h3V3h2M7 8v13h10V8M10 21v-6h4v6"/>',
  wall: '<path d="M3 7h18v14H3zM3 13h18M8 7v6M16 7v6M12 13v8M3 3v4M9 3v4M15 3v4M21 3v4"/>',
  sword: '<path d="M20 3l1 4L9 18l-3-3L17 3zM4 13l7 7M7 17l-4 4"/>',
  shield: '<path d="M12 2l9 4v6c0 5-9 10-9 10S3 17 3 12V6zM8 12l3 3 5-6"/>',
  eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  link: '<path d="M9 15l6-6M7 14l-2 2a4 4 0 005 5l4-4a4 4 0 000-6M17 10l2-2a4 4 0 00-5-5l-4 4a4 4 0 000 6"/>',
  copy: '<path d="M8 8h13v13H8zM4 16H2V2h14v2"/>',
  menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
  help: '<circle cx="12" cy="12" r="10"/><path d="M9 9a3 3 0 116 0c0 2-3 2-3 5M12 18h.01"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
};
function icon(name, size = 16) { return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' + (ICON_PATHS[name] || ICON_PATHS.diamond) + '</svg>'; }
function esc(text) { return String(text == null ? '' : text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
function coord(id) { return String.fromCharCode(65 + id % BOARD) + (Math.floor(id / BOARD) + 1); }
function worldPosition(id) { return { x: id % BOARD - 6.5, z: Math.floor(id / BOARD) - 6.5 }; }
let game = null, seat = null, role = 'player', links = {}, connected = false, loading = true, latency = 0, selected = 87;
let tab = 'economy', dialog = '', toast = '', toastError = false, toastUntil = 0, dirty = true, cachedHTML = '', clockSecond = -1, serverOffset = 0;
let cameraAngle = 0.72, cameraElevation = Math.atan2(15, 21), cameraZoom = 1, night = false, structureKey = '', boardSeed = null, windmills = [], construction = [], drag = null;
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, cornerRadius: 0 });
if (BROWSER) {
  renderer.isSupported = true;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  document.querySelector('[data-3d]').appendChild(renderer.domElement);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;
}
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x152a40);
scene.fog = new THREE.Fog(0x152a40, 28, 58);
const camera = new THREE.PerspectiveCamera(35, 1.6, 0.1, 90);
const ambient = new THREE.HemisphereLight(0xc7efff, 0x38435b, 1.6);
scene.add(ambient);
const sun = new THREE.DirectionalLight(0xffe5b2, 2.35);
sun.position.set(-8, 16, 9); scene.add(sun);
const crystalLight = new THREE.PointLight(0x81caff, 4, 10, 1.5);
crystalLight.position.set(-0.5, 2, -0.5); scene.add(crystalLight);
const GEOMETRY = { box: new THREE.BoxGeometry(1, 1, 1), cylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 8), cone: new THREE.ConeGeometry(0.5, 1, 6), sphere: new THREE.IcosahedronGeometry(0.5, 1) };
const instanceMaterial = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.82, metalness: 0.05 });
const materials = {};
function mat(color, emissive = 0) {
  const key = color + ':' + emissive;
  return materials[key] || (materials[key] = new THREE.MeshStandardMaterial({ color, roughness: 0.7, emissive: emissive || 0x000000, emissiveIntensity: emissive ? 0.6 : 0 }));
}
function mesh(parent, shape, x, y, z, sx, sy, sz, color, emissive = 0) {
  const object = new THREE.Mesh(GEOMETRY[shape], mat(color, emissive));
  object.position.set(x, y, z); object.scale.set(sx, sy, sz); parent.add(object); return object;
}
const tempPosition = new THREE.Vector3(), tempScale = new THREE.Vector3(), tempQuaternion = new THREE.Quaternion(), tempMatrix = new THREE.Matrix4(), tempColor = new THREE.Color();
function item(shape, x, y, z, sx, sy, sz, color, rotation = 0, tile = null) {
  return { shape, x, y, z, sx, sy, sz, color, quaternion: new THREE.Quaternion().setFromEuler(new THREE.Euler(0, rotation, 0)), tile };
}
function instantiate(items, parent, animated = false) {
  const groups = {};
  for (const entry of items) (groups[entry.shape] || (groups[entry.shape] = [])).push(entry);
  for (const shape of Object.keys(groups)) {
    const entries = groups[shape], object = new THREE.InstancedMesh(GEOMETRY[shape], instanceMaterial, entries.length);
    for (let i = 0; i < entries.length; i++) { object.setColorAt(i, tempColor.setHex(entries[i].color)); setInstance(object, i, entries[i], 1); }
    object.instanceMatrix.needsUpdate = true; object.instanceColor.needsUpdate = true;
    object.frustumCulled = false;
    parent.add(object);
    if (animated) construction.push({ object, entries });
  }
}
function setInstance(object, index, entry, grow) {
  const base = entry.tile ? entry.tile.height + 0.03 : 0;
  tempPosition.set(entry.x, entry.tile ? base + (entry.y - base) * grow : entry.y, entry.z);
  tempScale.set(entry.sx * (0.85 + grow * 0.15), entry.sy * grow, entry.sz * (0.85 + grow * 0.15));
  tempMatrix.compose(tempPosition, entry.quaternion, tempScale); object.setMatrixAt(index, tempMatrix);
}
function disposeGroup(group) { scene.remove(group); group.traverse(object => { if (object.isInstancedMesh && typeof object.dispose === 'function') object.dispose(); }); }
let board = new THREE.Group(), buildings = new THREE.Group(); scene.add(board); scene.add(buildings);
function previewTiles() {
  const tiles = [];
  for (let z = 0; z < BOARD; z++) for (let x = 0; x < BOARD; x++) {
    const water = x === 0 || z === 0 || x === 13 || z === 13 || ((x === 6 || x === 7) && z !== 6 && z !== 7);
    tiles.push({ id: z * BOARD + x, owner: x < 6 ? 0 : x > 7 ? 1 : -1, terrain: water ? 'water' : (x === 6 || x === 7) ? 'bridge' : 'grass', height: 0.14, kind: 'empty', level: 0, hp: 0, maxHp: 0, builtAt: 0 });
  }
  for (const [id, kind] of [[100, 'nexus'], [86, 'house'], [114, 'farm'], [101, 'barracks'], [95, 'nexus'], [81, 'house'], [109, 'farm'], [94, 'barracks']]) Object.assign(tiles[id], { kind, level: 1, hp: 100, maxHp: 100 });
  return tiles;
}
const preview = previewTiles();
function buildBoard(tiles, seed) {
  disposeGroup(board); board = new THREE.Group(); scene.add(board);
  const parts = [];
  parts.push(item('box', 0, -1.1, 0, 38, 0.4, 38, 0x123347));
  for (const side of [-1, 1]) {
    const x = side * 3.5;
    parts.push(item('box', x, -0.42, 0, 5.18, 1.04, 12.22, 0x394b5d));
    parts.push(item('box', x, -0.05, 0, 5.18, 0.25, 12.22, 0x7c9b79));
    for (let i = 0; i < 8; i++) parts.push(item('cone', x + Math.sin(i * 2.4) * 1.6, -1.1 - (i % 3) * 0.13, i * 1.4 - 5, 1.4, 2.8, 1.7, i % 2 ? 0x34495a : 0x2b4053, i, null));
  }
  for (const tile of tiles) {
    if (tile.terrain === 'water') continue;
    const p = worldPosition(tile.id), variation = (tile.id * 7 + seed) % 4;
    const color = tile.terrain === 'bridge' ? 0xbcae8a : tile.owner === 0 ? [0x6f9a7e, 0x739f81, 0x769d7c, 0x6d9578][variation] : [0x9f9d70, 0xa8a273, 0xa39e6e, 0xaaa579][variation];
    parts.push(item('box', p.x, tile.height - 0.05, p.z, 0.97, 0.16, 0.97, color));
    if (tile.terrain === 'bridge') parts.push(item('box', p.x, -0.08, p.z, 1, 0.3, 1, 0x686b64));
  }
  for (let z = -5.5; z < 6; z += 0.5) parts.push(item('box', 0, -0.52, z, 0.055, 0.016, 0.18, 0x518398));
  instantiate(parts, board);
  boardSeed = seed;
}
function buildStructures(tiles) {
  disposeGroup(buildings); buildings = new THREE.Group(); scene.add(buildings); construction = []; windmills = [];
  const parts = [];
  const add = (tile, shape, x, y, z, sx, sy, sz, color, rotation = 0) => { const p = worldPosition(tile.id); parts.push(item(shape, p.x + x, tile.height + y, p.z + z, sx, sy, sz, color, rotation, tile)); };
  for (const tile of tiles) {
    const p = worldPosition(tile.id);
    if (tile.kind === 'empty') {
      if (tile.terrain === 'grass' && ((tile.id * 13 + (game ? game.seed : 27)) % 11 === 0) && (tile.id % BOARD === 1 || tile.id % BOARD === 12 || Math.floor(tile.id / BOARD) < 3)) {
        add(tile, 'cylinder', 0.18, 0.24, 0.18, 0.12, 0.5, 0.12, 0x6b5744);
        add(tile, 'cone', 0.18, 0.65, 0.18, 0.66, 0.85, 0.66, 0x2e6d61);
        add(tile, 'cone', 0.18, 0.95, 0.18, 0.46, 0.7, 0.46, 0x3e8a72);
      } else if (tile.terrain === 'grass' && tile.id % 19 === 0) {
        add(tile, 'sphere', 0.23, 0.12, 0.24, 0.36, 0.25, 0.4, 0x91a0a2);
      }
      continue;
    }
    const cool = tile.owner === 0, roof = cool ? 0x315f72 : 0x9e604e, stone = cool ? 0xb5d4c9 : 0xe2c2a1, trim = cool ? 0x64bea9 : 0xd69672;
    const level = tile.level || 1, extra = (level - 1) * 0.2;
    add(tile, 'box', 0, 0.04, 0, 0.87, 0.08, 0.87, 0xaaa895);
    if (tile.kind === 'nexus') {
      add(tile, 'box', 0, 0.48, 0, 0.9, 0.92, 0.8, stone);
      add(tile, 'box', 0, 1.05, 0, 0.63, 0.55, 0.58, trim);
      add(tile, 'cone', 0, 1.58 + extra, 0, 0.94, 0.65, 0.94, roof, Math.PI / 4);
      for (const x of [-0.38, 0.38]) for (const z of [-0.34, 0.34]) {
        add(tile, 'cylinder', x, 0.62, z, 0.3, 1.2, 0.3, stone);
        add(tile, 'cone', x, 1.37, z, 0.44, 0.55, 0.44, roof);
      }
      add(tile, 'box', 0, 0.27, 0.41, 0.25, 0.45, 0.045, 0x354b56);
      add(tile, 'cylinder', 0, 2.05 + extra, 0, 0.035, 0.6, 0.035, 0xe7d7aa);
      add(tile, 'box', 0.18, 2.18 + extra, 0, 0.36, 0.22, 0.035, trim);
    } else if (tile.kind === 'house') {
      add(tile, 'box', 0, 0.38 + extra / 2, 0, 0.65, 0.65 + extra, 0.65, stone);
      add(tile, 'cone', 0, 0.9 + extra, 0, 1, 0.55, 1, roof, Math.PI / 4);
      add(tile, 'box', 0, 0.22, 0.34, 0.16, 0.32, 0.03, 0x3e545c);
      for (const x of [-0.19, 0.19]) add(tile, 'box', x, 0.46, 0.34, 0.12, 0.14, 0.03, 0xffdda0);
      add(tile, 'box', 0.19, 1 + extra, -0.15, 0.1, 0.28, 0.11, 0xa8b9b4);
    } else if (tile.kind === 'farm') {
      add(tile, 'box', 0, 0.1, 0, 0.82, 0.1, 0.82, 0x7f6a4b);
      for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) add(tile, 'cone', -0.3 + r * 0.22, 0.3, -0.3 + c * 0.22, 0.13, 0.32, 0.13, 0xe1c774);
      add(tile, 'cylinder', 0.15, 0.57, 0.12, 0.4, 1.02, 0.4, stone);
      add(tile, 'cone', 0.15, 1.21, 0.12, 0.59, 0.4, 0.59, roof);
      const rotor = new THREE.Group(); rotor.position.set(p.x + 0.15, tile.height + 0.94, p.z + 0.37);
      mesh(rotor, 'sphere', 0, 0, 0, 0.12, 0.12, 0.12, 0xe8d7aa);
      for (let r = 0; r < 4; r++) { const blade = mesh(rotor, 'box', 0, 0, 0, 0.1, 0.82, 0.045, 0xeee4bf); blade.rotation.z = r * Math.PI / 2; }
      buildings.add(rotor); windmills.push(rotor);
    } else if (tile.kind === 'quarry') {
      add(tile, 'box', 0, 0.17, 0, 0.76, 0.25, 0.76, 0x697c83);
      for (const [x, z, h] of [[-0.2, -0.1, 0.65], [0.18, 0.12, 0.9], [0, 0.25, 0.45]]) add(tile, 'cone', x, 0.3 + h / 2, z, 0.32, h, 0.32, 0x83c6df, x * 4);
      add(tile, 'box', 0, 0.25, -0.35, 0.85, 0.1, 0.1, 0x9b795b);
    } else if (tile.kind === 'barracks') {
      add(tile, 'box', 0, 0.36, 0, 0.8, 0.6, 0.65, stone);
      add(tile, 'cone', 0, 0.86, 0, 1.08, 0.5, 0.96, roof, Math.PI / 4);
      add(tile, 'box', 0, 0.29, 0.34, 0.3, 0.42, 0.03, 0x35495a);
      for (const x of [-0.35, 0.35]) { add(tile, 'cylinder', x, 1.06, 0, 0.03, 0.9, 0.03, 0xcfc3a3); add(tile, 'box', x + 0.11, 1.4, 0, 0.22, 0.16, 0.03, trim); }
    } else if (tile.kind === 'tower') {
      add(tile, 'cylinder', 0, 0.74 + extra / 2, 0, 0.61, 1.4 + extra, 0.61, stone);
      add(tile, 'cylinder', 0, 1.48 + extra, 0, 0.82, 0.19, 0.82, roof);
      for (const x of [-0.27, 0.27]) for (const z of [-0.27, 0.27]) add(tile, 'box', x, 1.69 + extra, z, 0.2, 0.28, 0.2, stone);
      add(tile, 'cone', 0, 1.94 + extra, 0, 0.58, 0.34, 0.58, roof);
      add(tile, 'box', 0, 0.91, 0.31, 0.11, 0.26, 0.03, 0x445962);
    } else if (tile.kind === 'wall') {
      add(tile, 'box', 0, 0.4, 0, 0.87, 0.72, 0.28, stone);
      for (const x of [-0.3, 0, 0.3]) add(tile, 'box', x, 0.86, 0, 0.2, 0.26, 0.3, trim);
    }
    if (tile.hp < tile.maxHp) {
      add(tile, 'box', 0, 1.02, 0, 0.68, 0.045, 0.06, 0x5d4148);
      add(tile, 'box', -(1 - tile.hp / tile.maxHp) * 0.34, 1.04, 0, 0.68 * tile.hp / tile.maxHp, 0.055, 0.07, tile.hp / tile.maxHp < 0.35 ? 0xe67f70 : 0xe2c37d);
    }
  }
  instantiate(parts, buildings, true);
}
const selectionRing = new THREE.Mesh(new THREE.TorusGeometry(0.55, 0.035, 5, 32), mat(0xffdf91, 0x927138));
selectionRing.rotation.x = Math.PI / 2; scene.add(selectionRing);
const relic = new THREE.Group(); relic.position.set(-0.5, 0.5, -0.5); scene.add(relic);
mesh(relic, 'cylinder', 0, -0.24, 0, 0.72, 0.16, 0.72, 0xbfc5aa);
const gem = mesh(relic, 'cone', 0, 0.48, 0, 0.47, 0.94, 0.47, 0x8ee1ff, 0x4e9dc7);
const gemBottom = mesh(gem, 'cone', 0, -0.5, 0, 1, 0.55, 1, 0x77c8e4, 0x4e9dc7); gemBottom.rotation.z = Math.PI;
const relicHalo = new THREE.Mesh(new THREE.TorusGeometry(0.68, 0.025, 5, 40), mat(0xa8daed, 0x6c9db5)); relicHalo.rotation.x = Math.PI / 2; relic.add(relicHalo);
const shieldMeshes = [0, 1].map(side => { const s = new THREE.Mesh(new THREE.SphereGeometry(1.3, 16, 10), new THREE.MeshStandardMaterial({ color: PALETTE[side], transparent: true, opacity: 0.2, roughness: 0.2, side: THREE.DoubleSide })); const p = worldPosition(side === 0 ? 100 : 95); s.position.set(p.x, 0.85, p.z); s.scale.y = 1.25; s.visible = false; scene.add(s); return s; });
const clouds = [];
for (let i = 0; i < 5; i++) {
  const cloud = new THREE.Group();
  for (let j = 0; j < 3; j++) mesh(cloud, 'sphere', j * 0.55, Math.sin(j * 2) * 0.1, 0, 1.1, 0.35 + j * 0.08, 0.65, 0x8fa6b8);
  cloud.userData.index = i; scene.add(cloud); clouds.push(cloud);
}
const armyBodies = new THREE.InstancedMesh(GEOMETRY.box, instanceMaterial, 256), armyHeads = new THREE.InstancedMesh(GEOMETRY.sphere, instanceMaterial, 256), effects = new THREE.InstancedMesh(GEOMETRY.box, instanceMaterial, 256);
for (const object of [armyBodies, armyHeads, effects]) { object.frustumCulled = false; object.count = 0; scene.add(object); }
const raycaster = new THREE.Raycaster(), ground = new THREE.Plane(new THREE.Vector3(0, 1, 0), -0.15);
buildBoard(preview, 27); buildStructures(preview);

function showToast(message, error = false) { toast = message; toastError = error; toastUntil = performance.now() + 5500; dirty = true; }
function send(action) { if (typeof TelegramWidget !== 'undefined') TelegramWidget.sendMessage('voxel:' + JSON.stringify(action)); }
TelegramWidget.on('voxelState', result => {
  connected = !!result.connected; loading = !!result.loading; latency = result.latency || 0;
  if (result.game) {
    const changedRoom = !game || game.id !== result.game.id;
    game = result.game; seat = typeof result.seat === 'number' ? result.seat : null; role = result.role || 'player'; links = result.links || {};
    serverOffset = game.serverTime - Date.now();
    if (changedRoom) { finishCameraDrag(null, true); selected = seat === 1 ? 80 : 87; dialog = ''; cameraAngle = 0.72; cameraElevation = Math.atan2(15, 21); }
    if (boardSeed !== game.seed) buildBoard(game.tiles, game.seed);
    const key = game.id + ':' + game.tiles.map(t => t.kind + t.level + ':' + t.hp).join('|');
    if (key !== structureKey) { structureKey = key; buildStructures(game.tiles); }
  }
  if (result.error) showToast(result.error, true);
  else if (result.notice) showToast(result.notice);
  dirty = true;
});
function onPointer(x, y) {
  if (!drag) selectPlot(x, y);
}
function selectPlot(x, y) {
  const size = renderer.getSize(new THREE.Vector2());
  raycaster.setFromCamera(new THREE.Vector2(x / Math.max(1, size.x) * 2 - 1, 1 - y / Math.max(1, size.y) * 2), camera);
  const hit = raycaster.ray.intersectPlane(ground, new THREE.Vector3());
  if (!hit) return;
  const tx = Math.floor(hit.x + 7), tz = Math.floor(hit.z + 7);
  if (tx < 0 || tx >= BOARD || tz < 0 || tz >= BOARD) return;
  const tile = (game ? game.tiles : preview)[tz * BOARD + tx];
  if (tile.terrain !== 'water') { selected = tile.id; dirty = true; }
}
function moveCameraDrag(x, y) {
  if (!drag) return;
  const dx = x - drag.startX, dy = y - drag.startY;
  if (!drag.moved && Math.hypot(dx, dy) < 5) return;
  drag.moved = true;
  cameraAngle = drag.angle - dx * 0.008;
  cameraElevation = Math.max(0.3, Math.min(1.2, drag.elevation + dy * 0.006));
}
function finishCameraDrag(event, cancelled = false) {
  if (!drag || (event && event.pointerId !== drag.pointerId)) return;
  if (event && !cancelled) moveCameraDrag(event.clientX, event.clientY);
  const gesture = drag;
  drag = null;
  gesture.stage.style.cursor = 'grab';
  if (gesture.stage.hasPointerCapture && gesture.stage.hasPointerCapture(gesture.pointerId)) gesture.stage.releasePointerCapture(gesture.pointerId);
  if (!cancelled && !gesture.moved) selectPlot(gesture.x, gesture.y);
  dirty = true;
}
function onKey(key) {
  if (key === 'Escape') { finishCameraDrag(null, true); dialog = ''; dirty = true; return; }
  if (key === 'ArrowLeft' || key === 'a') selected = Math.max(0, selected - 1);
  if (key === 'ArrowRight' || key === 'd') selected = Math.min(195, selected + 1);
  if (key === 'ArrowUp' || key === 'w') selected = Math.max(0, selected - BOARD);
  if (key === 'ArrowDown' || key === 's') selected = Math.min(195, selected + BOARD);
  dirty = true;
}
function onAction(action, value) {
  if (action === 'menu') dialog = dialog === 'match' ? '' : 'match';
  else if (action === 'help') dialog = dialog === 'help' ? '' : 'help';
  else if (action === 'close') dialog = '';
  else if (action === 'tab') tab = value;
  else if (action === 'rotate') cameraAngle += Number(value);
  else if (action === 'zoom') cameraZoom = Math.max(0.72, Math.min(1.45, cameraZoom + Number(value)));
  else if (action === 'night') { night = !night; scene.background.setHex(night ? 0x0b1830 : 0x152a40); scene.fog.color.copy(scene.background); sun.intensity = night ? 0.7 : 2.35; ambient.intensity = night ? 1.2 : 1.6; }
  else if (action === 'next') {
    if (game && seat !== null) for (let i = 1; i <= 196; i++) { const tile = game.tiles[(selected + i) % 196]; if (tile.owner === seat && tile.terrain === 'grass' && tile.kind === 'empty') { selected = tile.id; break; } }
  } else if (action === 'rival') { const tile = game && game.tiles.find(t => t.owner !== seat && t.kind === 'nexus'); if (tile) selected = tile.id; }
  else if (action === 'crystal') selected = game ? game.relic.tile : 90;
  else if (action === 'confirmRematch') dialog = 'reset';
  else if (['create', 'demo', 'joinClipboard', 'copyInvite', 'copyWatch', 'openWatch'].includes(action)) { send({ type: action }); if (['create', 'demo', 'joinClipboard'].includes(action)) dialog = ''; }
  else if (role === 'spectator') showToast('You are watching live. Share the spectator link to invite more viewers.');
  else if (!connected) showToast('Connecting to your match. Please wait a moment.', true);
  else if (action === 'build') send({ type: 'build', tile: selected, kind: value });
  else if (['upgrade', 'repair', 'attack', 'meteor'].includes(action)) send({ type: action, tile: selected });
  else if (['train', 'claim', 'shield', 'practice', 'rematch'].includes(action)) { send({ type: action }); if (action === 'rematch') dialog = ''; }
  dirty = true;
}
if (typeof document !== 'undefined') {
  document.addEventListener('pointerdown', event => {
    if (drag || (event.button !== undefined && event.button !== 0)) return;
    const stage = event.target && event.target.closest ? event.target.closest('[data-3d]') : null;
    if (!stage) return;
    const rect = stage.getBoundingClientRect();
    drag = { stage, pointerId: event.pointerId, startX: event.clientX, startY: event.clientY, x: event.clientX - rect.left, y: event.clientY - rect.top, angle: cameraAngle, elevation: cameraElevation, moved: false };
    stage.style.cursor = 'grabbing';
    if (stage.setPointerCapture) stage.setPointerCapture(event.pointerId);
    event.preventDefault();
  });
  document.addEventListener('pointermove', event => {
    if (!drag || event.pointerId !== drag.pointerId) return;
    if (event.buttons === 0) { finishCameraDrag(event, true); return; }
    moveCameraDrag(event.clientX, event.clientY);
    event.preventDefault();
  });
  document.addEventListener('pointerup', event => finishCameraDrag(event));
  document.addEventListener('pointercancel', event => finishCameraDrag(event, true));
  document.addEventListener('lostpointercapture', event => finishCameraDrag(event, true));
  globalThis.addEventListener('blur', () => finishCameraDrag(null, true));
  document.addEventListener('visibilitychange', () => { if (document.hidden) finishCameraDrag(null, true); });
}
function button(action, label, style = '', value = null) { return '<button class="' + style + '" data-action="' + action + '"' + (value !== null ? ' data-value="' + esc(value) + '"' : '') + '>' + label + '</button>'; }
function matchDialog() {
  if (dialog === 'help') return '<div class="dialog"><h2>Own the skies.</h2><p>Grow your kingdom, command an army, and outsmart your rival. Reach 80 crowns or destroy the enemy citadel to win.</p><div class="guide"><div class="step"><strong>1 · Build</strong>Cottages earn gold. Windmills feed knights. Mines power your abilities.</div><div class="step"><strong>2 · Command</strong>Capture the central Sky Crystal for crowns. Send knights to raid enemy buildings.</div><div class="step"><strong>3 · Defend</strong>Towers reduce incoming damage. Upgrade, repair, and shield your citadel.</div></div><p>Click the island to select a plot. Click and drag to orbit and tilt the camera. Use −/+ to zoom. Each match lasts six minutes.</p>' + button('close', 'Ready to play', 'primary') + '</div>';
  if (dialog === 'reset') return '<div class="dialog"><h2>A fresh battle?</h2><p>Both kingdoms will be rebuilt. Players, invitations, and spectator links stay in this match.</p><div class="actions">' + button('rematch', 'Start rematch', 'gold') + button('close', 'Keep playing') + '</div></div>';
  if (dialog !== 'match') return '';
  return '<div class="dialog"><h2>Your match, your audience.</h2><p>Create a private kingdom, invite a rival, and share a separate link with anyone who wants to watch live.</p><div class="actions">' + button('create', icon('plus') + ' Create match', 'primary') + button('joinClipboard', icon('link') + ' Join link') + '</div><div class="actions">' + (role !== 'spectator' ? button('copyInvite', icon('copy') + ' Copy invitation') : '') + button('copyWatch', icon('eye') + ' Copy spectator link') + '</div>' + (links.watch ? '<div class="link">' + esc(links.watch) + '</div>' : '') + '<div class="actions">' + button('openWatch', 'Watch in browser', 'quiet') + (seat === 0 ? button('confirmRematch', 'Rematch', 'quiet') : '') + button('close', 'Close', 'quiet') + '</div></div>';
}
function render() {
  if (!dirty || (drag && cachedHTML)) return cachedHTML;
  dirty = false;
  const now = Date.now() + serverOffset;
  const players = game ? game.players : [{ seat: 0, name: 'Your kingdom', gold: 280, food: 90, energy: 60, troops: 12, score: 0, joined: true, online: false }, { seat: 1, name: 'Open seat', gold: 280, food: 90, energy: 60, troops: 12, score: 0, joined: false, online: false }];
  const tiles = game ? game.tiles : preview;
  const playerHTML = players.map(player => {
    const nexus = tiles.find(t => t.owner === player.seat && t.kind === 'nexus');
    const health = nexus ? Math.round(nexus.hp / nexus.maxHp * 100) : 100;
    const count = tiles.filter(t => t.owner === player.seat && t.kind !== 'empty').length;
    return '<div class="player ' + (player.seat === 1 ? 'orange ' : '') + (seat === player.seat ? 'mine' : '') + '"><div class="playerhead"><span class="online ' + (player.online ? 'on' : '') + '"></span><span class="playername">' + esc(player.name || 'Waiting for rival') + '</span>' + (seat === player.seat ? '<span class="you">YOU</span>' : player.bot ? '<span class="you">BOT</span>' : '') + '<span class="crown">' + icon('crown', 12) + ' ' + player.score + '</span></div><div class="resources"><span class="goldcount">' + player.gold + '<span style="font-size:8px;font-weight:600"> G</span></span><span class="resource food">' + player.food + ' food</span><span class="resource energy">' + player.energy + ' energy</span></div><div class="health"><div class="healthfill" style="width:' + health + '%"></div></div><div class="playerfoot"><span>Citadel ' + health + '%</span><span>' + player.troops + ' knights · ' + count + ' buildings</span></div></div>';
  }).join('');
  const relicOwner = game && game.relic.owner >= 0 ? players[game.relic.owner].name : '';
  const left = game && game.startedAt ? Math.max(0, Math.ceil((game.duration - (now - game.startedAt)) / 1000)) : 360;
  const clock = game && game.phase === 'finished' ? 'FINAL' : String(Math.floor(left / 60)).padStart(2, '0') + ':' + String(left % 60).padStart(2, '0');
  const tile = tiles[selected], mine = tile && tile.owner === seat, occupied = tile && tile.kind !== 'empty';
  const info = occupied ? RULES_UI[tile.kind] : null;
  const title = selected === (game ? game.relic.tile : 90) ? 'Sky Crystal' : occupied ? info.name + ' · Lv ' + tile.level : tile && tile.terrain === 'water' ? 'Open sky' : 'Open building plot';
  const detail = selected === (game ? game.relic.tile : 90) ? 'Control this crystal to earn one crown every second.' : occupied ? (mine ? info.detail : 'Enemy building · ' + tile.hp + ' / ' + tile.maxHp + ' HP') : mine ? 'Choose a building below to grow your kingdom.' : 'Select your own grass plot to build, or an enemy building to attack.';
  const repair = mine && occupied && tile.hp < tile.maxHp;
  let controls = '';
  if (!game) {
    controls = '<div class="spectator">Connecting to your kingdom…</div>';
  } else if (game.phase === 'finished') {
    const winner = game.winner === -1 ? 'An even battle' : esc(players[game.winner].name) + ' owns the skies';
    controls = '<div class="victory">' + icon('crown', 32) + '<div class="big">' + winner + '</div><p>' + players[0].score + ' — ' + players[1].score + ' crowns · Every great rivalry deserves another round.</p>' + (seat === 0 ? button('confirmRematch', 'Play again', 'gold') : '<span>Waiting for the host to start a rematch.</span>') + '</div>';
  } else if (role === 'spectator') {
    controls = '<div class="spectator">' + icon('eye', 18) + ' You are watching live. Orbit the island and follow the battle.</div>';
  } else {
    controls = '<div class="selection"><div class="label"><h3>' + esc(title) + '</h3><p>' + esc(detail) + '</p></div><div class="small">' + (mine && occupied ? button('upgrade', 'Upgrade · ' + 55 * tile.level + ' G', tile.level >= 3 ? 'off' : '') : '') + (repair ? button('repair', 'Repair · 35 G') : '') + '</div></div><div class="tabbar">' + button('tab', 'Economy', tab === 'economy' ? 'active' : '', 'economy') + button('tab', 'Fortifications', tab === 'defense' ? 'active' : '', 'defense') + button('tab', 'Command army', tab === 'army' ? 'active' : '', 'army') + '</div>';
    if (tab === 'army') controls += '<div class="army">' + button('train', icon('flag') + ' Train 5<span class="sub">35 G · 25 food</span>') + button('claim', icon('diamond') + ' Capture<span class="sub">3 knights · Sky Crystal</span>', 'gold') + button('attack', icon('sword') + ' Attack<span class="sub">5 knights · 20 G</span>', 'danger') + button('meteor', icon('diamond') + ' Skystrike<span class="sub">80 energy · 65 damage</span>') + button('shield', icon('shield') + ' Shield<span class="sub">60 energy · 12 seconds</span>') + '</div>';
    else {
      const kinds = tab === 'economy' ? ['house', 'farm', 'quarry', 'barracks'] : ['tower', 'wall'];
      controls += '<div class="builds">' + kinds.map(kind => {
        const rule = RULES_UI[kind];
        return button('build', '<span class="symbol">' + icon(rule.icon, 19) + '</span><span class="label">' + rule.name + '</span><span class="cost">' + rule.cost + ' gold</span>', (!mine || occupied || !connected) ? 'off' : '', kind);
      }).join('') + '</div>';
    }
  }
  const waiting = game && game.phase === 'waiting' && role !== 'spectator' ? '<div class="waiting"><div class="message"><strong>Your rival’s seat is open.</strong>Invite someone or warm up against Clockwork.</div>' + button('copyInvite', 'Invite rival', 'gold') + (seat === 0 ? button('practice', 'Practice') : '') + '</div>' : '';
  const selectedText = '<strong>' + coord(selected) + '</strong> · ' + (selected === (game ? game.relic.tile : 90) ? 'Sky Crystal' : tile && tile.owner >= 0 ? esc(players[tile.owner].name || 'Rival') + '’s kingdom' : 'Neutral bridge');
  const log = game && game.events.length ? game.events[0] : null;
  cachedHTML = '<div class="game"><div class="top"><div class="brandmark">' + icon('crown', 23) + '</div><div class="brand"><div class="eyebrow">THE FLOATING KINGDOMS</div><div class="title">Voxel Clash</div></div><div class="top-actions">' + button('help', icon('help', 16), 'icon quiet') + button('menu', icon('menu', 16) + ' Match', 'icon') + '</div></div><div class="players">' + playerHTML + '</div><div class="objective">' + icon('diamond', 15) + '<div class="text">' + (game && game.phase === 'finished' ? '<strong>Match complete</strong> · The next chapter is yours.' : relicOwner ? '<strong>' + esc(relicOwner) + '</strong> controls the Sky Crystal · +1 crown/s' : '<strong>Capture the Sky Crystal.</strong> First to 80 crowns wins.') + '</div><div class="clock">' + (game && game.phase === 'waiting' ? 'LOBBY' : clock) + '</div></div><div class="stage" data-3d></div><div class="mapbar"><div class="plot">' + selectedText + '</div>' + button('rotate', '↶', 'icon', '-0.35') + button('rotate', '↷', 'icon', '0.35') + button('zoom', '−', 'icon', '-0.12') + button('zoom', '+', 'icon', '0.12') + button('night', night ? 'Dawn' : 'Dusk', 'quiet') + '</div>' + (toast ? '<div class="notice ' + (toastError ? 'error' : '') + '">' + esc(toast) + '</div>' : '') + waiting + controls + (role !== 'spectator' && (!game || game.phase !== 'finished') ? '<div class="mapbar">' + button('next', 'Next plot', 'quiet') + button('rival', 'Rival citadel', 'quiet') + button('crystal', 'Sky Crystal', 'quiet') + '<div class="plot muted" style="text-align:right;color:#7892a9;font-size:8px">Click to select · Drag to orbit</div></div>' : '') + matchDialog() + '<div class="log"><span style="color:#e8ce99">' + icon(log && log.kind === 'attack' ? 'sword' : 'flag', 12) + '</span><span class="event">' + esc(log ? log.text : 'Your kingdom is taking shape…') + '</span></div><div class="footer"><span class="live">' + (connected ? '● LIVE' : loading ? '○ CONNECTING' : '○ RECONNECTING') + '</span><span>' + (connected && latency ? latency + ' ms' : 'Shared world') + '</span><span class="spacer"></span>' + (role === 'spectator' ? '<span class="role">SPECTATOR</span>' : '') + '<span>' + (game ? game.spectators : 0) + ' watching</span><span>·</span><span>' + esc(game ? game.id.slice(0, 8).toUpperCase() : 'VOXEL CLASH') + '</span></div></div>';
  return cachedHTML;
}
function dynamicInstance(object, index, x, y, z, sx, sy, sz, rotation, color) {
  tempPosition.set(x, y, z); tempScale.set(sx, sy, sz); tempQuaternion.setFromEuler(new THREE.Euler(0, rotation, 0)); tempMatrix.compose(tempPosition, tempQuaternion, tempScale);
  object.setMatrixAt(index, tempMatrix); object.setColorAt(index, tempColor.setHex(color));
}
let lastRenderWidth = 0, lastRenderHeight = 0;
function tick(time) {
  const now = Date.now() + serverOffset, second = Math.floor(now / 1000);
  if (second !== clockSecond) { clockSecond = second; dirty = true; }
  if (toast && performance.now() > toastUntil) { toast = ''; dirty = true; }
  const size = renderer.getSize(new THREE.Vector2());
  if (BROWSER) {
    const stage = document.querySelector('[data-3d]');
    if (stage) {
      const width = stage.clientWidth || 560, height = stage.clientHeight || 350;
      if (lastRenderWidth !== width || lastRenderHeight !== height) { renderer.setSize(width, height, false); lastRenderWidth = width; lastRenderHeight = height; }
    }
  }
  camera.aspect = (BROWSER ? lastRenderWidth : size.x) / Math.max(1, BROWSER ? lastRenderHeight : size.y);
  const radius = Math.hypot(21, 15) / cameraZoom, horizontal = Math.cos(cameraElevation) * radius;
  camera.position.set(Math.sin(cameraAngle) * horizontal, Math.sin(cameraElevation) * radius, Math.cos(cameraAngle) * horizontal);
  camera.lookAt(0, 0.2, 0); camera.updateProjectionMatrix();
  const tile = (game ? game.tiles : preview)[selected], position = worldPosition(selected);
  selectionRing.visible = !!tile && tile.terrain !== 'water';
  selectionRing.position.set(position.x, (tile ? tile.height : 0.15) + 0.05, position.z);
  selectionRing.scale.setScalar(1 + Math.sin(time * 0.003) * 0.025);
  gem.rotation.y = time * 0.0008; gem.position.y = 0.49 + Math.sin(time * 0.0017) * 0.1;
  relicHalo.rotation.z = Math.sin(time * 0.0006) * 0.1;
  if (game) {
    const color = game.relic.owner < 0 ? 0x8bd4ee : PALETTE[game.relic.owner];
    gem.material.color.setHex(color); crystalLight.color.setHex(color);
    shieldMeshes.forEach((object, i) => { object.visible = game.players[i].shieldUntil > now; object.rotation.y = time * 0.0003; });
  }
  clouds.forEach((cloud, i) => { const a = i * 1.25 + time * 0.000015; cloud.position.set(Math.sin(a) * 15, 0.2 + (i % 2) * 1.7, Math.cos(a) * 14); });
  windmills.forEach((object, i) => { object.rotation.z = time * 0.00065 + i; });
  for (const batch of construction) {
    let animate = false;
    for (let i = 0; i < batch.entries.length; i++) {
      const entry = batch.entries[i];
      if (entry.tile && entry.tile.builtAt && now - entry.tile.builtAt < 1100) {
        const t = Math.max(0.04, Math.min(1, (now - entry.tile.builtAt) / 850));
        setInstance(batch.object, i, entry, 1 - Math.pow(1 - t, 3)); animate = true;
      }
    }
    if (animate) batch.object.instanceMatrix.needsUpdate = true;
  }
  let count = 0, debris = 0;
  if (game) {
    for (const wave of game.waves) {
      const from = worldPosition(wave.from), to = worldPosition(wave.to), t = Math.max(0, Math.min(1, (now - wave.start) / (wave.arrival - wave.start)));
      const angle = Math.atan2(to.x - from.x, to.z - from.z);
      const units = wave.type === 'meteor' ? 1 : wave.units;
      for (let i = 0; i < units && count < 256; i++) {
        const spread = (i % 3 - 1) * 0.2, trail = Math.floor(i / 3) * 0.26;
        const x = from.x + (to.x - from.x) * t + Math.cos(angle) * spread - Math.sin(angle) * trail;
        const z = from.z + (to.z - from.z) * t - Math.sin(angle) * spread - Math.cos(angle) * trail;
        const meteor = wave.type === 'meteor', y = meteor ? 0.6 + Math.sin(t * Math.PI) * 5 : 0.38 + Math.abs(Math.sin(time * 0.009 + i)) * 0.09;
        dynamicInstance(armyBodies, count, x, y, z, meteor ? 0.34 : 0.16, meteor ? 0.34 : 0.23, meteor ? 0.34 : 0.13, angle, meteor ? 0x97d9ff : PALETTE[wave.seat]);
        dynamicInstance(armyHeads, count, x, y + (meteor ? 0 : 0.19), z, meteor ? 0.55 : 0.17, meteor ? 0.55 : 0.19, meteor ? 0.55 : 0.17, angle, meteor ? 0xffdd9c : 0xe9e3c8);
        count++;
      }
    }
    for (const effect of game.effects) {
      const p = worldPosition(effect.tile), t = Math.max(0, Math.min(1, (now - effect.start) / 1500));
      for (let i = 0; i < 12 && debris < 256; i++) {
        const a = i * 2.399;
        dynamicInstance(effects, debris++, p.x + Math.sin(a) * t * 1.1, 0.3 + Math.sin(t * Math.PI) * (0.5 + i % 3 * 0.3), p.z + Math.cos(a) * t * 1.1, 0.13 * (1 - t), 0.13 * (1 - t), 0.13 * (1 - t), a + t * 4, i % 2 ? 0xecc78c : 0xb7d6d4);
      }
    }
  }
  for (const object of [armyBodies, armyHeads]) { object.count = count; if (count) { object.instanceMatrix.needsUpdate = true; object.instanceColor.needsUpdate = true; } }
  effects.count = debris; if (debris) { effects.instanceMatrix.needsUpdate = true; effects.instanceColor.needsUpdate = true; }
  renderer.render(scene, camera);
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
