import { canonicalize } from "./jcs.ts";
import { hex, sha256, utf8 } from "./text.ts";

/** The fields of a permission request the digest covers (README, "Digest"). */
export interface PermissionDigestInput {
  readonly requestID: string;
  readonly sessionID: string;
  readonly action: string;
  readonly resources: readonly string[];
  readonly save: readonly string[];
}

/** The fields of a form (question) the digest covers (README, "Digest"). */
export interface FormDigestInput {
  readonly formID: string;
  readonly sessionID: string;
  readonly title: string;
  readonly fields: readonly {
    readonly key: string;
    readonly type: string;
    readonly title: string;
    readonly description: string;
    readonly options: readonly { readonly value: string; readonly label: string }[];
  }[];
}

const record = (value: unknown, name: string): Record<string, unknown> => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new TypeError(`${name} must be an object`);
  return value as Record<string, unknown>;
};
const text = (value: unknown, name: string): string => {
  if (typeof value !== "string") throw new TypeError(`${name} must be a string`);
  return value;
};
const optionalText = (value: unknown, name: string): string => (value === undefined || value === null ? "" : text(value, name));
const texts = (value: unknown, name: string): string[] => {
  if (!Array.isArray(value)) throw new TypeError(`${name} must be an array`);
  return value.map((item, index) => text(item, `${name}[${index}]`));
};

/** Projects a `Permission.Request` as the server sends it. An absent `save` is an empty array. */
export function permissionDigestInput(request: unknown): PermissionDigestInput {
  const value = record(request, "request");
  return {
    requestID: text(value.id, "id"),
    sessionID: text(value.sessionID, "sessionID"),
    action: text(value.action, "action"),
    resources: texts(value.resources, "resources"),
    save: value.save === undefined || value.save === null ? [] : texts(value.save, "save"),
  };
}

/** Projects a `Form.Info` (or `Form.Detail`) as the server sends it. */
export function formDigestInput(form: unknown): FormDigestInput {
  const value = record(form, "form");
  if (!Array.isArray(value.fields)) throw new TypeError("fields must be an array");
  return {
    formID: text(value.id, "id"),
    sessionID: text(value.sessionID, "sessionID"),
    title: text(value.title, "title"),
    fields: value.fields.map((item, index) => {
      const field = record(item, `fields[${index}]`);
      const options = field.options === undefined || field.options === null ? [] : field.options;
      if (!Array.isArray(options)) throw new TypeError(`fields[${index}].options must be an array`);
      return {
        key: text(field.key, `fields[${index}].key`),
        type: text(field.type, `fields[${index}].type`),
        title: optionalText(field.title, `fields[${index}].title`),
        description: optionalText(field.description, `fields[${index}].description`),
        options: options.map((option, position) => {
          const entry = record(option, `fields[${index}].options[${position}]`);
          return { value: text(entry.value, "option value"), label: text(entry.label, "option label") };
        }),
      };
    }),
  };
}

/** Lowercase hex SHA-256 of the UTF-8 RFC 8785 canonical form. */
export const digestOf = async (input: PermissionDigestInput | FormDigestInput): Promise<string> =>
  hex(await sha256(utf8(canonicalize(input))));

export const permissionDigest = (request: unknown): Promise<string> => digestOf(permissionDigestInput(request));
export const formDigest = (form: unknown): Promise<string> => digestOf(formDigestInput(form));
