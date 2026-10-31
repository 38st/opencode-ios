import { CONTRACT } from "../../contracts/src/constants.ts";
import { APPLE_APP_ATTEST_ROOT } from "./attest/apple-root.ts";
import type { AttestEnvironment } from "./attest/verify.ts";
import { parseCertificate, pemCertificates, type Certificate } from "./attest/x509.ts";

/** Everything the relay reads from its environment. Workers bindings and Node's process.env share these names. */
export interface RelayEnvironment {
  readonly APNS_TEAM_ID?: string;
  readonly APNS_KEY_ID?: string;
  /** The .p8 key from Apple (PKCS#8 PEM). A secret: `wrangler secret put APNS_PRIVATE_KEY`. */
  readonly APNS_PRIVATE_KEY?: string;
  /** Overrides for tests and the local end-to-end. Production uses Apple's hosts. */
  readonly APNS_SANDBOX_URL?: string;
  readonly APNS_PRODUCTION_URL?: string;
  /** Comma-separated app bundle IDs this relay may push to. */
  readonly ALLOWED_BUNDLE_IDS?: string;
  /** "off" (default) or "required": registration then needs an App Attest assertion. */
  readonly APP_ATTEST?: string;
  /** "production" (default; TestFlight and App Store builds) or "development" (builds signed for development). */
  readonly APP_ATTEST_ENVIRONMENT?: string;
  /** PEM roots replacing Apple's App Attest root. Refused outside test mode. */
  readonly APP_ATTEST_TEST_ROOTS?: string;
  /** "1" only in the test suites and the local end-to-end; enables RELAY_TEST_LIMITS. */
  readonly RELAY_TEST_MODE?: string;
  /** JSON overriding rate limits, for example {"alertsPerMinute":3}. Refused outside test mode. */
  readonly RELAY_TEST_LIMITS?: string;
}

export interface Limits {
  readonly alertsPerMinute: number;
  readonly alertsPerDay: number;
  readonly activityUpdatesPerMinute: number;
  readonly activityUpdatesPerDay: number;
  readonly registrationsPerHour: number;
}

export interface RelayConfig {
  readonly apns: {
    readonly teamID: string;
    readonly keyID: string;
    readonly privateKey: string;
    readonly sandboxURL: string;
    readonly productionURL: string;
  };
  readonly bundleIDs: ReadonlySet<string>;
  readonly appAttest: AppAttestConfig;
  readonly limits: Limits;
}

export interface AppAttestConfig {
  readonly mode: "off" | "required";
  readonly environment: AttestEnvironment;
  /** `<team ID>.<bundle ID>` for every allowed bundle ID. */
  readonly appIDs: readonly string[];
  readonly roots: readonly Certificate[];
}

export class ConfigError extends Error {
  override readonly name = "ConfigError";
}

const required = (value: string | undefined, name: string): string => {
  if (!value || !value.trim()) throw new ConfigError(`${name} is not set`);
  return value.trim();
};

/** Test limits must name known limits with positive integer values. */
function testLimits(env: RelayEnvironment): Partial<Limits> {
  if (!env.RELAY_TEST_LIMITS) return {};
  if (env.RELAY_TEST_MODE !== "1") throw new ConfigError("RELAY_TEST_LIMITS is only accepted with RELAY_TEST_MODE=1");
  let value: unknown;
  try {
    value = JSON.parse(env.RELAY_TEST_LIMITS);
  } catch {
    throw new ConfigError("RELAY_TEST_LIMITS is not JSON");
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new ConfigError("RELAY_TEST_LIMITS must be an object");
  for (const [name, limit] of Object.entries(value)) {
    if (!Object.hasOwn(CONTRACT.limits, name)) throw new ConfigError(`RELAY_TEST_LIMITS has an unknown limit: ${name}`);
    if (typeof limit !== "number" || !Number.isSafeInteger(limit) || limit < 1) throw new ConfigError(`RELAY_TEST_LIMITS.${name} must be a positive integer`);
  }
  return value as Partial<Limits>;
}

function appAttest(env: RelayEnvironment, teamID: string, bundleIDs: ReadonlySet<string>): AppAttestConfig {
  const mode = env.APP_ATTEST?.trim() || "off";
  if (mode !== "off" && mode !== "required") throw new ConfigError("APP_ATTEST must be off or required");
  const environment = env.APP_ATTEST_ENVIRONMENT?.trim() || "production";
  if (environment !== "production" && environment !== "development") throw new ConfigError("APP_ATTEST_ENVIRONMENT must be production or development");
  if (env.APP_ATTEST_TEST_ROOTS && env.RELAY_TEST_MODE !== "1") throw new ConfigError("APP_ATTEST_TEST_ROOTS is only accepted with RELAY_TEST_MODE=1");
  let roots: Certificate[];
  try {
    roots = pemCertificates(env.APP_ATTEST_TEST_ROOTS || APPLE_APP_ATTEST_ROOT).map(parseCertificate);
  } catch {
    throw new ConfigError("APP_ATTEST_TEST_ROOTS is not a PEM certificate");
  }
  if (!roots.length) throw new ConfigError("APP_ATTEST_TEST_ROOTS is not a PEM certificate");
  return { mode, environment, appIDs: [...bundleIDs].map((bundle) => `${teamID}.${bundle}`), roots };
}

export function readConfig(env: RelayEnvironment): RelayConfig {
  const overrides = testLimits(env);
  const teamID = required(env.APNS_TEAM_ID, "APNS_TEAM_ID");
  const bundleIDs = new Set((env.ALLOWED_BUNDLE_IDS ?? "").split(",").map((item) => item.trim()).filter(Boolean));
  return {
    apns: {
      teamID,
      keyID: required(env.APNS_KEY_ID, "APNS_KEY_ID"),
      privateKey: required(env.APNS_PRIVATE_KEY, "APNS_PRIVATE_KEY"),
      sandboxURL: (env.APNS_SANDBOX_URL?.trim() || CONTRACT.apns.hosts.sandbox).replace(/\/+$/, ""),
      productionURL: (env.APNS_PRODUCTION_URL?.trim() || CONTRACT.apns.hosts.production).replace(/\/+$/, ""),
    },
    bundleIDs,
    appAttest: appAttest(env, teamID, bundleIDs),
    limits: { ...CONTRACT.limits, ...overrides },
  };
}
