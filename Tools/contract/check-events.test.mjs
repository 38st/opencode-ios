import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkEvents, eventNames } from './check-events.mjs';

test('event coverage detects a new source event', () => {
  const source = 'export type V2Event =\n  | A\n  | B\n\nexport type A = { type: "one" }\nexport type B = { type: "two" }\n';
  assert.deepEqual(eventNames(source), ['one', 'two']);
  assert.throws(() => checkEvents(source, 'static func decode( case "one": public var header'));
  checkEvents(source, 'static func decode( case "one": case "two": public var header');
});
