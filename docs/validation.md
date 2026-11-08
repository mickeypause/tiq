# Validation history

Validated locally on 2026-11-07. Phase-one checks below predate Linear integration; see the phase-two section for current evidence. No cloud builds, signing setup, remote publication or commits were performed.

## Phase two: Linear integration

Implemented native OAuth authorization-code/S256 PKCE, secure rotating credentials, authenticated GraphQL, team/workflow selection, native media uploads and issue submission on both platforms. iOS uses Keychain; Android uses AES-GCM with a Keystore key and no-backup storage. No client secret or personal API token is bundled. A real public Client ID is now configured in the ignored `example/.env.local`; native callbacks use `dev.rnqaoverlay.example.qa://linear/callback`. The workspace account has not yet been connected.

- `bun run check`: passes Oxlint, TypeScript, bundling and five config tests / 24 assertions.
- `bun run verify:exclusion`: preview, production, missing and unknown generation checks pass. The fixtures now include a public Linear Client ID/team. Only preview includes OAuth metadata and the callback scheme/activity. These are generated-config checks; phase-two production binaries have not been rebuilt/audited.
- `bun run test:linear:ios`: standalone Swift checks with mocked URLSession HTTP pass: RFC PKCE vector, random verifier length, exact callback/state and duplicate-parameter rejection, single-flight rotating refresh, HTTP 401 and GraphQL authentication-error refresh/retry, revoked refresh clearing, GraphQL partial errors, pagination failure, rate limits, issue lookup, receipt/upload URL validation, and upload headers without an OAuth bearer token.
- `bun run test:linear:android`: two JVM tests pass with zero failures, covering exact callback/state validation, malformed/duplicate parameters and URL-encoded token fields.
- Updated iOS and Android preview Release builds pass. The first iOS prebuild/pod installation includes the new Swift source files.
- iOS Simulator: opening Report bug shows the unconfigured connection/setup form sheet, with no input/keyboard focus and disabled submission. Authenticated composer interactions require a configured OAuth app and an already signed-in tester; existing composer/attachment regressions now document that prerequisite and were not replayed as phase-two passes.

Android phase-two device UI validation is blocked: Argent reinstall failed with `INSTALL_FAILED_DUPLICATE_PACKAGE` because the emulator has duplicate pending install requests. The APK compiles; that failed installation is not a passing device check.

Configured-client follow-up: generated iOS/Android metadata and callback registration match the supplied Client ID. The configured iOS Release build passes and reaches Linear's real login page in `ASWebAuthenticationSession`. An unsigned simulator build could not read Keychain; rebuilding through Xcode with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_LOCAL_EXECUTION_IDENTITY='Ad Hoc'` resolved that failure. Do not disable signing for OAuth/Keychain simulator checks. Manually applying an ad-hoc signature after building did not produce a launchable app; use Xcode's build/signing pipeline.

Still required: the tester must finish Linear sign-in and consent in the iPhone 18 Pro simulator. Then verify the native callback/token exchange, sign-in persistence and refresh, live team permissions, actual image/video visibility in Linear, and an authorized ticket-creation round trip. Reaching login does not yet prove redirect validation or token exchange. No real issue was created. Camera/recording hardware coverage remains as described below.

Media URLs are appended to Markdown after the text. Cursor-position insertion and a rich-description editor are not implemented. Drafts and same-UUID submission recovery remain process-local. Sign out removes local credentials; workspace authorization can be revoked in Linear settings.

## Passed

