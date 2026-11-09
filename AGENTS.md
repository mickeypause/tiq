# rn-qa-overlay

Open-source workflows: `.github/workflows/ci.yml` runs the required `checks` job
on PRs and main, including standalone package verification on macOS. Keep its job
name stable because the main ruleset requires it. `CONTRIBUTING.md`, `SECURITY.md`,
and `RELEASING.md` own contributor, disclosure, and release procedures. The manual
release workflow runs only on main and creates verified drafts; preserve the
private package guard until third-party redistribution permission is resolved.

Use Bun. Run `bun run check` after TypeScript/plugin changes. Use `bun run verify:exclusion` after inclusion or permission changes.

The reporter is native SwiftUI/Compose. The Expo example is the host, with no reporter runtime imports. Expo Go is unsupported. Phase two adds native Linear OAuth PKCE, secure token storage and API submission. Never bundle credentials or client secrets.

Always run the config plugin at build time, including excluded environments. APP_ENV uses an explicit allowlist; production, missing and unknown values exclude the module. Build type is independent. Regenerate native projects cleanly when changing environments. Never substitute runtime hiding for native exclusion.

See docs/project-environment.json for workspace and build context. Use Argent for device interaction. No runtime keyboard-controller dependency: both composers use native keyboard insets.

Composer behavior: focus the title automatically once editable when opening the composer; preserve the prior field when returning from an attachment preview. Disable interactive sheet dismissal. Close empty/whitespace-only reports directly; text or attachments require a native alert with only Discard and Save draft. Keep existing unconfirmed-submission discard guards.

Floating entry button: keep Expo dev-menu appearance, timed label/idle fade, momentum edge snapping and persisted position. Hide it while the reporter or any of its pickers, alerts and previews are open. Restore it on return to the host app, including the Stop control while screen recording. Its window must pass through touches outside the button. Native ports are attributed in THIRD_PARTY_NOTICES.md.

Attachment galleries open full-screen, start at the tapped asset, page horizontally across all images/videos, and have Back plus a Remove menu with no visible title. Keep keyboard focus suspended until Back. Form previews use larger rounded, sharp thumbnails and an overlaid circular remove button with a 44-point touch target.
