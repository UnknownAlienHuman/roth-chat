# Roth Chat code index

| Area | Files | Responsibility |
|---|---|---|
| Foundation | `Util.lua`, `Core.lua` | Namespace, event bus, scheduling and safe calls |
| Presentation | `Modules/Style.lua`, `Modules/Colors.lua`, `Modules/Resize.lua` | Chat frame appearance and geometry |
| Interaction | `Modules/Controls.lua`, `Modules/ChatBar.lua`, `Modules/Dock.lua`, `Modules/CopyOverlay.lua`, `Modules/UrlCopy.lua` | Controls, docking, copying and links |
| Runtime behavior | `Modules/Restore.lua`, `Modules/Ticker.lua`, `Modules/Timestamps.lua`, `Modules/Cleaner.lua`, `Modules/Alerts.lua`, `Modules/Sticky.lua` | Restore, ticker, formatting and alerts |
| Options | `Modules/Options.lua` | Settings panel |
| Dependencies | `ThirdParty/` | LibStub, CallbackHandler and LibSharedMedia |
