-- Devices registered by the app. The device secret is stored only as its SHA-256 hash.
-- apns_token is NULL after APNs reports the token gone, until the app sends a new one.
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  apns_token TEXT,
  env TEXT NOT NULL CHECK (env IN ('sandbox', 'production')),
  bundle_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- One sender per paired server. The send token is stored only as its SHA-256 hash.
CREATE TABLE senders (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER
);
CREATE INDEX senders_by_device ON senders (device_id);

-- Live Activity push tokens.
CREATE TABLE activities (
  device_id TEXT NOT NULL,
  ref TEXT NOT NULL,
  push_token TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, ref)
);
