# Roth Chat

Roth Chat is a modular World of Warcraft Retail chat interface with configurable styling, fading chat, hover controls, a hidden-state ticker, channel shortcuts, copy tools, and bounded scrollback restoration. Blizzard remains the owner of message routing, rendering and native chat history.

## Current target

- selected Retail build: `12.1.5.70688`;
- latest reviewed post-selected source: `12.1.5.70783`;
- interface: `120105`;
- addon version: `1.2.0`;
- SavedVariables: `RothChatDB`;
- source pins: `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`, with the delta through `297d7aaaa736f346b3e036f38ee088eaf7f8c07f` reviewed;
- engineering KB: `UnknownAlienHuman/wow-addon-engineering-kb@c2a630aa186de401262663cc8568a77988be69df`;
- live-client validation: **NOT RUN**.

The newer reviewed source adds Roleset, `UNIT_COMBAT`, and BNet title-icon contracts but no direct Roth Chat call-site migration.

## Features

Blizzard Settings and `/rothchat` expose **Minimal**, **Obsidian**, and **Ember** presentation presets, separate font/size presets, fading and hover timing, ticker behavior, chat-bar placement, scrolling, timestamps, Cleaner, URL handling, copy policy and Restore limits.

Modules cover dock-aware controls, channel shortcuts, style/color, resizing, timestamps, localized cleanup, alerts, sticky channels, URL copy, copy overlays, ticker playback and Restore. The former `History` module is removed. Restore is the sole addon persistence owner; legacy `RothChatDB.history` data is left untouched.

## Build and install

Build the deterministic install archive from the repository root:

```sh
python3 scripts/package.py
```

The default output is `dist/RothChat-1.2.0.zip`. The archive contains one `RothChat/` root, the exact recursive TOC/XML runtime graph, retained assets and required licenses/notices. Tests, scripts, workflows, research and agent files are excluded. Verify an existing archive with:

```sh
python3 scripts/package.py --verify dist/RothChat-1.2.0.zip
```

Extract `RothChat/` into `World of Warcraft/_retail_/Interface/AddOns/`, enable it, and reload the UI.

## Safety and architecture

One Core owner handles synchronous message filters and one handles displayed-message observers. Filters preserve exact tuple arity and `nil` positions and may change only visible text. Feature callbacks receive accessible displayed text and safe colors; opaque trailing metadata is discarded. Chat restriction entry drops pending content work and clears temporary copy surfaces.

See [ARCHITECTURE.md](ARCHITECTURE.md), [docs/VALIDATION.md](docs/VALIDATION.md), the [external addon review](RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md), and the [in-house addon review](RESEARCH_IN_HOUSE_ADDONS_2026_11_04.md).

## Licensing

Roth Chat code is MIT except for vendored dependencies and separately attributed material. LS: Glass assets/marked adaptations are Apache-2.0; original Glass assets are MIT. Exact paths and source hashes are in [ThirdParty/ATTRIBUTIONS.md](ThirdParty/ATTRIBUTIONS.md). Both Glass licenses and all applicable notices are included in the release package.
