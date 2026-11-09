# Contributing to Tiq

Open an issue for bugs or substantial changes before starting a large PR. Include
the Expo/React Native versions, OS/device, reproduction steps, and expected versus
actual behavior. Remove private report content and credentials from evidence.
Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Setup and checks

Use Bun 1.3.11 and Node 24+. Fork and clone the repository, then run:

```sh
bun install --frozen-lockfile
bun run check
bun run verify:package
```

`check` builds the plugin, lints, checks types, and runs the portable tests.
`verify:package` builds the tarball, installs it into an independent Expo project,
and checks native discovery and environment inclusion/exclusion. Run package
verification on macOS because it generates both iOS and Android projects.
Neither command requires Linear credentials.

For example-app and native test prerequisites, see [README.md](README.md).
Changes to native Swift/Compose behavior also need the relevant native tests and
a device check; CI does not build or interact with the native app. Inclusion or
permission changes additionally require `bun run verify:exclusion`.

## Pull requests

Work on a feature branch and open a PR targeting `main`. Keep changes focused,
describe their user-visible effect, and include the checks performed. Update
documentation when behavior or setup changes. The required `checks` CI job must
pass, and review conversations must be resolved before merging. Direct pushes,
force pushes, and deletion of `main` are blocked, including for administrators.

Never commit tokens, signing material, generated native projects, or local build
output. Keep the config plugin enabled in every environment so production
exclusion remains effective. Preserve third-party notices; the bundled Linear
artwork is not covered by the MIT license.

## Releases

Maintainers follow [RELEASING.md](RELEASING.md). Package registry publication is
deliberately disabled until the existing redistribution restrictions are resolved.
