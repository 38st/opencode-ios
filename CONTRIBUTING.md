# Contributing

Thanks for your interest in Opencode for iOS. Bug reports, problems with a particular opencode server version, and feature requests are all welcome as [issues](../../issues/new/choose). Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

Report security problems privately instead, as [SECURITY.md](SECURITY.md) describes.

## Issues

Before you open one, search the existing issues; a 👍 on an existing one helps more than a duplicate. For a bug, include:

- the app version and build, or the commit if you built it yourself;
- the device and its iOS or iPadOS version;
- the opencode server version (`opencode --version`) and how the app reaches it (same network, Tailscale, HTTPS or OpenTunnel);
- the steps to reproduce, what you expected and what happened instead;
- screenshots or a screen recording if the problem is visible.

Leave out server passwords, pairing links and QR codes: a pairing link signs a device in to your server.

Problems in opencode itself, rather than in this app, belong to the [opencode project](https://github.com/anomalyco/opencode/issues).

## Pull requests

Outside pull requests can't be merged yet. The app is licensed under the GPL-3.0, and its App Store build needs rights that the GPL alone does not grant, so code contributions will need a contributor licence agreement. Until one is in place, please open an issue to discuss a change instead of sending code.

## Development

[README.md](README.md) covers the requirements, building and the test commands. [Tools/README.md](Tools/README.md) covers the sandboxed opencode server, the scripted model, fixture recording, the contract checks and the UI smoke tests. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the app is put together, and [docs/design.md](docs/design.md) how it maps the opencode desktop design to native code.

Conventions the code follows:

- `project.yml` is the source of truth for the Xcode project; run `xcodegen generate` after changing it, and don't commit the generated project.
- The app target only wires things together. Logic lives in the Swift 6 modules of `Packages/OpencodeKit`, with strict concurrency.
- Wire models are hand-written and tolerant: every union has an `.unknown` case and arrays decode lossily, so a newer server can't break decoding.
- Dependencies are pinned to exact versions. Every bundled third-party file is credited in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) with its licence.
- Screens have snapshot tests in light and dark, at phone and iPad widths and at the largest text size. A change to a screen re-records its snapshots, and the new images are reviewed with the code.
- The push plugin and relay change in step with `server/contracts`. A change to the payload, envelope, digest or risk rules updates the contracts and their test vectors, which the Swift and TypeScript suites both check.
- Tests run against recorded or sandboxed opencode servers and never touch your own opencode installation, configuration or data.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:` or `chore:`, with an optional scope such as `fix(relay):`.
