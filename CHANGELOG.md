# Changelog

All notable Roth Chat changes are recorded here.

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
