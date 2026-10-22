import { seed } from '../design-reference/seed.mjs';
import { Capture } from '../fixture-recorder/transport.mjs';
import { selectMock } from '../fixture-recorder/scenarios.mjs';

export async function seedReadScreens(server, mock) {
  const screens = await seed(server, mock);
  const capture = new Capture(server);
  const create = async title => (await capture.request('POST', '/api/session', {
    title, location: { directory: server.project }, model: { providerID: 'mock', id: 'mock-1' },
  })).data.id;
  const agent = await create('Agent research');
  await selectMock(mock, 'subagent');
  await capture.request('POST', `/api/session/${agent}/prompt`, { text: 'Inspect the fixture with a subagent.' });
  await capture.request('POST', `/api/experimental/session/${agent}/wait`);
  const unread = await create('Unread check');
  await selectMock(mock, 'plain-text');
  await capture.request('POST', `/api/session/${unread}/prompt`, { text: 'Finish a turn for the mark-read check.' });
  await capture.request('POST', `/api/experimental/session/${unread}/wait`);
  const live = await create('Live transcript');
  return { ...screens, agent, unread, live };
}
