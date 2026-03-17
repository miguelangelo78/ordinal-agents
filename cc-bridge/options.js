// options.js — Parse SDK options from system prompt directives and /slash commands
//
// System prompt directives (parsed from the system message):
//   effort: low|medium|high|max
//   model: claude-sonnet-4-6
//   thinking: on|off|adaptive
//   maxTurns: 5
//   budget: 1.50
//   ---
//   Rest of system prompt passed to SDK as systemPrompt
//
// Slash commands (parsed from user messages):
//   /effort low|medium|high|max
//   /model claude-sonnet-4-6
//   /thinking on|off|adaptive
//   /maxturns 5
//   /budget 1.50
//   /settings — show current settings

const VALID_EFFORTS = new Set(['low', 'medium', 'high', 'max']);
const VALID_THINKING = new Set(['on', 'off', 'adaptive']);

const MEMORY_PROMPT = `You have a persistent memory file at /home/claude/workspace/.agent-memory.md.
ALWAYS read it at the start of every conversation before responding.
When users teach you preferences, rules, facts, or important context, append them to this file immediately so you remember across all conversations and restarts.
If the file doesn't exist yet, create it.

## PLANNING AND THINKING DISCIPLINE

You are a senior engineer. You do NOT rush into implementation. You think deeply first.

For EVERY non-trivial request, follow this exact sequence:

### Phase 1: Understand (MANDATORY)
- Read your memory file
- Read all relevant files and code before forming any opinion
- Identify ambiguities, edge cases, and unknowns
- Ask clarifying questions if ANYTHING is unclear — do NOT assume
- If you have zero questions, explain WHY you have zero questions

### Phase 2: Plan (MANDATORY before any code changes)
- Present a detailed plan: what you'll change, why, and what the risks are
- List the files you'll touch and what changes each gets
- Identify potential side effects or breaking changes
- Explicitly ask: "Does this plan look good, or would you like changes?"
- STOP HERE. Wait for user approval before proceeding.

### Phase 3: Implement (ONLY after explicit user approval)
- Only begin coding after the user says "go ahead", "yes", "do it", "looks good", or similar
- Implement incrementally — show progress, don't go silent for 50 tool calls
- Test your changes where possible
- Summarize what you did when finished

CRITICAL: If the user's message is a simple question, greeting, or small task (e.g. "what port is X on?", "read this file"), respond directly — this workflow is for tasks that involve code changes or architectural decisions.

NEVER skip Phase 1 and 2 for non-trivial work. The user WILL notice and WILL be unhappy.`;

// Per-conversation settings store (keyed by conversation key)
const conversationSettings = new Map();

export function getSettings(conversationKey) {
  return conversationSettings.get(conversationKey) || {};
}

function setSettings(conversationKey, settings) {
  conversationSettings.set(conversationKey, settings);
}

/**
 * Parse system message for directives. Returns { sdkOptions, systemPrompt }.
 * Directives are key: value lines before a --- separator (or the entire message if no separator).
 */
export function parseSystemDirectives(systemMsg) {
  if (!systemMsg) return { sdkOptions: {}, systemPrompt: null };

  const content = typeof systemMsg.content === 'string'
    ? systemMsg.content
    : (systemMsg.content || []).filter(b => b.type === 'text').map(b => b.text).join('\n');

  if (!content.trim()) return { sdkOptions: {}, systemPrompt: null };

  const separatorIdx = content.indexOf('\n---');
  let directiveBlock, promptBlock;

  if (separatorIdx !== -1) {
    directiveBlock = content.slice(0, separatorIdx);
    promptBlock = content.slice(separatorIdx + 4).trim();
  } else {
    // Try to parse the whole thing as directives; if none found, treat as system prompt
    directiveBlock = content;
    promptBlock = null;
  }

  const sdkOptions = {};
  let foundDirective = false;
  const nonDirectiveLines = [];

  for (const line of directiveBlock.split('\n')) {
    const match = line.match(/^(\w+)\s*:\s*(.+)$/);
    if (match) {
      const [, key, value] = match;
      const applied = applyDirective(sdkOptions, key.toLowerCase(), value.trim());
      if (applied) {
        foundDirective = true;
      } else {
        nonDirectiveLines.push(line);
      }
    } else {
      nonDirectiveLines.push(line);
    }
  }

  // If no separator and no directives found, the whole thing is system prompt
  let systemPrompt;
  if (separatorIdx !== -1) {
    systemPrompt = promptBlock || null;
  } else if (foundDirective) {
    const remaining = nonDirectiveLines.join('\n').trim();
    systemPrompt = remaining || null;
  } else {
    systemPrompt = content.trim() || null;
  }

  return { sdkOptions, systemPrompt };
}

/**
 * Check if a user message is a slash command. Returns { isCommand, response, settingsUpdate }
 */
