// Pure steps of the spec watch: version selection, the OpenAPI comparison, the event-union diff and the
// issue text. index.mjs does the I/O; spec-watch.test.mjs runs these against recorded inputs.
import { eventNames } from '../contract/check-events.mjs';

const stable = version => /^2\.\d+\.\d+$/.test(version);
export const compareVersions = (a, b) => {
  const [aa, bb] = [a, b].map(version => version.split('.').map(Number));
  return aa[0] - bb[0] || aa[1] - bb[1] || aa[2] - bb[2];
};

/** Stable 2.x versions published after `baseline`, oldest first. */
export function newerVersions(registry, baseline) {
  return Object.keys(registry.versions ?? {}).filter(stable).filter(version => compareVersions(version, baseline) > 0).sort(compareVersions);
}

const METHODS = ['get', 'put', 'post', 'delete', 'patch', 'head', 'options', 'trace'];
const operations = spec => Object.entries(spec.paths ?? {}).flatMap(([path, item]) =>
  METHODS.filter(method => item?.[method]).map(method => `${method.toUpperCase()} ${path}`));
const schemas = spec => Object.keys(spec.components?.schemas ?? {});
const difference = (a, b) => { const other = new Set(b); return a.filter(item => !other.has(item)).sort(); };
const stableJSON = value => JSON.stringify(value, (_, item) => item && typeof item === 'object' && !Array.isArray(item)
  ? Object.fromEntries(Object.entries(item).sort(([a], [b]) => a.localeCompare(b))) : item);

/**
 * A structural summary that needs no external tool: operations and schemas added or removed, and the
 * operations and schemas whose definitions changed.
 */
export function summarizeOpenAPI(base, next) {
  const [before, after] = [operations(base), operations(next)];
  const kept = after.filter(operation => before.includes(operation));
  const definition = (spec, operation) => {
    const [method, path] = operation.split(' ');
    return stableJSON(spec.paths[path][method.toLowerCase()]);
  };
  const sharedSchemas = schemas(next).filter(name => schemas(base).includes(name));
  return {
    addedOperations: difference(after, before),
    removedOperations: difference(before, after),
    changedOperations: kept.filter(operation => definition(base, operation) !== definition(next, operation)).sort(),
    addedSchemas: difference(schemas(next), schemas(base)),
    removedSchemas: difference(schemas(base), schemas(next)),
    changedSchemas: sharedSchemas.filter(name => stableJSON(base.components.schemas[name]) !== stableJSON(next.components.schemas[name])).sort(),
  };
}

export const summaryIsEmpty = summary => Object.values(summary).every(list => list.length === 0);

/** `oasdiff changelog --format json` output, reduced to what the issue lists. Level 3 is breaking. */
export function parseOasdiff(text) {
  const entries = JSON.parse(text || '[]');
  if (!Array.isArray(entries)) throw new Error('oasdiff output is not a list');
  return entries.map(entry => ({
    breaking: entry.level === 3,
    level: entry.level,
    id: String(entry.id ?? ''),
    text: String(entry.text ?? ''),
    operation: [entry.operation, entry.path].filter(Boolean).join(' '),
  }));
}

/** The event types the app's decoder knows, from `ServerEvent.knownTypes`. */
export function appEventTypes(swift) {
  const block = swift.match(/public static let knownTypes: Set<String> = \[([\s\S]*?)\]/)?.[1];
  if (!block) throw new Error('ServerEvent.knownTypes is missing');
  return [...block.matchAll(/"([^"]+)"/g)].map(match => match[1]).sort();
}

/** Upstream's event union (generated types.ts) against the app's decoder. rpc.* stays open on both sides. */
export function eventDiff(types, known) {
  const upstream = eventNames(types);
  return { upstream: upstream.length, added: difference(upstream, known), removed: difference(known, upstream) };
}

export const issueTitle = version => `opencode ${version}: server changes to check`;

const list = (items, format = item => `\`${item}\``) => items.length ? items.map(item => `- ${format(item)}`).join('\n') : '- none';

/** The issue body. Product-facing: what changed upstream, and where. */
export function issueBody({ version, baseline, newer, summary, oasdiff, events, notes = [] }) {
  const lines = [
    `opencode ${version} is published on npm (\`@opencode/cli\`). The app's committed API reference is from ${baseline}.`,
    newer.length > 1 ? `Releases since then: ${newer.join(', ')}.` : '',
    '',
    '## OpenAPI (`/openapi.json`)',
  ];
  if (oasdiff) {
    const breaking = oasdiff.filter(entry => entry.breaking);
    lines.push(`oasdiff reports ${oasdiff.length} change${oasdiff.length === 1 ? '' : 's'}, ${breaking.length} breaking.`, '');
    if (breaking.length) lines.push('### Breaking', list(breaking, entry => `${entry.operation ? `\`${entry.operation}\`: ` : ''}${entry.text} (${entry.id})`), '');
    const other = oasdiff.filter(entry => !entry.breaking);
    if (other.length) lines.push('### Other changes', list(other.slice(0, 50), entry => `${entry.operation ? `\`${entry.operation}\`: ` : ''}${entry.text}`), other.length > 50 ? `- …and ${other.length - 50} more` : '', '');
  } else {
    lines.push('oasdiff was not run; structural comparison only.', '');
  }
  lines.push(
    '### Operations',
    `Added:\n${list(summary.addedOperations)}`,
    `Removed:\n${list(summary.removedOperations)}`,
    `Changed:\n${list(summary.changedOperations)}`,
    '',
    '### Schemas',
    `Added:\n${list(summary.addedSchemas)}`,
    `Removed:\n${list(summary.removedSchemas)}`,
    `Changed:\n${list(summary.changedSchemas)}`,
    '',
    '## Event types',
  );
  if (events) {
    lines.push(
      `The upstream event union has ${events.upstream} fixed types (plus \`rpc.*\`).`,
      `New upstream (the app decodes these as unknown events):\n${list(events.added)}`,
      `No longer upstream (still handled by the app):\n${list(events.removed)}`,
    );
  } else {
    lines.push('The generated event union could not be read for this release.');
  }
  if (notes.length) lines.push('', '## Notes', list(notes, note => note));
  lines.push('', 'The nightly server contract run tests the app against the latest 2.x release.');
  return lines.filter((line, index, all) => !(line === '' && all[index - 1] === '')).join('\n') + '\n';
}
