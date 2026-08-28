Roth Chat (RothChat) v1.1.0
Retail 12.1.0 / Interface 120100
Author: Neomorph

Roth Chat is a modular, immersive chat addon for World of Warcraft Midnight.

CORE FEATURES
- Chat windows fade away when inactive and return on interaction.
- A compact ticker can keep the latest message visible.
- Hover controls and the ChatBar follow the active docked chat window.
- Double-click opens a selectable copy overlay.
- URLs can be converted into clickable copy links.
- Restore keeps bounded scrollback for each chat window across sessions.
- Optional modules provide timestamps, colors, resizing, alerts, cleaner formatting and sticky chat types.

RETAIL 12.1 SAFETY
- One centralized dispatcher owns Blizzard message-event filters.
- The dispatcher preserves the complete argument tuple it receives, including nil positions.
- Unchanged messages return only `false`, leaving Blizzard's secure tuple untouched.
- Changed text replaces arg1 while preserving all remaining fields.
- Filters are optional and stateless because Blizzard may skip callbacks for inaccessible values.
- Version upgrades preserve explicit user feature and module choices.

USAGE
- Install the RothChat folder under World of Warcraft/_retail_/Interface/AddOns/.
- Enable the addon and reload the UI.
- Use /rothchat to open settings.

PERSISTENCE OWNERSHIP
Restore.lua is the active scrollback owner. History.lua is legacy and intentionally not loaded.

VALIDATION
The repository CI parses every Lua file, validates active TOC paths and runs the 19-field dispatcher contract test. In-game validation is still required for combat, forced chat restrictions, whisper/reply, channels, dock transitions, reload and logout/login persistence.

See README.md, AGENT_GUIDE.md, ARCHITECTURE.md and MIGRATION_12_1.md for engineering details.
