import { Router } from 'express';
import { readdir, stat, readFile } from 'node:fs/promises';
import { join, resolve, extname } from 'node:path';

export function fileRoutes(rootDir) {
  const absRoot = resolve(rootDir);
  const router = Router();

  router.get('*', async (req, res) => {
    const requestedPath = decodeURIComponent(req.path || '/');
    const fullPath = resolve(join(absRoot, requestedPath));

    // Prevent path traversal
    if (!fullPath.startsWith(absRoot)) {
      return res.status(403).send('Forbidden');
    }

    try {
      const stats = await stat(fullPath);

      if (stats.isDirectory()) {
        const entries = await readdir(fullPath, { withFileTypes: true });
        const items = entries.map(e => ({
          name: e.name,
          isDir: e.isDirectory(),
          href: `/files${join(requestedPath, e.name)}`,
        })).sort((a, b) => {
          if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
          return a.name.localeCompare(b.name);
        });

        const parent = requestedPath !== '/'
          ? `/files${resolve(requestedPath, '..')}`
          : null;

        return res.send(renderDir(requestedPath, items, parent));
      }

      // File: download or inline view
      if (req.query.download !== undefined) {
        return res.download(fullPath);
      }

      const content = await readFile(fullPath, 'utf-8');
      const ext = extname(fullPath).slice(1);
      res.send(renderFile(requestedPath, content, ext));
    } catch (err) {
      if (err.code === 'ENOENT') return res.status(404).send('Not found');
      res.status(500).send(err.message);
    }
  });

  return router;
}

function renderDir(path, items, parentHref) {
  const rows = items.map(i =>
    `<tr><td>${i.isDir ? '[dir]' : ''}</td><td><a href="${i.href}">${i.name}${i.isDir ? '/' : ''}</a></td></tr>`
  ).join('\n');

  const back = parentHref ? `<a href="${parentHref}">..</a><br>` : '';

  return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${path}</title>
<style>body{font-family:monospace;max-width:900px;margin:2em auto;padding:0 1em}
a{color:#0366d6;text-decoration:none}a:hover{text-decoration:underline}
table{border-collapse:collapse;width:100%}td{padding:4px 8px}
tr:hover{background:#f6f8fa}</style></head>
<body><h2>${path}</h2>${back}<table>${rows}</table></body></html>`;
}

function renderFile(path, content, ext) {
  const esc = content.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const parentHref = `/files${resolve(path, '..')}`;
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${path}</title>
<style>body{font-family:monospace;max-width:1000px;margin:2em auto;padding:0 1em}
pre{background:#f6f8fa;padding:1em;overflow-x:auto;border-radius:6px;line-height:1.5}
a{color:#0366d6;text-decoration:none}</style></head>
<body><a href="${parentHref}">..</a> | <a href="/files${path}?download">Download</a>
<h2>${path}</h2><pre><code class="language-${ext}">${esc}</code></pre></body></html>`;
}