- Bun installation and plugin bundling; Oxlint; strict TypeScript checks for plugin/scripts and example; four Bun tests (15 assertions) for fail-closed environments, reversible native edits and unsupported-template failures.
- Expo SDK 58 prebuilds for preview, production, unknown and missing APP_ENV. Only preview includes enablement metadata and iOS camera/microphone descriptions. Excluded cases carry explicit CocoaPods and Gradle autolinking exclusions, and their public Expo config omits the reporter plugin entry.
- iOS Release simulator builds with APP_ENV=preview and APP_ENV=production. Reporter-specific symbols (`QaOverlayHost`, `QaOverlayAppDelegateSubscriber`, `qa-overlay.button`) occur in the preview executable and are absent from the production executable.
- Android Release arm64 builds for preview and production. Production APK DEX has no `expo.modules.qaoverlay` namespace. Its compiled manifest has no reporter activity, recording service, file provider or media-projection foreground-service permission.
- Native automatic startup without a runtime reporter import in example/App.tsx on iPhone 18 Pro / iOS 27 Simulator and an Android 17 emulator.
- iOS recorded composer flow: open, focus/type title, close, reopen, and retained title. Full replay passed. SwiftUI close has no matching UIView id/label in the native runner projection, so the recorded test uses one documented point from the accessibility tree, specific to iPhone 18 Pro portrait. Text assertions use the accessibility-tree tool because the runner's UIKit projection does not expose SwiftUI text values. Idle warnings were the visible text caret; title checks passed.
- Android recorded composer flow: open, type title, screenshot thumbnail, close/reopen and retained title. Full replay passed. The title uses its exported Compose resource test tag. Native keyboard insets keep all five attachment controls above the keyboard.
- One-off screenshot capture on both platforms showed the host content rather than the reporter form.
- Android screen capture: system consent, return to host with a Stop control, stop, and return to the same title/draft with a generated video thumbnail. This was an interactive check, not a saved recording-permission regression.
- The final iOS Simulator build's recording action was checked: it shows the explicit physical-iPhone message immediately and leaves the draft intact. It does not enter a false recording state.

## Native UI refresh

- Replaced custom header/toolbar treatments with SwiftUI navigation controls and native Liquid Glass on iOS 26+, with system material fallback on earlier iOS versions. Entry button uses UIKit's native glass configuration. Attachment buttons retain 44-point minimum hit areas.
- Android uses Material 3 `1.5.0-rc01`, `MaterialExpressiveTheme`, the native app bar, floating toolbar and extended FAB. Dynamic colors and automatic system-bar contrast follow the device appearance. This dependency is a release candidate.
- Removed Discard from both composers. Close retains the in-memory draft and per-attachment removal remains available.
- Title/description use the Linear reference's borderless layout, a scalable bold 24-point/sp title and regular body description. iOS uses Dynamic Type and Android uses the Material typography scale. Removed phase-two helper copy from the form.
- Updated preview Release builds pass on both platforms. Saved composer flows pass with the native controls; Android's FAB is selected by an explicit resource test tag and iOS's close point was updated from the current accessibility frame.
- Interactive checks on both platforms confirmed description entry, screenshot thumbnails, all five attachment actions above the keyboard, and no Discard control. These checks used iOS 27 Simulator and Android 17 emulator. Older-iOS material fallback and large accessibility font sizes were not visually rechecked in this refresh.

## Automatic appearance

- The native reporter follows the device: SwiftUI system colors/materials on iOS and `isSystemInDarkTheme()` plus system dynamic colors on Android. No forced reporter appearance remains.
- Updated the example host's hardcoded dark palette to `useColorScheme()` and its status bar to automatic appearance. Expo config already requests automatic appearance.
- `bun run check` passes (Oxlint, TypeScript, four tests / 15 assertions); updated iOS and Android preview Release builds pass.
- Composer flows pass on both devices in dark mode. Switched system settings back to light with the process still alive: both reporters changed appearance and retained the title; Android retained its screenshot attachment. Light host UI was checked on both platforms. Devices were restored to their original light appearance.

## Attachment zoom transitions

