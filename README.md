# Roth Chat

Roth Chat is a modular, immersive chat UI for World of Warcraft Midnight. It combines fading chat windows, a compact last-message ticker, dock-aware controls, channel shortcuts, copy overlays, clickable URLs, persistent scrollback and optional styling.

## Compatibility

- Retail: `12.1.0`
- Interface: `120100`
- Addon version: `1.1.0`
- SavedVariables: `RothChatDB`
- Author: Neomorph
- Verified source baseline: `12.1.0.69497` / `Gethe/wow-ui-source@027d26c3406d`

## Retail 12.1 chat safety

Roth Chat uses one centralized message-filter dispatcher rather than stacking independent Blizzard filters for every module.

- The dispatcher preserves the complete tuple it actually receives; it does not hard-code the old 14-argument shape.
- A no-op module filter returns only `false`, so Blizzard keeps its existing secure tuple instead of receiving an unnecessary addon-generated replacement.
- When visible text changes, Roth Chat replaces only `arg1` and returns every remaining field with the original arity and `nil` positions intact.
- Filter callbacks are optional and stateless because Blizzard may skip insecure callbacks when chat values are inaccessible.
- Updating the addon no longer force-enables modules or features that a user explicitly disabled.

The implementation notes and remaining live-client matrix are in [`MIGRATION_12_1.md`](MIGRATION_12_1.md).

## Installation and usage

Copy the `RothChat` directory into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Enable the addon and reload the UI. Use `/rothchat` to open its settings.

## Main features

- Glass-like fading chat presentation and hover controls
- Configurable ticker for the latest message
- Dock-aware ChatBar and channel shortcuts
- Double-click copy overlay
- Clickable URL handling with a copy popup
- Persistent per-window scrollback through the `Restore` module
- Timestamp, color, cleaner, alert, resize and sticky-channel modules

`History.lua` remains intentionally disabled: `Restore.lua` is the single active persistence owner.

## Verification

GitHub Actions performs:

- Lua syntax parsing for the addon, vendored libraries and tests;
- a 19-field chat-filter contract test, including interior `nil` values;
- TOC metadata checks;
- validation that every active TOC path exists.

Automated validation does not replace the in-game smoke matrix. Combat, forced chat restrictions, whisper/reply, channels, dock transitions, reload and logout/login persistence still require Retail runtime testing before a packaged release.

## Repository documentation

- [`AGENT_GUIDE.md`](AGENT_GUIDE.md) — engineering invariants and validation rules
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — runtime ownership and data flow
- [`CODE_INDEX.md`](CODE_INDEX.md) — subsystem map
- [`CHANGELOG.md`](CHANGELOG.md) — release history
- [`TODO.md`](TODO.md) — historical audit and remaining checks

## Dependencies and license

The addon vendors LibStub, CallbackHandler-1.0 and LibSharedMedia-3.0 under `ThirdParty/`. Their notices must remain in the repository.

Roth Chat is licensed under the [MIT License](LICENSE.md). The visual glass aesthetic and bundled Glass-derived textures retain the original MIT notice in [`ThirdParty/GLASS_LICENSE.txt`](ThirdParty/GLASS_LICENSE.txt).
