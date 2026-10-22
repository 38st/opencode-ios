import { mkdir, writeFile, realpath, symlink } from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import { randomBytes } from 'node:crypto';
import { parseArgs } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { launch, run, stopAll, onShutdown } from './process.mjs';
import { audit } from './isolation.mjs';
import { verifiedSandboxCommand } from './profile.mjs';
import { startMock } from '../mock-llm/server.mjs';

export const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const V1_VERSION = '1.19.3';
export const basic = password => `Basic ${Buffer.from(`opencode:${password}`).toString('base64')}`;

export async function resolveVersion(override) {
  if (override) {
    if (!/^2\.\d+\.\d+$/.test(override)) throw new Error('Expected an exact stable 2.x version');
    return override;
  }
  const response = await fetch('https://registry.npmjs.org/@opencode%2fcli', { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`npm registry: ${response.status}`);
  const metadata = await response.json();
  const versions = Object.keys(metadata.versions).filter(version => /^2\.\d+\.\d+$/.test(version));
  versions.sort((a, b) => {
    const aa = a.split('.').map(Number), bb = b.split('.').map(Number);
    return bb[1] - aa[1] || bb[2] - aa[2];
  });
  if (!versions.length) throw new Error('npm has no stable 2.x release');
  return versions[0];
}

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  if (port === 49374 || port === 49375) return freePort();
  return port;
}

