# Changelog

All notable Roth Chat changes are recorded here.

## 1.1.0 — 2026-08-27

### Retail 12.1 compatibility

- Updated the TOC to Interface `120100`.
- Updated addon metadata to author `Neomorph` and version `1.1.0`.
- Replaced the fixed 14-argument message-filter dispatcher with an arity-preserving vararg adapter.
- Preserved interior and trailing `nil` values in transformed chat payloads.
- Changed no-op filter handling to return only `false`, leaving Blizzard's current secure tuple untouched.
- Kept module-level transformations limited to visible `arg1` while preserving every remaining field when a replacement is required.

### SavedVariables

- Stopped version upgrades from force-enabling modules or features that users explicitly disabled.
- Retained one-time initialization for missing legacy fields and the disabled History module default.

### Verification and documentation

- Added a standalone 19-field dispatcher contract test.
- Added GitHub Actions validation for Lua syntax, TOC metadata and active load paths.
- Updated README, architecture, code index and engineering guidance for Retail 12.1.
- Added a migration record and explicit live-client smoke matrix.

### Runtime status

Automated static checks are provided by CI. In-game Retail validation remains required for restricted chat, combat, whisper/reply, channels, chat-frame lifecycle and persistence before packaging a release.

## 1.0.1

Published baseline containing the modular core, Restore persistence, consolidated chat hooks, modern Settings panel and prior chat-taint fixes.