- iOS thumbnails are matched transition sources for the native iOS 18+ zoom presentation into Quick Look. The same route supports image and video attachments. Reduce Motion and iOS 16/17 retain standard presentation. Added a native Done toolbar control. Opening a preview dismisses the keyboard.
- Android now previews attachments inside the reporter with Compose shared-bounds transitions instead of handing off to an external viewer. Native VideoView/MediaController provides playback, seek and error handling. Playback stops when the preview leaves composition and pauses when the app backgrounds. Image decoding runs off the main thread, caps display resolution at 2048 pixels and preserves EXIF orientation on the legacy decoder. Original attachment files remain untouched.
- Android scroll positions are retained outside the preview transition; Close and system Back return to the composer. Destination titles provide accessibility pane identity, and Compose animations follow system animation settings.
- Both preview Release builds compile; Bun/Oxlint/TypeScript checks and all four plugin tests pass. The recorded iOS image open / native Done / return flow passes end to end (`tests/e2e/attachment-zoom-ios.yaml`). Its Screenshot, thumbnail and Done taps use documented accessibility-derived points on iPhone 18 Pro portrait: native-find-views found no matching SwiftUI label/id and runner assertions failed, although raw accessibility waits succeeded. This test is device-specific.
- Android image open, native Close and return were visually checked. Also created a screen recording, opened its video thumbnail, observed changing playback frames and native play/seek controls, then closed and verified that image/video attachments remained.
- Android's automated preview-return check is blocked by an Argent inspector cache issue: after Close, the screenshot shows the composer but the helper continues reporting the old preview tree. A scoped inspector restart exposes the correct composer and attachment nodes. Two replay correction attempts did not resolve it; the diagnostic recording remains under ignored `.argent/e2e/attachment-zoom-android.yaml` and is not presented as a passing regression test.
- Not checked in this change: physical iPhone video playback/zoom, iOS 16/17 fallback, reduced-motion visuals, legacy Android decoder/device coverage, large galleries or format/codec permutations. No camera, permission, production inclusion or Linear behavior changed.

## Form-sheet presentation

- The custom compact floating surface and all focus-triggered expansion logic were removed. iOS presents the composer with UIKit `.formSheet`; Android uses the standard Material 3 modal sheet, with platform-default width and shape. Both start without input focus or a keyboard.
- Native dismissal and Close retain the draft. iOS's presentation delegate cleans up the overlay window after interactive dismissal, restoring the host key window/accessibility state. Android restores its floating entry button when the host resumes.
- The compact-sheet-only tests were removed because that mode no longer exists. Existing composer and image tests cover the current presentation; iOS points are scoped to iPhone 18 Pro portrait.
- Both preview Release builds compile. iOS composer/draft and image-preview regression replays pass, and native swipe dismissal restores the entry button. Android was checked interactively: opens as the standard sheet without a keyboard; tapping Title focuses it and shows the keyboard. Automated typing timed out with partial text, and entry-button restoration after Close could not be verified because the UI tree became unreadable. Its automated composer replay was also blocked twice at `am start` by emulator launch timeouts; the host subsequently appeared and no AndroidRuntime crash was logged. These are not reported as passing Android replays.
- Tablet, landscape and physical-device form-sheet behavior remain unverified.

## Limits and remaining checks

- iOS Simulator ReplayKit start/stop callbacks returned success but no movie existed at the output URL. Simulator builds now fail early with a clear physical-iPhone message instead of pretending recording succeeded. The physical-iPhone ReplayKit path is implemented but not hardware-validated. The installed SDK marks ReplayKit deprecated in iOS 27; migration needs evaluation when the replacement is available for the supported iOS SDK (ScreenCaptureKit headers were absent from this Simulator SDK).
- Camera photo/video, gallery import, external video playback, denied permissions, rotation, background interruptions and long/maximum-sized recordings still need hardware/device coverage. iOS camera requires a physical device. A video thumbnail verifies finalized output in the Android capture check, not playback/audio on all target devices.
- Android screen-recording system dialogs exposed an empty accessibility tree through Argent; keyboard focus navigation was used for consent. No screenshot-derived tap points were used for that consent flow.
- The supported setup keeps the build-time plugin installed in every environment and uses clean native generation when APP_ENV changes. Omitting the plugin or reusing approved generated native projects for production is unsupported. Exclusion is not a runtime toggle.
- Binary checks cover these example artifacts and selected markers, not all possible host-app configurations or shared dependencies. The example does not independently use the reporter's native features.
- Drafts are in-memory; process termination loses them. Evidence is temporary cache data. Screen recordings have a 60-second cap and files a 100 MB cap.

## Reproduce

```sh
bun run check
bun run verify:exclusion
bun run ios
bun run android
```

Replay installed preview builds with Argent:

```sh
argent e2e run --help
```

The saved flows are `tests/e2e/composer-ios.yaml` and `tests/e2e/composer-android.yaml`; provide their absolute path through Argent's `e2e-execute` tool and select the intended device explicitly. The iOS flow's documented point requires the tested device geometry.

Native build logs are under `/tmp/rn-qa-overlay-*-build.log`. Preview iOS artifacts are under `artifacts/ios-preview/`, production iOS artifacts under `artifacts/ios-production/`, and production generated examples/APKs under `artifacts/exclusion/production/`. These generated outputs are ignored by Git. Android's ordinary preview APK is under `example/android/app/build/outputs/apk/release/`.

