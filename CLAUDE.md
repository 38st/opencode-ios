# CLAUDE.md: opencode-ios

## Implementation goes through Codex

On 2026-10-16 the user asked for all implementation to be done with the Codex CLI from now on.

- Claude plans the work, writes each task brief, runs Codex, reviews the diff, runs the verification commands, and commits and pushes. The global git rules apply: work on `main`, push after each unit of work, and add no attribution.
- Claude does not write app code itself. When a review finds problems, send them back to Codex with `codex exec resume --last "<what to fix>"` instead of fixing them by hand.
- Run Codex non-interactively from the repo root: `codex exec -C ~/dev/opencode-ios -o <scratch>/codex-last.md "<brief>"`. The user's `~/.codex/config.toml` sets the model, reasoning effort, sandbox (`danger-full-access`) and approvals (`never`); do not override them without asking.
- Run long Codex tasks in the background, and review only after Codex finishes.
- Codex reads `AGENTS.md` for the repo rules. Keep `AGENTS.md` and this file in sync when the workflow changes.

## Temporary exception (2026-10-21)

Codex is out of usage until 2026-10-27 21:11. The user told Claude (Opus 5.5) to implement directly until then. Claude follows AGENTS.md exactly as Codex would, keeps the same verification gates (swift test, Node tests, contract, ui-smoke, app build, CI on Xcode 27.0 and 27.1), and commits and pushes each verified unit. Switch back to Codex when it is available again, unless the user says otherwise.

## Project docs

- `SPEC.md`: product decisions.
- `ARCHITECTURE.md`: design and milestones.
- `research/`: the protocol reference, the feature matrix, and the competitor and stack research. Each report ends with a verification table.
