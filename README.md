# Roth Chat

Roth Chat is a modular, immersive chat UI for World of Warcraft Midnight. It combines fading chat windows, a hidden-state message ticker, dock-aware controls, channel shortcuts, copy overlays, clickable URLs, persistent scrollback and optional styling.

## Compatibility

- Retail: `12.1.0`
- Interface: `120100`
- Addon version: `1.1.1`
- SavedVariables: `RothChatDB`
- Author: Neomorph
- Verified source baseline: `12.1.0.69497` / `Gethe/wow-ui-source@027d26c3406d`

## Retail 12.1 chat safety

Roth Chat uses one centralized message-filter dispatcher rather than stacking independent Blizzard filters for every module.

- The dispatcher preserves the exact tuple it receives instead of hard-coding 14 or 19 fields.
- A no-op module filter returns only `false`, leaving Blizzard's secure tuple untouched.
- A text transformation replaces only visible `arg1` while preserving every remaining field, arity and `nil` position.
- Chat text is gated through current value accessibility before comparison, formatting, copying, animation or persistence.
- Filter callbacks are optional and stateless because Blizzard may skip addon callbacks for inaccessible values.

The verified 12.1 source discrepancy and live-client matrix are recorded in [`MIGRATION_12_1.md`](MIGRATION_12_1.md).

## Runtime lifecycle

Version `1.1.1` separates configured module enablement from actual runtime activation.

- `Init` is one-shot; `OnEnable` and `OnDisable` are idempotent activation boundaries.
- Modules enabled after `PLAYER_LOGIN` receive their one-time login lifecycle notification.
- Core removes owner listeners, message filters and `AddMessage` callbacks on disable, even when a module-specific cleanup path is incomplete.
- Controls, ChatBar, Style, Resize, Restore and CopyOverlay attach to chat frames through the shared lifecycle router.
- The ticker keeps a bounded queue and accepts only messages that arrive while its primary chat surface is hidden; messages already visible in normal chat are not replayed later.
- Restore persists permanent chat-window identities only. Reused temporary whisper frames are excluded from durable scrollback.

## Installation and usage

Copy the `RothChat` directory into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Enable the addon and reload the UI. Use `/rothchat` to open its settings.

## Main features

- Glass-like fading chat presentation and hover controls
- Configurable ticker for messages received while chat is hidden
- Dock-aware ChatBar and channel shortcuts
- Double-click copy overlay
- Clickable URL handling with a copy popup
- Bounded persistent scrollback through the `Restore` module
- Timestamp, color, cleaner, alert, resize and sticky-channel modules

`History.lua` remains intentionally disabled: `Restore.lua` is the single active persistence owner.

## Verification

The repository validation workflow performs:

- Lua syntax parsing for addon, vendored library and test files;
- a complete chat-filter tuple contract test;
- module activation, owner-cleanup and late-login lifecycle tests;
- URL transformation tests, including balanced punctuation and inaccessible values;
- Cleaner localization and restoration tests;
- TOC metadata and active load-path validation.

Automated validation does not replace the in-game smoke matrix. Combat, forced chat restrictions, whisper/reply, temporary windows, dock transitions, module toggles, reload and logout/login persistence still require current Retail runtime testing before a packaged release.

## Repository documentation

- [`AGENT_GUIDE.md`](AGENT_GUIDE.md) — engineering invariants and validation rules
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — runtime ownership and data flow
- [`CODE_INDEX.md`](CODE_INDEX.md) — subsystem map
- [`CHANGELOG.md`](CHANGELOG.md) — release history
- [`MIGRATION_12_1.md`](MIGRATION_12_1.md) — source evidence and runtime matrix
- [`TODO.md`](TODO.md) — remaining release gates only

## Dependencies and license

The addon vendors LibStub, CallbackHandler-1.0 and LibSharedMedia-3.0 under `ThirdParty/`. Their notices must remain in the repository.

Roth Chat is licensed under the [MIT License](LICENSE.md). The visual glass aesthetic and bundled Glass-derived textures retain the original MIT notice in [`ThirdParty/GLASS_LICENSE.txt`](ThirdParty/GLASS_LICENSE.txt).
