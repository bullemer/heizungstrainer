# Release review: Heizungstrainer 1.2.1 (32)

Reviewed 2026-10-14 against starting commit `47b8466`. Changes remain uncommitted.
The release is prepared for **internal testing**, not certified for production.

## Confirmed findings and fixes

| Priority | Finding | Change / evidence |
|---|---|---|
| High | Changing billing providers retained the previous consumption; demo numbers could become “real Brunata” inputs. The SQLite cache also had one unlabelled entry for all providers. | Reset provider-specific state; cache by provider ID; ignore results from superseded syncs; restore settings before selecting a cached source. Regression tests cover source isolation and timestamps. |
| High | Reads and connection attempts completing after disconnect could restore stale data or reconnect the UI. Modbus disconnect could clear a newer socket after awaiting the old one. | Connection generations, single-flight provider polling, synchronous socket detachment and stale-result checks. Tests cover cancelled connects, late reads/errors and overlapping refreshes. |
| Medium | Starting demo mode replaced the real driver without releasing it; sample telemetry could overwrite the hardware cache/history. | Release the previous connection first; do not persist simulated controller readings or telemetry. |
| Medium | NaN bypassed min/max comparisons and could reach a driver. | Reject all non-finite writable parameter values before issuing commands; tests verify no writes. |
| Medium | Home, backup, settings and chart labels overflowed on narrow phones and with larger text. | Flexible/wrapping label groups, legends, presets and settings headers; shorter bottom-nav label. 36 screen/size/text-scale tests, including populated curve and live-view screens, now pass. |
| Medium | The status bar reported green “connected” while polls were failing. | Retry state has precedence; demo state is explicit; regression test. |
| Medium | The Danfoss demo did not expose the curve points needed by its own curve simulator. | Supply example points only in Danfoss simulation; label the simulator as demo; clear them on disconnect. |
| Low | “Yesterday” failed across month/year boundaries. | Calendar-date comparison; boundary tests. |
| Release | Store listing referenced 1.1.8/build 10, overstated storage encryption and excluded third-party transfers from Data safety. | Updated listing, reviewer notes, release notes and explicit outstanding Data-safety decisions. |

Old, unlabelled billing cache entries are deliberately not treated as real data.
Users need one billing sync after updating; credentials and settings are retained.

## Verification

- Baseline: 346 tests passed; static analysis clean.
- Updated: 392 unit/widget tests passed, including 36 responsive layout cases at
  320/360 logical pixels and text scale 1.0/1.3. Traversal includes content below the fold.
- `flutter analyze --no-pub`: no issues. A source-reference scan found no obvious
  entirely unused class. This does not prove all public APIs or runtime branches are reachable;
  compatibility aliases and controller adapters were not deleted speculatively.
- Some pre-existing tests still touch the shared SQLite database and emit caught
  database-lock/plugin warnings in parallel runs; the new persistence tests use an
  in-memory database. Passing tests are not proof of hardware/network behavior.
- Flutter 3.38.9 / Dart 3.10.8; Play flavor; package `com.heizungstrainer.heizungstrainer`;
  version name 1.2.1, version code 32; minimum API 24, target API 36.
- AAB and APK release builds, signatures, bundle validation and native alignment:
  see the accompanying release folder's `verification/` outputs for final artifacts.
- Final AAB validated with bundletool; `jarsigner` reports `jar verified`.
  Its additional self-signed-certificate/no-timestamp and streaming ZIP-manifest-order
  warnings are retained in the verification output; Play Console acceptance remains untested.
  The APK verifies with signature scheme v2 and the Heizungstrainer/Navisense certificate.
  Bundle config requests `PAGE_ALIGNMENT_16K`; all eight arm64/x86_64 libraries have
  LOAD alignment at least 16 KB; APK `zipalign -P 16` passes. This is a binary alignment
  check, not execution on a 16 KB device.
- No dependency upgrades: available updates were not mixed into this release fix.

## Screenshots

Five 1080×1920 screenshots are rendered directly from the current Flutter app's
widgets with demo data using `tool/capture_store_screenshots_test.dart`.
They were visually reviewed after loading real text, icon and emoji fonts.
These are **widget renders, not Android-device captures**; they do not verify native
system bars, Android permissions, WebView, keyboard or file-picker appearance.
No real tenant data, portal credentials or private controller addresses are used.
Existing icon (512×512) and feature graphic (1024×500) are included separately.

Reproduce on this workspace:

```sh
HEIZUNG_SCREENSHOT_FONT=/home/carsten/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf flutter test tool/capture_store_screenshots_test.dart
```

The harness uses local system fallback fonts for rendering. Other workstations need
the matching fonts/Flutter SDK path. Generated screenshots are in `build/play-release/screenshots/`.

## Before production submission

1. Upload the **AAB** to an internal Play track. Confirm build 32 is unused and the
   upload certificate matches the certificate registered in Play Console. Neither
   Play Console state nor server-side acceptance was accessible in this review.
2. Run Play's pre-launch report and test installation/update on a real Android device.
   Test fresh start, demo, back/navigation, keyboard and permission denial, offline/reconnect,
   file export/import, portal login and an authorized read/write/read-back on the actual ECL.
   No Android device, emulator or heating hardware was attached during this review.
3. Review the Data safety draft in `play-store-listing.md`, especially third-party
   portal/Cloud credentials, diagnostic payloads, server logs, retention and deletion.
   Backend processing cannot be established from this mobile repository alone.
4. Keep beta controller drivers labelled beta until tested on their real hardware.
   App-side holiday automation still requires the app to run and reach the controller.
5. Website APK and Play use different signing identities. The supplied Play-flavor
   APK is for testing, and is signed with the upload key; it may not update an app
   installed from Play (Play App Signing) or the website. Export settings before any
   uninstall. Prefer internal-track installation for the true Play update path.

## Official release references

- [Target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Android 16 KB page support](https://developer.android.com/guide/practices/page-sizes)
- [Play preview assets](https://support.google.com/googleplay/android-developer/answer/9866151)
- [Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Public privacy policy](https://heizungstrainer.de/datenschutz.html): HTTP 200 on the review date.
