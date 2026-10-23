// Ordered primary calls. Auxiliary generations have their own deterministic lane.
const text = (...deltas) => ({ deltas: deltas.map(text => ({ text })) });
const tool = (name, args) => ({ tools: [{ name, arguments: args }] });
const read = () => tool('read', { path: 'sample.txt' });
const edit = () => tool('edit', { path: 'sample.txt', oldString: 'original', newString: 'edited' });
export const scenarios = {
  'plain-text': { calls: [text('Hello', ', fixture world!')] },
  'reasoning-text': { calls: [{ deltas: [{ reasoning: 'Let me think.' }, { text: 'The answer is 42.' }] }] },
  'read-glob-grep': { calls: [read(), tool('glob', { pattern: '*.txt' }), tool('grep', { pattern: 'original', path: '.' }), text('Read, glob and grep completed.')] },
  'permission-allow': { calls: [read(), edit(), text('The edit was approved.')] },
  'permission-reject': { calls: [read(), edit(), text('I will leave the file unchanged.')] },
  'shell-output': { calls: [tool('shell', { command: "printf 'fixture-shell-output\\n'" }), text('Shell completed.')] },
  'question-form': { calls: [tool('question', { questions: [{ header: 'Color', question: 'Which color?', options: [{ label: 'Blue', description: 'Use blue' }, { label: 'Green', description: 'Use green' }] }] }), text('Blue selected.')] },
  'subagent': { calls: [tool('subagent', { agent: 'general', prompt: 'Report fixture child result.', description: 'Fixture child' }), text('Fixture child result.'), text('Child session completed.')] },
  'steer-queue': { calls: [{ ...text('Initial turn.'), delayMs: 1200 }, text('Steering applied.'), text('Queued turn completed.')] },
  'interrupt': { calls: [{ deltas: [{ text: 'Starting.' }, { text: 'Should be interrupted.', delayMs: 10000 }] }] },
  'interrupt-resume': { calls: [{ deltas: [{ text: 'Starting.' }, { text: 'Should be interrupted.', delayMs: 10000 }] }, text('Resumed steering input.')] },
  'revert': { calls: [text('Before revert.'), text('Redone after revert.')] },
  'fork': { calls: [text('History to fork.')] },
  'compaction': { calls: [text('Remember the fixture context.')] },
  'retry-429': { calls: [{ error: { status: 429, message: 'Scripted rate limit', retryAfter: '0' } }, text('Recovered from 429.')] },
  'retry-500': { calls: [{ error: { status: 500, message: 'Scripted server failure', retryAfter: '0' } }, text('Recovered from 500.')] },
  'final-error': { calls: [{ error: { status: 400, message: 'Scripted terminal error' } }] },
  'pty': { calls: [] },
  'pairing': { calls: [] },
  'v1-probe': { calls: [] },
};

export const checkpoint = `## Objective
- Record deterministic fixtures.
## Requirements
- Keep the server isolated.
## Decisions
- Use the mock provider.
## Work State
### Completed
- Recorded a reply.
### Active
- (none)
### Blocked
- (none)
## Next Move
1. Continue fixture checks.
## Relevant Files
- (none)
## Important Context
- The fixture context is deterministic.`;

export function auxiliaryKind(body) {
  const system = (body.messages ?? []).filter(m => ['system', 'developer'].includes(m.role)).map(m => JSON.stringify(m.content)).join('\n');
  // Title requests are known by their system prompt. 2.1.3 rewrote it (upstream d2812d147); 2.1.2 and
  // earlier, like the d0732ea source, use the first wording. Its user text alone is not a signal.
  if (system.includes('You are a title generator') || system.includes('You name conversations so the user can find them later')) return 'title';
  // Compaction appends a user instruction, so inspect its final message as well.
  const last = JSON.stringify(body.messages?.at(-1)?.content ?? '');
  if (last.includes('structured summary') || last.includes('consolidated summary') || last.includes('required summary template')) return 'compaction';
  if (system.includes('summary') && !body.tools?.length) return 'summary';
}

export function auxiliaryCall(kind) {
  return text(kind === 'title' ? 'Fixture conversation' : kind === 'compaction' ? checkpoint : 'Deterministic conversation summary.');
}
