import { Capture } from '../fixture-recorder/transport.mjs';
import { selectMock } from '../fixture-recorder/scenarios.mjs';

export async function seed(sandbox, mock) {
  const capture = new Capture(sandbox);
  await capture.openSSE();
  try {
    const create = async title => (await capture.request('POST', '/api/session', {
      title, location: { directory: sandbox.project }, model: { providerID: 'mock', id: 'mock-1' },
    })).data.id;
    const prompt = async (id, scenario) => {
      await selectMock(mock, scenario);
      await capture.request('POST', `/api/session/${id}/prompt`, { text: `Run the ${scenario} fixture scenario.` });
    };
    const timeline = await create('Design system');
    for (const scenario of ['plain-text', 'reasoning-text', 'read-glob-grep', 'shell-output', 'permission-allow']) {
      await prompt(timeline, scenario);
      if (scenario === 'permission-allow') {
        const event = await capture.event('permission.asked', event => event.data.sessionID === timeline);
        await capture.request('POST', `/api/session/${timeline}/permission/${event.data.id}/reply`, { decision: 'once' });
      }
      await capture.request('POST', `/api/experimental/session/${timeline}/wait`);
    }
    const permission = await create('Permission request');
    await prompt(permission, 'permission-allow');
    await capture.event('permission.asked', event => event.data.sessionID === permission);
    const question = await create('Question');
    await prompt(question, 'question-form');
    await capture.event('form.created', event => (event.data.form ?? event.data).sessionID === question);
    return { timeline, permission, question };
  } finally { await capture.closeSSE(); }
}
