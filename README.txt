Roth Chat (RothChat) v1.1.1
Retail 12.1.0 / Interface 120100
Author: Neomorph

Roth Chat is a modular, immersive chat addon for World of Warcraft Midnight.

CORE FEATURES
- Chat windows fade away when inactive and return on interaction.
- A bounded ticker shows messages that arrive while the primary chat is hidden.
- Hover controls and ChatBar follow the active docked chat window.
- Double-click opens a selectable copy overlay.
- URLs can be converted into clickable copy links.
- Restore keeps bounded scrollback for permanent chat windows across sessions.
- Optional modules provide timestamps, colors, resizing, alerts, localized cleaner formatting and sticky chat types.

RETAIL 12.1 SAFETY
- One centralized dispatcher owns Blizzard message-event filters.
- The dispatcher preserves the complete argument tuple it receives, including nil positions.
- Unchanged messages return only `false`, leaving Blizzard's secure tuple untouched.
- Changed text replaces arg1 while preserving every remaining field.
- Chat text is checked for current accessibility before comparison, formatting, copying, animation or persistence.
- Filters are optional and stateless because Blizzard may skip callbacks for inaccessible values.

RUNTIME LIFECYCLE
- Configured module choices and successful runtime activation are tracked separately.
- Init and login notifications are one-shot; module enable/disable is idempotent.
- Core removes owner listeners, filters and AddMessage callbacks on disable.
- Dynamic chat windows receive Controls, Style, Resize, Restore and CopyOverlay lifecycle handling.
- Temporary whisper frames are excluded from permanent Restore identity.

USAGE
- Install the RothChat folder under World of Warcraft/_retail_/Interface/AddOns/.
- Enable the addon and reload the UI.
- Use /rothchat to open settings.

PERSISTENCE OWNERSHIP
Restore.lua is the active scrollback owner. History.lua is legacy and intentionally not loaded.

VALIDATION
The repository workflow parses every Lua file, validates active TOC paths and runs chat-filter, module-lifecycle, URL and Cleaner localization contracts. In-game validation is still required for combat, forced chat restrictions, whisper/reply, temporary windows, dock transitions, module toggles, reload and logout/login persistence.

See README.md, AGENT_GUIDE.md, ARCHITECTURE.md and MIGRATION_12_1.md for engineering details.
