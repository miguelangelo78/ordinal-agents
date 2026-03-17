import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const SESSION_TTL = 90 * 24 * 60 * 60 * 1000; // 90 days
const CLEANUP_INTERVAL = 5 * 60 * 1000;

export default class SessionStore {
  constructor(persistPath) {
    this.sessions = new Map();
    this.persistPath = persistPath;
    this._load();
    this.timer = setInterval(() => this.cleanup(), CLEANUP_INTERVAL);
  }

  _load() {
    try {
      const data = JSON.parse(readFileSync(this.persistPath, 'utf8'));
      for (const [key, entry] of Object.entries(data)) {
        this.sessions.set(key, entry);
      }
      console.log(`Loaded ${this.sessions.size} sessions from disk`);
    } catch {
      // File doesn't exist yet
    }
  }

  _save() {
    try {
      writeFileSync(this.persistPath, JSON.stringify(Object.fromEntries(this.sessions), null, 2));
    } catch (err) {
      console.error('Failed to persist sessions:', err.message);
    }
  }

  conversationKey(messages, model) {
    const firstUserMsg = messages.find(m => m.role === 'user');
    if (!firstUserMsg) return null;
    const content = typeof firstUserMsg.content === 'string'
      ? firstUserMsg.content
      : JSON.stringify(firstUserMsg.content);
    const hash = createHash('sha256').update(content).digest('hex').slice(0, 16);
    return `${model}:${hash}`;
  }

  get(key) {
    const entry = this.sessions.get(key);
    if (!entry) return null;
    entry.lastAccess = Date.now();
    return entry.sessionId;
  }

  set(key, sessionId) {
    this.sessions.set(key, { sessionId, lastAccess: Date.now() });
    this._save();
  }

  delete(key) {
    this.sessions.delete(key);
    this._save();
  }

  cleanup() {
    const now = Date.now();
    let changed = false;
    for (const [key, entry] of this.sessions) {
      if (now - entry.lastAccess > SESSION_TTL) {
        this.sessions.delete(key);
        changed = true;
      }
    }
    if (changed) this._save();
  }

  close() {
    clearInterval(this.timer);
    this._save();
  }
}
