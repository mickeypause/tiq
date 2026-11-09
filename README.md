# Tiq

See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), and
[Releasing](RELEASING.md) for checks, private vulnerability reporting, and the
verified draft release process.

A native QA reporter for internal Expo builds. The library renders its own SwiftUI (iOS) and Jetpack Compose (Android) interface, without a React component, runtime JavaScript import, or provider in the host app. Expo Go is unsupported.

Includes the floating entry button, native title/description composer, in-memory draft, attachment preview/removal, gallery, photo, camera video and public-API screen recording. Phase two adds on-device Linear OAuth PKCE, team/workflow selection, private media uploads and issue creation. Configure your OAuth application to enable reporting.

The iOS interface uses system SwiftUI controls and Liquid Glass on iOS 26+, with native material on older versions. Android uses Material 3 Expressive, dynamic system colors where available, and the native floating toolbar/FAB. Both follow the device appearance and font scaling. The composer keeps Linear-style borderless title/description fields: a bold 24-point/scalable title and regular body description. Close immediately dismisses an empty report; reports with text or attachments show a native Discard/Save draft alert. The composer cannot be swiped away and focuses the title when opened.

Team and workflow selectors display bundled Linear vector icons in menus and selected controls, with the icon/color metadata fetched from Linear. Unknown team icon identifiers fall back to the Team symbol; unknown workflow types fall back to Todo. Emoji identifiers currently use that team fallback. The 317 third-party icons have separate [source and licensing notices](packages/rn-qa-overlay/THIRD_PARTY_NOTICES.md); they are not covered by this repository’s MIT license. No icon downloads occur at runtime. The selected status shows its icon and name in the shared capture toolbar; swipe the row horizontally to reach actions that do not fit.

Android currently requires Material 3 `1.5.0-rc01` for its public Expressive theme and toolbar APIs.

## Package distribution

```sh
bun run pack             # artifacts/npm/mickeypause-tiq-0.1.6.tgz; builds JS and declarations first
bun run verify:package   # installs that tarball in an independent temporary Expo project
```

Install the tarball in another app with `bun add /absolute/path/to/mickeypause-tiq-0.1.6.tgz` (or `npm install` with the same path). No build step is needed in the consuming app beyond its normal native Expo build. The archive includes the config plugin, TypeScript options, native sources, vector assets, podspec and standalone [package setup guide](packages/rn-qa-overlay/README.md). Native build output, tests, the example app and local environment files are excluded.

The package is named `@mickeypause/tiq`, using the authenticated GitHub username as its scope. It is local-only with `private: true`, which blocks registry publication while allowing tarball installation. No registry token is required. Registry publication and icon redistribution permission still need to be resolved separately. Code licensing and the excluded third-party artwork are described in the package license/notice.

To try it in another app without any registry setup:

```sh
bun add /Users/serhiifozykosh/Developer/project/rn-qa-overlay/artifacts/npm/mickeypause-tiq-0.1.6.tgz
```

Add `@mickeypause/tiq` to `plugins` in your Expo app config using the [package setup guide](packages/rn-qa-overlay/README.md), then make a clean native build with `APP_ENV=preview`. Expo Go cannot load it. For EAS or a portable checkout, copy the tarball into the consuming app’s `vendor/` folder and install from that relative path. Repack and reinstall after source changes. The example already uses the scoped package via the workspace; run `bun run ios` or `bun run android` from this repository to try it there.

## Workspace

```text
packages/rn-qa-overlay/  Expo module, SwiftUI, Compose, TypeScript config plugin
example/                Expo SDK 58 / React Native 0.88 host app
scripts/                Native generation and exclusion checks
docs/                   Architecture, environment and validation notes
```

## Run the example

Requires Bun 1.3+, Node 24+, Xcode/CocoaPods for iOS, or JDK 17+ and an Android SDK for Android.

```sh
bun install
bun run check
bun run ios
# or
bun run android
```

The example scripts generate native projects cleanly, then build **release mode** with `APP_ENV=preview`. The resulting app is standalone and does not need Metro. For JS iteration, use `bun run --cwd example ios:debug` or `android:debug`; Metro uses port 8097. Use your own chosen simulator/emulator through Expo CLI's device options. `example/ios` and `example/android` are generated and ignored.

## Host configuration

Install the package and keep its plugin configured in **every environment**:

```ts
// app.config.ts — build-time configuration only
export default {
  name: 'Your app',
  slug: 'your-app',
  plugins: [
    ['@mickeypause/tiq', {
      allowedEnvironments: ['preview', 'development'],
      teamName: 'Product',
      linear: {
        clientId: process.env.LINEAR_CLIENT_ID, // public OAuth application ID
        redirectUri: 'com.yourcompany.yourapp.qa://linear/callback',
        // teamId: 'optional-default-team-uuid',
      },
    }],
  ],
};
```

Set `APP_ENV` in the build environment. Exact matches on the explicit allowlist enable the reporter in either debug or release builds. Production is always excluded, even if mistakenly allowlisted. Missing and unknown values are excluded too.

The plugin is build-time tooling, not app runtime code. In excluded environments it tells CocoaPods and Gradle's Expo autolinker to exclude the native module, adds no reporter configuration/permissions, and removes its own entry from the public Expo manifest. **Omitting the plugin is not supported**: installed native modules autolink independently of plugins. Native templates outside SDK 58 require verification; unsupported exclusion templates fail prebuild.

Always regenerate native projects with `expo prebuild --clean` after changing environments. Do not reuse native projects generated for an approved environment for a production build. The supplied scripts and EAS profiles use CNG; do not commit generated native directories. Native availability cannot be changed by an OTA JS update.

## Linear setup

