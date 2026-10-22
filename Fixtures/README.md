# Fixtures

`foundation/` contains synthetic JSON and identifier vectors for offline unit tests.
These are not captured server responses.

`v2/<server-version>/` contains real isolated npm-server recordings. See
[`Tools/README.md`](../Tools/README.md) for isolation, mock scripts, and commands.

```sh
node Tools/fixture-recorder/index.mjs                 # newest stable V2, resolved once
node Tools/fixture-recorder/index.mjs --version 2.0.32
node Tools/contract/index.mjs --version 2.0.32        # separate live checks
swift test --package-path Packages/OpencodeKit       # offline fixture checks
```

Each recording includes:

- `info.json` and `openapi.json`: the live server's info and OpenAPI document.
- `rest/<scenario>.json`: ordered request/response pairs. Methods, relative paths,
  headers, status and decoded bodies are retained. Credentials, pairing codes,
  cookies and tokens are redacted. `bodyFormat` distinguishes JSON, empty bodies
  (`null`), and text. V1 `/api/info` returns the HTML app shell, so its body is
  stored as a JSON string with `bodyFormat: "text"`.
- `sse/<scenario>.sse`: exact received HTTP entity bytes, including SSE framing
  and any comments. Transfer chunk framing is not part of the SSE payload.
  Neither newlines nor IDs/timestamps/paths are normalized. A secret in raw SSE
  causes recording to fail instead of rewriting bytes.
- `ws/pty.json`: handshakes and each sent/received RFC 6455 frame. `opcode`, `fin`,
  connection number, and base64 payload preserve text, binary `0x00` + JSON cursor
  markers, and close/control frames. Client masking bytes are transport-only and
  omitted; payloads are unmasked. Connection 2 resumes from a UTF-16 cursor.
- `manifest.json`: recorder/server versions, recording time, scenario/script
  SHA-256 hashes, consumed model calls, file SHA-256 hashes, and omissions. V1
  probe pairs live in the V2 suite, with their actual V1 version listed separately.

The 2.0.32 suite covers all requested a–q scenarios: text, reasoning, read/glob/
grep, allow once, rejection with feedback, shell output fetch, answered form,
child session, steer/queue, interrupt, interrupt/resume, revert stage/clear/
commit/redo, fork, compaction, 429 retry, 500 retry, terminal error, PTY, pairing,
and V1 detection. Message snapshots at the end of conversations are retained for
future projection-parity tests. Server-generated IDs, times, ports and sandbox
paths vary between recordings; scripted model content is deterministic.

`OCFoundationTests/RecordedFixtureTests.swift` enumerates recordings without
network access, checks JSONValue decoding, first-event `server.connected`, known
durable envelopes, strictly increasing sequence numbers per aggregate (gaps are
legal), REST bodies and binary PTY markers. Its SSE framing helper is test-only;
the incremental production SSE parser and projection replay belong to M1/M2.

Partial debug captures should use `--output .build/fixture-debug`; repeat
`--scenario NAME` to select several. Run the full recorder to refresh a published
version. Failed scenario diagnostics and before/after isolation comparisons are
kept under `.build/opencode-sandbox/audits/`, outside the checked-in fixtures.

The foundation identifier vectors are derived from the read-only opencode V2 source at `d0732ea`,
`packages/schema/src/identifier.ts` and the prefix declarations beside it. The
source was inspected, never run. Each vector applies `timestamp * 4096 + counter`,
optionally complements it, keeps the low six big-endian bytes, and maps the 14
input bytes through `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`
with `byte % 62`. The sequence starts with counter 1 and resets on any timestamp
change. The 36 timestamp bits wrap every 68,719,476,736 ms; decoding a full date
requires a nearby reference time. More than 4,095 IDs/ms carries into the time bits.