## Reference-sized glass controls

- The iPhone 15 Pro reference was normalized to its 393-point logical width: approximately 40-point team capsule height, 44-point attachment bar height, 12-point outer horizontal/bottom spacing and 20-point SF Symbols. The team label uses a scalable 15-point semibold style. The existing five capture actions remain.
- Team menu and attachment bar use native Liquid Glass on iOS 26+, with native material fallback. Team/status/tool icons use the same adaptive primary foreground as text. Status uses a compact capsule rather than a blue text-only picker.
- The signed iOS Release build passes. Checked with an already authenticated account on the iPhone 18 Pro simulator: opens without focus, team menu opens/dismisses, title focus brings up the keyboard, and all five 44-point-minimum attachment targets remain visible above it. Light/dark appearance changes automatically; original Light appearance was restored. No report was submitted.
- A before/after screenshot diff reports 2.36% changed pixels in the header, bottom controls and blinking title caret. The status changed from In Review to the loaded default Backlog after reinstall, so this is visual-change evidence rather than a pixel-identical regression pass. Artifacts: `artifacts/glass-toolbar-diff/`.
- Physical iPhone 15 Pro pixel matching, long team names, large accessibility type and older-iOS material fallback remain unverified. Android UI was not changed in this iOS reference update.

## Keep editor focus

- iOS composer scrolling uses `.scrollDismissesKeyboard(.never)`. Preview, submit and screen-recording actions no longer explicitly clear the focused field. Gallery/camera/preview sheets remember the prior editor field and restore it after dismissal; opening a fresh composer still does not autofocus.
- Signed iOS Release build passes. On the signed-in iPhone 18 Pro simulator, title focus/keyboard survive a background tap, a scroll gesture, opening the team menu and selecting the same team. Canceling the gallery restores title focus with the keyboard visible. No ticket was submitted.
- System capture/preview screens temporarily own presentation and keyboard behavior. Camera return requires hardware coverage. Android behavior was not changed in this iOS composer update.

## Frame-by-frame menu-layout diagnosis

Recorded 42.47 seconds at 30 fps on the signed-in iPhone 18 Pro simulator, with static trimming and touch overlays disabled. Scanned all 1,274 frames and visually inspected consecutive frames around the four menu transitions. Video: `/Users/serhiifozykosh/.argent/recordings/screen-recording-A46CC871-01E3-49A6-8474-48F565EEA28A-1794082859909.mp4`. Analysis, frame trace and transition contact sheets: `artifacts/menu-layout-review/`.

- Team menu opening at frame 354 / 11.800 s removes the keyboard prediction strip. The status/tool bar drops about 26–27 logical points because its bottom safe-area inset follows the keyboard height. The input remains focused. Status-menu opening at frame 1030 / 34.333 s repeats the same shift.
- Selecting the team at frame 853 / 28.433 s also produces a separate, brief keyboard collapse while Loading workflow is shown, around frames 857–877. The composer disables its editor while `linear.locked`; the team loader also clears states/stateId before awaiting the request, so the status capsule briefly loses its text and shrinks. The keyboard returns when loading completes. Earlier settled-screen checks missed this transient collapse.
- Status selection at frame 1253 / 41.767 s restores the prediction strip and raises the lower controls again. The original In Review state was restored. No issue was created.

This turn diagnoses the motion and changes no app source. Stabilizing the keyboard-relative controls during menu presentation and keeping the editor/status geometry intact during workflow loading are the next implementation work. Physical devices and other OS versions remain unchecked.

## Native Close confirmation

