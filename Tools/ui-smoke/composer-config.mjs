import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

// Opt-in only: contract/fixture configurations and existing captures stay unchanged.
export async function configureComposer(config, dirs) {
  config.providers.mock.models['mock-vision'] = {
    name: 'Mock Vision (latest)', capabilities: { tools: true, input: ['text', 'image', 'pdf'], output: ['text'] },
    variants: [{ id: 'careful', settings: { temperature: 0.1 } }, { id: 'fast', settings: { temperature: 0.3 } }],
    limit: { context: 128000, output: 4096 }, cost: { input: 1, output: 2 },
  };
  Object.assign(config.agents, {
    reviewer: { mode: 'primary', description: 'Review changes carefully', color: '#8476CA', model: 'mock/mock-1' },
    'hidden-reviewer': { mode: 'primary', hidden: true, model: 'mock/mock-1' },
    researcher: { mode: 'subagent', description: 'Research context', model: 'mock/mock-1' },
  });
  config.commands = { check: { template: 'Check this input: $ARGUMENTS', description: 'Check the supplied input' } };
  const skills = path.join(dirs.config, 'composer-skills');
  await mkdir(path.join(skills, 'smoke-skill'), { recursive: true });
  await writeFile(path.join(skills, 'smoke-skill', 'SKILL.md'), '---\nname: smoke-skill\ndescription: A deterministic UI smoke skill\n---\nInspect the supplied context.\n');
  config.skills = [skills];
}
