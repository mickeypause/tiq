# Linear product icons

The SVG artwork in `ios/LinearIcons.xcassets` and the corresponding generated Android vector drawables originate from Linear’s public web client, retrieved on 2026-11-07. They are third-party artwork and are **not licensed under this package’s MIT license**. No redistribution license has been established; permission must be resolved before publishing this package with these assets.

Sources:
- https://static.linear.app/client/assets/startup-entry.ClW6uIWZ.js (icon identifiers)
- https://static.linear.app/client/assets/startup-root.C2vecms3.js (SVG symbols)

317 available named symbols are included. The client enum also contains `Cookie`, whose matching symbol was not present. Unknown names use a fallback. These are internal client assets, not a stable public API.

Regenerate Android vectors from the checked-in SVGs with `python3 scripts/generate-linear-icons.py`.

# Expo floating button

The native floating-button placement, appearance, gesture and animation code is adapted from `expo-dev-menu` 58.0.11 (Expo repository, `packages/expo-dev-menu/ios/FAB` and `android/src/debug/java/expo/modules/devmenu/fab`). Module integration, report actions, accessibility labels and persistent visibility are specific to Tiq.

Source: https://github.com/expo/expo/tree/main/packages/expo-dev-menu

The MIT License (MIT)

Copyright (c) 2015-present 650 Industries, Inc. (aka Expo)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
