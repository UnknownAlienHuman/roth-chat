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
12. Minimal, Obsidian and Ember presets; font/size choices; Cleaner locale behavior; URL handling; sticky channels; resize reset and scroll behavior.
13. No repeating taint, secret-value, forbidden-operation or Lua errors.

Record failures with exact reproduction steps. Do not mark this gate passed from source inspection, mocks or Actions.

## Release gate

A release requires all of the following on one exact commit:

- successful Lua 5.1 and Lua 5.4 workflow run;
- completed live-client matrix with no unresolved blocker;
- synchronized TOC/runtime/documentation version;
- clean package containing one `RothChat` root, required assets and all applicable licenses/notices;
- release archive checksum recorded with the tag.
