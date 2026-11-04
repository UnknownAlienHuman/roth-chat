# Chat addon implementation review — refreshed 2026-11-04

## Evidence boundary

This review compares Roth Chat with four source-pinned implementations. Third-party code is donor evidence only; Blizzard source and the engineering KB remain authoritative. No Chattynator, Prat or Glass code was copied during this review.

Current pins:

- Chattynator public snapshot: `dawsze/Chattynator@2c357fe8be3f0780b85cd84b231779b6e4f08218` — unchanged since the previous audit and explicitly non-authoritative for current upstream;
- Prat 3.0: `Legacy-of-Sylvanaar/prat-3-0@9a228050b232806833a9c4c38bc65efe7121bff6` — 33 commits ahead of the previous pin;
- LS: Glass: `ls-/ls_Glass@2df600e7b3d6d9eaf8dd29128377cd45ba1d9f26` — unchanged and retired for Midnight;
- original Glass: `mixxorz/Glass@1025ff58663731283388e556fb9264b933a6bc91` — 15 commits ahead of the previous pin and now targeting Interface `120100`.

None of these pins is current Retail `12.1.5.70783` authority.

## Chattynator snapshot

### Useful architecture evidence

- structured message time/type/color/text are separate from rendered strings;
- copy output is derived from message records rather than scraped presentation;
- durable history is bounded and migration work is incremental;
- a complete custom renderer uses explicit FontString/texture pools.

### Rejected for Roth Chat

- replacing Blizzard chat globals, unregistering native frame events or suppressing native frames;
- a second renderer and processed-message cache while Roth deliberately keeps Blizzard rendering;
- per-message stack inspection;
- any source transplant from an All Rights Reserved, non-authoritative snapshot.

## Prat 3.0 current head

Prat remains a large modular Ace3 suite and still carries a maintained derivative of Blizzard message handling.

Useful evidence:

- features have independent enable/disable ownership;
- dynamic frame changes are handled explicitly;
- expensive features are optional and history counts are bounded.

Current risk confirmation:

- `addon/MessageEventHandler.lua` still forwards only `arg1` through `arg14` to `ChatFrameUtil.ProcessMessageEventFilters` at `9a228050...`;
- the copied handler now also carries Discord-specific branches and additional current-client behavior, increasing the cost of contract drift;
- edit-box command history, tell targets and direct history-buffer mutation continue to expand protected/restricted ownership;
- Prat is GPLv3 and cannot be source-transplanted into MIT Roth Chat.

Roth Chat therefore keeps one variadic adapter around Blizzard's current filters rather than copying the native handler.

## LS: Glass

The inspected source remains unchanged at `2df600e...` and targets Interface `110207`.

Useful evidence:

- one active smoother owns pending scroll work and idles its updater when empty;
- dirty-layout flags coalesce rebuilds;
- chat-frame-to-renderer attachment/release is explicit;
- a replacement renderer must disable the native renderer to avoid duplicate work.

Rejected:

- hiding Blizzard's `FontStringContainer`, replacing visible rendering, reading private history buffers and taking over the full hyperlink/selection lifecycle;
- treating retired pre-Midnight implementation details as 12.1.5 API evidence.

## Original Glass current head

The project has resumed development and now includes a separate `MessageRouter`, extra windows and an expanded renderer. It targets Interface `120100`, not the selected `120105` contract.

Useful evidence:

- message sources and renderers have explicit bind/unbind ownership;
- one native `AddMessage` hook feeds any number of subscribed views;
- temporary source replacement is modeled as an override rather than duplicated subscriptions;
- fading frames cancel previous timers/animations before starting replacement work.

Rejected or unsafe for Roth Chat:

- it is still a full custom renderer, which would duplicate Blizzard rendering responsibilities;
- `MessageRouter.createMessage` can retain an inaccessible `text` value when `canAccessValue(text)` is false instead of dropping it;
- it hooks and reads `historyBuffer` directly, including `PushBack`, which is outside Roth Chat's narrow public-adapter boundary;
- history reads and renderer state are not proof of current 12.1.5 restriction/taint safety.

The explicit source/subscriber model supports Roth Chat's existing single-dispatcher architecture, but no renderer or private-buffer code is adopted.

## Adopted Roth Chat decisions

- `CoreDispatch.lua` owns one message-filter dispatcher per event and one displayed-message post-hook per frame;
- exact tuple arity and interior/trailing `nil` values are preserved;
- timestamp metadata remains separate from durable text and copy policy;
- persistence is sanitized, bounded and restricted to permanent chat windows;
- scheduler/fade/lifecycle work is coalesced and idles when empty;
- module teardown restores only state still owned by that module;
- Blizzard keeps rendering, `HistoryKeeper`, chat sound, tab alert state and native frame capacity.

## Provenance and licenses

Four retained Roth Chat assets are exact Git-blob matches to LS: Glass and remain Apache-2.0 material:

- `Assets/border-highlight.TGA` — `ae4d9aa4dd50ea16790009c986f24275c1c6515a`;
- `Assets/border.TGA` — `8c5aada40e24c107dfbd09a99c1c9748aa2a71d3`;
- `Assets/icons.TGA` — `1206ddcedff0a8cb191dc8094a4ecdf561cca009`;
- `Assets/scroll-buttons.TGA` — `43be3a6b0a742a52f40309a64eb987a33cc13ab8`.

Two retained assets match original Glass and remain covered by its MIT notice:

- `Assets/overlayMask.tga` — `48f0f1319903cdd1d7f1db43479984a30493c55e`;
- `Assets/snapToBottomIcon.tga` — `c3397a06ee3c6635de5ecbba6927fb13a256b145`.

`ThirdParty/ATTRIBUTIONS.md`, `ThirdParty/LS_GLASS_LICENSE.txt` and `ThirdParty/GLASS_LICENSE.txt` must ship in every release archive.

## Remaining boundary

Static source comparison cannot prove in-client behavior. Live Retail validation is still required for restricted values, temporary whispers, native history coexistence, one-message/one-alert behavior, taint and performance before release.