- iOS Close is a native UIKit `UIButton` inside the navigation toolbar. Its own configuration is plain, so the toolbar provides one native glass background without a second nested glass circle. Verified the rendered control is a single `UIButton` with `qa-overlay.close`.
- Close presents a native `UIPopoverPresentationController` to the right of its source button, with a left-pointing arrow. The 240-point-wide panel contains two native capsule buttons: red Discard and Save draft. The keyboard remains visible when opened from the focused editor. UIKit controls the popover chrome and adapts its appearance; button fonts support Dynamic Type.
- Save draft closes and retains the existing process-local report. Discard clears title/description, owned attachment files, cached uploaded URLs and restores the default workflow state before closing. Discard is unavailable during requests or while an uncertain issue creation still needs confirmation; Save draft is unavailable during a request or attachment import. These controls do not add disk persistence.
- Signed iOS Release build passes. `tests/e2e/close-draft-ios.yaml` completes a full save/reopen/discard/reopen pass, verifying saved title and screenshot retention, then an empty title and absent screenshot after discard. Its Screenshot tap has a documented accessibility-derived coordinate fallback for iPhone 18 Pro portrait because the native runner projection has no matching Screenshot view; raw AX checks preserve SwiftUI text/value and thumbnail evidence. One initial replay tapped Close before the reopened sheet settled; a readiness gate after the recorded identity check resolved it. Final run: 32 passed, zero failures; small idle warnings were the blinking text caret.
- Updated `tests/e2e/composer-ios.yaml` to select Save draft after Close. No Linear ticket was submitted. Android was not changed. Physical-device and large accessibility-type visuals remain unchecked; saved drafts still disappear on process termination. The earlier team/status-menu layout diagnosis remains separate work.

## Shared status and attachment toolbar

- Moved the iOS status picker from its separate chip into the leading 44-point icon button of the existing glass toolbar. A native vertical Divider, 24 points high with 8-point side spacing, separates it from the five attachment buttons. The shared capsule retains its 44-point baseline height, 12-point outer spacing, 20-point symbols and adaptive primary foreground.
- The native menu uses an inline Picker, checkmarks the selected workflow state and exposes Status plus the selected name through accessibility (`qa-overlay.status`). The separate status row/background is removed.
- Signed iOS Release build passes. The save/reopen/discard/reopen regression passes with the shared toolbar (32 passed, zero failures), including the existing Screenshot coordinate fallback. Interactive inspection confirmed one shared capsule/divider and all six controls; the Status menu showed Backlog checked, and selecting In Review updated its accessibility value. No issue was submitted.
- Android and physical-device visuals were not changed/rechecked. The previously diagnosed native-menu keyboard prediction-strip movement remains separate work.


## Bundled Linear icons (2026-11-07)

- Packaged 317 named Linear SVGs as an iOS asset catalog in a CocoaPods resource bundle and generated 317 Android VectorDrawables. The generator validates XML and the supported SVG subset; Android resource references are explicit so release shrinking preserves the lookup. No runtime asset requests or new dependencies.
- Native clients now query team `icon`/`color` and workflow `color`. Status types map to the bundled Triage, Backlog, Todo, Started, Done, Canceled and Duplicate symbols. Unknown identifiers, including unsupported emoji identifiers, use a fallback. `Cookie` was listed in the web-client enum but absent from its SVG sprite.
- iOS uses native UIButton/UIMenu for both selectors, preserving original icon colors in the menu and selected control. Verified cyan team icon with primary-color text, purple selected Done icon, per-row colored status symbols and native selection checkmarks. Controls retain their prior 40pt team / 44pt status frames and glass containers.
- Passed iOS Release Simulator build, Android release assembly, iOS native core checks including icon/color decoding and all workflow mappings, three Android JVM tests (zero failures/errors), `bun run check` and `bun run verify:exclusion` for preview/production/missing/unknown.
- Recorded then replayed `tests/e2e/linear-icons-ios.yaml`: 17 executable steps passed, no failed/errored/skipped steps. Final saved test uses native button identifiers, no raw points. It requires the signed-in internal workspace with Nitro Development and a Done state; it selects that team and Done, and creates no issue. Final status-value check uses the AX tree. No warnings on the final replay.
- Android UI was compiled but not manually exercised. All assets compiled on both platforms; individual artwork was not visually checked exhaustively. Third-party provenance and unresolved redistribution permission are recorded in the package notice, which is included in package files and excludes these assets from the package MIT license.


## Named status and scrollable capture row (2026-11-07)