1. Create an OAuth application in your Linear workspace's API settings. Use a dedicated reverse-domain callback scheme, for example `dev.rnqaoverlay.example.qa://linear/callback` for this example, and register that exact URI in Linear. Callback registration with a real OAuth application still needs live validation; do not substitute an HTTP URL into this plugin.
2. Supply the **public Client ID** through `linear.clientId`. No client secret or personal API key is used or accepted. The example reads `LINEAR_CLIENT_ID`, optional `LINEAR_REDIRECT_URI` (defaults to the example callback above), and optional `LINEAR_TEAM_ID` at prebuild time. These public values can be set in your approved EAS profile or local build environment.
3. Regenerate the native projects cleanly and rebuild. OAuth callback handlers are native build configuration, so an OTA update cannot add them.
4. Open Report bug. The first configured opening starts system-browser sign-in; cancellation leaves a Sign in button. Each tester grants `read,write` access and creates tickets as themselves. If config is absent, a connection/setup screen appears and submission stays disabled.
5. Choose a team and workflow state, enter a title and optional description/evidence, and submit. Triage is selected when available, otherwise Backlog or the first workflow state. `teamId` supplies the initial team; the menu can change it.

OAuth uses S256 PKCE and an exact callback/state check. iOS stores rotating tokens in Keychain and uses `ASWebAuthenticationSession`; Android uses the system browser and encrypts tokens/temporary PKCE material with an Android Keystore key in no-backup storage. Native HTTP clients exchange and refresh tokens directly with Linear. No application server is required by this implementation. See [Linear's PKCE documentation](https://linear.app/developers/oauth-2-0-authentication).

Submission first requests an authenticated upload URL, streams each original file to storage, then embeds the returned private `uploads.linear.app` URL in the issue's Markdown description. OAuth bearer tokens are sent only to Linear's API, never to upload storage. Images/videos are currently appended after the text, in attachment order. Cursor-position insertion and a rich Markdown editor remain separate work.

A confirmed issue receipt shows a brief nonblocking confirmation with the ticket identifier: a native-material banner on iOS and a Material snackbar on Android. The composer stays open, without a Done/Open dialog. A confirmed submission clears the draft and owned cache files; explicit Discard also clears them. Upload/request failures preserve the draft. An uncertain create retains the same client-generated issue UUID; Check submission looks it up before retrying. Edit report lets you revise a failed report while retaining that UUID, so the next attempt still checks for the earlier issue. Drafts, uploaded-URL caching and submission recovery survive closing the sheet **only while the app process remains alive**. Do not assume offline queuing or process-restored drafts. Uploaded assets can remain unused after an abandoned report.

Sign out on this device removes local credentials; it does not revoke the workspace grant. Revoke the app from Linear settings when needed.

```sh
bun run test:linear:ios     # macOS Swift core tests with mocked HTTP, no account needed
bun run test:linear:android # after Android prebuild; callback/form validation on the JVM
```

## Check exclusion

```sh
bun run verify:exclusion
```

Generates separate native projects for preview, production, missing and unknown environments under ignored `artifacts/exclusion/`. Checks the actual Podfile/Gradle exclusion instructions, iOS camera/microphone usage descriptions, native enablement metadata, Linear callback/Client ID exclusion and public Expo config. This generation check is not by itself a binary audit; see `docs/validation.md` for builds and device checks actually performed.

## Reporter presentation

The reporter opens as a native modal form sheet on iOS and a Material 3 modal sheet on Android. The title gains focus automatically when the editor is ready. Swipe dismissal is disabled. Close immediately dismisses an empty report; whitespace-only title/description values are empty. Reports with text or attachments show a native alert with Discard (clear the report and owned attachments) and Save draft (retain it for reopening). Saved drafts remain process-local; they are not written to disk. Discard is unavailable while a ticket submission still needs confirmation.

## Attachment previews

Tap an attachment to open a full-screen, title-free gallery at that asset. Swipe horizontally through all images and videos; Back restores the composer and its prior input focus. The More menu removes the current asset and closes the gallery when none remain. iOS 18+ keeps the native zoom entrance transition; Reduce Motion and older iOS use standard presentation. Form previews use sharp 1024-pixel thumbnails with circular remove controls. Gallery image decoding is bounded to 4096 pixels; original files remain untouched until removal.

## Capture behavior

- Gallery uses system pickers. Originals are copied into reporter-owned cache files and are never modified or deleted.
- Photo and camera video are separate actions. iOS simulator camera is unavailable; use hardware for those checks. Android delegates these actions to an installed camera app.
- Screen recording uses ReplayKit on physical iPhones and MediaProjection with a foreground service on Android. The tested iOS Simulator returned successful callbacks without exporting a movie, so Simulator builds show an explicit hardware-testing message. System consent applies. Tap the floating Stop recording control to return to the draft. Recordings stop after 60 seconds; attachments are limited to 100 MB. Screen recording does not request microphone audio; camera-video audio follows the system camera flow.
- Drafts survive closing/reopening the composer while the process remains alive. They do not survive process termination. Attachments are temporary cache files. Review evidence before submission.
- The library uses native keyboard insets. `react-native-keyboard-controller` is unnecessary with the native-only UI.

## EAS

`example/eas.json` contains internal development/preview profiles and an excluded production profile. Set up your own EAS project/signing with `bunx eas-cli init` from `example/` before a cloud build. No EAS project, Apple team, cloud build, or credentials are created by this repository.

## References

This is a local, unpublished workspace. The podspec derives its distribution URL from npm package metadata; normal Expo autolinking consumes the installed local source. Add your repository metadata when a repository is available.

Startup and build integration were informed by [expo-dev-menu](https://github.com/expo/expo/tree/main/packages/expo-dev-menu). Recording lifecycle was informed by [Squircle](https://github.com/achimala/Squircle). No private rendering APIs or dependency on either reference project are used.
