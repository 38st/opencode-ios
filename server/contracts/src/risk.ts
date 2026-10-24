import rules from "../risk-rules.json" with { type: "json" };

export type Tier = "low" | "elevated" | "high";
export interface Classification {
  readonly tier: Tier;
  /** The id of the deciding rule: an escalation pattern, an action rule, or the default. */
  readonly rule: string;
}

interface RulesFile {
  /** Joined resources longer than this (UTF-16 code units) get `rule` before any pattern runs. */
  readonly limits: { readonly maxLength: number; readonly rule: { readonly id: string; readonly tier: string } };
  readonly macros: Readonly<Record<string, string>>;
  readonly actions: readonly {
    readonly id: string;
    readonly actions: readonly string[];
    readonly tier: string;
    readonly escalate?: readonly { readonly id: string; readonly tier: string; readonly pattern: string }[];
  }[];
  readonly default: { readonly id: string; readonly tier: string };
}

export const RISK_RULES: RulesFile = rules;
const macros = RISK_RULES.macros;

/** Replaces each `{name}` with its macro. Quantifiers such as `{2}` contain digits and are left alone. */
export function expandMacros(pattern: string): string {
  return pattern.replace(/\{([a-z]+)\}/g, (_, name: string) => {
    const value = macros[name];
    if (value === undefined) throw new Error(`Unknown risk macro {${name}}`);
    return value;
  });
}

interface CompiledRule {
  readonly id: string;
  readonly actions: ReadonlySet<string>;
  readonly tier: Tier;
  readonly escalate: readonly { readonly id: string; readonly tier: Tier; readonly regex: RegExp }[];
}

// No flags: the portable dialect behaves the same under ICU (NSRegularExpression) and ECMAScript.
const compiled: readonly CompiledRule[] = RISK_RULES.actions.map((rule) => ({
  id: rule.id,
  actions: new Set(rule.actions),
  tier: rule.tier as Tier,
  escalate: (rule.escalate ?? []).map((item) => ({
    id: item.id,
    tier: item.tier as Tier,
    regex: new RegExp(expandMacros(item.pattern)),
  })),
}));

/**
 * Classifies a permission request. The action is matched exactly. Escalation patterns are tested,
 * in order, against the resources joined with "\n" and lowercased with the Unicode default mapping.
 * A joined text over `limits.maxLength` code units is rated by `limits.rule` without running any
 * pattern, which bounds the time a request can cost.
 */
export function classify(action: string, resources: readonly string[]): Classification {
  const rule = compiled.find((candidate) => candidate.actions.has(action));
  if (!rule) return { tier: RISK_RULES.default.tier as Tier, rule: RISK_RULES.default.id };
  if (rule.escalate.length) {
    const joined = resources.join("\n");
    if (joined.length > RISK_RULES.limits.maxLength) return { tier: RISK_RULES.limits.rule.tier as Tier, rule: RISK_RULES.limits.rule.id };
    const text = joined.toLowerCase();
    const match = rule.escalate.find((candidate) => candidate.regex.test(text));
    if (match) return { tier: match.tier, rule: match.id };
  }
  return { tier: rule.tier, rule: rule.id };
}
