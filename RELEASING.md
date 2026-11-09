# Releasing Tiq

## Current publication restriction

The package remains `private: true`. Its bundled Linear icons have no established
redistribution permission; see
[THIRD_PARTY_NOTICES.md](packages/rn-qa-overlay/THIRD_PARTY_NOTICES.md).
Resolve permission or replace those assets before publishing a package or making
a release containing them public. Do not remove the publishing guard as part of
an ordinary version bump. The workflow below creates a **draft**, not a public
release, and never publishes to npm.

## Prepare a version

1. Open a PR updating `packages/rn-qa-overlay/package.json` to a new semantic
   version. Update versioned install examples when needed. Use a new version for
   every release; never move an existing release tag.
2. Run `bun run check` and `bun run verify:package`. For native behavior changes,
   run the applicable native tests/device checks documented in the README.
3. Merge through the required CI check. From GitHub Actions, run **Draft release**
   on `main`, or use `gh workflow run release.yml --ref main`.

The workflow rechecks the exact main commit, verifies the packed consumer, then
creates a draft named `v<package version>` with generated PR-based release notes,
the verified tarball, and SHA-256 checksums. It uses the repository's built-in
token; no registry credential is needed. An existing release with the same tag
causes creation to fail rather than replacing its assets.

## Publish after clearance

Review the draft's notes, target commit, checksums, and licensing. Keep it a draft
until redistribution is cleared. When approved, publish the draft; GitHub creates
its versioned tag at the verified target commit. Mark prerelease versions as
prereleases before publishing. Registry publication requires a separate reviewed
change to the package guard and publishing configuration.
