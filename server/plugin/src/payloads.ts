import { classify, formDigest, permissionDigest, type Tier } from "../contracts/src/index.ts";

/** A permission request as `permission.asked` carries it (schema Permission.Request). */
export interface PermissionRequest {
  readonly id: string;
  readonly sessionID: string;
  readonly action: string;
  readonly resources: readonly string[];
  readonly save?: readonly string[];
}

interface FormField {
  readonly key: string;
  readonly type: string;
  readonly title?: string;
  readonly description?: string;
  readonly custom?: boolean;
  readonly options?: readonly { readonly value: string; readonly label: string }[];
}

/** A form as `form.created` carries it (schema Form.Info). */
export interface Form {
  readonly id: string;
  readonly sessionID: string;
  readonly title: string;
  readonly fields: readonly FormField[];
}

const strings = (value: unknown): value is string[] => Array.isArray(value) && value.every((item) => typeof item === "string");
const object = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);

export function parsePermission(value: unknown): PermissionRequest | undefined {
  if (!object(value)) return undefined;
  const { id, sessionID, action, resources, save } = value;
  if (typeof id !== "string" || typeof sessionID !== "string" || typeof action !== "string" || !strings(resources)) return undefined;
  if (save !== undefined && save !== null && !strings(save)) return undefined;
  return { ...(value as object), id, sessionID, action, resources, ...(strings(save) ? { save } : {}) } as PermissionRequest;
}

export function parseForm(value: unknown): Form | undefined {
  const form = object(value) ? value.form : undefined;
  if (!object(form)) return undefined;
  const { id, sessionID, title, fields } = form;
  if (typeof id !== "string" || typeof sessionID !== "string" || typeof title !== "string" || !Array.isArray(fields) || !fields.length) return undefined;
  if (!fields.every((field) => object(field) && typeof field.key === "string" && typeof field.type === "string")) return undefined;
  return form as unknown as Form;
}

export interface RequestDetails {
  readonly action?: string;
  readonly summary?: string;
  readonly options?: readonly string[];
  readonly risk?: Tier;
  readonly digest: string;
  readonly freeText?: boolean;
}

/** The summary is what the request is about: the commands, paths or URLs, one per line. */
export async function permissionDetails(request: PermissionRequest): Promise<RequestDetails> {
  return {
    action: request.action,
    summary: request.resources.join("\n"),
    risk: classify(request.action, request.resources).tier,
    digest: await permissionDigest(request),
  };
}

/**
 * The summary is the first field's question (its description, else its title, else the form's
 * title), and the options are that field's labels. `freeText` marks a form with one string field
 * that accepts typed text, which a notification can answer inline.
 */
export async function formDetails(form: Form): Promise<RequestDetails> {
  const [first] = form.fields;
  const summary = first?.description || first?.title || form.title;
  const options = first?.options?.map((option) => option.label).filter((label): label is string => typeof label === "string");
  return {
    summary,
    ...(options?.length ? { options } : {}),
    digest: await formDigest(form),
    freeText: form.fields.length === 1 && first?.type === "string" && (!first.options?.length || first.custom === true),
  };
}

/** The error message of `session.execution.failed` (schema Session.StructuredError). */
export function failureSummary(data: unknown): string | undefined {
  const error = object(data) ? data.error : undefined;
  if (!object(error)) return undefined;
  if (typeof error.message === "string" && error.message) return error.message;
  return typeof error.type === "string" ? error.type : undefined;
}
