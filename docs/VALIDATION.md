# Validation and release evidence

## Target and pinned references

| Item | Target |
|---|---|
| Retail build | `12.1.5.70688` |
| TOC interface | `120105` |
| Addon version | `1.2.0` |
| Blizzard UI source | `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5` |
| Engineering KB | `UnknownAlienHuman/wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83` |

Source pins establish reviewed contracts only. They do not prove runtime behavior in World of Warcraft.

## Automated gate

Run from the addon root:

```sh
python3 scripts/validate.py --lua lua5.1 --lua lua5.4
```

The validator checks:

- TOC metadata and every declared load path;
- absence of unloaded first-party Lua files;
- duplicate shared implementation owners;
- syntax of every Lua file on both runtimes;
- every discovered `tests/*_spec.lua` contract on both runtimes.

`.github/workflows/validate.yml` runs this command on pull requests and pushes to `main`, and also supports manual dispatch. A successful focused test is not a whole-suite pass. A successful Actions run is not live-client validation.

## Recorded evidence

### Base modernization tree

Tree `4b87f5d1d59727ee75be920799e59065e4d9b62f` passed the complete validator on Lua 5.1.1 and Lua 5.4.6: 49 Lua files, 22 discovered specs, Interface `120105`, addon `1.2.0`, 27 load entries, unique shared owners, clean whitespace and resolved relative documentation links.

### Lifecycle and Restore follow-up

Tree `a8c23e89733f1cfe47abd5d17aa184bf2256812d` received focused Lua 5.3.6 and Lua 5.4 checks for close-generation ordering, denied `AddMessage` hook terminality, Restore row/schema handling and native replay capacity. The exact capacity case retained 1000 valid rows plus one unknown future row, replayed `m873..m1000` into a 128-line frame, and exported the newest five valid rows. The complete Lua 5.1/5.4 gate was not run for that follow-up before merge.

### Ownership and diagnostics follow-up

Tree `9533f200f269ca6f5fd1efaa8b90b28994877036` received focused Lua 5.3.6 and Lua 5.4 checks for owner-aware fade replacement, conflict-safe Ticker alpha/mouse teardown, restriction cleanup, per-filter diagnostic isolation and suppression counts. The complete Lua 5.1/5.4 gate was not run for that follow-up before merge.

### Native Alerts and continuous-validation pass — 2026-11-04

Tree `80ad1af55e610e2cab42110060e960c60ef8f0cc` passed the complete automated gate twice:

- pull-request run `41819556174` for head `74fbd80d573d46e47f37d63ef7cf3d8a5933b2a7`;
- `main` push run `41820170059` for commit `218c89cf306ea906dc0a2127245e8441e0bc3db2`.

Both runs reported addon `1.2.0`, Interface `120105`, 27 load entries, unique shared owners, 51 parsed Lua files and all 24 discovered contract specs passing on both Lua 5.1 and Lua 5.4. The tree identities are equal; the merge endpoint failure did not change the reviewed content.

### KB and in-house cross-repository pass — 2026-11-04

The task-relevant engineering KB routes and current in-house donor implementations were reviewed before changing code. Exact pins and adoption/rejection decisions are recorded in [the in-house addon review](../RESEARCH_IN_HOUSE_ADDONS_2026_11_04.md).

Tree `93efec74db855d1b177f576bf725e4ff2c0b679d` passed the complete automated gate twice:

- pull-request run `41870467589` for head `5d8bd42c95abba3ce68bb9550cdea106bd52043a`;
- `main` push run `41871376452` for merge commit `98a671173f6a127f04d10730989a85d7af3d8e98`.

Both runs reported addon `1.2.0`, Interface `120105`, 27 load entries, unique shared owners, 52 parsed Lua files and all 25 discovered contract specs passing on both Lua 5.1 and Lua 5.4.

This pass covered fail-closed table/object access, atomic snapshot copying, ordinary scheduler identity, inaccessible chat-frame rejection, and per-registration `AddMessage` observer diagnostics. Raw callback errors and chat content remain outside retained diagnostics.

### Settings load-order pass — 2026-11-04

The first draft was correctly rejected by run `41871824330` because it introduced a second `InitOptions` implementation owner. The implementation was then changed rather than weakening the ownership validator.

Final tree `1881a5bf8c7aa19aa644f48adb69f060dc972b5b` passed the complete automated gate twice:

- pull-request run `41872164146` for head `8b01a54fe80b9f3b4b5657b0d3dd5b68ae03daab`;
- `main` push run `41872608705` for merge commit `fa853d7210947f2035933196983fef374c8df390`.

Both successful runs reported addon `1.2.0`, Interface `120105`, 28 load entries, unique shared owners, 54 parsed Lua files and all 26 discovered contract specs passing on both Lua 5.1 and Lua 5.4.

`Options.lua` remains the sole category/control owner. `OptionsBootstrap.lua` owns only a bounded late-load handshake for `Blizzard_Settings`; it prefers `EventUtil.ContinueOnAddOnLoaded`, retires its fallback `ADDON_LOADED` listener after registration, and does not force Settings to load during normal login.

Do not inherit a PASS from an earlier tree after production or test files change. Record the exact candidate commit and workflow run before release.

## Live-client gate

**Status: NOT RUN.** No current Retail client pass is claimed.

Test the exact release candidate on Retail `12.1.5.70688` and record date, addon commit, client build and result for:

1. Fresh install, login, `/reload`, logout/login and upgrade with an existing `RothChatDB`.
2. Enable, disable and re-enable every feature before and after login.
3. Say, yell, emote, whisper/reply, Battle.net whisper, guild/officer, party/raid, instance, channels, communities/Discord and system messages.
4. Native timestamps on/off, Roth timestamps on/off, copy timestamps on/off, Restore copy and native/frame copy fallback.
5. Permanent window creation, selection, dock/undock, close and slot reuse; temporary whisper frames must remain excluded from durable Restore.
6. Restore migration, fingerprint invalidation, unknown newer database/row versions, non-empty native history and replay capped by current `GetMaxLines()` without changing native capacity or fade properties.
7. A closed frame receives no same-flush READY; a denied `AddMessage` hook is not retried during later layout updates.
8. Chat restriction entry/exit while Ticker, Restore replay, URL copy or CopyOverlay content is pending. Pre-restriction content must be discarded and never replayed after access returns.
9. Combat entry/exit during Settings, Style, Dock, Resize, Controls, CopyOverlay and Ticker transitions; at most one current deferred continuation per owner/action.
10. Ticker with Controls and CopyOverlay across primary-frame changes, dock/undock and non-default pre-existing alpha/mouse state. Later foreign changes and replacement fades must survive Ticker teardown.
11. Alerts on inactive docked tabs: ordinary messages request one native flash; whisper and Battle.net whisper do not receive a duplicate flash or sound; disabling Alerts leaves Blizzard-owned flash state intact.
12. Blizzard Settings loading after login and repeated category registration attempts; exactly one Roth Chat category appears without forcing Settings during normal login.
13. Minimal, Obsidian and Ember presets; font/size choices; Cleaner locale behavior; URL handling; sticky channels; resize reset and scroll behavior.
14. No repeating taint, secret-value, forbidden-operation or Lua errors.

Record failures with exact reproduction steps. Do not mark this gate passed from source inspection, mocks or Actions.

## Release gate

A release requires all of the following on one exact commit:

- successful Lua 5.1 and Lua 5.4 workflow run;
- completed live-client matrix with no unresolved blocker;
- synchronized TOC/runtime/documentation version;
- clean package containing one `RothChat` root, required assets and all applicable licenses/notices;
- release archive checksum recorded with the tag.
