-- App Attest keys the relay has verified. public_key is the key's SubjectPublicKeyInfo (base64url),
-- app_id is "<team ID>.<bundle ID>", and counter is the last accepted assertion counter.
CREATE TABLE attest_keys (
  key_id TEXT PRIMARY KEY,
  public_key TEXT NOT NULL,
  app_id TEXT NOT NULL,
  counter INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  used_at INTEGER
);

-- One-time challenges for attestations and assertions. Each is deleted when used or expired.
CREATE TABLE attest_challenges (
  challenge TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
);
CREATE INDEX attest_challenges_by_expiry ON attest_challenges (expires_at);
