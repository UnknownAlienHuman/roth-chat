# Roth Chat

Roth Chat is a modular World of Warcraft Retail chat interface focused on a customizable appearance, fading chat, hover controls, a hidden-state ticker, channel shortcuts, copy tools, and bounded scrollback restoration. Blizzard continues to own message formatting, routing, rendering, and native chat history.

## Current target

- Retail build: `12.1.5.70688`
- Expected interface number: `120105`
- Addon version: `1.2.0`
- SavedVariables: `RothChatDB`
- Current source snapshot checked: 2026-11-02, [`Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`](https://github.com/Gethe/wow-ui-source/commit/d07eb00237d8891f153215db98a5df880a26cfe5)
- Live-client validation: **NOT RUN**

The engineering references are pinned to [`wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/commit/b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83) and the selectively reused PR5 changes at [`40c8fd59f9fab0a6701ae1b8203f3fb2f73c768f`](https://github.com/UnknownAlienHuman/roth-chat/commit/40c8fd59f9fab0a6701ae1b8203f3fb2f73c768f), based on [`main@3c995183626002965043e38a837346fb290acd8a`](https://github.com/UnknownAlienHuman/roth-chat/commit/3c995183626002965043e38a837346fb290acd8a). These pins identify review context; they do not imply runtime validation.

## Features and settings

Settings are exposed through Blizzard's Settings interface and the `/rothchat` entry point. The current presentation presets are **Minimal**, **Obsidian**, and **Ember**, with separate font and text-size presets. Other settings control fading and hover timing, the primary ticker frame and animation, chat-bar placement, scrolling, timestamps, cleaner behavior, URL handling, copy sources, and Restore limits.

Feature modules cover dock-aware controls, chat-bar shortcuts, style and color, resizing, timestamps, localized channel cleanup, alerts, sticky channels, URL copy, copy overlays, ticker playback, and Restore. The former `History` module has been removed. Restore is the sole addon persistence owner; old `RothChatDB.history` data is left untouched and no new History store is allocated.

## Install

Extract or rename the repository root so the installed directory is named `RothChat` and contains `RothChat.toc` directly. Place that directory in `World of Warcraft/_retail_/Interface/AddOns/`, enable Roth Chat, and reload the UI. Open settings with `/rothchat`.

## Safety and architecture

Roth Chat uses one central owner for synchronous message filters and one for displayed-message observers. Filters preserve the exact tuple supplied by the client, including its arity and `nil` positions, and can change only visible text. Addon consumers receive accessible displayed text and safe colors; opaque trailing metadata is discarded. During chat messaging lockdown, Roth Chat drops content work and clears temporary copied content.

The detailed ownership map and validation procedure are in [ARCHITECTURE.md](ARCHITECTURE.md) and [docs/VALIDATION.md](docs/VALIDATION.md). The pinned review of external chat implementations and its adoption boundaries remain in [RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md](RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md).

## Licensing

Roth Chat code is licensed under the [MIT License](LICENSE.md), except for vendored dependencies and separately attributed third-party material. LS: Glass assets and marked adaptations are Apache-2.0; original Glass assets are MIT. Their exact paths, source commits, and blob hashes are listed in [ThirdParty/ATTRIBUTIONS.md](ThirdParty/ATTRIBUTIONS.md). Keep both applicable Glass licenses and all vendored library notices with distributed copies.
