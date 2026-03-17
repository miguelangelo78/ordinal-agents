import { execFileSync } from 'node:child_process';
import http from 'node:http';

const BASE_PORT = parseInt(process.env.AGENT_BASE_PORT || '3000');

/**
 * Discover running subagent containers via Docker CLI.
 * Returns array of { name, id, port }.
 */
export async function discoverSubagents() {
  try {
    const output = execFileSync(
      'docker', ['ps', '--filter', 'name=subagent-', '--format', '{{.Names}}'],
      { encoding: 'utf-8', timeout: 5000 }
    ).trim();

    if (!output) return [];

    return output.split('\n').map(name => {
      const id = parseInt(name.replace('subagent-', ''));
      return { name, id, port: BASE_PORT + id };
    }).sort((a, b) => a.id - b.id);
  } catch {
    return [];
  }
}

/**
 * Proxy an HTTP request to a subagent's bridge.
 * Subagents use --network host inside DinD, so localhost:{BASE_PORT+N} works.
 */
export function proxyToSubagent(req, res, model) {
  const id = parseInt(model.replace('subagent-', ''));
  if (isNaN(id) || id < 1 || id > 20) {
    return res.status(400).json({
      error: { message: `Invalid subagent model: ${model}`, type: 'invalid_request_error' }
    });
  }

  const port = BASE_PORT + id;

  const proxyReq = http.request({
    hostname: 'localhost',
    port,
    path: req.originalUrl,
    method: req.method,
    headers: {
      'content-type': 'application/json',
      'accept': req.headers.accept || '*/*',
    },
  }, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res);
  });

  proxyReq.on('error', () => {
    if (!res.headersSent) {
      res.status(502).json({
        error: { message: `${model} is not running`, type: 'proxy_error' }
      });
    }
  });

  proxyReq.write(JSON.stringify(req.body));
  proxyReq.end();
}
