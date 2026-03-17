import { query } from "@anthropic-ai/claude-agent-sdk";
try {
  const q = query({ prompt: "say hello in 3 words", options: { cwd: "/home/claude/workspace", permissionMode: "acceptEdits", allowedTools: ["Bash","Read","Write","Edit","Glob","Grep"], pathToClaudeCodeExecutable: "/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js", stderr: (d) => console.error("STDERR:", d) } });
  for await (const m of q) { console.log(JSON.stringify(m).slice(0, 300)); }
} catch (e) { console.error("ERR:", e.message); }
