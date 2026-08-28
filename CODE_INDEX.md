# Roth Chat code index

| Area | Files | Responsibility |
|---|---|---|
| Foundation | `Util.lua`, `Core.lua` | Accessibility/restriction helpers, SavedVariables, configured/runtime module state, event bus, scheduling, owner cleanup and centralized chat dispatch |
| Presentation | `Modules/Style.lua`, `Modules/Colors.lua`, `Modules/Resize.lua` | Guarded chat-frame appearance, font/background/border styling, dynamic resize grips and combat-safe geometry |
| Interaction | `Modules/Controls.lua`, `Modules/ChatBar.lua`, `Modules/Dock.lua`, `Modules/CopyOverlay.lua`, `Modules/UrlCopy.lua` | Hover and mouse-wheel ownership, docking, channel shortcuts, copy surfaces and links |
| Runtime behavior | `Modules/Restore.lua`, `Modules/Ticker.lua`, `Modules/Timestamps.lua`, `Modules/Cleaner.lua`, `Modules/Alerts.lua`, `Modules/Sticky.lua` | Permanent-window restore, hidden-state ticker, formatting, localized cleanup, tab alerts and sticky channels |
| Options | `Options.lua` | Settings proxy values, module defaults, targeted activation and feature refresh routing |
| Chat-filter verification | `tests/core_chat_filter_spec.lua` | Complete tuple arity, `nil` preservation, no-op, transform, discard and unregister contracts |
| Lifecycle verification | `tests/core_module_lifecycle_spec.lua` | One-shot Init/Login, late activation, idempotent disable and owner cleanup |
| Transformation verification | `tests/url_copy_spec.lua`, `tests/cleaner_spec.lua` | URL punctuation/accessibility and localized Cleaner format restoration |
| CI | `.github/workflows/validate.yml` | Lua parsing, contract suite, TOC metadata and active load-path validation |
| Release evidence | `CHANGELOG.md`, `MIGRATION_12_1.md`, `TODO.md` | Version history, source baseline, unresolved runtime matrix and release gates |
| Dependencies | `ThirdParty/` | LibStub, CallbackHandler, LibSharedMedia and retained licenses |

Detailed ownership and lifecycle routing are in [`AGENT_GUIDE.md`](AGENT_GUIDE.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md).

`Modules/History.lua` remains legacy and is not part of the active TOC graph.
