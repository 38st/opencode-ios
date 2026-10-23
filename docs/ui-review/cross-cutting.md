# UI review: Cross-cutting

Part of the [UI review](README.md). 0 bugs and 1 improvement, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F25-13](#f25-13) | P3 improvement | Fallback push alert text is hard-coded English in the relay contract instead of a loc-key |

<a id="f25-13"></a>

## F25-13: Fallback push alert text is hard-coded English in the relay contract instead of a loc-key

*P3 improvement · localization · effort S · found by l10n-text*

- Where: `server/contracts/constants.json:45`, `server/relay/src/apns/request.ts:32`, `server/contracts/src/constants.ts:22`
- Evidence: `constants.json kinds.*.alert: "opencode needs your approval", "opencode has a question", "A session finished", "A session failed", "Answered on another device", "Test notification from opencode"`; `request.ts:32 alert: { body: policy.alert }`; `ARCHITECTURE.md:565 “The relay sends APNs a generic alert carrying the ciphertext.”`
- What happens: After M5b ships, iOS shows the relay’s body verbatim, always in English, whenever the Notification Service Extension cannot open the envelope: when it runs out of time, when keys are unavailable before first unlock, or when decryption fails.
- Why it matters: Once the relay is deployed, localizing these lock-screen alerts requires a relay redeploy coordinated with app releases. It is cheap to change now, before the relay goes live.
- Fix: Send aps.alert loc-key values (for example PUSH_FALLBACK_PERMISSION) instead of body, and ship those keys with English base text in the app target’s catalog in M5b. Keep the English sentences in constants.json as documentation only.
