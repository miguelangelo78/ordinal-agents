import express from 'express';
import { join } from 'node:path';
import SessionStore from './sessions.js';
import { streamCompletion, sendError } from './stream.js';
import { discoverSubagents, proxyToSubagent } from './subagents.js';
import { fileRoutes } from './files.js';

const app = express();
app.use(express.json({ limit: '50mb' }));

const PORT = parseInt(process.env.BRIDGE_PORT || '4000');
const CWD = process.env.BRIDGE_CWD || '/home/claude/workspace';
const MODEL_NAME = process.env.BRIDGE_MODEL || 'main-agent';
const IS_MAIN = process.env.BRIDGE_ROLE === 'main';

const sessions = new SessionStore(join(CWD, '.cc-bridge-sessions.json'));

app.get('/health', (req, res) => res.json({ status: 'ok', model: MODEL_NAME }));

app.get('/v1/models', async (req, res) => {
  const models = [{ id: MODEL_NAME, object: 'model', owned_by: 'ordinal-agents' }];
  if (IS_MAIN) {
    const subagents = await discoverSubagents();
    for (const sa of subagents) {
      models.push({ id: sa.name, object: 'model', owned_by: 'ordinal-agents' });
    }
  }
  res.json({ object: 'list', data: models });
});

app.post('/v1/chat/completions', async (req, res) => {
  const { model, messages, stream = true } = req.body;
  if (!messages || !messages.length) {
    return sendError(res, 400, 'messages is required');
  }
  if (IS_MAIN && model && model.startsWith('subagent-')) {
    return proxyToSubagent(req, res, model);
  }
  await streamCompletion(req, res, messages, model || MODEL_NAME, sessions, CWD);
});

app.use('/files', fileRoutes(CWD));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`cc-bridge listening on port ${PORT} (model: ${MODEL_NAME}, main: ${IS_MAIN})`);
});
