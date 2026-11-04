# Validation and release evidence

## Target and pinned references

| Item | Target |
|---|---|
| Selected Retail build | `12.1.5.70688` |
| Latest reviewed post-selected source | `12.1.5.70783` |
| TOC interface | `120105` |
| Addon version | `1.2.0` |
| Blizzard UI source | `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5` plus reviewed delta through `297d7aaaa736f346b3e036f38ee088eaf7f8c07f` |
| Engineering KB | `UnknownAlienHuman/wow-addon-engineering-kb@c2a630aa186de401262663cc8568a77988be69df` |

The post-selected delta adds Roleset, `UNIT_COMBAT` and BNet `subIcon` contracts but no direct Roth Chat API call site. Source pins establish reviewed contracts only; they do not prove in-client behavior.

## Automated gate

Run from the addon root:

```sh
python3 scripts/validate.py --lua lua5.1 --lua lua5.4
python3 scripts/package.py /tmp/RothChat-a.zip
python3 scripts/package.py /tmp/RothChat-b.zip
cmp /tmp/RothChat-a.zip /tmp/RothChat-b.zip
python3 scripts/package.py --verify /tmp/RothChat-a.zip
```

The validator checks:

- exact TOC metadata and recursive TOC/XML load graph;
- absence of unloaded first-party Lua files;
- duplicate shared implementation owners;
- syntax of every Lua file on both runtimes;
- every discovered `tests/*_spec.lua` contract on both runtimes.

The package gate:

- reuses the same authoritative TOC/XML graph;
- includes all retained assets and required attribution/license files;
- creates one `RothChat/` install root;
- excludes tests, scripts, workflows, research and agent files;
- rejects missing assets, unsafe paths, symlinks, duplicates and byte drift;
- fixes ZIP timestamps/permissions, sorts entries and compares two independently built archives;
- reports the archive SHA-256.

`.github/workflows/validate.yml` runs both gates on pull requests and pushes to `main`, and supports manual dispatch. A successful Actions run is not live-client validation.

## Recorded evidence

### Base modernization

Tree `4b87f5d1d59727ee75be920799e59065e4d9b62f` passed the complete Lua 5.1.1/Lua 5.4.6 gate: 49 Lua files, 22 specs, Interface `120105`, addon `1.2.0`, 27 load entries and unique shared owners.

### Lifecycle and Restore follow-up

Tree `a8c23e89733f1cfe47abd5d17aa184bf2256812d` received focused Lua 5.3.6/Lua 5.4 checks for close-generation ordering, terminal denied hooks, Restore schemas and native replay capacity. The exact capacity case replayed `m873..m1000` into a 128-line frame from 1000 valid rows plus one future row.

### Fade ownership and diagnostics

Tree `9533f200f269ca6f5fd1efaa8b90b28994877036` received focused Lua 5.3.6/Lua 5.4 checks for owner-aware fade replacement, Ticker alpha/mouse teardown, restriction cleanup and per-filter diagnostic isolation.

### Native Alerts and continuous validation — 2026-11-04

Tree `80ad1af55e610e2cab42110060e960c60ef8f0cc` passed twice:

- PR run `41819556174`, head `74fbd80d573d46e47f37d63ef7cf3d8a5933b2a7`;
- `main` run `41820170059`, commit `218c89cf306ea906dc0a2127245e8441e0bc3db2`.

Both reported 51 parsed Lua files and all 24 specs passing on Lua 5.1/Lua 5.4.

### KB and in-house audit — 2026-11-04

Tree `93efec74db855d1b177f576bf725e4ff2c0b679d` passed twice:

- PR run `41870467589`, head `5d8bd42c95abba3ce68bb9550cdea106bd52043a`;
- `main` run `41871376452`, commit `98a671173f6a127f04d10730989a85d7af3d8e98`.

Both reported 52 parsed Lua files and all 25 specs passing on Lua 5.1/Lua 5.4. This pass covered fail-closed table/object access, atomic snapshot copying, ordinary scheduler metadata and per-registration `AddMessage` diagnostics.

### Settings load order — 2026-11-04

The first draft was rejected by run `41871824330` for a second `InitOptions` implementation owner. The design was corrected rather than weakening validation.

Final tree `1881a5bf8c7aa19aa644f48adb69f060dc972b5b` passed twice:

- PR run `41872164146`, head `8b01a54fe80b9f3b4b5657b0d3dd5b68ae03daab`;
- `main` run `41872608705`, commit `fa853d7210947f2035933196983fef374c8df390`.

Both reported 28 load entries, 54 parsed Lua files and all 26 specs passing on Lua 5.1/Lua 5.4. `Options.lua` remains the sole settings builder; `OptionsBootstrap.lua` owns only the bounded late-load handshake.

Do not inherit a PASS from an earlier tree after any production, test, workflow or package-model change. Record the exact candidate commit, tree and workflow run before release.

## Live-client gate

**Status: NOT RUN.** Test the exact release candidate in current Retail 12.1.5 and record the actual client build, date, addon commit and result.

1. Install the generated ZIP into a clean AddOns directory; verify one `RothChat` root, assets and notices.
2. Fresh install, login, `/reload`, logout/login and upgrade with an existing `RothChatDB`.
3. Enable, disable and re-enable every feature before and after login.
4. Say, yell, emote, whisper/reply, BNet whisper, guild/officer, party/raid, instance, channels, communities/Discord and system messages.
5. Native/Roth timestamps and copy timestamps in every on/off combination; Restore and native/frame copy fallbacks.
6. Permanent window create/select/dock/undock/close/slot reuse; exclude temporary whisper frames from durable Restore.
7. Restore migration, fingerprint invalidation, future schemas, non-empty native history and replay capped by current `GetMaxLines()` without changing native capacity/fading.
8. Closed-frame terminality and denied-hook no-retry behavior.
9. Restriction entry/exit while Ticker, Restore, URL copy or CopyOverlay work is pending; pre-restriction content must never replay.
10. Combat transitions during Settings, Style, Dock, Resize, Controls, CopyOverlay and Ticker work.
11. Ticker/Controls/CopyOverlay across primary changes, dock state and non-default alpha/mouse state; later foreign writes/fades must survive teardown.
12. Alerts: one ordinary inactive-tab message requests one native flash; whispers/BNet do not duplicate sound/flash; disable preserves native state.
13. Blizzard Settings late load and repeated registration; exactly one Roth Chat category without eager loading.
14. Minimal/Obsidian/Ember, fonts/sizes, Cleaner locale behavior, URLs, sticky channels, resize reset and scrolling.
15. No repeating taint, secret-value, forbidden-operation or Lua errors.

Mocks, source inspection and Actions cannot mark this gate passed.

## Release gate

A release requires all of the following on one exact commit:

- successful Lua 5.1/Lua 5.4 workflow;
- two byte-identical deterministic package builds and a verified SHA-256;
- completed live-client matrix with no unresolved blocker;
- synchronized TOC/runtime/documentation version;
- tag and release asset matching the verified archive checksum.
