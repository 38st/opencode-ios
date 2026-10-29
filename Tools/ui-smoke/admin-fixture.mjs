import path from 'node:path';
import { copyFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { run } from '../opencode-sandbox/process.mjs';

// The server settings tests get their own Git project (worktrees need a commit) and a copy of the MCP fixture,
// which they register at runtime in that project's location only, so no other test sees its resources.
export async function seedAdmin(server) {
  const directory = path.join(server.root, 'admin-project');
  await mkdir(directory);
  await writeFile(path.join(directory, 'README.md'), 'Server settings UI fixture\n');
  const git = args => run('/usr/bin/git', args, { env: server.env, cwd: directory });
  await git(['init', '--quiet', '--initial-branch=main']);
  await git(['add', 'README.md']);
  await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'Fixture']);
  const mcpFixture = path.join(server.root, 'mcp-fixture.mjs');
  await copyFile(fileURLToPath(new URL('../mcp-fixture/server.mjs', import.meta.url)), mcpFixture);
  return { directory, mcpFixture };
}
