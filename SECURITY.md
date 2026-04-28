# Security Policy

## Reporting a vulnerability

If you believe you've found a security issue in zt-backup-kit, **please do not
open a public GitHub issue**. Instead, contact the maintainer directly:

- Open a [private security advisory](https://github.com/ShanukaDilan/zt-backup-kit/security/advisories/new) on GitHub, or
- Email the maintainer (see GitHub profile)

Please include:

- A description of the issue and its impact
- Steps to reproduce, ideally with a minimal example
- Affected versions / commits if known
- Whether you're willing to be credited in the fix

I aim to acknowledge reports within 5 business days and to coordinate a
disclosure timeline that gives users time to update.

## Scope

Things that are in scope:

- Vulnerabilities in the scripts in `bin/` and `scripts/`
- Logic errors that could cause data loss or credential exposure
- Documentation that recommends insecure practices

Things that are **not** in scope (report upstream instead):

- Vulnerabilities in `restic` itself → https://github.com/restic/restic
- Vulnerabilities in `rclone` itself → https://github.com/rclone/rclone
- Issues in dependencies installed by your OS package manager

## Security model

This kit does not invent new cryptography. All confidentiality guarantees
are inherited from Restic (AES-256 with Poly1305 MAC). The script's job is
to ensure those guarantees aren't undermined by configuration mistakes.

Specifically the kit assumes:

- The restic password file (`.restic-pass`) is mode `400` and stored on a
  filesystem only the running user can read
- The rclone config (which contains OAuth refresh tokens) is mode `600` and
  similarly restricted
- Cron runs the script as a low-privilege user, not root, where possible
- The encrypted credentials archive (`*.tar.gz.gpg`) is not stored in the
  same location as the keys to decrypt it

If your threat model is stricter than the above (e.g. you need defense
against a compromised cron user, or you require HSM-backed keys), this kit
in its current form is probably not enough — see the Pull-mode roadmap or
consider commercial DR products.

## Known caveats

- **Default rclone OAuth quota** is shared across the entire rclone user
  base. Heavy usage can hit Google's per-project rate limits. Solution:
  create your own Google Cloud OAuth project (documented in
  `docs/INSTALL.md`).
- **Restore on a clean machine requires the credentials archive AND its
  passphrase**. Losing both is unrecoverable. The runbook discusses this
  explicitly.
