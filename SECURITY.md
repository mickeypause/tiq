# Security policy

Tiq is pre-1.0. Security fixes target the latest source on `main`; older snapshots
do not have a separate maintenance branch.

## Report a vulnerability privately

Use [GitHub's private vulnerability report form](https://github.com/mickeypause/tiq/security/advisories/new).
Do not open a public issue or PR containing an unpatched exploit or credentials.
Include affected versions, impact, reproduction steps, and a minimal proof of
concept using synthetic data. Never submit real OAuth tokens, private Linear
issues, recordings, or personal information.

Maintainers will coordinate investigation, fixes, and disclosure through the
private advisory. There is no guaranteed response time or bug bounty.

If credentials were exposed, revoke or rotate them immediately. Removing them
from a commit does not invalidate copies or credentials already obtained.
