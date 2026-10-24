export interface LimitRule {
  readonly windowSeconds: number;
  readonly max: number;
}

/** Counts one event against every rule, or refuses without counting if any window is full. */
export interface Limiter {
  hit(key: string, rules: readonly LimitRule[], now: number): Promise<boolean>;
}

/** Fixed windows: the bucket for a rule is floor(now / windowSeconds). */
export const bucketName = (rule: LimitRule, now: number): string => `${rule.windowSeconds}:${Math.floor(now / rule.windowSeconds)}`;

/** The storage a Durable Object offers, reduced to what the limiter uses. */
export interface CounterStorage {
  get<T>(key: string): Promise<T | undefined>;
  put(entries: Record<string, number>): Promise<void>;
  list<T>(): Promise<Map<string, T>>;
  delete(keys: string[]): Promise<number>;
}

/** The Durable Object side: one object per limited key, so its storage holds only that key's buckets. */
export async function hitCounters(storage: CounterStorage, rules: readonly LimitRule[], now: number): Promise<boolean> {
  const names = rules.map((rule) => bucketName(rule, now));
  const stored = await storage.list<number>();
  const stale = [...stored.keys()].filter((name) => !names.includes(name));
  if (stale.length) await storage.delete(stale);
  const counts = names.map((name) => stored.get(name) ?? 0);
  if (rules.some((rule, index) => counts[index]! >= rule.max)) return false;
  await storage.put(Object.fromEntries(names.map((name, index) => [name, counts[index]! + 1])));
  return true;
}
