# Validation and release evidence

## Target and pinned references

| Item | Target / evidence |
|---|---|
| Retail build | `12.1.5.70688` |
| TOC interface | `120105` |
| Addon version | `1.2.0` |
| UI source snapshot | [`Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`](https://github.com/Gethe/wow-ui-source/commit/d07eb00237d8891f153215db98a5df880a26cfe5), checked 2026-11-02 |
| Engineering KB | [`UnknownAlienHuman/wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb/commit/b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83) |
| Reviewed project base | [`UnknownAlienHuman/roth-chat@3c995183626002965043e38a837346fb290acd8a`](https://github.com/UnknownAlienHuman/roth-chat/commit/3c995183626002965043e38a837346fb290acd8a) |
| Selectively reused PR5 changes | [`UnknownAlienHuman/roth-chat@40c8fd59f9fab0a6701ae1b8203f3fb2f73c768f`](https://github.com/UnknownAlienHuman/roth-chat/commit/40c8fd59f9fab0a6701ae1b8203f3fb2f73c768f) |

The pins identify the code/reference snapshots used for review; they are not evidence that the addon ran in WoW. The 12.1.5 source tree is a source contract reference and cannot prove runtime behavior by itself.

## Automated checks

Run the portable repository validator from the addon root with both supported runtimes:

```sh
python3 scripts/validate.py --lua lua5.1 --lua lua5.4
```

The validator checks TOC metadata and load ownership, parses Lua files under Lua 5.1 and 5.4, and discovers and runs every `tests/*_spec.lua` contract under both runtimes. Test discovery is automatic so newly added contract specs cannot be silently omitted. Record the exact candidate revision, command, and final result when repeating the gate.

`.github/workflows/validate.yml` exposes the same gate through a manual `workflow_dispatch` only. Automatic runs are deliberately disabled on `main`; no GitHub Actions run is claimed here. Do not describe local success as an Actions result. A focused spec run is not a full-suite result.

### Base modernization candidate — 2026-11-03

Tree `4b87f5d1d59727ee75be920799e59065e4d9b62f` passed the complete validator using the official Lua 5.1.1 source-built CLI and a host for the installed Lua 5.4.6 library. Both runtimes executed the same parser and discovered-spec checks from `scripts/validate.py`.

| Check | Result |
|---|---|
| Lua syntax | All 49 Lua files parsed on each runtime |
| Contract tests | All 22 discovered specs passed on each runtime |
| Metadata and load graph | Interface `120105`, version `1.2.0`, 27 load entries, no duplicate shared implementation owners |
| Patch whitespace | `git diff --check` passed |
| Relative documentation links | All targets resolved |

These results establish syntax and mocked-contract behavior for that exact tree only; the live-client gate below remains open.

### Third audit follow-up — 2026-11-03

The lifecycle/Restore/dispatch follow-up was checked locally with Lua 5.3.6 (`texlua`):

- modified production files and replacement specs parsed;
- focused close-generation, Restore replay/capacity/schema, and denied-hook contracts passed;
- the repository-form Restore spec passed.

The full Lua 5.1.1 + 5.4.6 validator was **NOT RUN** for this follow-up in the current environment. Do not inherit the base-tree PASS for changed files. The new regressions cover terminal close ordering, native replay capacity, valid-row selection across unknown future rows, removal of Restore frame-property ownership, and terminal denied AddMessage hooks. No client CPU/FPS improvement has been measured.

## Live-client gate

**Status: NOT RUN.** No current Retail client test is claimed. Static parsing, mocked contracts, source inspection, and Actions checks cannot establish correct behavior under in-client restrictions, taint rules, secure execution, combat, Settings, or native chat-frame reuse.

Before packaging or release, test on Retail `12.1.5.70688` and record the date, addon commit, client build, and results for:

- Fresh install, login, `/reload`, logout/login, and upgrade with existing `RothChatDB` values.
- Existing legacy `RothChatDB.history` and obsolete profile keys remain untouched; no new History table is created. During Restore v1/v2-to-v3 migration, unbound buckets are kept by reference in the bounded `RothChatDB.restore.legacyFrames.frames` snapshot, keyed only by valid permanent slots. This is a manual recovery location: those rows are intentionally never replayed, exported, or appended to live v3 buckets because their original window configuration cannot be proven.
- Restore fingerprint work is cached only for the current `core:GetChatLayoutRevision(frame)` value; verify direct group/channel mutations and window rename invalidate it before the next message, and that frame close and module disable invalidate it. Incomplete native invalidation hooks disable caching. Current identity accessibility is rechecked; no permission/restriction result is cached.
- Restore keeps its configured durable retention independently of Blizzard's live buffer, never changes `GetMaxLines()`/fade properties, and replays only the newest valid rows up to the current native capacity. Unknown row versions must be skipped without reducing the number of later valid rows selected where capacity permits.
- A frame reported active during its close callback receives `CHAT_FRAME_CLOSED` but no same-flush `CHAT_FRAME_READY`; a later native update may announce a reused frame.
- A denied per-frame `AddMessage` post-hook produces no repeated attempts or error storm during later layout/update events.
- Downgrade with an unknown newer Restore schema: verify version, buckets, and unknown fields remain unchanged while Restore history read/write/replay stays suspended.
- Enable/disable/re-enable each feature before and after login; module cleanup and late activation.
- Native chat input history (`HistoryKeeper`) coexists with Restore; whisper/reply behavior remains Blizzard-owned.
- Say, yell, emote, whisper and reply, Battle.net whisper, guild/officer, party/raid, instance, channels, system messages, and URLs/timestamps in each applicable path.
- Native timestamps on/off, Roth timestamps on/off, copy timestamps enabled/disabled, Restore copy, and native/frame copy fallbacks.
- Permanent chat-window creation, selection, docking/undocking, closing and index reuse; temporary whisper frames remain excluded from Restore.
- Chat messaging restriction entry/exit while content is visible or a replay/copy action is pending. Pending content must be discarded, popup/edit-box contents cleared, and no old content replayed after access returns.
- Combat entry/exit during Settings, style, dock, resize, and hover work; cancellation and at-most-one deferred continuation.
- Minimal, Obsidian, and Ember presets; font/size choices; module toggles and migration preservation.
- Cleaner behavior in relevant locales, Controls mouse wheel, Ticker visibility/alpha, and CopyOverlay alpha restoration.
- No repeating taint, secret-value, forbidden-operation, or Lua errors during the matrix.

Record failures and exact reproduction steps in the release evidence. Do not change the status above to passed without an actual live-client run.

## Provenance and architecture review

The pinned external implementation review is in [`../RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md`](../RESEARCH_CHAT_IMPLEMENTATIONS_2026_08_29.md). It records source quality and adoption/rejection decisions for Chattynator, Prat, original Glass, and LS: Glass. Exact distributed asset/helper provenance and license scope are maintained in [`../ThirdParty/ATTRIBUTIONS.md`](../ThirdParty/ATTRIBUTIONS.md). The research includes non-authoritative snapshots where upstream source was unavailable; do not describe those snapshots as current upstream contracts or copy their code.
