import { readFile } from "node:fs/promises";
import { describe, expect, test } from "vitest";
import { classify, expandMacros, RISK_RULES, type Tier } from "../src/index.ts";

const order: Record<Tier, number> = { low: 0, elevated: 1, high: 2 };
const vectors = JSON.parse(await readFile(new URL("../vectors/risk.json", import.meta.url), "utf8")).cases as {
  name: string;
  action: string;
  resources: string[];
  tier: Tier;
  rule: string;
}[];

// The subset that ICU (NSRegularExpression) and ECMAScript evaluate identically. Classes and
// boundaries are spelled out (no \b \s \w \d or .), there are no anchors or flags, lookbehinds
// hold a single class, and every character outside an escape is printable ASCII.
function checkPortable(pattern: string): string[] {
  const problems: string[] = [];
  const escapesOutside = new Set(["|", "+", ".", "(", ")", "*", "?", "[", "]", "\\", "/", "-", "{", "}", "^", "$", "t", "n", "f", "r"]);
  const escapesInside = new Set(["t", "n", "f", "r", "-", "]", "\\", "^"]);
  let index = 0, inClass = false;
  while (index < pattern.length) {
    const char = pattern[index]!;
    if (char.charCodeAt(0) < 0x20 || char.charCodeAt(0) > 0x7e) problems.push(`non-ASCII literal at ${index}`);
    if (/[A-Z]/.test(char)) problems.push(`uppercase literal ${char} can never match lowercased text`);
    if (char === "\\") {
      const next = pattern[index + 1] ?? "";
      if (next === "u") {
        if (!/^[0-9a-f]{4}$/.test(pattern.slice(index + 2, index + 6))) problems.push(`bad \\u escape at ${index}`);
        index += 6;
        continue;
      }
      if (!(inClass ? escapesInside : escapesOutside).has(next)) problems.push(`escape \\${next} is not portable`);
      index += 2;
      continue;
    }
    if (inClass) {
      if (char === "]") inClass = false;
      index++;
      continue;
    }
    if (char === "[") {
      inClass = true;
      index += pattern[index + 1] === "^" ? 2 : 1;
      continue;
    }
    if (char === "." || char === "^" || char === "$") problems.push(`${char} is not portable outside a class`);
    if (char === "(" && pattern[index + 1] === "?") {
      const head = ["(?:", "(?=", "(?!", "(?<=", "(?<!"].find((prefix) => pattern.startsWith(prefix, index));
      if (!head) problems.push(`group syntax at ${index} is not portable`);
      else if (head.startsWith("(?<")) {
        const close = pattern.indexOf(")", index);
        if (!/^\[[^\]]+\]$/.test(pattern.slice(index + head.length, close))) problems.push("a lookbehind must hold one class");
      }
    }
    if (char === "{" && !/^\{\d+(,\d*)?\}/.test(pattern.slice(index))) problems.push(`{ at ${index} is not a quantifier`);
    index++;
  }
  if (inClass) problems.push("unterminated class");
  return problems;
}

describe("risk-rules.json", () => {
  const patterns = RISK_RULES.actions.flatMap((rule) => (rule.escalate ?? []).map((item) => [item.id, item.pattern] as const));

  for (const [id, pattern] of patterns) {
    test(`${id} stays inside the portable dialect`, () => expect(checkPortable(expandMacros(pattern))).toEqual([]));
  }

  test("macros are portable too, and unknown macros are rejected", () => {
    for (const value of Object.values(RISK_RULES.macros)) expect(checkPortable(value)).toEqual([]);
    expect(() => expandMacros("{nope}")).toThrow();
    expect(expandMacros("a{2}")).toBe("a{2}");
  });

  test("ids are unique, actions appear once, and escalation never lowers a tier", () => {
    const ids = [RISK_RULES.default.id, ...RISK_RULES.actions.flatMap((rule) => [rule.id, ...(rule.escalate ?? []).map((item) => item.id)])];
    expect(new Set(ids).size).toBe(ids.length);
    const actions = RISK_RULES.actions.flatMap((rule) => rule.actions);
    expect(new Set(actions).size).toBe(actions.length);
    for (const rule of RISK_RULES.actions) {
      for (const item of rule.escalate ?? []) expect(order[item.tier as Tier]).toBeGreaterThanOrEqual(order[rule.tier as Tier]);
    }
  });

  test("every rule is exercised by a vector", () => {
    const used = new Set(vectors.map((item) => item.rule));
    const ids = [RISK_RULES.default.id, ...RISK_RULES.actions.flatMap((rule) => [rule.id, ...(rule.escalate ?? []).map((item) => item.id)])];
    expect(ids.filter((id) => !used.has(id))).toEqual([]);
  });
});