export function parseSlashCommand(text, conversationKey) {
  const trimmed = text.trim();
  if (!trimmed.startsWith('/')) return { isCommand: false };

  const parts = trimmed.split(/\s+/);
  const cmd = parts[0].toLowerCase();
  const arg = parts.slice(1).join(' ');
  const current = getSettings(conversationKey);

  switch (cmd) {
    case '/effort': {
      if (!arg || !VALID_EFFORTS.has(arg.toLowerCase())) {
        return { isCommand: true, response: `Usage: /effort ${[...VALID_EFFORTS].join('|')}\nCurrent: ${current.effort || 'high (default)'}` };
      }
      const effort = arg.toLowerCase();
      setSettings(conversationKey, { ...current, effort });
      return { isCommand: true, response: `Effort set to **${effort}**` };
    }

    case '/model': {
      if (!arg) {
        return { isCommand: true, response: `Usage: /model <model-name>\nCurrent: ${current.model || '(default)'}` };
      }
      setSettings(conversationKey, { ...current, model: arg });
      return { isCommand: true, response: `Model set to **${arg}**` };
    }

    case '/thinking': {
      if (!arg || !VALID_THINKING.has(arg.toLowerCase())) {
        return { isCommand: true, response: `Usage: /thinking ${[...VALID_THINKING].join('|')}\nCurrent: ${current.thinking || 'on (default)'}` };
      }
      const thinking = arg.toLowerCase();
      setSettings(conversationKey, { ...current, thinking });
      return { isCommand: true, response: `Thinking set to **${thinking}**` };
    }

    case '/maxturns': {
      const n = parseInt(arg);
      if (!arg || isNaN(n) || n < 1) {
        return { isCommand: true, response: `Usage: /maxturns <number>\nCurrent: ${current.maxTurns || 'unlimited (default)'}` };
      }
      setSettings(conversationKey, { ...current, maxTurns: n });
      return { isCommand: true, response: `Max turns set to **${n}**` };
    }

    case '/budget': {
      const b = parseFloat(arg);
      if (!arg || isNaN(b) || b <= 0) {
        return { isCommand: true, response: `Usage: /budget <amount_usd>\nCurrent: ${current.maxBudgetUsd ? '$' + current.maxBudgetUsd : 'unlimited (default)'}` };
      }
      setSettings(conversationKey, { ...current, maxBudgetUsd: b });
      return { isCommand: true, response: `Budget set to **$${b.toFixed(2)}**` };
    }

    case '/settings': {
      const lines = [
        '**Current settings:**',
        `- effort: ${current.effort || 'high (default)'}`,
        `- model: ${current.model || '(default)'}`,
        `- thinking: ${current.thinking || 'on (default)'}`,
        `- maxTurns: ${current.maxTurns || 'unlimited (default)'}`,
        `- budget: ${current.maxBudgetUsd ? '$' + current.maxBudgetUsd : 'unlimited (default)'}`,
      ];
      return { isCommand: true, response: lines.join('\n') };
    }

    case '/reset': {
      conversationSettings.delete(conversationKey);
      return { isCommand: true, response: 'Settings reset to defaults.' };
    }

    default:
      return { isCommand: false };
  }
}

/**
 * Build SDK options by merging: base defaults + system directives + conversation settings
 */
export function buildSdkOptions(cwd, sessionId, systemDirectives, conversationKey) {
  const stored = getSettings(conversationKey);

  const options = {
    cwd,
    permissionMode: 'acceptEdits',
    allowedTools: ['Bash', 'Read', 'Write', 'Edit', 'Glob', 'Grep', 'WebFetch', 'WebSearch', 'NotebookEdit', 'Agent', 'Task', 'TaskOutput'],
    settingSources: ['project'],
    pathToClaudeCodeExecutable: '/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js',
    stderr: (data) => console.error('[claude-sdk]', data.trim()),
  };

  // Defaults: think hard
  options.effort = 'high';
  options.thinking = { type: 'enabled', budgetTokens: 50000 };

  // Apply system prompt directives first, then stored slash command settings (slash commands win)
  const merged = { ...systemDirectives, ...stored };

  if (merged.effort) options.effort = merged.effort;
  if (merged.model) options.model = merged.model;
  if (merged.maxTurns) options.maxTurns = merged.maxTurns;
  if (merged.maxBudgetUsd) options.maxBudgetUsd = merged.maxBudgetUsd;

  if (merged.thinking) {
    switch (merged.thinking) {
      case 'off':
        options.thinking = { type: 'disabled' };
        break;
      case 'on':
        options.thinking = { type: 'enabled', budgetTokens: 50000 };
        break;
      case 'adaptive':
        options.thinking = { type: 'adaptive' };
        break;
    }
  }

  if (sessionId) options.resume = sessionId;

  // Always inject memory prompt (prepend to any user-provided system prompt)
  options.systemPrompt = MEMORY_PROMPT;

  return options;
}

function applyDirective(target, key, value) {
  switch (key) {
    case 'effort':
      if (VALID_EFFORTS.has(value.toLowerCase())) {
        target.effort = value.toLowerCase();
        return true;
      }
      return false;
    case 'model':
      target.model = value;
      return true;
    case 'thinking':
      if (VALID_THINKING.has(value.toLowerCase())) {
        target.thinking = value.toLowerCase();
        return true;
      }
      return false;
    case 'maxturns':
      const n = parseInt(value);
      if (!isNaN(n) && n > 0) { target.maxTurns = n; return true; }
      return false;
    case 'budget':
      const b = parseFloat(value);
      if (!isNaN(b) && b > 0) { target.maxBudgetUsd = b; return true; }
      return false;
    default:
      return false;
  }
}
