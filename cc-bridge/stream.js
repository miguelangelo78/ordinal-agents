import { query } from '@anthropic-ai/claude-agent-sdk';
import { parseSystemDirectives, parseSlashCommand, buildSdkOptions } from './options.js';

export async function streamCompletion(req, res, messages, model, sessionStore, cwd) {
  const conversationKey = sessionStore.conversationKey(messages, model);
  const existingSessionId = conversationKey ? sessionStore.get(conversationKey) : null;

  // Parse system message for directives
  const systemMsg = messages.find(m => m.role === 'system');
  const { sdkOptions: systemDirectives, systemPrompt } = parseSystemDirectives(systemMsg);

  const lastUserMsg = [...messages].reverse().find(m => m.role === 'user');
  if (!lastUserMsg) {
    return sendError(res, 400, 'No user message found');
  }

  const promptText = extractPrompt(lastUserMsg);

  // Check for slash commands
  if (conversationKey) {
    const { isCommand, response } = parseSlashCommand(promptText, conversationKey);
    if (isCommand) {
      return sendCommandResponse(res, model, response);
    }
  }

  const chatId = `chatcmpl-${Date.now().toString(36)}`;
  const created = Math.floor(Date.now() / 1000);
  const sdkOpts = buildSdkOptions(cwd, existingSessionId, systemDirectives, conversationKey);
  if (systemPrompt) sdkOpts.systemPrompt += '\n\n' + systemPrompt;

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');

  writeSSE(res, makeChunk(chatId, created, model, '', 'assistant'));

  const success = await runQuery(res, promptText, sdkOpts, conversationKey, sessionStore, chatId, created, model);

  if (!success && existingSessionId && conversationKey) {
    console.log('Resume failed, retrying with fresh session');
    sessionStore.delete(conversationKey);
    writeSSE(res, makeChunk(chatId, created, model, '\n> Session expired, starting fresh...\n'));
    const fullPrompt = messages
      .filter(m => m.role === 'user')
      .map(m => extractPrompt(m))
      .join('\n\n');
    delete sdkOpts.resume;
    await runQuery(res, fullPrompt, sdkOpts, conversationKey, sessionStore, chatId, created, model);
  }

  if (!res.destroyed) {
    writeSSE(res, {
      id: chatId, object: 'chat.completion.chunk', created, model,
      choices: [{ index: 0, delta: {}, finish_reason: 'stop' }]
    });
    res.write('data: [DONE]\n\n');
    res.end();
  }
}

function sendCommandResponse(res, model, text) {
  const chatId = `chatcmpl-${Date.now().toString(36)}`;
  const created = Math.floor(Date.now() / 1000);

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');

  writeSSE(res, makeChunk(chatId, created, model, '', 'assistant'));
  writeSSE(res, makeChunk(chatId, created, model, text));
  writeSSE(res, {
    id: chatId, object: 'chat.completion.chunk', created, model,
    choices: [{ index: 0, delta: {}, finish_reason: 'stop' }]
  });
  res.write('data: [DONE]\n\n');
  res.end();
}

async function runQuery(res, prompt, options, conversationKey, sessionStore, chatId, created, model) {
  let lastToolName = null;

  try {
    const stream = query({ prompt, options });

    for await (const message of stream) {
      if (res.destroyed) break;

      if (message.type === 'system' && message.subtype === 'init' && conversationKey) {
        sessionStore.set(conversationKey, message.session_id);
        continue;
      }

      if (message.type === 'assistant') {
        for (const block of (message.message?.content || [])) {
          if (block.type === 'text' && block.text) {
            writeSSE(res, makeChunk(chatId, created, model, block.text));
          } else if (block.type === 'tool_use') {
            lastToolName = block.name;
            const formatted = formatToolUse(block);
            if (formatted) {
              writeSSE(res, makeChunk(chatId, created, model, formatted));
            }
          }
        }
      }

      // Tool result messages
      if (message.type === 'tool_result' || message.type === 'user') {
        for (const block of (message.message?.content || [])) {
          if (block.type === 'tool_result') {
            const formatted = formatToolResult(block, lastToolName);
            if (formatted) {
              writeSSE(res, makeChunk(chatId, created, model, formatted));
            }
          }
        }
      }

      if (message.type === 'result') {
        if (message.subtype?.startsWith('error')) {
          const errorText = `\n\n**Error:** ${message.error || message.subtype}\n`;
          writeSSE(res, makeChunk(chatId, created, model, errorText));
        }
      }
    }
    return true;
  } catch (err) {
    console.error('SDK error:', err.message);
    if (!res.destroyed && !options.resume) {
      const errorText = `\n\n**Bridge Error:** ${err.message}\n`;
      writeSSE(res, makeChunk(chatId, created, model, errorText));
    }
    return false;
  }
}

function extractPrompt(userMsg) {
  if (typeof userMsg.content === 'string') {
    return userMsg.content;
  }
  const parts = [];
  for (const block of userMsg.content) {
    if (block.type === 'text') {
      parts.push(block.text);
    } else if (block.type === 'image_url' && block.image_url?.url) {
      parts.push('[Attached image]');
    }
  }
  return parts.join('\n');
}

function writeSSE(res, data) {
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function makeChunk(id, created, model, content, role) {
  const delta = role ? { role, content } : { content };
  return {
    id, object: 'chat.completion.chunk', created, model,
    choices: [{ index: 0, delta, finish_reason: null }]
  };
}

function formatToolUse(block) {
  const { name, input } = block;
  switch (name) {
    case 'Read':
      return `\n> Reading \`${input.file_path}\`...\n`;
    case 'Edit': {
      let msg = `\n> Editing \`${input.file_path}\`\n`;
      if (input.old_string != null && input.new_string != null) {
        msg += formatDiff(input.file_path, input.old_string, input.new_string);
      }
      return msg;
    }
    case 'Write':
      return `\n> Creating \`${input.file_path}\`\n`;
    case 'Bash':
      return `\n> Running: \`${input.command}\`\n`;
    case 'Glob':
      return `\n> Searching for \`${input.pattern}\`...\n`;
    case 'Grep':
      return `\n> Searching for "${input.pattern}"...\n`;
    case 'WebSearch':
      return `\n> Searching web: "${input.query}"...\n`;
    case 'WebFetch':
      return `\n> Fetching ${input.url}...\n`;
    default:
      return `\n> Using ${name}...\n`;
  }
}

function formatToolResult(block, lastToolName) {
  const content = typeof block.content === 'string' ? block.content : '';
  if (!content) return null;
  if (lastToolName === 'Bash' && content.trim()) {
    return `\n\`\`\`\n${content}\n\`\`\`\n`;
  }
  if (block.is_error) {
    return `\n> Error: ${content}\n`;
  }
  return null;
}

function formatDiff(filePath, oldStr, newStr) {
  const oldLines = oldStr.split('\n');
  const newLines = newStr.split('\n');
  let diff = '\n```diff\n';
  diff += `--- a/${filePath}\n+++ b/${filePath}\n`;
  diff += `@@ -1,${oldLines.length} +1,${newLines.length} @@\n`;
  for (const line of oldLines) diff += `-${line}\n`;
  for (const line of newLines) diff += `+${line}\n`;
  diff += '```\n';
  return diff;
}

export function sendError(res, status, message) {
  const type = status === 401 ? 'authentication_error'
    : status === 429 ? 'rate_limit_error'
    : status === 502 ? 'proxy_error'
    : 'invalid_request_error';
  res.status(status).json({ error: { message, type } });
}