// The app's original OCModels/PermissionRisk.swift rules, transcribed. ECMAScript's \b, \s and . already have the
// ASCII-boundary, whitespace and line semantics the shared macros spell out.
function originalSwift(action: string, resources: readonly string[]): Tier {
  switch (action) {
    case "read": case "glob": case "grep": case "list":
      return "low";
    case "edit": case "write": case "patch": case "apply_patch": case "webfetch": case "websearch":
      return "elevated";
    case "shell": case "bash": {
      const text = resources.join("\n").toLowerCase();
      const high = [/\brm\b/, /\bsudo\b/, /\b(chmod|chown|mkfs|dd)\b/, /\bgit\s+(push|reset|clean)\b/, /(curl|wget).*\|/, /\b(sh|bash|zsh)\s+-c\b/, />\s*\//];
      return high.some((pattern) => pattern.test(text)) ? "high" : "elevated";
    }
    default:
      return "high";
  }
}

describe("compatibility with the original Swift rules", () => {
  // Rated higher than the original rules on purpose: force-push forms its `git\s+push` missed, the length cap, and
  // U+0085, which ICU's `\s` matched on iOS but ECMAScript's does not.
  const additions = new Set(["force-push", "too-long"]);
  for (const item of vectors) {
    test(item.name, () => {
      const before = originalSwift(item.action, item.resources);
      const after = classify(item.action, item.resources);
      if ((additions.has(after.rule) || item.resources.join("").includes("\u0085")) && before !== "high") expect(after.tier).toBe("high");
      else expect(after.tier).toBe(before);
    });
  }

  test("the only additions are the force-push forms the original rules missed, the length cap and ICU's U+0085", () => {
    const changed = vectors.filter((item) => originalSwift(item.action, item.resources) !== item.tier).map((item) => item.name);
    expect(changed).toEqual([
      "shell, git push with a next line (U+0085, ICU whitespace)",
      "shell, force-push with -C",
      "shell, force-push with -c and refspec",
      "shell, force-push after many options",
      "shell, push is matched as a token, not as part of one",
      "shell, resources over the length cap are too long",
      "shell, the cap counts the joined text",
    ]);
  });
});

describe("time bounds", () => {
  const limit = RISK_RULES.limits.maxLength;
  // Inputs at the cap built to make quantified parts overlap. A rule that backtracks catastrophically takes seconds here.
  const adversarial = [
    "git x push ".repeat(limit / 11), "git -c a=b ".repeat(limit / 11) + "push", "push ".repeat(limit / 5), "git push ".repeat(limit / 9) + "--f",
    "curl ".repeat(limit / 5), "x ".repeat(limit / 2), "sh -".repeat(limit / 4), "> ".repeat(limit / 2), "\u0085".repeat(limit), "-".repeat(limit),
    `echo "${"git x push ".repeat(limit / 11)}"`,
  ];
  for (const [index, input] of adversarial.entries()) {
    test(`adversarial input ${index + 1} (${input.length} code units) finishes within the budget`, () => {
      expect(input.length).toBeLessThanOrEqual(limit + 16);
      const start = performance.now();
      classify("shell", [input]);
      expect(performance.now() - start).toBeLessThan(150);
    });
  }
  test("the cap applies before any pattern", () => {
    expect(classify("shell", ["x".repeat(limit + 1)])).toEqual({ tier: "high", rule: "too-long" });
    expect(classify("shell", ["x".repeat(limit)])).toEqual({ tier: "elevated", rule: "shell" });
    expect(classify("edit", ["x".repeat(limit + 1)])).toEqual({ tier: "elevated", rule: "edit-or-web" });
  });
});
