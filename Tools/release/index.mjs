// Archives, exports and uploads a release build. Signing is automatic and needs a team (TEAM_ID).
//
//   node Tools/release/index.mjs archive --unsigned   # dry run: a Release archive with signing off
//   TEAM_ID=… node Tools/release/index.mjs archive    # signed archive
//   TEAM_ID=… node Tools/release/index.mjs export     # .ipa for App Store Connect, in .build/release/export
//   TEAM_ID=… node Tools/release/index.mjs upload     # export straight to App Store Connect
//
// In CI, automatic signing and the upload authenticate with an App Store Connect API key:
// ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file). Locally, an Xcode account works instead.
// The version and build number come from Config/Version.xcconfig (Tools/release/version.mjs).
import { spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { access, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { parseVersion, VERSION_FILE } from './version.mjs';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const OUTPUT = path.join(ROOT, '.build/release');
const ARCHIVE = path.join(OUTPUT, 'Opencode.xcarchive');
export const EXTENSIONS = ['NotificationService.appex', 'Widgets.appex'];

export class ReleaseError extends Error {}

/** The App Store Connect API key, all three parts or none. */
export function apiKey(env) {
  const parts = { id: env.ASC_KEY_ID, issuer: env.ASC_ISSUER_ID, path: env.ASC_KEY_PATH };
  const given = Object.values(parts).filter(Boolean).length;
  if (given === 0) return undefined;
  if (given !== 3) throw new ReleaseError('Set all of ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH, or none of them');
  return parts;
}

const authentication = key => key ? ['-authenticationKeyPath', key.path, '-authenticationKeyID', key.id, '-authenticationKeyIssuerID', key.issuer] : [];

/** The team ID, which every signed step needs: ten upper-case letters and digits. */
export function team(env) {
  const value = (env.TEAM_ID ?? '').trim();
  if (!value) return undefined;
  if (!/^[A-Z0-9]{10}$/.test(value)) throw new ReleaseError(`TEAM_ID is not a team ID: ${value}`);
  return value;
}

/** The commands for one step, without running them. */
export function plan(step, { env = {}, unsigned = false } = {}) {
  const teamID = team(env), key = apiKey(env);
  if (!['archive', 'export', 'upload'].includes(step)) throw new ReleaseError(`Unknown step: ${step}`);
  if (unsigned && step !== 'archive') throw new ReleaseError('Only archive has an unsigned dry run');
  if (!unsigned && !teamID) {
    throw new ReleaseError('No team. Set TEAM_ID to the Apple Developer team ID, or run "archive --unsigned" for a dry run that stops before signing.');
  }
  const xcodebuild = ['xcodebuild', '-project', 'Opencode.xcodeproj', '-skipPackagePluginValidation'];
  if (step === 'archive') {
    const signing = unsigned
      ? ['CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'DEVELOPMENT_TEAM=']
      : [`DEVELOPMENT_TEAM=${teamID}`, '-allowProvisioningUpdates', ...authentication(key)];
    return [
      ['xcodegen', 'generate'],
      [...xcodebuild, '-scheme', 'Opencode', '-configuration', 'Release', '-destination', 'generic/platform=iOS',
        '-derivedDataPath', path.join(OUTPUT, 'DerivedData'), '-archivePath', ARCHIVE, 'archive', ...signing],
    ];
  }
  const options = path.join(OUTPUT, `ExportOptions-${step}.plist`);
  return [[
    'xcodebuild', '-exportArchive', '-archivePath', ARCHIVE, '-exportOptionsPlist', options,
    '-exportPath', path.join(OUTPUT, 'export'), '-allowProvisioningUpdates', ...authentication(key),
  ]];
}

/** App Store Connect distribution with automatic signing; `upload` sends the build instead of writing an .ipa. */
export function exportOptions(step, teamID) {
  const entries = {
    method: 'app-store-connect', destination: step === 'upload' ? 'upload' : 'export', teamID,
    signingStyle: 'automatic', uploadSymbols: true, manageAppVersionAndBuildNumber: false,
  };
  const value = item => typeof item === 'boolean' ? `<${item}/>` : `<string>${item}</string>`;
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
${Object.entries(entries).map(([key, item]) => `  <key>${key}</key>${value(item)}`).join('\n')}
</dict></plist>
`;
}

function run(command, log) {
  return new Promise((resolve, reject) => {
    log.write(`$ ${command.join(' ')}\n`);
    const child = spawn(command[0], command.slice(1), { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.pipe(log, { end: false });
    child.stderr.pipe(log, { end: false });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve() : reject(new ReleaseError(`${command[0]} exited with ${code}; see the log`)));
  });
}

const plist = async (file, key) => {
  const output = [];
  await new Promise((resolve, reject) => {
    const child = spawn('plutil', ['-extract', key, 'raw', '-o', '-', file]);
    child.stdout.on('data', chunk => output.push(chunk));
    child.on('close', code => code === 0 ? resolve() : reject(new ReleaseError(`${key} is missing from ${path.relative(ROOT, file)}`)));
  });
  return Buffer.concat(output).toString().trim();
};

/** Checks the archive holds the app and both extensions, all at the version in Config/Version.xcconfig. */
export async function checkArchive(archive = ARCHIVE) {
  const expected = parseVersion(await readFile(VERSION_FILE, 'utf8'));
  const app = path.join(archive, 'Products/Applications/Opencode.app');
  const bundles = [app, ...EXTENSIONS.map(name => path.join(app, 'PlugIns', name))];
  const found = [];
  for (const bundle of bundles) {
    await access(bundle).catch(() => { throw new ReleaseError(`Missing from the archive: ${path.relative(archive, bundle)}`); });
    const info = path.join(bundle, 'Info.plist');
    const marketing = await plist(info, 'CFBundleShortVersionString'), build = await plist(info, 'CFBundleVersion');
    if (marketing !== expected.marketing || build !== String(expected.build)) {
      throw new ReleaseError(`${path.basename(bundle)} is ${marketing} (${build}), expected ${expected.marketing} (${expected.build})`);
    }
    found.push(path.basename(bundle));
  }
  const plugins = (await readdir(path.join(app, 'PlugIns'))).sort();
  return { version: expected, bundles: found, plugins };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: { unsigned: { type: 'boolean' } } });
  const step = positionals[0];
  try {
    const commands = plan(step, { env: process.env, unsigned: values.unsigned });
    await mkdir(OUTPUT, { recursive: true });
    const logFile = path.join(OUTPUT, `${step}${values.unsigned ? '-unsigned' : ''}.log`);
    const log = createWriteStream(logFile);
    console.log(`Release ${step}${values.unsigned ? ' (unsigned dry run)' : ''}; log ${path.relative(ROOT, logFile)}`);
    if (step === 'archive') await Promise.all([ARCHIVE, path.join(OUTPUT, 'archive.json')].map(item => rm(item, { recursive: true, force: true })));
    else await writeFile(path.join(OUTPUT, `ExportOptions-${step}.plist`), exportOptions(step, team(process.env)));
    if (step !== 'archive') {
      const record = JSON.parse(await readFile(path.join(OUTPUT, 'archive.json'), 'utf8').catch(() => '{}'));
      if (!record.signed) throw new ReleaseError('Export and upload need a signed archive: run "archive" with TEAM_ID first');
    }
    for (const command of commands) await run(command, log);
    if (step === 'archive') {
      const summary = { ...(await checkArchive()), signed: !values.unsigned, archive: path.relative(ROOT, ARCHIVE) };
      await writeFile(path.join(OUTPUT, 'archive.json'), JSON.stringify(summary, null, 2) + '\n');
      log.write(`\n${JSON.stringify(summary)}\n`);
      console.log(`Archived ${summary.version.marketing} (${summary.version.build}) with ${summary.plugins.join(', ')}${summary.signed ? '' : '; unsigned, so it stops here'}`);
    } else {
      console.log(step === 'upload' ? 'Uploaded to App Store Connect' : `Exported to ${path.relative(ROOT, path.join(OUTPUT, 'export'))}`);
    }
    log.end();
  } catch (error) {
    if (!(error instanceof ReleaseError)) throw error;
    console.error(error.message);
    process.exit(1);
  }
}
