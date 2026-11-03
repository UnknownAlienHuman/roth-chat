# Changelog

All notable Roth Chat changes are recorded here.

## 1.2.0 — 2026-11-02

### Current Retail target and chat ownership

- Target Retail build `12.1.5.70688` and interface `120105`.
- Split ordinary safety/scheduling (`Util.lua`), current-client adapters (`Platform.lua`), applied decoration (`VisualPrimitives.lua`), internal listeners (`CoreListeners.lua`), filter/display dispatch (`CoreDispatch.lua`), and coalesced frame lifecycle routing (`ChatLifecycle.lua`) into explicit owners.
- Folded Controls and Style ownership helpers into their owning modules and removed their standalone files.
- Removed the legacy History module from the runtime; Restore remains the sole addon persistence owner. Existing `RothChatDB.history` data and obsolete profile keys are left untouched, with no new History table allocation.
- Bound Restore v3 buckets to permanent-window configuration, cache fingerprints by layout revision, and keep unbound v1/v2 buckets in a bounded manual-recovery snapshot instead of replaying them into a potentially different window.
- Coalesce and cancel combat-deferred layout work, restore owned Blizzard state on disable, and reuse decoration regions on re-enable.
- Bound and rate-limit diagnostics without retaining raw errors or chat content.
- Added Minimal, Obsidian, and Ember appearance presets.
- Tightened accessibility and restriction handling across filter dispatch, Restore, copy, timestamp, URL, and alert paths; restriction entry clears pending/visible copied content rather than replaying it later.
- Kept Blizzard's native chat history and message rendering as the owner; native `HistoryKeeper` is not replaced.

### Validation status

- Pinned current UI source and engineering references are recorded in `docs/VALIDATION.md`.
- Live-client validation is **NOT RUN**. The target build and source reference do not constitute a runtime pass.

### Follow-up review — 2026-11-03

- Cancel stale combat continuations in Controls, Restore, and CopyOverlay; preserve later wheel/clipping and Cleaner format changes made by other owners.
- Track only addon-started tab flashes so disabling Alerts preserves pre-existing native alerts.
- Invalidate Restore identity immediately after native subscription changes and window renames. Reject inaccessible identity data and suspend history access for unknown newer database schemas without altering their contents.
- Skip replay when the native message count cannot be established, preserving already populated chat windows.
- Replace Ticker's advancing queue indices with a fixed 100-slot ring and cap preview messages at 1,024 UTF-8 characters before the truncation marker.
- Refresh dependent Blizzard Settings controls after applying appearance, font, or size presets.
- Remove unused module status fields, listener aliases, the anonymous combat-defer entry point, and duplicate fallbacks for required shared helpers. Keep callback results on the stack and compact callback registries only after removal.
- Preserve cancellation and replacement of fade completions during the same update; gate URL options and temporary copy policy before evaluation.

## Historical audit — 2026-08-29

The selectively reused work below is incorporated and revised in 1.2.0. Its schema-v2 and validation notes describe the earlier audit snapshot.

### Structured chat text and persistence

- Added `ChatText.lua` as the shared accessibility, durable-storage, timestamp and copy-normalization boundary.
- Changed Restore to schema v2, storing timestamp metadata separately from timestamp-free durable message text.
- Prevented duplicate timestamps in Restore-backed copy output.
- Made `copyIncludeTimestamps=false` authoritative for Restore, message-buffer and rendered-font fallback sources.
- Preserved legacy schema-v1 rows through lazy normalization without destructive SavedVariables migration.
- Reconstructed replay timestamps only when the Timestamps module is currently active.
- Preserved the previous second-resolution copy/export timestamp while keeping live display timestamps at minute resolution.
- Replaced session-only account-name, BNet and censored-message handles before SavedVariables retention.

### Verification and research

- Added shared chat-text and timestamp integration contract tests.
- Expanded Restore tests for schema v2, legacy rows, durable sanitation, replay with timestamps enabled/disabled and temporary-frame exclusion.
- Added the existing Restore contract to the validation workflow.
- Added `workflow_dispatch` and temporary audit-branch validation routing for exact-head checks; automatic triggers were later disabled, leaving the workflow manual-only.
- Documented pinned Chattynator and Prat implementation traces, licensing boundaries and explicit adoption/rejection decisions.

### Gate at the time of the audit

- Rate-limited hot-path diagnostics and live Retail validation were pending in that snapshot. Version 1.2.0 implements bounded diagnostics; live Retail validation remains pending.

## 1.1.1 — 2026-08-28

### Runtime lifecycle

- Separated configured module enablement from actual runtime activation.
- Made disable/re-enable paths idempotent and added defensive owner cleanup for bus listeners, message filters and `AddMessage` callbacks.
- Ensured modules enabled after `PLAYER_LOGIN` receive their one-time login lifecycle notification.
- Prevented a profile-disabled addon from initializing or login-notifying feature modules.
- Preserved `nil` positions in combat-deferred argument lists.

### Chat safety and transformations

- Added `canaccessvalue`-compatible accessibility gating before evaluating chat text.
- Applied the accessibility boundary to filters, displayed-message hooks, copy collection, ticker playback, alerts and persistence.
- Preserved balanced closing punctuation inside URL links while leaving sentence punctuation outside.
- Kept existing Blizzard hyperlinks intact during URL transformation.
- Made timestamp filters a no-op for inaccessible values.

### Controls and presentation

- Rebuilt Controls lifecycle listeners after runtime re-enable.
- Replaced additive mouse-wheel hooking with owned scroll handling so a single wheel gesture is not processed by both Roth Chat and Blizzard.
- Rebound ChatBar hover ownership when the selected docked chat frame changes.
- Fixed Style's `FCFTab_UpdateAlpha` hook signature, guarded recursive tab positioning, removed the invalid empty-atlas call and made permanent hooks inactive when the module is disabled.
- Made Resize and Dock defer interrupted layout work safely through combat.
- Stopped active tab flashes when Alerts is disabled.

### Ticker, copy and persistence

- Bounded the ticker queue and limited it to messages received while the primary chat surface is hidden.
- Prevented visible-chat messages from being replayed after immersion hides the frame.
- Made ticker fade, hold and primary-frame ownership deterministic across cancellation, refresh and module toggles.
- Resolved CopyOverlay alpha arbitration so Controls/Ticker establish the authoritative final state after the overlay closes.
- Added Restore ownership for Blizzard fading settings and restored prior values on disable.
- Excluded reused temporary whisper frames from durable scrollback identity.
- Applied Restore and Resize behavior to chat frames created after login.

### Localization and settings

- Preserved Blizzard's localized chat format strings in Cleaner normal mode.
- Limited compact channel tags to the explicit `Shorten Channels` setting.
- Derived module reset defaults from each module definition instead of assuming every module defaults to disabled.
- Changed module checkboxes to activate or deactivate only their target module.

### Verification

- Added module lifecycle, owner-cleanup and late-login contract tests.
- Added URL punctuation, existing-hyperlink and inaccessible-value tests.
- Added Cleaner localization and restoration tests.
- Extended the validation workflow to parse all Lua and run the complete contract suite.

### Runtime status

The implementation is statically testable through the repository workflow. Current Retail live-client validation is still required for combat transitions, forced restrictions, temporary whisper windows, dynamic docking, copy/ticker alpha arbitration and persistence before packaging a release.

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
