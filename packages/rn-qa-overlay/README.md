# Tiq — @mickeypause/tiq

A native in-app QA reporter for internal Expo builds. A floating button opens a SwiftUI composer on iOS and a Material 3 Expressive composer on Android. Testers sign into Linear on their device, add evidence, and create an issue.

There is no React component, provider, or runtime JavaScript import. Expo Go is unsupported; a new native build is required.

## Install

Until this version is published to a registry, install the supplied npm tarball:

```sh
bun add /path/to/mickeypause-tiq-0.1.6.tgz
# npm install /path/to/mickeypause-tiq-0.1.6.tgz also works
```

The package is local-only and has `private: true` to block registry publication. No registry login or token is required. Bun is used to develop/build this package; consuming the tarball does not require Bun.

For a portable project (including EAS), copy the archive into your app’s `vendor/` directory, then run `bun add ./vendor/mickeypause-tiq-0.1.6.tgz`. Include that file in the build upload and commit the dependency and lockfile. Repack and reinstall after changing library sources; tarball installs do not update live.

Supported host: Expo SDK 58, React Native 0.88, Node.js 24+, iOS 16.4+, Android API 24+. Android uses Material 3 `1.5.0-rc01` for its Expressive APIs. Other Expo versions have not been validated.

## Configure

Keep the plugin in your app config in **every environment**:

```ts
// app.config.ts
import type { ExpoConfig } from 'expo/config';
import type { QaOverlayOptions } from '@mickeypause/tiq';

const reporter = {
  allowedEnvironments: ['preview', 'development'],
  teamName: 'Product',
  linear: {
    clientId: process.env.LINEAR_CLIENT_ID!, // public OAuth Client ID
    redirectUri: 'com.yourcompany.yourapp.qa://linear/callback',
    // teamId: 'optional-default-team-id',
  },
} satisfies QaOverlayOptions;

export default {
  name: 'Your App',
  slug: 'your-app',
  plugins: [['@mickeypause/tiq', reporter]],
} satisfies ExpoConfig;
```

Create a Linear OAuth application and register that exact redirect URI. Use a dedicated reverse-domain callback scheme for your app. Supply only its public Client ID; no client secret or API token belongs in app config. OAuth PKCE and secure credential storage run on-device. Each tester signs into their own account. Omit `linear` if you only want to inspect the composer/setup screen before configuring sign-in.

Build with an explicitly approved `APP_ENV`:

```sh
APP_ENV=preview bunx expo prebuild --clean
APP_ENV=preview bunx expo run:ios --configuration Release
# or: APP_ENV=preview bunx expo run:android --variant release
```

Set `APP_ENV=preview` in an internal EAS build profile as well. Debug/release mode does not control whether the reporter is included. No code imports are needed in your app.

## Production exclusion

Production, missing `APP_ENV`, and values absent from your explicit allowlist exclude the native module. Production remains excluded even if accidentally allowlisted. The plugin removes its own public Expo manifest entry in excluded builds.

**Do not omit the plugin in production:** installed Expo modules autolink independently of config plugins. This plugin adds the native autolinking exclusion. Always regenerate native projects cleanly after changing environments; reusing native projects generated for preview can retain the module. Use Expo CNG/EAS clean generation. An OTA update cannot add or remove this native library. Unsupported native templates fail instead of silently omitting the exclusion.

## Reporter behavior

- Native form sheet, automatic light/dark appearance, scalable typography, and automatic title focus.
- Team/status selection with bundled Linear icons, a scrollable capture toolbar, and native Discard/Save draft alerts for nonempty reports. Empty reports close immediately; swipe dismissal is disabled.
- Gallery, photo, camera video and screen recording; images/videos open in a full-screen, horizontally paged gallery with Back and a Remove menu. Sharp rounded form previews have circular remove buttons.
- Private uploads become Markdown links in the issue description. Confirmed creation shows a brief nonblocking banner/snackbar with the issue identifier.
- Failed or uncertain submissions preserve the report and reuse a client-generated issue UUID to avoid duplicate retries. Discard is unavailable while a submission still needs confirmation.

Drafts and recovery state are **process-local**: Save draft survives closing the sheet, not terminating the app. Media currently appends after description text; rich Markdown editing and cursor-position media insertion are not implemented. Attachments must be non-empty and smaller than 100 MB; recordings stop after 60 seconds. Camera video and iOS screen recording require hardware validation. This iOS Simulator implementation reports unsupported ReplayKit export instead of claiming it captured a video. Screen recording does not capture microphone audio.

Android keyboard/preview/confirmation acceptance testing is incomplete because the development emulators encountered ANRs and package-service failures. Release compilation and native unit checks passed; do not equate those checks with complete device validation.

## License

Package source code is MIT licensed. The bundled Linear icon artwork is excluded from that license. See [LICENSE](./LICENSE) and [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md). Redistribution permission for those icons remains unresolved before public publication.

The floating button follows Expo dev-menu styling and drag/snap behavior, remembers its edge position, and hides while the reporter and its previews are open, then returns in the host app.
