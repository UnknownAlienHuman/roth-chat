# Roth Chat code index

| Area | Files | Responsibility |
|---|---|---|
| Foundation | `Util.lua`, `Core.lua` | Namespace, SavedVariables, access gates, event bus, shared scheduling, module lifecycle, 19-field filter dispatch, and post-render `AddMessage` dispatch |
| Presentation | `Modules/Style.lua`, `Modules/Colors.lua`, `Modules/Resize.lua` | Chat-frame appearance, edit-box styling, geometry, and resize behavior |
| Interaction | `Modules/Controls.lua`, `Modules/ChatBar.lua`, `Modules/Dock.lua`, `Modules/CopyOverlay.lua`, `Modules/UrlCopy.lua` | Hover/scroll controls, dock lifecycle, channel shortcuts, copying, and links |
| Runtime behavior | `Modules/Restore.lua`, `Modules/Ticker.lua`, `Modules/Timestamps.lua`, `Modules/Cleaner.lua`, `Modules/Alerts.lua`, `Modules/Sticky.lua` | Access-normalized scrollback, ticker, visible-text formatting, alerts, and sticky channel behavior |
| Legacy, not loaded | `Modules/History.lua` | Historical raw-event persistence path; intentionally disabled in the TOC |
| Options | `Options.lua` | Blizzard Settings categories and targeted module refreshes |
| Dependencies | `ThirdParty/` | Vendored LibStub, CallbackHandler, and LibSharedMedia |
| Validation | `.github/workflows/lua-syntax.yml`, `TODO.md` | Lua 5.1 syntax gate and current live-client release matrix |

Detailed load, security, state, and verification rules are in [`AGENT_GUIDE.md`](AGENT_GUIDE.md). The system boundary is summarized in [`ARCHITECTURE.md`](ARCHITECTURE.md).
