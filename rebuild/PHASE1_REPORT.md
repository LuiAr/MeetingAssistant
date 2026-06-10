# Phase 1 acceptance report

Date: 2026-06-10. Tested on the user's Mac (arm64) from the staged, ad-hoc co-signed bundle
built by `scripts/build_and_run.sh`.

## Verdict

Phase 1 passes. The central question of the spike is answered: macOS attributes both privacy
permissions to the outer app, not the sidecar, so the embedded bare-binary sidecar approach
holds. No nested `LSUIElement` helper `.app` is needed.

## Results against the checklist

### 1. TCC attribution (key result)

System Settings, Privacy and Security lists **MeetingAssistant Rebuild** (the app) under both
Microphone and Screen Recording. The sidecar (`meetingcore-sidecar`) does not appear. The
permission prompt and the grant both key off the outer app's signed identity.

### 2. Capture

A three-second record/stop run completed end to end from the signed bundle:

- Status events: `recording` then `completed`. Level meters were live for both sources.
- Output: `$TMPDIR/MeetingAssistant-rebuild-spike/2026-06-10T15-15-21Z/`
- `system.caf`: 1,117,696 bytes
- `microphone.caf`: 552,960 bytes

Both sizes are plausible for three seconds of audio (non-zero, system roughly twice the mic).

### 3. Codesign identities and requirements

From `codesign -dv --verbose=4`:

| | App | Sidecar |
| --- | --- | --- |
| Identifier | `com.devswift.MeetingAssistant.rebuild` | `com.devswift.MeetingAssistant.rebuild.sidecar` |
| Format | app bundle, Mach-O thin (arm64) | Mach-O thin (arm64) |
| Signature | adhoc | adhoc |
| Flags | `0x2(adhoc)` | `0x2(adhoc)` |
| TeamIdentifier | not set | not set |
| Internal requirements | count=1 size=80 | count=1 size=88 |

`Internal requirements count=1` on each binary confirms the pinned designated requirement was
embedded (verify the exact DR text any time with `codesign -d -r- <path>`).

### 4. Sidecar identity and protocol

The UI showed the buffered `ready` event correctly: pid 46983, bundle id
`com.devswift.MeetingAssistant.rebuild.sidecar`, sidecar 0.1.0, protocol 1. No `error` events
were observed during the run.

### 5. Environment fixes that were needed to get here

These are already in the tree; recorded so they are not rediscovered:

- Tauri only embeds `frontendDist` when the `custom-protocol` cargo feature is on. The script
  now builds with `cargo build --release --features custom-protocol`; without it the release
  binary looks for the Vite dev server and renders a blank white window.
- `open_devtools()` must not be gated behind `#[cfg(feature = "devtools")]` (that checks the
  local crate's features, not Tauri's); it is called unconditionally.
- `generate_context!` requires a true RGBA `icons/icon.png`; the script re-encodes the iconset
  PNG via an AppKit converter with a `sips` fallback.
- Vite `base: "./"` and a removed `tsconfig.json` project reference (TS6310) round out the
  frontend build fixes.

## Known cosmetics (not blockers)

- Devtools auto-opens at launch (deliberate for the spike), which crowds the 780x680 window.
  Remove the `open_devtools()` call when the spike UI is retired.
- The sidecar build warns that `Info.plist` is an "unhandled" resource; the linker still
  embeds it via `-sectcreate`.

## Carry-over checks before closing the phase

- Quit the app and confirm the sidecar exits with it: `pgrep meetingcore-sidecar` returns
  nothing.
- Confirm the native app is untouched: `swift build` and `swift test` at the repo root still
  pass.

## Next

Phase 2 per `REBUILD_PLAN.md` section 8: freeze the contracts and add seam regression checks.
Do not start without the user's review.