- iOS status UIButton now displays its selected name beside the Linear icon. The shared glass toolbar is a horizontal ScrollView, retains its 44pt height and vertical separator, and uses fixed 48pt capture targets instead of compressing them. Scrolling explicitly keeps the keyboard open.
- Android moves the named status selector into the same M3 floating toolbar, with a vertical divider and a bounded horizontal scrolling Row. No additional dependencies or inclusion changes.
- iOS Release build passed. Updated the recorded close-draft regression for the new row: select In Progress, focus/type the title, scroll horizontally, verify typing predictions are still visible, tap Screenshot, save/reopen/discard, and verify the empty report. Full replay passed 42 executable steps with no failures/errors. Raw swipe/Screenshot coordinates remain scoped to iPhone 18 Pro portrait because the native runner omits those SwiftUI buttons; AX frames supplied the points. Waiting for scroll bounce to settle is required before tapping. Two idle warnings were consistent with the visible blinking caret; the keyboard, screenshot attachment, saved draft and discard results were independently checked.


## Nonblocking creation confirmation (2026-11-07)

- Replaced the iOS Ticket created alert and Done/Open actions with a SwiftUI native-material confirmation banner: checkmark and ticket identifier, no modal or hit interception. It expires after four seconds (eight with VoiceOver), announces success for accessibility, and emits native success feedback. Cancellation and receipt identity protect replacement messages; closing the composer clears its transient receipt.
- Android now consumes confirmed receipts in LaunchedEffect and shows a system Toast with the ticket identifier. Existing submission/error/recovery and confirmed-only draft clearing remain unchanged. The composer stays open on both platforms.
- iOS and Android Release builds passed. iOS UI validated with a temporary simulated receipt (QA-DEMO) inserted after session opening in a fixture build. Recorded visible banner, then hidden banner, then usable title field; final replay passed seven executable steps with zero failures/errors. No Linear issue was created. The temporary fixture source was restored byte-for-byte and the original final app binary restored/reinstalled afterward. The ignored fixture flow `.argent/e2e/success-confirmation-ios.yaml` requires that simulated-receipt build and is not a general live-submit regression test.
- Android toast was compile-checked, not manually exercised. VoiceOver timing/announcement and physical-device haptics were not exercised.


## Android native composer parity (2026-11-07)

- Added native Material Discard/Save draft dropdown anchored to Close, with protected discard when a submission UUID remains unconfirmed. Discard clears owned temporary attachments, cached upload URLs, errors and report fields; Save draft retains the process-local report. Sheet dismissal continues to preserve it.
- Added a bounded pill team selector and tonal circular header actions. Shared status/capture row uses named status, Linear colors/icons, a vertical divider, horizontal scrolling, monochrome 20dp capture icons and 48dp native touch targets. Removed duplicate system insets inside the modal sheet.
- Team/status/Close menus are nonfocusable native popups so the editor retains focus. Busy text fields become read-only rather than disabled. Workflow choices/team commit together after successful loading, avoiding transient status-label collapse or retaining mismatched team/state on failure. Progress floats centrally instead of inserting rows in the editor. Preview return restores the previously focused field.
- Replaced Android system toast with the native Material snackbar host for brief nonblocking ticket confirmation. No success dialog. No automatic input focus on first opening.
- Release assembly and four JVM checks passed, including preservation of the title/owned file while a submission UUID is unconfirmed, and deletion of only owned attachments after safe discard. `tests/e2e/composer-android.yaml` now chooses Save draft after Close; full replay remains unverified.
- Actual emulator observations using temporary local workspace data: initial sheet layout, title/description typography, team pill, shared toolbar, absence of initial keyboard, native Close choices, and returning to the host through Save draft. Keyboard typing, team/status focus retention, preview restoration and snackbar require a stable Android target before acceptance. Emulator input/graphics ANRs and later broken package service prevented a complete UI run. Failed/partial recordings are ignored `.argent/e2e/android-parity*.yaml`; none is reported as passing.
- Temporary workspace/receipt fixture was restored out of source. Final APK has no fixture marker and is preserved at `artifacts/android-parity/app-final.apk`. Emulator configuration and temporary handwriting/hardware-keyboard settings were restored. Final APK reinstall failed because Android’s package service returned Broken pipe; do not treat the current emulator installation as the final build. No real Linear issue was created.

Cleanup update: subsequent cleanup boots also failed registration and Argent terminated the emulator. Reinstall then failed with device not found. The emulator is stopped; its stored installation may still be the temporary fixture. Install the verified final APK before any further use. AVD config was verified byte-for-byte against its original backup. The normal release manifest still declares MainActivity with MAIN/LAUNCHER.


