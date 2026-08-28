# Roth Chat code index

| Area | Files | Responsibility |
|---|---|---|
| Foundation | `Util.lua`, `Core.lua` | Namespace, SavedVariables, module lifecycle, event bus, scheduling, safe calls and centralized chat dispatch |
| Presentation | `Modules/Style.lua`, `Modules/Colors.lua`, `Modules/Resize.lua` | Chat-frame appearance and geometry |
| Interaction | `Modules/Controls.lua`, `Modules/ChatBar.lua`, `Modules/Dock.lua`, `Modules/CopyOverlay.lua`, `Modules/UrlCopy.lua` | Controls, docking, copying and links |
| Runtime behavior | `Modules/Restore.lua`, `Modules/Ticker.lua`, `Modules/Timestamps.lua`, `Modules/Cleaner.lua`, `Modules/Alerts.lua`, `Modules/Sticky.lua` | Restore, ticker, formatting and alerts |
| Options | `Options.lua` | Settings panel and module refresh routing |
| Verification | `tests/core_chat_filter_spec.lua`, `.github/workflows/validate.yml` | Lua parsing, TOC validation and complete chat-filter tuple contract |
| Release evidence | `CHANGELOG.md`, `MIGRATION_12_1.md` | Version history, source baseline, known uncertainty and runtime gates |
| Dependencies | `ThirdParty/` | LibStub, CallbackHandler, LibSharedMedia and retained licenses |

Detailed load/event/state routing is in [`AGENT_GUIDE.md`](AGENT_GUIDE.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md).

`Modules/History.lua` remains legacy and is not part of the active TOC graph.
