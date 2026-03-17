import { createHash } from 'node:crypto';

const SESSION_TTL = 30 * 60 * 1000;
const CLEANUP_INTERVAL = 5 * 60 * 1000;

export default class SessionStore {
  constructor() {
    this.sessions = new Map();
    this.timer = setInterval(() => this.cleanup(), CLEANUP_INTERVAL);
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
  }

  delete(key) {
    this.sessions.delete(key);
  }

  cleanup() {
    const now = Date.now();
    for (const [key, entry] of this.sessions) {
      if (now - entry.lastAccess > SESSION_TTL) {
        this.sessions.delete(key);
      }
    }
  }

  close() {
    clearInterval(this.timer);
  }
}
