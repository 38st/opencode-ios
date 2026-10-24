// Shared by both test runners, their configs and the mock. No runtime-specific imports.
export const TEAM_ID = "TEAMTEST01";
export const KEY_ID = "KEYTEST001";
export const BUNDLE_ID = "com.example.opencode.tests";
/** Small limits so the suite can reach them quickly; the real ones are unit-tested in test/node. */
export const TEST_LIMITS = { alertsPerMinute: 5, alertsPerDay: 500, activityUpdatesPerMinute: 30, activityUpdatesPerDay: 3, registrationsPerHour: 6 };

export interface MockRequest {
  readonly protocol: "h1" | "h2";
  readonly path: string;
  readonly token: string;
  readonly headers: Record<string, string>;
  readonly body: unknown;
  readonly bytes: number;
  readonly jwt: string | undefined;
  readonly problems: string[];
  readonly status: number;
}
