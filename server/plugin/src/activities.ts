/** Coarse Live Activity state (server/contracts/schema/activity-state.schema.json). */
export type Phase = "running" | "needsInput" | "retrying" | "succeeded" | "failed" | "interrupted";
export type ToolGlyph = "none" | "read" | "edit" | "shell" | "search" | "web" | "agent" | "question" | "other";

/** Maps a tool name to the glyph category the activity shows. MCP and plugin tools are "other". */
export function glyphFor(tool: string): ToolGlyph {
  switch (tool) {
    case "read":
      return "read";
    case "glob":
    case "grep":
    case "list":
      return "search";
    case "edit":
    case "write":
    case "patch":
    case "apply_patch":
      return "edit";
    case "shell":
    case "bash":
      return "shell";
    case "webfetch":
    case "websearch":
      return "web";
    case "subagent":
    case "task":
      return "agent";
    case "question":
      return "question";
    default:
      return "other";
  }
}

/**
 * What an execution event does to the activity of its session's root. Needs-input is not here:
 * it follows the request's grace period, and the reply that clears it is sent at once (service.ts).
 * The service applies `phase`, `started` and `end` only for the root's own events; a subagent's
 * events count as progress of the root's run and change only the step and the glyph.
 */
export type ActivityChange =
  | { readonly kind: "progress"; readonly phase?: Phase; readonly step?: boolean; readonly glyph?: ToolGlyph; readonly started?: boolean }
  | { readonly kind: "end"; readonly phase: "succeeded" | "failed" | "interrupted" };

export function activityChange(type: string, data: Record<string, unknown>): ActivityChange | undefined {
  switch (type) {
    case "session.execution.started":
      return { kind: "progress", phase: "running", started: true };
    case "session.step.started":
      return { kind: "progress", phase: "running", step: true };
    case "session.tool.input.started":
      return { kind: "progress", glyph: typeof data.name === "string" ? glyphFor(data.name) : "other" };
    case "session.retry.scheduled":
      return { kind: "progress", phase: "retrying" };
    case "session.execution.succeeded":
      return { kind: "end", phase: "succeeded" };
    case "session.execution.failed":
      return { kind: "end", phase: "failed" };
    case "session.execution.interrupted":
    case "session.deleted":
      return { kind: "end", phase: "interrupted" };
    default:
      return undefined;
  }
}
