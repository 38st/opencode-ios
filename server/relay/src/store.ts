export type SqlValue = string | number | null;
export type Statement = readonly [query: string, params: readonly SqlValue[]];

/** The SQL subset the relay needs. D1 and node:sqlite both implement it (sql-d1.ts, sql-sqlite.ts). */
export interface Sql {
  run(query: string, params?: readonly SqlValue[]): Promise<number>;
  first<T>(query: string, params?: readonly SqlValue[]): Promise<T | undefined>;
  /** Runs the statements atomically, in order. */
  batch(statements: readonly Statement[]): Promise<void>;
}

export interface Device {
  readonly id: string;
  readonly secretHash: string;
  readonly apnsToken: string | null;
  readonly env: "sandbox" | "production";
  readonly bundleID: string;
}

export interface Sender {
  readonly id: string;
  readonly deviceID: string;
}

export interface Activity {
  readonly pushToken: string;
  readonly expiresAt: number;
}

export interface AttestKey {
  readonly keyID: string;
  /** SubjectPublicKeyInfo, base64url. */
  readonly publicKey: string;
  readonly appID: string;
  readonly counter: number;
}

export const MAX_SENDERS = 32;
export const MAX_ACTIVITIES = 16;

/** Devices, senders and Live Activity tokens. Times are Unix seconds. */
export class Store {
  readonly #sql: Sql;
  constructor(sql: Sql) {
    this.#sql = sql;
  }

  async createDevice(device: Device, now: number): Promise<void> {
    await this.#sql.run(
      "INSERT INTO devices (id, secret_hash, apns_token, env, bundle_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      [device.id, device.secretHash, device.apnsToken, device.env, device.bundleID, now, now],
    );
  }

  device(id: string): Promise<Device | undefined> {
    return this.#sql.first<Device>(
      "SELECT id, secret_hash AS secretHash, apns_token AS apnsToken, env, bundle_id AS bundleID FROM devices WHERE id = ?",
      [id],
    );
  }

  async updateDeviceToken(id: string, apnsToken: string | null, env: Device["env"], now: number): Promise<void> {
    await this.#sql.run("UPDATE devices SET apns_token = ?, env = ?, updated_at = ? WHERE id = ?", [apnsToken, env, now, id]);
  }

  async deleteDevice(id: string): Promise<void> {
    await this.#sql.batch([
      ["DELETE FROM activities WHERE device_id = ?", [id]],
      ["DELETE FROM senders WHERE device_id = ?", [id]],
      ["DELETE FROM devices WHERE id = ?", [id]],
    ]);
  }

  async countSenders(deviceID: string): Promise<number> {
    return (await this.#sql.first<{ count: number }>("SELECT COUNT(*) AS count FROM senders WHERE device_id = ?", [deviceID]))?.count ?? 0;
  }

  async createSender(sender: Sender, tokenHash: string, now: number): Promise<void> {
    await this.#sql.run("INSERT INTO senders (id, device_id, token_hash, created_at) VALUES (?, ?, ?, ?)", [sender.id, sender.deviceID, tokenHash, now]);
  }

  senderByTokenHash(tokenHash: string): Promise<Sender | undefined> {
    return this.#sql.first<Sender>("SELECT id, device_id AS deviceID FROM senders WHERE token_hash = ?", [tokenHash]);
  }

  async deleteSender(deviceID: string, id: string): Promise<void> {
    await this.#sql.run("DELETE FROM senders WHERE device_id = ? AND id = ?", [deviceID, id]);
  }

  async touchSender(id: string, now: number): Promise<void> {
    await this.#sql.run("UPDATE senders SET last_used_at = ? WHERE id = ?", [now, id]);
  }

  async putActivity(deviceID: string, ref: string, activity: Activity, now: number): Promise<boolean> {
    await this.#sql.run("DELETE FROM activities WHERE device_id = ? AND expires_at <= ?", [deviceID, now]);
    const existing = await this.#sql.first<{ count: number }>(
      "SELECT COUNT(*) AS count FROM activities WHERE device_id = ? AND ref <> ?",
      [deviceID, ref],
    );
    if ((existing?.count ?? 0) >= MAX_ACTIVITIES) return false;
    await this.#sql.run(
      "INSERT INTO activities (device_id, ref, push_token, expires_at, updated_at) VALUES (?, ?, ?, ?, ?) " +
        "ON CONFLICT (device_id, ref) DO UPDATE SET push_token = excluded.push_token, expires_at = excluded.expires_at, updated_at = excluded.updated_at",
      [deviceID, ref, activity.pushToken, activity.expiresAt, now],
    );
    return true;
  }

  activity(deviceID: string, ref: string): Promise<Activity | undefined> {
    return this.#sql.first<Activity>(
      "SELECT push_token AS pushToken, expires_at AS expiresAt FROM activities WHERE device_id = ? AND ref = ?",
      [deviceID, ref],
    );
  }

  async deleteActivity(deviceID: string, ref: string): Promise<void> {
    await this.#sql.run("DELETE FROM activities WHERE device_id = ? AND ref = ?", [deviceID, ref]);
  }

  async createChallenge(challenge: string, expiresAt: number, now: number): Promise<void> {
    await this.#sql.batch([
      ["DELETE FROM attest_challenges WHERE expires_at <= ?", [now]],
      ["INSERT INTO attest_challenges (challenge, expires_at) VALUES (?, ?)", [challenge, expiresAt]],
    ]);
  }

  /** Deletes the challenge; true only if it existed and had not expired, so each one works once. */
  async consumeChallenge(challenge: string, now: number): Promise<boolean> {
    return (await this.#sql.run("DELETE FROM attest_challenges WHERE challenge = ? AND expires_at > ?", [challenge, now])) === 1;
  }

  /** False if the key ID is already stored. */
  async createAttestKey(key: AttestKey, now: number): Promise<boolean> {
    const changes = await this.#sql.run(
      "INSERT INTO attest_keys (key_id, public_key, app_id, counter, created_at) VALUES (?, ?, ?, ?, ?) ON CONFLICT (key_id) DO NOTHING",
      [key.keyID, key.publicKey, key.appID, key.counter, now],
    );
    return changes === 1;
  }

  attestKey(keyID: string): Promise<AttestKey | undefined> {
    return this.#sql.first<AttestKey>("SELECT key_id AS keyID, public_key AS publicKey, app_id AS appID, counter FROM attest_keys WHERE key_id = ?", [keyID]);
  }

  /** Stores a higher counter; false if another request already stored this one or a higher one. */
  async advanceAttestCounter(keyID: string, counter: number, now: number): Promise<boolean> {
    return (await this.#sql.run("UPDATE attest_keys SET counter = ?, used_at = ? WHERE key_id = ? AND counter < ?", [counter, now, keyID, counter])) === 1;
  }
}
