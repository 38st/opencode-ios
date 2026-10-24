import schema from "../../contracts/schema/activity-state.schema.json" with { type: "json" };
import { isObject } from "./validation.ts";

export interface ActivityState {
  readonly phase: string;
  readonly step: number;
  readonly toolGlyph: string;
  readonly startedAt: number;
  readonly updatedAt: number;
}

const { phase, step, toolGlyph, startedAt, updatedAt } = schema.properties;
const keys = new Set(Object.keys(schema.properties));

/**
 * Live Activity state is plaintext to the relay and Apple, so the relay accepts exactly the
 * coarse fields of schema/activity-state.schema.json and nothing else.
 */
export function activityState(value: unknown): ActivityState | undefined {
  if (!isObject(value) || Object.keys(value).some((key) => !keys.has(key))) return undefined;
  const number = (item: unknown, minimum: number, maximum = Number.MAX_SAFE_INTEGER) =>
    typeof item === "number" && Number.isFinite(item) && item >= minimum && item <= maximum;
  if (!phase.enum.includes(value.phase as string)) return undefined;
  if (!toolGlyph.enum.includes(value.toolGlyph as string)) return undefined;
  if (!Number.isSafeInteger(value.step) || !number(value.step, step.minimum, step.maximum)) return undefined;
  if (!number(value.startedAt, startedAt.minimum) || !number(value.updatedAt, updatedAt.minimum)) return undefined;
  return value as unknown as ActivityState;
}