## Installable npm artifact (2026-11-08)

- Added a package prepack build for bundled Node CommonJS plugin code and generated TypeScript declarations. Exported QaOverlayOptions; scoped peer support to the tested Expo 58 / React Native 0.88 families. Root `bun run pack` writes an npm-compatible tarball under `artifacts/npm`.
- Replaced broad native-folder packing with source/resource allowlists. The archive contains 984 files, including 317 iOS SVG assets and 317 Android vectors, and excludes native build directories, unit tests, example app, environment files and dependency folders. The package README is standalone; mixed license metadata and bundled-asset notices are included. Podspec distribution metadata no longer points to example.invalid; `pod ipc spec` parses it successfully.
- `bun run verify:package` passed. It installed the actual tarball, with lifecycle scripts disabled, in a separate temporary project outside the workspace. No symlink to workspace package sources was permitted. Plain Node require loaded the plugin, consumer TypeScript validated the exported options (including rejecting a non-array environment value), and Expo autolinking discovered the installed Apple and Android native sources.
- The installed consumer passed clean native prebuild and public-config checks for preview inclusion and production/unknown/missing exclusion, with public OAuth fixture callback metadata included only in preview. This verifies generated configuration, not a new native binary exclusion audit. The temporary project was removed after the checks; results are recorded in `artifacts/npm/verification.json`.
- `bun run check` passed: build, Oxlint, workspace/example typechecks and five plugin tests (24 assertions). No registry publication was attempted. Existing Android device-validation and third-party icon redistribution limitations remain documented in the distributed README.

## Local Tiq package

- Renamed the consumer package and Expo plugin to `@mickeypause/tiq`; native class names, source directory and OAuth callback identifiers remain unchanged.
- `private: true` blocks registry publication; local tarball installation needs no registry authentication.
- `bun run check` passed build, lint, type checking and all five plugin tests.
- `bun run verify:package` installed `artifacts/npm/mickeypause-tiq-0.1.0.tgz` outside the workspace, checked the scoped package identity/publication guard, loaded the plugin in Node, checked TypeScript declarations and discovered both native modules. Clean native generation included preview and excluded production, unknown and missing environments.
- Android’s autolinked Gradle project is now `mickeypause-tiq`; the native test script targets that name after clean native generation.
- No registry publication or new device/runtime validation was performed for the package rename.

## Screenshot tool removal

- Removed the screenshot button and capture implementation from iOS and Android. Android no longer snapshots the host when opening the reporter. Screen recording is unchanged.
- Package version 0.1.1 installs independently and passes preview/production/unknown/missing environment checks. Android Release Kotlin compilation passed.
- Saved composer/draft flows now cover text drafts; image zoom requires an image prepared through Gallery. Prior screenshot-based replay results above are historical and do not establish that the revised flows passed.
- Signed iOS Simulator Release build passed. Live AX/UI checks confirmed the four remaining capture actions and no Screenshot action, both before focus and with the keyboard attached. No issue was submitted.

## Draft alert, focus and dismissal

- Removed the iOS custom close popover and Android close dropdown. Nonempty reports use native alerts with only Discard and Save draft; empty/whitespace-only reports close immediately. Existing submission/import guards remain.
- Disabled iOS interactive modal dismissal and Android sheet gestures/outside dismissal. Android Back goes through the same empty/content-aware close path. Hid the drag handles.
- The title automatically receives focus once editing is available; preview focus restoration remains separate and team requests do not refocus the title.
- Both native builds passed. Android unit checks passed five tests, including whitespace/text/attachment draft-content cases and retained uncertain-submission protections.
- `tests/e2e/close-draft-ios.yaml` was recorded live and replayed on the signed iOS Simulator Release build: 45 executable steps passed. It covers empty close, typing into the automatically focused title, blocked sheet drag, Save draft/reopen, Discard/reopen, and automatic focus on subsequent opens. Seven idle gates warned about small continuing motion; the visible caret and hard value/destination checks were inspected. Keyboard and value checks intentionally retain AX tools because the native runner omits those values. The one raw swipe targets the intentionally unlabeled sheet header, with an AX-derived origin on iPhone 18 Pro portrait.
- A second prefix replay stopped at the alert; native AX/UI inspection verified exactly Save draft and Discard, without an extra Cancel action. No Linear issue was submitted. Android device behavior is still not live-validated.

