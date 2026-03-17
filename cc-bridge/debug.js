import { query } from '@anthropic-ai/claude-agent-sdk';

console.log('HOME:', process.env.HOME);
console.log('USER:', process.env.USER);
console.log('CWD:', process.cwd());
console.log('Starting SDK query...');

try {
  const q = query({
    prompt: 'say hello in 3 words',
    options: {
      cwd: '/home/claude/workspace',
      permissionMode: 'bypassPermissions',
      allowDangerouslySkipPermissions: true,
      settingSources: ['project'],
      stderr: (data) => console.error('[SDK STDERR]', data),
    }
  });

  for await (const message of q) {
    console.log('MSG:', JSON.stringify(message).slice(0, 300));
  }
  console.log('Done.');
} catch (err) {
  console.error('ERROR:', err.message);
  console.error('STACK:', err.stack);
}
