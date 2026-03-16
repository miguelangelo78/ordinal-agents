#!/usr/bin/env node
/**
 * Bridge: agent-0 can POST { "agent": 1, "message": "..." } to /message.
 * Loads <repo>/<agent>/CLAUDE.md, calls Anthropic API, returns { "response": "..." }.
 */

import http from "http";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = Number(process.env.BRIDGE_PORT) || 32360;
const REPO_PATH = process.env.REPO_PATH || path.join(__dirname, "..");
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;

function loadAgentSystemPrompt(agentId) {
  const p = path.join(REPO_PATH, String(agentId), "CLAUDE.md");
  if (!fs.existsSync(p)) throw new Error(`No CLAUDE.md for agent ${agentId} at ${p}`);
  return fs.readFileSync(p, "utf-8");
}

async function callAnthropic(systemPrompt, userMessage) {
  if (!ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY not set");
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-20250514",
      max_tokens: 2048,
      system: systemPrompt,
      messages: [{ role: "user", content: userMessage }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic API ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data.content?.find((c) => c.type === "text")?.text ?? "";
}

const server = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  if (req.method === "GET" && (req.url === "/" || req.url === "/health")) {
    res.writeHead(200);
    res.end(JSON.stringify({ ok: true, service: "ordinal-agents-bridge" }));
    return;
  }
  if (req.method !== "POST" || req.url !== "/message") {
    res.writeHead(404);
    res.end(JSON.stringify({ error: "Use POST /message" }));
    return;
  }
  let body = "";
  for await (const chunk of req) body += chunk;
  let payload;
  try {
    payload = JSON.parse(body);
  } catch {
    res.writeHead(400);
    res.end(JSON.stringify({ error: "Invalid JSON" }));
    return;
  }
  const agent = payload.agent;
  const message = payload.message;
  if (agent == null || typeof message !== "string") {
    res.writeHead(400);
    res.end(JSON.stringify({ error: "Body must have agent (number) and message (string)" }));
    return;
  }
  const agentId = Number(agent);
  if (!Number.isInteger(agentId) || agentId < 1) {
    res.writeHead(400);
    res.end(JSON.stringify({ error: "agent must be a positive integer (1, 2, ...)" }));
    return;
  }
  try {
    const systemPrompt = loadAgentSystemPrompt(agentId);
    const response = await callAnthropic(systemPrompt, message);
    res.writeHead(200);
    res.end(JSON.stringify({ response }));
  } catch (err) {
    res.writeHead(500);
    res.end(JSON.stringify({ error: err.message }));
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Bridge listening on ${PORT} (REPO_PATH=${REPO_PATH})`);
});