export async function startSandbox({ version, mockURL, v1 = false, configure }) {
  if (v1 ? version !== V1_VERSION : !/^2\.\d+\.\d+$/.test(version)) throw new Error('Invalid sandbox version');
  const versionRoot = path.join(repository, '.build/opencode-sandbox', version);
  const root = path.join(versionRoot, randomBytes(4).toString('hex'));
  const dirs = Object.fromEntries(['home', 'config', 'data', 'state', 'cache', 'tmp', 'runtime', 'bin', 'project'].map(name => [name, path.join(root, name)]));
  await Promise.all(Object.values(dirs).map(dir => mkdir(dir, { recursive: true, mode: 0o700 })));
  const password = randomBytes(32).toString('base64url');
  // Construct from an allowlist: never inherit credentials, OTEL exporters, npmrc,
  // OPENCODE overrides, XDG roots, shell startup hooks, or NODE_OPTIONS.
  const env = {
    PATH: `${dirs.bin}:/usr/bin:/bin:/usr/sbin:/sbin`,
    HOME: dirs.home, USER: 'fixture', LOGNAME: 'fixture', SHELL: '/bin/bash',
    LANG: 'en_US.UTF-8', LC_ALL: 'en_US.UTF-8', TERM: 'xterm-256color', TZ: 'UTC',
    TMPDIR: dirs.tmp, TMP: dirs.tmp, TEMP: dirs.tmp,
    XDG_CONFIG_HOME: dirs.config, XDG_DATA_HOME: dirs.data, XDG_STATE_HOME: dirs.state,
    XDG_CACHE_HOME: dirs.cache, XDG_RUNTIME_DIR: dirs.runtime,
    XDG_CONFIG_DIRS: dirs.config, XDG_DATA_DIRS: dirs.data,
    npm_config_cache: path.join(versionRoot, 'npm-cache'),
    npm_config_prefix: path.join(root, 'npm-prefix'),
    npm_config_userconfig: path.join(root, 'npmrc'),
    npm_config_globalconfig: path.join(root, 'npmrc-global'),
    npm_config_update_notifier: 'false', npm_config_audit: 'false', npm_config_fund: 'false',
    npm_config_allow_scripts: v1 ? 'opencode-ai' : '@opencode/cli',
    GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(root, 'gitconfig'),
    OPENCODE_PASSWORD: password, OPENCODE_SERVER_PASSWORD: password,
    OPENCODE_SERVER_USERNAME: 'opencode', OPENCODE_TEST_HOME: dirs.home,
    OPENCODE_CONFIG_DIR: path.join(dirs.config, 'opencode'),
    OPENCODE_CONFIG: path.join(root, 'opencode.json'),
    OPENCODE_DB: path.join(dirs.data, 'opencode.db'),
    OPENCODE_MODELS_PATH: path.join(root, 'models.json'),
    OPENCODE_MODELS_URL: `${mockURL}/models-disabled`, OPENCODE_DISABLE_MODELS_FETCH: '1',
    OPENCODE_DISABLE_AUTOUPDATE: '1', OPENCODE_DISABLE_SHARE: '1',
    OPENCODE_DISABLE_PROJECT_CONFIG: '1', OPENCODE_CONFIG_PROJECT_DISABLE: '1',
    OPENCODE_DISABLE_CLAUDE_CODE: '1', OPENCODE_DISABLE_CLAUDE_CODE_SKILLS: '1',
    OPENCODE_DISABLE_FILEWATCHER: '1', OPENCODE_DISABLE_FFF: '1',
    OPENCODE_PTY_BIN: path.join(root, 'disabled-persistent-pty'),
    OPENCODE_CLI_CONFIG_CONTENT: JSON.stringify({ update: 'disable' }),
    OTEL_SDK_DISABLED: 'true', DO_NOT_TRACK: '1', NO_COLOR: '1',
  };
  await symlink(process.execPath, path.join(dirs.bin, 'node'));
  // Resolve npm's npx next to the active Node installation, never an opencode executable.
  const npx = await realpath(path.join(path.dirname(process.execPath), 'npx'));
  await writeFile(env.npm_config_userconfig, 'registry=https://registry.npmjs.org/\n');
  await writeFile(env.npm_config_globalconfig, '');
  await writeFile(env.GIT_CONFIG_GLOBAL, '');
  await mkdir(env.OPENCODE_CONFIG_DIR, { recursive: true });
  await writeFile(env.OPENCODE_MODELS_PATH, '{}');
  const config = v1 ? { autoupdate: false, share: 'disabled', lsp: false, formatter: false } : {
    update: 'disable', share: 'disabled', model: 'mock/mock-1', shell: '/bin/bash',
    lsp: false, formatter: false, warming: false,
    providers: {
      mock: {
        name: 'Fixture Mock', package: '@opencode/ai/providers/openai-compatible',
        settings: { baseURL: `${mockURL}/v1`, apiKey: 'fixture-not-a-secret' },
        models: {
          'mock-1': { name: 'Mock 1', capabilities: { tools: true, input: ['text'], output: ['text'] }, limit: { context: 128000, output: 4096 } },
        },
      },
    },
    agents: Object.fromEntries(['title', 'summary', 'compaction'].map(id => [id, { model: 'mock/mock-1' }])),
    permissions: [{ action: '*', resource: '*', effect: 'allow' }, { action: 'edit', resource: '*', effect: 'ask' }],
  };
  const restrictions = configure && !v1 ? await configure(config, dirs, env) : undefined;
  await writeFile(env.OPENCODE_CONFIG, JSON.stringify(config, null, 2));
  env.OPENCODE_CONFIG_CONTENT = JSON.stringify(config);
  await writeFile(path.join(dirs.project, 'sample.txt'), 'original fixture line\nsecond line\n');
  await run('/usr/bin/git', ['init', '--quiet', dirs.project], { env, cwd: root });
  const port = await freePort(), baseURL = `http://127.0.0.1:${port}`;
  const invocation = await verifiedSandboxCommand(process.execPath, [npx, '-y', `${v1 ? 'opencode-ai' : '@opencode/cli'}@${version}`, 'serve', '--hostname', '127.0.0.1', '--port', String(port)], root, undefined, restrictions?.deniedReads);
  const group = launch(invocation.command, invocation.args, { cwd: dirs.project, env, sandboxed: true, enforcement: invocation.enforcement });
  try {
    const deadline = Date.now() + 180000;
    while (Date.now() < deadline) {
      group.check();
      if (!await group.verifyEnforcement()) { await delay(50); continue; }
      try {
        const response = await fetch(`${baseURL}${v1 ? '/global/health' : '/api/info'}`, { headers: { authorization: basic(password) }, signal: AbortSignal.timeout(1500) });
        if (response.ok) {
          const info = await response.json();
          if (info.version !== version) throw new Error(`Wrong server version: ${info.version}, expected ${version}`);
          await writeFile(path.join(root, 'run.json'), JSON.stringify({ version, baseURL, pid: group.child.pid, mode: 'foreground', project: dirs.project }, null, 2));
          return { version, baseURL, password, root, project: dirs.project, env, info, pid: group.child.pid,
            async stop() { await group.stop(); await writeFile(path.join(root, 'server.log'), group.output); await writeFile(path.join(root, 'cleanup.json'), JSON.stringify({ processGroup: group.child.pid, survivors: [] }) + '\n'); } };
        }
      } catch (error) {
        if (error.message.startsWith('Wrong server')) throw error;
      }
      await delay(150);
    }
    throw new Error(`Server startup timed out: ${group.output}`);
  } catch (error) {
    await group.stop();
    await writeFile(path.join(root, 'server.log'), group.output);
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { values } = parseArgs({ options: { v1: { type: 'boolean' }, version: { type: 'string' } } });
  const v1 = values.v1 ?? false;
  const version = v1 ? V1_VERSION : await resolveVersion(values.version);
  await audit(path.join(repository, '.build/opencode-sandbox/audits/manual'), async () => {
    const mock = await startMock();
    const removeHook = onShutdown(() => mock.close());
    try {
      const sandbox = await startSandbox({ version, v1, mockURL: mock.url });
      // Explicit interactive handoff only. Recorders and contracts never print passwords.
      console.log(JSON.stringify({ baseURL: sandbox.baseURL, password: sandbox.password, mockURL: mock.url, project: sandbox.project }));
      await new Promise(resolve => { for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, resolve); });
      await sandbox.stop();
    } finally { removeHook(); await stopAll(); await mock.close(); }
  });
}
