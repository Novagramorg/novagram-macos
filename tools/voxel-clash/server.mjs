import { createServer } from './api.mjs';

const app = createServer();
app.server.listen(Number(process.env.PORT || 3000), '0.0.0.0', () => console.log('Voxel Clash v2 is ready: private matches, spectators and WebSockets'));
let stopping = false;
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, async () => {
  if (stopping) return;
  stopping = true;
  await app.close();
  process.exit(0);
});