## Expo-style floating button (0.1.3)

Ported Expo dev-menu 58.0.11 native FAB styling, label/idle timers, momentum, springs and persisted edge position. Kept the button above the reporter on both platforms. Included Expo MIT attribution. iOS Release and Android Release builds pass. Swift safe-area placement assertions and Android placement unit tests pass. The iOS recorded flow passes: persisted right position, drag left, open reporter, drag right above sheet with title/keyboard focused, close empty report. Android live checks confirm host touch passthrough, dragging/snapping, FAB above the sign-in sheet, and persisted right-edge position after closing. Its injected accessibility tree can retain pre-animation frames until window recreation; action screenshots and known drag endpoints were used to diagnose this tool limitation. The authenticated Android composer was not checked in this fresh emulator.

The existing iOS close/draft regression also passes after replacing post-close FAB-visible gates with composer-hidden gates (the FAB now remains visible by design).

Qpaws Preview was updated to the local 0.1.3 tarball, built as signed Release without dev launcher, installed over the existing Preview app via Wi-Fi and launched successfully on the iPhone 15 Pro. Qpaws dependency update is local commit 72b6e603b; no push/publication.

## Full-screen asset gallery and thumbnail controls (0.1.5)

- Full-screen, title-free native gallery starts at the tapped asset and pages horizontally through images/videos. Back restores editor focus; More removes the current asset, selects its neighbor, and closes at empty state. iOS retains the native zoom entrance where supported. Android uses a full-screen native dialog with HorizontalPager and native video controls; inactive videos pause.
- Form previews are 208×156 logical points with rounded corners and a gray circular × at the upper right (44-point button). Thumbnail generation increased from about 240 pixels to 1024; Android thumbnails now use the same orientation-aware decoder as previews. Gallery image decoding is bounded to 4096 pixels.
- iOS Release build and the saved 23-step `tests/e2e/attachment-gallery-ios.yaml` pass. It covers importing two stock photos, opening the second asset, paging both ways, Back/keyboard restoration, removing one then the final asset through More, and importing/removing another asset using ×. Run against a freshly installed example with its six stock Simulator photos and existing Linear sign-in. Swipes start inside the image, beyond the FAB's expanded edge touch area.
- Android Release assembly and native unit checks pass. Authenticated Android gallery interaction and real camera/video playback remain unverified.
- Packed-consumer verification passes for the final local 0.1.5 archive: Preview includes the native module; production, unknown and missing environments exclude it. No registry publication.

Qpaws Preview's signed standalone Release build passed signature verification and includes the new native gallery, embedded JS and no dev launcher. Installed over the existing Preview app on the iPhone 15 Pro via Wi-Fi, preserving app data. Launch was denied because the phone was locked; unlock and open Preview to exercise it on hardware. The final archive also passes its host Activity explicitly into the Android gallery instead of casting a dialog's themed Context. Android Release and native unit checks pass after that change. Qpaws' frozen dependency install matches the final package source; no unrelated dependency changes, pushes or registry publication.

## Reporter-owned FAB exclusion (0.1.6)

The current visibility contract supersedes the earlier always-visible behavior. The host button hides before opening the reporter and stays absent throughout its own form, picker, gallery and alerts. It returns only after closing the reporter or returning to the host for screen recording. iOS uses the existing visibility/entrance animation; Android retains its host composition and restores it on the React Activity resume, without attaching extra FABs to reporter dialogs.

The updated iOS gallery regression passes all 25 steps with explicit FAB-hidden checks and a final host restoration check. The close/draft regression passes 59 executable steps, including the hidden button during discard/save alerts and restored button after closing. Android Release assembly/native unit checks pass, and `tests/e2e/fab-visibility-android.yaml` passes its 8-step hide/restore flow through the native sign-in sheet. Recording on physical hardware was not repeated. Final packed-consumer checks pass for Preview inclusion and production/missing/unknown exclusion.

Qpaws Preview update is local commit 71c1e9d6c. Its signed standalone Release build passed and was installed over Wi-Fi on the iPhone 15 Pro without uninstalling the app. The temporary EAS environment file was removed; no push or registry publication.
