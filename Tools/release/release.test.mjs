import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { apiKey, exportOptions, plan, ReleaseError, team } from './index.mjs';
import { parseVersion, VERSION_FILE, withVersion } from './version.mjs';

const TEAM = { TEAM_ID: 'ABCDE12345' };
const KEY = { ASC_KEY_ID: 'KEY123', ASC_ISSUER_ID: '00000000-0000-0000-0000-000000000000', ASC_KEY_PATH: '/tmp/AuthKey.p8' };

test('every step refuses to run without a team, except the unsigned archive', () => {
  for (const step of ['archive', 'export', 'upload']) assert.throws(() => plan(step), /No team/);
  const [generate, archive] = plan('archive', { unsigned: true });
  assert.deepEqual(generate, ['xcodegen', 'generate']);
  for (const flag of ['CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'archive', '-skipPackagePluginValidation', 'generic/platform=iOS', 'Release']) assert.ok(archive.includes(flag), flag);
  assert.ok(!archive.includes('-allowProvisioningUpdates'));
  assert.throws(() => plan('export', { unsigned: true }), /Only archive/);
  assert.throws(() => plan('ship', { env: TEAM }), /Unknown step/);
});

test('signed steps use the team, automatic signing and the API key when given', () => {
  const [, archive] = plan('archive', { env: { ...TEAM, ...KEY } });
  assert.ok(archive.includes('DEVELOPMENT_TEAM=ABCDE12345'));
  assert.ok(archive.includes('-allowProvisioningUpdates'));
  assert.deepEqual(archive.slice(archive.indexOf('-authenticationKeyPath'), archive.indexOf('-authenticationKeyPath') + 6),
    ['-authenticationKeyPath', '/tmp/AuthKey.p8', '-authenticationKeyID', 'KEY123', '-authenticationKeyIssuerID', KEY.ASC_ISSUER_ID]);
  const [upload] = plan('upload', { env: TEAM });
  assert.ok(upload.includes('-exportArchive'));
  assert.ok(!upload.includes('-authenticationKeyPath'));
});

test('the team and the API key are validated', () => {
  assert.equal(team({}), undefined);
  assert.throws(() => team({ TEAM_ID: 'team' }), ReleaseError);
  assert.equal(apiKey({}), undefined);
  assert.throws(() => apiKey({ ASC_KEY_ID: 'x' }), /all of/);
});

test('export options name App Store Connect, the team and the destination', () => {
  const upload = exportOptions('upload', 'ABCDE12345');
  assert.match(upload, /<key>method<\/key><string>app-store-connect<\/string>/);
  assert.match(upload, /<key>destination<\/key><string>upload<\/string>/);
  assert.match(upload, /<key>teamID<\/key><string>ABCDE12345<\/string>/);
  assert.match(upload, /<key>manageAppVersionAndBuildNumber<\/key><false\/>/);
  assert.match(exportOptions('export', 'ABCDE12345'), /<key>destination<\/key><string>export<\/string>/);
});

test('the version and build number come from Config/Version.xcconfig', async () => {
  const text = await readFile(VERSION_FILE, 'utf8');
  const current = parseVersion(text);
  assert.match(current.marketing, /^\d+\.\d+(\.\d+)?$/);
  const updated = withVersion(text, { marketing: '1.2.3', build: 42 });
  assert.deepEqual(parseVersion(updated), { marketing: '1.2.3', build: 42 });
  assert.equal(updated.split('\n').length, text.split('\n').length);
  assert.throws(() => withVersion(text, { build: 0 }), /build number/);
  assert.throws(() => withVersion(text, { marketing: 'v1' }), /version/);
});

test('project.yml takes the version from Config/Version.xcconfig instead of setting it', async () => {
  const project = await readFile(new URL('../../project.yml', import.meta.url), 'utf8');
  assert.doesNotMatch(project, /MARKETING_VERSION:|CURRENT_PROJECT_VERSION:/, 'project.yml must not set the version itself');
});
