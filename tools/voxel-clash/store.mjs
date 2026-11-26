import fs from 'node:fs';
import path from 'node:path';
import { makeGame, addHost } from './engine.mjs';

export class GameStore {
  constructor(directory) {
    fs.mkdirSync(directory, { recursive: true });
    this.file = path.join(directory, 'matches-v2.json');
    this.games = new Map();
    if (fs.existsSync(this.file)) {
      const saved = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      if (saved.version !== 2 || !Array.isArray(saved.games)) throw new Error('Unsupported match store format');
      for (const game of saved.games) this.games.set(game.id, game);
    }
  }
  save() {
    const data = JSON.stringify({ version: 2, games: [...this.games.values()] });
    fs.writeFileSync(this.file + '.tmp', data, { mode: 0o600 });
    fs.renameSync(this.file + '.tmp', this.file);
  }
  create(name, clientId, title) {
    if (this.games.size >= 120) {
      const expired = [...this.games.values()].filter(g => g.phase === 'finished' && Date.now() - g.createdAt > 86400000);
      for (const game of expired) this.games.delete(game.id);
      if (this.games.size >= 120) throw new Error('The demo server is full. Please reuse an existing match.');
    }
    const game = makeGame({ host: name, name: title || `${name}’s sky kingdom` });
    const identity = addHost(game, clientId);
    this.games.set(game.id, game);
    this.save();
    return { game, ...identity };
  }
}
