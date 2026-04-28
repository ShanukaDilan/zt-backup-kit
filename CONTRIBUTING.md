# Contributing to zt-backup-kit

Thanks for your interest! This project welcomes contributions of all sizes.

## Quick guide

1. **Open an issue first** for non-trivial changes. We'll discuss approach
   before you write code.
2. **Fork the repo**, create a feature branch (`git checkout -b feature/my-thing`).
3. **Keep changes focused.** One PR = one logical change.
4. **Pass shellcheck.** `shellcheck bin/*.sh` should be clean.
5. **Test your changes.** At minimum, run `./bin/backup.sh --check` against
   your config and verify scripts still pass syntax checking with `bash -n`.
6. **Update docs** if you change behavior.
7. **Submit a pull request** with a clear description.

## What I'm interested in

High value:

- **Pull-mode setup** — scripts and docs for the SSH-pull architecture
- **Notification integrations** — Healthchecks.io, ntfy.sh, Slack webhooks
- **Native cloud backend examples** — B2, S3, Wasabi, Azure (without going through rclone)
- **Distro coverage** — testing on Fedora, Arch, Alpine, Rocky, etc.
- **Internationalization** — translating the runbook PDF / docs

Welcome but lower priority:

- Cosmetic changes to scripts (variable renames, formatting)
- New default exclude patterns (please justify with examples)

Probably won't accept:

- Switching the backup engine away from Restic
- Adding GUIs (this is intentionally a CLI/cron tool)
- Cryptocurrency-related anything

## Code style

- Bash, not zsh, not POSIX-only sh
- `set -u` is required at the top of every script
- Use functions for repeated logic; inline is fine for one-off blocks
- Prefer `[[ ... ]]` over `[ ... ]`
- Comment *why*, not *what*
- Keep functions under ~50 lines where reasonable
- Use lowercase for local variables, UPPERCASE for config-sourced ones

## Testing

For now testing is manual:

```bash
# Syntax check
for f in bin/*.sh scripts/*.sh; do bash -n "$f" || exit 1; done

# shellcheck (install with apt/brew)
shellcheck bin/*.sh scripts/*.sh

# Functional check (uses a temp local repo)
./tests/test-roundtrip.sh
```

Automated CI (GitHub Actions) runs shellcheck on every PR.

## Reporting bugs

Use the issue template. Include:

- Your OS and version (`uname -a; cat /etc/os-release`)
- Restic and rclone versions (`restic version; rclone version`)
- The relevant excerpt from `~/.zt-backup-kit/logs/`
- A redacted copy of your `config.sh` if config-related

**Never paste real credentials, OAuth tokens, or restic passwords.**

## Code of conduct

Be kind. Disagree on technical merits, not on people. Maintainers reserve
the right to remove comments, commits, or contributors that don't.

## License

By contributing, you agree your contributions are licensed under the MIT
license that covers the project.
