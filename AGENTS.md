# AGENTS.md: opencode-ios

A native iPhone and iPad client for opencode V2 servers (github.com/anomalyco/opencode).

- `SPEC.md`: product decisions and scope.
- `ARCHITECTURE.md`: modules, sync engine, push, security, testing and milestones.
- `research/01-opencode-server-api.md`: the V2 protocol reference. `research/opencode-openapi.json` is the V2 OpenAPI spec.
- `research/08-feature-matrix.md`: every feature with its priority.

Read the relevant sections before changing code. If the code and the design disagree, follow the design and flag it in your final report. If the design and the opencode source disagree, follow the source and flag it.

## Roles

- Codex implements. A separate orchestrator (Claude Code) writes task briefs, reviews diffs, runs verification, and commits and pushes.
- Do not run `git commit` or `git push`, create branches, or change git config. Leave your changes in the working tree.
- Do not edit `SPEC.md`, `ARCHITECTURE.md` or anything under `research/` unless the brief asks; propose doc changes in your final report instead.
- Do not install, upgrade or reconfigure global tools (opencode, Homebrew packages, Xcode, simulators) unless the brief asks.

## Stack

- Swift 6 language mode with strict concurrency. Code must build with Xcode 27.0 and later. Minimum iOS and iPadOS 26.4.
- XcodeGen: `project.yml` is the source of truth. The generated `.xcodeproj` is not committed; run `xcodegen generate` after changing `project.yml`.
- All logic lives in the local Swift package `Packages/OpencodeKit`. The app target only wires things together.
- Module layout and dependency rules are in ARCHITECTURE.md §1.1. Extensions never link OCSync or OCNetworking, and feature targets never import OCNetworking.
- Allowed third-party dependencies, pinned to exact versions: GRDB, swift-markdown, Textual, SwiftTreeSitter, Runestone, SwiftTerm, Citadel (later), swift-snapshot-testing, swift-clocks. Ask in your final report before adding anything else.

## Code rules

- Decoding is tolerant (ARCHITECTURE.md §2.3): ignore unknown keys, treat `null` as absent, give every union an `.unknown` case, decode arrays of unions lossily, and never let an unknown or malformed event end the stream. Never force-unwrap or `try!` on server data.
- Core targets are nonisolated and `Sendable`; UI targets run on the MainActor. No detached tasks: every task is owned, and cancelled, by an actor or a store.
- Never log credentials or `Authorization` headers. Credentials live only in the Keychain.
- Tests use Swift Testing (`import Testing`) and never touch the network; use fixtures under `Fixtures/`.
- The UI follows the opencode desktop app's design language (see `docs/design.md` once it exists). Feature code uses OCDesign tokens and components only: no raw system colours, fonts or one-off styling.
- Keep files focused and small, match the surrounding style, and comment only what is not obvious.
- Never commit an absolute local path such as a home directory. Recordings write `/sandbox` for the sandbox root, `Tools/fixture-recorder/home-paths.test.mjs` fails on home paths, and example paths use `/Users/Shared`.

## Licences

- The app is GPL-3.0-only (`LICENSE`). The push plugin and relay are MIT-licensed; give each its own `LICENSE` file when you create it.
- Third-party code, assets and fonts keep their own licences. Credit each one in `THIRD_PARTY_NOTICES.md` when you bundle it.

## Commands

- Generate the project: `xcodegen generate`
- Package tests (fast, on the macOS host): `swift test --package-path Packages/OpencodeKit`
- App build: `xcodebuild -project Opencode.xcodeproj -scheme Opencode -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/DerivedData build`

The only installed simulator runtime is iOS 26.5, and the booted device is "iPhone 17 Pro". Run the package tests and the app build before you finish, and fix whatever fails.

## Final report

End every task with: the files you changed, the commands you ran and their results, anything you could not finish, and any disagreement with the docs.
